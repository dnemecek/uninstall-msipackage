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
    - Ansible-ready: stdout = pouze JSON, log do souboru.
      Vyjimka: interaktivni rezim (bez -Force) pise vyber/dotazy na konzoli.
    - Vyzaduje elevated (Administrator) pristup pro per-machine balicky.

.PARAMETER List
    Pouze vypise nainstalovane MSI jako tabulku (s -Json jako JSON). Zadne zmeny.
    Respektuje -Filter, -Vendor, -ProductName, -ProductCode.

.PARAMETER Filter
    Wildcard na DisplayName pro zuzeni seznamu (napr. "*RemoteApp*").
    Vychozi: vse.

.PARAMETER Vendor
    Wildcard na Publisher pro zuzeni seznamu (napr. "Administrator" =
    RemoteApp balicky generovane RemoteApp Managerem). Vychozi: vse.

.PARAMETER Json
    Vystup -List jako JSON misto tabulky (Ansible).

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
    .\Uninstall-MsiPackage.ps1 -List -Vendor Administrator -Json

.EXAMPLE
    .\Uninstall-MsiPackage.ps1 -Vendor Administrator
    # interaktivni vyber a odinstalace balicku daneho vydavatele

.EXAMPLE
    .\Uninstall-MsiPackage.ps1 -ProductCode "{GUID}" -FileExtension .abc -Force

.NOTES
    Nazev:   Uninstall-MsiPackage.ps1
    Autor:   David Nemecek
    Verze:   1.1.0
    Vyzaduje: Windows 10/11, PowerShell 5.1

    SECURITY WARNING:
    - Odinstalace je nevratna. Vzdy nejdriv -List / -DryRun.
    - Wildcard v -ProductName drz co nejuzsi.
#>

[CmdletBinding()]
param (
    [switch]$List,
    [string]$Filter = '*',
    [string]$Vendor = '*',
    [switch]$Json,
    [string[]]$ProductName = @(),
    [ValidatePattern('^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$')]
    [string[]]$ProductCode = @(),
    [ValidatePattern('^\.?[A-Za-z0-9]+$')]
    [string[]]$FileExtension = @(),
    [ValidatePattern('^(?!\.\.?$)[^\\/:*?"<>|]+$')]
    [string[]]$ShortcutFolder = @(),
    [string]$LogPath,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$startTime = Get-Date
$scriptVersion = '1.1.0'
if (-not $LogPath) { $LogPath = Join-Path $PSScriptRoot 'logs\Uninstall-MsiPackage.log' }
. (Join-Path $PSScriptRoot 'common\Add-Log.ps1')
function Write-Log { param([string]$Message, [string]$Level = 'INFO') Add-Log -Message $Message -Level $Level -LogFile $LogPath -StartTime $startTime }

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
        } | Group-Object code | ForEach-Object { $_.Group[0] } | Sort-Object name
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

