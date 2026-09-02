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
    [switch]$Production,
    [string[]]$ExemptUsers,
    [string]$NotifyUser,
    [string[]]$AllowedSsid,
    [switch]$EnableAdapterGuard,
    [switch]$SkipCalendar,
    [switch]$ResetConfig
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

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
    $ids = @()
    try { $ids = @(Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -ne 'Disabled' } | Select-Object -ExpandProperty PnPDeviceID) }
    catch { Warn "Get-NetAdapter indisponible : $($_.Exception.Message)" }
    $g = Get-DodoProp $existing 'adapterGuard'
    if ($null -eq $g) { $g = [pscustomobject]@{}; Set-Prop $existing 'adapterGuard' $g }
    Set-Prop $g 'enabled' $true
    Set-Prop $g 'allowedPnpDeviceIds' $ids
    Ok "$($ids.Count) carte(s) reseau presente(s) inscrite(s) sur liste blanche"
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue)) { Info "  $($a.Name) - $($a.InterfaceDescription)" }
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
    $at = (Get-Date).Date
    try { return (New-ScheduledTaskTrigger -Once -At $at -RepetitionInterval (New-TimeSpan -Minutes 1) -RepetitionDuration ([TimeSpan]::MaxValue)) } catch { }
    try { return (New-ScheduledTaskTrigger -Once -At $at -RepetitionInterval (New-TimeSpan -Minutes 1)) } catch { }
    return (New-ScheduledTaskTrigger -Once -At $at)
}

function Repair-DodoRepetition {
    <# Relit la tache et force la repetition d'une minute si elle n'a pas pris. #>
    param([string]$Name)
    try {
        $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $Name -ErrorAction Stop
        $changed = $false
        foreach ($tr in @($t.Triggers)) {
            if ($tr.CimClass.CimClassName -notlike '*TimeTrigger*') { continue }
            $cur = $null
            try { $cur = $tr.Repetition.Interval } catch { }
            if ($cur -ne 'PT1M') { $tr.Repetition.Interval = 'PT1M'; $tr.Repetition.Duration = $null; $changed = $true }
        }
        if ($changed) { Set-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null }
    }
    catch { Warn "Reglage de la repetition de $Name : $($_.Exception.Message)" }
}

$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)

# --- Tache 1 : application, compte SYSTEM, toutes les minutes + au demarrage
$actEnforce = New-ScheduledTaskAction -Execute $psExe `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}"' -f $enforce)
$prinSystem = $null
foreach ($u in @('SYSTEM', 'NT AUTHORITY\SYSTEM')) {
    try { $prinSystem = New-ScheduledTaskPrincipal -UserId $u -LogonType ServiceAccount -RunLevel Highest -ErrorAction Stop; break } catch { }
}
if ($null -eq $prinSystem) { throw "Impossible de construire le principal SYSTEM pour la tache planifiee." }

Register-ScheduledTask -TaskName 'Dodo-Enforce' -TaskPath $taskPath -Force `
    -Action $actEnforce -Principal $prinSystem -Settings $settings `
    -Trigger @((New-DodoMinuteTrigger), (New-ScheduledTaskTrigger -AtStartup)) `
    -Description 'Couvre-feu Dodo : applique la fenetre d extinction (compte SYSTEM).' | Out-Null
Repair-DodoRepetition -Name 'Dodo-Enforce'
Ok 'Dodo-Enforce enregistree (SYSTEM, toutes les minutes + au demarrage)'

# --- Tache 2 : alerte, session de l'utilisateur, sans privilege
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

Register-ScheduledTask -TaskName 'Dodo-Notify' -TaskPath $taskPath -Force `
    -Action $actNotify -Principal $prinUser -Settings $settings `
    -Trigger @((New-DodoMinuteTrigger), (New-ScheduledTaskTrigger -AtLogOn)) `
    -Description 'Couvre-feu Dodo : preavis sonore et fenetre d alerte dans la session utilisateur.' | Out-Null
Repair-DodoRepetition -Name 'Dodo-Notify'
Ok "Dodo-Notify enregistree ($principalLabel, toutes les minutes + a l ouverture de session)"

# --------------------------------------------------------------------------
Step 'Reseau (facultatif)'

if ($PSBoundParameters.ContainsKey('AllowedSsid')) {
    $hasWifi = $false
    try { $hasWifi = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { $_.InterfaceDescription -match 'Wi-?Fi|Wireless|802\.11' }).Count -gt 0 } catch { }
    if (-not $hasWifi) { Warn 'Aucune carte Wi-Fi detectee : filtre SSID non applique (normal sur un poste fixe Ethernet).' }
    else {
        & netsh.exe wlan delete filter permission=denyall networktype=infrastructure 2>&1 | Out-Null
        foreach ($s in $AllowedSsid) {
            $out = & netsh.exe wlan add filter permission=allow ssid="$s" networktype=infrastructure 2>&1
            Info "allow '$s' : $($out -join ' ')"
        }
        $out = & netsh.exe wlan add filter permission=denyall networktype=infrastructure 2>&1
        Info "denyall : $($out -join ' ')"
        Ok 'Filtre Wi-Fi applique : seuls les SSID autorises sont connectables'
        Info 'Verification : netsh wlan show filters'
    }
}
else { Info 'Filtre Wi-Fi non demande (-AllowedSsid).' }

if ($EnableAdapterGuard) { Ok 'Garde-cartes reseau actif : toute nouvelle carte (partage USB, Bluetooth) sera desactivee.' }
else { Info 'Garde-cartes reseau non demande (-EnableAdapterGuard).' }

# --------------------------------------------------------------------------
Step 'Verification finale'

$allGood = $true
foreach ($n in @('Dodo-Enforce', 'Dodo-Notify')) {
    try {
        $t = Get-ScheduledTask -TaskPath $taskPath -TaskName $n -ErrorAction Stop
        $rep = '(aucune)'
        foreach ($tr in @($t.Triggers)) { try { if ($tr.Repetition.Interval) { $rep = $tr.Repetition.Interval; break } } catch { } }
        if ($t.State -eq 'Disabled') { Warn "$n est DESACTIVEE"; $allGood = $false }
        elseif ($rep -ne 'PT1M')     { Warn "$n : repetition = $rep (attendu PT1M) - le test bout-en-bout le confirmera"; $allGood = $false }
        else                          { Ok "$n : etat=$($t.State) repetition=$rep principal=$($t.Principal.UserId)$($t.Principal.GroupId)" }
    }
    catch { Warn "$n introuvable"; $allGood = $false }
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
