@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM Zadny redirect/vetveni - identicke chovani jako primy vyvolani .ps1
REM (interaktivni Read-Host je uvnitr if/else bloku s '>' redirekci
REM nespolehlivy v nekterych verzich cmd.exe - proto zde neresime).

set "scriptPath=%~dp0"
set "scriptName=%~n0"

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%scriptPath%%scriptName%.ps1" %*
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
