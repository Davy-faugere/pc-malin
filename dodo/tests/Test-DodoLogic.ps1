#Requires -Version 5.1
<#
    Test-DodoLogic.ps1 - Tests du noyau de decision (100 % hors ligne, sans effet de bord).

    Executable partout : Windows PowerShell 5.1, PowerShell 7 (Windows/Linux/macOS).
        pwsh -File dodo/tests/Test-DodoLogic.ps1

    Les enregistrements de calendrier utilises en fixture sont des extraits REELS
    de l'API data.education.gouv.fr (dataset fr-en-calendrier-scolaire, zone C),
    y compris ses cas degenres : population "Enseignants", periodes de duree nulle
    et "Debut des Vacances d'Ete" sans date de fin publiee.
#>

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'src/DodoCore.ps1')

$script:Pass = 0
$script:Fail = 0
$script:Failures = New-Object System.Collections.Generic.List[string]

function Assert-Equal {
    param($Expected, $Actual, [string]$Label)
    $e = if ($null -eq $Expected) { '<null>' } else { $Expected.ToString() }
    $a = if ($null -eq $Actual)   { '<null>' } else { $Actual.ToString() }
    if ($e -eq $a) {
        $script:Pass++
        Write-Host ("  [OK]   " + $Label) -ForegroundColor DarkGreen
    }
    else {
        $script:Fail++
        $script:Failures.Add("$Label : attendu '$e', obtenu '$a'")
        Write-Host ("  [FAIL] " + $Label + " : attendu '$e', obtenu '$a'") -ForegroundColor Red
    }
}

function Assert-Throws {
    param([scriptblock]$Script, [string]$Label)
    $threw = $false
    try { & $Script } catch { $threw = $true }
    Assert-Equal -Expected $true -Actual $threw -Label $Label
}

function Write-Section { param([string]$Title) Write-Host ''; Write-Host "== $Title" -ForegroundColor Cyan }

# --------------------------------------------------------------------------
# Fixture : extraits reels de l'API (zone C, annees 2025-2026 et 2026-2027)
# --------------------------------------------------------------------------
$rawJson = @'
[
 {"description":"Vacances de la Toussaint","population":"-","start_date":"2025-10-17T22:00:00+00:00","end_date":"2025-11-02T23:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Vacances de No\u00ebl","population":"-","start_date":"2025-12-19T23:00:00+00:00","end_date":"2026-01-04T23:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Vacances d'Hiver","population":"-","start_date":"2026-02-20T23:00:00+00:00","end_date":"2026-03-08T23:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Vacances de Printemps","population":"-","start_date":"2026-04-17T22:00:00+00:00","end_date":"2026-05-03T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Pont de l'Ascension","population":"-","start_date":"2026-05-13T22:00:00+00:00","end_date":"2026-05-17T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Vacances d'\u00c9t\u00e9","population":"Enseignants","start_date":"2026-07-03T22:00:00+00:00","end_date":"2026-08-30T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Vacances d'\u00c9t\u00e9","population":"\u00c9l\u00e8ves","start_date":"2026-07-03T22:00:00+00:00","end_date":"2026-08-31T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2025-2026"},
 {"description":"Vacances de la Toussaint","population":"-","start_date":"2026-10-16T22:00:00+00:00","end_date":"2026-11-01T23:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2026-2027"},
 {"description":"Vacances de No\u00ebl","population":"-","start_date":"2026-12-18T23:00:00+00:00","end_date":"2027-01-03T23:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2026-2027"},
 {"description":"Vacances d'Hiver","population":"-","start_date":"2027-02-05T23:00:00+00:00","end_date":"2027-02-21T23:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2026-2027"},
 {"description":"Vacances de Printemps","population":"-","start_date":"2027-04-02T22:00:00+00:00","end_date":"2027-04-18T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2026-2027"},
 {"description":"Pont de l'Ascension","population":"-","start_date":"2027-05-06T22:00:00+00:00","end_date":"2027-05-06T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2026-2027"},
 {"description":"D\u00e9but des Vacances d'\u00c9t\u00e9","population":"-","start_date":"2027-07-02T22:00:00+00:00","end_date":"2027-07-02T22:00:00+00:00","location":"Paris","zones":"Zone C","annee_scolaire":"2026-2027"}
]
'@
$records = $rawJson | ConvertFrom-Json
$cfg     = Resolve-DodoConfig ([pscustomobject]@{})
$tz      = Get-DodoParisTimeZone
$parsed  = ConvertFrom-DodoCalendarRecords -Records $records -Config $cfg -TimeZone $tz
$periods = $parsed.Periods

Write-Host "Dodo - tests du noyau de decision" -ForegroundColor White
Write-Host "PowerShell $($PSVersionTable.PSVersion) / fuseau resolu : $($tz.Id)"

