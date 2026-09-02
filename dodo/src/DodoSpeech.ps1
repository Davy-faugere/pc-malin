#Requires -Version 5.1
<#
    DodoSpeech.ps1 - Moteur vocal.

    Windows expose DEUX jeux de voix, qui ne se voient pas entre eux :

      - les voix "classiques" SAPI5, visibles par System.Speech
        (HKLM\SOFTWARE\Microsoft\Speech\Voices\Tokens) ;
      - les voix "modernes" OneCore, celles que Windows 11 installe et
        propose dans Parametres > Heure et langue > Voix
        (HKLM\SOFTWARE\Microsoft\Speech_OneCore\Voices\Tokens).

    Sur une installation francaise de Windows 11, les voix francaises
    (Denise, Henri, Paul...) sont TOUJOURS du second jeu. System.Speech ne
    les voit pas : c'est la raison pour laquelle la synthese tombait sur une
    voix anglaise, ou sur rien.

    Ce fichier atteint les voix OneCore par l'API WinRT
    Windows.Media.SpeechSynthesis, projetee dans Windows PowerShell 5.1.
    La synthese produit un flux WAV, ecrit dans un fichier temporaire, joue
    par System.Media.SoundPlayer -- ce qui permet aussi de REJOUER le meme
    message pendant le decompte sans le resynthetiser.

    Aucune fonction de ce fichier ne leve d'exception : la voix est un
    confort, jamais une condition du couvre-feu. Chaque fonction renvoie ce
    qu'elle a reellement pu faire, pour que le diagnostic ne mente pas.

    Ordre de repli : WAV enregistre par le parent > OneCore > SAPI5 > son
    systeme > silence.
#>

Set-StrictMode -Version 2.0

$script:DodoSpeechCache   = @{}    # texte -> chemin du WAV synthetise
$script:DodoSpeechPlayer  = $null
$script:DodoSpeechSynth   = $null
$script:DodoAsTask        = $null

function Get-DodoSpeechTempDir {
    $d = Join-Path $env:TEMP 'Dodo-voix'
    if (-not (Test-Path -LiteralPath $d)) {
        New-Item -ItemType Directory -Path $d -Force | Out-Null
    }
    return $d
}

