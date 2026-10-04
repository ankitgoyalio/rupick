import SwiftUI

@main
struct rupickApp: App {
    @State private var workspace = ProjectWorkspace()

    var body: some Scene {
        Window("rupick", id: "welcome") {
            ContentView(project: .constant(nil))
                .environment(workspace)
        }
        .defaultLaunchBehavior(.presented)
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)

        WindowGroup(for: URL.self) { $project in
            ContentView(project: $project)
                .environment(workspace)
        }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .defaultSize(width: 950, height: 620)
        .windowResizability(.contentSize)
    }
}
