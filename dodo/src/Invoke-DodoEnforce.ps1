#Requires -Version 5.1
<#
    Invoke-DodoEnforce.ps1 - Agent d'application, execute par le compte SYSTEM.

    Declenche par deux taches planifiees (Dodo-Enforce toutes les minutes,
    Dodo-Boot au demarrage). C'est ce script, et lui seul, qui eteint le poste.

    Principes :
      - il ne fait jamais confiance a l'horloge du calendrier : si le calendrier
        est indisponible ou perime, il applique la regle la plus stricte ;
      - il ne leve jamais d'exception vers le planificateur : toute erreur est
        journalisee, et un echec de calendrier n'empeche pas l'extinction ;
      - en mode dryRun, il journalise l'action au lieu de l'executer.
#>
[CmdletBinding()]
param([string]$Root)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')

$paths  = Get-DodoPaths -Root $Root
$logDir = $paths.Logs

function Log { param([string]$m, [string]$l = 'INFO', [switch]$Event)
    Write-DodoLog -Message $m -Level $l -LogDirectory $logDir -AlsoEventLog:$Event | Out-Null
}

try { $cfg = Get-DodoConfiguration -Root $Root }
catch {
    # Configuration illisible : on ne peut pas decider, on ne fait rien mais on crie.
    Log "Configuration illisible, aucune action : $($_.Exception.Message)" 'ERROR' -Event
    exit 2
}

if (-not $cfg.enabled) { exit 0 }

$now = Get-DodoNow -Config $cfg -Root $Root

# --------------------------------------------------------------------------
# 1. Garde-cartes reseau : independant de l'horaire (partage de connexion)
# --------------------------------------------------------------------------
if ($cfg.adapterGuard.enabled) {
    try {
        $allowed = @($cfg.adapterGuard.allowedPnpDeviceIds)
        if ($allowed.Count -eq 0) {
            Log 'adapterGuard actif mais allowedPnpDeviceIds est vide : aucune carte desactivee (relancer Install-Dodo.ps1 -EnableAdapterGuard).' 'WARN'
        }
        else {
            foreach ($a in @(Get-NetAdapter -ErrorAction Stop)) {
                if ($allowed -contains $a.PnPDeviceID) { continue }
                if ($a.Status -eq 'Disabled') { continue }
                if ($cfg.dryRun) {
                    Log "SIMULATION : carte non autorisee '$($a.Name)' ($($a.InterfaceDescription)) - PnP $($a.PnPDeviceID)" 'ACTION'
                }
                else {
                    Disable-NetAdapter -Name $a.Name -Confirm:$false -ErrorAction Stop
                    Log "Carte reseau non autorisee desactivee : '$($a.Name)' ($($a.InterfaceDescription)) - PnP $($a.PnPDeviceID)" 'ACTION' -Event
                }
            }
        }
    }
    catch { Log "Garde-cartes reseau en echec : $($_.Exception.Message)" 'WARN' }
}

# --------------------------------------------------------------------------
# 2. Rafraichissement opportuniste du calendrier (au plus une fois par jour)
# --------------------------------------------------------------------------
try {
    $cal = Get-DodoCalendar -Config $cfg -Root $Root -Now $now
    if ($null -eq $cal.AgeDays -or $cal.AgeDays -ge 1) {
        try {
            $r = Update-DodoCalendarCache -Config $cfg -Root $Root -Now $now -TimeoutSec 20
            if ($r.Success -and -not $r.Skipped) {
                Log "Calendrier rafraichi : $($r.Message)"
                foreach ($w in @($r.Warnings)) { Log "Calendrier : $w" 'WARN' }
                $cal = Get-DodoCalendar -Config $cfg -Root $Root -Now $now
            }
            elseif (-not $r.Success) { Log "Calendrier non rafraichi : $($r.Message)" 'WARN' }
        }
        catch { Log "Rafraichissement du calendrier impossible (le cache existant reste utilise) : $($_.Exception.Message)" 'WARN' }
    }
}
catch {
    Log "Calendrier illisible : $($_.Exception.Message) - repli sur la regle scolaire." 'ERROR'
    $cal = [pscustomobject]@{ Trusted = $false; Periods = @(); AgeDays = $null; Notes = @() }
}

if (-not $cal.Trusted) { Log ("Calendrier non fiable ({0}) : application de la regle scolaire." -f (@($cal.Notes) -join ' ; ')) 'WARN' }

# --------------------------------------------------------------------------
# 3. Decision
# --------------------------------------------------------------------------
$state = Get-DodoState -Now $now -Config $cfg -Periods $cal.Periods -CalendarTrusted $cal.Trusted

if ($state.State -ne 'Blocked') {
    if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force -ErrorAction SilentlyContinue }
    exit 0
}

# --- Derogation posee par un parent
$exc = Get-DodoActiveException -Root $Root -Now $now
if ($null -ne $exc) {
    Log ("Fenetre d'extinction active mais derogation en cours jusqu'a {0} (motif : {1}, par {2})." -f $exc.Until.ToString('yyyy-MM-dd HH:mm'), $exc.Reason, $exc.By) 'WARN'
    exit 0
}

