#Requires -Version 5.1
<#
    Show-DodoWarning.ps1 - Agent d'alerte, execute DANS la session de l'utilisateur.

    Tache planifiee Dodo-Notify, toutes les minutes, avec les droits de
    l'utilisateur connecte (aucun privilege necessaire). Il n'eteint rien :
    il previent, par un message vocal et une fenetre au premier plan.

    Ordre de repli pour le son, du plus fiable au moins fiable (voir
    DodoSpeech.ps1) :
      1. fichier WAV enregistre par le parent dans media\ (warning.wav / shutdown.wav)
      2. voix moderne de Windows 11 (OneCore, via WinRT) - c'est la que sont
         les voix francaises
      3. synthese vocale SAPI5 classique
      4. son systeme Windows
    Aucune de ces etapes n'est bloquante : si tout echoue, la fenetre reste.

    Le message est repete pendant que la fenetre est affichee, a la cadence
    speech.repeatEverySeconds. Le WAV n'est synthetise qu'une fois puis rejoue.

    Liste des voix : -ListVoices   (les DEUX jeux, OneCore et SAPI)
    Essai manuel   : -Force -ForceMinutes 5
    Essai d'un texte : -SpeakText "bonne nuit"
    Diagnostic     : -Diagnose   (affiche tout ce que le script voit)
