@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM bez -Force = interaktivni rezim (Read-Host vyber/potvrzeni)
REM -Force     = davkovy rezim (Ansible), bez dotazu
REM -Verbose   = stderr do konzole; jinak stderr potlacen (chyby v logu)

set "scriptPath=%~dp0"
set "scriptName=%~n0"

set "hasVerbose=0"
for %%a in (%*) do (
    if /i "%%~a"=="-Verbose" set "hasVerbose=1"
)

if "%hasVerbose%"=="1" (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%scriptPath%%scriptName%.ps1" %*
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%scriptPath%%scriptName%.ps1" %* 2>nul
)
set "exitCode=%ERRORLEVEL%"

exit /b %exitCode%
