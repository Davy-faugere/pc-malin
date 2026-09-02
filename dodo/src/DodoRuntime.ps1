#Requires -Version 5.1
<#
    DodoRuntime.ps1 - Couche d'execution : fichiers, cache calendrier, journal.
    Depend de DodoCore.ps1 (noyau pur), qui doit etre charge au prealable.

    Arborescence d'installation (par defaut C:\ProgramData\Dodo) :
        bin\    scripts        (Administrateurs + SYSTEM en ecriture, Utilisateurs en lecture)
        etc\    configuration  (idem)
        var\    etat courant   (idem)
        logs\   journal SYSTEM (idem)
        media\  sons optionnels enregistres par le parent
#>

Set-StrictMode -Version 2.0

function Get-DodoRoot {
    <# Racine d'installation : dossier parent de bin\. #>
    param([string]$Root)
    if (-not [string]::IsNullOrWhiteSpace($Root)) { return $Root }
    if ($PSScriptRoot) { return (Split-Path -Parent $PSScriptRoot) }
    return (Join-Path $env:ProgramData 'Dodo')
}

function Get-DodoPaths {
    param([string]$Root)
    $r = Get-DodoRoot -Root $Root
    return [pscustomobject]@{
        Root        = $r
        Bin         = Join-Path $r 'bin'
        Etc         = Join-Path $r 'etc'
        Var         = Join-Path $r 'var'
        Logs        = Join-Path $r 'logs'
        Media       = Join-Path $r 'media'
        Config      = Join-Path $r 'etc\dodo.config.json'
        Messages    = Join-Path $r 'etc\dodo.messages.json'
        Calendar    = Join-Path $r 'var\calendar.json'
        Exception   = Join-Path $r 'var\exception.json'
        ClockOffset = Join-Path $r 'var\clock-offset.txt'
        Pending     = Join-Path $r 'var\shutdown-pending.txt'
    }
}

# --------------------------------------------------------------------------
# Lecture / ecriture UTF-8 deterministes (5.1 et 7 se comportent differemment
# avec Get-Content/Set-Content : on passe donc par .NET directement).
# --------------------------------------------------------------------------

function Read-DodoText {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Write-DodoText {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Content)
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $enc = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $enc)
}

function Read-DodoJson {
    param([Parameter(Mandatory = $true)][string]$Path)
    $t = Read-DodoText -Path $Path
    if ([string]::IsNullOrWhiteSpace($t)) { return $null }
    return ($t | ConvertFrom-Json)
}

function Write-DodoJson {
    param([Parameter(Mandatory = $true)][string]$Path, $Object)
    Write-DodoText -Path $Path -Content ($Object | ConvertTo-Json -Depth 12)
}

# --------------------------------------------------------------------------
# Journal
# --------------------------------------------------------------------------

function Write-DodoLog {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'ACTION')][string]$Level = 'INFO',
        [string]$LogDirectory,
        [switch]$AlsoEventLog
    )
    $line = '{0} [{1,-6}] {2}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Write-Verbose $line
    if ($LogDirectory) {
        try {
            if (-not (Test-Path -LiteralPath $LogDirectory)) { New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null }
            $file = Join-Path $LogDirectory ('dodo-{0}.log' -f (Get-Date).ToString('yyyyMMdd'))
            Add-Content -LiteralPath $file -Value $line -Encoding UTF8
            # Retention 60 jours
            Get-ChildItem -LiteralPath $LogDirectory -Filter 'dodo-*.log' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-60) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        catch { Write-Verbose "Journal indisponible : $($_.Exception.Message)" }
    }
    if ($AlsoEventLog -and $env:OS -eq 'Windows_NT') {
        try {
            $type = 'Information'
            if ($Level -eq 'WARN')  { $type = 'Warning' }
            if ($Level -eq 'ERROR') { $type = 'Error' }
            Write-EventLog -LogName 'Application' -Source 'Dodo' -EntryType $type -EventId 1000 -Message $Message -ErrorAction Stop
        }
        catch { }
    }
    return $line
}

# --------------------------------------------------------------------------
# Horloge (decalage de test, uniquement en mode dryRun)
# --------------------------------------------------------------------------