# --------------------------------------------------------------------------
Write-Section 'Analyse des horaires'
Assert-Equal '21:00:00' (ConvertTo-DodoTimeSpan '21:00') 'ConvertTo-DodoTimeSpan 21:00'
Assert-Equal '06:30:00' (ConvertTo-DodoTimeSpan '06:30') 'ConvertTo-DodoTimeSpan 06:30'
Assert-Throws { ConvertTo-DodoTimeSpan '24:00' }  'refus de 24:00'
Assert-Throws { ConvertTo-DodoTimeSpan '9:00' }   'refus de 9:00 (non zero-pad)'
Assert-Throws { ConvertTo-DodoTimeSpan '21h00' }  'refus de 21h00'
Assert-Throws { ConvertTo-DodoTimeSpan '' }       'refus de la chaine vide'

# --------------------------------------------------------------------------
Write-Section 'Validation de la configuration'
Assert-Equal '21:00' $cfg.schedule.school.start  'defaut ecole = 21:00'
Assert-Equal '23:00' $cfg.schedule.holiday.start 'defaut vacances = 23:00'
Assert-Equal '06:30' $cfg.schedule.school.end    'defaut fin = 06:30'
Assert-Equal 'Zone C' $cfg.zone                  'defaut zone = Zone C'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ schedule = @{ school = @{ start = '06:00'; end = '21:00' } } }) } 'refus fenetre non nocturne'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ warningMinutes = @() }) }                                        'refus warningMinutes vide'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ warningMinutes = @(10, 0) }) }                                   'refus seuil nul'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ shutdownGraceSeconds = 9999 }) }                                 'refus grace > 600 s'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ bootGraceSeconds = -1 }) }                                       'refus bootGrace negatif'
Assert-Equal 90 $cfg.bootGraceSeconds 'defaut bootGraceSeconds = 90 s'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ calendar = @{ openEndedSummerEnd = '31-12' } }) }                'refus format MM-JJ invalide'
$custom = Resolve-DodoConfig ([pscustomobject]@{ schedule = @{ holiday = @{ start = '22:30' } } })
Assert-Equal '22:30' $custom.schedule.holiday.start 'fusion partielle : holiday.start surcharge'
Assert-Equal '06:30' $custom.schedule.holiday.end   'fusion partielle : holiday.end conserve par defaut'

# --------------------------------------------------------------------------
Write-Section 'Conversion des horodatages source vers dates de Paris'
Assert-Equal '2025-10-18' (ConvertTo-DodoParisDate '2025-10-17T22:00:00+00:00' $tz).ToString('yyyy-MM-dd') 'heure d ete (+02) -> 18/10/2025'
Assert-Equal '2025-11-03' (ConvertTo-DodoParisDate '2025-11-02T23:00:00+00:00' $tz).ToString('yyyy-MM-dd') 'heure d hiver (+01) -> 03/11/2025'
Assert-Equal '2026-09-01' (ConvertTo-DodoParisDate '2026-08-31T22:00:00+00:00' $tz).ToString('yyyy-MM-dd') 'rentree 01/09/2026'

# --------------------------------------------------------------------------
Write-Section 'Analyse du calendrier (cas reels degenres inclus)'
Assert-Equal 11 $periods.Count 'nombre de periodes retenues'
$dup = New-Object System.Collections.Generic.List[object]
foreach ($r in $records) { $dup.Add($r) }
foreach ($r in $records) { $dup.Add($r) }   # les 5 academies de la zone C repetent chaque creneau
Assert-Equal 11 (ConvertFrom-DodoCalendarRecords -Records $dup -Config $cfg -TimeZone $tz).Periods.Count 'doublons d academies elimines'
$toussaint25 = $periods | Where-Object { $_.Start -eq [datetime]'2025-10-18' } | Select-Object -First 1
Assert-Equal '2025-10-18' $toussaint25.Start.ToString('yyyy-MM-dd')        'Toussaint 2025 : premier jour'
Assert-Equal '2025-11-03' $toussaint25.EndExclusive.ToString('yyyy-MM-dd') 'Toussaint 2025 : rentree (borne exclue)'
$ete26 = $periods | Where-Object { $_.Start -eq [datetime]'2026-07-04' } | Select-Object -First 1
Assert-Equal 1 (@($periods | Where-Object { $_.Start -eq [datetime]'2026-07-04' }).Count) 'ete 2026 : un seul enregistrement (Enseignants exclu)'
Assert-Equal '2026-09-01' $ete26.EndExclusive.ToString('yyyy-MM-dd')       'ete 2026 : fin = 01/09/2026 (population Eleves)'
Assert-Equal 0 (@($periods | Where-Object { $_.Start -eq [datetime]'2027-05-07' }).Count) 'Pont Ascension 2027 (duree nulle) ignore'
$ete27 = $periods | Where-Object { $_.Start -eq [datetime]'2027-07-03' } | Select-Object -First 1
Assert-Equal '2027-09-01' $ete27.EndExclusive.ToString('yyyy-MM-dd')       'ete 2027 sans fin publiee : fin deduite au 01/09'
Assert-Equal 2 $parsed.Warnings.Count 'deux avertissements remontes a l administrateur'

