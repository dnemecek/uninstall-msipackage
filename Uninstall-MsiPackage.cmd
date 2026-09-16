@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM -NonInteractive se prida jen pri presnem tokenu -Force v argumentech
REM (davkovy/Ansible rezim, kde se Read-Host nikdy nevola - viz
REM Uninstall-MsiPackage.ps1). Presny token match (ne substring) - napr.
REM -ProductName "WorkForce Client*" nema false-positive na -Force.
REM Bez -Force zustava beh plne interaktivni - zadne vetveni ani
REM presmerovani kolem samotneho volani powershell.exe (historie:
REM Read-Host uvnitr if/else bloku s presmerovanim byl v nekterych
REM verzich cmd.exe nespolehlivy, viz git log).

set "scriptPath=%~dp0"
set "scriptName=%~n0"
set "extraFlag="

for %%A in (%*) do if /i "%%~A"=="-Force" set "extraFlag=-NonInteractive"

powershell.exe -ExecutionPolicy Bypass -NoProfile %extraFlag% -File "%scriptPath%%scriptName%.ps1" %*
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
