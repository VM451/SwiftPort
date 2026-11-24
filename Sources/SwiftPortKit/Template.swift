import Foundation

/// Locates and renders the embedded project template.
public enum Template {
    /// Token substitution values applied to every text file in the template.
    public struct Tokens: Sendable {
        public var appName: String
        public var appModule: String
        public var appSlug: String
        public var bundleID: String
        public var bundleIDPrefix: String

        public init(appName: String, bundleIDPrefix: String) {
            self.appName = appName
            self.bundleIDPrefix = bundleIDPrefix
            self.appModule = Self.sanitizeModuleName(appName)
            self.appSlug = appName.lowercased().filter { $0.isLetter || $0.isNumber }
            self.bundleID = "\(bundleIDPrefix).\(appSlug)"
        }

        /// File-name-safe module identifier (letters/digits/underscore).
        static func sanitizeModuleName(_ name: String) -> String {
            var result = ""
            for (index, scalar) in name.unicodeScalars.enumerated() {
                if CharacterSet.alphanumerics.contains(scalar) {
                    result.unicodeScalars.append(scalar)
                } else if index > 0 {
                    result.append("_")
                }
            }
            if result.first?.isNumber == true { result = "App" + result }
            return result.isEmpty ? "App" : result
        }

        public var replacements: [String: String] {
            [
                "__APP_NAME__": appName,
                "__APP_MODULE__": appModule,
                "__APP_SLUG__": appSlug,
                "__BUNDLE_ID__": bundleID,
                "__BUNDLE_ID_PATH__": bundleID.replacingOccurrences(of: ".", with: "/"),
                "__BUNDLE_ID_PREFIX__": bundleIDPrefix,
            ]
        }
    }

    public enum TemplateError: Error, CustomStringConvertible {
        case templateMissing
        case destinationExists(String)
        case invalidAppName(String)

        public var description: String {
            switch self {
            case .templateMissing:
                return "embedded template not found — reinstall swiftport"
            case .destinationExists(let path):
                return "destination already exists: \(path)"
            case .invalidAppName(let name):
                return "invalid app name `\(name)` — use letters, digits, spaces, dash or underscore"
            }
        }
    }

    /// Validates an app name supplied to `swiftport init`.
    public static func validateAppName(_ name: String) -> Bool {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))
            .union(.whitespaces)
        return !name.isEmpty
            && name.unicodeScalars.allSatisfy { allowed.contains($0) }
            && name.rangeOfCharacter(from: .newlines) == nil
    }

    /// URL of the bundled template root (`Templates/App` inside the resource bundle).
    public static func templateRoot(bundle: Bundle? = nil) throws -> URL {
        let bundle = bundle ?? .module
        guard let url = (bundle.url(
            forResource: "App",
            withExtension: nil,
            subdirectory: "Templates"
        ) ?? bundle.url(forResource: "App", withExtension: nil)) else {
            throw TemplateError.templateMissing
        }
        return url
    }

    /// Renders the template into `destination`, substituting tokens.
    /// Fails if `destination` already contains a `swiftport.toml`.
    @discardableResult
    public static func render(
        appName: String,
        bundleIDPrefix: String,
        to destination: URL,
        bundle: Bundle? = nil
    ) throws -> URL {
        guard validateAppName(appName) else {
            throw TemplateError.invalidAppName(appName)
        }
        let fm = FileManager.default
        let configURL = ProjectConfig.url(in: destination)
        if fm.fileExists(atPath: configURL.path) {
            throw TemplateError.destinationExists(destination.path)
        }

        let tokens = Tokens(appName: appName, bundleIDPrefix: bundleIDPrefix)
        let source = try templateRoot(bundle: bundle)
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        try copyTree(from: source, to: destination, tokens: tokens.replacements)
        return destination
    }

    // MARK: - Tree copy with token substitution

    private static func copyTree(from source: URL, to dest: URL, tokens: [String: String]) throws {
        try copyNode(at: source, to: dest, tokens: tokens)
    }

    private static func copyNode(at src: URL, to dst: URL, tokens: [String: String]) throws {
        let fm = FileManager.default
        // Tokens apply to path components as well as file contents.
        var renderedName = dst.lastPathComponent
        for (token, value) in tokens {
            renderedName = renderedName.replacingOccurrences(of: token, with: value)
        }
        let dst = renderedName == dst.lastPathComponent
            ? dst
            : dst.deletingLastPathComponent().appendingPathComponent(renderedName)

        let values = try src.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey])
        if values.isDirectory == true {
            try fm.createDirectory(at: dst, withIntermediateDirectories: true)
            let children = try fm.contentsOfDirectory(
                at: src,
                includingPropertiesForKeys: nil,
                options: []
            )
            for child in children {
                try copyNode(at: child, to: dst.appendingPathComponent(child.lastPathComponent), tokens: tokens)
            }
        } else if values.isRegularFile == true {
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let text = try? String(contentsOf: src, encoding: .utf8) {
                var rendered = text
                for (token, value) in tokens {
                    rendered = rendered.replacingOccurrences(of: token, with: value)
                }
                try rendered.write(to: dst, atomically: true, encoding: .utf8)
            } else {
                try fm.copyItem(at: src, to: dst)
            }
        }
    }
}
