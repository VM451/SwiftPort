import Foundation

/// The UI-facing phase of the task list. Every native UI must render all
/// four cases — that is the contract `swiftport verify --contracts` checks.
public enum TaskPhase: String, Sendable, Codable, CaseIterable, SwiftPortExported {
    case loading
    case empty
    case loaded
    case error
}

/// Immutable snapshot of everything a native UI needs to render one frame.
/// Platforms observe/poll this — never reach into the store directly.
public struct TaskListSnapshot: Sendable, Codable, Equatable, SwiftPortExported {
    public var phase: TaskPhase
    public var tasks: [TaskItem]
    public var errorMessage: String?

    public init(phase: TaskPhase, tasks: [TaskItem] = [], errorMessage: String? = nil) {
        self.phase = phase
        self.tasks = tasks
        self.errorMessage = errorMessage
    }
}
