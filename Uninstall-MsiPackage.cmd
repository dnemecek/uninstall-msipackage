@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM -Force     = davkovy rezim (Ansible): NonInteractive, bez dotazu
REM bez -Force = interaktivni rezim (Read-Host vyber/potvrzeni)
REM -Verbose   = stderr do konzole; jinak stderr potlacen (chyby v logu)

setlocal
set "scriptPath=%~dp0"
set "scriptName=%~n0"
set "hasVerbose=0"
set "hasForce=0"
for %%a in (%*) do (
    if /i "%%~a"=="-Verbose" set "hasVerbose=1"
    if /i "%%~a"=="-Force" set "hasForce=1"
)

set "PS=powershell.exe -ExecutionPolicy Bypass -NoProfile"
if "%hasForce%"=="1" set "PS=%PS% -NonInteractive"
set "PS=%PS% -File "%scriptPath%%scriptName%.ps1""

if "%hasVerbose%"=="1" (
    %PS% %*
) else (
    %PS% %* 2^>nul
)
set "exitCode=%ERRORLEVEL%"
endlocal & exit /b %exitCode%
