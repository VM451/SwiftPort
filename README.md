# SwiftPort

Apple-first, native-everywhere app scaffolding. Write your backend once in
pure Swift; ship truly native UIs on macOS, iOS, iPadOS, Android, Windows,
and Linux — with automated visual verification so ported UIs never silently
break.

```
swiftport init TaskFlow     # scaffold the monorepo
cd TaskFlow
swiftport doctor            # audit toolchain
swiftport verify            # lint + contracts + visual snapshots
swiftport build --target apple
```

## What you get

A generated project contains:

- `Core/` — platform-independent Swift package (models, store, state
  machine). `swiftport lint` fails the build if Apple-only frameworks leak in.
- `Apps/Apple/` — SwiftUI app for macOS + iOS (XcodeGen project).
- `Apps/Linux/` — GTK4 + Libadwaita app (Adwaita for Swift), GNOME HIG.
- `Apps/Android/`, `Apps/Windows/` — stubs today; Kotlin/Compose and
  WinUI 3 land in Phases 2–3.
- `Verification/` — shared JSON state fixtures every platform must render,
  plus golden UI snapshots with ≤0.1% pixel tolerance.
- `.github/workflows/` — CI that builds all enabled targets and gates PRs
  on contract + visual regressions.

## Commands

| Command | Purpose |
|---|---|
| `swiftport init <Name>` | Scaffold monorepo (`--platforms`, `--path`, `--bundle-id-prefix`) |
| `swiftport doctor` | Audit SDKs/toolchains, print fix commands |
| `swiftport lint` | Reject platform-locked imports in `Core/` |
| `swiftport sync` | Scan `SwiftPortExported` APIs, regen bridges/projects |
| `swiftport build --target <t>` | Build apple/linux (`--release`, `--low-memory`, `-j`) |
| `swiftport verify` | Full gate: lint + contract tests + snapshot diff |

## Install (development)

```sh
git clone <this repo>
cd SwiftPort
swift build -c release
.build/release/swiftport --help
```

## Status

Phase 1 (this repo): CLI + template + verification harness for Apple + Linux.
See `docs/PRD.md` for the full product requirements and roadmap.

## License

MIT
