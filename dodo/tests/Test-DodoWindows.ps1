#Requires -Version 5.1
<#
    Test-DodoWindows.ps1 - Installation REELLE sur une machine Windows jetable.

    Concu pour un runner GitHub Actions windows-latest, ou pour une machine
    virtuelle de test. Installe pour de vrai, verifie, puis desinstalle et
    verifie que la machine est revenue a son etat initial.

    NE PAS LANCER sur un poste en service : l'installation ecrase la
    configuration existante et la desinstallation supprime tout a la fin.

    C'est ce test qui couvre la couche que les 140 assertions hors ligne ne
    peuvent pas atteindre : ACL NTFS, planificateur de taches, passage
    d'arguments, netsh. Les trois defauts remontes du terrain (ordre icacls,
    duree de repetition hors limites, debordement de parametre) y echouent.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:ProgramData 'Dodo'),
    [switch]$SkipTaskWait
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$srcDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
. (Join-Path $srcDir 'DodoCore.ps1')
. (Join-Path $srcDir 'DodoRuntime.ps1')

$Pass = 0; $Fail = 0
$Failures = New-Object System.Collections.Generic.List[string]
function Sec { param($T) Write-Host ''; Write-Host ("=== $T " + ('=' * [math]::Max(0, 62 - $T.Length))) -ForegroundColor Cyan }
function Chk { param([bool]$C, [string]$L, [string]$D = '')
    if ($C) { $script:Pass++; Write-Host "  [OK]   $L" -ForegroundColor DarkGreen }
    else { $script:Fail++; $script:Failures.Add("$L $D"); Write-Host "  [FAIL] $L  $D" -ForegroundColor Red } }
function Note { param($T) Write-Host "         $T" -ForegroundColor DarkGray }

function Invoke-Ps {
    <#
        Lance un script dans un powershell.exe fils et rend code + sortie.
        Sans cette precaution, la moindre ligne ecrite sur la sortie d'erreur
        par un utilitaire natif (shutdown /a quand aucune extinction n'est en
        cours, par exemple) devient une erreur terminante chez l'appelant a
        cause de $ErrorActionPreference = 'Stop'.
    #>
    param([string]$Script, [string[]]$Arguments = @())
    $ancien = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $sortie = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Lignes = @($sortie | ForEach-Object { [string]$_ }) }
    }
    finally { $ErrorActionPreference = $ancien }
}

$paths = Get-DodoPaths -Root $Root

Write-Host ''
Write-Host '  DODO - recette d integration Windows' -ForegroundColor White
Write-Host ("  $env:COMPUTERNAME - " + (Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) -ForegroundColor DarkGray

# ==========================================================================
Sec 'PHASE 1 - Prealables'
Chk ($env:OS -eq 'Windows_NT') 'systeme Windows'
Chk ($PSVersionTable.PSVersion.Major -ge 5) "PowerShell $($PSVersionTable.PSVersion)"
$estAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Chk $estAdmin 'session administrateur'
if (-not $estAdmin) { Write-Host 'Interrompu : droits administrateur requis.' -ForegroundColor Red; exit 1 }

$cartes = @()
try { $cartes = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne 'Disabled' } | Select-Object -ExpandProperty Name) } catch { }
Note ("cartes reseau presentes : " + $(if ($cartes.Count) { $cartes -join ', ' } else { 'aucune' }))

# ==========================================================================
Sec 'PHASE 2 - Installation reelle (mode simulation)'

