import AppIntents
import SwiftUI
import TagwerkCore
import WidgetKit

struct NextUpEntry: TimelineEntry {
    let date: Date
    let next: WatchNextUp
    let relevance: TimelineEntryRelevance?
}

/// One entry per moment at which "Als Nächstes" changes (start, end, due time, midnight).
struct NextUpProvider: TimelineProvider {
    func placeholder(in context: Context) -> NextUpEntry {
        let now = Date.now
        return NextUpEntry(date: now, next: WatchNextUp.select(snapshot: WatchWidgetData.sample(now: now), now: now, calendar: .watch), relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (NextUpEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : Self.entries(from: .now).0.first ?? placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NextUpEntry>) -> Void) {
        let (entries, policy) = Self.entries(from: .now)
        completion(Timeline(entries: entries, policy: policy))
    }

    static func entries(from now: Date) -> ([NextUpEntry], TimelineReloadPolicy) {
        let calendar = Calendar.watch
        guard let snapshot = WatchWidgetData.load().current else {
            // No snapshot yet: ask to open the app on the phone and look again in an hour.
            return ([NextUpEntry(date: now, next: .stale, relevance: nil)], .after(now.addingTimeInterval(3600)))
        }
        let entries = WatchNextUp.timelineDates(snapshot: snapshot, from: now, calendar: calendar).map { date -> NextUpEntry in
            let next = WatchNextUp.select(snapshot: snapshot, now: date, calendar: calendar)
            return NextUpEntry(date: date, next: next, relevance: relevance(of: next, at: date))
        }
        return (entries, .atEnd)
    }

    /// The Smart Stack shows the card higher while something runs or starts soon.
    static func relevance(of next: WatchNextUp, at date: Date) -> TimelineEntryRelevance? {
        switch next {
        case .entry(let entry, let isRunning):
            isRunning ? TimelineEntryRelevance(score: 100, duration: max(entry.end.timeIntervalSince(date), 60))
                      : TimelineEntryRelevance(score: 60, duration: max(entry.start.timeIntervalSince(date), 60))
        case .timedTask: TimelineEntryRelevance(score: 40, duration: 1800)
        case .untimedTask: TimelineEntryRelevance(score: 10, duration: 3600)
        default: nil
        }
    }
}

struct WatchNextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tagwerk.watch.nextUp", provider: NextUpProvider()) { entry in
            NextUpView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Als Nächstes")
        .description("Dein nächster Termin, Zeitblock oder deine nächste Aufgabe.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

/// Titles and times of the items are marked privacy sensitive: with the wrist down or a locked watch they are hidden.
/// A complication shows no habit name, ever.
struct NextUpView: View {
    @Environment(\.widgetFamily) private var family
    let entry: NextUpEntry

    private var text: WatchNextUpText { WatchNextUpText.make(entry.next, calendar: .watch) }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(text.inline).privacySensitive(text.title != nil)
        case .accessoryCircular:
            VStack(spacing: 1) {
                Image(systemName: text.symbolName)
                Text(text.time ?? text.suffix ?? "").font(.caption2).minimumScaleFactor(0.6).privacySensitive()
            }
        case .accessoryCorner:
            Image(systemName: text.symbolName)
                .widgetLabel {
                    Text(text.inline).privacySensitive(text.title != nil)
                }
        default:
            rectangular
        }
    }

    private var rectangular: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 1) {
                Label(text.caption, systemImage: text.symbolName).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                if let title = text.title {
                    HStack(spacing: 4) {
                        if let time = text.time { Text(time).monospacedDigit() }
                        if let suffix = text.suffix { Text(suffix).foregroundStyle(.secondary) }
                    }
                    .font(.headline).privacySensitive()
                    Text(title).font(.caption).lineLimit(2).privacySensitive()
                }
            }
            Spacer(minLength: 0)
            if let task {
                // Interactive in the Smart Stack; on a watch face a tap opens the app instead.
                Button(intent: WatchCompleteTaskIntent(taskKey: task.key, version: task.version)) {
                    Image(systemName: "checkmark.circle")
                }
                .buttonStyle(.plain)
                .privacySensitive()
            }
        }
    }

    private var task: WatchTask? {
        switch entry.next {
        case .timedTask(let task): task
        case .untimedTask(let task, _): task
        default: nil
        }
    }
}
