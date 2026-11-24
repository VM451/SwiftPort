import SwiftUI
import AppCore
import AppUI

@main
struct __APP_MODULE__App: App {
    @StateObject private var model = TaskListViewModel()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TaskListView(model: model)
                    .navigationTitle("__APP_NAME__")
            }
        }
        #if os(macOS)
        .defaultSize(width: 560, height: 640)
        #endif
    }
}