# --- Compte adulte REELLEMENT devant l'ecran
# On ne suspend l'extinction que pour un adulte present a la console. Une
# session laissee ouverte en arriere-plan par le changement rapide
# d'utilisateur ne compte pas : sinon il suffisait qu'un parent ait oublie de
# fermer sa session pour que le poste ne s'eteigne PLUS JAMAIS sur le profil de
# l'enfant, et le journal n'annoncait qu'un laconique "Extinction suspendue".
if (@($cfg.exemptUsers).Count -gt 0) {
    $console = Get-DodoConsoleUser
    if ($null -ne $console) {
        if (@($cfg.exemptUsers) -contains $console) {
            Log "Extinction suspendue : le compte exempte '$console' est celui ouvert a l'ecran." 'WARN'
            exit 0
        }
    }
    else {
        # Session console indeterminable : on retombe sur la regle precedente,
        # plus prudente, plutot que d'eteindre a l'aveugle devant un adulte.
        foreach ($u in @(Get-DodoInteractiveUsers)) {
            if (@($cfg.exemptUsers) -contains $u) {
                Log "Extinction suspendue : session console indeterminable, et le compte exempte '$u' a une session ouverte." 'WARN'
                exit 0
            }
        }
    }
}

# --- Delai accorde : plus long juste apres un demarrage, pour laisser a un
#     adulte le temps d'ouvrir une session et de poser une derogation.
$grace = $cfg.shutdownGraceSeconds
try {
    $boot = (Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop).LastBootUpTime
    if (((Get-Date) - $boot).TotalSeconds -lt 180) { $grace = $cfg.bootGraceSeconds }
}
catch { }

# --- Anti-rafale : une seule commande d'extinction par fenetre de grace
$graceWindow = $grace + 45
$pendingAt   = Read-DodoText -Path $paths.Pending
if (-not [string]::IsNullOrWhiteSpace($pendingAt)) {
    try {
        $t = [datetime]::Parse($pendingAt.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
        if (((Get-Date) - $t).TotalSeconds -lt $graceWindow) { exit 0 }
        Log "Extinction precedente non aboutie (annulation manuelle ?) : nouvelle commande emise." 'WARN' -Event
    }
    catch { }
}
Write-DodoText -Path $paths.Pending -Content (Get-Date).ToString('o')

# --------------------------------------------------------------------------
# 4. Extinction
# --------------------------------------------------------------------------
$msgs   = Get-DodoMessages -Root $Root
$reason = "Dodo - $($state.Reason) - fenetre $($state.BlockStart.ToString('HH:mm')) a $($state.BlockEnd.ToString('HH:mm'))"
$detail = "Etat=Blocked fenetre=$($state.WindowKind) motif='$($state.Reason)' debut=$($state.BlockStart.ToString('yyyy-MM-dd HH:mm')) fin=$($state.BlockEnd.ToString('yyyy-MM-dd HH:mm')) calendrierFiable=$($cal.Trusted)"

if ($cfg.dryRun) {
    Log "SIMULATION : extinction qui aurait ete declenchee. $detail" 'ACTION' -Event
    exit 0
}

# shutdown.exe n'accepte pas de facon fiable les caracteres accentues : on
# translittere le commentaire affiche par Windows.
$comment = ConvertTo-DodoAscii ((Format-DodoMessage $msgs.shutdownNow @{ name = '' }).Trim())
if ($comment.Length -gt 500) { $comment = $comment.Substring(0, 500) }

try {
    $shutdownArgs = @('/s', '/f', '/t', [string]$grace, '/c', $comment)
    $p = Start-Process -FilePath 'shutdown.exe' -ArgumentList $shutdownArgs -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($p.ExitCode -eq 0) {
        Log "EXTINCTION DEMANDEE (dans $grace s). $detail" 'ACTION' -Event
        # Une fenetre d'essai ne sert qu'une fois : on la retire immediatement
        # pour qu'un redemarrage ne relance pas une extinction en boucle.
        if ($state.WindowKind -eq 'test') {
            try {
                $raw = Read-DodoJson -Path $paths.Config
                if ($null -ne $raw -and $null -ne $raw.PSObject.Properties['testWindow']) {
                    $raw.PSObject.Properties.Remove('testWindow')
                    Write-DodoJson -Path $paths.Config -Object $raw
                    Log "Fenetre d'essai consommee et retiree de la configuration." 'ACTION' -Event
                }
            }
            catch { Log "Retrait de la fenetre d'essai impossible : $($_.Exception.Message)" 'ERROR' -Event }
        }
    }
    else                   { Log "shutdown.exe a renvoye le code $($p.ExitCode). $detail" 'ERROR' -Event }
}
catch {
    Log "Echec de l'appel a shutdown.exe : $($_.Exception.Message). $detail" 'ERROR' -Event
    exit 3
}
exit 0
