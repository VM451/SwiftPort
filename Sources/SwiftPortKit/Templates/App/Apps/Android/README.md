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

## Swift bridge (Phase 2 status)

`Core/` types marked `@SwiftPortExport`/`SwiftPortExported` are the bridge
surface. `swiftport sync` reports the export list; generating Kotlin wrappers
and JNI bindings via **swift-java** + compiling `libAppCore.so` for
`arm64-v8a`/`x86_64` requires the Swift Android SDK toolchain — run it on a
machine with the SDK installed, then drop the `.so` files into
`app/src/main/jniLibs/<abi>/` (a Gradle pre-build hook lands with the
bridge codegen).
