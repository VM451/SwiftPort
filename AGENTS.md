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
- `Verification/Snapshots/apple/` — blessed goldens; `current/` is gitignored.
- Bridge surface = `SwiftPortExported` protocol conformances in `Core/`
  (scanned by `swiftport sync`; macro-based `@SwiftPortExport` is a later phase).

## Conventions

- Swift 6 language mode; keep new kit code `Sendable`-clean.
- Template Swift code targets macOS 14 / iOS 17 / Linux (Swift 6).
- After editing template files, `swift build` re-bundles them into
  `Bundle.module` — re-run `swiftport init` to see changes in generated apps.
