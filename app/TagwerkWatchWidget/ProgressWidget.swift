import AppIntents
import SwiftUI
import TagwerkCore
import WidgetKit

enum ProgressKind: String, AppEnum {
    case habits, water

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Anzeige")
    static let caseDisplayRepresentations: [ProgressKind: DisplayRepresentation] = [
        .habits: DisplayRepresentation(title: "Gewohnheiten"),
        .water: DisplayRepresentation(title: "Wasser"),
    ]
}

struct ProgressConfigurationIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Fortschritt"
    static let description = IntentDescription("Gewohnheiten von heute oder Wasser.")

    @Parameter(title: "Anzeige", default: .habits)
    var kind: ProgressKind
}

struct ProgressEntry: TimelineEntry {
    let date: Date
    let kind: ProgressKind
    /// `nil` when there is nothing to show (no snapshot, an old day, no habits, water not allowed in complications).
    let value: Value?

    struct Value {
        var fraction: Double
        var label: String
    }
}

/// Numbers only: never a habit name.
struct ProgressProvider: AppIntentTimelineProvider {
    /// Watch faces offer both variants when the user picks the complication.
    func recommendations() -> [AppIntentRecommendation<ProgressConfigurationIntent>] {
        [ProgressKind.habits, .water].map { kind in
            let intent = ProgressConfigurationIntent()
            intent.kind = kind
            return AppIntentRecommendation(intent: intent, description: kind == .water ? Text("Wasser") : Text("Gewohnheiten"))
        }
    }

    func placeholder(in context: Context) -> ProgressEntry {
        ProgressEntry(date: .now, kind: .habits, value: .init(fraction: 0.6, label: "3/5"))
    }

    func snapshot(for configuration: ProgressConfigurationIntent, in context: Context) async -> ProgressEntry {
        context.isPreview ? placeholder(in: context) : Self.entry(for: configuration.kind, at: .now)
    }

    func timeline(for configuration: ProgressConfigurationIntent, in context: Context) async -> Timeline<ProgressEntry> {
        let now = Date.now
        let calendar = Calendar.watch
        // Now, and at midnight, when the numbers of today are no longer valid.
        let midnight = PlanDay(date: now, calendar: calendar).adding(days: 1, calendar: calendar).startDate(in: calendar)
        return Timeline(entries: [Self.entry(for: configuration.kind, at: now), Self.entry(for: configuration.kind, at: midnight)],
                        policy: .after(midnight.addingTimeInterval(60)))
    }

    static func entry(for kind: ProgressKind, at date: Date) -> ProgressEntry {
        let calendar = Calendar.watch
        let content = WatchWidgetData.load()
        guard let original = content.original, let current = content.current,
              !original.isStale(at: date, calendar: calendar) else { return ProgressEntry(date: date, kind: kind, value: nil) }
        switch kind {
        case .habits:
            guard let counter = current.habitCounter(relativeTo: original), counter.total > 0 else {
                return ProgressEntry(date: date, kind: kind, value: nil)
            }
            return ProgressEntry(date: date, kind: kind, value: .init(fraction: WatchComplicationText.fraction(done: counter.done, goal: counter.total),
                                                                       label: WatchComplicationText.habitCounter(counter)))
        case .water:
            // Water shows only while the phone allows nutrition in the widgets, like the lock screen.
            guard let water = current.water, water.showsInComplication else { return ProgressEntry(date: date, kind: kind, value: nil) }
            return ProgressEntry(date: date, kind: kind, value: .init(fraction: WatchComplicationText.fraction(done: water.milliliters, goal: water.goalMilliliters),
                                                                       label: WatchComplicationText.liters(milliliters: water.milliliters)))
        }
    }
}

struct WatchProgressWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "tagwerk.watch.progress", intent: ProgressConfigurationIntent.self, provider: ProgressProvider()) { entry in
            ProgressComplicationView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Fortschritt")
        .description("Gewohnheiten von heute (3/5) oder dein Wasser.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct ProgressComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ProgressEntry

    private var symbol: String { entry.kind == .water ? "drop.fill" : "checkmark.circle" }

    var body: some View {
        let fraction = entry.value?.fraction ?? 0
        let label = entry.value?.label ?? "–"
        switch family {
        case .accessoryCorner:
            Text(label)
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: fraction) { Text(label) }
                }
        default:
            Gauge(value: fraction) {
                Image(systemName: symbol)
            } currentValueLabel: {
                Text(label).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
        }
    }
}
