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

/// A habit as Siri and Shortcuts see it: only its name, never streaks or rates.
struct HabitEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Gewohnheit"
    static let defaultQuery = HabitEntityQuery()

    var id: UUID
    @Property(title: "Name") var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name)) }

    init(_ habit: Habit) {
        id = habit.id
        name = habit.name
    }
}

struct HabitEntityQuery: EntityQuery {
    @Dependency private var services: IntentServices

    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [HabitEntity] {
        services.activeHabits().filter { identifiers.contains($0.id) }.map(HabitEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [HabitEntity] {
        services.activeHabits().map(HabitEntity.init)
    }
}

/// "Gewohnheit abhaken": runs in the background and checks a habit off for today. There is no undo by voice.
struct CheckHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "Gewohnheit abhaken"
    static let description = IntentDescription("Hakt eine Gewohnheit für heute ab, ohne die App zu öffnen.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Gewohnheit", requestValueDialog: "Welche Gewohnheit?")
    var habit: HabitEntity

    @Dependency private var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await services.checkHabit(id: habit.id)
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

/// An article name as Siri and Shortcuts see it. The id is the name itself, so any name can be rebuilt from it.
struct ShoppingArticleEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Artikel"
    static let defaultQuery = ShoppingArticleEntityQuery()

    var id: String
    @Property(title: "Name") var name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name)) }

    init(name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        id = trimmed
        self.name = trimmed
    }

    /// Entities for stored ids; blank ids are dropped.
    static func entities(for identifiers: [String]) -> [ShoppingArticleEntity] {
        identifiers.map(ShoppingArticleEntity.init(name:)).filter { !$0.name.isEmpty }
    }
}

/// Resolves article names: the suggested ones (own history and common terms) are what Siri can speak in a phrase;
/// typed or spoken text is matched against them and otherwise taken as it is.
struct ShoppingArticleEntityQuery: EntityStringQuery {
    @Dependency private var services: IntentServices

    @MainActor
    func entities(for identifiers: [String]) async throws -> [ShoppingArticleEntity] {
        ShoppingArticleEntity.entities(for: identifiers)
    }

    @MainActor
    func entities(matching string: String) async throws -> [ShoppingArticleEntity] {
        await services.shoppingArticleNames(matching: string).map(ShoppingArticleEntity.init(name:))
    }

    @MainActor
    func suggestedEntities() async throws -> [ShoppingArticleEntity] {
        await services.shoppingArticleNames().map(ShoppingArticleEntity.init(name:))
    }
}

/// "Füge Milch zur Einkaufsliste hinzu": the article is part of the spoken phrase. Runs in the background like
/// the text shortcut; without a recognized article Siri asks the same question.
struct AddShoppingArticleIntent: AppIntent {
    static let title: LocalizedStringResource = "Artikel auf die Einkaufsliste"
    static let description = IntentDescription("Fügt einen Artikel zur Einkaufsliste hinzu, ohne Tagwerk zu öffnen.")
    static let supportedModes: IntentModes = .background

    @Parameter(title: "Artikel", requestValueDialog: "Was soll auf die Liste?")
    var article: ShoppingArticleEntity

    /// Not private: a test sets it, the system injects it otherwise.
    @Dependency var services: IntentServices

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let reply = await services.addToShopping(article: article)
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
            "Füge etwas zur Einkaufsliste in \(.applicationName) hinzu",
            "Ich brauche etwas aus dem Laden in \(.applicationName)",
            "Einkaufsliste in \(.applicationName)",
            "Neuer Artikel in \(.applicationName)",
            "Etwas auf die Einkaufsliste in \(.applicationName) setzen",
        ], shortTitle: "Auf die Einkaufsliste", systemImageName: "cart.badge.plus")
        // The article is part of the phrase; its names come from `ShoppingArticleEntityQuery.suggestedEntities`
        // and are refreshed with `updateAppShortcutParameters()`.
        AppShortcut(intent: AddShoppingArticleIntent(), phrases: [
            "Füge \(\.$article) zur Einkaufsliste in \(.applicationName) hinzu",
            "\(\.$article) auf die Einkaufsliste in \(.applicationName)",
            "Setz \(\.$article) auf die Einkaufsliste in \(.applicationName)",
        ], shortTitle: "Artikel auf die Einkaufsliste", systemImageName: "cart.badge.plus")
        AppShortcut(intent: CheckHabitIntent(), phrases: [
            "\(\.$habit) in \(.applicationName) abhaken",
            "Gewohnheit in \(.applicationName) abhaken",
        ], shortTitle: "Gewohnheit abhaken", systemImageName: "checkmark.circle")
        AppShortcut(intent: OpenShoppingListIntent(), phrases: [
            "Einkaufsliste in \(.applicationName) zeigen",
        ], shortTitle: "Einkaufsliste zeigen", systemImageName: "cart")
    }
}
