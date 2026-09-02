#Requires -Version 5.1
<#
    Test-DodoE2E.ps1 - Recette bout-en-bout du couvre-feu Dodo, sur le PC d'essai.

    A lancer EN ADMINISTRATEUR, apres Install-Dodo.ps1, depuis dodo\tests :

        powershell -ExecutionPolicy Bypass -File .\Test-DodoE2E.ps1

    Phases (toutes par defaut, sauf 'boot' et 'real' qui sont explicites) :
        preflight  droits, fichiers deployes conformes aux sources, voix disponibles
        logic      116 assertions du noyau de decision
        calendar   recuperation reelle du calendrier + verification du repli securitaire
        security   l'enfant ne peut ni modifier les scripts ni desactiver les taches
        tasks      les taches planifiees tournent vraiment toutes les minutes
        evening    deroule une soiree complete en ~1 minute : 4 preavis + extinction simulee
        boot       persistance apres redemarrage           (-Phase boot puis -Phase bootcheck)
        real       VRAIE extinction, une fois              (-Phase real -IReallyWantToShutDown)

    Aucune phase par defaut n'eteint le poste : elles exigent le mode dryRun.
#>
[CmdletBinding()]
param(
    [string]$Root = (Join-Path $env:ProgramData 'Dodo'),
    [string[]]$Phase = @('preflight', 'logic', 'calendar', 'security', 'tasks', 'evening'),
    [int]$InMinutes = 12,
    [switch]$IReallyWantToShutDown,
    [int]$PopupSeconds = 4
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

# powershell.exe -File passe les arguments en chaines litterales : un
# "-Phase a,b,c" arrive comme UN seul element. On renormalise donc ici.
$Phase = @($Phase | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$srcDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
. (Join-Path $srcDir 'DodoCore.ps1')
. (Join-Path $srcDir 'DodoRuntime.ps1')

$paths   = Get-DodoPaths -Root $Root
$Pass    = 0; $Fail = 0; $Skip = 0
$Failures = New-Object System.Collections.Generic.List[string]

function Sec  { param($T) Write-Host ''; Write-Host ("=== $T " + ('=' * [math]::Max(0, 64 - $T.Length))) -ForegroundColor Cyan }
function Chk  { param([bool]$Cond, [string]$Label, [string]$Detail = '')
    if ($Cond) { $script:Pass++; Write-Host "  [OK]   $Label" -ForegroundColor DarkGreen }
    else { $script:Fail++; $script:Failures.Add("$Label $Detail"); Write-Host "  [FAIL] $Label  $Detail" -ForegroundColor Red } }
function Skp  { param([string]$Label, [string]$Why) $script:Skip++; Write-Host "  [--]   $Label ($Why)" -ForegroundColor DarkGray }
function Note { param($T) Write-Host "         $T" -ForegroundColor DarkGray }

function Get-LogTail { param([string]$Dir, [int]$From = 0)
    $f = Join-Path $Dir ('dodo-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    $all = @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue)
    if ($From -ge $all.Count) { return @() }
    return @($all[$From..($all.Count - 1)]) }
function Get-LogCount { param([string]$Dir)
    $f = Join-Path $Dir ('dodo-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
    if (-not (Test-Path -LiteralPath $f)) { return 0 }
    return @(Get-Content -LiteralPath $f -ErrorAction SilentlyContinue).Count }

$userLogDir = Join-Path $env:LOCALAPPDATA 'Dodo'
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$want = { param($p) ($Phase -contains $p) -or ($Phase -contains 'all') }

Write-Host ''
Write-Host '  DODO - recette bout-en-bout' -ForegroundColor White
Write-Host ("  poste $env:COMPUTERNAME - $((Get-Date).ToString('dd/MM/yyyy HH:mm:ss')) - phases : $($Phase -join ', ')") -ForegroundColor DarkGray

# ==========================================================================
if (& $want 'preflight') {
    Sec 'PHASE 1 - Prealables'
    Chk $isAdmin 'session administrateur'
    Chk ($env:OS -eq 'Windows_NT') 'systeme Windows'
    Chk ($PSVersionTable.PSVersion.Major -ge 5) "PowerShell $($PSVersionTable.PSVersion)"
    Chk (Test-Path -LiteralPath $paths.Root) "installation presente : $($paths.Root)"

    # Le code deploye doit etre EXACTEMENT le code source teste.
    $diff = @()
    foreach ($f in @('DodoCore.ps1', 'DodoRuntime.ps1', 'Invoke-DodoEnforce.ps1', 'Show-DodoWarning.ps1', 'Get-DodoStatus.ps1', 'Add-DodoException.ps1')) {
        $a = Join-Path $srcDir $f; $b = Join-Path $paths.Bin $f
        if (-not (Test-Path -LiteralPath $b)) { $diff += "$f absent"; continue }
        if ((Get-FileHash $a).Hash -ne (Get-FileHash $b).Hash) { $diff += "$f different" }
    }
    Chk ($diff.Count -eq 0) 'les scripts deployes sont identiques aux sources' ($diff -join ', ')

    $cfg = Get-DodoConfiguration -Root $Root
    Chk $cfg.enabled 'couvre-feu actif (enabled = true)'
    Note ("mode : " + $(if ($cfg.dryRun) { 'SIMULATION' } else { 'PRODUCTION - extinction reelle' }))

    $voices = @()
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $sy = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $voices = @($sy.GetInstalledVoices() | Where-Object { $_.Enabled })
        $sy.Dispose()
    }
    catch { }
    $fr = @($voices | Where-Object { $_.VoiceInfo.Culture.Name -like 'fr*' })
    foreach ($v in $voices) { Note ("voix : {0} [{1}]" -f $v.VoiceInfo.Name, $v.VoiceInfo.Culture.Name) }
    if ($fr.Count -gt 0) { Chk $true "voix francaise disponible : $($fr[0].VoiceInfo.Name)" }
    elseif ((Test-Path (Join-Path $paths.Media 'warning.wav')) -and (Test-Path (Join-Path $paths.Media 'shutdown.wav'))) {
        Chk $true 'pas de voix francaise, mais media\warning.wav et media\shutdown.wav sont presents'
    }
    else {
        Chk $false 'annonce vocale en francais' "aucune voix fr* et aucun WAV dans $($paths.Media) - voir docs/03-exploitation.md"
    }
}

# ==========================================================================
if (& $want 'logic') {
    Sec 'PHASE 2 - Noyau de decision'
    $lt = Join-Path $PSScriptRoot 'Test-DodoLogic.ps1'
    if (-not (Test-Path -LiteralPath $lt)) { Skp 'suite logique' 'Test-DodoLogic.ps1 introuvable' }
    else {
        $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $lt 2>&1
        $res = @($out | Where-Object { $_ -match 'RESULTAT' })
        Chk ($LASTEXITCODE -eq 0) ('suite logique : ' + ($res -join ' ')) ''
        if ($LASTEXITCODE -ne 0) { $out | Where-Object { $_ -match '\[FAIL\]' } | ForEach-Object { Note $_ } }
    }
}

# ==========================================================================
if (& $want 'calendar') {
    Sec 'PHASE 3 - Calendrier scolaire et repli securitaire'
    $cfg = Get-DodoConfiguration -Root $Root
    try {
        $r = Update-DodoCalendarCache -Config $cfg -Root $Root
        Chk $r.Success "recuperation du calendrier : $($r.Message)"
        foreach ($w in @($r.Warnings)) { Note "avertissement source : $w" }
    }
    catch { Chk $false 'recuperation du calendrier' $_.Exception.Message }

    $cal = Get-DodoCalendar -Config $cfg -Root $Root
    Chk $cal.Trusted 'calendrier juge fiable' ($cal.Notes -join ' ; ')
    Chk ($cal.ApiCount -ge 4) "au moins 4 periodes connues (obtenu $($cal.ApiCount))"
    foreach ($p in @($cal.Periods | Where-Object { $_.EndExclusive -gt (Get-Date) } | Sort-Object Start | Select-Object -First 5)) {
        Note ('{0,-30} {1} -> rentree le {2}' -f $p.Label, $p.Start.ToString('dd/MM/yyyy'), $p.EndExclusive.ToString('dd/MM/yyyy'))
    }

    # Repli : on met le cache de cote et on verifie que la regle stricte s'applique
    $bak = "$($paths.Calendar).e2e-bak"
    if (Test-Path -LiteralPath $paths.Calendar) {
        Move-Item -LiteralPath $paths.Calendar -Destination $bak -Force
        try {
            $degraded = Get-DodoCalendar -Config $cfg -Root $Root
            Chk (-not $degraded.Trusted) 'sans cache, le calendrier est declare non fiable'
            $probe = [datetime]::Parse('2026-12-24 22:00', [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR'))
            $w = Get-DodoNightWindow -EveningDate $probe.Date -Config $cfg -Periods $degraded.Periods -CalendarTrusted $degraded.Trusted
            Chk ($w.Kind -eq 'school') 'sans calendrier, meme un soir de vacances applique la regle 21:00 (repli le plus strict)'
        }
        finally { Move-Item -LiteralPath $bak -Destination $paths.Calendar -Force }
        $restored = Get-DodoCalendar -Config $cfg -Root $Root
        Chk $restored.Trusted 'cache restaure et de nouveau fiable'
    }
    else { Skp 'test de repli' 'aucun cache a mettre de cote' }
}

# ==========================================================================
if (& $want 'security') {
    Sec 'PHASE 4 - Resistance a la manipulation'
    foreach ($d in @($paths.Bin, $paths.Etc, $paths.Var)) {
        $bad = @()
        try { $bad = @(Get-DodoUserWriteRights -Path $d) }
        catch { $bad += "ACL illisible : $($_.Exception.Message)" }
        Chk ($bad.Count -eq 0) "le groupe Utilisateurs ne peut pas ecrire dans $(Split-Path -Leaf $d)" ($bad -join ', ')
    }

    $admins = @()
    try { $admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop | Select-Object -ExpandProperty Name) } catch { }
    foreach ($a in $admins) { Note "administrateur local : $a" }
    Note "Verifiez a l'oeil que le compte de l'enfant n'y figure pas : sinon tout le dispositif est contournable."

    try {
        $t = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName 'Dodo-Enforce' -ErrorAction Stop
        Chk ($t.Principal.UserId -match 'SYSTEM|S-1-5-18') "Dodo-Enforce s'execute bien sous SYSTEM ($($t.Principal.UserId))"
        Chk ($t.Principal.RunLevel -eq 'Highest') 'Dodo-Enforce s execute avec les privileges les plus eleves'
    }
    catch { Chk $false 'tache Dodo-Enforce presente' $_.Exception.Message }
}

# ==========================================================================
if (& $want 'tasks') {
    Sec 'PHASE 5 - Les taches tournent vraiment'
    foreach ($n in @('Dodo-Enforce', 'Dodo-Notify')) {
        try {
            $t = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName $n -ErrorAction Stop
            Chk ($t.State -ne 'Disabled') "$n : etat $($t.State)"
            $rep = '(aucune)'
            foreach ($tr in @($t.Triggers)) { try { if ($tr.Repetition.Interval) { $rep = $tr.Repetition.Interval; break } } catch { } }
            Chk ($rep -eq 'PT1M') "$n : repetition d une minute declaree ($rep)"
        }
        catch { Chk $false "$n presente" $_.Exception.Message }
    }
    # Dodo-Boot n'a qu'un declencheur au demarrage : pas de repetition attendue.
    try {
        $tb = Get-ScheduledTask -TaskPath '\Dodo\' -TaskName 'Dodo-Boot' -ErrorAction Stop
        Chk ($tb.State -ne 'Disabled') "Dodo-Boot : etat $($tb.State)"
    }
    catch { Skp 'Dodo-Boot' 'absente - la repetition de Dodo-Enforce couvre le cas' }
    $before = (Get-ScheduledTaskInfo -TaskPath '\Dodo\' -TaskName 'Dodo-Enforce').LastRunTime
    Note 'attente de 75 s pour observer un declenchement spontane...'
    Start-Sleep -Seconds 75
    $after = (Get-ScheduledTaskInfo -TaskPath '\Dodo\' -TaskName 'Dodo-Enforce')
    Chk ($after.LastRunTime -gt $before) "Dodo-Enforce s'est declenchee seule (avant $($before.ToString('HH:mm:ss')), apres $($after.LastRunTime.ToString('HH:mm:ss')))"
    Chk ($after.LastTaskResult -eq 0) "Dodo-Enforce se termine sans erreur (code $($after.LastTaskResult))"
}

# ==========================================================================
if (& $want 'evening') {
    Sec 'PHASE 6 - Une soiree complete en une minute'
    $cfg = Get-DodoConfiguration -Root $Root
    if (-not $cfg.dryRun) {
        Chk $false 'phase soiree' 'le mode SIMULATION est obligatoire ici (relancez Install-Dodo.ps1 sans -Production)'
    }
    else {
        $raw     = Read-DodoJson -Path $paths.Config
        $tStart  = (Get-Date).AddMinutes(60)
        $tw      = [pscustomobject]@{ start = $tStart.ToString('s'); end = $tStart.AddMinutes(5).ToString('s'); label = 'recette bout-en-bout' }
        $raw | Add-Member -NotePropertyName 'testWindow' -NotePropertyValue $tw -Force
        Write-DodoJson -Path $paths.Config -Object $raw
        Note ("fenetre d'essai posee a {0} (simulee, aucune extinction reelle)" -f $tStart.ToString('HH:mm'))
        Get-ChildItem -LiteralPath $userLogDir -Filter 'fired-*.txt' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }

        $enforceScript = Join-Path $paths.Bin 'Invoke-DodoEnforce.ps1'
        $notifyScript  = Join-Path $paths.Bin 'Show-DodoWarning.ps1'
        $scenario = @(
            @{ D = -11; Warn = $false; Shut = $false; Label = 'a 11 minutes : rien ne se passe' },
            @{ D = -10; Warn = $true;  Shut = $false; Label = 'a 10 minutes : 1er preavis (voix + fenetre)' },
            @{ D = -6;  Warn = $false; Shut = $false; Label = 'a 6 minutes : pas de repetition inutile' },
            @{ D = -5;  Warn = $true;  Shut = $false; Label = 'a 5 minutes : 2e preavis' },
            @{ D = -2;  Warn = $true;  Shut = $false; Label = 'a 2 minutes : 3e preavis' },
            @{ D = -1;  Warn = $true;  Shut = $false; Label = 'a 1 minute : dernier preavis' },
            @{ D = 0;   Warn = $false; Shut = $true;  Label = 'a l heure : extinction (simulee)' }
        )
        # Les taches planifiees tourneraient en parallele et consommeraient les
        # marqueurs de preavis : on les met en pause pour rendre la phase
        # deterministe (leur bon fonctionnement est verifie par la phase 'tasks').
        $paused = @()
        foreach ($n in @('Dodo-Enforce', 'Dodo-Notify')) {
            try { Disable-ScheduledTask -TaskPath '\Dodo\' -TaskName $n -ErrorAction Stop | Out-Null; $paused += $n } catch { }
        }
        if ($paused.Count -gt 0) { Note ("taches mises en pause pendant la phase : " + ($paused -join ', ')) }

        try {
            foreach ($s in $scenario) {
                if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
                Write-DodoText -Path $paths.ClockOffset -Content ([string](60 + $s.D))
                $nBefore = Get-LogCount -Dir $paths.Logs
                $uBefore = Get-LogCount -Dir $userLogDir
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $enforceScript -Root $Root | Out-Null
                & powershell.exe -NoProfile -Sta -ExecutionPolicy Bypass -File $notifyScript -Root $Root -DisplaySeconds $PopupSeconds | Out-Null
                $sysNew  = Get-LogTail -Dir $paths.Logs -From $nBefore
                $usrNew  = Get-LogTail -Dir $userLogDir -From $uBefore
                $gotWarn = @($usrNew | Where-Object { $_ -match 'Preavis diffuse' }).Count -gt 0
                $gotShut = @($sysNew | Where-Object { $_ -match 'SIMULATION : extinction' }).Count -gt 0
                $gotSaid = @($usrNew | Where-Object { $_ -match "Message d'extinction diffuse" }).Count -gt 0
                if ($s.Shut) { Chk ($gotShut -and $gotSaid) $s.Label ("extinction=$gotShut annonce=$gotSaid") }
                else         { Chk (($gotWarn -eq $s.Warn) -and (-not $gotShut)) $s.Label ("preavis=$gotWarn extinction=$gotShut") }
                foreach ($l in @($usrNew | Where-Object { $_ -match 'ACTION|WARN|ERROR' })) { Note $l }
                foreach ($l in @($sysNew | Where-Object { $_ -match 'ACTION|ERROR' })) { Note $l }
            }
        }
        finally {
            foreach ($n in $paused) { try { Enable-ScheduledTask -TaskPath '\Dodo\' -TaskName $n -ErrorAction Stop | Out-Null } catch { Note "ATTENTION : reactivez la tache $n a la main." } }
            if ($paused.Count -gt 0) { Note ("taches reactivees : " + ($paused -join ', ')) }
            if (Test-Path -LiteralPath $paths.ClockOffset) { Remove-Item -LiteralPath $paths.ClockOffset -Force }
            $raw2 = Read-DodoJson -Path $paths.Config
            if ($null -ne $raw2.PSObject.Properties['testWindow']) { $raw2.PSObject.Properties.Remove('testWindow'); Write-DodoJson -Path $paths.Config -Object $raw2 }
            if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
            Get-ChildItem -LiteralPath $userLogDir -Filter 'fired-*.txt' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Note "decalage d'horloge et fenetre d'essai retires ; configuration revenue a l'etat initial"
        }
    }
}

# ==========================================================================
if ($Phase -contains 'boot') {
    Sec 'PHASE 7a - Persistance apres redemarrage (preparation)'
    $cfg = Get-DodoConfiguration -Root $Root
    if (-not $cfg.dryRun) { Chk $false 'phase boot' 'mode SIMULATION obligatoire' }
    else {
        $raw = Read-DodoJson -Path $paths.Config
        $st  = (Get-Date).AddMinutes(2)
        $raw | Add-Member -NotePropertyName 'testWindow' -NotePropertyValue ([pscustomobject]@{
            start = $st.ToString('s'); end = $st.AddMinutes(25).ToString('s'); label = 'recette persistance redemarrage' }) -Force
        Write-DodoJson -Path $paths.Config -Object $raw
        Write-DodoText -Path (Join-Path $paths.Var 'e2e-boot.txt') -Content (Get-Date).ToString('o')
        if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
        Write-Host ''
        Write-Host '  Preparation faite. Maintenant :' -ForegroundColor Yellow
        Write-Host '    1. Attendez 2 minutes, puis REDEMARREZ le poste.' -ForegroundColor Yellow
        Write-Host '    2. Rouvrez une session administrateur.' -ForegroundColor Yellow
        Write-Host '    3. Relancez :  .\Test-DodoE2E.ps1 -Phase bootcheck' -ForegroundColor Yellow
        Write-Host '  (mode SIMULATION : le poste ne s eteindra pas, seule la trace est verifiee)' -ForegroundColor DarkGray
    }
}

if ($Phase -contains 'bootcheck') {
    Sec 'PHASE 7b - Persistance apres redemarrage (verification)'
    $marker = Join-Path $paths.Var 'e2e-boot.txt'
    if (-not (Test-Path -LiteralPath $marker)) { Chk $false 'preparation trouvee' 'lancez d abord -Phase boot' }
    else {
        $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        $prep = [datetime]::Parse((Read-DodoText -Path $marker).Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
        Chk ($boot -gt $prep) "le poste a bien redemarre apres la preparation (demarrage $($boot.ToString('HH:mm:ss')))"
        $lines = @(Get-LogTail -Dir $paths.Logs)
        $hits = @()
        foreach ($l in $lines) {
            if ($l -notmatch 'SIMULATION : extinction') { continue }
            $ts = $null
            try { $ts = [datetime]::Parse($l.Substring(0, 19), [System.Globalization.CultureInfo]::InvariantCulture) } catch { continue }
            if ($ts -gt $boot) { $hits += ,@($ts, $l) }
        }
        Chk ($hits.Count -gt 0) 'la regle a ete reappliquee toute seule apres le redemarrage'
        if ($hits.Count -gt 0) {
            $delay = [int]($hits[0][0] - $boot).TotalSeconds
            Note "premiere application $delay s apres le demarrage : $($hits[0][1])"
            Chk ($delay -le 180) "reapplication en moins de 3 minutes ($delay s)"
        }
        $raw = Read-DodoJson -Path $paths.Config
        if ($null -ne $raw.PSObject.Properties['testWindow']) { $raw.PSObject.Properties.Remove('testWindow'); Write-DodoJson -Path $paths.Config -Object $raw }
        Remove-Item -LiteralPath $marker -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
        Note 'fenetre d essai retiree, configuration revenue a l etat initial'
    }
}

# ==========================================================================
if ($Phase -contains 'real') {
    Sec 'PHASE 8 - VRAIE extinction (une seule fois)'
    if (-not $IReallyWantToShutDown) {
        Chk $false 'confirmation' 'ajoutez -IReallyWantToShutDown pour autoriser une extinction reelle'
    }
    else {
        $raw = Read-DodoJson -Path $paths.Config
        $cfgNow = Resolve-DodoConfig $raw
        $cal = Get-DodoCalendar -Config $cfgNow -Root $Root
        $st  = Get-DodoState -Now (Get-Date) -Config (Resolve-DodoConfig ([pscustomobject]@{})) -Periods $cal.Periods -CalendarTrusted $cal.Trusted
        if ($st.State -ne 'Allowed' -or $st.MinutesToBlock -lt ($InMinutes + 10)) {
            Chk $false 'creneau adapte' "la regle normale se declenche dans $($st.MinutesToBlock) min : refaites ce test plus tot dans la journee"
        }
        else {
            $start = (Get-Date).AddMinutes($InMinutes)
            $raw | Add-Member -NotePropertyName 'dryRun' -NotePropertyValue $false -Force
            $raw | Add-Member -NotePropertyName 'testWindow' -NotePropertyValue ([pscustomobject]@{
                start = $start.ToString('s'); end = $start.AddMinutes(3).ToString('s'); label = 'recette extinction reelle' }) -Force
            Write-DodoJson -Path $paths.Config -Object $raw
            if (Test-Path -LiteralPath $paths.ClockOffset) { Remove-Item -LiteralPath $paths.ClockOffset -Force }
            if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force }
            Get-ChildItem -LiteralPath $userLogDir -Filter 'fired-*.txt' -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
            Chk $true "extinction reelle programmee a $($start.ToString('HH:mm:ss'))"
            Write-Host ''
            Write-Host '  ENREGISTREZ VOTRE TRAVAIL MAINTENANT.' -ForegroundColor Red
            Write-Host "  Preavis attendus a T-10, T-5, T-2 et T-1 minute, puis extinction a $($start.ToString('HH:mm'))." -ForegroundColor Yellow
            Write-Host '  Pour tout annuler avant : Add-DodoException.ps1 -Minutes 60 -Reason "annulation du test"' -ForegroundColor Yellow
            Write-Host '  La fenetre d essai se supprime toute seule apres declenchement : aucun risque de boucle au redemarrage.' -ForegroundColor DarkGray
            Write-Host '  Apres redemarrage, verifiez :  Get-DodoStatus.ps1  puis  Install-Dodo.ps1 -Production' -ForegroundColor DarkGray
        }
    }
}

# ==========================================================================
Write-Host ''
Write-Host ('-' * 72)
if ($Fail -eq 0) { Write-Host ("RECETTE : {0} controles OK, {1} ignores, 0 echec." -f $Pass, $Skip) -ForegroundColor Green }
else {
    Write-Host ("RECETTE : {0} OK, {1} ignores, {2} ECHECS." -f $Pass, $Skip, $Fail) -ForegroundColor Red
    foreach ($f in $Failures) { Write-Host "  - $f" -ForegroundColor Red }
}
Write-Host ''
exit $(if ($Fail -eq 0) { 0 } else { 1 })