# --------------------------------------------------------------------------
Write-Section 'Appartenance d une date aux vacances'
Assert-Equal $true  (Test-DodoVacationDate ([datetime]'2025-10-18') $periods) '18/10/2025 : premier jour de vacances'
Assert-Equal $true  (Test-DodoVacationDate ([datetime]'2025-11-02') $periods) '02/11/2025 : dernier jour de vacances'
Assert-Equal $false (Test-DodoVacationDate ([datetime]'2025-11-03') $periods) '03/11/2025 : jour de rentree, pas vacances'
Assert-Equal $false (Test-DodoVacationDate ([datetime]'2025-10-17') $periods) '17/10/2025 : dernier jour de classe'
Assert-Equal $true  (Test-DodoVacationDate ([datetime]'2026-08-31') $periods) '31/08/2026 : encore les vacances'
Assert-Equal $false (Test-DodoVacationDate ([datetime]'2026-09-01') $periods) '01/09/2026 : rentree'

# --------------------------------------------------------------------------
Write-Section 'Fenetre applicable a une nuit'
function WinKind([string]$d) { (Get-DodoNightWindow ([datetime]$d) $cfg $periods $true).Kind }
Assert-Equal 'school'  (WinKind '2026-09-02') 'mercredi 02/09/2026 (periode scolaire)'
Assert-Equal 'school'  (WinKind '2026-10-16') 'vendredi 16/10/2026, veille du 1er jour de vacances'
Assert-Equal 'holiday' (WinKind '2026-10-17') 'samedi 17/10/2026, 1re nuit de vacances'
Assert-Equal 'holiday' (WinKind '2026-10-31') 'samedi 31/10/2026, pleines vacances'
Assert-Equal 'school'  (WinKind '2026-11-01') 'dimanche 01/11/2026, veille de rentree (regle stricte)'
Assert-Equal 'school'  (WinKind '2026-11-02') 'lundi 02/11/2026, rentree'

$cfgSouple = Resolve-DodoConfig ([pscustomobject]@{ strictNightBeforeReturn = $false })
Assert-Equal 'holiday' (Get-DodoNightWindow ([datetime]'2026-11-01') $cfgSouple $periods $true).Kind 'veille de rentree si strictNightBeforeReturn = false'

$cfgWeekend = Resolve-DodoConfig ([pscustomobject]@{ lateEveningsDuringTerm = @('Friday', 'Saturday') })
Assert-Equal 'holiday' (Get-DodoNightWindow ([datetime]'2026-09-04') $cfgWeekend $periods $true).Kind 'vendredi scolaire avec lateEveningsDuringTerm'
Assert-Equal 'school'  (Get-DodoNightWindow ([datetime]'2026-09-03') $cfgWeekend $periods $true).Kind 'jeudi scolaire avec lateEveningsDuringTerm'

# --------------------------------------------------------------------------
Write-Section 'Repli securitaire quand le calendrier est indisponible'
Assert-Equal 'school' (Get-DodoNightWindow ([datetime]'2026-10-20') $cfg $periods $false).Kind 'pleines vacances mais calendrier non fiable -> regle stricte'
$degrade = Get-DodoState ([datetime]'2026-10-20 22:00') $cfg $periods $false
Assert-Equal 'Blocked' $degrade.State 'vacances a 22h00 sans calendrier fiable -> bloque'
$normal = Get-DodoState ([datetime]'2026-10-20 22:00') $cfg $periods $true
Assert-Equal 'Allowed' $normal.State 'vacances a 22h00 avec calendrier fiable -> autorise'

# --------------------------------------------------------------------------
Write-Section 'Machine a etats (periode scolaire, 21h00 - 06h30)'
function St([string]$d) { Get-DodoState ([datetime]$d) $cfg $periods $true }
Assert-Equal 'Allowed' (St '2026-09-02 18:00').State 'mercredi 18h00'
Assert-Equal 'Allowed' (St '2026-09-02 20:49').State '20h49 : hors preavis'
Assert-Equal 'Warning' (St '2026-09-02 20:50').State '20h50 : debut du preavis de 10 min'
Assert-Equal 10        (St '2026-09-02 20:50').MinutesToBlock '20h50 : 10 minutes restantes'
Assert-Equal 'Warning' (St '2026-09-02 20:55').State '20h55'
Assert-Equal 5         (St '2026-09-02 20:55').MinutesToBlock '20h55 : 5 minutes restantes'
Assert-Equal 1         (St '2026-09-02 20:59').MinutesToBlock '20h59 : 1 minute restante'
Assert-Equal 'Blocked' (St '2026-09-02 21:00').State '21h00 pile : bloque'
Assert-Equal 'Blocked' (St '2026-09-02 23:59').State '23h59 : bloque'
Assert-Equal 'Blocked' (St '2026-09-03 00:00').State 'minuit : bloque (nuit precedente)'
Assert-Equal 'Blocked' (St '2026-09-03 03:00').State '03h00 : bloque'
Assert-Equal 'Blocked' (St '2026-09-03 06:29').State '06h29 : encore bloque'
Assert-Equal 'Allowed' (St '2026-09-03 06:30').State '06h30 pile : autorise'
Assert-Equal 'Allowed' (St '2026-09-03 07:00').State '07h00 : autorise'
Assert-Equal '2026-09-02 21:00' (St '2026-09-03 03:00').BlockStart.ToString('yyyy-MM-dd HH:mm') '03h00 : debut de blocage = veille 21h00'
Assert-Equal '2026-09-03 06:30' (St '2026-09-03 03:00').BlockEnd.ToString('yyyy-MM-dd HH:mm')   '03h00 : fin de blocage = 06h30'
Assert-Equal 210 (St '2026-09-03 03:00').MinutesToUnblock '03h00 : 210 minutes avant deblocage'
Assert-Equal 870 (St '2026-09-03 06:30').MinutesToBlock   '06h30 : 870 minutes avant la prochaine extinction'

