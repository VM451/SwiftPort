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

## Swift bridge (Phase 3 status)

The WinUI app will consume `Core/` through a C-ABI `.dll` exported from
Swift plus generated C# `DllImport` bindings (`swiftport sync`). Until that
codegen lands, the app is a minimal Fluent 2 shell and the contract tests
prove fixture parity.
