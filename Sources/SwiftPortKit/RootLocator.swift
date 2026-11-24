import Foundation

/// Locates the SwiftPort project root (directory containing `swiftport.toml`)
/// by walking up from a starting directory.
public enum RootLocator {
    public static func find(from start: URL) -> URL? {
        var current = start.standardizedFileURL
        // If start is a file, begin at its parent.
        if !FileManager.default.fileExists(atPath: current.path) {
            current = current.deletingLastPathComponent()
        }
        var isDirectory: ObjCBool = false
        while FileManager.default.fileExists(atPath: current.path, isDirectory: &isDirectory),
              isDirectory.boolValue {
            if FileManager.default.fileExists(
                atPath: ProjectConfig.url(in: current).path
            ) {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return nil
    }

    /// Finds the root or throws a friendly error.
    public static func require(from start: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)) throws -> URL {
        guard let root = find(from: start) else {
            throw Verify.VerifyError.notInProject
        }
        return root
    }
}
