import SwiftUI
import AppCore
import AppUI
import Foundation

@main
struct __APP_MODULE__App: App {
    @StateObject private var model: TaskListViewModel

    init() {
        // Snapshot mode for `swiftport verify`: SWIFTPORT_SCENARIO +
        // SWIFTPORT_CONTRACTS_DIR render a contract fixture directly.
        // SWIFTPORT_THEME=light|dark forces a color scheme for captures.
        let env = ProcessInfo.processInfo.environment
        if let id = env["SWIFTPORT_SCENARIO"], !id.isEmpty,
           let dir = env["SWIFTPORT_CONTRACTS_DIR"], !dir.isEmpty,
           let fixtures = try? ContractScenario.loadAll(
               from: URL(fileURLWithPath: dir)
           ),
           let scenario = fixtures.first(where: { $0.id == id }) {
            _model = StateObject(wrappedValue: TaskListViewModel(fixture: scenario))
        } else {
            _model = StateObject(wrappedValue: TaskListViewModel())
        }
    }

    /// Forced color scheme for snapshot captures; nil follows the system.
    static var colorSchemeOverride: ColorScheme? {
        switch ProcessInfo.processInfo.environment["SWIFTPORT_THEME"] {
        case "dark": return .dark
        case "light": return .light
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TaskListView(model: model)
                    .navigationTitle("__APP_NAME__")
            }
            .preferredColorScheme(Self.colorSchemeOverride)
        }
        #if os(macOS)
        .defaultSize(width: 560, height: 640)
        #endif
    }
}
