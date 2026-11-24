# Bridges

Generated interop layers between `Core/` (pure Swift) and each native UI.
Everything here is **generated** by `swiftport sync` — edit `Core/` and
re-run sync.

All bridges speak one wire protocol: the `swiftport_*` C ABI exported by
`AppCoreCABI`, a dynamic library product built from `Core/`. Every call
returns the JSON encoding of `TaskListSnapshot` (Swift `Codable`,
ISO-8601 dates, sorted keys) or null on failure; callers free strings
with `swiftport_free_string`.

| Directory    | Platform | Mechanism                                        | Status |
|--------------|----------|--------------------------------------------------|--------|
| `AndroidJNI` | Android  | Kotlin bindings + JNI C shim (dlopen)            | generated; needs `libswiftportcore.so` per ABI |
| `WindowsABI` | Windows  | C# `DllImport` P/Invoke wrappers                 | generated; needs `AppCoreCABI.dll` |
| `LinuxC`     | Linux    | direct SwiftPM dependency (no glue needed)       | n/a — links `AppCore` directly |

Apple needs no bridge: `Apps/Apple` links `Core/` as a local Swift package.

## Producing the native libraries

- **Android**: `cd Core && swift build -c release --swift-sdk <abi>-unknown-linux-android --product AppCoreCABI`
  for `aarch64` and `x86_64` (Swift Android SDK), then place each `.so` as
  `libswiftportcore.so` under `Apps/Android/app/src/main/jniLibs/<abi>/`
  or `Bridges/AndroidJNI/libs/<abi>/` (Gradle copies from there).
- **Windows**: on Windows, `cd Core && swift build -c release --product AppCoreCABI`,
  then copy `AppCoreCABI.dll` to `Bridges/WindowsABI/lib/`.
- **Linux**: `swift build -c release --product AppCoreCABI` produces a `.so`
  usable from C/Python via the same `swiftport_*` symbols.
