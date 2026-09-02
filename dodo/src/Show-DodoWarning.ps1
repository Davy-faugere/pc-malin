#Requires -Version 5.1
<#
    Show-DodoWarning.ps1 - Agent d'alerte, execute DANS la session de l'utilisateur.

    Tache planifiee Dodo-Notify, toutes les minutes, avec les droits de
    l'utilisateur connecte (aucun privilege necessaire). Il n'eteint rien :
    il previent, par un message vocal et une fenetre au premier plan.

    Ordre de repli pour le son, du plus fiable au moins fiable :
      1. fichier WAV enregistre par le parent dans media\ (warning.wav / shutdown.wav)
      2. synthese vocale SAPI5 (voix francaise si installee)
      3. son systeme Windows
    Aucune de ces etapes n'est bloquante : si tout echoue, la fenetre reste.

    Diagnostic : -ListVoices affiche les voix reellement disponibles sur ce poste.
    Essai manuel : -Force -ForceMinutes 5
#>
[CmdletBinding()]
param(
    [string]$Root,
    [int]$DisplaySeconds = 25,
    [switch]$Force,
    [int]$ForceMinutes = 10,
    [switch]$ListVoices
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')

$userDir = Join-Path $env:LOCALAPPDATA 'Dodo'
function LogU { param([string]$m, [string]$l = 'INFO') Write-DodoLog -Message $m -Level $l -LogDirectory $userDir | Out-Null }

# --------------------------------------------------------------------------
# Son
# --------------------------------------------------------------------------
function Get-DodoVoices {
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $v = @($s.GetInstalledVoices() | Where-Object { $_.Enabled } | ForEach-Object {
                [pscustomobject]@{ Name = $_.VoiceInfo.Name; Culture = $_.VoiceInfo.Culture.Name; Gender = $_.VoiceInfo.Gender }
            })
        $s.Dispose()
        return ,$v
    }
    catch { return ,@() }
}

function Start-DodoSound {
    <# Joue le message. Ne bloque pas et ne leve jamais d'exception. #>
    param([string]$Text, [string]$WavPath)

    if ($WavPath -and (Test-Path -LiteralPath $WavPath)) {
        try {
            $player = New-Object System.Media.SoundPlayer $WavPath
            $player.Play()
            return 'wav'
        }
        catch { LogU "Lecture de $WavPath impossible : $($_.Exception.Message)" 'WARN' }
    }

    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $script:DodoSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
        $fr = @($script:DodoSynth.GetInstalledVoices() |
                Where-Object { $_.Enabled -and $_.VoiceInfo.Culture.Name -like 'fr*' }) | Select-Object -First 1
        if ($fr) { $script:DodoSynth.SelectVoice($fr.VoiceInfo.Name) }
        $script:DodoSynth.Volume = 100
        $script:DodoSynth.SpeakAsync($Text) | Out-Null
        return $(if ($fr) { 'voix ' + $fr.VoiceInfo.Name } else { 'voix par defaut (aucune voix francaise installee)' })
    }
    catch { LogU "Synthese vocale indisponible : $($_.Exception.Message)" 'WARN' }

    try { [System.Media.SystemSounds]::Exclamation.Play(); return 'son systeme' } catch { }
    return 'aucun'
}

# --------------------------------------------------------------------------
# Fenetre
# --------------------------------------------------------------------------
function Show-DodoPopup {
    param([string]$Title, [string]$Line1, [string]$Line2, [int]$Seconds, [string]$Accent = 'orange')
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

        $script:DodoForm.Add_Shown({ $script:DodoForm.Activate(); $script:DodoForm.BringToFront() })
        [void]$script:DodoForm.ShowDialog()
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
        $v = Get-DodoVoices
        if ($v.Count -eq 0) { Write-Host 'Aucune voix SAPI5 exploitable sur ce poste.' -ForegroundColor Yellow }
        else { $v | Format-Table -AutoSize | Out-String | Write-Host }
        Write-Host "Note : les voix 'modernes' de Windows 11 (Speech_OneCore) ne sont pas visibles par System.Speech." -ForegroundColor DarkGray
        Write-Host "Si aucune voix francaise n'apparait : deposer media\warning.wav et media\shutdown.wav." -ForegroundColor DarkGray
        exit 0
    }

    $paths = Get-DodoPaths -Root $Root
    $cfg   = Get-DodoConfiguration -Root $Root
    $msgs  = Get-DodoMessages -Root $Root
    $now   = Get-DodoNow -Config $cfg -Root $Root
    if (-not (Test-Path -LiteralPath $userDir)) { New-Item -ItemType Directory -Path $userDir -Force | Out-Null }

    $name = $env:USERNAME

    if ($Force) {
        $txt = Format-DodoMessage $msgs.warning @{ minutes = $ForceMinutes; name = $name }
        $how = Start-DodoSound -Text $txt -WavPath (Join-Path $paths.Media 'warning.wav')
        LogU "Essai manuel : $how"
        [void](Show-DodoPopup -Title $msgs.popupTitle -Line1 ("Extinction dans $ForceMinutes minutes") -Line2 $txt -Seconds $DisplaySeconds)
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
        $how = Start-DodoSound -Text $txt -WavPath (Join-Path $paths.Media 'shutdown.wav')
        LogU "Message d'extinction diffuse ($how) - fenetre $($state.BlockStart.ToString('yyyy-MM-dd HH:mm'))" 'ACTION'
        [void](Show-DodoPopup -Title $msgs.popupTitle -Line1 'Extinction en cours' -Line2 $txt -Seconds ([math]::Max(10, $cfg.shutdownGraceSeconds)) -Accent 'red')
        exit 0
    }

    $fired = @(Get-ChildItem -LiteralPath $userDir -Filter "fired-$tag-*.txt" -File -ErrorAction SilentlyContinue |
        ForEach-Object { ($_.BaseName -split '-')[-1] })
    $due = Get-DodoPendingWarnings -State $state -Config $cfg -AlreadyFired $fired
    if ($due.Count -eq 0) { exit 0 }

    foreach ($t in $due) { Write-DodoText -Path (Join-Path $userDir "fired-$tag-$t.txt") -Content (Get-Date).ToString('o') }

    $mins = [math]::Max(1, $state.MinutesToBlock)
    $tpl  = if ($mins -eq 1) { $msgs.warningOne } else { $msgs.warning }
    $txt  = Format-DodoMessage $tpl @{ minutes = $mins; name = $name }
    $how  = Start-DodoSound -Text $txt -WavPath (Join-Path $paths.Media 'warning.wav')
    LogU "Preavis diffuse a $mins min (seuils $(($due) -join ',')) via $how" 'ACTION'

    $l1 = if ($mins -eq 1) { 'Extinction dans 1 minute' } else { "Extinction dans $mins minutes" }
    [void](Show-DodoPopup -Title $msgs.popupTitle -Line1 $l1 -Line2 "$txt`r`n`r`n$($msgs.popupFooter)" -Seconds $DisplaySeconds)
    exit 0
}
catch {
    try { LogU "Erreur inattendue : $($_.Exception.Message)" 'ERROR' } catch { }
    exit 0   # ne jamais faire echouer la tache planifiee
}