# --------------------------------------------------------------------------
Write-Section 'Machine a etats (vacances zone C, 23h00 - 06h30)'
Assert-Equal 'Allowed'  (St '2026-10-20 21:30').State 'vacances 21h30 : autorise'
Assert-Equal 'Allowed'  (St '2026-10-20 22:49').State 'vacances 22h49 : hors preavis'
Assert-Equal 'Warning'  (St '2026-10-20 22:50').State 'vacances 22h50 : preavis'
Assert-Equal 'Blocked'  (St '2026-10-20 23:00').State 'vacances 23h00 : bloque'
Assert-Equal 'Blocked'  (St '2026-10-21 05:00').State 'vacances 05h00 : bloque'
Assert-Equal 'Allowed'  (St '2026-10-21 06:30').State 'vacances 06h30 : autorise'
Assert-Equal 'holiday'  (St '2026-10-20 22:00').WindowKind 'fenetre vacances retenue'
Assert-Equal 'Blocked'  (St '2026-11-01 21:30').State 'veille de rentree 21h30 : bloque (regle scolaire)'
Assert-Equal 'Allowed'  (St '2026-10-17 22:30').State '1re nuit de vacances 22h30 : autorise'
Assert-Equal 'Blocked'  (St '2026-10-16 21:30').State 'derniere soiree de classe 21h30 : bloque'

# --------------------------------------------------------------------------
Write-Section 'Bascule d une nuit sur l autre (fin de vacances)'
Assert-Equal 'Blocked' (St '2026-11-02 03:00').State 'nuit du 01 au 02/11 a 03h00 : bloque'
Assert-Equal '2026-11-01 21:00' (St '2026-11-02 03:00').BlockStart.ToString('yyyy-MM-dd HH:mm') 'blocage commence a 21h00 (regle stricte veille de rentree)'
Assert-Equal 'Blocked' (St '2026-11-01 02:00').State 'nuit du 31/10 au 01/11 a 02h00 : bloque'
Assert-Equal '2026-10-31 23:00' (St '2026-11-01 02:00').BlockStart.ToString('yyyy-MM-dd HH:mm') 'blocage commence a 23h00 (vacances)'

# --------------------------------------------------------------------------
Write-Section 'Changements d heure legale'
Assert-Equal 'Blocked' (St '2027-03-28 04:00').State 'nuit du passage a l heure d ete (28/03/2027) : bloque'
Assert-Equal 'Allowed' (St '2027-03-28 06:30').State 'lendemain du passage a l heure d ete : autorise a 06h30'
Assert-Equal 'Blocked' (St '2026-10-25 04:00').State 'nuit du passage a l heure d hiver (25/10/2026) : bloque'

# --------------------------------------------------------------------------
Write-Section 'Sequencement des alertes sonores'
$w7 = @(Get-DodoPendingWarnings (St '2026-09-02 20:53') $cfg @())
Assert-Equal '10' ($w7 -join ',') 'a 7 min restantes, seul le seuil 10 est du'
$w7b = @(Get-DodoPendingWarnings (St '2026-09-02 20:53') $cfg @('10'))
Assert-Equal '' ($w7b -join ',') 'seuil 10 deja emis : rien a rejouer'
$w3 = @(Get-DodoPendingWarnings (St '2026-09-02 20:57') $cfg @('10'))
Assert-Equal '5' ($w3 -join ',') 'a 3 min restantes, le seuil 5 est du'
$wCatchUp = @(Get-DodoPendingWarnings (St '2026-09-02 20:59') $cfg @())
Assert-Equal '10,5,2,1' ($wCatchUp -join ',') 'agent endormi : rattrapage de tous les seuils'
$wNone = @(Get-DodoPendingWarnings (St '2026-09-02 18:00') $cfg @())
Assert-Equal 0 $wNone.Count 'hors preavis : aucune alerte'
$wBlocked = @(Get-DodoPendingWarnings (St '2026-09-02 22:00') $cfg @())
Assert-Equal 0 $wBlocked.Count 'deja bloque : aucune alerte de preavis'

# --------------------------------------------------------------------------
Write-Section 'Substitution dans les messages'
Assert-Equal "Extinction dans 5 minutes, Malo." (Format-DodoMessage 'Extinction dans {minutes} minutes, {name}.' @{ minutes = 5; name = 'Malo' }) 'jetons remplaces'
Assert-Equal "Vacances d'Ete" (ConvertTo-DodoAscii ([char]0x56 + "acances d'" + [char]0xC9 + 't' + [char]0xE9)) 'suppression des diacritiques'

