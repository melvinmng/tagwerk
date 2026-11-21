import Foundation

extension FocusTimerModel {
    /// A button of the Live Activity. Does nothing without a session (the activity may be older than the app's state).
    func handle(_ action: FocusIntentAction) async {
        // A button tap can start the app in the background; the session is then still in the store only.
        if !isRunning { await restore() }
        guard let snap = snapshot(at: now()) else { return }
        switch action {
        case .togglePause: await snap.isPaused ? resume() : pause()
        case .complete: await finish(.complete)
        case .keepGoing: await finish(.keepGoing)
        case .postpone: await finish(.postpone)
        case .showCurrent: break
        }
        // Every button leaves the Live Activity in line with the phase that runs now, also when nothing else changed.
        await refresh()
    }

    /// The focus toggle of the control: "on" starts a free session, "off" ends the running one. Runs in the background and
    /// never opens the sheet; the session shows in the Live Activity.
    /// Returns whether something changed: a session was started or ended.
    @discardableResult
    func setRunning(_ on: Bool) async -> Bool {
        // The app may have been started in the background by the control; the session is then still in the store only.
        if !isRunning { await restore() }
        if on {
            // A session whose timer ran out waits for a choice and would block the start: close it as completed, which
            // completes no task.
            if snapshot(at: now())?.phase == .finished { await stop() }
            // Running or paused already: leave it as it is (a second start would only show the sheet).
            guard !isRunning else { return false }
            await start(task: nil, block: nil)
            isPresented = false
            return true
        } else {
            guard isRunning else { return false }
            await stop()
            return true
        }
    }

    /// Lets the Live Activity buttons reach this model. Called once by the app environment.
    func installIntentHandler() {
        FocusActionBridge.handler = { [weak self] action in await self?.handle(action) }
    }

    /// Shows the sheet for the link of the Live Activity. Returns `false` for any other link.
    func open(url: URL) -> Bool {
        guard url == FocusLink.url else { return false }
        if isRunning { isPresented = true } else { showsWhenRestored = true }
        return true
    }
}
