#Requires -Version 5.1
<#
    DodoCore.ps1 - Noyau de decision du couvre-feu "Dodo".

    Ce fichier ne contient QUE des fonctions pures (aucun arret, aucune ecriture,
    aucun appel reseau). Il est donc executable et testable sur n'importe quelle
    plateforme (Windows PowerShell 5.1, PowerShell 7 Linux/macOS).

    Convention du depot : source ASCII pur. Tous les textes francais accentues
    vivent dans dodo.messages.json, lu en UTF-8 explicite.
#>

Set-StrictMode -Version 2.0

# --------------------------------------------------------------------------
# Utilitaires
# --------------------------------------------------------------------------

function Get-DodoProp {
    <# Lit une propriete d'un PSCustomObject/Hashtable sans exploser si absente. #>
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [System.Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $p = $Object.PSObject.Properties[$Name]
    if ($null -eq $p -or $null -eq $p.Value) { return $Default }
    return $p.Value
}

function ConvertTo-DodoAscii {
    <# Retire les diacritiques : "Vacances d'Ete" depuis "Vacances d'Ete" accentue. #>
    param([string]$Text)
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $d = $Text.Normalize([System.Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $d.ToCharArray()) {
        if ([System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    return $sb.ToString()
}

function ConvertTo-DodoTimeSpan {
    <# "21:00" -> [TimeSpan]. Rejette tout format non conforme. #>
    param([Parameter(Mandatory = $true)][string]$Text)
    $m = [regex]::Match($Text, '^(?<h>[01][0-9]|2[0-3]):(?<m>[0-5][0-9])$')
    if (-not $m.Success) {
        throw "Heure invalide '$Text' : format attendu HH:mm entre 00:00 et 23:59."
    }
    return (New-Object System.TimeSpan ([int]$m.Groups['h'].Value), ([int]$m.Groups['m'].Value), 0)
}

function Get-DodoParisTimeZone {
    <# Fuseau Europe/Paris : identifiant Windows puis identifiant IANA. #>
    foreach ($id in @('Romance Standard Time', 'Europe/Paris')) {
        try { return [System.TimeZoneInfo]::FindSystemTimeZoneById($id) } catch { }
    }
    return [System.TimeZoneInfo]::Local
}

function ConvertTo-DodoParisDate {
    <#
        Convertit un horodatage ISO du jeu de donnees education.gouv.fr en DATE
        civile a Paris. Les bornes du jeu de donnees sont des minuits de Paris
        exprimes en UTC (ex. 2026-10-16T22:00:00+00:00 = 17/10/2026 00:00 a Paris).
    #>
    param([Parameter(Mandatory = $true)][string]$Iso, $TimeZone = $null)
    if ($null -eq $TimeZone) { $TimeZone = Get-DodoParisTimeZone }
    $dto = [System.DateTimeOffset]::Parse(
        $Iso,
        [System.Globalization.CultureInfo]::InvariantCulture,
        [System.Globalization.DateTimeStyles]::AssumeUniversal)
    return ([System.TimeZoneInfo]::ConvertTime($dto, $TimeZone)).Date
}

# --------------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------------

function New-DodoDefaultConfig {
    return [pscustomobject]@{
        enabled                 = $true
        dryRun                  = $false
        zone                    = 'Zone C'
        schedule                = [pscustomobject]@{
            school  = [pscustomobject]@{ start = '21:00'; end = '06:30' }
            holiday = [pscustomobject]@{ start = '23:00'; end = '06:30' }
        }
        warningMinutes          = @(10, 5, 2, 1)
        shutdownGraceSeconds    = 30
        bootGraceSeconds        = 90
        strictNightBeforeReturn = $true
        lateEveningsDuringTerm  = @()
        exemptUsers             = @()
        calendar                = [pscustomobject]@{
            apiUrl              = 'https://data.education.gouv.fr/api/explore/v2.1/catalog/datasets/fr-en-calendrier-scolaire/records'
            maxCacheAgeDays     = 21
            excludePopulations  = @('Enseignants')
            openEndedSummerEnd  = '09-01'
            overrides           = @()
        }
        adapterGuard            = [pscustomobject]@{ enabled = $false; allowedPnpDeviceIds = @() }
        wifi                    = [pscustomobject]@{ enforceSsidFilter = $false; allowedSsids = @() }
        speech                  = [pscustomobject]@{
            enabled            = $true
            engine             = 'auto'
            voiceName          = ''
            rate               = 0
            volume             = 100
            repeatEverySeconds = 20
            displaySeconds     = 25
        }
        testWindow              = $null
    }
}

function Resolve-DodoConfig {
    <# Fusionne un objet de configuration partiel avec les valeurs par defaut, puis valide. #>
    param($UserConfig)

    $d = New-DodoDefaultConfig
    if ($null -eq $UserConfig) { $UserConfig = [pscustomobject]@{} }

    $sched = Get-DodoProp $UserConfig 'schedule'
    $cal   = Get-DodoProp $UserConfig 'calendar'
    $ag    = Get-DodoProp $UserConfig 'adapterGuard'
    $wifi  = Get-DodoProp $UserConfig 'wifi'
    $sp    = Get-DodoProp $UserConfig 'speech'

    $cfg = [pscustomobject]@{
        enabled                 = [bool](Get-DodoProp $UserConfig 'enabled' $d.enabled)
        dryRun                  = [bool](Get-DodoProp $UserConfig 'dryRun' $d.dryRun)
        zone                    = [string](Get-DodoProp $UserConfig 'zone' $d.zone)
        schedule                = [pscustomobject]@{
            school  = [pscustomobject]@{
                start = [string](Get-DodoProp (Get-DodoProp $sched 'school') 'start' $d.schedule.school.start)
                end   = [string](Get-DodoProp (Get-DodoProp $sched 'school') 'end'   $d.schedule.school.end)
            }
            holiday = [pscustomobject]@{
                start = [string](Get-DodoProp (Get-DodoProp $sched 'holiday') 'start' $d.schedule.holiday.start)
                end   = [string](Get-DodoProp (Get-DodoProp $sched 'holiday') 'end'   $d.schedule.holiday.end)
            }
        }
        warningMinutes          = @(Get-DodoProp $UserConfig 'warningMinutes' $d.warningMinutes)
        shutdownGraceSeconds    = [int](Get-DodoProp $UserConfig 'shutdownGraceSeconds' $d.shutdownGraceSeconds)
        bootGraceSeconds        = [int](Get-DodoProp $UserConfig 'bootGraceSeconds' $d.bootGraceSeconds)
        strictNightBeforeReturn = [bool](Get-DodoProp $UserConfig 'strictNightBeforeReturn' $d.strictNightBeforeReturn)
        lateEveningsDuringTerm  = @(Get-DodoProp $UserConfig 'lateEveningsDuringTerm' $d.lateEveningsDuringTerm)
        exemptUsers             = @(Get-DodoProp $UserConfig 'exemptUsers' $d.exemptUsers)
        calendar                = [pscustomobject]@{
            apiUrl             = [string](Get-DodoProp $cal 'apiUrl' $d.calendar.apiUrl)
            maxCacheAgeDays    = [int](Get-DodoProp $cal 'maxCacheAgeDays' $d.calendar.maxCacheAgeDays)
            excludePopulations = @(Get-DodoProp $cal 'excludePopulations' $d.calendar.excludePopulations)
            openEndedSummerEnd = [string](Get-DodoProp $cal 'openEndedSummerEnd' $d.calendar.openEndedSummerEnd)
            overrides          = @(Get-DodoProp $cal 'overrides' $d.calendar.overrides)
        }
        adapterGuard            = [pscustomobject]@{
            enabled             = [bool](Get-DodoProp $ag 'enabled' $d.adapterGuard.enabled)
            allowedPnpDeviceIds = @(Get-DodoProp $ag 'allowedPnpDeviceIds' $d.adapterGuard.allowedPnpDeviceIds)
        }
        wifi                    = [pscustomobject]@{
            enforceSsidFilter = [bool](Get-DodoProp $wifi 'enforceSsidFilter' $d.wifi.enforceSsidFilter)
            allowedSsids      = @(Get-DodoProp $wifi 'allowedSsids' $d.wifi.allowedSsids)
        }
        speech                  = [pscustomobject]@{
            enabled            = [bool](Get-DodoProp $sp 'enabled' $d.speech.enabled)
            engine             = ([string](Get-DodoProp $sp 'engine' $d.speech.engine)).ToLowerInvariant()
            voiceName          = [string](Get-DodoProp $sp 'voiceName' $d.speech.voiceName)
            rate               = [int](Get-DodoProp $sp 'rate' $d.speech.rate)
            volume             = [int](Get-DodoProp $sp 'volume' $d.speech.volume)
            repeatEverySeconds = [int](Get-DodoProp $sp 'repeatEverySeconds' $d.speech.repeatEverySeconds)
            displaySeconds     = [int](Get-DodoProp $sp 'displaySeconds' $d.speech.displaySeconds)
        }
        testWindow              = (Get-DodoProp $UserConfig 'testWindow')
    }

    # --- Validation stricte : mieux vaut refuser que se comporter n'importe comment
    foreach ($kind in @('school', 'holiday')) {
        $w     = $cfg.schedule.$kind
        $start = ConvertTo-DodoTimeSpan $w.start
        $end   = ConvertTo-DodoTimeSpan $w.end
        if ($start -le $end) {
            throw "schedule.$kind : l'heure de debut ($($w.start)) doit etre posterieure a l'heure de fin ($($w.end)) - la fenetre doit passer minuit."
        }
    }
    if ($cfg.warningMinutes.Count -eq 0) {
        throw "warningMinutes ne peut pas etre vide."
    }
    foreach ($m in $cfg.warningMinutes) {
        if ([int]$m -le 0) { throw "warningMinutes : '$m' doit etre un entier strictement positif." }
    }
    if ($cfg.shutdownGraceSeconds -lt 0 -or $cfg.shutdownGraceSeconds -gt 600) {
        throw "shutdownGraceSeconds doit etre compris entre 0 et 600."
    }
    if ($cfg.bootGraceSeconds -lt 0 -or $cfg.bootGraceSeconds -gt 600) {
        throw "bootGraceSeconds doit etre compris entre 0 et 600."
    }
    if ($cfg.calendar.openEndedSummerEnd -notmatch '^(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$') {
        throw "calendar.openEndedSummerEnd doit etre au format MM-JJ (ex. 09-01)."
    }
    $moteursConnus = @('auto', 'onecore', 'sapi', 'wav', 'off')
    if ($cfg.speech.engine -notin $moteursConnus) {
        throw ("speech.engine : '{0}' inconnu. Valeurs admises : {1}." -f $cfg.speech.engine, ($moteursConnus -join ', '))
    }
    if ($cfg.speech.rate -lt -10 -or $cfg.speech.rate -gt 10) {
        throw "speech.rate doit etre compris entre -10 (tres lent) et 10 (tres rapide)."
    }
    if ($cfg.speech.volume -lt 0 -or $cfg.speech.volume -gt 100) {
        throw "speech.volume doit etre compris entre 0 et 100."
    }
    if ($cfg.speech.repeatEverySeconds -lt 0 -or $cfg.speech.repeatEverySeconds -gt 300) {
        throw "speech.repeatEverySeconds doit etre compris entre 0 (aucune repetition) et 300."
    }
    if ($cfg.speech.displaySeconds -lt 5 -or $cfg.speech.displaySeconds -gt 300) {
        throw "speech.displaySeconds doit etre compris entre 5 et 300."
    }

    if ($null -ne $cfg.testWindow) {
        $tw = Get-DodoTestWindow $cfg   # leve si mal forme
        if ($null -eq $tw) { throw "testWindow present mais illisible : 'start' et 'end' doivent etre des dates completes (ex. 2026-09-02T21:12:00)." }
    }

    return $cfg
}

# --------------------------------------------------------------------------
# Calendrier : periodes de vacances
# --------------------------------------------------------------------------

function New-DodoPeriod {
    param(
        [Parameter(Mandatory = $true)][datetime]$Start,
        [Parameter(Mandatory = $true)][datetime]$EndExclusive,
        [string]$Label = '',
        [string]$Origin = 'api'
    )
    return [pscustomobject]@{
        Label        = $Label
        Start        = $Start.Date
        EndExclusive = $EndExclusive.Date
        Origin       = $Origin
    }
}

function ConvertFrom-DodoCalendarRecords {
    <#
        Transforme les enregistrements bruts de l'API "fr-en-calendrier-scolaire"
        en periodes exploitables.

        Semantique verifiee sur les donnees reelles :
          start_date = minuit (Paris) du PREMIER jour de vacances
          end_date   = minuit (Paris) du jour de la RENTREE (donc borne EXCLUE)

        Pieges reels presents dans le jeu de donnees et traites ici :
          - population = "Enseignants" (dates differentes) -> exclu par configuration
          - enregistrements a duree nulle (start_date = end_date), ex. "Pont de
            l'Ascension" 2026-2027 -> ignores, avec avertissement
          - "Debut des Vacances d'Ete" sans date de fin publiee -> fin deduite
            (calendar.openEndedSummerEnd), avec avertissement
    #>
    param(
        $Records,
        [Parameter(Mandatory = $true)]$Config,
        $TimeZone = $null
    )
    if ($null -eq $TimeZone) { $TimeZone = Get-DodoParisTimeZone }

    $periods  = New-Object System.Collections.Generic.List[object]
    $warnings = New-Object System.Collections.Generic.List[string]
    $excluded = @($Config.calendar.excludePopulations | ForEach-Object { (ConvertTo-DodoAscii $_).ToLowerInvariant() })

    $seen  = New-Object 'System.Collections.Generic.HashSet[string]'
    $items = New-Object System.Collections.Generic.List[object]
    if ($null -ne $Records) { foreach ($x in $Records) { $items.Add($x) } }

    foreach ($r in $items) {
        $desc = ConvertTo-DodoAscii ([string](Get-DodoProp $r 'description' ''))
        $pop  = ConvertTo-DodoAscii ([string](Get-DodoProp $r 'population' ''))
        $sIso = [string](Get-DodoProp $r 'start_date' '')
        $eIso = [string](Get-DodoProp $r 'end_date' '')

        if ([string]::IsNullOrWhiteSpace($sIso)) { continue }
        if ($excluded -contains $pop.ToLowerInvariant()) { continue }

        try   { $start = ConvertTo-DodoParisDate -Iso $sIso -TimeZone $TimeZone }
        catch { $warnings.Add("Date de debut illisible pour '$desc' : '$sIso'."); continue }

        $end = $null
        if (-not [string]::IsNullOrWhiteSpace($eIso)) {
            try   { $end = ConvertTo-DodoParisDate -Iso $eIso -TimeZone $TimeZone }
            catch { $warnings.Add("Date de fin illisible pour '$desc' : '$eIso'.") }
        }

        if ($null -eq $end -or $end -le $start) {
            if ($desc -match "Vacances d'Ete") {
                $mmdd = $Config.calendar.openEndedSummerEnd.Split('-')
                $end  = New-Object datetime ($start.Year), ([int]$mmdd[0]), ([int]$mmdd[1])
                if ($end -le $start) { $end = $end.AddYears(1) }
                $warnings.Add("Periode '$desc' sans date de fin publiee : fin deduite au $($end.ToString('yyyy-MM-dd')) (calendar.openEndedSummerEnd).")
            }
            else {
                $warnings.Add("Periode '$desc' ignoree (duree nulle ou fin absente dans la source : $sIso -> $eIso).")
                continue
            }
        }

        # La zone C compte cinq academies : le meme creneau revient donc cinq fois.
        $key = '{0}|{1}|{2}' -f $desc, $start.ToString('yyyy-MM-dd'), $end.ToString('yyyy-MM-dd')
        if (-not $seen.Add($key)) { continue }

        $periods.Add((New-DodoPeriod -Start $start -EndExclusive $end -Label $desc -Origin 'api'))
    }

    # Ajouts manuels verifies par l'administrateur (priment jamais, s'ajoutent)
    foreach ($o in @($Config.calendar.overrides)) {
        $os = [string](Get-DodoProp $o 'start' '')
        $oe = [string](Get-DodoProp $o 'endExclusive' '')
        $ol = [string](Get-DodoProp $o 'label' 'override')
        if ([string]::IsNullOrWhiteSpace($os) -or [string]::IsNullOrWhiteSpace($oe)) {
            $warnings.Add("Override '$ol' ignore : 'start' et 'endExclusive' (AAAA-MM-JJ) sont obligatoires.")
            continue
        }
        try {
            $ds = [datetime]::ParseExact($os, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
            $de = [datetime]::ParseExact($oe, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        catch { $warnings.Add("Override '$ol' ignore : dates illisibles ('$os', '$oe')."); continue }
        if ($de -le $ds) { $warnings.Add("Override '$ol' ignore : endExclusive doit etre posterieur a start."); continue }
        $periods.Add((New-DodoPeriod -Start $ds -EndExclusive $de -Label $ol -Origin 'override'))
    }

    return [pscustomobject]@{
        Periods  = @($periods | Sort-Object Start)
        Warnings = $warnings.ToArray()
    }
}

function Test-DodoVacationDate {
    <# Vrai si la DATE fournie est un jour de vacances (borne de fin exclue). #>
    param([Parameter(Mandatory = $true)][datetime]$Date, $Periods)
    $d = $Date.Date
    foreach ($p in $Periods) {
        if ($null -eq $p) { continue }
        if ($d -ge $p.Start -and $d -lt $p.EndExclusive) { return $true }
    }
    return $false
}

# --------------------------------------------------------------------------
# Decision
# --------------------------------------------------------------------------

function Get-DodoTestWindow {
    <#
        Fenetre d'essai absolue et ponctuelle, posee par le test bout-en-bout
        pour verifier une VRAIE extinction sans dependre de l'heure du jour.

        Elle est volontairement a usage unique : l'agent la supprime de la
        configuration des qu'elle a declenche une extinction reelle, de sorte
        qu'un redemarrage ne puisse jamais rester pris au piege.
    #>
    param($Config)
    $tw = Get-DodoProp $Config 'testWindow'
    if ($null -eq $tw) { return $null }
    $s = [string](Get-DodoProp $tw 'start' '')
    $e = [string](Get-DodoProp $tw 'end' '')
    if ([string]::IsNullOrWhiteSpace($s) -or [string]::IsNullOrWhiteSpace($e)) { return $null }
    try {
        $ds = [datetime]::Parse($s, [System.Globalization.CultureInfo]::InvariantCulture)
        $de = [datetime]::Parse($e, [System.Globalization.CultureInfo]::InvariantCulture)
    }
    catch { return $null }
    if ($de -le $ds) { return $null }
    return [pscustomobject]@{ Start = $ds; End = $de; Label = [string](Get-DodoProp $tw 'label' 'fenetre d essai') }
}

function Get-DodoNightWindow {
    <#
        Determine la fenetre d'extinction applicable a la nuit qui COMMENCE le
        soir de $EveningDate.

        Regles :
          - vacances scolaires zone C -> fenetre "holiday" (23:00)
          - periode scolaire          -> fenetre "school"  (21:00)
          - si strictNightBeforeReturn : la derniere nuit des vacances (veille de
            la rentree) repasse en fenetre "school"
          - si le calendrier n'est pas fiable (absent / perime / illisible) :
            repli sur "school", c'est-a-dire la regle la PLUS stricte
    #>
    param(
        [Parameter(Mandatory = $true)][datetime]$EveningDate,
        [Parameter(Mandatory = $true)]$Config,
        $Periods = @(),
        [bool]$CalendarTrusted = $true
    )

    $kind   = 'school'
    $reason = 'periode scolaire'

    if (-not $CalendarTrusted) {
        $reason = 'calendrier indisponible - repli securitaire sur la regle scolaire'
    }
    else {
        $e = $EveningDate.Date
        if (Test-DodoVacationDate -Date $e -Periods $Periods) {
            if ($Config.strictNightBeforeReturn -and -not (Test-DodoVacationDate -Date $e.AddDays(1) -Periods $Periods)) {
                $reason = 'derniere nuit des vacances (veille de rentree) - regle scolaire'
            }
            else {
                $kind   = 'holiday'
                $reason = 'vacances scolaires ' + $Config.zone
            }
        }
        elseif (@($Config.lateEveningsDuringTerm) -contains $e.DayOfWeek.ToString()) {
            $kind   = 'holiday'
            $reason = 'soir sans ecole le lendemain (lateEveningsDuringTerm)'
        }
    }

    $w = $Config.schedule.$kind
    return [pscustomobject]@{
        Kind      = $kind
        Reason    = $reason
        StartTime = ConvertTo-DodoTimeSpan $w.start
        EndTime   = ConvertTo-DodoTimeSpan $w.end
    }
}

function Get-DodoState {
    <#
        Etat du poste a l'instant $Now.
        Retourne State = 'Blocked' | 'Warning' | 'Allowed'.

        Deux nuits candidates sont evaluees : celle commencee la veille au soir
        (dont la fin deborde sur aujourd'hui) et celle qui commence ce soir.
    #>
    param(
        [Parameter(Mandatory = $true)][datetime]$Now,
        [Parameter(Mandatory = $true)]$Config,
        $Periods = @(),
        [bool]$CalendarTrusted = $true
    )

    # Fenetre d'essai : prioritaire tant qu'elle n'est pas expiree.
    $tw = Get-DodoTestWindow $Config
    if ($null -ne $tw -and $Now -lt $tw.End) {
        if ($Now -ge $tw.Start) {
            return [pscustomobject]@{
                State = 'Blocked'; Now = $Now; WindowKind = 'test'; Reason = $tw.Label
                BlockStart = $tw.Start; BlockEnd = $tw.End
                MinutesToBlock = 0
                MinutesToUnblock = [int][math]::Ceiling(($tw.End - $Now).TotalMinutes)
                CalendarTrusted = $CalendarTrusted
            }
        }
        $lead0 = [int](@($Config.warningMinutes) | Measure-Object -Maximum).Maximum
        $mins0 = ($tw.Start - $Now).TotalMinutes
        return [pscustomobject]@{
            State = $(if ($mins0 -le $lead0) { 'Warning' } else { 'Allowed' })
            Now = $Now; WindowKind = 'test'; Reason = $tw.Label
            BlockStart = $tw.Start; BlockEnd = $tw.End
            MinutesToBlock = [int][math]::Ceiling($mins0)
            MinutesToUnblock = 0
            CalendarTrusted = $CalendarTrusted
        }
    }

    $nights = @()
    foreach ($offset in @(-1, 0)) {
        $evening = $Now.Date.AddDays($offset)
        $win     = Get-DodoNightWindow -EveningDate $evening -Config $Config -Periods $Periods -CalendarTrusted $CalendarTrusted
        $nights += [pscustomobject]@{
            Evening = $evening
            Window  = $win
            Start   = $evening.Add($win.StartTime)
            End     = $evening.AddDays(1).Add($win.EndTime)
        }
    }
    $previous = $nights[0]
    $tonight  = $nights[1]

    $active = $null
    foreach ($n in @($previous, $tonight)) {
        if ($Now -ge $n.Start -and $Now -lt $n.End) { $active = $n; break }
    }

    if ($null -ne $active) {
        return [pscustomobject]@{
            State           = 'Blocked'
            Now             = $Now
            WindowKind      = $active.Window.Kind
            Reason          = $active.Window.Reason
            BlockStart      = $active.Start
            BlockEnd        = $active.End
            MinutesToBlock  = 0
            MinutesToUnblock = [int][math]::Ceiling(($active.End - $Now).TotalMinutes)
            CalendarTrusted = $CalendarTrusted
        }
    }

    # Hors fenetre : la prochaine extinction est celle de ce soir.
    $next    = $tonight
    $minutes = ($next.Start - $Now).TotalMinutes
    if ($minutes -lt 0) {
        # Ne devrait pas arriver (couvert par la branche Blocked) : garde-fou.
        $nextEvening = $Now.Date.AddDays(1)
        $win  = Get-DodoNightWindow -EveningDate $nextEvening -Config $Config -Periods $Periods -CalendarTrusted $CalendarTrusted
        $next = [pscustomobject]@{
            Evening = $nextEvening
            Window  = $win
            Start   = $nextEvening.Add($win.StartTime)
            End     = $nextEvening.AddDays(1).Add($win.EndTime)
        }
        $minutes = ($next.Start - $Now).TotalMinutes
    }

    $lead  = [int](@($Config.warningMinutes) | Measure-Object -Maximum).Maximum
    $state = 'Allowed'
    if ($minutes -le $lead) { $state = 'Warning' }

    return [pscustomobject]@{
        State            = $state
        Now              = $Now
        WindowKind       = $next.Window.Kind
        Reason           = $next.Window.Reason
        BlockStart       = $next.Start
        BlockEnd         = $next.End
        MinutesToBlock   = [int][math]::Ceiling($minutes)
        MinutesToUnblock = 0
        CalendarTrusted  = $CalendarTrusted
    }
}

function Get-DodoPendingWarnings {
    <#
        CONVENTION DE RETOUR (valable pour toutes les fonctions de listes du
        projet) : pas de virgule devant le return, et l'appelant enveloppe
        l'appel dans @(...). Melanger les deux fait qu'un resultat vide
        devient un tableau d'UN element - le tableau vide lui-meme - et
        Count vaut 1 au lieu de 0.

        Seuils d'alerte a declencher maintenant, compte tenu de ceux deja emis.
        Robuste a un reveil tardif : si l'agent a saute un tour, tous les seuils
        depasses sont rattrapes en une fois (et le message annonce le temps REEL
        restant, pas le seuil).
    #>
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Config,
        [string[]]$AlreadyFired = @()
    )
    if ($State.State -ne 'Warning') { return @() }
    $due = @()
    foreach ($t in (@($Config.warningMinutes) | Sort-Object -Descending)) {
        $ti = [int]$t
        if ($State.MinutesToBlock -le $ti -and ($AlreadyFired -notcontains "$ti")) { $due += $ti }
    }
    return @($due)
}

function Format-DodoMessage {
    <# Remplace les jetons {minutes}, {name}, {heure} dans un message. #>
    param([string]$Template, [hashtable]$Tokens)
    $out = $Template
    foreach ($k in $Tokens.Keys) { $out = $out.Replace('{' + $k + '}', [string]$Tokens[$k]) }
    return $out
}

function Get-DodoSpeechPlan {
    <#
        Instants, en secondes depuis l'apparition de la fenetre, auxquels le
        message doit etre prononce.

        0 est toujours present : le message est dit des l'affichage. Ensuite il
        est repete toutes les RepeatEverySeconds tant que la fenetre reste a
        l'ecran. Une repetition qui tomberait pile a la fermeture n'est pas
        programmee : elle serait coupee.

        Fonction pure, sans effet de bord : c'est la cadence qui est testee
        hors ligne, pas le son.
    #>
    param(
        [int]$DisplaySeconds,
        [int]$RepeatEverySeconds,
        [int]$MaxRepeats = 20
    )
    $plan = New-Object System.Collections.Generic.List[int]
    $plan.Add(0)

    if ($RepeatEverySeconds -gt 0 -and $DisplaySeconds -gt 0) {
        $t = $RepeatEverySeconds
        while ($t -lt $DisplaySeconds -and $plan.Count -le $MaxRepeats) {
            $plan.Add($t)
            $t += $RepeatEverySeconds
        }
    }
    # Pas de virgule devant le retour : les appelants enveloppent dans @(...)
    return $plan.ToArray()
}
