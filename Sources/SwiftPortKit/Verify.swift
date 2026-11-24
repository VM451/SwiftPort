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
        for platform in [ProjectConfig.Platform.android, .windows] where platforms.contains(platform) {
            results.append(StageResult(
                name: "contracts:\(platform.rawValue)",
                ok: true,
                detail: "skipped — \(platform.rawValue) contracts land with its bridge phase"
            ))
        }
        return results
    }

    /// True when pkg-config can see gtk4 + libadwaita (needed to build the
    /// Linux app's Adwaita dependency, even for contract tests).
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
        #if os(macOS)
        guard platforms.contains(.apple) else {
            return [SnapshotResult(file: "-", status: .skipped,
                                   diffFraction: nil)]
        }
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

        // Collect produced PNGs.
        let currentPNGs = pngFiles(in: currentDir)
        guard !currentPNGs.isEmpty else {
            return [SnapshotResult(file: "-", status: .regression, diffFraction: nil)]
        }

        if update {
            try bless(current: currentDir, golden: goldenDir)
            return currentPNGs.map {
                SnapshotResult(file: $0.lastPathComponent, status: .blessed, diffFraction: nil)
            }
        }
        if captureOnly {
            return currentPNGs.map {
                SnapshotResult(file: $0.lastPathComponent, status: .skipped, diffFraction: nil)
            }
        }

        // Compare against goldens.
        var results: [SnapshotResult] = []
        for current in currentPNGs {
            let name = current.lastPathComponent
            let golden = goldenDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: golden.path) else {
                results.append(SnapshotResult(file: name, status: .new, diffFraction: nil))
                continue
            }
            do {
                let diff = try SnapshotDiff.compare(pngA: current, pngB: golden)
                results.append(SnapshotResult(
                    file: name,
                    status: diff <= config.verify.snapshotTolerance ? .match : .regression,
                    diffFraction: diff
                ))
            } catch {
                results.append(SnapshotResult(file: name, status: .regression, diffFraction: nil))
            }
        }
        return results
        #else
        return [SnapshotResult(file: "-", status: .skipped, diffFraction: nil)]
        #endif
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
