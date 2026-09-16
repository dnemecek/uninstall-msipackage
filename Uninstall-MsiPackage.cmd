@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM Pouziti:
REM   Uninstall-MsiPackage.cmd -List [-Filter "*x*"] [-Vendor "y"] [-Json]
REM   Uninstall-MsiPackage.cmd -Filter "*RemoteApp*"            (interaktivni vyber)
REM   Uninstall-MsiPackage.cmd -ProductCode {GUID} -Force [-DryRun] [-FileExtension .x] [-ShortcutFolder N]
REM
REM Vyzaduje: elevated (Administrator) pristup pro per-machine MSI

set "scriptPath=%~dp0"
set "scriptName=%~n0"

REM Detekce -Verbose a -Force v argumentech
REM -Force  = davkovy rezim (Ansible): NonInteractive, bez dotazu
REM bez -Force = interaktivni rezim (Read-Host vyber/potvrzeni)
set "hasVerbose=0"
set "hasForce=0"
for %%a in (%*) do (
    if /i "%%~a"=="-Verbose" set "hasVerbose=1"
    if /i "%%~a"=="-Force" set "hasForce=1"
)
set "psMode="
if "%hasForce%"=="1" set "psMode=-NonInteractive"

if "%hasVerbose%"=="1" (
    powershell.exe -ExecutionPolicy Bypass -NoProfile %psMode% -File "%scriptPath%%scriptName%.ps1" %*
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile %psMode% -File "%scriptPath%%scriptName%.ps1" %* 2>nul
)
set "exitCode=%ERRORLEVEL%"
exit /b %exitCode%
