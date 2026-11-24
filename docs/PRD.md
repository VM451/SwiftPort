# Product Requirements Document (PRD): SwiftPort (Working Title)

| Field | Details |
|---|---|
| Project Name | SwiftPort (Working Codename) |
| Document Version | 1.1 (Enhanced UX/UI Verification) |
| License | Apache 2.0 or MIT (Open Source) |
| Target Platforms | Apple (macOS, iOS, iPadOS), Android, Windows, Linux |
| Core Philosophy | Apple-First, Native-Everywhere, Zero Visual Regressions, Low-RAM Friendly |

## 1. Executive Summary & Vision

SwiftPort is an open-source scaffolding toolkit, monorepo template, and CLI orchestrator that enables developers to build Apple-first applications with a 100% Native Swift Core (Backend) and seamlessly connect that core to 100% Native UIs on every major operating system:

- **Apple** (macOS / iOS / iPadOS): SwiftUI / AppKit / UIKit
- **Android**: Kotlin + Jetpack Compose
- **Windows**: WinUI 3 (C# / C++ or Swift-WinUI)
- **Linux**: GTK4 + Libadwaita

Unlike cross-platform UI frameworks that compromise on native feel (Electron, Flutter) or Rust-based stacks that overwhelm 8 GB RAM laptops during compilation, SwiftPort gives developers a one-click, low-RAM workflow to write business logic once in Swift and ship truly native, visually verified apps everywhere.

## 2. Problem Statement

- **The 8 GB RAM Compiler Bottleneck**: Cross-platform Rust cores (cargo + rustc + rust-analyzer) routinely spike RAM usage past 8 GB, causing severe SSD swap and system freezes on entry-level laptops (such as an 8 GB MacBook Air M2).
- **Fragmented Cross-Platform Swift Tooling**: While Swift officially supports Linux, Windows, and Android, stitching together swift-java, Android NDK, Gradle, C-ABI .dll exports for WinUI 3, and GTK4 bindings requires days of fragile boilerplate configuration.
- **Broken or Un-Idiomatic Ported UIs**: Ported applications frequently suffer from clipped text, broken dark mode, mismatched spacing, unresponsive layouts, or missing UI states (such as unhandled errors or loading spinners) when developers cannot visually inspect every target OS on every change.

## 3. Target Audience & Personas

- **The Apple-First Indie Developer**: Builds primarily in Xcode/SwiftUI on a MacBook Air and wants to expand to Android, Windows, and Linux without rewriting business logic in Kotlin, C#, or Rust—and without shipping broken UIs on platforms they don't use daily.
- **The Resource-Constrained Developer**: Works on an 8 GB–16 GB RAM machine and needs fast incremental builds without system freezes.
- **Small Product Teams**: Want a single source of truth for data models, networking, encryption, and local storage while guaranteeing native, pixel-accurate UI quality across every OS.

## 4. System Architecture

SwiftPort enforces a strict Core / Bridge / Native UI / Verification separation inside a unified monorepo.

```
my-swiftport-app/
├── swiftport.toml              # Central project, target & UI verification config
├── Core/                       # 100% Platform-Independent Swift Package
│   ├── Package.swift
│   └── Sources/AppCore/        # Models, Networking, DB, Business Logic, UI State Machines
├── Bridges/                    # Auto-generated interop layers (gitignored or cached)
│   ├── AndroidJNI/             # Generated via swift-java
│   ├── WindowsABI/             # Generated C-ABI headers + C# P/Invoke wrappers
│   └── LinuxC/                 # Direct Swift-to-C / Adwaita module maps
├── Apps/
│   ├── Apple/                  # Xcode project (SwiftUI for macOS/iOS)
│   ├── Android/                # Gradle project (Kotlin + Jetpack Compose)
│   ├── Windows/                # Visual Studio / .NET project (WinUI 3)
│   └── Linux/                  # SwiftPM / Flatpak project (GTK4 + Libadwaita)
├── Verification/               # Cross-platform UI contract & visual snapshot baselines
│   ├── Contracts/              # Shared state-scenario test fixtures (JSON/Swift)
│   └── Snapshots/              # Golden screenshots per OS, theme, and viewport
└── .github/workflows/          # Pre-configured CI/CD build + visual diff gates
```

### Platform Integration & Design System Matrix

| Platform | Native UI Layer | Mandatory Design System | Bridge Mechanism | Output Artifact |
|---|---|---|---|---|
| Apple | SwiftUI / AppKit / UIKit | Apple Human Interface Guidelines (HIG) | Direct Swift Package import (Zero bridge) | .app / .ipa |
| Android | Kotlin + Jetpack Compose | Material Design 3 (Material You) | Official Swift SDK for Android + swift-java (JNI) | .apk / .aab (bundling .so) |
| Windows | WinUI 3 (C# shell) | Microsoft Fluent 2 Design System | C-ABI .dll exported from Swift + auto-generated C# P/Invoke | .msix / .exe |
| Linux | GTK4 + Libadwaita | GNOME Human Interface Guidelines | Direct Swift C-interop / AparokshaUI/Adwaita | .flatpak / .AppImage |

## 5. Functional Requirements (FR)

### FR-1: "One-Click" Project Scaffolding CLI (swiftport)

- `swiftport init <AppName>`: Interactively scaffolds the monorepo, letting the developer pick target platforms (e.g., Apple + Android + Linux + Windows).
- `swiftport doctor`: Audits the host machine for required SDKs (Swift toolchain, Xcode, Android NDK, Java/Gradle, GTK4, etc.) and prints actionable fix commands if anything is missing.

### FR-2: Pure Swift Core Guardrails

- Automatically configures Core/Package.swift to use cross-platform-safe libraries (FoundationEssentials, Swift-HTTP-Types, etc.).
- Includes a lightweight linter/build check that warns immediately if Apple-only frameworks (SwiftUI, UIKit, AppKit, Combine) are accidentally imported into Core/.

### FR-3: Automated Bridge Generation (swiftport sync)

- Scans public APIs marked with @SwiftPortExport (or a dedicated Swift Macro) in Core/.
- Automatically generates:
  - **Android**: Kotlin wrapper classes and JNI bindings via swift-java, copying compiled .so libraries directly into Apps/Android/app/src/main/jniLibs/.
  - **Windows**: C-ABI header files and type-safe C# DllImport bindings for the WinUI 3 frontend.
  - **Linux**: Clean Swift module integration for the GTK4/Libadwaita frontend.

### FR-4: Unified Build & Packaging Commands

- `swiftport build --target <apple|android|windows|linux> --release`
- Handles stripping debug symbols and linking the Swift standard library (--static-swift-stdlib where appropriate) to minimize final package size.

### FR-5: Working Reference App ("Batteries Included")

Every generated project includes a clean, minimal working app (e.g., a Local-First Task Manager or API Fetcher) demonstrating:

- Passing structs/models across the bridge.
- Handling async/await calls from native UI threads (Swift Concurrency ↔ Kotlin Coroutines ↔ C# Task).
- Complete handling of all core UI states (loading, empty, populated, error) across all 4 native UIs.

### FR-6: Out-of-the-Box GitHub Actions CI/CD with Visual Quality Gates

- Pre-configured workflow files so a macOS developer without a Windows or Linux PC can push to GitHub and automatically receive compiled Windows .msix, Linux .flatpak, and Android .apk release artifacts.
- Every Pull Request automatically executes the Visual & Contract Verification Suite on native macOS, Ubuntu (Xvfb/Wayland), Windows, and Android Emulator runners, posting side-by-side screenshot diffs directly onto the PR and blocking merges if broken layouts or regressions are detected.

### FR-7: Native UX/UI Correctness & Automated Visual Verification (swiftport verify)

To guarantee that every ported native UI is accurate, idiomatic, and visually unbroken across all operating systems, SwiftPort must include a built-in verification pipeline:

**Platform Design System Conformance**: All scaffolded UI templates must strictly adhere to each OS's official design language (native window chrome, system typography, standard navigation patterns, native dialogs, and system accent colors)—never forcing Apple-style UI metaphors onto Windows, Linux, or Android.

**State-Driven UI Contract Testing**: Core/ defines deterministic mock states (e.g., emptyState, loadingState, longTextOverflowState, errorState). `swiftport verify --contracts` launches each platform's UI against identical Core/ state fixtures to prove that every exported state, action, and error message is properly wired with zero unhandled cases or silent failures.

**Automated Multi-Matrix Visual Snapshot Testing**: Captures headless screenshots of every screen across a mandatory test matrix:

- Themes: Light Mode & Dark Mode (plus High Contrast where supported).
- Viewports & Density: Compact, standard, and expanded window sizes; standard (1x) and HiDPI (2x/3x) scaling.
- Text & Locale Stress Tests: Large Dynamic Type / Accessibility font scaling (up to 200%), long localized strings (e.g., German), and Right-to-Left (RTL) layouts.

Compares rendered frames against approved golden snapshots in Verification/Snapshots/ and flags any unintended clipping, overlapping controls, or layout shifts.

**Automated Layout & Accessibility Audits**: Verifies zero truncated/clipped labels, zero overlapping hit targets, minimum touch/click target dimensions, WCAG AA color contrast ratios (≥ 4.5:1 for normal text), and full keyboard navigation + screen-reader labels (VoiceOver, TalkBack, Windows Narrator, Linux Orca).

## 6. Non-Functional Requirements (NFR)

**8 GB RAM Developer Experience (Critical)**: Compiling Core/ and running swiftport sync on an 8 GB RAM MacBook Air M2 must stay under 3 GB peak toolchain RAM and must never trigger system-locking swap freezes. CLI must expose a --low-memory / -j job-throttling flag for constrained hosts.

**Native End-User Performance**: Zero JavaScript/WebView runtime overhead. Bridge serialization latency for standard UI payloads must remain under 1 ms so scrolling and interactions feel 100% native.

**Zero-Defect Visual & UX Fidelity**: 0% tolerance for layout clipping, overlapping interactive controls, or unhandled Core/ error states in released starter templates. Visual regression tolerance threshold must default to ≤ 0.1% pixel variance (to account strictly for OS-level font anti-aliasing differences), requiring explicit human sign-off for any intentional UI change.

**Developer Onboarding Speed**: Time from git clone (or swiftport init) to running the Apple + first secondary platform app must be under 10 minutes on a properly configured machine.

**Maintainability & Modularity**: Each platform target (Android, Windows, Linux) must be an independent plugin/module so community maintainers can update one platform without breaking others.

## 7. Phased Roadmap

**Phase 1: Foundation, MVP & Verification Harness (Apple + Linux)**
- Build the swiftport CLI (written in Swift using swift-argument-parser).
- Create the monorepo template with Core/, Apps/Apple/ (SwiftUI), and Apps/Linux/ (GTK4/Libadwaita).
- Implement swiftport init, swiftport doctor, and the initial swiftport verify snapshot + contract testing runner for macOS and Linux.
- Publish GitHub Actions workflow for macOS and Linux builds with automated PR screenshot diffs.

**Phase 2: Android Integration & Visual Parity**
- Integrate the official Swift SDK for Android and swift-java.
- Build Apps/Android/ starter template in Kotlin + Jetpack Compose strictly following Material Design 3.
- Automate .so compilation (for arm64-v8a and x86_64) and automatic placement into Android's jniLibs/ via a Gradle pre-build hook.
- Add Compose Screenshot Testing (Paparazzi / Roborazzi) into swiftport verify for Light/Dark, RTL, and font-scale checks.

**Phase 3: Windows Integration & Visual Parity**
- Add Swift Macro / code-gen for exporting C-ABI .dll functions and C# P/Invoke bindings.
- Build Apps/Windows/ starter template in C# + WinUI 3 strictly following Fluent 2 Design System guidelines.
- Add GitHub Actions Windows runner to build .msix installers and execute automated WinUI visual/layout regression checks.

**Phase 4: Ecosystem & 1.0 Release**
- Publish optional "Core Recipes" (cross-platform SQLite, Keychain/Credential storage, Networking).
- Add an interactive HTML Visual Diff Report generator (swiftport verify --report) so developers can visually inspect all 4 OSes side-by-side in one browser view.
- Tag v1.0.0 and invite platform-specific open-source maintainers.

## 8. Technical Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Android Swift SDK / swift-java API changes | High | Pin tested Swift toolchain versions in swiftport.toml and update bridges in minor releases. |
| Visual regressions or broken layouts on OSes the dev doesn't own | High | Enforce mandatory CI visual snapshot diffs, layout-overflow assertions, and contract tests on every PR before merging. |
| Cross-compiling Windows from macOS is difficult | Medium | Rely on GitHub Actions Windows runners (free for public open-source repos) for building and visually verifying Windows binaries, while allowing local logic testing on macOS. |
| Android APK Size Bloat | Medium | Bundling Swift stdlib per CPU architecture adds ≈10–15 MB; mitigate by stripping symbols, enabling App Bundles (.aab), and targeting arm64-v8a by default for releases. |
| 4 Separate UIs Increase Maintenance | Medium | Keep the starter UI templates intentionally minimal (1–2 screens) and driven by shared Core/ state machines so they act as clean, easy-to-verify reference shells. |

## 9. Success Metrics (KPIs)

- **Setup Friction**: ≥ 90% of new users successfully build the Apple + at least one non-Apple target on their first try using swiftport doctor.
- **Visual & UX Accuracy**: 100% pass rate on automated visual regression, accessibility, and Core/ state-contract verification checks across all 4 platforms on every release tag, with 0 broken-layout regressions reported in starter templates.
- **Hardware Efficiency**: Peak RAM during Core/ incremental builds remains comfortable (< 3 GB) on an 8 GB M2 MacBook Air.
- **Community Traction**: 500+ GitHub stars, 20+ external community PRs/platform improvements, and at least 5 real-world apps shipped using the template within 12 months of launch.
