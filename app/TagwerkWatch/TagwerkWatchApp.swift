import SwiftUI
import WatchKit

@main
struct TagwerkWatchApp: App {
    @State private var store: WatchStore
    private let client: WatchSessionClient
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = WatchStore()
        let client = WatchSessionClient(store: store)
        store.client = client
        _store = State(initialValue: store)
        self.client = client
        client.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            // Actions the complications recorded meanwhile, and everything that waits for delivery.
            store.refreshFromDisk()
            client.flush()
        }
        // The system wakes the app for data of the phone and for the periodic refresh.
        .backgroundTask(.watchConnectivity) {}
        .backgroundTask(.appRefresh(WatchRefresh.identifier)) {
            await store.refreshAndFlush()
            await WatchRefresh.scheduleNext()
        }
    }
}

/// Keeps the queue moving while the app is closed: a refresh every half hour sends what the complications recorded.
@MainActor
enum WatchRefresh {
    static let identifier = "tagwerk.watch.refresh"

    static func scheduleNext() {
        WKApplication.shared().scheduleBackgroundRefresh(withPreferredDate: Date().addingTimeInterval(30 * 60), userInfo: nil) { _ in }
    }
}
