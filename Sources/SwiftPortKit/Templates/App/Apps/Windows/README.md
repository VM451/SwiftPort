# Apps/Windows — C# + WinUI 3 (Fluent 2)

Native Windows UI following the Fluent 2 design language, sharing the
`Verification/Contracts/*.json` fixtures with every other platform.

## Layout

- `src/__APP_MODULE__.App/` — unpackaged WinUI 3 app (Windows App SDK,
  `net8.0-windows10.0.19041.0`), builds on Windows only
- `tests/__APP_MODULE__.Tests/` — xunit contract tests parsing the shared
  fixtures via `System.Text.Json` (fixtures are linked, not copied)

## Building (Windows host or CI)

Requires the .NET 8 SDK:

```powershell
swiftport build --target windows --release   # dotnet build -c Release
dotnet test Apps/Windows/tests/__APP_MODULE__.Tests   # contract fixtures
```

`swiftport doctor` reports the dotnet toolchain on Windows hosts; on macOS
and Linux the Windows target is verified by the GitHub Actions `windows`
runner instead.

## Swift bridge

`swiftport sync` generates `Bridges/WindowsABI/SwiftPortBridge.cs` — C#
wire models plus `DllImport` bindings for the `swiftport_*` C ABI exported
by `AppCoreCABI.dll`. Every call returns the JSON encoding of
`TaskListSnapshot` (Swift `Codable`, ISO-8601 dates); strings cross as
UTF-8.

To activate the bridge on Windows:

```powershell
cd Core
swift build -c release --product AppCoreCABI
```

Copy the resulting `AppCoreCABI.dll` to `Bridges/WindowsABI/lib/` — both
csproj files glob that directory into their output, so `dotnet test` and
`dotnet build` pick it up automatically. `BridgeTests` exercises the real
P/Invoke round-trip (fixture snapshot + store mutations) whenever the DLL
is present.

Until the DLL is staged, the contract tests prove fixture parity and the
bridge tests skip cleanly.

## UI states

`MainWindow` renders all four contract phases (loading / empty / loaded /
error) and honors the shared `SWIFTPORT_SCENARIO` + `SWIFTPORT_CONTRACTS_DIR`
+ `SWIFTPORT_THEME` environment contract, so a future `swiftport verify`
Windows capture can drive it like the Apple/Linux apps.
