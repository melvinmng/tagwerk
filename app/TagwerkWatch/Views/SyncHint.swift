import SwiftUI
import TagwerkCore

/// The quiet line under a page: actions that wait for the phone, actions that were dropped, an old snapshot.
struct SyncHint: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.pendingCount > 0 {
                Label("Wird übertragen, sobald das iPhone erreichbar ist (\(store.pendingCount))", systemImage: "arrow.triangle.2.circlepath")
            }
            if store.droppedCount > 0 {
                Button {
                    store.clearDroppedNotice()
                } label: {
                    Label("Nicht übertragen (\(store.droppedCount))", systemImage: "exclamationmark.triangle")
                }
                .buttonStyle(.plain)
            }
            if store.isStale() {
                Label("Öffne Tagwerk auf dem iPhone", systemImage: "iphone")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

/// "Rückgängig" for five seconds after a tap.
struct UndoRow: View {
    @Environment(WatchStore.self) private var store

    var body: some View {
        if let offer = store.undoOffer() {
            Button {
                store.undoLast()
            } label: {
                Label {
                    VStack(alignment: .leading) {
                        Text("Rückgängig")
                        Text(summary(of: offer.subject)).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
                    }
                } icon: {
                    Image(systemName: "arrow.uturn.backward")
                }
            }
            .tint(.orange)
        }
    }

    private func summary(of subject: WatchState.UndoOffer.Subject) -> String {
        switch subject {
        case .task(let title): title
        case .habit(let name, _): name
        case .water(let milliliters): "+\(milliliters) ml"
        }
    }
}
