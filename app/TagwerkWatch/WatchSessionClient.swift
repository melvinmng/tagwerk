import Foundation
import TagwerkCore
import WatchConnectivity

/// The watch's side of `WCSession`: sends the queued actions (a direct message while the phone is reachable, otherwise
/// a user-info transfer that the system delivers later) and receives the snapshot of the phone.
@MainActor
final class WatchSessionClient: NSObject {
    private let store: WatchStore
    private let session: WCSession?

    init(store: WatchStore) {
        self.store = store
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    /// Sends what is due: actions never sent and actions without a confirmation after ten minutes. The phone applies
    /// every action ID once, so a repeat does no harm.
    func flush() {
        guard let session, session.activationState == .activated else { return }
        for action in store.pendingActions() {
            guard let payload = try? action.encoded() else { continue }
            let message = [WatchAction.transportKey: payload]
            store.markSent(action.id)
            if session.isReachable {
                let id = action.id
                session.sendMessage(message, replyHandler: { reply in
                    guard reply["watchReply"] as? String == "done" else { return }
                    Task { @MainActor in self.store.acknowledge(id) }
                }, errorHandler: { _ in
                    // Not delivered: hand it to the system, which sends it as soon as the phone is reachable.
                    session.transferUserInfo(message)
                })
            } else {
                session.transferUserInfo(message)
            }
        }
    }

    private func receive(context: [String: Any]) {
        guard let data = context["watchSnapshot"] as? Data, let snapshot = WatchSnapshot.decode(data) else { return }
        store.receive(snapshot)
        flush()
    }
}

extension WatchSessionClient: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        let context = session.receivedApplicationContext
        nonisolated(unsafe) let box = context
        Task { @MainActor in
            self.receive(context: box)
            self.flush()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        nonisolated(unsafe) let box = applicationContext
        Task { @MainActor in self.receive(context: box) }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.flush() }
    }
}
