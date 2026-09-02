' run-notify-hidden.vbs - lance l'agent d'alerte sans faire clignoter de console.
' Place dans le meme dossier que Show-DodoWarning.ps1 ; se localise tout seul.
Option Explicit
Dim sh, fso, here, cmd
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
here = fso.GetParentFolderName(WScript.ScriptFullName)
cmd = "powershell.exe -NoProfile -NonInteractive -Sta -ExecutionPolicy Bypass -File """ & here & "\Show-DodoWarning.ps1"""
sh.Run cmd, 0, False
