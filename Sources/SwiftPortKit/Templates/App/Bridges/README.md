# Bridges

Generated interop layers between `Core/` (pure Swift) and each native UI.
Everything here is **generated** — edit `Core/` and run `swiftport sync`.

| Directory    | Platform | Mechanism                                  | Phase      |
|--------------|----------|--------------------------------------------|------------|
| `AndroidJNI` | Android  | swift-java → Kotlin wrappers + `.so`       | Phase 2 🚧 |
| `WindowsABI` | Windows  | C-ABI `.dll` + C# `DllImport`              | Phase 3    |
| `LinuxC`     | Linux    | direct SwiftPM dependency (no glue needed) | Phase 1 ✅ |

Apple needs no bridge: `Apps/Apple` links `Core/` as a local Swift package.
