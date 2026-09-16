# Uninstall-MsiPackage

Vypíše nainstalované MSI balíčky, nechá vybrat a odinstaluje je. Volitelně uklidí
zbylé per-user asociace přípon a Start-menu složky se zástupci.

## Použití

```
Uninstall-MsiPackage.cmd -List                          # výpis (tabulka); -Json pro JSON
Uninstall-MsiPackage.cmd -List -Vendor Administrator    # jen balíčky daného vydavatele
Uninstall-MsiPackage.cmd -Vendor Administrator          # interaktivní výběr + odinstalace
Uninstall-MsiPackage.cmd -Filter "*RemoteApp*"          # totéž, filtr podle názvu
Uninstall-MsiPackage.cmd -ProductCode "{GUID}" -Force   # dávkově, bez dotazů
Uninstall-MsiPackage.cmd -ProductName "MyApp*" -FileExtension .abc -ShortcutFolder "MyApp" -DryRun -Force
```

Vyžaduje: Windows 10/11, PowerShell 5.1, oprávnění správce pro per-machine balíčky.
Log: `logs\Uninstall-MsiPackage.log` + `logs\msi_<ProductCode>.log` (verbose msiexec).

## Instalace

```
git clone --recurse-submodules https://github.com/dnemecek/uninstall-msipackage.git
```

Bez `--recurse-submodules` zůstane `common/` prázdná a skript selže na chybějícím `Add-Log.ps1`.
Git na Windows: `winget install --id Git.Git -e --source winget`.

## Struktura

```
Uninstall-MsiPackage.ps1   hlavní skript
Uninstall-MsiPackage.cmd   CMD launcher (ExecutionPolicy Bypass)
common/                    submodul dnemecek/ps-common
logs/                      logy (mimo git)
```

## Autor

David Němeček
