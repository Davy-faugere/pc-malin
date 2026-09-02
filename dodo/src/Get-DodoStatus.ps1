#Requires -Version 5.1
<#
    Get-DodoStatus.ps1 - Etat complet du couvre-feu, sans rien modifier.

    C'est l'outil de controle a lancer apres installation, apres une mise a jour
    de calendrier, ou quand un doute apparait. Aucun effet de bord (sauf -Refresh
    qui rafraichit le cache calendrier).

        powershell -ExecutionPolicy Bypass -File Get-DodoStatus.ps1
        powershell -ExecutionPolicy Bypass -File Get-DodoStatus.ps1 -Refresh -Nights 21
#>
[CmdletBinding()]
param(
    [string]$Root,
    [switch]$Refresh,
    [int]$Nights = 14
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')

$isWindows5 = ($env:OS -eq 'Windows_NT')
$paths = Get-DodoPaths -Root $Root
$cfg   = Get-DodoConfiguration -Root $Root
$now   = Get-DodoNow -Config $cfg -Root $Root

function Head { param([string]$T) Write-Host ''; Write-Host "-- $T " -NoNewline -ForegroundColor Cyan; Write-Host ('-' * [math]::Max(0, 66 - $T.Length)) -ForegroundColor DarkCyan }
function Kv   { param([string]$K, $V, [string]$Color = 'Gray') Write-Host ('   {0,-26}: ' -f $K) -NoNewline; Write-Host $V -ForegroundColor $Color }

Write-Host ''
Write-Host ' DODO - etat du couvre-feu' -ForegroundColor White
Write-Host (' {0}' -f (Get-Date).ToString('dddd dd MMMM yyyy HH:mm:ss')) -ForegroundColor DarkGray

Head 'Installation'
Kv 'Racine'      $paths.Root
Kv 'Poste'       $env:COMPUTERNAME
Kv 'PowerShell'  $PSVersionTable.PSVersion
Kv 'Actif'       $(if ($cfg.enabled) { 'oui' } else { 'NON (enabled = false)' }) $(if ($cfg.enabled) { 'Green' } else { 'Yellow' })
Kv 'Mode'        $(if ($cfg.dryRun) { 'SIMULATION (dryRun = true) - aucune extinction reelle' } else { 'PRODUCTION - extinction reelle' }) $(if ($cfg.dryRun) { 'Yellow' } else { 'Green' })
if ($cfg.dryRun) {
    $off = Read-DodoText -Path $paths.ClockOffset
    if (-not [string]::IsNullOrWhiteSpace($off)) {
        Kv 'Decalage horloge test' ("{0} min -> heure simulee {1}" -f $off.Trim(), $now.ToString('dd/MM HH:mm:ss')) 'Yellow'
    }
}

Head 'Regles horaires'
Kv 'Periode scolaire'  ("{0} -> {1}" -f $cfg.schedule.school.start,  $cfg.schedule.school.end)
Kv 'Vacances scolaires' ("{0} -> {1}   ({2})" -f $cfg.schedule.holiday.start, $cfg.schedule.holiday.end, $cfg.zone)
Kv 'Preavis (minutes)' (($cfg.warningMinutes | Sort-Object -Descending) -join ', ')
Kv 'Delai d extinction' ("{0} s" -f $cfg.shutdownGraceSeconds)
Kv 'Veille de rentree'  $(if ($cfg.strictNightBeforeReturn) { 'regle scolaire (stricte)' } else { 'regle vacances' })
if (@($cfg.lateEveningsDuringTerm).Count -gt 0) { Kv 'Soirs tolerants' (@($cfg.lateEveningsDuringTerm) -join ', ') }
if (@($cfg.exemptUsers).Count -gt 0)            { Kv 'Comptes exemptes' (@($cfg.exemptUsers) -join ', ') }

Head 'Calendrier scolaire'
if ($Refresh) {
    try {
        $r = Update-DodoCalendarCache -Config $cfg -Root $Root -Now $now
        Kv 'Rafraichissement' $r.Message $(if ($r.Success) { 'Green' } else { 'Yellow' })
    }
    catch { Kv 'Rafraichissement' ("ECHEC : " + $_.Exception.Message) 'Red' }
}
$cal = Get-DodoCalendar -Config $cfg -Root $Root -Now $now
Kv 'Source'   'data.education.gouv.fr / fr-en-calendrier-scolaire'
Kv 'Fiable'   $(if ($cal.Trusted) { 'OUI' } else { 'NON -> repli sur la regle scolaire (21:00)' }) $(if ($cal.Trusted) { 'Green' } else { 'Yellow' })
Kv 'Anciennete' $(if ($null -eq $cal.AgeDays) { 'inconnue' } else { "$($cal.AgeDays) jours (max $($cfg.calendar.maxCacheAgeDays))" })
Kv 'Periodes'   ("{0} issues de l API, {1} saisies a la main" -f $cal.ApiCount, $cal.OverrideCount)
foreach ($n in $cal.Notes) { Write-Host "   ! $n" -ForegroundColor Yellow }
$future = @($cal.Periods | Where-Object { $_.EndExclusive -gt $now.Date } | Sort-Object Start | Select-Object -First 8)
if ($future.Count -gt 0) {
    Write-Host ''
    Write-Host '   Prochaines periodes de vacances :' -ForegroundColor DarkGray
    foreach ($p in $future) {
        Write-Host ('     {0,-30} du {1} au {2} inclus  (rentree le {3})' -f `
            $p.Label, $p.Start.ToString('dd/MM/yyyy'), $p.EndExclusive.AddDays(-1).ToString('dd/MM/yyyy'), $p.EndExclusive.ToString('dd/MM/yyyy'))
    }
}

Head 'Decision a cet instant'
$exc = Get-DodoActiveException -Root $Root -Now $now
if ($exc) {
    Kv 'DEROGATION ACTIVE' ("jusqu'a {0} - motif : {1} (par {2})" -f $exc.Until.ToString('dd/MM HH:mm'), $exc.Reason, $exc.By) 'Magenta'
}
$state = Get-DodoState -Now $now -Config $cfg -Periods $cal.Periods -CalendarTrusted $cal.Trusted
$col = switch ($state.State) { 'Blocked' { 'Red' } 'Warning' { 'Yellow' } default { 'Green' } }
Kv 'Etat'   $state.State $col
Kv 'Motif'  $state.Reason
Kv 'Fenetre' ("{0}  ->  {1}" -f $state.BlockStart.ToString('ddd dd/MM HH:mm'), $state.BlockEnd.ToString('ddd dd/MM HH:mm'))
if ($state.State -eq 'Blocked') { Kv 'Deblocage dans' ("{0} min" -f $state.MinutesToUnblock) }
else                            { Kv 'Extinction dans' ("{0} min" -f $state.MinutesToBlock) }

Head "Previsionnel des $Nights prochaines nuits"
Write-Host '   Soir         Jour        Fenetre    Extinction   Reveil   Motif' -ForegroundColor DarkGray
for ($i = 0; $i -lt $Nights; $i++) {
    $ev  = $now.Date.AddDays($i)
    $w   = Get-DodoNightWindow -EveningDate $ev -Config $cfg -Periods $cal.Periods -CalendarTrusted $cal.Trusted
    $c   = if ($w.Kind -eq 'holiday') { 'Green' } else { 'Gray' }
    Write-Host ('   {0}   {1,-10}  {2,-9}  {3,-11}  {4,-7}  {5}' -f `
        $ev.ToString('dd/MM/yyyy'), $ev.ToString('dddd'), $w.Kind,
        $ev.Add($w.StartTime).ToString('HH:mm'), $ev.AddDays(1).Add($w.EndTime).ToString('HH:mm'), $w.Reason) -ForegroundColor $c
}

if ($isWindows5) {
    Head 'Taches planifiees'
    foreach ($t in @('Dodo-Enforce', 'Dodo-Boot', 'Dodo-Notify')) {
        try {
            $task = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName $t -ErrorAction Stop
            $info = Get-ScheduledTaskInfo -InputObject $task
            $rep  = ''
            foreach ($tr in @($task.Triggers)) {
                $ri = $null
                try { $ri = $tr.Repetition.Interval } catch { }
                if ($ri) { $rep = $ri; break }
            }
            $ok = ($task.State -ne 'Disabled')
            Kv $t ("etat={0} repetition={1} dernier={2} resultat=0x{3:X}" -f `
                $task.State, $(if ($rep) { $rep } else { '(aucune)' }),
                $(if ($info.LastRunTime -and $info.LastRunTime.Year -gt 1999) { $info.LastRunTime.ToString('dd/MM HH:mm:ss') } else { 'jamais' }),
                $info.LastTaskResult) $(if ($ok) { 'Green' } else { 'Red' })
        }
        catch { Kv $t 'ABSENTE' 'Red' }
    }

    Head 'Reseau'
    if ($cfg.wifi.enforceSsidFilter) {
        Kv 'Filtre Wi-Fi' ('actif - SSID autorises : ' + (@($cfg.wifi.allowedSsids) -join ', ')) 'Green'
        $f = & netsh.exe wlan show filters 2>&1
        foreach ($l in @($f)) { if ($l -match '\S') { Write-Host "     $l" -ForegroundColor DarkGray } }
    }
    else { Kv 'Filtre Wi-Fi' 'inactif' 'DarkGray' }

    if ($cfg.adapterGuard.enabled) {
        Kv 'Garde-cartes reseau' ('actif - ' + @($cfg.adapterGuard.allowedPnpDeviceIds).Count + ' carte(s) autorisee(s)') 'Green'
        try {
            foreach ($a in @(Get-NetAdapter -ErrorAction Stop | Sort-Object Name)) {
                $allowed = (@($cfg.adapterGuard.allowedPnpDeviceIds) -contains $a.PnPDeviceID)
                Write-Host ('     [{0}] {1,-22} {2,-10} {3}' -f $(if ($allowed) { 'OK' } else { '!!' }), $a.Name, $a.Status, $a.InterfaceDescription) `
                    -ForegroundColor $(if ($allowed) { 'DarkGray' } else { 'Yellow' })
            }
        }
        catch { Write-Host "     Get-NetAdapter indisponible : $($_.Exception.Message)" -ForegroundColor Yellow }
    }
    else { Kv 'Garde-cartes reseau' 'inactif' 'DarkGray' }

    Head 'Journal (10 dernieres lignes)'
    $lf = Join-Path $paths.Logs ('dodo-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    if (Test-Path -LiteralPath $lf) { Get-Content -LiteralPath $lf -Tail 10 | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray } }
    else { Write-Host '   (aucune entree aujourd hui)' -ForegroundColor DarkGray }
}

Write-Host ''
