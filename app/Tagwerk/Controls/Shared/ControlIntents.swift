import AppIntents
import Foundation

/// What a control asks the app to do. Plain data, so the app side can be tested without the system.
enum ControlAction: Equatable, Sendable {
    case logWater(milliliters: Int)
    case checkHabit(id: UUID)
    case setFocus(Bool)
}

/// Connects the controls to the app. Only the app sets the handler, at launch (`TagwerkApp.init`), because the system
/// may start the app in the background just to run the intent and `RootView` never appears then. These are Live
/// Activity intents, which run in the app's process; in the widget extension the handler stays `nil`.
@MainActor
enum ControlActionBridge {
    static var handler: (@MainActor (ControlAction) async -> Void)?
}

/// "+250 ml" of the water control. Adding twice records twice, on purpose.
struct ControlLogWaterIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Wasser erfassen"
    static let isDiscoverable = false

    @Parameter(title: "Menge", default: 250, inclusiveRange: (50, 1000))
    var milliliters: Int

    init() {}

    init(milliliters: Int) {
        self.milliliters = milliliters
    }

    func perform() async throws -> some IntentResult {
        await ControlActionBridge.handler?(.logWater(milliliters: milliliters))
        return .result()
    }
}

/// The habit control: checks the chosen habit off for today; a second tap changes nothing. Without a chosen habit (the
/// control asks for one when it is added, but the list may have been empty) a tap does nothing.
struct ControlCheckHabitIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Gewohnheit abhaken"
    static let isDiscoverable = false

    @Parameter(title: "Gewohnheit")
    var habit: HabitEntity?

    init() {}

    init(habit: HabitEntity?) {
        self.habit = habit
    }

    func perform() async throws -> some IntentResult {
        if let habit { await ControlActionBridge.handler?(.checkHabit(id: habit.id)) }
        return .result()
    }
}

/// The focus toggle: starts a free session or ends the running one.
struct ControlSetFocusIntent: SetValueIntent, LiveActivityIntent {
    static let title: LocalizedStringResource = "Fokus"
    static let isDiscoverable = false

    @Parameter(title: "Läuft")
    var value: Bool

    init() {}

    func perform() async throws -> some IntentResult {
        await ControlActionBridge.handler?(.setFocus(value))
        return .result()
    }
}
