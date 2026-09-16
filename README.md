# Uninstall-MsiPackage

Vypíše nainstalované MSI balíčky, nechá vybrat a odinstaluje je. Volitelně uklidí
zbylé per-user asociace přípon a Start-menu složky se zástupci.

## Použití

```
Uninstall-MsiPackage.cmd -List                          # jen výpis (JSON)
Uninstall-MsiPackage.cmd -Filter "*RemoteApp*"          # interaktivní výběr + odinstalace
Uninstall-MsiPackage.cmd -ProductCode "{GUID}" -Force   # dávkově, bez dotazů
Uninstall-MsiPackage.cmd -ProductName "MyApp*" -FileExtension .abc -ShortcutFolder "MyApp" -DryRun -Force
```

Vyžaduje: Windows 10/11, PowerShell 5.1, oprávnění správce pro per-machine balíčky.
Log: `logs\Uninstall-MsiPackage.log` + `logs\msi_<ProductCode>.log` (verbose msiexec).

## Struktura

```
Uninstall-MsiPackage.ps1   hlavní skript
Uninstall-MsiPackage.cmd   CMD launcher (ExecutionPolicy Bypass)
common/                    submodul dnemecek/ps-common
logs/                      logy (mimo git)
```

## Autor

David Němeček
