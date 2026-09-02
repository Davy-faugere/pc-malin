#Requires -Version 5.1
<#
    Add-DodoException.ps1 - Derogation ponctuelle accordee par un parent.

    A lancer EN ADMINISTRATEUR. Fait deux choses :
      1. annule une extinction deja engagee (shutdown /a) ;
      2. depose var\exception.json, que l'agent relit a la minute suivante.

    Exemples :
        .\Add-DodoException.ps1 -Minutes 60 -Reason "film en famille"
        .\Add-DodoException.ps1 -Until "23:45"
        .\Add-DodoException.ps1 -Cancel
#>
[CmdletBinding(DefaultParameterSetName = 'Duration')]
param(
    [Parameter(ParameterSetName = 'Duration')][ValidateRange(1, 720)][int]$Minutes = 60,
    [Parameter(ParameterSetName = 'Until')][string]$Until,
    [Parameter(ParameterSetName = 'Cancel')][switch]$Cancel,
    [string]$Reason = 'non precise',
    [string]$Root
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DodoCore.ps1')
. (Join-Path $PSScriptRoot 'DodoRuntime.ps1')

$id = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $id.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Ce script doit etre lance en tant qu'administrateur." -ForegroundColor Red
    exit 1
}

$paths = Get-DodoPaths -Root $Root

if ($Cancel) {
    if (Test-Path -LiteralPath $paths.Exception) {
        Remove-Item -LiteralPath $paths.Exception -Force
        Write-Host 'Derogation annulee : la regle redevient active a la minute suivante.' -ForegroundColor Yellow
    }
    else { Write-Host 'Aucune derogation en cours.' -ForegroundColor DarkGray }
    Write-DodoLog -Message "Derogation annulee par $($id.Identity.Name)." -Level 'ACTION' -LogDirectory $paths.Logs -AlsoEventLog | Out-Null
    exit 0
}

if ($PSCmdlet.ParameterSetName -eq 'Until') {
    $target = [datetime]::Parse($Until, [System.Globalization.CultureInfo]::GetCultureInfo('fr-FR'))
    if ($target -le (Get-Date)) { $target = $target.AddDays(1) }
}
else { $target = (Get-Date).AddMinutes($Minutes) }

# 1. Annuler une extinction deja engagee (sans echouer s'il n'y en a pas)
try {
    $p = Start-Process -FilePath 'shutdown.exe' -ArgumentList @('/a') -NoNewWindow -Wait -PassThru -ErrorAction Stop
    if ($p.ExitCode -eq 0) { Write-Host 'Extinction en cours annulee.' -ForegroundColor Green }
}
catch { }
if (Test-Path -LiteralPath $paths.Pending) { Remove-Item -LiteralPath $paths.Pending -Force -ErrorAction SilentlyContinue }

# 2. Poser la derogation
Write-DodoJson -Path $paths.Exception -Object ([pscustomobject]@{
    until     = $target.ToString('o')
    reason    = $Reason
    grantedBy = $id.Identity.Name
    createdAt = (Get-Date).ToString('o')
})
Write-DodoLog -Message "Derogation accordee jusqu'a $($target.ToString('yyyy-MM-dd HH:mm')) par $($id.Identity.Name) - motif : $Reason" -Level 'ACTION' -LogDirectory $paths.Logs -AlsoEventLog | Out-Null

Write-Host ("Derogation active jusqu'a {0}. Motif : {1}" -f $target.ToString('dddd dd/MM HH:mm'), $Reason) -ForegroundColor Green
Write-Host 'Pour l annuler plus tot : .\Add-DodoException.ps1 -Cancel' -ForegroundColor DarkGray