# --------------------------------------------------------------------------
Write-Section 'Fenetre d essai a usage unique'
$cfgT = Resolve-DodoConfig ([pscustomobject]@{ testWindow = [pscustomobject]@{ start = '2026-09-02T14:12:00'; end = '2026-09-02T14:20:00'; label = 'essai' } })
Assert-Equal 'Allowed' (Get-DodoState ([datetime]'2026-09-02 13:00') $cfgT $periods $true).State 'avant le preavis : autorise'
Assert-Equal 'Warning' (Get-DodoState ([datetime]'2026-09-02 14:05') $cfgT $periods $true).State 'dans le preavis de 10 min : alerte'
Assert-Equal 7         (Get-DodoState ([datetime]'2026-09-02 14:05') $cfgT $periods $true).MinutesToBlock '7 minutes restantes'
Assert-Equal 'test'    (Get-DodoState ([datetime]'2026-09-02 14:05') $cfgT $periods $true).WindowKind 'fenetre identifiee comme essai'
Assert-Equal 'Blocked' (Get-DodoState ([datetime]'2026-09-02 14:12') $cfgT $periods $true).State 'debut de la fenetre : bloque'
Assert-Equal 'Blocked' (Get-DodoState ([datetime]'2026-09-02 14:19') $cfgT $periods $true).State 'fin - 1 min : encore bloque'
Assert-Equal 'Allowed' (Get-DodoState ([datetime]'2026-09-02 14:20') $cfgT $periods $true).State 'fenetre expiree : la regle normale reprend'
Assert-Equal 'school'  (Get-DodoState ([datetime]'2026-09-02 14:20') $cfgT $periods $true).WindowKind 'apres expiration : retour a la regle scolaire'
Assert-Equal 'Blocked' (Get-DodoState ([datetime]'2026-09-02 22:00') $cfgT $periods $true).State 'la regle normale reste appliquee le soir'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ testWindow = [pscustomobject]@{ start = '2026-09-02T14:20:00'; end = '2026-09-02T14:12:00' } }) } 'refus fenetre d essai inversee'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ testWindow = [pscustomobject]@{ start = 'demain'; end = 'apres-demain' } }) }                     'refus dates illisibles'

# --------------------------------------------------------------------------
Write-Section 'Non-regression : collections generiques en entree'
# En PowerShell 7, @(...) applique a une System.Collections.Generic.List[object]
# leve "Argument types do not match". Le noyau doit accepter indifferemment un
# tableau, une List[object] ou $null.
$asList = New-Object System.Collections.Generic.List[object]
foreach ($r in $records) { $asList.Add($r) }
$fromList = ConvertFrom-DodoCalendarRecords -Records $asList -Config $cfg -TimeZone $tz
Assert-Equal $periods.Count $fromList.Periods.Count 'List[object] en entree donne le meme resultat qu un tableau'
Assert-Equal 2 $fromList.Warnings.Count            'List[object] : avertissements identiques'
$fromNull = ConvertFrom-DodoCalendarRecords -Records $null -Config $cfg -TimeZone $tz
Assert-Equal 0 $fromNull.Periods.Count             'entree $null toleree'
$periodsList = New-Object System.Collections.Generic.List[object]
foreach ($p in $periods) { $periodsList.Add($p) }
Assert-Equal $true (Test-DodoVacationDate ([datetime]'2026-10-20') $periodsList) 'List[object] de periodes acceptee'
$st = Get-DodoState ([datetime]'2026-10-20 22:00') $cfg $periodsList $true
Assert-Equal 'Allowed' $st.State 'Get-DodoState accepte une List[object] de periodes'

# --------------------------------------------------------------------------
Write-Section 'Non-regression : transmission des reglages a l installateur'
# powershell.exe -File ne reinterprete pas les quotes PowerShell. En production,
# "-AllowedAdapterName 'Ethernet 2','Wi-Fi'" etait decoupe sur l'espace et le
# jeton "2','Wi-Fi'" se liait au premier parametre POSITIONNEL, -InstallPath :
# l'installation partait dans un dossier nomme 2','Wi-Fi'. Meme cause pour
# "-NotifyUser 'Malo'", dont les apostrophes cassaient la resolution du compte.
$srcDir    = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
$installer = Join-Path $srcDir 'Install-Dodo.ps1'
$pdSauve = $env:ProgramData
if ([string]::IsNullOrEmpty($env:ProgramData)) { $env:ProgramData = [System.IO.Path]::GetTempPath() }

function Invoke-Installer {
    param([hashtable]$Parametres)
    try { & $installer @Parametres | Out-Null; return '' }
    catch { return $_.Exception.Message }
}

