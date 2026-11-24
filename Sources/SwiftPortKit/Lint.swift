import Foundation

/// FR-2 guardrail: ensures `Core/` stays platform-independent by rejecting
/// imports of Apple-only (or otherwise platform-locked) frameworks.
public enum Lint {
    /// Modules that must never be imported unconditionally from `Core/`.
    public static let forbiddenModules: Set<String> = [
        "SwiftUI", "UIKit", "AppKit", "Combine",
        "WatchKit", "WebKit", "CoreData", "SwiftData",
        "WidgetKit", "AppIntents", "CloudKit",
        "ARKit", "AVFoundation", "MapKit", "StoreKit",
        "CoreLocation", "HealthKit", "HomeKit", "PassKit",
        "Vision", "PDFKit", "QuickLook", "ScreenCaptureKit",
    ]

    public struct Violation: Sendable, Equatable {
        public var file: String
        public var line: Int
        public var module: String
        public var text: String
    }

    public struct Report: Sendable {
        public var violations: [Violation]
        public var scannedFiles: Int

        public var isClean: Bool { violations.isEmpty }
    }

    /// Scans every `.swift` file under `Core/Sources`.
    public static func run(root: URL) throws -> Report {
        let coreSources = root.appendingPathComponent("Core/Sources")
        var files: [URL] = []
        if FileManager.default.fileExists(atPath: coreSources.path) {
            let enumerator = FileManager.default.enumerator(
                at: coreSources,
                includingPropertiesForKeys: nil
            )
            while let url = enumerator?.nextObject() as? URL {
                if url.pathExtension == "swift" { files.append(url) }
            }
        }
        files.sort { $0.path < $1.path }

        var violations: [Violation] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            violations.append(contentsOf: scan(text: text, file: file.lastPathComponent))
        }
        return Report(violations: violations, scannedFiles: files.count)
    }

    /// Scans source text, honoring `#if canImport(<module>)` escape hatches:
    /// an import inside such a conditional block is permitted.
    public static func scan(text: String, file: String) -> [Violation] {
        // Lines like `#if canImport(SwiftUI)` open an allowed region for that module.
        var conditionStack: [String?] = [] // nil = non-canImport condition
        var violations: [Violation] = []

        let importRegex = try! NSRegularExpression(
            pattern: #"^\s*(?:@\w+(?:\([^)]*\))?\s+)*import\s+(?:(?:typealias|struct|class|enum|protocol|let|var|func)\s+)?([A-Za-z_][A-Za-z0-9_]*)"#
        )
        let canImportRegex = try! NSRegularExpression(
            pattern: #"^\s*#if\s+canImport\(\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
        )
        let anyIfRegex = try! NSRegularExpression(pattern: #"^\s*#if\b"#)

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine
            let nsLine = line as NSString

            if nsLine.range(of: #"^\s*#endif\b"#, options: .regularExpression).location != NSNotFound {
                if !conditionStack.isEmpty { conditionStack.removeLast() }
                continue
            }
            if nsLine.range(of: #"^\s*#else(if)?\b"#, options: .regularExpression).location != NSNotFound {
                // Conservatively keep the enclosing condition; a `#else` branch of
                // `canImport` technically un-guards imports, but the common pattern
                // (`#if canImport(X) / real code / #else / fallback / #endif`) keeps
                // fallback imports equally platform-safe. Accept the edge case.
                continue
            }
            if let match = canImportRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)),
               match.numberOfRanges > 1 {
                let module = nsLine.substring(with: match.range(at: 1))
                conditionStack.append(module)
                continue
            }
            if anyIfRegex.firstMatch(in: line, range: NSRange(location: 0, length: nsLine.length)) != nil {
                conditionStack.append(nil)
                continue
            }

            guard let match = importRegex.firstMatch(
                in: line, range: NSRange(location: 0, length: nsLine.length)
            ), match.numberOfRanges > 1 else { continue }

            let module = nsLine.substring(with: match.range(at: 1))
            guard forbiddenModules.contains(module) else { continue }

            // Allowed when enclosed by `#if canImport(<same module>)`.
            if conditionStack.contains(module) { continue }

            violations.append(Violation(
                file: file,
                line: index + 1,
                module: module,
                text: line.trimmingCharacters(in: .whitespaces)
            ))
        }
        return violations
    }

    public static func render(_ report: Report) -> String {
        if report.isClean {
            return "Core lint clean — \(report.scannedFiles) file(s) scanned, no forbidden imports."
        }
        var lines = ["Core lint FAILED — \(report.violations.count) forbidden import(s):", ""]
        for v in report.violations {
            lines.append("  \(v.file):\(v.line): \(v.text)")
            lines.append("    `\(v.module)` is platform-locked — Core/ must stay platform-independent.")
            lines.append("    Move UI code to Apps/, or guard with `#if canImport(\(v.module))`.")
        }
        return lines.joined(separator: "\n")
    }
}
