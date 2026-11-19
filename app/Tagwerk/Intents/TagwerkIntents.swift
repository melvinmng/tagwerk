import AppIntents
import SwiftUI
import TagwerkCore

/// Workout types for Siri; mirrors `WorkoutActivity`.
enum WorkoutActivityOption: String, AppEnum {
    case strength, running, cycling, walking, hiking, swimming, yoga, hiit, other

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Trainingsart"
    static let caseDisplayRepresentations: [WorkoutActivityOption: DisplayRepresentation] = [
        .strength: "Krafttraining", .running: "Laufen", .cycling: "Radfahren", .walking: "Gehen", .hiking: "Wandern",
        .swimming: "Schwimmen", .yoga: "Yoga", .hiit: "HIIT", .other: "Sonstiges",
    ]

    var activity: WorkoutActivity { WorkoutActivity(rawValue: rawValue) ?? .other }
}

/// "Wasser erfassen": runs in the background and records water now.
struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Wasser erfassen"
    static let description = IntentDescription("Trägt Wasser in Tagwerk ein, ohne die App zu öffnen.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Menge", default: 250, inclusiveRange: (50, 2000))
    var milliliters: Int

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await services.logWater(milliliters: milliliters)
        return .result(dialog: IntentDialog(reply))
    }
}

/// "Mahlzeit erfassen": opens the meal sheet; estimating needs a tap there (main design §7).
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Mahlzeit erfassen"
    static let description = IntentDescription("Öffnet das Blatt „Essen“ in Tagwerk.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Beschreibung")
    var text: String?

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult {
        services.openMeal(text: text)
        return .result()
    }
}

/// "Training erfassen": opens the workout sheet prefilled.
struct LogWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Training erfassen"
    static let description = IntentDescription("Öffnet das Blatt „Training“ in Tagwerk.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Parameter(title: "Art")
    var activity: WorkoutActivityOption?

    @Parameter(title: "Dauer", inclusiveRange: (1, 600))
    var minutes: Int?

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult {
        services.openWorkout(activity: activity?.activity, minutes: minutes)
        return .result()
    }
}

/// "Auf die Einkaufsliste": runs in the background and adds the named items to the chosen reminder list.
/// The reply repeats only what was just said, so no unlocked device is required.
struct AddToShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Auf die Einkaufsliste"
    static let description = IntentDescription("Fügt Artikel zur Einkaufsliste hinzu, ohne Tagwerk zu öffnen.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Artikel", requestValueDialog: "Was soll auf die Liste?")
    var items: String

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await services.addToShopping(text: items)
        return .result(dialog: IntentDialog(reply))
    }
}

/// "Einkaufsliste zeigen": opens the shopping page.
struct OpenShoppingListIntent: AppIntent {
    static let title: LocalizedStringResource = "Einkaufsliste zeigen"
    static let description = IntentDescription("Öffnet die Einkaufsliste in Tagwerk.")
    static let supportedModes: IntentModes = .foreground(.immediate)

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult {
        services.openShopping()
        return .result()
    }
}

/// "Was steht heute an?": events, blocks and deadlines from the widget snapshot, never nutrition.
struct TodayOverviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Was steht heute an?"
    static let description = IntentDescription("Nennt Termine, Blöcke und Deadlines von heute.")
    static let supportedModes: IntentModes = .background
    /// Titles are read aloud; the device has to be unlocked.
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let overview = services.todayOverview()
        return .result(dialog: IntentDialog(stringLiteral: overview.text)) {
            TodayOverviewSnippet(entries: overview.entries)
        }
    }
}

/// The list under Siri's answer: up to three next entries.
struct TodayOverviewSnippet: View {
    let entries: [SnapshotEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                HStack(spacing: 8) {
                    Text(DateText.time(entry.start, calendar: .tagwerk))
                        .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    Text(entry.title).font(.subheadline).lineLimit(1)
                }
            }
        }
        .padding()
    }
}

/// The phrases Siri and Shortcuts offer without setup (design §8); every phrase names the app.
struct TagwerkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Wasser in \(.applicationName) erfassen",
            "Wasser mit \(.applicationName) erfassen",
            "Trinken in \(.applicationName) erfassen",
        ], shortTitle: "Wasser erfassen", systemImageName: "drop.fill")
        AppShortcut(intent: LogMealIntent(), phrases: [
            "Mahlzeit in \(.applicationName) erfassen",
            "Essen in \(.applicationName) erfassen",
        ], shortTitle: "Mahlzeit erfassen", systemImageName: "fork.knife")
        AppShortcut(intent: LogWorkoutIntent(), phrases: [
            "Training in \(.applicationName) erfassen",
            "\(\.$activity) in \(.applicationName) erfassen",
        ], shortTitle: "Training erfassen", systemImageName: "figure.run")
        AppShortcut(intent: TodayOverviewIntent(), phrases: [
            "Was steht heute in \(.applicationName) an",
            "Mein Tag in \(.applicationName)",
        ], shortTitle: "Heute", systemImageName: "calendar")
        AppShortcut(intent: AddToShoppingListIntent(), phrases: [
            "Auf die Einkaufsliste in \(.applicationName)",
            "Zur Einkaufsliste in \(.applicationName) hinzufügen",
            "Einkaufsliste in \(.applicationName) ergänzen",
        ], shortTitle: "Auf die Einkaufsliste", systemImageName: "cart.badge.plus")
        AppShortcut(intent: OpenShoppingListIntent(), phrases: [
            "Einkaufsliste in \(.applicationName) zeigen",
        ], shortTitle: "Einkaufsliste zeigen", systemImageName: "cart")
    }
}
