#Requires -Version 5.1
<#
    Install-Dodo.ps1 - Installation / mise a jour du couvre-feu sur un poste Windows.

    A lancer EN ADMINISTRATEUR, depuis le dossier dodo\src :
        powershell -ExecutionPolicy Bypass -File .\Install-Dodo.ps1

    Par defaut l'installation se fait en MODE SIMULATION (dryRun) : rien ne
    s'eteint, tout est journalise. Passez -Production quand les essais sont
    concluants.

    Options :
        -Production                    bascule en extinction reelle
        -ExemptUsers 'Papa','Maman'    comptes devant lesquels on n'eteint pas
        -NotifyUser 'Malo'             restreint l'agent d'alerte a ce compte
                                       (par defaut : tout membre du groupe Utilisateurs)
        -AllowedSsid 'Livebox-1234'    n'autorise le Wi-Fi que sur ces SSID
        -EnableAdapterGuard            desactive toute carte reseau non recensee
                                       maintenant (bloque le partage de connexion USB)
        -ResetConfig                   ecrase la configuration existante
#>
[CmdletBinding()]
param(
    [string]$InstallPath = (Join-Path $env:ProgramData 'Dodo'),
    [string]$AnswerFile,
    [switch]$Production,
    [string[]]$ExemptUsers,
    [string]$NotifyUser,
    [string[]]$AllowedSsid,
    [switch]$EnableAdapterGuard,
    [string[]]$AllowedAdapterName,
    [switch]$SkipCalendar,
    [switch]$ResetConfig
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Fiche de reponses.
#
# powershell.exe -File NE REINTERPRETE PAS les quotes PowerShell : les
# arguments qui suivent le script sont decoupes sur les espaces par le
# runtime C. "-AllowedAdapterName 'Ethernet 2','Wi-Fi'" devenait donc deux
# jetons, et le second ("2','Wi-Fi'") se liait au premier parametre
# POSITIONNEL, c'est-a-dire -InstallPath. De meme "-NotifyUser 'Malo'"
# arrivait avec ses apostrophes, d'ou l'echec de resolution du compte.
#
# Aucun tableau ni aucune valeur a espaces ne passe donc plus par la ligne
# de commande : l'appelant depose un JSON, on le relit ici.
# --------------------------------------------------------------------------
$ScheduleFromAnswer = $null
$HolidaysFromAnswer = $null
$OfflineFromAnswer  = $null

if ($AnswerFile) {
    if (-not (Test-Path -LiteralPath $AnswerFile)) { throw "Fiche de reponses introuvable : $AnswerFile" }
    $ans = ([System.IO.File]::ReadAllText($AnswerFile, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)

    if ($ans.PSObject.Properties['InstallPath'] -and $ans.InstallPath) { $InstallPath = [string]$ans.InstallPath }
    if ($ans.PSObject.Properties['NotifyUser']  -and $ans.NotifyUser)  { $NotifyUser  = [string]$ans.NotifyUser }
    if ($ans.PSObject.Properties['Production']         -and [bool]$ans.Production)         { $Production = $true }
    if ($ans.PSObject.Properties['EnableAdapterGuard'] -and [bool]$ans.EnableAdapterGuard) { $EnableAdapterGuard = $true }
    if ($ans.PSObject.Properties['SkipCalendar']       -and [bool]$ans.SkipCalendar)       { $SkipCalendar = $true }
    if ($ans.PSObject.Properties['ResetConfig']        -and [bool]$ans.ResetConfig)        { $ResetConfig = $true }

    # ExemptUsers s'applique meme vide : c'est ainsi qu'on vide la liste.
    if ($ans.PSObject.Properties['ExemptUsers']) {
        $ExemptUsers = [string[]]@($ans.ExemptUsers)
        $PSBoundParameters['ExemptUsers'] = $ExemptUsers
    }
    # Ces deux-la, en revanche, ne s'appliquent que non vides : une liste vide
    # de SSID poserait un denyall sans aucune autorisation, coupant tout le Wi-Fi.
    if ($ans.PSObject.Properties['AllowedSsid'] -and @($ans.AllowedSsid).Count -gt 0) {
        $AllowedSsid = [string[]]@($ans.AllowedSsid)
        $PSBoundParameters['AllowedSsid'] = $AllowedSsid
    }
    if ($ans.PSObject.Properties['AllowedAdapterName'] -and @($ans.AllowedAdapterName).Count -gt 0) {
        $AllowedAdapterName = [string[]]@($ans.AllowedAdapterName)
        $PSBoundParameters['AllowedAdapterName'] = $AllowedAdapterName
    }

    # Horaires et periodes de vacances saisis dans l'assistant.
    if ($ans.PSObject.Properties['Schedule']    -and $ans.Schedule)    { $ScheduleFromAnswer = $ans.Schedule }
    if ($ans.PSObject.Properties['Holidays'])                          { $HolidaysFromAnswer = @($ans.Holidays) }
    if ($ans.PSObject.Properties['OfflineOnly'])                       { $OfflineFromAnswer  = [bool]$ans.OfflineOnly }
}

# Garde-fou : un chemin relatif ou porteur de quotes est le symptome d'un
# debordement de parametre. Mieux vaut refuser bruyamment qu'installer ailleurs.
if (-not [System.IO.Path]::IsPathRooted($InstallPath) -or $InstallPath -match '[''"|<>*?]') {
    throw ("Chemin d'installation invalide : '{0}'. Un chemin absolu est attendu, par exemple C:\ProgramData\Dodo." -f $InstallPath)
}
if ($NotifyUser -and $NotifyUser -match '[''"]') {
    throw ("Nom de compte invalide : {0}. Les apostrophes et guillemets ne sont pas acceptes." -f $NotifyUser)
}

. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')

$Step = 0
function Step { param([string]$T) $script:Step++; Write-Host ''; Write-Host ("[{0}] {1}" -f $script:Step, $T) -ForegroundColor Cyan }
function Ok   { param([string]$T) Write-Host "    OK   $T" -ForegroundColor Green }
function Warn { param([string]$T) Write-Host "    !    $T" -ForegroundColor Yellow }
function Info { param([string]$T) Write-Host "         $T" -ForegroundColor DarkGray }

Write-Host ''
Write-Host '  DODO - installation du couvre-feu' -ForegroundColor White
Write-Host '  ---------------------------------' -ForegroundColor DarkGray

# --------------------------------------------------------------------------
Step 'Verifications prealables'

if ($env:OS -ne 'Windows_NT') { throw 'Ce script ne fonctionne que sous Windows.' }
$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Droits administrateur requis. Relancez PowerShell via 'Executer en tant qu'administrateur'."
}
Ok "Administrateur : $($id.Identity.Name)"
Ok "Windows PowerShell $($PSVersionTable.PSVersion)"
if ($PSVersionTable.PSVersion.Major -lt 5) { throw 'Windows PowerShell 5.1 minimum.' }

$os = Get-CimInstance Win32_OperatingSystem
Ok "$($os.Caption) $($os.Version)"

# Le dispositif ne vaut que si l'enfant n'est PAS administrateur : on le montre.
Write-Host ''
Info 'Membres du groupe Administrateurs local (ces comptes peuvent tout desactiver) :'
$admins = @()
try   { $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object -ExpandProperty Name) }
catch { $admins = @((& net.exe localgroup administrators) | Where-Object { $_ -match '^\S' } | Select-Object -Skip 4) }
foreach ($a in $admins) { if ($a -and $a -notmatch '^(La commande|The command)') { Write-Host "           - $a" -ForegroundColor Yellow } }
Warn "Si le compte de l'enfant figure ci-dessus, RETIREZ-L'EN avant d'aller plus loin :"
Info "  Get-LocalGroupMember -SID 'S-1-5-32-544'"
Info "  Remove-LocalGroupMember -SID 'S-1-5-32-544' -Member '<compte>'"

