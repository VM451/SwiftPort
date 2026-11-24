import ArgumentParser
import Foundation
import SwiftPortKit
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@main
struct SwiftPort: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swiftport",
        abstract: "Apple-first, native-everywhere app scaffolding and verification",
        version: SwiftPortKit.version,
        subcommands: [
            InitCommand.self,
            DoctorCommand.self,
            SyncCommand.self,
            BuildCommand.self,
            VerifyCommand.self,
            LintCommand.self,
        ]
    )
}

// MARK: - init

struct InitCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Scaffold a new SwiftPort monorepo"
    )

    @Argument(help: "App name (e.g. TaskFlow)")
    var name: String

    @Option(name: .long, help: "Output directory (default: ./<AppName>)")
    var path: String?

    @Option(name: .long, help: "Comma-separated platforms: apple,android,windows,linux (default: apple,linux; prompts on a TTY)")
    var platforms: String?

    @Option(name: .long, help: "Bundle ID prefix")
    var bundleIDPrefix: String = "com.example"

    @Flag(name: .long, help: "Skip git repository initialization")
    var noGit: Bool = false

    func run() throws {
        let selected: Set<ProjectConfig.Platform>
        if let platforms {
            let parsed = Set(platforms.split(separator: ",").compactMap {
                ProjectConfig.Platform(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased())
            })
            let unknown = platforms.split(separator: ",").contains {
                ProjectConfig.Platform(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased()) == nil
            }
            guard !parsed.isEmpty, !unknown else {
                throw ValidationError("invalid --platforms value: \(platforms)")
            }
            selected = parsed
        } else if Self.stdinIsTTY, let picked = Self.promptPlatforms() {
            selected = picked
        } else {
            selected = [.apple, .linux]
        }

        let dest: URL
        if let path {
            dest = URL(fileURLWithPath: path).standardizedFileURL
        } else {
            let slug = name.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
            dest = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent(String(slug))
        }

        let result = try Init.run(appName: name, options: Init.Options(
            path: dest,
            platforms: selected,
            bundleIDPrefix: bundleIDPrefix,
            git: !noGit
        ))
        print(Init.render(result))
    }

    static var stdinIsTTY: Bool {
        #if canImport(Darwin) || canImport(Glibc)
        return isatty(STDIN_FILENO) != 0
        #else
        return false
        #endif
    }

    /// Interactive platform picker. Enter = default (apple, linux).
    static func promptPlatforms() -> Set<ProjectConfig.Platform>? {
        let all = ProjectConfig.Platform.allCases
        print("Select target platforms — comma-separated numbers, 'all', or Enter for default [apple, linux]:")
        for (index, platform) in all.enumerated() {
            print("  \(index + 1). \(platform.rawValue)")
        }
        guard let line = readLine()?.trimmingCharacters(in: .whitespaces),
              !line.isEmpty else { return nil }
        if line.lowercased() == "all" { return Set(all) }
        var selected = Set<ProjectConfig.Platform>()
        for part in line.split(separator: ",") {
            guard let n = Int(part.trimmingCharacters(in: .whitespaces)),
                  all.indices.contains(n - 1) else { continue }
            selected.insert(all[n - 1])
        }
        return selected.isEmpty ? nil : selected
    }
}

// MARK: - doctor

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Audit the host toolchain for required SDKs"
    )

    @Option(name: .long, help: "Comma-separated platforms to audit (default: all enabled)")
    var platforms: String?

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let root = RootLocator.find(from: cwd)
        var config = root.flatMap { try? ProjectConfig.load(from: $0) }
        if let platforms {
            let parsed = Set(platforms.split(separator: ",").compactMap {
                ProjectConfig.Platform(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased())
            })
            guard !parsed.isEmpty else {
                throw ValidationError("invalid --platforms value: \(platforms)")
            }
            config?.platforms = parsed
        }
        let report = Doctor.run(root: root ?? cwd, config: config)
        print(Doctor.render(report))
        if !report.failed.isEmpty { throw ExitCode(1) }
    }
}

// MARK: - sync

struct SyncCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sync",
        abstract: "Scan exported APIs and regenerate platform bridges"
    )

    @Option(name: .long, help: "Job count override")
    var jobs: Int?

    func run() throws {
        let root = try RootLocator.require()
        let config = try ProjectConfig.load(from: root)
        let report = try Sync.run(root: root, config: config, jobs: jobs)
        print(Sync.render(report))
    }
}

// MARK: - lint

struct LintCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lint",
        abstract: "Check Core/ for platform-locked imports"
    )

    func run() throws {
        let root = try RootLocator.require()
        let report = try Lint.run(root: root)
        print(Lint.render(report))
        if !report.isClean { throw ExitCode(1) }
    }
}

// MARK: - build

struct BuildCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build a platform target"
    )

    @Option(name: .long, help: "Target platform")
    var target: String

    @Flag(name: .long, help: "Release configuration")
    var release: Bool = false

    @Flag(name: .long, help: "Low-memory mode (throttles parallel jobs)")
    var lowMemory: Bool = false

    @Option(name: .shortAndLong, help: "Job count")
    var jobs: Int?

    func run() throws {
        guard let buildTarget = Build.Target(rawValue: target.lowercased()) else {
            throw ValidationError("unknown target '\(target)' — expected apple|linux|android|windows")
        }
        let root = try RootLocator.require()
        do {
            try Build.run(root: root, target: buildTarget, release: release,
                          lowMemory: lowMemory, jobs: jobs)
        } catch let error as Build.BuildError {
            throw ValidationError(error.description)
        }
    }
}

// MARK: - verify

struct VerifyCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "verify",
        abstract: "Run lint, contract tests, and visual snapshot verification"
    )

    @Option(name: .long, help: "Stage to run: all|contracts|snapshots")
    var mode: String = "all"

    @Flag(name: .long, help: "Bless current snapshots as new goldens")
    var updateSnapshots: Bool = false

    @Flag(name: .long, help: "Capture snapshots without comparing to goldens")
    var captureOnly: Bool = false

    @Flag(name: .long, help: "Low-memory mode")
    var lowMemory: Bool = false

    @Option(name: .shortAndLong, help: "Job count")
    var jobs: Int?

    @Option(name: .long, help: "Comma-separated platforms to verify")
    var platforms: String?

    func run() throws {
        let root = try RootLocator.require()
        var options = Verify.Options()
        switch mode.lowercased() {
        case "all": options.contracts = true; options.snapshots = true
        case "contracts": options.contracts = true; options.snapshots = false
        case "snapshots": options.contracts = false; options.snapshots = true
        default: throw ValidationError("unknown --mode '\(mode)' — expected all|contracts|snapshots")
        }
        options.updateSnapshots = updateSnapshots
        options.captureOnly = captureOnly
        options.lowMemory = lowMemory
        options.jobs = jobs
        if let platforms {
            let parsed = Set(platforms.split(separator: ",").compactMap {
                ProjectConfig.Platform(rawValue: $0.trimmingCharacters(in: .whitespaces).lowercased())
            })
            guard !parsed.isEmpty else {
                throw ValidationError("invalid --platforms value: \(platforms)")
            }
            options.platforms = parsed
        }

        let report = try Verify.run(root: root, options: options)
        print(Verify.render(report))
        if !report.ok { throw ExitCode(1) }
    }
}