function Clear-DodoSpeechCache {
    <# Retire les WAV synthetises de plus d'un jour. Jamais bloquant. #>
    try {
        $d = Get-DodoSpeechTempDir
        Get-ChildItem -LiteralPath $d -Filter '*.wav' -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
    catch { }
}

# --------------------------------------------------------------------------
# Enumeration des voix
# --------------------------------------------------------------------------

function Get-DodoSapiVoices {
    <# Voix classiques, via System.Speech. Renvoie un tableau, jamais $null. #>
    $sortie = New-Object System.Collections.Generic.List[object]
    try {
        Add-Type -AssemblyName System.Speech -ErrorAction Stop
        $s = New-Object System.Speech.Synthesis.SpeechSynthesizer
        foreach ($v in $s.GetInstalledVoices()) {
            if (-not $v.Enabled) { continue }
            $sortie.Add([pscustomobject]@{
                Name     = $v.VoiceInfo.Name
                Culture  = $v.VoiceInfo.Culture.Name
                Gender   = [string]$v.VoiceInfo.Gender
                Engine   = 'SAPI'
                IsFrench = ($v.VoiceInfo.Culture.Name -like 'fr*')
            })
        }
        $s.Dispose()
    }
    catch { }
    return $sortie.ToArray()
}

function Get-DodoOneCoreVoices {
    <#
        Voix modernes de Windows 11, via l'API WinRT. Renvoie un tableau vide
        si la projection WinRT n'est pas disponible (Windows 8, edition sans
        composants media, PowerShell 7 hors Windows...).
    #>
    $sortie = New-Object System.Collections.Generic.List[object]
    try {
        # Le litteral de type force le chargement de la projection WinRT.
        [void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]
        foreach ($v in [Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices) {
            $sortie.Add([pscustomobject]@{
                Name     = $v.DisplayName
                Culture  = $v.Language
                Gender   = [string]$v.Gender
                Engine   = 'OneCore'
                IsFrench = ($v.Language -like 'fr*')
                Id       = $v.Id
            })
        }
    }
    catch { }
    return $sortie.ToArray()
}

function Get-DodoAllVoices {
    <#
        Les deux jeux reunis, OneCore d'abord : sur Windows 11 c'est la qu'on
        trouve les voix francaises, et c'est ce que l'utilisateur voit dans
        les Parametres de Windows.
    #>
    $tout = New-Object System.Collections.Generic.List[object]
    foreach ($v in @(Get-DodoOneCoreVoices)) { $tout.Add($v) }
    foreach ($v in @(Get-DodoSapiVoices))    { $tout.Add($v) }
    return $tout.ToArray()
}

function Select-DodoVoice {
    <#
        Choisit la voix a employer.
          1. celle demandee par son nom, si elle existe encore ;
          2. sinon la premiere voix francaise ;
          3. sinon la premiere disponible ;
          4. sinon $null.
        -Engine restreint le choix ('onecore', 'sapi'), 'auto' ne restreint pas.
    #>
    param(
        [string]$VoiceName = '',
        [string]$Engine = 'auto',
        $Voices = $null
    )
    if ($null -eq $Voices) { $Voices = @(Get-DodoAllVoices) }
    $liste = @($Voices)

    switch (("$Engine").ToLowerInvariant()) {
        'onecore' { $liste = @($liste | Where-Object { $_.Engine -eq 'OneCore' }) }
        'sapi'    { $liste = @($liste | Where-Object { $_.Engine -eq 'SAPI' }) }
        default   { }
    }
    if ($liste.Count -eq 0) { return $null }

    if (-not [string]::IsNullOrWhiteSpace($VoiceName)) {
        $exact = @($liste | Where-Object { $_.Name -eq $VoiceName })
        if ($exact.Count -gt 0) { return $exact[0] }
        $partiel = @($liste | Where-Object { $_.Name -like "*$VoiceName*" })
        if ($partiel.Count -gt 0) { return $partiel[0] }
    }

    $fr = @($liste | Where-Object { $_.IsFrench })
    if ($fr.Count -gt 0) { return $fr[0] }
    return $liste[0]
}

# --------------------------------------------------------------------------
# Synthese OneCore (WinRT)
# --------------------------------------------------------------------------

function Get-DodoAsTaskMethod {
    <# Recupere WindowsRuntimeSystemExtensions.AsTask pour IAsyncOperation<T>. #>
    if ($null -ne $script:DodoAsTask) { return $script:DodoAsTask }
    try {
        Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
        $m = @([System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object {
                $_.Name -eq 'AsTask' -and
                $_.IsGenericMethodDefinition -and
                $_.GetParameters().Count -eq 1 -and
                $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1'
            })
        if ($m.Count -eq 0) { return $null }
        $script:DodoAsTask = $m[0]
        return $script:DodoAsTask
    }
    catch { return $null }
}

function ConvertTo-DodoSpeakingRate {
    <# Convertit le reglage -10..10 (echelle SAPI) vers 0.5..2.0 (echelle WinRT). #>
    param([int]$Rate)
    $r = [math]::Max(-10, [math]::Min(10, $Rate))
    if ($r -ge 0) { return 1.0 + ($r * 0.1) }
    return 1.0 + ($r * 0.05)
}

function New-DodoOneCoreWav {
    <#
        Synthetise le texte avec une voix OneCore et renvoie le chemin du WAV
        produit, ou $null en cas d'echec. Ne leve jamais.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        $Voice = $null,
        [int]$Rate = 0,
        [int]$Volume = 100
    )
    try {
        [void][Windows.Media.SpeechSynthesis.SpeechSynthesizer, Windows.Media, ContentType = WindowsRuntime]
        $asTask = Get-DodoAsTaskMethod
        if ($null -eq $asTask) { return $null }

        $synth = New-Object Windows.Media.SpeechSynthesis.SpeechSynthesizer
        try {
            if ($null -ne $Voice -and $Voice.PSObject.Properties['Id']) {
                $cible = @([Windows.Media.SpeechSynthesis.SpeechSynthesizer]::AllVoices |
                           Where-Object { $_.Id -eq $Voice.Id })
                if ($cible.Count -gt 0) { $synth.Voice = $cible[0] }
            }
            try {
                $synth.Options.SpeakingRate = ConvertTo-DodoSpeakingRate $Rate
                $synth.Options.AudioVolume  = [math]::Max(0.0, [math]::Min(1.0, $Volume / 100.0))
            }
            catch { }   # Options absent sur les tres vieilles versions : sans consequence

            $op   = $synth.SynthesizeTextToStreamAsync($Text)
            $task = $asTask.MakeGenericMethod([Windows.Media.SpeechSynthesis.SpeechSynthesisStream]).Invoke($null, @($op))
            # Une synthese qui n'aboutit pas ne doit pas figer l'agent d'alerte.
            if (-not $task.Wait(15000)) { return $null }
            $flux = $task.Result

            Add-Type -AssemblyName System.Runtime.WindowsRuntime -ErrorAction Stop
            $lecture = [System.IO.WindowsRuntimeStreamExtensions]::AsStreamForRead($flux.GetInputStreamAt(0))
            $memoire = New-Object System.IO.MemoryStream
            $lecture.CopyTo($memoire)
            $octets = $memoire.ToArray()
            $memoire.Dispose()
            $lecture.Dispose()
            $flux.Dispose()

            if ($octets.Length -lt 64) { return $null }   # flux vide = echec silencieux

            $nom = 'dodo-{0:x8}.wav' -f ($Text.GetHashCode())
            $chemin = Join-Path (Get-DodoSpeechTempDir) $nom
            [System.IO.File]::WriteAllBytes($chemin, $octets)
            return $chemin
        }
        finally { try { $synth.Dispose() } catch { } }
    }
    catch { return $null }
}

# --------------------------------------------------------------------------
# Diffusion
# --------------------------------------------------------------------------

function Start-DodoWavPlayback {
    <# Joue un WAV sans bloquer. Renvoie $true si la lecture a demarre. #>
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        if (-not (Test-Path -LiteralPath $Path)) { return $false }
        $script:DodoSpeechPlayer = New-Object System.Media.SoundPlayer $Path
        $script:DodoSpeechPlayer.Play()
        return $true
    }
    catch { return $false }
}