# --------------------------------------------------------------------------
Step "Arborescence dans $InstallPath"

if ($InstallPath -match '\s') { Warn "Le chemin contient un espace : les taches planifiees le gerent, mais un chemin sans espace reste preferable." }
$paths = Get-DodoPaths -Root $InstallPath
foreach ($d in @($paths.Root, $paths.Bin, $paths.Etc, $paths.Var, $paths.Logs, $paths.Media)) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}
Ok 'Dossiers bin, etc, var, logs, media crees'

$sourceFiles = @('DodoCore.ps1', 'DodoRuntime.ps1', 'Invoke-DodoEnforce.ps1', 'Show-DodoWarning.ps1',
                 'Get-DodoStatus.ps1', 'Add-DodoException.ps1', 'Uninstall-Dodo.ps1', 'run-notify-hidden.vbs')
foreach ($f in $sourceFiles) {
    $src = Join-Path $PSScriptRoot $f
    if (-not (Test-Path -LiteralPath $src)) { throw "Fichier source manquant : $src" }
    Copy-Item -LiteralPath $src -Destination (Join-Path $paths.Bin $f) -Force
}
Ok "$($sourceFiles.Count) fichiers copies dans bin\"

# --------------------------------------------------------------------------
Step 'Configuration'

$existing = $null
if ((Test-Path -LiteralPath $paths.Config) -and -not $ResetConfig) {
    $existing = Read-DodoJson -Path $paths.Config
    Ok 'Configuration existante conservee (utilisez -ResetConfig pour repartir du modele)'
}
if ($null -eq $existing) {
    $existing = Read-DodoJson -Path (Join-Path $PSScriptRoot 'dodo.config.json')
    Ok 'Configuration initialisee depuis le modele'
}