# La fiche de reponses reprend exactement la forme produite par l'assistant,
# avec des valeurs a espaces : c'est le cas qui avait deborde sur -InstallPath.
$fiche = Join-Path $env:TEMP 'dodo-recette-reponses.json'
$reponses = [pscustomobject]@{
    InstallPath        = $Root
    Production         = $false
    NotifyUser         = $env:USERNAME
    ExemptUsers        = @($env:USERNAME)
    EnableAdapterGuard = $true
    AllowedAdapterName = @($cartes)
    AllowedSsid        = @()
    OfflineOnly        = $false
    Schedule           = [pscustomobject]@{
        school  = [pscustomobject]@{ start = '21:00'; end = '06:30' }
        holiday = [pscustomobject]@{ start = '23:00'; end = '06:30' }
    }
    Holidays           = @(
        [pscustomobject]@{ label = 'Recette Toussaint'; start = '2026-10-17'; endExclusive = '2026-11-02' }
    )
}
[System.IO.File]::WriteAllText($fiche, ($reponses | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))

$installe = $false
try {
    $r = Invoke-Ps -Script (Join-Path $srcDir 'Install-Dodo.ps1') -Arguments @('-AnswerFile', $fiche)
    foreach ($l in $r.Lignes) { Note $l }
    Chk ($r.Code -eq 0 -or $null -eq $r.Code) "Install-Dodo.ps1 se termine sans erreur (code $($r.Code))"
    $installe = $true
}
catch { Chk $false 'Install-Dodo.ps1 se termine sans erreur' $_.Exception.Message }

