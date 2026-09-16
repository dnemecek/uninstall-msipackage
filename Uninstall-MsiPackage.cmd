@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM -NonInteractive se prida jen pri -Force (davkovy/Ansible rezim, kde se
REM Read-Host nikdy nevola - viz Uninstall-MsiPackage.ps1). Bez -Force
REM zustava beh plne interaktivni - zadne vetveni ani presmerovani kolem
REM samotneho volani powershell.exe (historie: Read-Host uvnitr if/else
REM bloku s presmerovanim byl v nekterych verzich cmd.exe nespolehlivy,
REM viz git log).

set "scriptPath=%~dp0"
set "scriptName=%~n0"
set "extraFlag="

echo %*| findstr /i /c:"-force" >nul
if not errorlevel 1 set "extraFlag=-NonInteractive"

powershell.exe -ExecutionPolicy Bypass -NoProfile %extraFlag% -File "%scriptPath%%scriptName%.ps1" %*
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
