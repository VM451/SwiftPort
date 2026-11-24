# __APP_NAME__

A SwiftPort app — 100% native Swift core, native UI on every OS.

## Layout

```
Core/            Pure Swift package — models, store, state machine. No UI frameworks.
Apps/Apple/      SwiftUI app (macOS + iOS) — XcodeGen project + SwiftPM UI package
Apps/Linux/      GTK4 + Libadwaita app (Adwaita for Swift)
Apps/Android/    Phase 2 — Kotlin + Compose (stub)
Apps/Windows/    Phase 3 — WinUI 3 / C# (stub)
Bridges/         Generated interop layers (`swiftport sync`)
Verification/    Shared contract fixtures + golden snapshots
```

## Daily commands

```sh
swiftport doctor                    # check toolchain
swiftport sync                      # scan Core exports, regen bridges/projects
swiftport build --target apple      # build the macOS app
swiftport verify                    # lint + contracts + snapshots (full gate)
swiftport verify --mode contracts   # state-contract tests only
swiftport verify --mode snapshots --update-snapshots  # bless new goldens
```

## Apple app

```sh
cd Apps/Apple
xcodegen generate          # if the .xcodeproj is missing/stale
open __APP_MODULE__.xcodeproj
```

## Linux app

```sh
# one-time system deps (Debian/Ubuntu):
sudo apt install libgtk-4-dev libadwaita-1-dev
cd Apps/Linux && swift run __APP_MODULE__
```

## The contract

`Verification/Contracts/*.json` defines every UI state (`loading`, `empty`,
`loaded`, `error`, plus stress fixtures). `Core/` is platform-pure — enforced
by `swiftport lint`. When you add a state or field, add a fixture; every
platform must render it or verification fails.
