@echo off
REM Uninstall-MsiPackage - CMD Launcher
REM Autor: David Nemecek | Zari 2026
REM
REM Pouziti:
REM   Uninstall-MsiPackage.cmd -List
REM   Uninstall-MsiPackage.cmd -Filter "*RemoteApp*"            (interaktivni vyber)
REM   Uninstall-MsiPackage.cmd -ProductCode {GUID} -Force [-DryRun] [-FileExtension .x] [-ShortcutFolder N]
REM
REM Vyzaduje: elevated (Administrator) pristup pro per-machine MSI

set "scriptPath=%~dp0"
set "scriptName=%~n0"

set "hasVerbose=0"
for %%a in (%*) do (
    if /i "%%~a"=="-Verbose" set "hasVerbose=1"
)

if "%hasVerbose%"=="1" (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File "%scriptPath%%scriptName%.ps1" %*
) else (
    powershell.exe -ExecutionPolicy Bypass -NoProfile -NonInteractive -File "%scriptPath%%scriptName%.ps1" %* 2>nul
)
set "exitCode=%ERRORLEVEL%"
exit /b %exitCode%
