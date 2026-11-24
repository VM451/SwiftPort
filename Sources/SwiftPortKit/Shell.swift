import Foundation

/// Shells out to external tools, capturing stdout/stderr and exit status.
public enum Shell {
    public struct Result: Sendable {
        public var status: Int32
        public var stdout: String
        public var stderr: String

        public var succeeded: Bool { status == 0 }
        public var combined: String { stdout + stderr }
    }

    /// Errors thrown before a process can even be launched.
    public enum Error: Swift.Error, CustomStringConvertible {
        case launchFailed(String, Swift.Error)

        public var description: String {
            switch self {
            case .launchFailed(let tool, let error):
                return "failed to launch \(tool): \(error.localizedDescription)"
            }
        }
    }

    /// Runs a command and returns its result. Never throws for non-zero exit.
    /// Throws `Error.launchFailed` if the executable cannot be spawned.
    @discardableResult
    public static func run(
        _ executable: String,
        arguments: [String] = [],
        currentDirectory: URL? = nil,
        environment: [String: String] = [:],
        stdin: String? = nil
    ) throws -> Result {
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = resolveExecutable(executable)
        process.arguments = arguments
        if let currentDirectory { process.currentDirectoryURL = currentDirectory }
        var env = ProcessInfo.processInfo.environment
        for (key, value) in environment { env[key] = value }
        process.environment = env
        process.standardOutput = outPipe
        process.standardError = errPipe

        let inPipe: Pipe? = stdin.map { _ in Pipe() }
        process.standardInput = inPipe ?? FileHandle.nullDevice

        // Drain both pipes on background queues so a chatty child can't
        // deadlock on a full pipe buffer.
        final class Box: @unchecked Sendable {
            var data = Data()
        }
        let outBox = Box()
        let errBox = Box()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            outBox.data = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        try process.run()
        if let inPipe, let stdin, let data = stdin.data(using: .utf8) {
            try? inPipe.fileHandleForWriting.write(contentsOf: data)
        }
        try? inPipe?.fileHandleForWriting.close()

        process.waitUntilExit()
        group.wait()

        return Result(
            status: process.terminationStatus,
            stdout: String(decoding: outBox.data, as: UTF8.self),
            stderr: String(decoding: errBox.data, as: UTF8.self)
        )
    }

    /// Resolves `name` to an executable URL: direct paths pass through,
    /// bare names are looked up on PATH (with Windows executable extensions).
    static func resolveExecutable(_ name: String) -> URL {
        if name.contains("/") || name.hasPrefix(".") {
            return URL(fileURLWithPath: name)
        }
        if let path = which(name) { return URL(fileURLWithPath: path) }
        #if os(Windows)
        for ext in [".exe", ".bat", ".cmd"] {
            if let path = which(name + ext) { return URL(fileURLWithPath: path) }
        }
        #endif
        // Unresolvable — return as-is so `run` throws launchFailed.
        return URL(fileURLWithPath: name)
    }

    /// Returns the resolved path of an executable on PATH, or nil.
    public static func which(_ name: String) -> String? {
        #if os(Windows)
        let separator: Character = ";"
        #else
        let separator: Character = ":"
        #endif
        let searchPaths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: separator)
            .map(String.init)
        for dir in searchPaths {
            let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