try {
    Write-Log "=== Uninstall-MsiPackage v$scriptVersion start (dry_run=$DryRun, list=$List, filter=$Filter, vendor=$Vendor)"
    $result.elevated = Test-Elevated
    $installed = @(Get-InstalledMsi | Where-Object { $_.name -like $Filter -and ($_.vendor -like $Vendor -or (-not $_.vendor -and $Vendor -eq '*')) })
    if ($ProductName -or $ProductCode) {
        $installed = @($installed | Where-Object {
            $n = $_.name; $c = $_.code
            ($ProductName | Where-Object { $n -like $_ }) -or ($ProductCode | Where-Object { $c -ieq $_ })
        })
    }
    
    # ---------------------------------------------------------------- list
    if ($List) {
        Write-Log "List: $($installed.Count) packages"
        if ($Json) {
            $result.packages = $installed
            $result.assoc = @(Get-AssocState -Ext $FileExtension)
            $result | ConvertTo-Json -Depth 5
        } else {
            Write-Host ""
            Write-Host "Installed MSI packages (filter: $Filter, vendor: $Vendor) - $($installed.Count)"
            $installed | Format-Table @{n='Name';e={$_.name}}, @{n='Version';e={$_.version}}, @{n='Vendor';e={$_.vendor}}, @{n='Scope';e={$_.scope}}, @{n='ProductCode';e={$_.code}} -AutoSize | Out-String -Width 220 | Write-Host
            $assoc = @(Get-AssocState -Ext $FileExtension)
            if ($assoc) { $assoc | Format-Table ext, userchoice, userchoice_valid -AutoSize | Out-String | Write-Host }
        }
        exit 0
    }
    
    # ---------------------------------------------------------------- selection
    $selected = @()
    if ($ProductName -or $ProductCode) {
        $selected = $installed
    } elseif (-not $Force) {
        if ($installed.Count -eq 0) { Write-Host "No MSI packages match filter '$Filter'."; exit 0 }
        Write-Host ""
        Write-Host "Installed MSI packages (filter: $Filter, vendor: $Vendor)"
        Write-Host "----------------------------------------"
        for ($i = 0; $i -lt $installed.Count; $i++) {
            $p = $installed[$i]
            Write-Host ("{0,3}. {1,-50} {2,-12} {3,-8} {4}" -f ($i + 1), $p.name, $p.version, $p.scope, $p.code)
        }
        Write-Host ""
        $input = Read-Host 'Numbers to uninstall (e.g. 1,3,5) or Enter to quit'
        if (-not $input.Trim()) { Write-Log 'Nothing selected'; exit 0 }
        $idx = $input -split '[,\s]+' | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ - 1 } | Where-Object { $_ -ge 0 -and $_ -lt $installed.Count } | Sort-Object -Unique
        $selected = @($installed[$idx])
    } else {
        $result.warnings += '-Force requires -ProductName or -ProductCode.'
        Write-Log $result.warnings[-1] 'ERROR'; $result | ConvertTo-Json -Depth 4; exit 2
    }
    
    $result.selected = @($selected | ForEach-Object { "$($_.name) [$($_.code)]" })
    if ($selected.Count -eq 0) { $result.warnings += 'No package matched.'; Write-Log $result.warnings[-1] 'WARNING'; $result | ConvertTo-Json -Depth 4; exit 0 }
    
    if (($selected | Where-Object scope -eq 'machine') -and -not $result.elevated -and -not $DryRun) {
        $result.warnings += 'Per-machine MSI uninstall requires elevation (Administrator).'
        Write-Log $result.warnings[-1] 'ERROR'; $result | ConvertTo-Json -Depth 4; exit 3
    }
    
    if (-not $Force -and -not $DryRun) {
        Write-Host ""
        Write-Host "Will uninstall:"; $result.selected | ForEach-Object { Write-Host "  - $_" }
        if ((Read-Host 'Continue? [y/N]') -notmatch '^[yY]') { Write-Log 'Aborted by user' 'WARNING'; exit 4 }
    }
    
    # ---------------------------------------------------------------- uninstall
    $productCodePattern = '^\{[0-9A-Fa-f]{8}-([0-9A-Fa-f]{4}-){3}[0-9A-Fa-f]{12}\}$'
    foreach ($m in $selected) {
        if ($m.code -notmatch $productCodePattern) {
            $result.failed += "$($m.code):invalid_product_code_format"
            Write-Log "SKIPPED $($m.name) - code '$($m.code)' neni platny MSI ProductCode GUID, msiexec se nevola" 'ERROR'
            continue
        }
        $msiLog = Join-Path (Split-Path $LogPath -Parent) ("msi_" + ($m.code -replace '[{}]', '') + ".log")
        if ($DryRun) { Write-Log "DRY-RUN: msiexec /x $($m.code) ($($m.name))"; continue }
        Write-Log "Uninstalling $($m.name) $($m.code)"
        $p = Start-Process msiexec.exe -ArgumentList "/x $($m.code) /qn /norestart /l*v `"$msiLog`"" -Wait -PassThru -NoNewWindow
        switch ($p.ExitCode) {
            0       { $result.removed += $m.code; $result.changed = $true; Write-Log "OK $($m.code)" }
            1605    { $result.removed += $m.code; Write-Log "Already removed $($m.code)" }
            3010    { $result.removed += $m.code; $result.changed = $true; $result.reboot_required = $true; Write-Log "OK, reboot required $($m.code)" 'WARNING' }
            default { $result.failed += "$($m.code):$($p.ExitCode)"; Write-Log "FAILED $($m.code) exit=$($p.ExitCode) see $msiLog" 'ERROR' }
        }
    }
    
    # ---------------------------------------------------------------- stale associations
    foreach ($a in (Get-AssocState -Ext $FileExtension)) {
        if ($a.userchoice -and -not $a.userchoice_valid) {
            if ($DryRun) { Write-Log "DRY-RUN: remove $($a.path) (ProgId $($a.userchoice) missing)"; continue }
            Remove-Item $a.path -Force
            $result.assoc_cleaned += $a.ext; $result.changed = $true
            Write-Log "Removed stale UserChoice $($a.ext) -> $($a.userchoice)"
        } elseif ($a.userchoice) { Write-Log "UserChoice $($a.ext) -> $($a.userchoice) valid, kept" }
    }
    
    # ---------------------------------------------------------------- shortcut folders
    foreach ($f in $ShortcutFolder) {
        foreach ($root in "$env:ProgramData\Microsoft\Windows\Start Menu\Programs", "$env:AppData\Microsoft\Windows\Start Menu\Programs") {
            $dir = Join-Path $root $f
            if (-not (Test-Path $dir)) { continue }
            $other = Get-ChildItem $dir -Recurse -File | Where-Object { $_.Extension -notin '.rdp', '.lnk', '.ico' }
            if ($other) { $result.warnings += "Folder kept (non-shortcut files): $dir"; Write-Log $result.warnings[-1] 'WARNING'; continue }
            if ($DryRun) { Write-Log "DRY-RUN: remove folder $dir"; continue }
            Remove-Item $dir -Recurse -Force
            $result.folders_removed += $dir; $result.changed = $true; Write-Log "Removed folder $dir"
        }
    }
    
    Write-Log "=== done changed=$($result.changed) removed=$($result.removed.Count) failed=$($result.failed.Count)"
    $result | ConvertTo-Json -Depth 4
    if ($result.failed.Count -gt 0) { exit 1 } else { exit 0 }
}
catch {
    Write-Log "FATAL: $($_.Exception.Message)" -Level ERROR
    Write-Log "Stack: $($_.ScriptStackTrace)" -Level ERROR
    $result.error = $_.Exception.Message
    $result | ConvertTo-Json -Depth 4
    exit 1
}
