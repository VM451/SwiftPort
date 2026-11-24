# Apps/Android — Kotlin + Jetpack Compose (Material Design 3)

Native Android UI following the Material Design 3 guidelines, driven by the
same `Verification/Contracts/*.json` fixtures every other platform consumes.

## Layout

- `app/` — Android application module (`compileSdk 35`, `minSdk 26`)
- `MainActivity` — edge-to-edge `ComponentActivity` hosting Compose
- `ui/TaskScreen.kt` — renders every contract phase (loading, empty, loaded,
  error) with Material 3 components
- `data/ContractState.kt` — parses the shared JSON fixtures (`org.json`)
- `TaskScreenSnapshotTest` — Paparazzi screenshot tests, one per fixture × theme

## Building

Requires JDK 17+ and the Android SDK (`ANDROID_HOME` or `local.properties`
with `sdk.dir`). `swiftport doctor` checks both.

```sh
./gradlew assembleDebug          # or: swiftport build --target android
./gradlew testDebugUnitTest      # contract fixture parsing
./gradlew recordPaparazziDebug   # regenerate screenshot goldens
```

Contract fixtures are shared, not copied — `app/build.gradle.kts` points the
assets source set at `../../Verification/Contracts`.

## Swift bridge

`Core/` types marked `SwiftPortExported` are the bridge surface.
`swiftport sync` generates the Kotlin bindings and JNI shim under
`Bridges/AndroidJNI/` — `SwiftPortBridge.kt` wraps the `swiftport_*` C ABI
exported by `AppCoreCABI` (a dynamic library built from `Core/`), and
`jni_shim.c` forwards JNI calls via `dlopen`, so no link-time dependency
on the Swift toolchain is needed.

Every bridge call returns the JSON encoding of `TaskListSnapshot` (Swift
`Codable`, ISO-8601 dates). `MainActivity` already prefers the bridge and
falls back to the contract fixture when `libswiftportcore.so` is absent.

To activate the bridge, build the Swift core per ABI with the
[Swift Android SDK](https://www.swift.org/swift-android/):

```sh
cd Core
swift build -c release --swift-sdk aarch64-unknown-linux-android --product AppCoreCABI
swift build -c release --swift-sdk x86_64-unknown-linux-android --product AppCoreCABI
```

Copy each `AppCoreCABI.so` to `app/src/main/jniLibs/<abi>/libswiftportcore.so`
(`arm64-v8a`, `x86_64`) — or stage them under `Bridges/AndroidJNI/libs/<abi>/`
and `./gradlew installSwiftPortJniLibs` copies them in. See
`Bridges/AndroidJNI/README.md` for details.
