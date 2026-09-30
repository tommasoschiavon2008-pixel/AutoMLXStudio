import SwiftUI

@main
struct AutoMLXStudioApp: App {
    @StateObject private var appState = { // Creates production state normally while preventing the XCTest host from scanning user model folders.
        let isXCTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil // Detects only the injected unit-test application host.
        if isXCTestHost { return AppState(startsBackgroundTasks: false, workspace: WorkspaceController(), loadsPersistentState: false, inspectsModelFiles: false) } // Gives tests an empty isolated host because each test injects its own dependencies.
        return AppState() // Preserves complete production persistence, model inspection, and background startup.
    }() // Ends environment-specific application-state construction.

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.titleBar)
    }
}