#>
[CmdletBinding()]
param(
    [string]$Root,
    [int]$DisplaySeconds = 0,      # 0 = valeur de la configuration (speech.displaySeconds)
    [switch]$Force,
    [int]$ForceMinutes = 10,
    [switch]$ListVoices,
    [switch]$Diagnose,
    [string]$SpeakText = ''        # prononce ce texte et sort : essai de la voix
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')
. (Join-Path $PSScriptRoot 'DodoSpeech.ps1')

# En tache planifiee, toute erreur est avalee : une tache qui echoue chaque
# minute est pire que le silence. En lancement MANUEL au contraire, avaler
# l'erreur donne un "il ne se passe rien" indebogable : on l'affiche.
$Interactif = ($Force -or $ListVoices -or $Diagnose -or $SpeakText)

$userDir = Join-Path $env:LOCALAPPDATA 'Dodo'
function LogU { param([string]$m, [string]$l = 'INFO') Write-DodoLog -Message $m -Level $l -LogDirectory $userDir | Out-Null }

# --------------------------------------------------------------------------
# Son
# --------------------------------------------------------------------------
function Start-DodoSound {
    <#
        Diffuse le message. Delegue a DodoSpeech.ps1, qui sait atteindre les
        voix modernes de Windows 11. Ne bloque pas, ne leve jamais.
    #>
    param([string]$Text, [string]$WavPath, $Speech = $null)
    return (Invoke-DodoSpeak -Text $Text -WavPath $WavPath -Speech $Speech `
                -OnLog { param($m, $n) LogU $m $n })
}

# --------------------------------------------------------------------------
# Fenetre
# --------------------------------------------------------------------------
function Show-DodoPopup {
    <#
        Fenetre au premier plan. -SpeakAt donne les instants, en secondes
        depuis l'affichage, auxquels rediffuser le message : c'est ainsi que
        la voix repete l'annonce pendant que la fenetre est a l'ecran.
    #>
    param([string]$Title, [string]$Line1, [string]$Line2, [int]$Seconds,
          [string]$Accent = 'orange', $SpeakAt = @(), [scriptblock]$OnSpeak = $null)
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop

        $bg     = [System.Drawing.Color]::FromArgb(17, 24, 39)
        $fg     = [System.Drawing.Color]::White
        $accCol = if ($Accent -eq 'red') { [System.Drawing.Color]::FromArgb(220, 68, 68) } else { [System.Drawing.Color]::FromArgb(245, 158, 11) }

        $script:DodoForm = New-Object System.Windows.Forms.Form
        $script:DodoForm.Text            = $Title
        $script:DodoForm.ClientSize      = New-Object System.Drawing.Size(600, 240)
        $script:DodoForm.StartPosition   = 'CenterScreen'
        $script:DodoForm.FormBorderStyle = 'FixedDialog'
        $script:DodoForm.MaximizeBox     = $false
        $script:DodoForm.MinimizeBox     = $false
        $script:DodoForm.TopMost         = $true
        $script:DodoForm.BackColor       = $bg
        $script:DodoForm.ShowInTaskbar   = $true

        $bar = New-Object System.Windows.Forms.Panel
        $bar.Dock = 'Top'; $bar.Height = 8; $bar.BackColor = $accCol
        $script:DodoForm.Controls.Add($bar)

        $l1 = New-Object System.Windows.Forms.Label
        $l1.Text = $Line1
        $l1.Font = New-Object System.Drawing.Font('Segoe UI', 20, [System.Drawing.FontStyle]::Bold)
        $l1.ForeColor = $accCol
        $l1.TextAlign = 'MiddleCenter'
        $l1.SetBounds(20, 40, 560, 60)
        $script:DodoForm.Controls.Add($l1)

        $l2 = New-Object System.Windows.Forms.Label
        $l2.Text = $Line2
        $l2.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Regular)
        $l2.ForeColor = $fg
        $l2.TextAlign = 'MiddleCenter'
        $l2.SetBounds(20, 105, 560, 80)
        $script:DodoForm.Controls.Add($l2)

        $btn = New-Object System.Windows.Forms.Button
        $btn.Text = 'J ai compris'
        $btn.SetBounds(240, 190, 120, 32)
        $btn.FlatStyle = 'Flat'
        $btn.BackColor = [System.Drawing.Color]::FromArgb(55, 65, 81)
        $btn.ForeColor = $fg
        $btn.Add_Click({ $script:DodoForm.Close() })
        $script:DodoForm.Controls.Add($btn)

        $timer = New-Object System.Windows.Forms.Timer
        $timer.Interval = [math]::Max(3, $Seconds) * 1000
        $timer.Add_Tick({ $this.Stop(); $script:DodoForm.Close() })
        $timer.Start()

        # Rediffusion pendant l'affichage. Les gestionnaires d'evenement ne
        # voient pas les variables locales : tout passe par la portee script.
        $script:DodoEcoule  = 0
        $script:DodoSpeakAt = @(@($SpeakAt) | Where-Object { $_ -gt 0 })
        $script:DodoOnSpeak = $OnSpeak
        $repete = $null
        if ($script:DodoSpeakAt.Count -gt 0 -and $null -ne $OnSpeak) {
            $repete = New-Object System.Windows.Forms.Timer
            $repete.Interval = 1000
            $repete.Add_Tick({
                $script:DodoEcoule++
                if ($script:DodoSpeakAt -contains $script:DodoEcoule) {
                    try { & $script:DodoOnSpeak } catch { }
                }
            })
            $repete.Start()
        }

        $script:DodoForm.Add_Shown({ $script:DodoForm.Activate(); $script:DodoForm.BringToFront() })
        [void]$script:DodoForm.ShowDialog()
        if ($null -ne $repete) { $repete.Stop(); $repete.Dispose() }
        $timer.Dispose()
        $script:DodoForm.Dispose()
        return $true
    }
    catch {
        LogU "Affichage de la fenetre impossible : $($_.Exception.Message)" 'ERROR'
        return $false
    }
}

# --------------------------------------------------------------------------
# Corps
# --------------------------------------------------------------------------
try {
    if ($ListVoices) {
        $rap = Get-DodoSpeechReport
        Write-Host ''
        Write-Host (' Voix disponibles : {0} OneCore (Windows 11) + {1} SAPI5 classiques, dont {2} en francais.' -f
                    $rap.OneCoreCount, $rap.SapiCount, $rap.FrenchCount) -ForegroundColor White
        Write-Host ''
        if (@($rap.Voices).Count -eq 0) {
            Write-Host ' Aucune voix exploitable sur ce poste.' -ForegroundColor Yellow
        }
        else {
            $rap.Voices | Select-Object Engine, Name, Culture, Gender, IsFrench |
                Format-Table -AutoSize | Out-String | Write-Host
        }
        if ($null -ne $rap.Selected) {
            Write-Host (' Voix retenue par defaut : {0} ({1}, {2})' -f
                        $rap.Selected.Name, $rap.Selected.Engine, $rap.Selected.Culture) -ForegroundColor Green
        }
        if ($rap.FrenchCount -eq 0) {
            Write-Host ''
            Write-Host " Aucune voix francaise installee. Pour en ajouter :" -ForegroundColor Yellow
            Write-Host "   Parametres > Heure et langue > Voix > Ajouter des voix > Francais" -ForegroundColor DarkGray
            Write-Host "   A defaut, deposer vos propres enregistrements dans media\warning.wav et media\shutdown.wav." -ForegroundColor DarkGray
        }
        if (-not $rap.WinRtAvailable) {
            Write-Host ''
            Write-Host " WinRT indisponible : les voix modernes de Windows ne peuvent pas etre atteintes." -ForegroundColor Yellow
        }
        Write-Host ''
        exit 0
    }

    $paths = Get-DodoPaths -Root $Root

    if ($Diagnose) {
        function D { param($k, $v, $ok = $null)
            Write-Host ('  {0,-26}: ' -f $k) -NoNewline
            $c = if ($null -eq $ok) { 'Gray' } elseif ($ok) { 'Green' } else { 'Red' }
            Write-Host $v -ForegroundColor $c }
        Write-Host ''; Write-Host ' Show-DodoWarning - diagnostic' -ForegroundColor White; Write-Host ''
        D 'PowerShell'      $PSVersionTable.PSVersion
        D 'Mode de thread'  ([System.Threading.Thread]::CurrentThread.GetApartmentState())  ([System.Threading.Thread]::CurrentThread.GetApartmentState() -eq 'STA')
        D 'Compte'          $env:USERNAME
        D 'Racine resolue'  $paths.Root                 (Test-Path -LiteralPath $paths.Root)
        D 'Configuration'   $paths.Config               (Test-Path -LiteralPath $paths.Config)
        D 'Messages'        $paths.Messages             (Test-Path -LiteralPath $paths.Messages)
        D 'Dossier media'   $paths.Media                (Test-Path -LiteralPath $paths.Media)
        D 'warning.wav'     (Join-Path $paths.Media 'warning.wav')  (Test-Path -LiteralPath (Join-Path $paths.Media 'warning.wav'))
        D 'Journal utilisateur' $userDir
        $rap = Get-DodoSpeechReport
        D 'WinRT (voix Windows 11)' $(if ($rap.WinRtAvailable) { 'disponible' } else { 'INDISPONIBLE' }) $rap.WinRtAvailable
        D 'Voix installees'  ("{0} OneCore + {1} SAPI5, dont {2} en francais" -f
                              $rap.OneCoreCount, $rap.SapiCount, $rap.FrenchCount) ($rap.FrenchCount -gt 0)
        foreach ($x in @($rap.Voices)) {
            Write-Host ("      - [{0,-7}] {1} [{2}]" -f $x.Engine, $x.Name, $x.Culture) -ForegroundColor DarkGray
        }
        D 'Voix retenue'     $(if ($null -ne $rap.Selected) { '{0} ({1})' -f $rap.Selected.Name, $rap.Selected.Engine } else { 'aucune' }) ($null -ne $rap.Selected)
        $wf = $true
        try { Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop; Add-Type -AssemblyName System.Drawing -ErrorAction Stop }
        catch { $wf = $false }
        D 'WinForms chargeable' $(if ($wf) { 'oui' } else { 'NON' }) $wf
        try {
            $c0 = Get-DodoConfiguration -Root $Root
            D 'Configuration lue' ("enabled={0} dryRun={1} scolaire={2}->{3}" -f $c0.enabled, $c0.dryRun, $c0.schedule.school.start, $c0.schedule.school.end) $true
            $cal0 = Get-DodoCalendar -Config $c0 -Root $Root
            D 'Calendrier' ("fiable={0} api={1} manuelles={2}" -f $cal0.Trusted, $cal0.ApiCount, $cal0.OverrideCount) $cal0.Trusted
            foreach ($n in $cal0.Notes) { Write-Host "      ! $n" -ForegroundColor Yellow }
            $st0 = Get-DodoState -Now (Get-DodoNow -Config $c0 -Root $Root) -Config $c0 -Periods $cal0.Periods -CalendarTrusted $cal0.Trusted
            D 'Etat courant' ("{0} - extinction {1}" -f $st0.State, $st0.BlockStart.ToString('dd/MM HH:mm')) $true
            $plan0 = @(Get-DodoSpeechPlan -DisplaySeconds $c0.speech.displaySeconds `
                                          -RepeatEverySeconds $c0.speech.repeatEverySeconds)
            D 'Voix (configuration)' ("active={0} moteur={1} voix='{2}' debit={3} volume={4}" -f
                $c0.speech.enabled, $c0.speech.engine,
                $(if ($c0.speech.voiceName) { $c0.speech.voiceName } else { 'automatique' }),
                $c0.speech.rate, $c0.speech.volume) ([bool]$c0.speech.enabled)
            D 'Diffusions par fenetre' ("{0} (a {1} s ; fenetre affichee {2} s)" -f
                $plan0.Count, ($plan0 -join ', '), $c0.speech.displaySeconds) $true
        }
        catch { D 'Configuration lue' ("ECHEC : " + $_.Exception.Message) $false }
        Write-Host ''
        if (-not $Force) { exit 0 }
    }

    if ($SpeakText) {
        $cfgV = $null
        try { $cfgV = Get-DodoConfiguration -Root $Root } catch { }
        $spV = $null
        if ($null -ne $cfgV -and $cfgV.PSObject.Properties['speech']) { $spV = $cfgV.speech }
        $comment = Invoke-DodoSpeak -Text $SpeakText -Speech $spV
        Write-Host ''
        Write-Host (" Texte prononce : {0}" -f $SpeakText)
        Write-Host (" Voie utilisee  : {0}" -f $comment) -ForegroundColor Green
        Write-Host ''
        # La lecture est asynchrone : sans cette attente le processus se
        # termine avant que le son soit sorti des haut-parleurs.
        Start-Sleep -Seconds ([math]::Min(30, 2 + [int]($SpeakText.Length / 12)))
        exit 0
    }

    $cfg   = Get-DodoConfiguration -Root $Root
    $msgs  = Get-DodoMessages -Root $Root
    $now   = Get-DodoNow -Config $cfg -Root $Root
    if (-not (Test-Path -LiteralPath $userDir)) { New-Item -ItemType Directory -Path $userDir -Force | Out-Null }

    $name = $env:USERNAME

    # -DisplaySeconds l'emporte s'il est fourni ; sinon la configuration decide.
    $secondes = $DisplaySeconds
    if ($secondes -le 0) { $secondes = [int]$cfg.speech.displaySeconds }
    if ($secondes -le 0) { $secondes = 25 }
    $plan = @(Get-DodoSpeechPlan -DisplaySeconds $secondes -RepeatEverySeconds ([int]$cfg.speech.repeatEverySeconds))
    Clear-DodoSpeechCache

    if ($Force) {
        $txt = Format-DodoMessage $msgs.warning @{ minutes = $ForceMinutes; name = $name }
        $wav = Join-Path $paths.Media 'warning.wav'
        $how = Start-DodoSound -Text $txt -WavPath $wav -Speech $cfg.speech
        LogU "Essai manuel : $how ; $($plan.Count) diffusion(s) prevue(s)"
        $script:DodoRedire = { [void](Start-DodoSound -Text $txt -WavPath $wav -Speech $cfg.speech) }.GetNewClosure()
        [void](Show-DodoPopup -Title $msgs.popupTitle -Line1 ("Extinction dans $ForceMinutes minutes") `
                              -Line2 $txt -Seconds $secondes -SpeakAt $plan -OnSpeak $script:DodoRedire)
        exit 0
    }

    if (-not $cfg.enabled) { exit 0 }
    $cal   = Get-DodoCalendar -Config $cfg -Root $Root -Now $now
    $state = Get-DodoState -Now $now -Config $cfg -Periods $cal.Periods -CalendarTrusted $cal.Trusted

    if ($null -ne (Get-DodoActiveException -Root $Root -Now $now)) { exit 0 }

    $tag = $state.BlockStart.ToString('yyyyMMddHHmm')

    # Menage des marqueurs des nuits precedentes
    Get-ChildItem -LiteralPath $userDir -Filter 'fired-*.txt' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notlike "fired-$tag-*" -and $_.LastWriteTime -lt (Get-Date).AddDays(-2) } |
        Remove-Item -Force -ErrorAction SilentlyContinue

    if ($state.State -eq 'Blocked') {
        $marker = Join-Path $userDir "fired-$tag-final.txt"
        if (Test-Path -LiteralPath $marker) { exit 0 }
        Write-DodoText -Path $marker -Content (Get-Date).ToString('o')
        $txt = Format-DodoMessage $msgs.shutdownNow @{ name = $name; minutes = 0 }
        $wav = Join-Path $paths.Media 'shutdown.wav'
        $how = Start-DodoSound -Text $txt -WavPath $wav -Speech $cfg.speech
        LogU "Message d'extinction diffuse ($how) - fenetre $($state.BlockStart.ToString('yyyy-MM-dd HH:mm'))" 'ACTION'
        # La fenetre finale dure le sursis d'extinction : la cadence de
        # repetition est recalculee sur cette duree, pas sur celle des preavis.
        $secFinal  = [math]::Max(10, $cfg.shutdownGraceSeconds)
        $planFinal = @(Get-DodoSpeechPlan -DisplaySeconds $secFinal -RepeatEverySeconds ([int]$cfg.speech.repeatEverySeconds))
        $script:DodoRedire = { [void](Start-DodoSound -Text $txt -WavPath $wav -Speech $cfg.speech) }.GetNewClosure()
        [void](Show-DodoPopup -Title $msgs.popupTitle -Line1 'Extinction en cours' -Line2 $txt `
                              -Seconds $secFinal -Accent 'red' -SpeakAt $planFinal -OnSpeak $script:DodoRedire)
        exit 0
    }

    $fired = @(Get-ChildItem -LiteralPath $userDir -Filter "fired-$tag-*.txt" -File -ErrorAction SilentlyContinue |
        ForEach-Object { ($_.BaseName -split '-')[-1] })
    $due = @(Get-DodoPendingWarnings -State $state -Config $cfg -AlreadyFired $fired)
    if ($due.Count -eq 0) { exit 0 }

    foreach ($t in $due) { Write-DodoText -Path (Join-Path $userDir "fired-$tag-$t.txt") -Content (Get-Date).ToString('o') }

    $mins = [math]::Max(1, $state.MinutesToBlock)
    $tpl  = if ($mins -eq 1) { $msgs.warningOne } else { $msgs.warning }
    $txt  = Format-DodoMessage $tpl @{ minutes = $mins; name = $name }
    $wav  = Join-Path $paths.Media 'warning.wav'
    $how  = Start-DodoSound -Text $txt -WavPath $wav -Speech $cfg.speech
    LogU "Preavis diffuse a $mins min (seuils $(($due) -join ',')) via $how ; $($plan.Count) diffusion(s)" 'ACTION'

    $l1 = if ($mins -eq 1) { 'Extinction dans 1 minute' } else { "Extinction dans $mins minutes" }
    $script:DodoRedire = { [void](Start-DodoSound -Text $txt -WavPath $wav -Speech $cfg.speech) }.GetNewClosure()
    [void](Show-DodoPopup -Title $msgs.popupTitle -Line1 $l1 -Line2 "$txt`r`n`r`n$($msgs.popupFooter)" `
                          -Seconds $secondes -SpeakAt $plan -OnSpeak $script:DodoRedire)
    exit 0
}
catch {
    try { LogU "Erreur inattendue : $($_.Exception.Message)" 'ERROR' } catch { }
    if ($Interactif) {
        Write-Host ''
        Write-Host "ECHEC : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray
        Write-Host ''
        Write-Host 'Relancez avec -Diagnose pour un etat detaille.' -ForegroundColor Yellow
        try {
            Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
            [System.Windows.Forms.MessageBox]::Show(
                "Show-DodoWarning a echoue :`n`n$($_.Exception.Message)", 'Dodo', 'OK', 'Error') | Out-Null
        }
        catch { }
        exit 1
    }
    exit 0   # ne jamais faire echouer la tache planifiee
}
