import Combine
import Foundation
import AppCore

/// View model bridging the `TaskStore` actor to SwiftUI's `ObservableObject`.
/// The UI only ever reads `snapshot` — a plain value type — so rendering is
/// a pure function of Core state.
@MainActor
public final class TaskListViewModel: ObservableObject {
    @Published public private(set) var snapshot: TaskListSnapshot
    private let store: TaskStore

    public init(store: TaskStore = TaskStore(), autoLoad: Bool = true) {
        self.store = store
        self.snapshot = TaskListSnapshot(phase: .loading)
        if autoLoad {
            Task { await reload() }
        }
    }

    /// Deterministic initializer for snapshot tests and contract fixtures.
    public convenience init(fixture scenario: ContractScenario) {
        self.init(
            store: TaskStore(tasks: scenario.tasks.map(\.taskItem)),
            autoLoad: false
        )
        self.snapshot = TaskStore.fixtureSnapshot(for: scenario)
    }

    public func reload() async {
        await store.load()
        snapshot = await store.snapshot()
    }

    public func addTask(title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        _ = await store.addTask(title: trimmed)
        snapshot = await store.snapshot()
    }

    public func toggle(_ id: UUID) async {
        await store.toggleCompleted(id)
        snapshot = await store.snapshot()
    }

    public func delete(_ id: UUID) async {
        await store.delete(id)
        snapshot = await store.snapshot()
    }
}
