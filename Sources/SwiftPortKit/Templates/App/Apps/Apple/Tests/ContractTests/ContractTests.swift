import Foundation
import Testing
import AppCore
import AppUI

/// Contract tests: every fixture in `Verification/Contracts/` must map to a
/// view model whose snapshot matches the declared phase, task count, and
/// error message. This is the logic-level half of `swiftport verify`;
/// pixel-level rendering is covered by `snapshot-runner`.
@Suite("UI contracts")
struct ContractTests {

    /// Walk up from this file to the monorepo root (contains swiftport.toml).
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

    static func scenarios() throws -> [ContractScenario] {
        let dir = repoRoot().appendingPathComponent("Verification/Contracts")
        return try ContractScenario.loadAll(from: dir)
    }

    @Test("every contract fixture produces the declared UI state")
    @MainActor
    func fixturesMatchViewModels() throws {
        let fixtures = try Self.scenarios()
        try #require(!fixtures.isEmpty, "no contract fixtures found")

        for fixture in fixtures {
            let model = TaskListViewModel(fixture: fixture)
            let snapshot = model.snapshot

            #expect(
                snapshot.phase.rawValue == fixture.phase,
                "\(fixture.id): expected phase \(fixture.phase), got \(snapshot.phase.rawValue)"
            )
            #expect(
                snapshot.tasks.count == fixture.tasks.count,
                "\(fixture.id): expected \(fixture.tasks.count) tasks, got \(snapshot.tasks.count)"
            )
            if fixture.phase == "error" {
                #expect(snapshot.errorMessage != nil, "\(fixture.id): error phase needs a message")
            }
            // Every task must carry non-empty content — no silent blank rows.
            for task in snapshot.tasks {
                #expect(!task.title.isEmpty, "\(fixture.id): task with empty title")
            }
        }
    }

    @Test("store mutations flow through to snapshot")
    @MainActor
    func mutationsFlowThrough() async {
        let model = TaskListViewModel(store: TaskStore(latency: .zero))
        await model.reload()
        #expect(model.snapshot.phase == .empty)

        await model.addTask(title: "Ship it")
        #expect(model.snapshot.phase == .loaded)
        #expect(model.snapshot.tasks.count == 1)

        if let id = model.snapshot.tasks.first?.id {
            await model.toggle(id)
            #expect(model.snapshot.tasks[0].isCompleted)
            await model.delete(id)
            #expect(model.snapshot.phase == .empty)
        }
    }
}
