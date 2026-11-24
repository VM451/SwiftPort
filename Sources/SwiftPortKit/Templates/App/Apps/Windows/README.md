# Apps/Windows — Phase 3

WinUI 3 (C#) UI following the Fluent 2 design system, talking to `Core/`
through an exported C-ABI `.dll` and generated C# `DllImport` bindings.

Not yet scaffolded. `swiftport init` creates this directory as a stub when
`windows` is selected in `swiftport.toml`; the .NET project, ABI header +
binding generation, and `.msix` packaging arrive in Phase 3.
