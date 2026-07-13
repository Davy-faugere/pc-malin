@echo off
setlocal
echo ============================================
echo   PC Malin - demarrage
echo ============================================
echo.

net file >nul 2>&1
if errorlevel 1 (
    echo Windows va demander une autorisation, c'est normal...
    powershell -NoProfile -Command "Start-Process cmd -ArgumentList '/c \"\"%~f0\"\"' -Verb RunAs"
    exit /b
)
echo [1/3] Autorisation : OK

set "PS=%temp%\pcmalin_%random%.ps1"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$all=@(Get-Content -LiteralPath '%~f0'); for($n=0;$n -lt $all.Count;$n++){ if($all[$n].Trim() -ceq 'ZZ_PSSTART_ZZ'){ $all[($n+1)..($all.Count-1)] | Set-Content -LiteralPath '%PS%' -Encoding UTF8; break } }"

if not exist "%PS%" (
    echo [2/3] Preparation : ECHEC
    pause
    exit /b 1
)
echo [2/3] Preparation : OK

echo [3/3] Ouverture de PC Malin...
echo.
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%PS%" -SrcCmd "%~f0"
set "RC=%errorlevel%"
del "%PS%" >nul 2>&1

if not "%RC%"=="0" (
    echo.
    echo   Un souci est survenu ^(code %RC%^) - message ci-dessus.
    pause
)
exit /b

ZZ_PSSTART_ZZ
