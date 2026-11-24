import Foundation

/// `swiftport verify` — the Phase-1 verification harness:
///   1. Core purity lint (FR-2)
///   2. Contract tests: shared JSON fixtures in `Verification/Contracts/`
///      exercised by `swift test` in Core and each enabled platform app
///   3. Visual snapshots (Apple): renders every contract scenario × theme
///      via the `snapshot-runner` tool and pixel-diffs against goldens in
///      `Verification/Snapshots/` (tolerance from `swiftport.toml`)
public enum Verify {
    public struct Options: Sendable {
        public var contracts = true
        public var snapshots = false
        public var updateSnapshots = false
        /// Capture snapshots but skip golden comparison (CI artifact mode).
        public var captureOnly = false
        public var platforms: Set<ProjectConfig.Platform>?
        public var lowMemory = false
        public var jobs: Int? = nil
        /// Write `Verification/report.html` — side-by-side snapshot review.
        public var report = false

        public init() {}
    }

    public enum VerifyError: Error, CustomStringConvertible {
        case notInProject
        case missingDirectory(String)

        public var description: String {
            switch self {
            case .notInProject: return "not inside a SwiftPort project (no swiftport.toml found)"
            case .missingDirectory(let path): return "missing directory: \(path)"
            }
        }
    }

    public struct StageResult: Sendable {
        public var name: String
        public var ok: Bool
        public var detail: String
    }

    public struct Report: Sendable {
        public var stages: [StageResult]
        public var snapshotResults: [SnapshotResult]

        public var ok: Bool { stages.allSatisfy(\.ok) && snapshotResults.allSatisfy { $0.ok } }
    }

    public struct SnapshotResult: Sendable {
        public var file: String
        public var status: Status
        public var diffFraction: Double?
        public var detail: String? = nil

        public enum Status: String, Sendable {
            case match, regression, new, blessed, skipped
        }

        public var ok: Bool {
            switch status {
            case .match, .new, .blessed, .skipped: return true
            case .regression: return false
            }
        }
    }

    // MARK: - Entry point

    @discardableResult
    public static func run(root: URL, options: Options = Options()) throws -> Report {
        let config = try ProjectConfig.load(from: root)
        let platforms = options.platforms ?? config.platforms
        var stages: [StageResult] = []
        var snapshotResults: [SnapshotResult] = []

        // 1. Lint — always on.
        let lint = try Lint.run(root: root)
        stages.append(StageResult(
            name: "core-lint",
            ok: lint.isClean,
            detail: Lint.render(lint)
        ))

        // 2. Contracts.
        if options.contracts {
            stages.append(contentsOf: try runContracts(
                root: root, platforms: platforms,
                lowMemory: options.lowMemory, jobs: options.jobs
            ))
        }

        // 3. Snapshots.
        if options.snapshots {
            snapshotResults = try runSnapshots(
                root: root, config: config, platforms: platforms,
                update: options.updateSnapshots, captureOnly: options.captureOnly,
                lowMemory: options.lowMemory, jobs: options.jobs
            )
        }

        return Report(stages: stages, snapshotResults: snapshotResults)
    }

    // MARK: - Contracts

    static func runContracts(
        root: URL,
        platforms: Set<ProjectConfig.Platform>,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> [StageResult] {
        var results: [StageResult] = []

        // Core's own tests always run when any platform is enabled.
        let coreDir = root.appendingPathComponent("Core")
        results.append(try swiftTest(packageAt: coreDir, name: "contracts:core",
                                     lowMemory: lowMemory, jobs: jobs))

        #if os(macOS)
        if platforms.contains(.apple) {
            let appleDir = root.appendingPathComponent("Apps/Apple")
            if FileManager.default.fileExists(atPath: appleDir.path) {
                results.append(try swiftTest(packageAt: appleDir, name: "contracts:apple",
                                             lowMemory: lowMemory, jobs: jobs))
            }
        }
        #endif

        if platforms.contains(.linux) {
            let linuxDir = root.appendingPathComponent("Apps/Linux")
            if FileManager.default.fileExists(atPath: linuxDir.path) {
                // Contract tests build the whole Apps/Linux package, which
                // links GTK4/libadwaita through adwaita-swift. That stack is
                // only supported on Linux hosts (and Linux CI) — on macOS the
                // brew glib is too new for adwaita-swift 0.1.0.
                if Self.hostIsLinux && Self.gtkToolchainAvailable() {
                    results.append(try swiftTest(packageAt: linuxDir, name: "contracts:linux",
                                                 lowMemory: lowMemory, jobs: jobs))
                } else {
                    results.append(StageResult(
                        name: "contracts:linux",
                        ok: true,
                        detail: "skipped — Linux contract tests run on Linux hosts/CI "
                            + "(GTK4 + libadwaita required)"
                    ))
                }
            }
        }
        #if os(Windows)
        if platforms.contains(.windows) {
            let testsDir = root.appendingPathComponent("Apps/Windows/tests")
            let enumerator = FileManager.default.enumerator(at: testsDir, includingPropertiesForKeys: nil)
            var csproj: URL?
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "csproj" { csproj = url; break }
            }
            if let csproj {
                results.append(try dotnetTest(csproj: csproj, name: "contracts:windows",
                                              lowMemory: lowMemory, jobs: jobs))
            }
        }
        #else
        if platforms.contains(.windows) {
            results.append(StageResult(
                name: "contracts:windows",
                ok: true,
                detail: "skipped — WinUI contract tests run on Windows CI"
            ))
        }
        #endif

        if platforms.contains(.android) {
            let androidDir = root.appendingPathComponent("Apps/Android")
            if FileManager.default.fileExists(atPath: androidDir.path) {
                if Self.jdkAvailable() {
                    results.append(try gradleTask(
                        androidDir: androidDir, task: "testDebugUnitTest",
                        name: "contracts:android", lowMemory: lowMemory, jobs: jobs
                    ))
                } else {
                    results.append(StageResult(
                        name: "contracts:android",
                        ok: true,
                        detail: "skipped — JDK 17+ required for Gradle "
                            + "(run `swiftport doctor` to audit)"
                    ))
                }
            }
        }
        return results
    }

