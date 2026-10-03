import SwiftUI

@main
struct rupickApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 480, height: 600)
        .windowResizability(.contentSize)
    }
}