try {
    # ======================================================================
    Sec 'PHASE 3 - Arborescence et configuration'
    # Un debordement de parametre ferait atterrir l'installation ailleurs :
    # cette seule verification aurait suffi a l'attraper.
    foreach ($d in @($paths.Root, $paths.Bin, $paths.Etc, $paths.Var, $paths.Logs)) {
        Chk (Test-Path -LiteralPath $d) "present : $d"
    }
    Chk (Test-Path -LiteralPath $paths.Config) 'configuration ecrite'
    $cfg = $null
    try { $cfg = Get-DodoConfiguration -Root $Root } catch { }
    Chk ($null -ne $cfg) 'configuration relue et valide'
    if ($null -ne $cfg) {
        Chk ($cfg.dryRun -eq $true)                     'mode simulation actif'
        Chk ($cfg.schedule.school.start -eq '21:00')    'horaire scolaire transmis par la fiche de reponses'
        Chk ($cfg.schedule.holiday.start -eq '23:00')   'horaire vacances transmis'
        Chk (@($cfg.exemptUsers) -contains $env:USERNAME) 'compte exempte transmis'
        Chk (@($cfg.calendar.overrides).Count -eq 1)    'periode de vacances manuelle transmise'
    }

    # ======================================================================
    Sec 'PHASE 4 - Droits NTFS'
    # Couvre l'ordre icacls : /inheritance:r avant /grant vidait la racine.
    # Bits d'ecriture elementaires uniquement : Modify est un masque composite
    # qui contient deja la lecture, un -band avec lui est toujours vrai.
    foreach ($d in @($paths.Bin, $paths.Etc, $paths.Var)) {
        $ecrivables = @()
        try { $ecrivables = @(Get-DodoUserWriteRights -Path $d) }
        catch { $ecrivables += "ACL illisible : $($_.Exception.Message)" }
        Chk ($ecrivables.Count -eq 0) "groupe Utilisateurs sans ecriture sur $(Split-Path -Leaf $d)" ([string]::Join(', ', @($ecrivables)))
        $sidU = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
        $lecture = @((Get-Acl -LiteralPath $d).Access | Where-Object {
            $x = $null; try { $x = $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) } catch { }
            $x -eq $sidU -and $_.AccessControlType -eq 'Allow' })
        Chk ($lecture.Count -gt 0) "groupe Utilisateurs en lecture sur $(Split-Path -Leaf $d)"
    }

    # ======================================================================
    Sec 'PHASE 5 - Taches planifiees'
    # Couvre la duree de repetition hors limites et le chemin d'action relatif.
    foreach ($n in @('Dodo-Enforce', 'Dodo-Boot', 'Dodo-Notify')) {
        $t = $null
        try { $t = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName $n -ErrorAction Stop } catch { }
        Chk ($null -ne $t) "$n enregistree"
        if ($null -eq $t) { continue }
        Chk ($t.State -ne 'Disabled') "$n active (etat $($t.State))"
        foreach ($ac in @($t.Actions)) {
            $arg = [string]$ac.Arguments
            Chk ($arg -like "*$($paths.Bin)*") "$n pointe dans l installation" $arg
        }
        if ($n -ne 'Dodo-Boot') {
            $rep = ''
            foreach ($tr in @($t.Triggers)) { try { if ($tr.Repetition.Interval) { $rep = [string]$tr.Repetition.Interval; break } } catch { } }
            Chk ($rep -eq 'PT1M') "$n : repetition d une minute effective" "obtenu '$rep'"
        }
    }
    $te = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName 'Dodo-Enforce' -ErrorAction SilentlyContinue
    if ($null -ne $te) {
        Chk ("$($te.Principal.UserId)" -match 'SYSTEM|S-1-5-18') "Dodo-Enforce s execute sous SYSTEM ($($te.Principal.UserId))"
    }

    # ======================================================================
    Sec 'PHASE 6 - Execution reelle des agents'
    $journal = Join-Path $paths.Logs ('dodo-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    $rE = Invoke-Ps -Script (Join-Path $paths.Bin 'Invoke-DodoEnforce.ps1')
    Chk ($rE.Code -eq 0) "Invoke-DodoEnforce.ps1 se termine en code 0 (obtenu $($rE.Code))" ($rE.Lignes -join ' ')
    # Hors fenetre d'extinction l'agent n'a rien a dire : le silence est le
    # comportement attendu, un journal vide n'est donc pas un defaut. Sa
    # presence est verifiee en phase 7, quand un evenement se produit.

    $rD = Invoke-Ps -Script (Join-Path $paths.Bin 'Show-DodoWarning.ps1') -Arguments @('-Diagnose')
    Chk ($rD.Code -eq 0) "Show-DodoWarning.ps1 -Diagnose se termine en code 0 (obtenu $($rD.Code))"
    foreach ($l in $rD.Lignes) { Note $l }
    Chk (@($rD.Lignes | Where-Object { $_ -match 'Racine resolue' }).Count -gt 0) 'le diagnostic restitue bien son etat'

    $rS = Invoke-Ps -Script (Join-Path $paths.Bin 'Get-DodoStatus.ps1') -Arguments @('-Nights', '3')
    Chk ($rS.Code -eq 0) "Get-DodoStatus.ps1 se termine en code 0 (obtenu $($rS.Code))"

    # ======================================================================
    Sec 'PHASE 7 - Soiree simulee via la fenetre d essai'
    $raw = Read-DodoJson -Path $paths.Config
    $depart = (Get-Date).AddMinutes(60)
    $raw | Add-Member -NotePropertyName 'testWindow' -NotePropertyValue ([pscustomobject]@{
        start = $depart.ToString('s'); end = $depart.AddMinutes(5).ToString('s'); label = 'recette windows' }) -Force
    Write-DodoJson -Path $paths.Config -Object $raw
    Write-DodoText -Path $paths.ClockOffset -Content '60'

    function Get-NouvellesLignes {
        param([int]$Depuis)
        $t = @(Get-Content -LiteralPath $journal -ErrorAction SilentlyContinue)
        if ($t.Count -le $Depuis) { return @() }
        return @($t[$Depuis..($t.Count - 1)])
    }

    # 7a. Le compte courant est dans exemptUsers et a une session ouverte :
    #     l'agent doit refuser d'eteindre. C'est le mecanisme d'exemption.
    if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
    $n0 = @(Get-Content -LiteralPath $journal -ErrorAction SilentlyContinue).Count
    Invoke-Ps -Script (Join-Path $paths.Bin 'Invoke-DodoEnforce.ps1') | Out-Null
    $l1 = Get-NouvellesLignes -Depuis $n0
    foreach ($l in $l1) { Note $l }
    Chk (@($l1 | Where-Object { $_ -match 'Extinction suspendue' }).Count -gt 0) 'compte exempte connecte : extinction refusee'

    # 7b. Sans compte exempte, la meme fenetre doit journaliser l'extinction.
    $raw2 = Read-DodoJson -Path $paths.Config
    $raw2 | Add-Member -NotePropertyName 'exemptUsers' -NotePropertyValue @() -Force
    Write-DodoJson -Path $paths.Config -Object $raw2
    if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
    $n1 = @(Get-Content -LiteralPath $journal -ErrorAction SilentlyContinue).Count
    Invoke-Ps -Script (Join-Path $paths.Bin 'Invoke-DodoEnforce.ps1') | Out-Null
    $l2 = Get-NouvellesLignes -Depuis $n1
    foreach ($l in $l2) { Note $l }
    Chk (@($l2 | Where-Object { $_ -match 'SIMULATION : extinction' }).Count -gt 0) 'extinction journalisee en simulation, sans extinction reelle'
    Chk (Test-Path -LiteralPath $journal) 'journal ecrit par l agent SYSTEM'

    Remove-Item -LiteralPath $paths.ClockOffset -Force -ErrorAction SilentlyContinue
    $raw3 = Read-DodoJson -Path $paths.Config
    if ($null -ne $raw3.PSObject.Properties['testWindow']) { $raw3.PSObject.Properties.Remove('testWindow'); Write-DodoJson -Path $paths.Config -Object $raw3 }

    # ======================================================================
    if (-not $SkipTaskWait) {
        Sec 'PHASE 8 - Declenchement spontane'
        $t0 = (Get-ScheduledTaskInfo -TaskPath '\Dodo\' -TaskName 'Dodo-Enforce').LastRunTime
        Note 'attente de 95 s...'
        Start-Sleep -Seconds 95
        $i1 = Get-ScheduledTaskInfo -TaskPath '\Dodo\' -TaskName 'Dodo-Enforce'
        Chk ($i1.LastRunTime -gt $t0) "Dodo-Enforce s est declenchee seule (avant $t0, apres $($i1.LastRunTime))"
        Chk ($i1.LastTaskResult -eq 0) "Dodo-Enforce se termine en code 0 (obtenu $($i1.LastTaskResult))"
    }
}
finally {
    # ======================================================================
    Sec 'PHASE 9 - Desinstallation et retour a l etat initial'
    if ($installe) {
        $rU = Invoke-Ps -Script (Join-Path $paths.Bin 'Uninstall-Dodo.ps1')
        foreach ($l in $rU.Lignes) { Note $l }
        Chk (@($rU.Lignes | Where-Object { $_ -match 'no shutdown was in progress|1116' }).Count -eq 0) 'la desinstallation ne remonte pas d erreur parasite de shutdown'
        $restantes = @()
        foreach ($n in @('Dodo-Enforce', 'Dodo-Boot', 'Dodo-Notify')) {
            try { $null = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName $n -ErrorAction Stop; $restantes += $n } catch { }
        }
        Chk ($restantes.Count -eq 0) 'toutes les taches sont retirees' ($restantes -join ', ')
        Chk (-not (Test-Path -LiteralPath $paths.Root)) 'dossier d installation supprime'
        $filtres = @(& netsh.exe wlan show filters 2>&1)
        Chk (@($filtres | Where-Object { $_ -match 'denyall|Refuser tout' }).Count -eq 0) 'aucun filtre Wi-Fi denyall residuel'
    }
    Remove-Item -LiteralPath $fiche -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ('-' * 72)
if ($Fail -eq 0) { Write-Host ("RECETTE WINDOWS : {0} controles OK, 0 echec." -f $Pass) -ForegroundColor Green; exit 0 }
Write-Host ("RECETTE WINDOWS : {0} OK, {1} ECHECS." -f $Pass, $Fail) -ForegroundColor Red
foreach ($f in $Failures) { Write-Host "  - $f" -ForegroundColor Red }
exit 1