    /// True when a working JDK is on PATH. `/usr/bin/javac` on macOS is a
    /// stub that exits non-zero without a real JDK — `javac -version`
    /// distinguishes the two.
    static func jdkAvailable() -> Bool {
        guard Shell.which("javac") != nil else { return false }
        return (try? Shell.run("javac", arguments: ["-version"]))?.succeeded == true
    }

    /// `dotnet test` on a Windows contract-test project.
    static func dotnetTest(csproj: URL, name: String, lowMemory: Bool, jobs: Int?) throws -> StageResult {
        guard Shell.which("dotnet") != nil || Shell.which("dotnet.exe") != nil else {
            return StageResult(name: name, ok: false,
                               detail: "dotnet SDK not found — install .NET 8 SDK")
        }
        var args = ["test", csproj.path]
        let effective = Build.jobCount(jobs: jobs, lowMemory: lowMemory)
        if let effective { args += ["-m:\(effective)"] }
        guard let result = try? Shell.run("dotnet", arguments: args,
                                          currentDirectory: csproj.deletingLastPathComponent()) else {
            return StageResult(name: name, ok: false, detail: "failed to launch dotnet test")
        }
        let tail = result.combined
            .components(separatedBy: .newlines)
            .suffix(15)
            .joined(separator: "\n")
        return StageResult(name: name, ok: result.succeeded, detail: tail)
    }

