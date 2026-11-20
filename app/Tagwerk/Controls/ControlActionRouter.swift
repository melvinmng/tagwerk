import AppIntents
import Foundation
import WidgetKit

/// Reloads a control after its state changed.
@MainActor
protocol ControlReloading: AnyObject {
    func reloadControls(ofKind kind: String)
}

/// The real thing: asks the system to ask the extension for the control's current value.
@MainActor
final class SystemControlReloader: ControlReloading {
    func reloadControls(ofKind kind: String) {
        ControlCenter.shared.reloadControls(ofKind: kind)
    }
}

/// What the controls may write: the same two actions the Siri shortcuts use.
@MainActor
protocol ControlWriting: AnyObject {
    func logWater(milliliters: Int?) async -> LocalizedStringResource
    func checkHabit(id: UUID) async -> LocalizedStringResource
}

extension IntentServices: ControlWriting {}

/// The focus timer as the focus control sees it.
@MainActor
protocol ControlFocusSwitching: AnyObject {
    func setRunning(_ on: Bool) async
}

extension FocusTimerModel: ControlFocusSwitching {}

/// Carries out what the controls ask for, in the app's process. `TagwerkApp.init` installs it, before the first frame.
@MainActor
final class ControlActionRouter {
    private let writer: ControlWriting
    private let focus: ControlFocusSwitching

    init(writer: ControlWriting, focus: ControlFocusSwitching) {
        self.writer = writer
        self.focus = focus
    }

    func handle(_ action: ControlAction) async {
        switch action {
        case .logWater(let milliliters): _ = await writer.logWater(milliliters: milliliters)
        case .checkHabit(let id): _ = await writer.checkHabit(id: id)
        case .setFocus(let on): await focus.setRunning(on)
        }
    }

    /// Makes the controls reach this router. Called once at launch.
    func install() {
        // Held by the bridge for the life of the process, like the dependencies of the App Intents.
        ControlActionBridge.handler = { [self] action in await handle(action) }
    }
}