function Set-Prop { param($O, [string]$N, $V) $O | Add-Member -NotePropertyName $N -NotePropertyValue $V -Force }

Set-Prop $existing 'dryRun' (-not $Production)
if ($PSBoundParameters.ContainsKey('ExemptUsers')) { Set-Prop $existing 'exemptUsers' @($ExemptUsers) }

if ($PSBoundParameters.ContainsKey('AllowedSsid')) {
    $w = Get-DodoProp $existing 'wifi'
    if ($null -eq $w) { $w = [pscustomobject]@{}; Set-Prop $existing 'wifi' $w }
    Set-Prop $w 'enforceSsidFilter' $true
    Set-Prop $w 'allowedSsids' @($AllowedSsid)
}
if ($EnableAdapterGuard) {
    $ids  = @()
    $vues = @()
    try { $vues = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne 'Disabled' }) }
    catch { Warn "Get-NetAdapter indisponible : $($_.Exception.Message)" }

    # Sans liste explicite, on ecarte d'office les cartes de partage
    # (Bluetooth PAN, RNDIS) : ce sont precisement les voies de partage de
    # connexion qu'on cherche a bloquer, les autoriser viderait la mesure.
    $exclus = 'Bluetooth|Personal Area|RNDIS|Remote NDIS|Tethering|iPhone|Android'
    foreach ($a in $vues) {
        $retenue = $false
        if ($PSBoundParameters.ContainsKey('AllowedAdapterName')) {
            $retenue = (@($AllowedAdapterName) -contains $a.Name)
        }
        elseif ($a.Name -notmatch $exclus -and $a.InterfaceDescription -notmatch $exclus) {
            $retenue = $true
        }
        if ($retenue) { $ids += $a.PnPDeviceID; Info "  AUTORISEE : $($a.Name) - $($a.InterfaceDescription)" }
        else          { Warn "  BLOQUEE   : $($a.Name) - $($a.InterfaceDescription)" }
    }

    $g = Get-DodoProp $existing 'adapterGuard'
    if ($null -eq $g) { $g = [pscustomobject]@{}; Set-Prop $existing 'adapterGuard' $g }
    Set-Prop $g 'enabled' $true
    Set-Prop $g 'allowedPnpDeviceIds' $ids
    if ($ids.Count -eq 0) {
        Warn 'Aucune carte retenue : le garde-cartes desactiverait TOUT le reseau. Il reste actif mais sans effet tant que la liste est vide.'
    }
    else { Ok "$($ids.Count) carte(s) reseau sur liste blanche" }
}

# --- Horaires saisis a la main
if ($null -ne $ScheduleFromAnswer) {
    $sc = Get-DodoProp $existing 'schedule'
    if ($null -eq $sc) { $sc = [pscustomobject]@{}; Set-Prop $existing 'schedule' $sc }
    foreach ($k in @('school', 'holiday')) {
        $src = Get-DodoProp $ScheduleFromAnswer $k
        if ($null -eq $src) { continue }
        $dst = Get-DodoProp $sc $k
        if ($null -eq $dst) { $dst = [pscustomobject]@{}; Set-Prop $sc $k $dst }
        foreach ($ff in @('start', 'end')) {
            $vv = Get-DodoProp $src $ff
            if ($vv) { Set-Prop $dst $ff ([string]$vv) }
        }
    }
    Ok ("Horaires appliques : scolaire {0}->{1}, vacances {2}->{3}" -f $sc.school.start, $sc.school.end, $sc.holiday.start, $sc.holiday.end)
}

