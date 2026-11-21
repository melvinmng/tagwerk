import AppIntents
import Foundation

/// What a button of the Live Activity asks for.
enum FocusIntentAction: String, Sendable {
    /// Pauses a running timer, or resumes a paused one.
    case togglePause
    case complete
    /// Skips a running break, or starts the next session after a finished one.
    case keepGoing
    case postpone
    /// Brings the activity in line with the phase that runs now ("Pause starten" after the work phase ended).
    case showCurrent
}

/// Connects the Live Activity buttons to the app. Only the app sets the handler. Live Activity intents run in the app's
/// process, so the handler is there when a button is tapped; in the widget extension it stays `nil`.
@MainActor
enum FocusActionBridge {
    static var handler: (@MainActor (FocusIntentAction) async -> Void)?
}

struct FocusPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fokus pausieren"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await FocusActionBridge.handler?(.togglePause)
        return .result()
    }
}

struct FocusCompleteIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aufgabe erledigen"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await FocusActionBridge.handler?(.complete)
        return .result()
    }
}

struct FocusContinueIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Fokus fortsetzen"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await FocusActionBridge.handler?(.keepGoing)
        return .result()
    }
}

struct FocusPostponeIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aufgabe verschieben"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await FocusActionBridge.handler?(.postpone)
        return .result()
    }
}

struct FocusShowCurrentIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Aktuelle Phase zeigen"
    static let isDiscoverable = false

    func perform() async throws -> some IntentResult {
        await FocusActionBridge.handler?(.showCurrent)
        return .result()
    }
}
