import Foundation
import Testing
@testable import AppCore

@Suite("TaskStore")
struct StoreTests {

    @Test("load transitions empty store to .empty")
    func emptyLoad() async {
        let store = TaskStore(latency: .zero)
        await store.load()
        let snap = await store.snapshot()
        #expect(snap.phase == .empty)
        #expect(snap.tasks.isEmpty)
    }

    @Test("load transitions seeded store to .loaded")
    func loadedLoad() async {
        let store = TaskStore(tasks: [TaskItem(title: "Write spec")], latency: .zero)
        await store.load()
        let snap = await store.snapshot()
        #expect(snap.phase == .loaded)
        #expect(snap.tasks.count == 1)
    }

    @Test("failNextLoad produces .error with message")
    func errorLoad() async {
        let store = TaskStore(latency: .zero, failNextLoad: true)
        await store.load()
        let snap = await store.snapshot()
        #expect(snap.phase == .error)
        #expect(snap.errorMessage != nil)
    }

    @Test("addTask appends and flips phase to loaded")
    func addTask() async {
        let store = TaskStore(latency: .zero)
        await store.addTask(title: "First")
        let snap = await store.snapshot()
        #expect(snap.phase == .loaded)
        #expect(snap.tasks.first?.title == "First")
    }

    @Test("toggle and delete keep snapshot consistent")
    func mutations() async {
        let store = TaskStore(latency: .zero)
        let task = await store.addTask(title: "Toggle me")
        await store.toggleCompleted(task.id)
        var snap = await store.snapshot()
        #expect(snap.tasks[0].isCompleted == true)

        await store.delete(task.id)
        snap = await store.snapshot()
        #expect(snap.phase == .empty)
    }

    @Test("fixture snapshot maps contract phase verbatim")
    func fixtureMapping() {
        let scenario = ContractScenario(
            id: "error",
            phase: "error",
            tasks: [],
            errorMessage: "boom"
        )
        let snap = TaskStore.fixtureSnapshot(for: scenario)
        #expect(snap.phase == .error)
        #expect(snap.errorMessage == "boom")
    }

    @Test("ContractScenario decodes a fixture")
    func decodeFixture() throws {
        let json = """
        {"id":"empty","phase":"empty","tasks":[],"errorMessage":null}
        """
        let scenario = try JSONDecoder().decode(
            ContractScenario.self, from: Data(json.utf8)
        )
        #expect(scenario.id == "empty")
        #expect(scenario.phase == "empty")
    }
}
