import SwiftData
import SwiftUI

@main
struct TagwerkApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainerFactory.make(inMemory: false)
        } catch {
            // A broken store makes the app unusable; fail loudly instead of losing data silently.
            fatalError("Failed to open the SwiftData store: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