Assert-Equal $true ((Invoke-Installer @{ InstallPath = "2','Wi-Fi'"; ValidateOnly = $true }) -like "*Chemin d'installation invalide*") 'chemin issu d un debordement de parametre refuse'
Assert-Equal $true ((Invoke-Installer @{ InstallPath = 'dodo'; ValidateOnly = $true })       -like "*Chemin d'installation invalide*") 'chemin relatif refuse'
Assert-Equal $true ((Invoke-Installer @{ InstallPath = ([System.IO.Path]::GetTempPath() + 'D'); NotifyUser = "'Malo'"; ValidateOnly = $true }) -like '*Nom de compte invalide*') 'compte porteur d apostrophes refuse'

# Chemin nominal : une fiche de reponses contenant justement des valeurs a
# espaces doit etre lue sans encombre, jusqu'au controle de plateforme.
$fiche = Join-Path ([System.IO.Path]::GetTempPath()) 'dodo-reponses-test.json'
$reponses = [pscustomobject]@{
    InstallPath        = (Join-Path ([System.IO.Path]::GetTempPath()) 'DodoTest')
    NotifyUser         = 'Malo'
    ExemptUsers        = @('Papa', 'Maman')
    AllowedSsid        = @('Ma Box 5G')
    AllowedAdapterName = @('Ethernet 2', 'Wi-Fi')
    EnableAdapterGuard = $true
    Production         = $false
    Speech             = [pscustomobject]@{ voiceName = 'Microsoft Denise'; repeatEverySeconds = 15 }
    Messages           = [pscustomobject]@{ warning = 'Malo, extinction dans {minutes} minutes.' }
}
[System.IO.File]::WriteAllText($fiche, ($reponses | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))
$sortie = ''
try { $sortie = (& $installer -AnswerFile $fiche -ValidateOnly 2>&1 | Out-String) } catch { $sortie = $_.Exception.Message }
$lu = $null
try { $lu = ($sortie.Trim() | ConvertFrom-Json) } catch { }
Assert-Equal $true ($null -ne $lu) 'fiche de reponses lue et parametres restitues'
if ($null -ne $lu) {
    Assert-Equal 'Malo'       $lu.NotifyUser                       'compte transmis sans apostrophes parasites'
    Assert-Equal 2            @($lu.AllowedAdapterName).Count      'les DEUX noms de carte arrivent entiers'
    Assert-Equal 'Ethernet 2' @($lu.AllowedAdapterName)[0]         'le nom a espace n est pas coupe'
    Assert-Equal 'Wi-Fi'      @($lu.AllowedAdapterName)[1]         'le second nom de carte est intact'
    Assert-Equal 'Ma Box 5G'  @($lu.AllowedSsid)[0]                'le SSID a espaces arrive entier'
    Assert-Equal 2            @($lu.ExemptUsers).Count             'les comptes exemptes arrivent tous'
    Assert-Equal $true        ($lu.InstallPath -notlike '*Wi-Fi*') 'aucun debordement vers -InstallPath'
    Assert-Equal 'Microsoft Denise' $lu.VoiceName                  'la voix choisie par le parent est transmise'
    Assert-Equal 15                 $lu.RepeatEverySeconds         'la cadence de repetition est transmise'
    Assert-Equal 'Malo, extinction dans {minutes} minutes.' $lu.WarningText 'le texte ecrit par le parent arrive entier'
    # @($null) vaut 1 : le diagnostic doit compter zero, pas un fantome.
    Assert-Equal 0            $lu.HolidayCount                     'aucune periode transmise : le rapport annonce zero'
}
Assert-Equal $true  ((Invoke-Installer @{ AnswerFile = '/introuvable.json'; ValidateOnly = $true }) -like '*introuvable*') 'fiche de reponses absente signalee'
Remove-Item -LiteralPath $fiche -Force -ErrorAction SilentlyContinue
$env:ProgramData = $pdSauve

