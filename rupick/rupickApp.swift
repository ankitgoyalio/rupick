import AppKit
import SwiftUI

// MARK: - rupickApp

@main
struct rupickApp: App {
    @NSApplicationDelegateAdaptor(SessionApplicationDelegate.self) private var delegate
    @State private var workspace = ProjectWorkspace(defaults: SessionApplicationDelegate.sessionDefaults, persistsSessions:
        UserDefaults.standard.bool(forKey: "ApplePersistenceIgnoreState") == false ||
            ProcessInfo.processInfo.environment["RUPICK_RESTORE_SESSIONS"] == "1")

    var body: some Scene {
        Window("rupick", id: "welcome") {
            ContentView(project: .constant(nil))
                .environment(workspace)
                .task { delegate.workspace = workspace }
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

// MARK: - SessionApplicationDelegate

/// The termination callback precedes window teardown, so quitting retains open sessions.
@MainActor
final class SessionApplicationDelegate: NSObject, NSApplicationDelegate {
    static var sessionDefaults: UserDefaults {
        #if DEBUG
            if let suite = ProcessInfo.processInfo.environment["RUPICK_SESSION_TEST_ID"], let defaults = UserDefaults(suiteName: suite) {
                return defaults
            }
        #endif
        return .standard
    }

    var workspace: ProjectWorkspace?

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        if workspace?.prepareForTermination() == false {
            .terminateCancel
        } else {
            .terminateNow
        }
    }
}
