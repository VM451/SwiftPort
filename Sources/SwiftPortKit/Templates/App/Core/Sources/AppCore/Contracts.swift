import Foundation

/// A contract fixture: one deterministic UI state every platform must render.
/// Fixtures live in `Verification/Contracts/*.json` and are the shared source
/// of truth for `swiftport verify --contracts` and snapshot testing.
public struct ContractScenario: Sendable, Codable, Equatable {
    public var id: String
    /// One of: loading, empty, loaded, error
    public var phase: String
    public var tasks: [ContractTask]
    public var errorMessage: String?

    public init(id: String, phase: String, tasks: [ContractTask] = [], errorMessage: String? = nil) {
        self.id = id
        self.phase = phase
        self.tasks = tasks
        self.errorMessage = errorMessage
    }

    /// Loads every `*.json` fixture in a contracts directory, sorted by id.
    public static func loadAll(from directory: URL) throws -> [ContractScenario] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else { return [] }
        return try files
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { try JSONDecoder().decode(ContractScenario.self, from: Data(contentsOf: $0)) }
    }
}

/// JSON-friendly task representation (dates/ids as strings).
public struct ContractTask: Sendable, Codable, Equatable {
    public var id: String
    public var title: String
    public var notes: String
    public var isCompleted: Bool
    public var priority: String
    public var createdAt: String

    public init(id: String, title: String, notes: String = "",
                isCompleted: Bool = false, priority: String = "medium",
                createdAt: String = "2026-01-01T00:00:00Z") {
        self.id = id
        self.title = title
        self.notes = notes
        self.isCompleted = isCompleted
        self.priority = priority
        self.createdAt = createdAt
    }

    /// Bridges to the core model. Malformed fixture values fall back to
    /// deterministic defaults — contract tests catch genuinely bad fixtures.
    public var taskItem: TaskItem {
        TaskItem(
            id: UUID(uuidString: id) ?? UUID(uuidString: "00000000-0000-0000-0000-000000000000")!,
            title: title,
            notes: notes,
            isCompleted: isCompleted,
            priority: TaskPriority(rawValue: priority) ?? .medium,
            createdAt: ISO8601DateFormatter().date(from: createdAt) ?? Date(timeIntervalSince1970: 0)
        )
    }
}