# --------------------------------------------------------------------------
Write-Section 'Calendrier saisi a la main (reseau indisponible)'
. (Join-Path $srcDir 'DodoRuntime.ps1')
$rootTmp = Join-Path ([System.IO.Path]::GetTempPath()) ('dodo-cal-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path (Join-Path $rootTmp 'var') -Force | Out-Null

# Aucun cache API : seule une periode saisie a la main est disponible. Elle
# doit faire autorite, sinon le repli scolaire s'appliquerait toute l'annee
# sur un poste sans acces au calendrier officiel.
$cfgM = Resolve-DodoConfig ([pscustomobject]@{ calendar = [pscustomobject]@{ overrides = @(
    [pscustomobject]@{ label = 'Toussaint'; start = '2026-10-17'; endExclusive = '2026-11-02' }) } })
$calM = Get-DodoCalendar -Config $cfgM -Root $rootTmp -Now ([datetime]'2026-10-20 12:00')
Assert-Equal $true  $calM.Trusted        'sans cache API, une periode manuelle a venir rend le calendrier fiable'
Assert-Equal 1      $calM.OverrideCount  'la periode manuelle est bien chargee'
Assert-Equal 0      $calM.ApiCount       'aucune periode issue de l API'
Assert-Equal 'Allowed' (Get-DodoState ([datetime]'2026-10-20 22:00') $cfgM $calM.Periods $calM.Trusted).State 'vacances manuelles : 22h00 autorise'
Assert-Equal 'Blocked' (Get-DodoState ([datetime]'2026-10-20 23:00') $cfgM $calM.Periods $calM.Trusted).State 'vacances manuelles : 23h00 bloque'
Assert-Equal 'Blocked' (Get-DodoState ([datetime]'2026-11-03 21:30') $cfgM $calM.Periods $calM.Trusted).State 'apres la rentree : retour a 21h00'

# Une periode entierement passee ne prouve rien : on retombe sur le repli strict.
$cfgP = Resolve-DodoConfig ([pscustomobject]@{ calendar = [pscustomobject]@{ overrides = @(
    [pscustomobject]@{ label = 'Ancienne'; start = '2020-01-01'; endExclusive = '2020-01-10' }) } })
$calP = Get-DodoCalendar -Config $cfgP -Root $rootTmp -Now ([datetime]'2026-10-20 12:00')
Assert-Equal $false $calP.Trusted 'une periode manuelle entierement passee ne rend pas le calendrier fiable'

# Mode hors ligne assume : les periodes manuelles suffisent, sans aucun reseau.
$cfgO = Resolve-DodoConfig ([pscustomobject]@{ calendar = [pscustomobject]@{ offlineOnly = $true; overrides = @(
    [pscustomobject]@{ label = 'Noel'; start = '2026-12-19'; endExclusive = '2027-01-04' }) } })
$calO = Get-DodoCalendar -Config $cfgO -Root $rootTmp -Now ([datetime]'2026-12-20 12:00')
Assert-Equal $true $calO.Trusted 'mode hors ligne avec periodes saisies : calendrier fiable'
Assert-Equal 'Allowed' (Get-DodoState ([datetime]'2026-12-20 22:30') $cfgO $calO.Periods $calO.Trusted).State 'hors ligne, vacances de Noel : 22h30 autorise'
Remove-Item -LiteralPath $rootTmp -Recurse -Force -ErrorAction SilentlyContinue

# --------------------------------------------------------------------------
Write-Section 'Voix : reglages et cadence de repetition'

# --- valeurs par defaut
$cfgV = Resolve-DodoConfig ([pscustomobject]@{})
Assert-Equal $true   $cfgV.speech.enabled            'voix active par defaut'
Assert-Equal 'auto'  $cfgV.speech.engine             'moteur automatique par defaut'
Assert-Equal ''      $cfgV.speech.voiceName          'aucune voix imposee par defaut'
Assert-Equal 20      $cfgV.speech.repeatEverySeconds 'repetition toutes les 20 s par defaut'
Assert-Equal 25      $cfgV.speech.displaySeconds     'fenetre affichee 25 s par defaut'

# --- fusion partielle : on ne change qu'un reglage, les autres tiennent
$cfgV2 = Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ voiceName = 'Microsoft Denise' } })
Assert-Equal 'Microsoft Denise' $cfgV2.speech.voiceName          'voix imposee prise en compte'
Assert-Equal 20                 $cfgV2.speech.repeatEverySeconds 'les autres reglages de voix restent par defaut'

# --- le nom du moteur est normalise : l'assistant peut ecrire 'OneCore'
$cfgV3 = Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ engine = 'OneCore' } })
Assert-Equal 'onecore' $cfgV3.speech.engine 'moteur normalise en minuscules'

# --- validations
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ engine = 'siri' } }) }              'refus d un moteur inconnu'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ rate = 42 } }) }                    'refus d un debit hors bornes'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ volume = 300 } }) }                 'refus d un volume hors bornes'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ repeatEverySeconds = -1 } }) }      'refus d une cadence negative'
Assert-Throws { Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ displaySeconds = 2 } }) }           'refus d un affichage trop bref'
# 'off' est un moteur valide : c'est ainsi que le parent coupe la voix.
$cfgOff = Resolve-DodoConfig ([pscustomobject]@{ speech = [pscustomobject]@{ engine = 'off' } })
Assert-Equal 'off' $cfgOff.speech.engine 'moteur off accepte : la voix se desactive'

# --- cadence de diffusion pendant l affichage
$p1 = @(Get-DodoSpeechPlan -DisplaySeconds 25 -RepeatEverySeconds 20)
Assert-Equal 2  $p1.Count 'fenetre de 25 s, cadence 20 s : deux diffusions'
Assert-Equal 0  $p1[0]    'la premiere diffusion a lieu des l affichage'
Assert-Equal 20 $p1[1]    'la seconde a 20 s'

$p2 = @(Get-DodoSpeechPlan -DisplaySeconds 60 -RepeatEverySeconds 15)
Assert-Equal 4  $p2.Count 'fenetre de 60 s, cadence 15 s : quatre diffusions'
Assert-Equal 45 $p2[3]    'la derniere a 45 s'
# 60 s pile ne serait pas entendu : la fenetre se ferme au meme instant.
Assert-Equal $false ($p2 -contains 60) 'aucune diffusion a l instant exact de la fermeture'

$p3 = @(Get-DodoSpeechPlan -DisplaySeconds 25 -RepeatEverySeconds 0)
Assert-Equal 1 $p3.Count 'cadence a zero : une seule diffusion'
Assert-Equal 0 $p3[0]    'et c est celle de l affichage'

