# SwiftPort — agent notes

CLI + monorepo template for Apple-first, native-everywhere Swift apps.
PRD: `docs/PRD.md`.

## Layout

- `Sources/SwiftPortKit/` — all logic (init/doctor/lint/sync/build/verify), unit-testable.
- `Sources/swiftport/` — ArgumentParser commands (thin wrappers over the kit).
- `Sources/SwiftPortKit/Templates/App/` — the generated project's template.
  Text files are copied verbatim except token substitution; **file and
  directory names are substituted too** (`__APP_NAME__`, `__APP_MODULE__`,
  `__APP_SLUG__`, `__BUNDLE_ID__`, `__BUNDLE_ID_PREFIX__`).
- `Tests/SwiftPortKitTests/` — kit unit tests (Swift Testing).

## Commands

```sh
swift build                  # builds .build/debug/swiftport
swift test                   # needs Xcode toolchain — see below
.build/debug/swiftport init MyApp --path ./MyApp
```

**Toolchain gotcha (this machine):** `xcode-select` points at Command Line
Tools. `swift build` works, but `swift test` (Swift Testing macros) and
`xcodebuild` need Xcode. The kit auto-sets `DEVELOPER_DIR` for its own
`swift test`/`xcodebuild` calls when `/Applications/Xcode.app` exists.
For direct runs use:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

## Generated project layout

See template `README.md`. Key contracts:

- `Core/` must stay platform-pure — `swiftport lint` fails on
  SwiftUI/UIKit/AppKit/Combine/etc. `#if canImport(X)` guards are allowed.
- `Verification/Contracts/*.json` — shared state fixtures; every platform
  must render them (`swiftport verify --mode contracts`).
- `Verification/Snapshots/{apple,ios,linux,...}/` — blessed goldens per
  platform; `current/` is gitignored.
- Bridge surface = `SwiftPortExported` protocol conformances in `Core/`
  (scanned by `swiftport sync`; macro-based `@SwiftPortExport` is a later phase).

## Host quirks (this machine)

- `xcode-select` → CLT; all `xcodebuild`/`xcrun simctl`/`swift test` need
  `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (kit sets it
  automatically for its own calls via `xcodeEnvironment`).
- `javac` on PATH is the macOS stub — no JDK. Android contract/snapshot
  stages skip cleanly; real builds need CI or a JDK install.
- No `dotnet` — Windows targets are CI-only.
- `adwaita-swift` 0.1.0 does not compile on macOS (brew glib 2.90 removed
  `G_CONNECT_AFTER`); Linux app builds only on Linux/CI.
- **iOS simulator capture is flaky on this host** (iOS 27.0 runtime,
  Xcode 27.2): `simctl io screenshot` intermittently returns flat frames,
  SpringBoard, or launch-screen frames — even Apple's Settings app is
  affected. After `killall com.apple.CoreSimulator.CoreSimulatorService`
  + device erase it works intermittently. `verify` guards against
  blessing garbage (blank-frame + SpringBoard detection, `--mask=black`
  pins the Dynamic Island). Treat local iOS goldens as suspect; CI is
  the reliable capture environment.
- **UI-test audits need one-time interactive approval**: `swiftport verify
  --mode audits` runs `xcodebuild test` on the generated UITests bundle;
  macOS demands Touch ID/password consent for UI automation and the prompt
  is not reachable from agent shells → stage fails with
  "failed to initialize for UI testing" until a human approves once in a
  GUI terminal. CI runners are pre-authorized.
- No git remote configured — nothing has run on GitHub Actions yet; the
  template's generated-app CI is the first real exercise of the
  Android/Windows/Linux bridge code.

## Conventions

- Swift 6 language mode; keep new kit code `Sendable`-clean.
- Template Swift code targets macOS 14 / iOS 17 / Linux (Swift 6).
- After editing template files, `swift build` re-bundles them into
  `Bundle.module` — re-run `swiftport init` to see changes in generated apps.
