import Adwaita
import AppCore

@main
struct __APP_MODULE__App: App {
    let app = AdwaitaApp(id: "__BUNDLE_ID__")

    var scene: Scene {
        Window(id: "main") { _ in
            TaskListView(store: TaskStore())
        }
        .defaultSize(width: 480, height: 640)
        .quitShortcut()
        .closeShortcut()
    }
}
