<#
.SYNOPSIS
    Vypise nainstalovane MSI balicky, necha vybrat a odinstaluje je.

.DESCRIPTION
    Obecny nastroj pro rucni i davkovou odinstalaci MSI balicku.
    - Interaktivne: vypise ocislovany seznam (volitelne zuzeny -Filter),
      uzivatel zada cisla k odinstalaci, potvrdi.
    - Davkove: -ProductCode / -ProductName + -Force bez dotazu (Ansible).
    - Odinstalace pres msiexec /x /qn s verbose logem per balicek.
    - Volitelny uklid po odinstalaci:
        -FileExtension : smaze per-user UserChoice pripony, pokud jeji ProgID
                         uz neexistuje (stale asociace po odinstalaci)
        -ShortcutFolder: smaze Start-menu slozky, ve kterych zbyly jen
                         .lnk/.rdp/.ico
    - Idempotentni (1605 = uz odinstalovano => OK).
    - Ansible-ready: stdout = pouze JSON (krome interaktivniho rezimu), log do souboru.
    - Vyzaduje elevated (Administrator) pristup pro per-machine balicky.

.PARAMETER List
    Pouze vypise nainstalovane MSI (JSON). Zadne zmeny.

.PARAMETER Filter
    Wildcard na DisplayName pro zuzeni seznamu (napr. "*RemoteApp*").
    Vychozi: vse.

.PARAMETER ProductName
    Vzory DisplayName k odinstalaci (wildcard). Lze vice hodnot.

.PARAMETER ProductCode
    ProductCode GUIDy k odinstalaci (se slozenymi zavorkami). Lze vice hodnot.

.PARAMETER FileExtension
    Pripony, u kterych se po odinstalaci overi/uklidi per-user UserChoice.

.PARAMETER ShortcutFolder
    Nazvy Start-menu slozek (all users + current user) k uklidu.

.PARAMETER LogPath
    Cesta k log souboru. Vychozi: logs\Uninstall-MsiPackage.log vedle skriptu.

.PARAMETER DryRun
    Simulace bez provedeni zmen.

.PARAMETER Force
    Bez potvrzeni (Ansible / davka). Vyzaduje -ProductName nebo -ProductCode.

.EXAMPLE
    .\Uninstall-MsiPackage.ps1 -List

.EXAMPLE
    .\Uninstall-MsiPackage.ps1 -Filter "*RemoteApp*"
    # interaktivni vyber a odinstalace

.EXAMPLE
    .\Uninstall-MsiPackage.ps1 -ProductCode "{GUID}" -FileExtension .abc -Force

.NOTES
    Nazev:   Uninstall-MsiPackage.ps1
    Autor:   David Nemecek
    Verze:   1.0.0
    Vyzaduje: Windows 10/11, PowerShell 5.1

    SECURITY WARNING:
    - Odinstalace je nevratna. Vzdy nejdriv -List / -DryRun.
    - Wildcard v -ProductName drz co nejuzsi.
#>

[CmdletBinding()]
param (
    [switch]$List,
    [string]$Filter = '*',
    [string[]]$ProductName = @(),
    [string[]]$ProductCode = @(),
    [string[]]$FileExtension = @(),
    [string[]]$ShortcutFolder = @(),
    [string]$LogPath,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$scriptVersion = '1.0.0'
if (-not $LogPath) { $LogPath = Join-Path $PSScriptRoot 'logs\Uninstall-MsiPackage.log' }
. (Join-Path $PSScriptRoot 'common\Add-Log.ps1')
function Log { param([string]$M, [string]$L = 'INFO') Add-Log -Message $M -Level $L -LogFile $LogPath -StartTime $startTime }

$result = [ordered]@{
    changed = $false; dry_run = [bool]$DryRun; elevated = $false
    selected = @(); removed = @(); failed = @(); assoc_cleaned = @(); folders_removed = @()
    reboot_required = $false; warnings = @(); log = $LogPath
}

function Test-Elevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-InstalledMsi {
    $paths = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
             'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    Get-ItemProperty $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and ($_.WindowsInstaller -eq 1 -or $_.UninstallString -match 'msiexec') } |
        ForEach-Object {
            [pscustomobject]@{
                name = $_.DisplayName; version = $_.DisplayVersion; vendor = $_.Publisher
                code = $_.PSChildName; date = $_.InstallDate
                scope = if ($_.PSPath -match 'HKEY_CURRENT_USER') { 'user' } else { 'machine' }
            }
        } | Sort-Object name -Unique
}

function Get-AssocState {
    param([string[]]$Ext)
    foreach ($e in $Ext) {
        if (-not $e.StartsWith('.')) { $e = ".$e" }
        $uc = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$e\UserChoice"
        $progid = (Get-ItemProperty $uc -ErrorAction SilentlyContinue).ProgId
        $valid = $false
        if ($progid) { $valid = Test-Path "Registry::HKEY_CLASSES_ROOT\$progid" }
        [pscustomobject]@{ ext = $e; userchoice = $progid; userchoice_valid = $valid; path = $uc }
    }
}

Log "=== Uninstall-MsiPackage v$scriptVersion start (dry_run=$DryRun, list=$List, filter=$Filter)"
$result.elevated = Test-Elevated
$installed = @(Get-InstalledMsi | Where-Object { $_.name -like $Filter })

# ---------------------------------------------------------------- list
if ($List) {
    $result.packages = $installed
    $result.assoc = @(Get-AssocState -Ext $FileExtension)
    Log "List: $($installed.Count) packages"
    $result | ConvertTo-Json -Depth 5; exit 0
}

# ---------------------------------------------------------------- selection
$selected = @()
if ($ProductName -or $ProductCode) {
    $selected = @($installed | Where-Object {
        $n = $_.name; $c = $_.code
        ($ProductName | Where-Object { $n -like $_ }) -or ($ProductCode | Where-Object { $c -ieq $_ })
    })
} elseif (-not $Force) {
    if ($installed.Count -eq 0) { Write-Host "No MSI packages match filter '$Filter'."; exit 0 }
    Write-Host ""
    Write-Host "Installed MSI packages (filter: $Filter)"
    Write-Host "----------------------------------------"
    for ($i = 0; $i -lt $installed.Count; $i++) {
        $p = $installed[$i]
        Write-Host ("{0,3}. {1,-50} {2,-12} {3,-8} {4}" -f ($i + 1), $p.name, $p.version, $p.scope, $p.code)
    }
    Write-Host ""
    $input = Read-Host 'Numbers to uninstall (e.g. 1,3,5) or Enter to quit'
    if (-not $input.Trim()) { Log 'Nothing selected'; exit 0 }
    $idx = $input -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $installed.Count } | Sort-Object -Unique
    $selected = @($installed[$idx])
} else {
    $result.warnings += '-Force requires -ProductName or -ProductCode.'
    Log $result.warnings[-1] 'ERROR'; $result | ConvertTo-Json -Depth 4; exit 2
}