$p4 = @(Get-DodoSpeechPlan -DisplaySeconds 25 -RepeatEverySeconds 40)
Assert-Equal 1 $p4.Count 'cadence plus longue que l affichage : une seule diffusion'

# Garde-fou : une cadence de 1 s sur une longue fenetre ne doit pas produire
# des centaines de diffusions.
$p5 = @(Get-DodoSpeechPlan -DisplaySeconds 300 -RepeatEverySeconds 1)
Assert-Equal $true ($p5.Count -le 21) 'nombre de diffusions plafonne'

# Le message final suit le sursis d extinction, pas la duree des preavis.
$p6 = @(Get-DodoSpeechPlan -DisplaySeconds 30 -RepeatEverySeconds 20)
Assert-Equal 2 $p6.Count 'sursis de 30 s : deux diffusions du message final'

# --- le texte prononce est bien celui du parent, jetons substitues
$perso = 'Malo, il est temps. Extinction dans {minutes} minutes.'
Assert-Equal 'Malo, il est temps. Extinction dans 10 minutes.' `
    (Format-DodoMessage $perso @{ minutes = 10; name = 'Malo' }) 'texte personnalise du parent, jetons substitues'

# --------------------------------------------------------------------------
Write-Section 'Variables de portee script masquees par une locale (casse)'
# Les noms de variables PowerShell sont INSENSIBLES A LA CASSE. Une variable
# assignee au premier niveau du script (colonne 0) est de portee script ; si
# une locale ne differant que par la casse est assignee ailleurs, elle la
# masque en silence. Deux defauts reels sont nes de ce piege :
#   - $src local dans Get-DodoHorairesInitiales masquait $SRC (racine des
#     sources) : l'assistant mourait au chargement, sans aucun message, et
#     l'installateur "ne se lancait pas" ;
#   - $partage local dans Get-Adapters masquait le motif $PARTAGE : des la
#     deuxieme carte le motif valait "False", plus aucune voie de partage
#     n'etait detectee et le Bluetooth PAN etait autorise d'office.
$srcDir2 = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
foreach ($f in (Get-ChildItem -Path $srcDir2 -Filter '*.ps1' -File | Sort-Object Name)) {
    $lignes = [System.IO.File]::ReadAllLines($f.FullName)
    # -cne, PAS -ne : l'operateur -ne de PowerShell est INSENSIBLE A LA CASSE,
    # donc 'partage' -ne 'PARTAGE' vaut $false et le controle ne verrait rien.
    # Ce test est tombe dans le piege qu'il verifie ; d'ou cette note.
    $portees = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($l in $lignes) {
        $m = [regex]::Match($l, '^\$([A-Za-z_][A-Za-z0-9_]*)\s*=')
        if ($m.Success) { [void]$portees.Add($m.Groups[1].Value) }
    }
    $conflits = New-Object System.Collections.Generic.List[string]
    foreach ($l in $lignes) {
        foreach ($m in [regex]::Matches($l, '\$([A-Za-z_][A-Za-z0-9_]*)\s*=')) {
            $nom = $m.Groups[1].Value
            foreach ($g in $portees) {
                if ($nom -cne $g -and $nom.ToLowerInvariant() -eq $g.ToLowerInvariant()) {
                    $conflits.Add(('$' + $nom + ' masque $' + $g))
                }
            }
        }
    }
    Assert-Equal 0 (@($conflits | Sort-Object -Unique).Count) `
        ("$($f.Name) : aucune locale ne masque une variable de portee script" +
         $(if ($conflits.Count) { ' -> ' + (($conflits | Sort-Object -Unique) -join ', ') } else { '' }))
}

# --------------------------------------------------------------------------
Write-Section 'Purete ASCII des sources (accents interdits hors messages JSON)'
$srcDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'src'
# Regle : un .ps1 est soit en ASCII pur, soit en UTF-8 AVEC BOM. Sans BOM,
# Windows PowerShell 5.1 lit le fichier en ANSI et casse les accents.
foreach ($f in (Get-ChildItem -Path $srcDir, $PSScriptRoot -Filter '*.ps1' -File)) {
    $bytes  = [System.IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $bad    = @($bytes | Where-Object { $_ -gt 127 }).Count
    if ($hasBom) {
        Assert-Equal $true $true ("$($f.Name) : UTF-8 avec BOM, accents autorises")
    }
    else {
        Assert-Equal 0 $bad ("$($f.Name) : ASCII pur (pas de BOM, donc pas d'accent possible)")
    }
}

# --------------------------------------------------------------------------
Write-Host ''
Write-Host ('-' * 70)
if ($script:Fail -eq 0) {
    Write-Host ("RESULTAT : {0} tests reussis, 0 echec." -f $script:Pass) -ForegroundColor Green
    exit 0
}
Write-Host ("RESULTAT : {0} reussis, {1} ECHECS." -f $script:Pass, $script:Fail) -ForegroundColor Red
foreach ($f in $script:Failures) { Write-Host "  - $f" -ForegroundColor Red }
exit 1
