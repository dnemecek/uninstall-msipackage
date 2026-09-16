@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM -NonInteractive se prida jen pri presnem tokenu -Force v argumentech
REM (davkovy/Ansible rezim, kde se Read-Host nikdy nevola - viz
REM Uninstall-MsiPackage.ps1). Parsovani pres shift/goto, NE 'for %%A in
REM (%*)' - ten v cmd.exe dela wildcard-expanzi (FindFirstFile) na kazde
REM polozce obsahujici * nebo ? i v uvozovkach, takze by napr.
REM -ProductName "WorkForce Client*" mohl matchovat soubory v aktualnim
REM adresari misto doslovneho textu.
REM Bez -Force zustava beh plne interaktivni - zadne vetveni ani
REM presmerovani kolem samotneho volani powershell.exe (historie:
REM Read-Host uvnitr if/else bloku s presmerovanim byl v nekterych
REM verzich cmd.exe nespolehlivy, viz git log).

set "scriptPath=%~dp0"
set "scriptName=%~n0"
set "extraFlag="

:parseArgs
if "%~1"=="" goto argsParsed
if /i "%~1"=="-Force" set "extraFlag=-NonInteractive"
shift
goto parseArgs
:argsParsed

powershell.exe -ExecutionPolicy Bypass -NoProfile %extraFlag% -File "%scriptPath%%scriptName%.ps1" %*
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
