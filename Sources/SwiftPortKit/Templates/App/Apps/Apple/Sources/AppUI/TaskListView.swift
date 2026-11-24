import SwiftUI
import AppCore

/// Root view — renders every `TaskPhase` explicitly. This is the UI contract:
/// loading, empty, loaded, and error must all have a designed state.
public struct TaskListView: View {
    @ObservedObject public var model: TaskListViewModel
    @State private var newTaskTitle = ""

    public init(model: TaskListViewModel) {
        self.model = model
    }

    public var body: some View {
        Group {
            switch model.snapshot.phase {
            case .loading:
                loadingView
            case .empty:
                emptyView
            case .loaded:
                listView
            case .error:
                errorView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading tasks…")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading tasks")
    }

    private var emptyView: some View {
        ContentUnavailableView {
            Label("No Tasks", systemImage: "checklist")
        } description: {
            Text("Add your first task using the field below.")
        }
    }

    private var errorView: some View {
        ContentUnavailableView {
            Label("Couldn't Load Tasks", systemImage: "exclamationmark.triangle")
        } description: {
            Text(model.snapshot.errorMessage ?? "An unknown error occurred.")
        } actions: {
            Button("Try Again") {
                Task { await model.reload() }
            }
        }
    }

    // MARK: - Loaded

    private var listView: some View {
        VStack(spacing: 0) {
            List(model.snapshot.tasks) { task in
                TaskRow(task: task) {
                    Task { await model.toggle(task.id) }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await model.delete(task.id) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
            .listStyle(.plain)

            Divider()
            HStack(spacing: 8) {
                TextField("New task…", text: $newTaskTitle)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submitNewTask() }
                Button("Add") { submitNewTask() }
                    .disabled(newTaskTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    private func submitNewTask() {
        let title = newTaskTitle
        newTaskTitle = ""
        Task { await model.addTask(title: title) }
    }
}

/// One task row. Button-based so it's fully keyboard/screen-reader accessible.
private struct TaskRow: View {
    let task: TaskItem
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                    .imageScale(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .strikethrough(task.isCompleted)
                        .foregroundStyle(task.isCompleted ? .secondary : .primary)
                    if !task.notes.isEmpty {
                        Text(task.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Text(task.priority.rawValue.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(task.title), \(task.priority.rawValue) priority\(task.isCompleted ? ", completed" : "")")
        .accessibilityHint(task.isCompleted ? "Marks task as not completed" : "Marks task as completed")
        .accessibilityAddTraits(.isButton)
    }
}
