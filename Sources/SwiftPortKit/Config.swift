import Foundation

/// A parsed `swiftport.toml` project configuration.
public struct ProjectConfig: Sendable, Equatable {
    public enum Platform: String, Sendable, CaseIterable, Codable {
        case apple, android, windows, linux
    }

    public struct Verify: Sendable, Equatable {
        /// Maximum fraction of differing pixels allowed in snapshot comparisons.
        public var snapshotTolerance: Double = 0.001
        /// Viewport matrix entries rendered per contract scenario.
        public var themes: [String] = ["light", "dark"]
    }

    public var name: String = ""
    public var bundleIDPrefix: String = "com.example"
    public var platforms: Set<Platform> = [.apple]
    public var verify = Verify()

    public static let fileName = "swiftport.toml"

    public static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName)
    }

    public static func load(from root: URL) throws -> ProjectConfig {
        let url = Self.url(in: root)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ConfigError.missing(url.path)
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parse(text)
    }

    public func write(to root: URL) throws {
        try Self.serialize(self).write(
            to: Self.url(in: root),
            atomically: true,
            encoding: .utf8
        )
    }

    // MARK: - Errors

    public enum ConfigError: Error, CustomStringConvertible {
        case missing(String)
        case parse(String)

        public var description: String {
            switch self {
            case .missing(let path): return "no swiftport.toml at \(path)"
            case .parse(let detail): return "swiftport.toml: \(detail)"
            }
        }
    }

    // MARK: - Parser (subset of TOML covering the schema we emit)

    /// Parses the subset of TOML produced by `serialize`. Supports:
    /// `[section]` headers, `key = "string"`, `key = 123`, `key = 1.5`,
    /// `key = true|false`, `key = ["a", "b"]`, and `#` comments.
    public static func parse(_ text: String) throws -> ProjectConfig {
        var config = ProjectConfig()
        var section = ""

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let lineNumber = index + 1
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if let hash = line.firstIndex(of: "#") {
                line = String(line[..<hash]).trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty { continue }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }

            guard let eq = line.firstIndex(of: "=") else {
                throw ConfigError.parse("line \(lineNumber): expected key = value")
            }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: eq)...]).trimmingCharacters(in: .whitespaces)

            do {
                switch (section, key) {
                case ("project", "name"):
                    config.name = try string(value)
                case ("project", "bundle_id_prefix"):
                    config.bundleIDPrefix = try string(value)
                case ("targets", "platforms"):
                    config.platforms = Set(try stringArray(value).compactMap(Platform.init(rawValue:)))
                case ("verify", "snapshot_tolerance"):
                    config.verify.snapshotTolerance = try double(value)
                case ("verify", "themes"):
                    config.verify.themes = try stringArray(value)
                default:
                    break // forward-compatible: ignore unknown keys
                }
            } catch {
                throw ConfigError.parse("line \(lineNumber): \(error)")
            }
        }
        return config
    }

    public static func serialize(_ config: ProjectConfig) -> String {
        let out = """
        # SwiftPort project configuration
        # Docs: https://github.com/nitiptc/swiftport

        [project]
        name = "\(config.name)"
        bundle_id_prefix = "\(config.bundleIDPrefix)"

        [targets]
        platforms = [\(config.platforms.map { "\"\($0.rawValue)\"" }.sorted().joined(separator: ", "))]

        [verify]
        snapshot_tolerance = \(config.verify.snapshotTolerance)
        themes = [\(config.verify.themes.map { "\"\($0)\"" }.joined(separator: ", "))]

        """
        return out
    }

    // MARK: - Scalar helpers

    private static func unquote(_ value: String) throws -> String {
        guard value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") else {
            throw ConfigError.parse("expected quoted string, got `\(value)`")
        }
        let inner = value.dropFirst().dropLast()
        // Minimal unescaping for the strings we emit.
        return inner
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\\\", with: "\\")
    }

    private static func string(_ value: String) throws -> String {
        try unquote(value)
    }

    private static func stringArray(_ value: String) throws -> [String] {
        guard value.hasPrefix("["), value.hasSuffix("]") else {
            throw ConfigError.parse("expected array, got `\(value)`")
        }
        let inner = value.dropFirst().dropLast()
        if inner.trimmingCharacters(in: .whitespaces).isEmpty { return [] }
        return try inner
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { try unquote(String($0).trimmingCharacters(in: .whitespaces)) }
    }

    private static func double(_ value: String) throws -> Double {
        guard let d = Double(value) else {
            throw ConfigError.parse("expected number, got `\(value)`")
        }
        return d
    }
}
