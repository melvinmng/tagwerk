import AppIntents
import SwiftUI

/// When the Siri tip card is shown (#188 SI3).
enum SiriTipPolicy {
    /// The card stays until the user closes it or runs the shortcut once; never in UI test mode, so the audits of the
    /// shopping list and "Erfassen" do not change.
    static func isVisible(done: Bool, isUITest: Bool) -> Bool {
        !done && !isUITest
    }

    /// The same rule for the running app (UI test mode from the launch arguments). Call sites check it before they add the
    /// card, so a hidden card leaves no empty list row behind.
    static func isVisible(done: Bool) -> Bool {
        isVisible(done: done, isUITest: UITestMode.isActive)
    }
}

/// The system tip card for one App Shortcut. The system draws no content when the shortcuts are not registered (device check Z1).
/// Closing it writes `done`; `IntentServices` sets the same flag when the shortcut ran once.
struct SiriTip<Intent: AppIntent>: View {
    let intent: Intent
    /// Reads and writes the "done" flag in `AppSettings`.
    let isDone: Binding<Bool>

    var body: some View {
        SiriTipView(intent: intent, isVisible: Binding(
            get: { SiriTipPolicy.isVisible(done: isDone.wrappedValue) },
            set: { if !$0 { isDone.wrappedValue = true } }))
    }
}
