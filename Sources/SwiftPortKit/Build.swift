import Foundation

/// `swiftport build --target <apple|linux> [--release] [--low-memory] [--jobs N]`
public enum Build {
    public enum Target: String, Sendable, CaseIterable {
        case apple, linux, android, windows
    }

    public enum BuildError: Error, CustomStringConvertible {
        case unsupportedOnHost(Target)
        case toolMissing(String, String)
        case commandFailed(String, Int32, String)

        public var description: String {
            switch self {
            case .unsupportedOnHost(let t):
                return "building \(t.rawValue) is not supported on this host OS"
            case .toolMissing(let tool, let fix):
                return "required tool `\(tool)` missing — \(fix)"
            case .commandFailed(let command, let status, let output):
                return "`\(command)` exited \(status)\n\(output)"
            }
        }
    }

    /// Effective job count: explicit jobs wins, then low-memory throttle.
    public static func jobCount(jobs: Int?, lowMemory: Bool) -> Int? {
        if let jobs { return max(1, jobs) }
        return lowMemory ? 2 : nil
    }

    public static func run(
        root: URL,
        target: Target,
        release: Bool,
        lowMemory: Bool,
        jobs: Int? = nil
    ) throws {
        let jobs = jobCount(jobs: jobs, lowMemory: lowMemory)
        switch target {
        case .apple: try buildApple(root: root, release: release, jobs: jobs)
        case .linux: try buildLinux(root: root, release: release, jobs: jobs)
        case .android, .windows:
            throw BuildError.unsupportedOnHost(target)
        }
    }

    // MARK: - Apple

    static func buildApple(root: URL, release: Bool, jobs: Int?) throws {
        #if os(macOS)
        let appleDir = root.appendingPathComponent("Apps/Apple")
        guard FileManager.default.fileExists(atPath: appleDir.path) else {
            throw BuildError.commandFailed("locate Apps/Apple", 1, "directory missing")
        }
        guard Shell.which("xcodegen") != nil else {
            throw BuildError.toolMissing("xcodegen", "brew install xcodegen")
        }
        _ = try Shell.run("xcodegen", arguments: ["generate", "--spec", "project.yml"],
                          currentDirectory: appleDir)

        // Discover the generated project + scheme names.
        let contents = try FileManager.default.contentsOfDirectory(atPath: appleDir.path)
        guard let project = contents.first(where: { $0.hasSuffix(".xcodeproj") }) else {
            throw BuildError.commandFailed("xcodegen", 1, "no .xcodeproj produced")
        }
        let scheme = project.replacingOccurrences(of: ".xcodeproj", with: "")
        let config = release ? "Release" : "Debug"

        var args = [
            "-project", project,
            "-scheme", scheme,
            "-configuration", config,
            "-destination", "platform=macOS",
            "-quiet",
            "build",
        ]
        if let jobs { args += ["-jobs", String(jobs)] }

        // xcodebuild fails under Command Line Tools even when Xcode is
        // installed — point at Xcode's developer dir when it's available.
        var environment: [String: String] = [:]
        if ProcessInfo.processInfo.environment["DEVELOPER_DIR"] == nil {
            let xcode = "/Applications/Xcode.app/Contents/Developer"
            if FileManager.default.fileExists(atPath: xcode) {
                environment["DEVELOPER_DIR"] = xcode
            }
        }

        let result = try Shell.run("xcodebuild", arguments: args,
                                   currentDirectory: appleDir, environment: environment)
        if !result.succeeded {
            throw BuildError.commandFailed("xcodebuild", result.status, result.combined)
        }
        print("Built \(project) (\(config))")
        #else
        throw BuildError.unsupportedOnHost(.apple)
        #endif
    }

    // MARK: - Linux

    static func buildLinux(root: URL, release: Bool, jobs: Int?) throws {
        let linuxDir = root.appendingPathComponent("Apps/Linux")
        guard FileManager.default.fileExists(atPath: linuxDir.path) else {
            throw BuildError.commandFailed("locate Apps/Linux", 1, "directory missing")
        }
        var args = ["build"]
        if release { args.append("-c"); args.append("release") }
        if let jobs { args += ["-j", String(jobs)] }

        let result = try Shell.run("swift", arguments: args, currentDirectory: linuxDir)
        if !result.succeeded {
            throw BuildError.commandFailed("swift build (Apps/Linux)", result.status, result.combined)
        }
        print("Built Apps/Linux (\(release ? "release" : "debug"))")
    }
}