function Invoke-DodoSpeak {
    <#
        Prononce le texte. Ne bloque pas, ne leve jamais, renvoie la voie
        reellement utilisee sous forme de chaine lisible dans le journal.

        -WavPath : enregistrement du parent. S'il existe, il gagne sur tout le
        reste : une voix de parent vaut mieux qu'une synthese.

        -Speech : bloc de configuration (enabled, engine, voiceName, rate,
        volume). Absent, les valeurs par defaut s'appliquent.

        Le WAV synthetise est mis en cache par texte : rejouer le meme message
        pendant le decompte ne resynthetise rien.
    #>
    param(
        [string]$Text,
        [string]$WavPath = '',
        $Speech = $null,
        [scriptblock]$OnLog = $null
    )

    function Note([string]$m, [string]$niveau = 'INFO') {
        if ($null -ne $OnLog) { try { & $OnLog $m $niveau } catch { } }
    }

    $active  = $true
    $moteur  = 'auto'
    $nomVoix = ''
    $debit   = 0
    $volume  = 100
    if ($null -ne $Speech) {
        try {
            if ($Speech.PSObject.Properties['enabled'])   { $active  = [bool]$Speech.enabled }
            if ($Speech.PSObject.Properties['engine'])    { $moteur  = [string]$Speech.engine }
            if ($Speech.PSObject.Properties['voiceName']) { $nomVoix = [string]$Speech.voiceName }
            if ($Speech.PSObject.Properties['rate'])      { $debit   = [int]$Speech.rate }
            if ($Speech.PSObject.Properties['volume'])    { $volume  = [int]$Speech.volume }
        }
        catch { }
    }

    if (-not $active -or ("$moteur").ToLowerInvariant() -eq 'off') { return 'voix desactivee' }

    # 1. Enregistrement du parent
    if ($WavPath -and (Test-Path -LiteralPath $WavPath)) {
        if (Start-DodoWavPlayback -Path $WavPath) { return 'enregistrement ' + (Split-Path -Leaf $WavPath) }
        Note "Lecture de $WavPath impossible." 'WARN'
    }
    if (("$moteur").ToLowerInvariant() -eq 'wav') {
        return 'aucun enregistrement trouve (moteur force sur wav)'
    }

    if ([string]::IsNullOrWhiteSpace($Text)) { return 'aucun texte a prononcer' }

    # 2. Voix moderne de Windows 11 (OneCore), rejouee depuis le cache
    if (("$moteur").ToLowerInvariant() -in @('auto', 'onecore')) {
        $cle = $Text
        $chemin = $null
        if ($script:DodoSpeechCache.ContainsKey($cle) -and
            (Test-Path -LiteralPath $script:DodoSpeechCache[$cle])) {
            $chemin = $script:DodoSpeechCache[$cle]
        }
        else {
            $voix = Select-DodoVoice -VoiceName $nomVoix -Engine 'onecore'
            if ($null -ne $voix) {
                $chemin = New-DodoOneCoreWav -Text $Text -Voice $voix -Rate $debit -Volume $volume
                if ($chemin) { $script:DodoSpeechCache[$cle] = $chemin }
            }
        }
        if ($chemin -and (Start-DodoWavPlayback -Path $chemin)) {
            $v = Select-DodoVoice -VoiceName $nomVoix -Engine 'onecore'
            return 'voix Windows ' + $(if ($v) { $v.Name } else { '(par defaut)' })
        }
    }

    # 3. Voix classique SAPI5
    if (("$moteur").ToLowerInvariant() -in @('auto', 'sapi')) {
        try {
            Add-Type -AssemblyName System.Speech -ErrorAction Stop
            $script:DodoSpeechSynth = New-Object System.Speech.Synthesis.SpeechSynthesizer
            $v = Select-DodoVoice -VoiceName $nomVoix -Engine 'sapi'
            if ($null -ne $v) { $script:DodoSpeechSynth.SelectVoice($v.Name) }
            $script:DodoSpeechSynth.Rate   = [math]::Max(-10, [math]::Min(10, $debit))
            $script:DodoSpeechSynth.Volume = [math]::Max(0, [math]::Min(100, $volume))
            $script:DodoSpeechSynth.SpeakAsync($Text) | Out-Null
            if ($null -ne $v -and $v.IsFrench) { return 'voix SAPI ' + $v.Name }
            if ($null -ne $v) { return 'voix SAPI ' + $v.Name + ' (aucune voix francaise trouvee)' }
            return 'voix SAPI par defaut'
        }
        catch { Note "Synthese vocale indisponible : $($_.Exception.Message)" 'WARN' }
    }

    # 4. Dernier recours : un son, pour qu'il se passe quelque chose
    try { [System.Media.SystemSounds]::Exclamation.Play(); return 'son systeme (aucune voix exploitable)' } catch { }
    return 'aucun'
}

function Get-DodoSpeechReport {
    <#
        Etat du sous-systeme vocal, pour le diagnostic et pour l'assistant.
        Ne prononce rien.
    #>
    param($Speech = $null)
    $toutes = @(Get-DodoAllVoices)
    $nomVoix = ''
    $moteur  = 'auto'
    if ($null -ne $Speech) {
        try {
            if ($Speech.PSObject.Properties['voiceName']) { $nomVoix = [string]$Speech.voiceName }
            if ($Speech.PSObject.Properties['engine'])    { $moteur  = [string]$Speech.engine }
        }
        catch { }
    }
    $choisie = Select-DodoVoice -VoiceName $nomVoix -Engine $moteur -Voices $toutes
    return [pscustomobject]@{
        Voices        = $toutes
        OneCoreCount  = @($toutes | Where-Object { $_.Engine -eq 'OneCore' }).Count
        SapiCount     = @($toutes | Where-Object { $_.Engine -eq 'SAPI' }).Count
        FrenchCount   = @($toutes | Where-Object { $_.IsFrench }).Count
        Selected      = $choisie
        WinRtAvailable = ($null -ne (Get-DodoAsTaskMethod))
    }
}
