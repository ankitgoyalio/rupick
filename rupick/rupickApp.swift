import SwiftUI

@main
struct rupickApp: App {
    @State private var workspace = ProjectWorkspace()

    var body: some Scene {
        WindowGroup(for: URL?.self) { $project in
            ContentView(project: $project)
                .environment(workspace)
        } defaultValue: {
            nil
        }
        .defaultLaunchBehavior(.presented)
        .restorationBehavior(.disabled)
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
    }
}
