import SwiftUI
import TagwerkCore
import WidgetKit

@main
struct TagwerkWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextUpWidget()
        TodayWidget()
        FocusLiveActivity()
    }
}

/// "Als Nächstes" (mockup W1a, W3a): small and on the lock screen; never shows nutrition.
struct NextUpWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tagwerk.nextUp", provider: SnapshotProvider()) { entry in
            NextUpView(entry: entry)
                .widgetURL(AppRoute.planToday.url)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Als Nächstes")
        .description("Dein nächster Termin oder Zeitblock und was danach kommt.")
        .supportedFamilies([.systemSmall, .accessoryRectangular, .accessoryInline])
    }
}

/// "Heute" (mockup W2a/W2b): the next entries and, when allowed, today's calories and water.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "tagwerk.today", provider: SnapshotProvider()) { entry in
            TodayView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Heute")
        .description("Die nächsten Einträge des Tages, auf Wunsch mit Kalorien und Wasser.")
        .supportedFamilies([.systemMedium])
    }
}
