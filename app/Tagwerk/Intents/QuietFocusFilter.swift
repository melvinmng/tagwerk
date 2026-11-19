import AppIntents

/// Focus filter (iOS Settings › Focus › Focus filters › Tagwerk): "Mitteilungen ruhen lassen".
/// iOS runs it with the chosen value when a Focus starts and with the default value when it ends, in the app's process
/// like the other App Intents. The filter needs no entitlement; it is a plain App Intent.
struct QuietFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Mitteilungen ruhen lassen"
    static let description: IntentDescription? = IntentDescription(
        "Hält Mitteilungen zu Aufgaben und Deadline-Terminen zurück, solange der Fokus aktiv ist. Sie kommen nach den Ruhezeiten oder nach dem Fokus.")

    @Parameter(title: "Tagwerk-Mitteilungen ruhen lassen", default: false)
    var silencesNotifications: Bool

    @Dependency private var services: IntentServices

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: silencesNotifications ? "Mitteilungen ruhen" : "Mitteilungen wie gewohnt")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await services.setFocusQuiet(active: silencesNotifications)
        return .result()
    }
}
