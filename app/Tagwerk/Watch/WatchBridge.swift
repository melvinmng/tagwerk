import Foundation
import TagwerkCore

/// Connects the phone to the Apple Watch app: receives its actions (exactly once, in order), and sends the snapshot the
/// watch shows. `TagwerkApp.init` installs it, because iOS starts the app in the background for a watch message and
/// `RootView` never appears then.
@MainActor
final class WatchBridge {
    private let session: any WatchSessioning
    private let executor: any WatchActionPerforming
    private let snapshotProvider: @MainActor ([UUID]) -> WatchSnapshot?
    private let directory: URL?
    private let debounce: Duration
    private var log: WatchActionLog
    private var lastSentFingerprint: Data?
    private var pendingSend: Task<Void, Never>?
    private var tail: Task<WatchReply, Never>?

    init(session: any WatchSessioning, executor: any WatchActionPerforming,
         snapshotProvider: @escaping @MainActor ([UUID]) -> WatchSnapshot?, directory: URL?, debounce: Duration = .seconds(2)) {
        self.session = session
        self.executor = executor
        self.snapshotProvider = snapshotProvider
        self.directory = directory
        self.debounce = debounce
        self.log = WatchActionLog.load(from: directory)
    }

    /// The real bridge of the app: the system session, the app's models and a small file in the app container.
    static func install(environment: AppEnvironment, services: IntentServices) {
        let session = SystemWatchSession()
        guard session.isSupported else { return }
        let directory = URL.applicationSupportDirectory.appending(path: "Watch", directoryHint: .isDirectory)
        let bridge = WatchBridge(session: session, executor: WatchActionExecutor(environment: environment, services: services),
                                 snapshotProvider: { [weak environment] applied in
                                     guard let environment else { return nil }
                                     return WatchSnapshotBuilder.make(environment: environment, appliedActionIDs: applied)
                                 },
                                 directory: directory)
        environment.watchBridge = bridge
        environment.snapshotWriter.onWritten = { [weak bridge] in bridge?.snapshotInputsChanged() }
        bridge.start()
    }

    func start() {
        guard session.isSupported else { return }
        session.onAction = { [weak self] data in await self?.handle(data) ?? .later }
        session.onReady = { [weak self] in self?.sendSnapshot(force: true) }
        session.activate()
    }

    // MARK: Receiving

    /// Applies the action in `data`. Calls are served one after the other, so a repeat that arrives while the first
    /// is still running waits and then finds it applied.
    func handle(_ data: Data) async -> WatchReply {
        let previous = tail
        let task = Task { @MainActor [weak self] () -> WatchReply in
            _ = await previous?.value
            return await self?.process(data) ?? .later
        }
        tail = task
        return await task.value
    }

    private func process(_ data: Data) async -> WatchReply {
        guard let action = WatchAction.decode(data) else { return .done }
        if log.hasApplied(action.id) {
            // The watch did not hear about it yet: confirm with the next snapshot.
            snapshotInputsChanged()
            return .done
        }
        // An undo that overtook its action: remember it, so the action is skipped when it arrives.
        if case .undo(let target) = action.kind, !log.hasApplied(target) {
            log.markCancelled(target)
            markApplied(action.id)
            return .done
        }
        if log.consumeCancellation(of: action.id) {
            markApplied(action.id)
            return .done
        }
        let result = await executor.perform(action)
        if result == .done { markApplied(action.id) }
        snapshotInputsChanged()
        return result == .done ? .done : .later
    }

    private func markApplied(_ id: UUID) {
        log.markApplied(id)
        try? log.write(to: directory)
    }

    // MARK: Sending

    /// The inputs of the snapshot changed (the widget snapshot was written, an action was applied): sends a new one
    /// after a short pause, because several changes arrive together.
    func snapshotInputsChanged() {
        guard session.isSupported else { return }
        pendingSend?.cancel()
        pendingSend = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.sendSnapshot(force: false)
        }
    }

    /// `force` sends even when the content is the one sent last (a watch that was just installed has none).
    func sendSnapshot(force: Bool) {
        guard session.isSupported, session.canSendContext, let snapshot = snapshotProvider(log.recentApplied),
              let data = try? snapshot.encoded() else { return }
        let fingerprint = snapshot.contentFingerprint()
        guard force || fingerprint != lastSentFingerprint else { return }
        do {
            try session.sendContext(data)
            lastSentFingerprint = fingerprint
        } catch {
            // The system refuses while the session is not ready; the next change or activation sends again.
        }
    }
}