# --- Periodes de vacances saisies a la main
if ($null -ne $HolidaysFromAnswer -or $null -ne $OfflineFromAnswer) {
    $calNode = Get-DodoProp $existing 'calendar'
    if ($null -eq $calNode) { $calNode = [pscustomobject]@{}; Set-Prop $existing 'calendar' $calNode }
    if ($null -ne $HolidaysFromAnswer) {
        Set-Prop $calNode 'overrides' @($HolidaysFromAnswer)
        Ok ("{0} periode(s) de vacances saisie(s) a la main" -f @($HolidaysFromAnswer).Count)
        foreach ($h in @($HolidaysFromAnswer)) {
            Info ("  {0} : du {1} au {2} inclus" -f (Get-DodoProp $h 'label' '?'), (Get-DodoProp $h 'start' '?'),
                  ([datetime]::ParseExact([string](Get-DodoProp $h 'endExclusive'), 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture).AddDays(-1).ToString('yyyy-MM-dd')))
        }
    }
    if ($null -ne $OfflineFromAnswer) {
        Set-Prop $calNode 'offlineOnly' $OfflineFromAnswer
        if ($OfflineFromAnswer) { Ok 'Mode hors ligne : aucune connexion au calendrier officiel, les periodes saisies font foi' }
    }
}

# Validation AVANT ecriture : une configuration invalide n'est jamais deployee.
$validated = Resolve-DodoConfig $existing
Write-DodoJson -Path $paths.Config -Object $existing
Ok "Configuration validee et ecrite : $($paths.Config)"
Info ("Mode : " + $(if ($validated.dryRun) { 'SIMULATION (aucune extinction reelle)' } else { 'PRODUCTION (extinction reelle)' }))
Info ("Scolaire {0}->{1}   Vacances {2}->{3}   {4}" -f $validated.schedule.school.start, $validated.schedule.school.end, $validated.schedule.holiday.start, $validated.schedule.holiday.end, $validated.zone)

if (-not (Test-Path -LiteralPath $paths.Messages)) {
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'dodo.messages.json') -Destination $paths.Messages -Force
    Ok 'Messages parles installes (dodo.messages.json)'
}
else { Ok 'Messages parles existants conserves' }

# --------------------------------------------------------------------------
Step 'Verrouillage des droits (l enfant ne doit pas pouvoir modifier)'

# SID bien connus : insensible a la langue du systeme.
#   S-1-5-18     SYSTEM               controle total
#   S-1-5-32-544 Administrateurs      controle total
#   S-1-5-32-545 Utilisateurs         lecture / execution seulement
#
# ORDRE IMPORTANT : les droits explicites sont poses AVANT de couper
# l'heritage. Dans l'autre sens, la racine se retrouve un instant sans
# aucune ACE, le processus perd son droit de parcours, et icacls echoue
# aussitot en "Acces refuse" sur les sous-dossiers.
$grant = @('*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-32-545:(OI)(CI)RX')
$o1 = & icacls.exe $paths.Root /grant:r @grant /T /C 2>&1
if ($LASTEXITCODE -ne 0) { Warn "icacls /grant a signale un probleme : $($o1 -join ' ')" }

# Heritage coupe sur la RACINE uniquement : les sous-dossiers heritent
# desormais des ACE explicites ci-dessus. Avec /T ils perdraient tout.
$o2 = & icacls.exe $paths.Root /inheritance:r /C 2>&1
if ($LASTEXITCODE -ne 0) { Warn "icacls /inheritance a signale un probleme : $($o2 -join ' ')" }

# Verification effective plutot que declarative
$usersSid = New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-545')
$writable = @()
foreach ($d in @($paths.Bin, $paths.Etc, $paths.Var, $paths.Logs)) {
    try {
        foreach ($ace in (Get-Acl -LiteralPath $d).Access) {
            if ($ace.AccessControlType -ne 'Allow') { continue }
            $sid = $null
            try { $sid = $ace.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]) } catch { }
            if ($null -eq $sid -or $sid -ne $usersSid) { continue }
            if (($ace.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Write) -ne 0 -or
                ($ace.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::Modify) -ne 0) {
                $writable += (Split-Path -Leaf $d)
            }
        }
    }
    catch { Warn "ACL de $d illisible : $($_.Exception.Message)" }
}
if ($writable.Count -eq 0) {
    Ok 'Heritage coupe ; SYSTEM et Administrateurs en controle total, Utilisateurs en lecture seule'
}
else {
    Warn ('Le groupe Utilisateurs peut encore ecrire dans : ' + (($writable | Select-Object -Unique) -join ', '))
}
foreach ($l in @(& icacls.exe $paths.Root 2>&1)) { if ($l -match 'S-1-|:\(') { Info $l.Trim() } }

