import Adwaita
import AppCore
import Foundation

/// GNOME-HIG task list. Every `TaskPhase` has a designed state, matching the
/// shared contract fixtures in `Verification/Contracts/`.
struct TaskListView: View {
    let store: TaskStore

    @State private var snapshot: TaskListSnapshot

    init(store: TaskStore) {
        self.store = store
        // Snapshot mode for `swiftport verify`: when SWIFTPORT_SCENARIO and
        // SWIFTPORT_CONTRACTS_DIR are set, render that contract fixture
        // directly instead of the live loading state.
        let env = ProcessInfo.processInfo.environment
        var initial = TaskListSnapshot(phase: .loading)
        if let id = env["SWIFTPORT_SCENARIO"], !id.isEmpty,
           let dir = env["SWIFTPORT_CONTRACTS_DIR"], !dir.isEmpty,
           let fixtures = try? ContractScenario.loadAll(
               from: URL(fileURLWithPath: dir)
           ),
           let scenario = fixtures.first(where: { $0.id == id }) {
            initial = TaskStore.fixtureSnapshot(for: scenario)
        }
        _snapshot = State(wrappedValue: initial)
    }

    var view: Body {
        VStack(spacing: 12) {
            switch snapshot.phase {
            case .loading:
                StatusPage("Loading…")
            case .empty:
                StatusPage(
                    "No Tasks",
                    description: "Add a task to get started."
                )
            case .loaded:
                List(snapshot.tasks, id: \.id, selection: nil) { task in
                    HStack(spacing: 8) {
                        Text(task.isCompleted ? "✓" : "○")
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title).ellipsize()
                            if !task.notes.isEmpty {
                                Text(task.notes).ellipsize().style("caption")
                            }
                        }
                    }
                }
                .boxedList()
            case .error:
                StatusPage(
                    "Couldn't Load Tasks",
                    description: snapshot.errorMessage ?? "An unknown error occurred."
                )
            }

            HStack(spacing: 8) {
                Button("Load") {
                    Task {
                        await store.load()
                        snapshot = await store.snapshot()
                    }
                }
                Button("Add Sample Task") {
                    Task {
                        _ = await store.addTask(
                            title: "Try SwiftPort",
                            notes: "Local-first tasks, native everywhere."
                        )
                        snapshot = await store.snapshot()
                    }
                }
                .style("suggested-action")
            }
        }
        .padding()
    }
}
