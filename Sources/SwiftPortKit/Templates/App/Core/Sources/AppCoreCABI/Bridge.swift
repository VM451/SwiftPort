import AppCore
import Foundation

/// Synchronous JSON helpers behind the `swiftport_*` C ABI in
/// `Exports.swift`. Every function returns a `String?` (JSON) or nil on
/// bad input; the C layer turns nil into a null pointer.
///
/// Actor-isolated store calls are bridged with a semaphore — call these
/// only from native UI/test threads, never from Swift concurrency.
public enum Bridge {
    public static let abiVersion: Int32 = 1

    /// Contract fixture JSON → `TaskListSnapshot` JSON. This is the
    /// deterministic path native contract tests use to render identical
    /// states without bundling fixtures twice.
    public static func fixtureSnapshotJSON(_ fixtureJSON: String) -> String? {
        let decoder = JSONDecoder()
        guard let data = fixtureJSON.data(using: .utf8),
              let scenario = try? decoder.decode(ContractScenario.self, from: data)
        else { return nil }
        return encode(TaskStore.fixtureSnapshot(for: scenario))
    }

    // MARK: - Live store

    public static func snapshotJSON() -> String? {
        withStore { await $0.snapshot() }.flatMap(encode)
    }

    public static func addTask(title: String, notes: String, priority: String) -> String? {
        withStore { store in
            _ = await store.addTask(
                title: title,
                notes: notes,
                priority: TaskPriority(rawValue: priority) ?? .medium
            )
            return await store.snapshot()
        }.flatMap(encode)
    }

    public static func toggleTask(id: String) -> String? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return withStore { store in
            await store.toggleCompleted(uuid)
            return await store.snapshot()
        }.flatMap(encode)
    }

    public static func deleteTask(id: String) -> String? {
        guard let uuid = UUID(uuidString: id) else { return nil }
        return withStore { store in
            await store.delete(uuid)
            return await store.snapshot()
        }.flatMap(encode)
    }

    public static func resetStore() -> String? {
        storeQueue.sync {
            store = TaskStore(tasks: Self.demoTasks(), latency: .zero)
        }
        return snapshotJSON()
    }

    // MARK: - Internals

    private static let storeQueue = DispatchQueue(label: "swiftport.cabi.store")
    private nonisolated(unsafe) static var store = TaskStore(tasks: demoTasks(), latency: .zero)

    private static func demoTasks() -> [TaskItem] {
        [
            TaskItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                title: "Buy groceries",
                notes: "Milk, eggs, coffee",
                priority: .medium
            ),
            TaskItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                title: "Write release notes",
                isCompleted: true,
                priority: .high
            ),
            TaskItem(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                title: "Review community PRs",
                priority: .low
            ),
        ]
    }

    private final class ResultBox<T>: @unchecked Sendable {
        var value: T?
    }

    /// Runs `body` against the actor store from synchronous C code. The
    /// semaphore blocks the calling (native) thread until the actor call
    /// completes — safe because C callers are never on the Swift
    /// cooperative thread pool.
    private static func withStore<T>(
        _ body: @escaping @Sendable (TaskStore) async -> T
    ) -> T? {
        let box = ResultBox<T>()
        let semaphore = DispatchSemaphore(value: 0)
        storeQueue.sync {
            let current = store
            Task {
                box.value = await body(current)
                semaphore.signal()
            }
        }
        semaphore.wait()
        return box.value
    }

    private static func encode<T: Encodable>(_ value: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