# --------------------------------------------------------------------------
Step 'Source de journal Windows'
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists('Dodo')) {
        New-EventLog -LogName 'Application' -Source 'Dodo' -ErrorAction Stop
        Ok "Source 'Dodo' creee dans le journal Application"
    }
    else { Ok "Source 'Dodo' deja presente" }
}
catch { Warn "Source de journal non creee (non bloquant) : $($_.Exception.Message)" }

# --------------------------------------------------------------------------
Step 'Calendrier scolaire'
if ($SkipCalendar) { Warn 'Ignore (-SkipCalendar) : tant que le cache est vide, la regle scolaire 21:00 s applique.' }
else {
    try {
        $r = Update-DodoCalendarCache -Config $validated -Root $InstallPath
        if ($r.Success) {
            Ok $r.Message
            foreach ($w in @($r.Warnings)) { Warn "Calendrier : $w" }
        }
        else { Warn $r.Message }
    }
    catch {
        Warn "Recuperation impossible : $($_.Exception.Message)"
        Info 'Sans calendrier, la regle scolaire (21:00) s applique en permanence : le poste reste protege.'
    }
}

# --------------------------------------------------------------------------
Step 'Taches planifiees'

$psExe    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
if (-not (Test-Path -LiteralPath $psExe)) { $psExe = 'powershell.exe' }
$enforce  = Join-Path $paths.Bin 'Invoke-DodoEnforce.ps1'
$vbs      = Join-Path $paths.Bin 'run-notify-hidden.vbs'
$taskPath = '\Dodo\'

function New-DodoMinuteTrigger {
    <#
        Declencheur repete toutes les minutes, sans fin.

        AUCUN -RepetitionDuration : la valeur "indefiniment" obtenue depuis
        [TimeSpan]::MaxValue est serialisee en P99999999DT23H59M59S, que le
        planificateur de Windows 11 refuse ("valeur incorrectement formatee ou
        hors limites", HRESULT 0x80041318). Une repetition sans duree se repete
        indefiniment : c'est exactement l'intention. La duree est en plus videe
        de force, au cas ou la version installee la renseignerait d'elle-meme.
    #>
    $t = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Minutes 1)
    try {
        if ($null -ne $t.Repetition) {
            $t.Repetition.Duration = ''
            $t.Repetition.StopAtDurationEnd = $false
        }
    }
    catch { }
    return $t
}

function Test-DodoTaskExists {
    param([string]$Name)
    try { $null = Get-ScheduledTask -TaskPath $taskPath -TaskName $Name -ErrorAction Stop; return $true }
    catch { return $false }
}

function Get-DodoTaskRepetition {
    param([string]$Name)
    try {
        $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $Name -ErrorAction Stop
        foreach ($tr in @($t.Triggers)) {
            try { if ($tr.Repetition.Interval) { return [string]$tr.Repetition.Interval } } catch { }
        }
    }
    catch { }
    return ''
}

function Repair-DodoRepetition {
    <# Relit la tache et force la repetition d'une minute si elle n'a pas pris. #>
    param([string]$Name)
    try {
        $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $Name -ErrorAction Stop
        $changed = $false
        foreach ($tr in @($t.Triggers)) {
            if ($tr.CimClass.CimClassName -notlike '*TimeTrigger*') { continue }
            if ($null -eq $tr.Repetition) { continue }
            try {
                if ($tr.Repetition.Interval -ne 'PT1M') { $tr.Repetition.Interval = 'PT1M'; $changed = $true }
                if ($tr.Repetition.Duration)            { $tr.Repetition.Duration = ''    ; $changed = $true }
                if ($tr.Repetition.StopAtDurationEnd)   { $tr.Repetition.StopAtDurationEnd = $false; $changed = $true }
            }
            catch { }
        }
        if ($changed) { Set-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null }
    }
    catch { }
}