function Get-DodoNow {
    <#
        Heure courante. Si dryRun est actif ET que var\clock-offset.txt contient
        un entier, ce decalage en minutes est applique : c'est le levier qui
        permet de derouler une soiree entiere en quelques secondes pendant les
        tests. En production (dryRun = false) le fichier est ignore.
    #>
    param($Config, [string]$Root)
    $now = Get-Date
    if ($null -eq $Config -or -not $Config.dryRun) { return $now }
    $p = (Get-DodoPaths -Root $Root).ClockOffset
    $t = Read-DodoText -Path $p
    if ([string]::IsNullOrWhiteSpace($t)) { return $now }
    $m = 0
    if ([int]::TryParse($t.Trim(), [ref]$m)) { return $now.AddMinutes($m) }
    return $now
}

# --------------------------------------------------------------------------
# Configuration et messages
# --------------------------------------------------------------------------

function Get-DodoConfiguration {
    param([string]$Root)
    $paths = Get-DodoPaths -Root $Root
    $raw   = $null
    if (Test-Path -LiteralPath $paths.Config) { $raw = Read-DodoJson -Path $paths.Config }
    return (Resolve-DodoConfig $raw)
}

function Get-DodoMessages {
    param([string]$Root)
    $paths = Get-DodoPaths -Root $Root
    $defaults = [pscustomobject]@{
        popupTitle   = 'Extinction programmee'
        warning      = "Attention {name}, l'ordinateur va s'eteindre dans {minutes} minutes. Enregistre ton travail."
        warningOne   = "Attention {name}, l'ordinateur va s'eteindre dans une minute."
        shutdownNow  = "Il est l'heure de dormir. L'ordinateur s'eteint. Bonne nuit."
        bootBlocked  = "Il est trop tard pour l'ordinateur. Il va s'eteindre. Bonne nuit."
        popupFooter  = 'Regle parentale - extinction automatique'
    }
    if (-not (Test-Path -LiteralPath $paths.Messages)) { return $defaults }
    $m = Read-DodoJson -Path $paths.Messages
    foreach ($n in @('popupTitle', 'warning', 'warningOne', 'shutdownNow', 'bootBlocked', 'popupFooter')) {
        $v = Get-DodoProp $m $n
        if (-not [string]::IsNullOrWhiteSpace($v)) { $defaults.$n = [string]$v }
    }
    return $defaults
}

# --------------------------------------------------------------------------
# Derogation temporaire posee par le parent
# --------------------------------------------------------------------------

function Get-DodoActiveException {
    <# Renvoie l'objet de derogation s'il est encore valide, sinon $null. #>
    param([string]$Root, [datetime]$Now = (Get-Date))
    $p = (Get-DodoPaths -Root $Root).Exception
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $e     = Read-DodoJson -Path $p
        $until = [datetime]::Parse([string](Get-DodoProp $e 'until' ''), [System.Globalization.CultureInfo]::InvariantCulture)
        if ($Now -lt $until) {
            return [pscustomobject]@{
                Until  = $until
                Reason = [string](Get-DodoProp $e 'reason' 'non precise')
                By     = [string](Get-DodoProp $e 'grantedBy' 'inconnu')
            }
        }
    }
    catch { }
    return $null
}

# --------------------------------------------------------------------------
# Calendrier scolaire
# --------------------------------------------------------------------------

function Get-DodoSchoolYearLabels {
    <# Annees scolaires a recuperer : precedente, courante, suivante. #>
    param([datetime]$Now = (Get-Date))
    $y = $Now.Year
    if ($Now.Month -lt 9) { $y = $y - 1 }
    return @(
        ('{0}-{1}' -f ($y - 1), $y),
        ('{0}-{1}' -f $y, ($y + 1)),
        ('{0}-{1}' -f ($y + 1), ($y + 2))
    )
}

