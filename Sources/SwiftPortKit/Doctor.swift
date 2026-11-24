import Foundation

/// `swiftport doctor` — audits the host toolchain for the platforms enabled
/// in `swiftport.toml` and reports actionable fixes for anything missing.
public enum Doctor {
    public enum Status: String, Sendable {
        case ok, warn, fail, skip
    }

    public struct Check: Sendable {
        public var name: String
        public var status: Status
        public var detail: String
        public var fix: String?
    }

    public struct Report: Sendable {
        public var checks: [Check]
        public var root: URL

        public var failed: [Check] { checks.filter { $0.status == .fail } }
        public var warnings: [Check] { checks.filter { $0.status == .warn } }
    }

    public static func run(root: URL, config: ProjectConfig? = nil) -> Report {
        let config = try? config ?? ProjectConfig.load(from: root)
        let platforms = config?.platforms ?? [.apple]
        var checks: [Check] = []

        // --- Always required -------------------------------------------------
        checks.append(swiftCheck())
        checks.append(toolCheck(name: "git", fix: "Install git: https://git-scm.com/downloads"))

        // --- Apple -----------------------------------------------------------
        if platforms.contains(.apple) {
            checks.append(xcodeCheck())
            checks.append(toolCheck(
                name: "xcodegen",
                fix: "brew install xcodegen  (or: mint install yonaskolb/XcodeGen)"
            ))
        }

        // --- Linux -----------------------------------------------------------
        if platforms.contains(.linux) {
            checks.append(contentsOf: gtkChecks())
        }

        // --- Android / Windows (later phases) --------------------------------
        for platform in [ProjectConfig.Platform.android, .windows] where platforms.contains(platform) {
            checks.append(Check(
                name: "\(platform.rawValue) toolchain",
                status: .skip,
                detail: "bridge generation for \(platform.rawValue) lands in a later phase — no checks yet",
                fix: nil
            ))
        }

        return Report(checks: checks, root: root)
    }

    // MARK: - Individual checks

    static func swiftCheck() -> Check {
        guard let path = Shell.which("swift") else {
            return Check(name: "swift", status: .fail,
                         detail: "Swift toolchain not found",
                         fix: "Install from https://swift.org/download or via `xcode-select --install`")
        }
        guard let result = try? Shell.run("swift", arguments: ["--version"]),
              result.succeeded else {
            return Check(name: "swift", status: .fail,
                         detail: "swift found at \(path) but `swift --version` failed",
                         fix: "Reinstall the Swift toolchain")
        }
        let first = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        // e.g. "swift-driver version: 1.168.6 Apple Swift version 6.4 ..."
        if let range = first.range(of: "Swift version ") {
            let versionText = first[range.upperBound...]
                .prefix { $0.isNumber || $0 == "." }
            if let major = versionText.split(separator: ".").first.flatMap({ Int($0) }), major >= 6 {
                return Check(name: "swift", status: .ok,
                             detail: "\(path) — \(versionText)", fix: nil)
            }
            return Check(name: "swift", status: .fail,
                         detail: "Swift \(versionText) found — SwiftPort requires 6.0+",
                         fix: "Upgrade: https://swift.org/download")
        }
        return Check(name: "swift", status: .warn,
                     detail: "\(path) — could not parse version from: \(first)", fix: nil)
    }

    static func toolCheck(name: String, fix: String?) -> Check {
        if let path = Shell.which(name) {
            return Check(name: name, status: .ok, detail: path, fix: nil)
        }
        return Check(name: name, status: .fail,
                     detail: "not found on PATH", fix: fix)
    }

    static func xcodeCheck() -> Check {
        #if os(macOS)
        // Prefer a full Xcode over Command Line Tools when probing.
        var environment: [String: String] = [:]
        let xcodeApp = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer")
        if FileManager.default.fileExists(atPath: xcodeApp.path),
           ProcessInfo.processInfo.environment["DEVELOPER_DIR"] == nil {
            environment["DEVELOPER_DIR"] = xcodeApp.path
        }
        guard let result = try? Shell.run("xcodebuild", arguments: ["-version"], environment: environment),
              result.succeeded else {
            let selected = (try? Shell.run("xcode-select", arguments: ["-p"]))?.stdout
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"
            return Check(
                name: "xcodebuild",
                status: .fail,
                detail: "xcodebuild unavailable (active developer dir: \(selected))",
                fix: "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
            )
        }
        let versionLine = result.stdout.split(separator: "\n").first.map(String.init) ?? ""
        return Check(name: "xcodebuild", status: .ok, detail: versionLine, fix: nil)
        #else
        return Check(name: "xcodebuild", status: .skip,
                     detail: "not applicable on this host", fix: nil)
        #endif
    }

    /// GTK4 + libadwaita presence via pkg-config.
    static func gtkChecks() -> [Check] {
        guard Shell.which("pkg-config") != nil else {
            let isLinux = ProcessInfo.processInfo.environment["XDG_CURRENT_DESKTOP"] != nil
                || FileManager.default.fileExists(atPath: "/etc/os-release")
            return [Check(
                name: "gtk4/libadwaita",
                status: isLinux ? .fail : .warn,
                detail: "pkg-config not found — cannot detect GTK4/libadwaita",
                fix: isLinux
                    ? "sudo apt install pkg-config libgtk-4-dev libadwaita-1-dev (or distro equivalent)"
                    : "brew install pkgconf gtk4 libadwaita  (optional on macOS — CI builds Linux)"
            )]
        }

        func pkgCheck(_ name: String, minimum: String?, fix: String) -> Check {
            guard let result = try? Shell.run("pkg-config", arguments: ["--modversion", name]),
                  result.succeeded else {
                return Check(name: name, status: .warn,
                             detail: "not found via pkg-config",
                             fix: fix)
            }
            let version = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return Check(name: name, status: .ok, detail: version, fix: nil)
        }

        let gtkFix = "sudo apt install libgtk-4-dev (or: brew install gtk4)"
        let adwFix = "sudo apt install libadwaita-1-dev (or: brew install libadwaita)"
        return [
            pkgCheck("gtk4", minimum: "4.0", fix: gtkFix),
            pkgCheck("libadwaita-1", minimum: "1.4", fix: adwFix),
        ]
    }

    /// Human-readable rendering of a report.
    public static func render(_ report: Report) -> String {
        var lines: [String] = ["SwiftPort doctor — \(report.root.path)", ""]
        let width = report.checks.map(\.name.count).max() ?? 10
        for check in report.checks {
            let label: String
            switch check.status {
            case .ok: label = "ok  "
            case .warn: label = "warn"
            case .fail: label = "FAIL"
            case .skip: label = "skip"
            }
            let name = check.name.padding(toLength: width, withPad: " ", startingAt: 0)
            lines.append("  [\(label)] \(name)  \(check.detail)")
            if let fix = check.fix {
                lines.append("         fix: \(fix)")
            }
        }
        lines.append("")
        if report.failed.isEmpty {
            lines.append(report.warnings.isEmpty
                ? "All checks passed."
                : "\(report.warnings.count) warning(s) — see above.")
        } else {
            lines.append("\(report.failed.count) required check(s) failed.")
        }
        return lines.joined(separator: "\n")
    }
}
