import Foundation
import Testing
import AppCore

/// Contract tests on Linux: same shared fixtures as every other platform.
/// Walks up from this file to the monorepo root (contains swiftport.toml).
@Suite("UI contracts")
struct ContractTests {

    static func repoRoot() -> URL {
        var url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while url.path != "/" {
            if FileManager.default.fileExists(
                atPath: url.appendingPathComponent("swiftport.toml").path
            ) {
                return url
            }
            url.deleteLastPathComponent()
        }
        fatalError("swiftport.toml not found above \(#filePath)")
    }

    @Test("every contract fixture produces the declared UI state")
    func fixturesMatchSnapshots() throws {
        let dir = Self.repoRoot().appendingPathComponent("Verification/Contracts")
        let fixtures = try ContractScenario.loadAll(from: dir)
        try #require(!fixtures.isEmpty, "no contract fixtures found")

        for fixture in fixtures {
            let snapshot = TaskStore.fixtureSnapshot(for: fixture)
            #expect(
                snapshot.phase.rawValue == fixture.phase,
                "\(fixture.id): expected \(fixture.phase), got \(snapshot.phase.rawValue)"
            )
            #expect(snapshot.tasks.count == fixture.tasks.count)
            if fixture.phase == "error" {
                #expect(snapshot.errorMessage != nil)
            }
        }
    }
}