$result.selected = @($selected | ForEach-Object { "$($_.name) [$($_.code)]" })
if ($selected.Count -eq 0) { $result.warnings += 'No package matched.'; Log $result.warnings[-1] 'WARNING'; $result | ConvertTo-Json -Depth 4; exit 0 }

if (($selected | Where-Object scope -eq 'machine') -and -not $result.elevated -and -not $DryRun) {
    $result.warnings += 'Per-machine MSI uninstall requires elevation (Administrator).'
    Log $result.warnings[-1] 'ERROR'; $result | ConvertTo-Json -Depth 4; exit 3
}

if (-not $Force -and -not $DryRun) {
    Write-Host ""
    Write-Host "Will uninstall:"; $result.selected | ForEach-Object { Write-Host "  - $_" }
    if ((Read-Host 'Continue? [y/N]') -notmatch '^[yY]') { Log 'Aborted by user' 'WARNING'; exit 4 }
}

# ---------------------------------------------------------------- uninstall
foreach ($m in $selected) {
    $msiLog = Join-Path (Split-Path $LogPath -Parent) ("msi_" + ($m.code -replace '[{}]', '') + ".log")
    if ($DryRun) { Log "DRY-RUN: msiexec /x $($m.code) ($($m.name))"; continue }
    Log "Uninstalling $($m.name) $($m.code)"
    $p = Start-Process msiexec.exe -ArgumentList "/x $($m.code) /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -NoNewWindow
    switch ($p.ExitCode) {
        0       { $result.removed += $m.code; $result.changed = $true; Log "OK $($m.code)" }
        1605    { $result.removed += $m.code; Log "Already removed $($m.code)" }
        3010    { $result.removed += $m.code; $result.changed = $true; $result.reboot_required = $true; Log "OK, reboot required $($m.code)" 'WARNING' }
        default { $result.failed += "$($m.code):$($p.ExitCode)"; Log "FAILED $($m.code) exit=$($p.ExitCode) see $msiLog" 'ERROR' }
    }
}

# ---------------------------------------------------------------- stale associations
foreach ($a in (Get-AssocState -Ext $FileExtension)) {
    if ($a.userchoice -and -not $a.userchoice_valid) {
        if ($DryRun) { Log "DRY-RUN: remove $($a.path) (ProgId $($a.userchoice) missing)"; continue }
        Remove-Item $a.path -Force
        $result.assoc_cleaned += $a.ext; $result.changed = $true
        Log "Removed stale UserChoice $($a.ext) -> $($a.userchoice)"
    } elseif ($a.userchoice) { Log "UserChoice $($a.ext) -> $($a.userchoice) valid, kept" }
}

# ---------------------------------------------------------------- shortcut folders
foreach ($f in $ShortcutFolder) {
    foreach ($root in "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:AppData\Microsoft\Windows\Start Menu\Programs") {
        $dir = Join-Path $root $f
        if (-not (Test-Path $dir)) { continue }
        $other = Get-ChildItem $dir -Recurse -File | Where-Object { $_.Extension -notin '.rdp', '.lnk', '.ico' }
        if ($other) { $result.warnings += "Folder kept (non-shortcut files): $dir"; Log $result.warnings[-1] 'WARNING'; continue }
        if ($DryRun) { Log "DRY-RUN: remove folder $dir"; continue }
        Remove-Item $dir -Recurse -Force
        $result.folders_removed += $dir; $result.changed = $true; Log "Removed folder $dir"
    }
}

Log "=== done changed=$($result.changed) removed=$($result.removed.Count) failed=$($result.failed.Count)"
$result | ConvertTo-Json -Depth 4
if ($result.failed.Count -gt 0) { exit 1 } else { exit 0 }