function Register-DodoRepeatingTask {
    <#
        Enregistre une tache repetee chaque minute, en essayant plusieurs formes
        jusqu'a ce qu'une repetition d'une minute soit REELLEMENT en place.

        Chaque tentative est verifiee par relecture : on ne se fie pas a
        l'absence d'exception, c'est precisement ce qui avait laisse passer le
        declencheur a duree hors limites.
    #>
    param(
        [string]$Name, $Action, $Principal, $Settings,
        [object[]]$ExtraTriggers = @(), [string]$Description,
        [string]$SchtasksCommand
    )
    $notes = New-Object System.Collections.Generic.List[string]

    # 1. Forme normale : declencheur repete (+ declencheurs supplementaires)
    try {
        $trig = @((New-DodoMinuteTrigger)) + @($ExtraTriggers)
        Register-ScheduledTask -TaskName $Name -TaskPath $taskPath -Force -Action $Action `
            -Principal $Principal -Settings $Settings -Trigger $trig -Description $Description -ErrorAction Stop | Out-Null
        if ((Get-DodoTaskRepetition -Name $Name) -eq 'PT1M') { return 'declencheur repete' }
        $notes.Add('repetition absente apres enregistrement')
    }
    catch { $notes.Add("forme normale refusee : $($_.Exception.Message)") }

    # 2. Enregistrement sans repetition, puis ajout par Set-ScheduledTask
    try {
        $trig = @((New-ScheduledTaskTrigger -Once -At (Get-Date).Date)) + @($ExtraTriggers)
        Register-ScheduledTask -TaskName $Name -TaskPath $taskPath -Force -Action $Action `
            -Principal $Principal -Settings $Settings -Trigger $trig -Description $Description -ErrorAction Stop | Out-Null
        Repair-DodoRepetition -Name $Name
        if ((Get-DodoTaskRepetition -Name $Name) -eq 'PT1M') { return 'enregistrement en deux temps' }
        $notes.Add('repetition refusee par Set-ScheduledTask')
    }
    catch { $notes.Add("forme simple refusee : $($_.Exception.Message)") }

    # 3. Repli schtasks.exe : /SC MINUTE ne passe par aucun XML de duree.
    #    Reserve au compte SYSTEM, qui ne demande pas de mot de passe.
    if ($SchtasksCommand) {
        try {
            $full = ($taskPath.TrimEnd('') + '' + $Name).TrimStart('')
            $out = & schtasks.exe /Create /TN $full /SC MINUTE /MO 1 /RU 'SYSTEM' /RL 'HIGHEST' /TR $SchtasksCommand /F 2>&1
            if ($LASTEXITCODE -eq 0 -and (Test-DodoTaskExists -Name $Name)) {
                try { Set-ScheduledTask -TaskPath $taskPath -TaskName $Name -Settings $Settings -ErrorAction Stop | Out-Null } catch { }
                return 'schtasks.exe'
            }
            $notes.Add("schtasks a renvoye $LASTEXITCODE : $($out -join ' ')")
        }
        catch { $notes.Add("schtasks refuse : $($_.Exception.Message)") }
    }

    throw ("aucune forme d'enregistrement n'a abouti. Tentatives : " + ($notes.ToArray() -join ' | '))
}

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

$psArgs     = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $enforce
$actEnforce = New-ScheduledTaskAction -Execute $psExe -Argument $psArgs

$prinSystem = $null
foreach ($u in @('SYSTEM', 'NT AUTHORITY\SYSTEM')) {
    try { $prinSystem = New-ScheduledTaskPrincipal -UserId $u -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop; break } catch { }
}
if ($null -eq $prinSystem) { throw "Impossible de construire le principal SYSTEM pour la tache planifiee." }

# --- Tache 1 : application de la regle, compte SYSTEM, toutes les minutes
$voie = Register-DodoRepeatingTask -Name 'Dodo-Enforce' -Action $actEnforce -Principal $prinSystem `
    -Settings $settings -Description 'Couvre-feu Dodo : applique la fenetre d extinction (compte SYSTEM).' `
    -SchtasksCommand ('"{0}" {1}' -f $psExe, $psArgs)
Ok "Dodo-Enforce enregistree (SYSTEM, toutes les minutes) - voie : $voie"

