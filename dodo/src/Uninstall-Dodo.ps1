#Requires -Version 5.1
<#
    Uninstall-Dodo.ps1 - Retrait complet du couvre-feu. A lancer EN ADMINISTRATEUR.

        powershell -ExecutionPolicy Bypass -File .\Uninstall-Dodo.ps1
        powershell -ExecutionPolicy Bypass -File .\Uninstall-Dodo.ps1 -KeepLogs
#>
[CmdletBinding()]
param([string]$Root, [switch]$KeepLogs, [switch]$KeepNetworkRules)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Droits administrateur requis.' -ForegroundColor Red; exit 1
}
$paths = Get-DodoPaths -Root $Root
function Ok { param($T) Write-Host "  OK  $T" -ForegroundColor Green }
function Warn { param($T) Write-Host "  !   $T" -ForegroundColor Yellow }

Write-Host ''; Write-Host '  DODO - desinstallation' -ForegroundColor White; Write-Host ''

# 1. Taches planifiees
foreach ($n in @('Dodo-Enforce', 'Dodo-Notify', 'Dodo-Boot')) {
    try { Unregister-ScheduledTask -TaskPath '\Dodo\' -TaskName $n -Confirm:$false -ErrorAction Stop; Ok "tache $n supprimee" }
    catch { }
}
try {
    $s = New-Object -ComObject 'Schedule.Service'; $s.Connect()
    $s.GetFolder('\').DeleteFolder('Dodo', 0); Ok 'dossier de taches \Dodo supprime'
}
catch { }

# 2. Extinction eventuellement engagee
try { Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/a') -NoNewWindow -Wait -ErrorAction SilentlyContinue | Out-Null } catch { }

# 3. Regles reseau
if (-not $KeepNetworkRules) {
    # INCONDITIONNEL : le filtre denyall rend tous les reseaux Wi-Fi invisibles.
    # Le retirer ne doit dependre ni de la lisibilite de la configuration, ni
    # de l'emplacement de l'installation. C'est le geste de secours.
    & netsh.exe wlan delete filter permission=denyall networktype=infrastructure 2>&1 | Out-Null
    & netsh.exe wlan delete filter permission=denyall networktype=adhoc 2>&1 | Out-Null
    Ok 'filtre Wi-Fi denyall retire : tous les reseaux redeviennent visibles'

    # Puis les autorisations nominatives, si la configuration est lisible.
    try {
        $cfg = Get-DodoConfiguration -Root $Root
        foreach ($s in @($cfg.wifi.allowedSsids)) {
            & netsh.exe wlan delete filter permission=allow ssid="$s" networktype=infrastructure 2>&1 | Out-Null
        }
    }
    catch { Warn "configuration illisible, filtres nominatifs non retires : $($_.Exception.Message)" }

    Write-Host '  Filtres restants :' -ForegroundColor DarkGray
    foreach ($l in @(& netsh.exe wlan show filters 2>&1)) { if ($l -match '\S') { Write-Host "      $l" -ForegroundColor DarkGray } }

    # Cartes reseau : reactivation inconditionnelle elle aussi.
    foreach ($a in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Disabled' })) {
        try { Enable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop; Ok "carte reactivee : $($a.Name)" } catch { }
    }
}
else { Warn 'regles reseau conservees (-KeepNetworkRules)' }

# 4. Journal Windows
try { if ([System.Diagnostics.EventLog]::SourceExists('Dodo')) { Remove-EventLog -Source 'Dodo' -ErrorAction Stop; Ok "source de journal 'Dodo' retiree" } } catch { }

# 5. Marqueurs dans les profils utilisateurs
try {
    foreach ($p in @(Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction Stop)) {
        $d = Join-Path $p.FullName 'AppData\Local\Dodo'
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue; Ok "marqueurs retires : $($p.Name)" }
    }
}
catch { }

# 6. Fichiers
if (Test-Path -LiteralPath $paths.Root) {
    if ($KeepLogs) {
        $keep = Join-Path $env:ProgramData ('Dodo-logs-' + (Get-Date).ToString('yyyyMMdd-HHmmss'))
        try { Copy-Item -LiteralPath $paths.Logs -Destination $keep -Recurse -Force; Ok "journaux conserves dans $keep" } catch { Warn "copie des journaux : $($_.Exception.Message)" }
    }
    & icacls.exe $paths.Root /reset /T /C 2>&1 | Out-Null
    try { Remove-Item -LiteralPath $paths.Root -Recurse -Force -ErrorAction Stop; Ok "dossier $($paths.Root) supprime" }
    catch { Warn "suppression du dossier : $($_.Exception.Message) - supprimez-le a la main apres redemarrage." }
}

Write-Host ''; Write-Host '  Desinstallation terminee.' -ForegroundColor Green
Write-Host '  Verification : Get-ScheduledTask -TaskPath \Dodo\   (doit ne rien renvoyer)' -ForegroundColor DarkGray
Write-Host ''
