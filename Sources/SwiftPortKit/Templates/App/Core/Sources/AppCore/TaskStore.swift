import Foundation

/// Actor-isolated task store — the single source of truth for task data.
/// Every platform UI talks to this through `snapshot()` so the UI layer
/// stays a pure function of `TaskListSnapshot`.
public actor TaskStore {

    /// How long `load()` pretends to fetch. Deterministic fixtures bypass it.
    public private(set) var tasks: [TaskItem]
    public private(set) var phase: TaskPhase
    public private(set) var errorMessage: String?

    private let latency: Duration
    private var failNextLoad: Bool

    public init(
        tasks: [TaskItem] = [],
        latency: Duration = .milliseconds(300),
        failNextLoad: Bool = false
    ) {
        self.tasks = tasks
        self.phase = tasks.isEmpty ? .empty : .loaded
        self.latency = latency
        self.failNextLoad = failNextLoad
    }

    // MARK: - Loading

    /// Simulates an async fetch. Always ends in `.loaded`, `.empty`, or `.error`.
    public func load() async {
        phase = .loading
        errorMessage = nil
        try? await Task.sleep(for: latency)
        if failNextLoad {
            failNextLoad = false
            phase = .error
            errorMessage = "Couldn't load tasks. Check your connection and try again."
            return
        }
        phase = tasks.isEmpty ? .empty : .loaded
    }

    // MARK: - Mutations

    @discardableResult
    public func addTask(title: String, notes: String = "", priority: TaskPriority = .medium) -> TaskItem {
        let task = TaskItem(title: title, notes: notes, priority: priority)
        tasks.append(task)
        recomputePhase()
        return task
    }

    public func toggleCompleted(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].isCompleted.toggle()
    }

    public func delete(_ id: UUID) {
        tasks.removeAll { $0.id == id }
        recomputePhase()
    }

    // MARK: - Snapshot

    public func snapshot() -> TaskListSnapshot {
        TaskListSnapshot(phase: phase, tasks: tasks, errorMessage: errorMessage)
    }

    /// Deterministic snapshot for a contract fixture — bypasses `load()` so
    /// every platform renders identical state without timing dependencies.
    public static func fixtureSnapshot(for scenario: ContractScenario) -> TaskListSnapshot {
        let phase = TaskPhase(rawValue: scenario.phase) ?? .loaded
        return TaskListSnapshot(
            phase: phase,
            tasks: scenario.tasks.map(\.taskItem),
            errorMessage: scenario.errorMessage
        )
    }

    private func recomputePhase() {
        if phase != .error { phase = tasks.isEmpty ? .empty : .loaded }
    }
}