# --- Tache 2 : rattrapage au demarrage. Tache separee, sans repetition : elle
#     ne depend donc d'aucun assemblage de declencheurs multiples.
try {
    Register-ScheduledTask -TaskName 'Dodo-Boot' -TaskPath $taskPath -Force `
        -Action $actEnforce -Principal $prinSystem -Settings $settings `
        -Trigger (New-ScheduledTaskTrigger -AtStartup) `
        -Description 'Couvre-feu Dodo : reapplique la regle au demarrage du poste.' -ErrorAction Stop | Out-Null
    Ok 'Dodo-Boot enregistree (SYSTEM, au demarrage du poste)'
}
catch {
    Warn "Dodo-Boot non enregistree : $($_.Exception.Message)"
    Info "La repetition d'une minute de Dodo-Enforce couvre deja le cas, avec au plus une minute de retard."
}

# --- Tache 3 : alerte, session de l'utilisateur, sans privilege
$actNotify = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') -Argument ('"{0}"' -f $vbs)
$prinUser  = $null
$principalLabel = ''
if ($NotifyUser) {
    $prinUser = New-ScheduledTaskPrincipal -UserId $NotifyUser -LogonType Interactive -RunLevel Limited
    $principalLabel = "compte $NotifyUser"
}
else {
    foreach ($g in @('S-1-5-32-545', 'BUILTIN\Users', 'Users')) {
        try { $prinUser = New-ScheduledTaskPrincipal -GroupId $g -RunLevel Limited -ErrorAction Stop; $principalLabel = "groupe $g"; break } catch { }
    }
}
if ($null -eq $prinUser) {
    Warn "Principal de groupe refuse : repli sur le compte courant ($($id.Identity.Name))."
    $prinUser = New-ScheduledTaskPrincipal -UserId $id.Identity.Name -LogonType Interactive -RunLevel Limited
    $principalLabel = "compte $($id.Identity.Name)"
}

try {
    $voieN = Register-DodoRepeatingTask -Name 'Dodo-Notify' -Action $actNotify -Principal $prinUser `
        -Settings $settings -ExtraTriggers @((New-ScheduledTaskTrigger -AtLogOn)) `
        -Description 'Couvre-feu Dodo : preavis sonore et fenetre d alerte dans la session utilisateur.'
    Ok "Dodo-Notify enregistree ($principalLabel, toutes les minutes + a l ouverture de session) - voie : $voieN"
}
catch {
    Warn "Dodo-Notify : $($_.Exception.Message)"
    Warn "Les preavis sonores ne seront pas diffuses. L'extinction, elle, reste assuree par Dodo-Enforce."
}

# --------------------------------------------------------------------------
Step 'Reseau (facultatif)'

if ($PSBoundParameters.ContainsKey('AllowedSsid')) {
    $hasWifi = $false
    try { $hasWifi = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' }).Count -gt 0 } catch { }

    foreach ($s in $AllowedSsid) {
        if ($s -match '[''"]') { throw "SSID invalide : $s. Les apostrophes et guillemets ne sont pas acceptes." }
        if ([string]::IsNullOrWhiteSpace($s)) { throw 'SSID vide : refus.' }
    }

    if (-not $hasWifi) {
        Warn 'Aucune carte Wi-Fi detectee : filtre SSID non applique (normal sur un poste fixe Ethernet).'
    }
    elseif ($validated.dryRun) {
        # Un filtre Wi-Fi mal renseigne rend TOUS les reseaux invisibles. En
        # mode simulation on annonce ce qui serait applique, on n'applique rien :
        # "rien ne change" doit valoir pour le reseau comme pour l'extinction.
        Warn 'Mode SIMULATION : le filtre Wi-Fi n est PAS applique.'
        Info ("Il le sera a la mise en service, avec pour seuls SSID autorises : " + ($AllowedSsid -join ', '))
    }
    else {
        & netsh.exe wlan delete filter permission=denyall networktype=infrastructure 2>&1 | Out-Null
        $poses = 0
        foreach ($s in $AllowedSsid) {
            $out = & netsh.exe wlan add filter permission=allow ssid="$s" networktype=infrastructure 2>&1
            if ($LASTEXITCODE -eq 0) { $poses++; Info "allow '$s' : accepte" }
            else { Warn "allow '$s' refuse : $($out -join ' ')" }
        }
        if ($poses -eq 0) {
            # Sans aucune autorisation acceptee, poser denyall couperait tout
            # le Wi-Fi du poste. On s'abstient plutot que d'isoler la machine.
            Warn 'Aucun SSID autorise n a pu etre pose : denyall NON applique, le Wi-Fi reste libre.'
        }
        else {
            $out = & netsh.exe wlan add filter permission=denyall networktype=infrastructure 2>&1
            if ($LASTEXITCODE -eq 0) { Ok "Filtre Wi-Fi applique : $poses SSID autorise(s), tout le reste bloque" }
            else { Warn "denyall refuse : $($out -join ' ')" }
        }
        foreach ($l in @(& netsh.exe wlan show filters 2>&1)) { if ($l -match '\S') { Info $l.Trim() } }
        Info 'En cas de souci : netsh wlan delete filter permission=denyall networktype=infrastructure'
    }
}
else { Info 'Filtre Wi-Fi non demande (-AllowedSsid).' }

if ($EnableAdapterGuard) { Ok 'Garde-cartes reseau actif : toute nouvelle carte (partage USB, Bluetooth) sera desactivee.' }
else { Info 'Garde-cartes reseau non demande (-EnableAdapterGuard).' }

# --------------------------------------------------------------------------
Step 'Verification finale'

$allGood = $true
foreach ($n in @('Dodo-Enforce', 'Dodo-Boot', 'Dodo-Notify')) {
    try {
        $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $n -ErrorAction Stop
        $rep = '(aucune)'
        foreach ($tr in @($t.Triggers)) { try { if ($tr.Repetition.Interval) { $rep = $tr.Repetition.Interval; break } } catch { } }
        if ($t.State -eq 'Disabled') { Warn "$n est DESACTIVEE"; $allGood = $false }
        elseif ($n -eq 'Dodo-Boot')  { Ok "$n : etat=$($t.State) declencheur=au demarrage" }
        elseif ($rep -ne 'PT1M')     { Warn "$n : repetition = $rep (attendu PT1M) - le test bout-en-bout le confirmera"; $allGood = $false }
        else                          { Ok "$n : etat=$($t.State) repetition=$rep principal=$($t.Principal.UserId)$($t.Principal.GroupId)" }
        foreach ($ac in @($t.Actions)) {
            $arg = [string]$ac.Arguments
            if ($arg -and $arg -notmatch [regex]::Escape($paths.Bin)) {
                Warn "$n pointe hors de l'installation : $arg"
                $allGood = $false
            }
        }
    }
    catch { if ($n -eq 'Dodo-Boot') { Warn "$n absente (non bloquant)" } else { Warn "$n introuvable"; $allGood = $false } }
}

try {
    Start-ScheduledTask -TaskPath $taskPath -TaskName 'Dodo-Enforce' -ErrorAction Stop
    Start-Sleep -Seconds 4
    $info = Get-ScheduledTaskInfo -TaskPath $taskPath -TaskName 'Dodo-Enforce'
    if ($info.LastTaskResult -eq 0) { Ok "Execution d essai reussie (code 0, $($info.LastRunTime))" }
    else { Warn "Execution d essai : code $($info.LastTaskResult) - voir $($paths.Logs)"; $allGood = $false }
}
catch { Warn "Execution d essai impossible : $($_.Exception.Message)"; $allGood = $false }

Write-Host ''
if ($allGood) { Write-Host '  Installation terminee.' -ForegroundColor Green }
else          { Write-Host '  Installation terminee AVEC DES RESERVES (voir les lignes en jaune).' -ForegroundColor Yellow }

Write-Host ''
Write-Host '  Suite :' -ForegroundColor White
Write-Host ("    1. Etat complet      : powershell -ExecutionPolicy Bypass -File `"{0}\Get-DodoStatus.ps1`"" -f $paths.Bin) -ForegroundColor Gray
Write-Host ("    2. Test bout-en-bout : powershell -ExecutionPolicy Bypass -File `".\Test-DodoE2E.ps1`"") -ForegroundColor Gray
Write-Host ("    3. Voix disponibles  : powershell -ExecutionPolicy Bypass -File `"{0}\Show-DodoWarning.ps1`" -ListVoices" -f $paths.Bin) -ForegroundColor Gray
if ($validated.dryRun) {
    Write-Host ''
    Write-Host '    Mode SIMULATION actif : aucune extinction reelle.' -ForegroundColor Yellow
    Write-Host '    Quand les essais sont concluants, relancez avec -Production.' -ForegroundColor Yellow
}
Write-Host ''
