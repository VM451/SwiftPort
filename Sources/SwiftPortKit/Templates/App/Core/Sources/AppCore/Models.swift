import Foundation

/// Priority level for a task. Raw-value enum keeps bridge serialization trivial.
public enum TaskPriority: String, Sendable, Codable, CaseIterable, SwiftPortExported {
    case low, medium, high
}

/// A single task item. `Sendable` + `Codable` so it crosses every bridge
/// (SwiftUI, Compose, WinUI, Libadwaita) without translation layers.
public struct TaskItem: Sendable, Codable, Equatable, Identifiable, SwiftPortExported {
    public var id: UUID
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var priority: TaskPriority
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        isCompleted: Bool = false,
        priority: TaskPriority = .medium,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.priority = priority
        self.createdAt = createdAt
    }
}
