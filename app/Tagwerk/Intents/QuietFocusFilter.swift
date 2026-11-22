import AppIntents

/// Focus filter (iOS Settings › Focus › Focus filters › Tagwerk): "Mitteilungen zurückhalten".
/// iOS runs it with the chosen value when a Focus starts and with the default value when it ends, in the app's process
/// like the other App Intents. The filter needs no entitlement; it is a plain App Intent.
struct QuietFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Mitteilungen zurückhalten"
    static let description: IntentDescription? = IntentDescription(
        "Tagwerk meldet sich nach dem Fokus, spätestens nach 4 Stunden. Nichts entfällt.")

    @Parameter(title: "Aufgaben und Deadlines zurückhalten", default: false)
    var silencesNotifications: Bool

    @Dependency private var services: IntentServices

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: silencesNotifications ? "Mitteilungen nach dem Fokus" : "Mitteilungen wie gewohnt")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await services.setFocusQuiet(active: silencesNotifications)
        return .result()
    }
}
