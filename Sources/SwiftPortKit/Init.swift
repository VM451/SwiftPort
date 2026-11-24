import Foundation

/// `swiftport init` implementation: render template, write config, optional git init.
public enum Init {
    public struct Options: Sendable {
        public var path: URL
        public var platforms: Set<ProjectConfig.Platform>
        public var bundleIDPrefix: String
        public var git: Bool

        public init(path: URL, platforms: Set<ProjectConfig.Platform>,
                    bundleIDPrefix: String, git: Bool) {
            self.path = path
            self.platforms = platforms
            self.bundleIDPrefix = bundleIDPrefix
            self.git = git
        }
    }

    public struct Result: Sendable {
        public var root: URL
        public var config: ProjectConfig
        public var gitInitialized: Bool
        public var notes: [String]
    }

    public enum InitError: Error, CustomStringConvertible {
        case invalidName(String)
        case destinationExists(String)

        public var description: String {
            switch self {
            case .invalidName(let n): return Template.TemplateError.invalidAppName(n).description
            case .destinationExists(let p): return "destination already exists: \(p)"
            }
        }
    }

    @discardableResult
    public static func run(appName: String, options: Options) throws -> Result {
        guard Template.validateAppName(appName) else {
            throw InitError.invalidName(appName)
        }
        let fm = FileManager.default
        let dest = options.path.standardizedFileURL
        // If path exists but is empty-ish (no swiftport.toml), still allow —
        // render() itself rejects when swiftport.toml exists.
        if fm.fileExists(atPath: ProjectConfig.url(in: dest).path) {
            throw InitError.destinationExists(dest.path)
        }

        _ = try Template.render(
            appName: appName,
            bundleIDPrefix: options.bundleIDPrefix,
            to: dest
        )

        // Apply the user's platform selection into swiftport.toml.
        var config = try ProjectConfig.load(from: dest)
        config.platforms = options.platforms
        try config.write(to: dest)

        var notes: [String] = []
        if options.platforms.contains(.android) {
            notes.append("android: Compose app + Kotlin/JNI bridge generated — build "
                + "libswiftportcore.so per ABI with the Swift Android SDK "
                + "(see Bridges/AndroidJNI/README.md)")
        }
        if options.platforms.contains(.windows) {
            notes.append("windows: WinUI 3 + xunit + C# P/Invoke bridge generated — "
                + "build AppCoreCABI.dll on Windows (see Bridges/WindowsABI/README.md)")
        }

        // Emit bridge bindings for platforms that consume generated glue.
        // (Apple needs none; Linux links AppCore via SwiftPM directly.)
        for platform in [ProjectConfig.Platform.android, .windows]
        where options.platforms.contains(platform) {
            do {
                if platform == .android {
                    _ = try BridgeGen.generateAndroid(root: dest, config: config)
                } else {
                    _ = try BridgeGen.generateWindows(root: dest, config: config)
                }
            } catch {
                notes.append("\(platform.rawValue): bridge generation failed: \(error)")
            }
        }

        var gitInitialized = false
        if options.git {
            if let result = try? Shell.run("git", arguments: ["init"], currentDirectory: dest),
               result.succeeded {
                gitInitialized = true
            } else {
                notes.append("git init skipped (git unavailable or failed)")
            }
        }

        // Regenerate the Apple Xcode project when xcodegen is available so the
        // project opens immediately in Xcode.
        if options.platforms.contains(.apple), Shell.which("xcodegen") != nil {
            let appleDir = dest.appendingPathComponent("Apps/Apple")
            if Sync.runXcodegen(in: appleDir) {
                notes.append("generated Apps/Apple Xcode project via xcodegen")
            }
        }

        return Result(root: dest, config: config, gitInitialized: gitInitialized, notes: notes)
    }

    public static func render(_ result: Result) -> String {
        var lines = [
            "Created \(result.config.name) at \(result.root.path)",
            "  platforms: \(result.config.platforms.map(\.rawValue).sorted().joined(separator: ", "))",
            result.gitInitialized ? "  git repository initialized" : "  (no git repo — run `git init` later)",
        ]
        for note in result.notes { lines.append("  note: \(note)") }
        lines.append("")
        lines.append("Next steps:")
        lines.append("  cd \(result.root.path)")
        lines.append("  swiftport doctor     # verify toolchain")
        lines.append("  swiftport verify     # lint + contract tests")
        lines.append("  open Apps/Apple/\(Template.Tokens(appName: result.config.name, bundleIDPrefix: result.config.bundleIDPrefix).appModule).xcodeproj   # if generated")
        return lines.joined(separator: "\n")
    }
}
