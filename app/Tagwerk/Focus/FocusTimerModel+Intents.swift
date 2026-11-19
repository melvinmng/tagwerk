import Foundation

extension FocusTimerModel {
    /// A button of the Live Activity. Does nothing without a session (the activity may be older than the app's state).
    func handle(_ action: FocusIntentAction) async {
        guard let snap = snapshot(at: now()) else { return }
        switch action {
        case .togglePause: await snap.isPaused ? resume() : pause()
        case .complete: await finish(.complete)
        case .keepGoing: await finish(.keepGoing)
        case .postpone: await finish(.postpone)
        }
    }

    /// Lets the Live Activity buttons reach this model. Called once by the app environment.
    func installIntentHandler() {
        FocusActionBridge.handler = { [weak self] action in await self?.handle(action) }
    }

    /// Shows the sheet for the link of the Live Activity. Returns `false` for any other link.
    func open(url: URL) -> Bool {
        guard url == FocusLink.url else { return false }
        if isRunning { isPresented = true }
        return true
    }
}