    /// Runs a Gradle task inside Apps/Android via the wrapper.
    static func gradleTask(
        androidDir: URL,
        task: String,
        name: String,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> StageResult {
        let gradlew = androidDir.appendingPathComponent("gradlew")
        guard FileManager.default.fileExists(atPath: gradlew.path) else {
            return StageResult(name: name, ok: false,
                               detail: "gradlew missing in Apps/Android — re-run swiftport init")
        }
        // Defensive: callers pre-check jdkAvailable(), but keep the guard
        // for direct invocations.
        if !Self.jdkAvailable() {
            return StageResult(name: name, ok: false,
                               detail: "JDK 17+ required — install a JDK and re-run `swiftport doctor`")
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: gradlew.path)
        var args = [task]
        let effective = Build.jobCount(jobs: jobs, lowMemory: lowMemory)
        if let effective { args += ["--max-workers", String(effective)] }
        guard let result = try? Shell.run(gradlew.path, arguments: args,
                                          currentDirectory: androidDir) else {
            return StageResult(name: name, ok: false,
                               detail: "failed to launch gradlew in Apps/Android")
        }
        let tail = result.combined
            .components(separatedBy: .newlines)
            .suffix(15)
            .joined(separator: "\n")
        return StageResult(name: name, ok: result.succeeded, detail: tail)
    }

    /// True when pkg-config can see gtk4 + libadwaita (needed to build the
    /// Linux app's Adwaita dependency, even for contract tests).
    /// Environment for xcodebuild/xcrun calls: points DEVELOPER_DIR at
    /// Xcode when the active developer dir is Command Line Tools (which
    /// lacks simctl and the iOS platform).
    static var xcodeEnvironment: [String: String] {
        #if os(macOS)
        if ProcessInfo.processInfo.environment["DEVELOPER_DIR"] == nil {
            let xcode = "/Applications/Xcode.app/Contents/Developer"
            if FileManager.default.fileExists(atPath: xcode) {
                return ["DEVELOPER_DIR": xcode]
            }
        }
        #endif
        return [:]
    }

    static func gtkToolchainAvailable() -> Bool {
        guard Shell.which("pkg-config") != nil else { return false }
        let gtk = (try? Shell.run("pkg-config", arguments: ["--exists", "gtk4"]))?.succeeded ?? false
        let adw = (try? Shell.run("pkg-config", arguments: ["--exists", "libadwaita-1"]))?.succeeded ?? false
        return gtk && adw
    }

    static var hostIsLinux: Bool {
        FileManager.default.fileExists(atPath: "/etc/os-release")
            || ProcessInfo.processInfo.environment["XDG_CURRENT_DESKTOP"] != nil
    }

    static func swiftTest(
        packageAt dir: URL,
        name: String,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> StageResult {
        var args = ["test"]
        let effective = Build.jobCount(jobs: jobs, lowMemory: lowMemory)
        if let effective { args += ["-j", String(effective)] }

        // Swift Testing's macro plugin ships with Xcode, not Command Line
        // Tools — prefer Xcode's developer dir when it's installed.
        var environment: [String: String] = [:]
        #if os(macOS)
        if ProcessInfo.processInfo.environment["DEVELOPER_DIR"] == nil {
            let xcode = "/Applications/Xcode.app/Contents/Developer"
            if FileManager.default.fileExists(atPath: xcode) {
                environment["DEVELOPER_DIR"] = xcode
            }
        }
        #endif

        guard let result = try? Shell.run("swift", arguments: args,
                                          currentDirectory: dir,
                                          environment: environment) else {
            return StageResult(name: name, ok: false,
                               detail: "failed to launch `swift test` in \(dir.lastPathComponent)")
        }
        let tail = result.combined
            .components(separatedBy: .newlines)
            .suffix(15)
            .joined(separator: "\n")
        return StageResult(name: name, ok: result.succeeded, detail: tail)
    }

    // MARK: - Snapshots (Apple)

    static func runSnapshots(
        root: URL,
        config: ProjectConfig,
        platforms: Set<ProjectConfig.Platform>,
        update: Bool,
        captureOnly: Bool,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> [SnapshotResult] {
        var results: [SnapshotResult] = []

        #if os(macOS)
        if platforms.contains(.apple) {
            results.append(contentsOf: try runAppleSnapshots(
                root: root, config: config,
                update: update, captureOnly: captureOnly,
                lowMemory: lowMemory, jobs: jobs
            ))
            results.append(contentsOf: try runIOSSnapshots(
                root: root, config: config,
                update: update, captureOnly: captureOnly,
                lowMemory: lowMemory, jobs: jobs
            ))
        }
        #endif

        if platforms.contains(.android) {
            results.append(contentsOf: try runAndroidSnapshots(
                root: root, config: config,
                update: update, captureOnly: captureOnly,
                lowMemory: lowMemory, jobs: jobs
            ))
        }

        if platforms.contains(.linux) {
            results.append(contentsOf: try runLinuxSnapshots(
                root: root, config: config,
                update: update, captureOnly: captureOnly,
                lowMemory: lowMemory, jobs: jobs
            ))
        }

        for platform in platforms where platform == .windows {
            results.append(SnapshotResult(
                file: platform.rawValue, status: .skipped, diffFraction: nil))
        }
        if results.isEmpty {
            results.append(SnapshotResult(file: "-", status: .skipped, diffFraction: nil))
        }
        return results
    }

    // MARK: - Apple snapshots

    #if os(macOS)
    static func runAppleSnapshots(
        root: URL,
        config: ProjectConfig,
        update: Bool,
        captureOnly: Bool,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> [SnapshotResult] {
        let appleDir = root.appendingPathComponent("Apps/Apple")
        let contractsDir = root.appendingPathComponent("Verification/Contracts")
        let snapshotsRoot = root.appendingPathComponent("Verification/Snapshots")
        let currentDir = snapshotsRoot.appendingPathComponent("current/apple")
        let goldenDir = snapshotsRoot.appendingPathComponent("apple")

        guard FileManager.default.fileExists(atPath: contractsDir.path) else {
            throw VerifyError.missingDirectory(contractsDir.path)
        }

        // Build the snapshot runner. Prefer Xcode's developer dir when
        // present — SwiftUI/Testing need the full Xcode toolchain on macOS.
        var buildArgs = ["build", "--product", "snapshot-runner"]
        let effective = Build.jobCount(jobs: jobs, lowMemory: lowMemory)
        if let effective { buildArgs += ["-j", String(effective)] }
        var buildEnv: [String: String] = [:]
        if ProcessInfo.processInfo.environment["DEVELOPER_DIR"] == nil {
            let xcode = "/Applications/Xcode.app/Contents/Developer"
            if FileManager.default.fileExists(atPath: xcode) {
                buildEnv["DEVELOPER_DIR"] = xcode
            }
        }
        let build = try Shell.run("swift", arguments: buildArgs,
                                  currentDirectory: appleDir, environment: buildEnv)
        guard build.succeeded else {
            return [SnapshotResult(file: "build", status: .regression,
                                   diffFraction: nil,
                                   detail: build.combined.suffix(2000).description)]
        }

        // Run it. Wipe `current/` first — stale captures from renamed or
        // removed matrix variants would otherwise be re-blessed as ghosts.
        let binary = appleDir.appendingPathComponent(".build/debug/snapshot-runner")
        try? FileManager.default.removeItem(at: currentDir)
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        let run = try Shell.run(binary.path, arguments: [
            "--contracts-dir", contractsDir.path,
            "--output-dir", currentDir.path,
        ], currentDirectory: appleDir)
        guard run.succeeded else {
            return [SnapshotResult(file: "run", status: .regression,
                                   diffFraction: nil,
                                   detail: run.combined.suffix(2000).description)]
        }

        return try finishSnapshots(
            current: currentDir, golden: goldenDir,
            update: update, captureOnly: captureOnly,
            tolerance: config.verify.snapshotTolerance
        )
    }

    // MARK: - iOS snapshots (simulator)

    /// Builds the app for an iPhone simulator, launches it once per
    /// contract scenario × theme with `SWIFTPORT_*` env vars, and captures
    /// `simctl io screenshot`. Filenames include the device name — goldens
    /// are device-specific. The status bar is overridden for determinism.
    static func runIOSSnapshots(
        root: URL,
        config: ProjectConfig,
        update: Bool,
        captureOnly: Bool,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> [SnapshotResult] {
        let appleDir = root.appendingPathComponent("Apps/Apple")
        let snapshotsRoot = root.appendingPathComponent("Verification/Snapshots")
        let currentDir = snapshotsRoot.appendingPathComponent("current/ios")
        let goldenDir = snapshotsRoot.appendingPathComponent("ios")
        let contractsDir = root.appendingPathComponent("Verification/Contracts")
        let fm = FileManager.default

        func skipped(_ detail: String) -> [SnapshotResult] {
            [SnapshotResult(file: "ios", status: .skipped,
                            diffFraction: nil, detail: detail)]
        }

        guard fm.fileExists(atPath: appleDir.path) else {
            return skipped("Apps/Apple not found")
        }
        guard Shell.which("xcodebuild") != nil, Shell.which("xcrun") != nil else {
            return skipped("xcodebuild/xcrun not found")
        }
        guard let device = firstIPhoneSimulator() else {
            return skipped("no iPhone simulator found — install one in Xcode "
                + "(Xcode → Settings → Components)")
        }
        let fixtureIDs = contractFixtureIDs(in: contractsDir)
        guard !fixtureIDs.isEmpty else {
            return skipped("no contract fixtures found in Verification/Contracts")
        }

        let tokens = Template.Tokens(
            appName: config.name, bundleIDPrefix: config.bundleIDPrefix)
        let project = appleDir.appendingPathComponent("\(tokens.appModule).xcodeproj")
        guard fm.fileExists(atPath: project.path) else {
            return skipped("\(tokens.appModule).xcodeproj missing — run `swiftport sync`")
        }

        // Boot the simulator if needed; shut it down afterwards only when
        // we booted it ourselves.
        var weBooted = false
        if device.state != "Booted" {
            guard let boot = try? Shell.run("xcrun", arguments: ["simctl", "boot", device.udid], environment: xcodeEnvironment),
                  boot.succeeded else {
                return skipped("could not boot simulator \(device.name)")
            }
            weBooted = true
            _ = try? Shell.run("xcrun", arguments: ["simctl", "bootstatus", device.udid, "-b"], environment: xcodeEnvironment)
        }
        defer {
            _ = try? Shell.run("xcrun", arguments: ["simctl", "status_bar", "booted", "clear"], environment: xcodeEnvironment)
            if weBooted {
                _ = try? Shell.run("xcrun", arguments: ["simctl", "shutdown", device.udid], environment: xcodeEnvironment)
            }
        }

        // Deterministic status bar (real clock would drift between goldens).
        _ = try? Shell.run("xcrun", arguments: [
            "simctl", "status_bar", "booted", "override",
            "--time", "9:41",
            "--batteryState", "charged", "--batteryLevel", "100",
            "--wifiMode", "active", "--wifiBars", "3",
            "--cellularMode", "active", "--cellularBars", "4",
            "--operatorName", "SwiftPort",
        ], environment: xcodeEnvironment)

        // Build for the simulator.
        let dd = fm.temporaryDirectory
            .appendingPathComponent("swiftport-ios-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dd) }
        var buildArgs = [
            "-project", project.path,
            "-scheme", "\(tokens.appModule)iOS",
            "-destination", "platform=iOS Simulator,id=\(device.udid)",
            "-configuration", "Debug",
            "-derivedDataPath", dd.path,
            "build",
        ]
        let effective = Build.jobCount(jobs: jobs, lowMemory: lowMemory)
        if let effective { buildArgs += ["-jobs", String(effective)] }
        let buildResult = try? Shell.run(
            "xcodebuild", arguments: buildArgs,
            currentDirectory: appleDir, environment: xcodeEnvironment)
        guard let build = buildResult, build.succeeded else {
            return [SnapshotResult(
                file: "ios-build", status: .regression, diffFraction: nil,
                detail: (buildResult?.combined ?? "xcodebuild failed")
                    .suffix(2000).description)]
        }

        // Locate the built .app.
        let productsDir = dd.appendingPathComponent("Build/Products/Debug-iphonesimulator")
        guard let appName = (try? fm.contentsOfDirectory(atPath: productsDir.path))?
            .first(where: { $0.hasSuffix(".app") }) else {
            return [SnapshotResult(file: "ios-app", status: .regression,
                                   diffFraction: nil,
                                   detail: "no .app in \(productsDir.path)")]
        }
        let appPath = productsDir.appendingPathComponent(appName)
        guard let install = try? Shell.run("xcrun", arguments: [
            "simctl", "install", "booted", appPath.path], environment: xcodeEnvironment), install.succeeded else {
            return [SnapshotResult(file: "ios-install", status: .regression,
                                   diffFraction: nil, detail: "simctl install failed")]
        }

        try? fm.removeItem(at: currentDir)
        try fm.createDirectory(at: currentDir, withIntermediateDirectories: true)

        // Reference frame of whatever is frontmost before the first launch —
        // used to detect captures that actually show SpringBoard because the
        // app failed to come to the foreground.
        let springRef = dd.appendingPathComponent("springboard-ref.png")
        _ = try? Shell.run("xcrun", arguments: [
            "simctl", "io", "booted", "screenshot", springRef.path],
            environment: xcodeEnvironment)

        let deviceTag = device.name.replacingOccurrences(of: " ", with: "_")
        var consecutiveBad = 0
        var badCount = 0
        var totalCount = 0
        var captureAborted = false
        for fixtureID in fixtureIDs {
            for theme in config.verify.themes {
                let png = currentDir.appendingPathComponent(
                    "\(fixtureID)__\(theme)__\(deviceTag).png")
                // SIMCTL_CHILD_* env vars are forwarded to the app process.
                var launchEnv = xcodeEnvironment
                launchEnv["SIMCTL_CHILD_SWIFTPORT_SCENARIO"] = fixtureID
                launchEnv["SIMCTL_CHILD_SWIFTPORT_THEME"] = theme
                launchEnv["SIMCTL_CHILD_SWIFTPORT_CONTRACTS_DIR"] = contractsDir.path
                let launch = try? Shell.run("xcrun", arguments: [
                    "simctl", "launch", "--terminate-running-process",
                    "booted", tokens.bundleID,
                ], environment: launchEnv)
                guard let launch, launch.succeeded else { continue }
                Thread.sleep(forTimeInterval: 3)
                _ = try? Shell.run("xcrun", arguments: [
                    "simctl", "io", "booted", "screenshot", png.path], environment: xcodeEnvironment)
                totalCount += 1
                // A capture is "bad" when the framebuffer never composited the
                // app: either a flat uncomposited frame, or SpringBoard still
                // frontmost because the app never appeared. Three in a row
                // means a broken capture pipeline, not sparse screens.
                var bad = SnapshotDiff.isBlankCapture(png)
                if !bad, fm.fileExists(atPath: springRef.path),
                   let diff = try? SnapshotDiff.compare(pngA: png, pngB: springRef),
                   diff < 0.05 {
                    bad = true
                }
                if bad {
                    try? fm.removeItem(at: png)
                    badCount += 1
                    consecutiveBad += 1
                    if consecutiveBad >= 3 { captureAborted = true; break }
                } else {
                    consecutiveBad = 0
                }
            }
            if captureAborted { break }
        }

        // A host whose simulator never composites app content returns flat
        // frames (white/black) or SpringBoard for most captures — blessing
        // those as goldens would poison every other machine. Skip instead.
        if captureAborted || (totalCount > 0 && badCount * 5 >= totalCount * 4) {
            return skipped(
                "simulator captures show no app content (\(badCount)/\(totalCount) bad) — "
                + "screen capture is not compositing app frames on this host; "
                + "reboot the simulator or run `swiftport verify` on CI")
        }

        return try finishSnapshots(
            current: currentDir, golden: goldenDir,
            update: update, captureOnly: captureOnly,
            tolerance: config.verify.snapshotTolerance
        )
    }

    /// First available iPhone simulator — prefers an already-booted device.
    static func firstIPhoneSimulator() -> (udid: String, name: String, state: String)? {
        guard let result = try? Shell.run("xcrun", arguments: [
            "simctl", "list", "devices", "available", "-j"], environment: xcodeEnvironment),
              result.succeeded,
              let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let runtimes = json["devices"] as? [String: Any]
        else { return nil }
        var fallback: (String, String, String)?
        for value in runtimes.values {
            guard let devices = value as? [[String: Any]] else { continue }
            for d in devices {
                guard let name = d["name"] as? String, name.contains("iPhone"),
                      let udid = d["udid"] as? String,
                      let state = d["state"] as? String else { continue }
                if state == "Booted" { return (udid, name, state) }
                if fallback == nil { fallback = (udid, name, state) }
            }
        }
        return fallback
    }
    #endif

    // MARK: - Android snapshots (Paparazzi)

    /// `recordPaparazziDebug` renders every contract fixture × theme through
    /// the Compose UI; the PNGs land under `app/build/output/paparazzi` and
    /// are diffed against `Verification/Snapshots/android` goldens.
    static func runAndroidSnapshots(
        root: URL,
        config: ProjectConfig,
        update: Bool,
        captureOnly: Bool,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> [SnapshotResult] {
        let androidDir = root.appendingPathComponent("Apps/Android")
        let outputRoot = androidDir.appendingPathComponent("app/build/output/paparazzi")
        let snapshotsRoot = root.appendingPathComponent("Verification/Snapshots")
        let currentDir = snapshotsRoot.appendingPathComponent("current/android")
        let goldenDir = snapshotsRoot.appendingPathComponent("android")

        guard FileManager.default.fileExists(atPath: androidDir.path) else {
            return [SnapshotResult(file: "android", status: .skipped, diffFraction: nil)]
        }
        guard Self.jdkAvailable() else {
            return [SnapshotResult(
                file: "android", status: .skipped, diffFraction: nil,
                detail: "skipped — JDK 17+ required for Gradle"
            )]
        }

        let stage = try gradleTask(
            androidDir: androidDir, task: "recordPaparazziDebug",
            name: "snapshots:android", lowMemory: lowMemory, jobs: jobs
        )
        guard stage.ok else {
            return [SnapshotResult(file: "recordPaparazziDebug", status: .regression,
                                   diffFraction: nil, detail: stage.detail)]
        }

        try? FileManager.default.removeItem(at: currentDir)
        try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        try copyPNGsPreservingStructure(from: outputRoot, to: currentDir)

        return try finishSnapshots(
            current: currentDir, golden: goldenDir,
            update: update, captureOnly: captureOnly,
            tolerance: config.verify.snapshotTolerance
        )
    }

    // MARK: - Linux snapshots (Xvfb + GTK)

    /// Runs the real GTK app under Xvfb once per contract fixture (the app
    /// reads `SWIFTPORT_SCENARIO`/`SWIFTPORT_CONTRACTS_DIR`) and screenshots
    /// the root window with ImageMagick's `import`. Light theme only —
    /// libadwaita's color-scheme follows the desktop settings portal, which
    /// is unreliable headless.
    static func runLinuxSnapshots(
        root: URL,
        config: ProjectConfig,
        update: Bool,
        captureOnly: Bool,
        lowMemory: Bool,
        jobs: Int?
    ) throws -> [SnapshotResult] {
        let linuxDir = root.appendingPathComponent("Apps/Linux")
        let snapshotsRoot = root.appendingPathComponent("Verification/Snapshots")
        let currentDir = snapshotsRoot.appendingPathComponent("current/linux")
        let goldenDir = snapshotsRoot.appendingPathComponent("linux")
        let contractsDir = root.appendingPathComponent("Verification/Contracts")

        func skipped(_ detail: String) -> [SnapshotResult] {
            [SnapshotResult(file: "linux", status: .skipped,
                            diffFraction: nil, detail: detail)]
        }

        guard FileManager.default.fileExists(atPath: linuxDir.path) else {
            return skipped("Apps/Linux not found")
        }
        guard hostIsLinux else {
            return skipped("GTK screenshots need a Linux host/CI")
        }
        let tokens = Template.Tokens(
            appName: config.name, bundleIDPrefix: config.bundleIDPrefix)
        let binary = linuxDir.appendingPathComponent(".build/debug/\(tokens.appModule)")
        guard FileManager.default.fileExists(atPath: binary.path) else {
            return skipped("Linux app not built — run `swiftport build --target linux` first")
        }
        guard Shell.which("Xvfb") != nil, Shell.which("import") != nil else {
            return skipped("install xvfb + imagemagick for GTK snapshots "
                + "(sudo apt install xvfb imagemagick)")
        }
        let fixtureIDs = contractFixtureIDs(in: contractsDir)
        guard !fixtureIDs.isEmpty else {
            return skipped("no contract fixtures found in Verification/Contracts")
        }

        // Ensure a fresh debug build so the scenario env vars are honored —
        // cheap no-op when sources are unchanged.
        _ = try? Shell.run("swift", arguments: ["build"], currentDirectory: linuxDir)

        try? FileManager.default.removeItem(at: currentDir)
        try FileManager.default.createDirectory(
            at: currentDir, withIntermediateDirectories: true)

        // Fixed display avoids collisions; verify runs platforms serially.
        let display = ":98"
        for fixtureID in fixtureIDs {
            let png = currentDir.appendingPathComponent("\(fixtureID)__light.png")
            let script = """
            Xvfb \(display) -screen 0 1280x1024x24 >/dev/null 2>&1 &
            XPID=$!
            sleep 1
            DISPLAY=\(display) SWIFTPORT_SCENARIO=\(fixtureID) \
            SWIFTPORT_CONTRACTS_DIR=\(contractsDir.path) \
            \(binary.path) >/dev/null 2>&1 &
            APPPID=$!
            sleep 6
            DISPLAY=\(display) import -window root \(png.path)
            kill $APPPID $XPID 2>/dev/null
            wait $APPPID $XPID 2>/dev/null
            """
            _ = try? Shell.run("/bin/sh", arguments: ["-c", script])
        }

        return try finishSnapshots(
            current: currentDir, golden: goldenDir,
            update: update, captureOnly: captureOnly,
            tolerance: config.verify.snapshotTolerance
        )
    }

    /// Fixture ids from `Verification/Contracts/*.json` (the `id` field).
    static func contractFixtureIDs(in dir: URL) -> [String] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil) else { return [] }
        return files
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> String? in
                guard let data = try? Data(contentsOf: url),
                      let obj = try? JSONSerialization.jsonObject(with: data)
                        as? [String: Any]
                else { return nil }
                return obj["id"] as? String
            }
            .sorted()
    }

    /// Copies every PNG under `source` into `dest`, preserving relative paths.
    static func copyPNGsPreservingStructure(from source: URL, to dest: URL) throws {
        let fm = FileManager.default
        let base = source.standardizedFileURL.resolvingSymlinksInPath().path
        for png in pngFiles(in: source) {
            let pngPath = png.standardizedFileURL.resolvingSymlinksInPath().path
            let relative = pngPath.hasPrefix(base + "/")
                ? String(pngPath.dropFirst(base.count + 1))
                : png.lastPathComponent
            let target = dest.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: png, to: target)
        }
    }

    /// Shared tail of snapshot verification: bless, capture-only, or diff
    /// every PNG under `current` against `golden`.
    static func finishSnapshots(
        current: URL,
        golden: URL,
        update: Bool,
        captureOnly: Bool,
        tolerance: Double
    ) throws -> [SnapshotResult] {
        let fm = FileManager.default
        let base = current.standardizedFileURL.resolvingSymlinksInPath().path
        func relName(_ url: URL) -> String {
            let p = url.standardizedFileURL.resolvingSymlinksInPath().path
            return p.hasPrefix(base + "/") ? String(p.dropFirst(base.count + 1)) : url.lastPathComponent
        }

        let currentPNGs = pngFiles(in: current)
        guard !currentPNGs.isEmpty else {
            return [SnapshotResult(file: "-", status: .regression, diffFraction: nil)]
        }
        if update {
            try bless(current: current, golden: golden)
            return currentPNGs.map {
                SnapshotResult(file: relName($0), status: .blessed, diffFraction: nil)
            }
        }
        if captureOnly {
            return currentPNGs.map {
                SnapshotResult(file: relName($0), status: .skipped, diffFraction: nil)
            }
        }

        var results: [SnapshotResult] = []
        for png in currentPNGs {
            let name = relName(png)
            let goldenPNG = golden.appendingPathComponent(name)
            guard fm.fileExists(atPath: goldenPNG.path) else {
                results.append(SnapshotResult(file: name, status: .new, diffFraction: nil))
                continue
            }
            do {
                let diff = try SnapshotDiff.compare(pngA: png, pngB: goldenPNG)
                results.append(SnapshotResult(
                    file: name,
                    status: diff <= tolerance ? .match : .regression,
                    diffFraction: diff
                ))
            } catch {
                results.append(SnapshotResult(file: name, status: .regression, diffFraction: nil))
            }
        }
        return results
    }

    static func pngFiles(in dir: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var files: [URL] = []
        while let url = enumerator.nextObject() as? URL {
            if url.pathExtension == "png" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    /// Copies every PNG under `current` into `golden`, preserving relative paths.
    /// Paths are standardized first — `/tmp` vs `/private/tmp` symlink
    /// resolution otherwise corrupts the relative-path computation.
    static func bless(current: URL, golden: URL) throws {
        let fm = FileManager.default
        let currentPath = current.standardizedFileURL.resolvingSymlinksInPath().path
        for png in pngFiles(in: current) {
            let pngPath = png.standardizedFileURL.resolvingSymlinksInPath().path
            let relative: String
            if pngPath.hasPrefix(currentPath + "/") {
                relative = String(pngPath.dropFirst(currentPath.count + 1))
            } else {
                relative = png.lastPathComponent
            }
            let dest = golden.appendingPathComponent(relative)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: dest)
            try fm.copyItem(at: png, to: dest)
        }
    }

    // MARK: - HTML report

    /// Writes `Verification/report.html`: a stage summary plus side-by-side
    /// current-vs-golden cards for every captured snapshot. Images are
    /// referenced relatively, so the report works straight from the repo.
    @discardableResult
    public static func writeReport(root: URL, report: Report) throws -> URL {
        let verificationDir = root.appendingPathComponent("Verification")
        let snapshotsDir = verificationDir.appendingPathComponent("Snapshots")
        let currentRoot = snapshotsDir.appendingPathComponent("current")
        let out = verificationDir.appendingPathComponent("report.html")

        var byName: [String: SnapshotResult] = [:]
        for r in report.snapshotResults { byName[r.file] = r }

        var sections: [String] = []
        if let platforms = try? FileManager.default
            .contentsOfDirectory(atPath: currentRoot.path).sorted() {
            for platform in platforms where !platform.hasPrefix(".") {
                let currentDir = currentRoot.appendingPathComponent(platform)
                var cards: [String] = []
                for png in pngFiles(in: currentDir) {
                    let base = currentDir.standardizedFileURL
                        .resolvingSymlinksInPath().path
                    let p = png.standardizedFileURL.resolvingSymlinksInPath().path
                    let rel = p.hasPrefix(base + "/")
                        ? String(p.dropFirst(base.count + 1)) : png.lastPathComponent
                    let result = byName[rel] ?? byName[png.lastPathComponent]
                    cards.append(snapshotCard(
                        platform: platform, rel: rel, result: result,
                        goldenURL: snapshotsDir.appendingPathComponent(platform)
                            .appendingPathComponent(rel)
                    ))
                }
                if !cards.isEmpty {
                    sections.append(
                        "<h2>\(htmlEscape(platform))</h2><div class=\"grid\">"
                            + cards.joined() + "</div>")
                }
            }
        }

        let name = (try? ProjectConfig.load(from: root).name) ?? root.lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let verdict = report.ok ? "PASS" : "FAIL"
        let verdictClass = report.ok ? "pass" : "fail"

        var stageRows = ""
        for stage in report.stages {
            let cls = stage.ok ? "ok" : "fail"
            let mark = stage.ok ? "✓" : "✗"
            stageRows += "<tr class=\"\(cls)\"><td>\(mark)</td><td>\(htmlEscape(stage.name))</td></tr>"
        }

        let html = """
        <!DOCTYPE html>
        <html lang="en"><head><meta charset="utf-8">
        <title>SwiftPort verify — \(htmlEscape(name))</title>
        <style>
          body { font-family: -apple-system, system-ui, sans-serif; margin: 2rem; color: #1a1a1a; }
          h1 { font-size: 1.4rem; } h2 { font-size: 1.1rem; margin-top: 2rem; }
          .verdict { display: inline-block; padding: .2rem .8rem; border-radius: 1rem;
                     font-weight: 700; color: #fff; }
          .verdict.pass { background: #1a7f37; } .verdict.fail { background: #cf222e; }
          table { border-collapse: collapse; margin: 1rem 0; }
          td { padding: .3rem 1rem .3rem 0; font-family: ui-monospace, monospace; font-size: .9rem; }
          tr.ok td:first-child { color: #1a7f37; } tr.fail td:first-child { color: #cf222e; }
          .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
                  gap: 1rem; }
          .card { border: 1px solid #d0d7de; border-radius: 8px; padding: .6rem; }
          .card .name { font-family: ui-monospace, monospace; font-size: .8rem;
                        word-break: break-all; }
          .badge { display: inline-block; padding: .1rem .5rem; border-radius: .7rem;
                   font-size: .75rem; font-weight: 600; color: #fff; margin-left: .4rem; }
          .b-match { background: #1a7f37; } .b-regression { background: #cf222e; }
          .b-new { background: #0969da; } .b-blessed { background: #8250df; }
          .b-skipped, .b-unknown { background: #6e7781; }
          .diff { color: #57606a; font-size: .8rem; margin-left: .4rem; }
          .pair { display: flex; gap: .5rem; margin-top: .5rem; }
          .pair figure { margin: 0; flex: 1; }
          .pair img { width: 100%; border: 1px solid #d0d7de; border-radius: 4px;
                      image-rendering: auto; }
          .pair figcaption { font-size: .7rem; color: #57606a; text-align: center; }
          .meta { color: #57606a; font-size: .85rem; }
        </style></head><body>
        <h1>SwiftPort verify — \(htmlEscape(name))
            <span class="verdict \(verdictClass)">\(verdict)</span></h1>
        <p class="meta">Generated \(timestamp) · tolerance from swiftport.toml</p>
        <table>\(stageRows)</table>
        \(sections.isEmpty ? "<p class=\"meta\">No snapshots captured.</p>" : sections.joined(separator: "\n"))
        </body></html>
        """
        try html.write(to: out, atomically: true, encoding: .utf8)
        return out
    }

    static func snapshotCard(
        platform: String, rel: String,
        result: SnapshotResult?, goldenURL: URL
    ) -> String {
        let status = result?.status.rawValue ?? "unknown"
        let badgeClass = "b-\(status)"
        let diff = result?.diffFraction
            .map { " <span class=\"diff\">\(String(format: "%.3f%%", $0 * 100))</span>" } ?? ""
        let currentSrc = "Snapshots/current/\(platform)/\(rel)"
        let goldenSrc = "Snapshots/\(platform)/\(rel)"
        let hasGolden = FileManager.default.fileExists(atPath: goldenURL.path)

        var figures = "<figure><img src=\"\(currentSrc)\" loading=\"lazy\">"
            + "<figcaption>current</figcaption></figure>"
        if hasGolden {
            figures += "<figure><img src=\"\(goldenSrc)\" loading=\"lazy\">"
                + "<figcaption>golden</figcaption></figure>"
        }
        return """
        <div class="card">
          <div class="name">\(htmlEscape(rel))
            <span class="badge \(badgeClass)">\(status)</span>\(diff)</div>
          <div class="pair">\(figures)</div>
        </div>
        """
    }

    static func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Rendering

    public static func render(_ report: Report) -> String {
        var lines: [String] = []
        for stage in report.stages {
            lines.append("  [\(stage.ok ? "ok" : "FAIL")] \(stage.name)")
            if !stage.ok || stage.detail.contains("FAIL") {
                for detailLine in stage.detail.components(separatedBy: .newlines).suffix(8) {
                    lines.append("       \(detailLine)")
                }
            }
        }
        if !report.snapshotResults.isEmpty {
            lines.append("")
            lines.append("  Snapshots:")
            for r in report.snapshotResults {
                let diff = r.diffFraction.map { String(format: "%.3f%%", $0 * 100) } ?? "-"
                lines.append("    [\(r.status.rawValue)] \(r.file)  diff=\(diff)")
                if let detail = r.detail {
                    for detailLine in detail.components(separatedBy: .newlines).suffix(6) {
                        lines.append("       \(detailLine)")
                    }
                }
            }
        }
        lines.append("")
        lines.append(report.ok ? "verify: PASS" : "verify: FAIL")
        return lines.joined(separator: "\n")
    }
}