function Update-DodoCalendarCache {
    <#
        Interroge l'API Open Data du ministere de l'Education nationale
        (dataset fr-en-calendrier-scolaire) et met a jour var\calendar.json.

        Le cache n'est REMPLACE que si la reponse est exploitable : en cas
        d'echec reseau ou de reponse vide, l'ancien cache reste en place.
    #>
    param(
        [Parameter(Mandatory = $true)]$Config,
        [string]$Root,
        [datetime]$Now = (Get-Date),
        [int]$TimeoutSec = 30
    )
    $paths = Get-DodoPaths -Root $Root

    if ($Config.zone -notmatch '^Zone [A-C]$') {
        throw "zone invalide : '$($Config.zone)'. Valeurs acceptees : 'Zone A', 'Zone B', 'Zone C'."
    }

    if ($null -ne (Get-DodoProp $Config.calendar 'offlineOnly')) {
        if ($Config.calendar.offlineOnly) {
            return [pscustomobject]@{ Success = $true; Skipped = $true; Message = 'mode hors ligne : recuperation reseau desactivee'; RecordCount = 0 }
        }
    }

    if ($PSVersionTable.PSVersion.Major -lt 6) {
        try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
    }

    $years  = Get-DodoSchoolYearLabels -Now $Now
    $filter = ($years | ForEach-Object { 'annee_scolaire="' + $_ + '"' }) -join ' or '
    $where  = 'zones="' + $Config.zone + '" and (' + $filter + ')'

    $all    = New-Object System.Collections.Generic.List[object]
    $limit  = 100
    $offset = 0
    for ($page = 0; $page -lt 10; $page++) {
        $url = '{0}?where={1}&limit={2}&offset={3}&order_by=start_date' -f `
            $Config.calendar.apiUrl, [uri]::EscapeDataString($where), $limit, $offset
        $resp = Invoke-RestMethod -Uri $url -Method Get -TimeoutSec $TimeoutSec -ErrorAction Stop
        $results = @(Get-DodoProp $resp 'results' @())
        foreach ($r in $results) { $all.Add($r) }
        if ($results.Count -lt $limit) { break }
        $offset += $limit
    }

    if ($all.Count -eq 0) {
        return [pscustomobject]@{ Success = $false; Skipped = $false; Message = "l'API n'a renvoye aucun enregistrement pour $($Config.zone) / $($years -join ', ') - cache precedent conserve"; RecordCount = 0 }
    }

    $parsed = ConvertFrom-DodoCalendarRecords -Records $all -Config $Config
    if ($parsed.Periods.Count -eq 0) {
        return [pscustomobject]@{ Success = $false; Skipped = $false; Message = 'aucune periode exploitable apres analyse - cache precedent conserve'; RecordCount = $all.Count }
    }

    $cache = [pscustomobject]@{
        schemaVersion = 1
        fetchedAt     = (Get-Date).ToString('o')
        zone          = $Config.zone
        schoolYears   = $years
        source        = 'data.education.gouv.fr / fr-en-calendrier-scolaire'
        recordCount   = $all.Count
        warnings      = @($parsed.Warnings)
        periods       = @($parsed.Periods | Where-Object { $_.Origin -eq 'api' } | ForEach-Object {
                [pscustomobject]@{
                    label        = $_.Label
                    start        = $_.Start.ToString('yyyy-MM-dd')
                    endExclusive = $_.EndExclusive.ToString('yyyy-MM-dd')
                }
            })
    }
    Write-DodoJson -Path $paths.Calendar -Object $cache

    return [pscustomobject]@{
        Success     = $true
        Skipped     = $false
        Message     = "$($cache.periods.Count) periodes enregistrees ($($all.Count) enregistrements bruts)"
        RecordCount = $all.Count
        Warnings    = @($parsed.Warnings)
        Periods     = @($parsed.Periods)
    }
}

function Get-DodoCalendar {
    <#
        Charge le calendrier exploitable et decide s'il est DIGNE DE CONFIANCE.

        Non fiable (donc repli sur la regle scolaire, la plus stricte) si :
          - le cache est absent ou illisible
          - il a depasse calendar.maxCacheAgeDays
          - il ne contient plus aucune periode couvrant l'avenir proche
        Les periodes saisies a la main (calendar.overrides) sont toujours
        ajoutees ; en mode offlineOnly, elles suffisent a etablir la confiance.
    #>
    param([Parameter(Mandatory = $true)]$Config, [string]$Root, [datetime]$Now = (Get-Date))

    $paths    = Get-DodoPaths -Root $Root
    $periods  = New-Object System.Collections.Generic.List[object]
    $notes    = New-Object System.Collections.Generic.List[string]
    $trusted  = $false
    $ageDays  = $null
    $offline  = [bool](Get-DodoProp $Config.calendar 'offlineOnly' $false)

    $cache = $null
    try { $cache = Read-DodoJson -Path $paths.Calendar }
    catch { $notes.Add("cache calendrier illisible : $($_.Exception.Message)") }

    if ($null -ne $cache) {
        foreach ($p in (Get-DodoProp $cache 'periods' @())) {
            try {
                $periods.Add((New-DodoPeriod `
                    -Start ([datetime]::ParseExact([string]$p.start, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)) `
                    -EndExclusive ([datetime]::ParseExact([string]$p.endExclusive, 'yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)) `
                    -Label ([string](Get-DodoProp $p 'label' '')) -Origin 'api'))
            }
            catch { $notes.Add("periode illisible dans le cache : $($_.Exception.Message)") }
        }
        $fetchedAt = [string](Get-DodoProp $cache 'fetchedAt' '')
        if (-not [string]::IsNullOrWhiteSpace($fetchedAt)) {
            try {
                $ageDays = [math]::Round([math]::Max(0, ($Now - [datetime]::Parse($fetchedAt, [System.Globalization.CultureInfo]::InvariantCulture)).TotalDays), 1)
            }
            catch { $notes.Add('date de rafraichissement du cache illisible') }
        }
        $zoneCache = [string](Get-DodoProp $cache 'zone' '')
        if ($zoneCache -and $zoneCache -ne $Config.zone) {
            $notes.Add("le cache concerne '$zoneCache' alors que la configuration demande '$($Config.zone)'")
        }
    }
    else { $notes.Add('aucun cache calendrier') }

    # Periodes saisies manuellement
    $ovr = ConvertFrom-DodoCalendarRecords -Records @() -Config $Config
    foreach ($p in $ovr.Periods) { $periods.Add($p) }
    foreach ($w in $ovr.Warnings) { $notes.Add($w) }

    $apiCount = @($periods | Where-Object { $_.Origin -eq 'api' }).Count
    $ovrCount = @($periods | Where-Object { $_.Origin -eq 'override' }).Count
    $maxEnd   = $null
    if ($periods.Count -gt 0) { $maxEnd = (@($periods | Sort-Object EndExclusive)[-1]).EndExclusive }

    if ($offline) {
        $trusted = ($ovrCount -gt 0)
        if (-not $trusted) { $notes.Add('mode hors ligne mais aucune periode dans calendar.overrides') }
    }
    elseif ($apiCount -eq 0) { $notes.Add('cache vide') }
    elseif ($null -eq $ageDays) { $notes.Add('anciennete du cache inconnue') }
    elseif ($ageDays -gt $Config.calendar.maxCacheAgeDays) {
        $notes.Add("cache perime : $ageDays jours (maximum $($Config.calendar.maxCacheAgeDays))")
    }
    elseif ($null -ne $maxEnd -and $maxEnd -le $Now.Date) {
        $notes.Add("le cache ne couvre plus l'avenir (derniere periode : $($maxEnd.ToString('yyyy-MM-dd')))")
    }
    else { $trusted = $true }

    return [pscustomobject]@{
        Trusted     = $trusted
        Periods     = @($periods | Sort-Object Start)
        AgeDays     = $ageDays
        ApiCount    = $apiCount
        OverrideCount = $ovrCount
        Notes       = $notes.ToArray()
        CachePath   = $paths.Calendar
    }
}

# --------------------------------------------------------------------------
# Sessions interactives (Windows)
# --------------------------------------------------------------------------

function Get-DodoInteractiveUsers {
    <#
        Comptes ayant une session graphique ouverte, deduits des processus
        explorer.exe. Sert a ne pas eteindre le poste sous le nez d'un adulte
        inscrit dans exemptUsers.
    #>
    $users = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe'" -ErrorAction Stop)) {
            try {
                $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop
                if ($o.ReturnValue -eq 0 -and $o.User) {
                    $n = $o.User
                    if (-not $users.Contains($n)) { $users.Add($n) }
                }
            }
            catch { }
        }
    }
    catch { }
    return ,$users.ToArray()
}
