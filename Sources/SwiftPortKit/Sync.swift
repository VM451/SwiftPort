import Foundation

/// `swiftport sync` — discovers the bridge surface (`SwiftPortExported`
/// conformances in `Core/`) and regenerates per-platform glue that is cheap
/// to produce deterministically. Heavy codegen (JNI, P/Invoke) lands in
/// later phases; today sync covers Apple (Xcode project regen) and reports
/// readiness for every selected platform.
public enum Sync {
    public struct ExportedType: Sendable, Equatable {
        public var name: String
        public var kind: String
        public var file: String
    }

    public struct Report: Sendable {
        public var exports: [ExportedType]
        public var actions: [String]
        public var skippedPlatforms: [ProjectConfig.Platform]
    }

    /// Scans `Core/Sources` for types conforming to `SwiftPortExported`.
    public static func scanExports(root: URL) throws -> [ExportedType] {
        let coreSources = root.appendingPathComponent("Core/Sources")
        var found: [ExportedType] = []
        guard FileManager.default.fileExists(atPath: coreSources.path) else { return [] }

        let enumerator = FileManager.default.enumerator(at: coreSources, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        files.sort { $0.path < $1.path }

        // Matches `struct|class|enum|actor Name ... : ... SwiftPortExported`
        // and `extension Name ... : ... SwiftPortExported`.
        let declRegex = try! NSRegularExpression(
            pattern: #"(?:struct|class|enum|actor)\s+([A-Za-z_][A-Za-z0-9_]*)[^\n{]*:[^\n{]*\bSwiftPortExported\b"#
        )
        let extRegex = try! NSRegularExpression(
            pattern: #"extension\s+([A-Za-z_][A-Za-z0-9_]*)[^\n{]*:[^\n{]*\bSwiftPortExported\b"#
        )
        let kindRegex = try! NSRegularExpression(
            pattern: #"^\s*(?:(?:public|open|final|indirect|package|internal|private|fileprivate)\s+)*(struct|class|enum|actor)\s"#
        )

        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            let ns = text as NSString

            for regex in [declRegex, extRegex] {
                regex.enumerateMatches(
                    in: text,
                    range: NSRange(location: 0, length: ns.length)
                ) { match, _, _ in
                    guard let match, match.numberOfRanges > 1 else { return }
                    let name = ns.substring(with: match.range(at: 1))
                    // Kind: look at the line for a nominal keyword.
                    var kind = "type"
                    if let lineRange = text.range(of: name).map({
                        NSRange($0, in: text)
                    }), let km = kindRegex.firstMatch(in: text, range: lineRange),
                       km.numberOfRanges > 1 {
                        kind = ns.substring(with: km.range(at: 1))
                    }
                    found.append(ExportedType(name: name, kind: kind, file: file.lastPathComponent))
                }
            }
        }

        // Dedupe by name, keep first-seen order.
        var seen = Set<String>()
        return found.filter { seen.insert($0.name).inserted }
    }

    /// Runs the sync: scan exports, regenerate Apple project if needed,
    /// report per-platform bridge status.
    @discardableResult
    public static func run(
        root: URL,
        config: ProjectConfig? = nil,
        jobs: Int? = nil
    ) throws -> Report {
        let config = try config ?? ProjectConfig.load(from: root)
        var actions: [String] = []
        var skipped: [ProjectConfig.Platform] = []

        let exports = try scanExports(root: root)
        actions.append("found \(exports.count) exported type(s) in Core/")

        if config.platforms.contains(.apple) {
            let appleDir = root.appendingPathComponent("Apps/Apple")
            if regenerateXcodeProject(in: appleDir) {
                actions.append("regenerated Apps/Apple Xcode project via xcodegen")
            } else {
                actions.append("Apps/Apple Xcode project up to date")
            }
        }

        if config.platforms.contains(.linux) {
            // Linux consumes AppCore as a local SwiftPM dependency — no
            // generated glue required in Phase 1.
            actions.append("linux: AppCore linked directly via SwiftPM (no bridge codegen)")
        }

        for platform in [ProjectConfig.Platform.android, .windows] where config.platforms.contains(platform) {
            if platform == .android {
                actions.append("android: \(exports.count) export(s) ready for swift-java JNI codegen "
                    + "(requires the Swift Android SDK — see Apps/Android/README.md)")
            } else {
                skipped.append(platform)
                actions.append("\(platform.rawValue): C# contract tests scaffolded; "
                    + "C-ABI/PInvoke codegen pending (Phase 3)")
            }
        }

        return Report(exports: exports, actions: actions, skippedPlatforms: skipped)
    }

    /// Regenerates the Xcode project when `project.yml` is newer than the
    /// `.xcodeproj`, or when the project is missing. Returns true if it ran.
    @discardableResult
    static func regenerateXcodeProject(in appleDir: URL) -> Bool {
        let fm = FileManager.default
        let spec = appleDir.appendingPathComponent("project.yml")
        guard fm.fileExists(atPath: spec.path) else { return false }
        guard let projects = try? fm.contentsOfDirectory(atPath: appleDir.path),
              let projectDir = projects.first(where: { $0.hasSuffix(".xcodeproj") }) else {
            return runXcodegen(in: appleDir)
        }
        let projectURL = appleDir.appendingPathComponent(projectDir)
        let specDate = (try? fm.attributesOfItem(atPath: spec.path)[.modificationDate]) as? Date
        let projDate = (try? fm.attributesOfItem(atPath: projectURL.path)[.modificationDate]) as? Date
        if let specDate, let projDate, specDate <= projDate { return false }
        return runXcodegen(in: appleDir)
    }

    @discardableResult
    static func runXcodegen(in appleDir: URL) -> Bool {
        guard Shell.which("xcodegen") != nil else { return false }
        guard let result = try? Shell.run(
            "xcodegen",
            arguments: ["generate", "--spec", "project.yml"],
            currentDirectory: appleDir
        ), result.succeeded else { return false }
        return true
    }

    public static func render(_ report: Report) -> String {
        var lines = ["SwiftPort sync", ""]
        if report.exports.isEmpty {
            lines.append("  No SwiftPortExported types found in Core/.")
            lines.append("  Mark public API types with `SwiftPortExported` conformance to export them.")
        } else {
            lines.append("  Exported types (\(report.exports.count)):")
            for e in report.exports {
                lines.append("    • \(e.kind) \(e.name)  (\(e.file))")
            }
        }
        lines.append("")
        for action in report.actions { lines.append("  → \(action)") }
        return lines.joined(separator: "\n")
    }
}
