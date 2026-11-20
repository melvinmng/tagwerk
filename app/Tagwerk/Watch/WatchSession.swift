import Foundation
import TagwerkCore
import WatchConnectivity

/// What the phone does with a received watch action.
enum WatchReply: String, Sendable {
    /// Applied, ignored on purpose (task gone) or applied before: the watch may drop the action.
    case done
    /// Could not be carried out now (models not loaded in time); the watch keeps the action queued.
    case later
}

/// The phone's side of the watch connection, behind a protocol so tests do not need the system.
@MainActor
protocol WatchSessioning: AnyObject {
    var isSupported: Bool { get }
    /// A watch is paired and has the app installed.
    var canSendContext: Bool { get }
    /// Called with the payload of every received action; the result goes back as the reply of `sendMessage`.
    var onAction: (@MainActor (Data) async -> WatchReply)? { get set }
    /// Called when the session becomes active or the watch state changes: the phone sends a fresh snapshot.
    var onReady: (@MainActor () -> Void)? { get set }
    func activate()
    /// Hands the encoded snapshot to `updateApplicationContext` (the system keeps only the latest).
    func sendContext(_ snapshot: Data) throws
}

/// Key of the snapshot in the application context.
enum WatchTransport {
    static let snapshotKey = "watchSnapshot"
    static let replyKey = "watchReply"
}

/// The real `WCSession`. The delegate callbacks arrive on a background queue; only `Data` crosses to the main actor.
@MainActor
final class SystemWatchSession: NSObject, WatchSessioning {
    private let session: WCSession?
    var onAction: (@MainActor (Data) async -> WatchReply)?
    var onReady: (@MainActor () -> Void)?

    override init() {
        session = WCSession.isSupported() ? WCSession.default : nil
        super.init()
    }

    var isSupported: Bool { session != nil }

    var canSendContext: Bool {
        guard let session else { return false }
        return session.activationState == .activated && session.isPaired && session.isWatchAppInstalled
    }

    func activate() {
        guard let session else { return }
        session.delegate = self
        session.activate()
    }

    func sendContext(_ snapshot: Data) throws {
        try session?.updateApplicationContext([WatchTransport.snapshotKey: snapshot])
    }
}

extension SystemWatchSession: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.onReady?() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// A new watch was paired: the session must be activated again.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.onReady?() }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        guard let data = message[WatchAction.transportKey] as? Data else {
            replyHandler([WatchTransport.replyKey: WatchReply.done.rawValue])
            return
        }
        nonisolated(unsafe) let reply = replyHandler
        Task { @MainActor in
            let result = await self.onAction?(data) ?? .later
            reply([WatchTransport.replyKey: result.rawValue])
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo[WatchAction.transportKey] as? Data else { return }
        Task { @MainActor in _ = await self.onAction?(data) }
    }
}
