import SwiftData
import SwiftUI

@main
struct TagwerkApp: App {
    @State private var environment: AppEnvironment
    @Environment(\.scenePhase) private var scenePhase

    init() {
        do {
            let container = try ModelContainerFactory.make(inMemory: false)
            _environment = State(initialValue: try AppEnvironment(modelContainer: container))
        } catch {
            // A broken store makes the app unusable; fail loudly instead of losing data silently.
            fatalError("Failed to open the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(environment)
                .task {
                    #if DEBUG && targetEnvironment(simulator)
                    await DemoData.seedIfRequested(environment)
                    #endif
                    environment.startObservingChanges()
                    await environment.activateGitHubIfSignedIn()
                    environment.startReconnectWatch()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { Task { await environment.retryGitHubIfNeeded() } }
                }
        }
        .modelContainer(environment.modelContainer)
    }
}
