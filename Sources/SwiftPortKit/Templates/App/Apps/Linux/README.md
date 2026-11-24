# Apps/Linux — GTK4 + Libadwaita (GNOME HIG)

Native Linux UI following the GNOME Human Interface Guidelines, driven by
the same `Verification/Contracts/*.json` fixtures every other platform
consumes. `Core/` is linked as a local SwiftPM dependency — no bridge code.

## Layout

- `Package.swift` — SwiftPM executable (`__APP_MODULE__`) + contract tests
- `Sources/__APP_MODULE__/App.swift` — Adwaita `App`/`Window` bootstrap
- `Sources/__APP_MODULE__/TaskListView.swift` — renders every `TaskPhase`
  (loading, empty, loaded, error); explicit buttons drive `TaskStore`
- `Tests/ContractTests/` — parses the shared fixtures via `AppCore`

## Building (Linux host)

Requires GTK4 + libadwaita development packages:

```sh
sudo apt install pkg-config libgtk-4-dev libadwaita-1-dev   # Debian/Ubuntu
# Fedora: sudo dnf install gtk4-devel libadwaita-devel
# macOS (optional): brew install pkgconf gtk4 libadwaita
```

```sh
swiftport build --target linux --release   # or: swift build -c release
swiftport verify --mode contracts --platforms linux
```

`swiftport doctor` checks `gtk4`/`libadwaita-1` via pkg-config.

## Visual snapshots

`swiftport verify --mode snapshots --platforms linux` runs the real app
under Xvfb once per contract fixture and screenshots the root window with
ImageMagick (`sudo apt install xvfb imagemagick`). The app enters snapshot
mode via `SWIFTPORT_SCENARIO=<fixture-id>` +
`SWIFTPORT_CONTRACTS_DIR=<path>` env vars.

Goldens live in `Verification/Snapshots/linux/` — bless once on your Linux
machine with `swiftport verify --update-snapshots`, then CI/dev hosts diff
against them. Currently light theme only (libadwaita follows the desktop
settings portal, unreliable headless).
