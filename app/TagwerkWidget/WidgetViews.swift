import SwiftUI
import TagwerkCore
import WidgetKit

/// What a widget shows at one moment, derived from the snapshot (texts from the mockup, section "Texte").
struct WidgetContent {
    enum State {
        case stale
        case upcoming([SnapshotEntry])
        case tomorrow([SnapshotEntry])
        case nothingLeft
    }

    let state: State
    let deadlines: Int
    let intake: SnapshotIntake?
    /// Today's habit counter; only the "Heute" widget on the home screen shows it.
    let habits: SnapshotHabits?

    init(entry: SnapshotTimelineEntry, limit: Int) {
        let calendar = Calendar.widget
        guard let snapshot = entry.snapshot, !snapshot.isStale(at: entry.date, calendar: calendar) else {
            state = .stale
            deadlines = 0
            intake = nil
            habits = nil
            return
        }
        let upcoming = snapshot.upcoming(at: entry.date, calendar: calendar, limit: limit)
        if upcoming.entries.isEmpty {
            state = .nothingLeft
        } else {
            state = upcoming.isTomorrow ? .tomorrow(upcoming.entries) : .upcoming(upcoming.entries)
        }
        deadlines = snapshot.deadlineCount(at: entry.date, calendar: calendar)
        intake = snapshot.intake(at: entry.date, calendar: calendar)
        habits = snapshot.habits(at: entry.date, calendar: calendar)
    }

    static func time(_ date: Date) -> String { DateText.time(date, calendar: .widget) }

    /// "10:30–12:00"; deadlines only "18:00".
    static func span(_ entry: SnapshotEntry) -> String {
        entry.kind == .deadline || entry.end <= entry.start ? time(entry.start) : "\(time(entry.start))–\(time(entry.end))"
    }

    static func deadlineFooter(_ count: Int) -> String? {
        switch count {
        case 0: nil
        default: String(localized: "⚠︎ \(count) Deadlines heute")
        }
    }

    /// "✓ 3 von 5".
    static func habitCounter(_ counter: SnapshotHabits) -> String {
        String(localized: "✓ \(counter.done) von \(counter.total)")
    }

    static var staleText: String { String(localized: "Tagwerk öffnen, um den Plan zu laden") }
    static var nothingLeftText: String { String(localized: "Heute nichts mehr geplant") }
}

/// Small, rectangular and inline "Als Nächstes".
struct NextUpView: View {
    let entry: SnapshotTimelineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let content = WidgetContent(entry: entry, limit: 2)
        switch family {
        case .accessoryInline: inline(content)
        case .accessoryRectangular: rectangular(content)
        default: small(content)
        }
    }

    @ViewBuilder
    private func small(_ content: WidgetContent) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            switch content.state {
            case .stale:
                Image(systemName: "calendar").foregroundStyle(.secondary)
                Text(WidgetContent.staleText).font(.footnote).foregroundStyle(.secondary)
            case .nothingLeft:
                Text("ALS NÄCHSTES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(WidgetContent.nothingLeftText).font(.headline)
            case .upcoming(let entries), .tomorrow(let entries):
                if case .tomorrow = content.state {
                    Text("MORGEN").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                } else {
                    Text("ALS NÄCHSTES").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                if let first = entries.first {
                    Text(WidgetContent.span(first)).font(.subheadline.weight(.semibold).monospacedDigit())
                        // "10:30 AM–12:00 PM" is much wider than "10:30–12:00"; it shrinks instead of wrapping.
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .foregroundStyle(Color(hex: first.colorHex) ?? .accentColor)
                    Text(first.title).font(.headline).lineLimit(2).privacySensitive()
                }
                if entries.count > 1 {
                    Text("danach \(WidgetContent.time(entries[1].start)) \(entries[1].title)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                }
            }
            Spacer(minLength: 0)
            if let footer = WidgetContent.deadlineFooter(content.deadlines), !isStale(content) {
                Text(footer).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func rectangular(_ content: WidgetContent) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            switch content.state {
            case .stale:
                Text(WidgetContent.staleText).font(.caption)
            case .nothingLeft:
                Text(WidgetContent.nothingLeftText).font(.headline)
            case .tomorrow(let entries):
                if let first = entries.first {
                    HStack(spacing: 4) {
                        Text("Morgen \(WidgetContent.time(first.start))").font(.headline.monospacedDigit())
                        Text(first.title).font(.headline).lineLimit(1).privacySensitive()
                    }
                }
            case .upcoming(let entries):
                if let first = entries.first {
                    HStack(spacing: 4) {
                        Text(WidgetContent.time(first.start)).font(.headline.monospacedDigit())
                        Text(first.title).font(.headline).lineLimit(1).privacySensitive()
                    }
                }
                if entries.count > 1 {
                    HStack(spacing: 4) {
                        Text("danach \(WidgetContent.time(entries[1].start))").monospacedDigit()
                        Text(entries[1].title).lineLimit(1).privacySensitive()
                    }
                    .font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inline(_ content: WidgetContent) -> some View {
        switch content.state {
        case .stale: Text("Tagwerk öffnen")
        case .nothingLeft: Text("Nichts mehr geplant")
        case .tomorrow(let entries): Text("Morgen \(WidgetContent.time(entries[0].start)) \(entries[0].title)").privacySensitive()
        case .upcoming(let entries): Text("\(WidgetContent.time(entries[0].start)) \(entries[0].title)").privacySensitive()
        }
    }

    private func isStale(_ content: WidgetContent) -> Bool {
        if case .stale = content.state { true } else { false }
    }
}

/// Medium "Heute": entries on the left, calories and water on the right (W2a); full width without nutrition (W2b).
struct TodayView: View {
    let entry: SnapshotTimelineEntry

    var body: some View {
        let content = WidgetContent(entry: entry, limit: 4)
        // Without nutrition the counter takes the place of the fourth plan row (design §10).
        let counterBelowPlan = content.intake == nil && content.habits != nil
        HStack(alignment: .top, spacing: 12) {
            Link(destination: AppRoute.planToday.url) {
                plan(content, limit: content.intake == nil && !counterBelowPlan ? 4 : 3, showsCounter: counterBelowPlan)
            }
            if let intake = content.intake {
                Divider()
                Link(destination: AppRoute.capture.url) {
                    VStack(alignment: .leading, spacing: 6) {
                        nutrition(intake)
                        if let habits = content.habits { counter(habits) }
                    }
                    .frame(width: 118, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func plan(_ content: WidgetContent, limit: Int, showsCounter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(headerText).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            switch content.state {
            case .stale:
                Text(WidgetContent.staleText).font(.footnote).foregroundStyle(.secondary)
            case .nothingLeft:
                Text(WidgetContent.nothingLeftText).font(.subheadline)
            case .tomorrow(let entries):
                Text(WidgetContent.nothingLeftText).font(.subheadline)
                if let first = entries.first {
                    Text("Morgen \(WidgetContent.time(first.start)) \(first.title)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1).privacySensitive()
                }
            case .upcoming(let entries):
                ForEach(entries.prefix(limit)) { item in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color(hex: item.colorHex) ?? .accentColor).frame(width: 3, height: 14)
                        Text(WidgetContent.time(item.start)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Text(item.title).font(.caption).lineLimit(1).privacySensitive()
                    }
                }
            }
            Spacer(minLength: 0)
            if showsCounter, let habits = content.habits {
                Link(destination: AppRoute.capture.url) { counter(habits) }
            }
            if let footer = WidgetContent.deadlineFooter(content.deadlines) {
                Text(footer).font(.caption2.weight(.semibold)).foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "✓ 3 von 5": numbers only, never a habit name; hidden on the lock screen by `privacySensitive`.
    private func counter(_ habits: SnapshotHabits) -> some View {
        Text(WidgetContent.habitCounter(habits))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .privacySensitive()
    }

    /// Fixes the date part, e.g. "HEUTE · Mi 18 Nov" → "HEUTE · Mi 18. Nov".
    private var headerText: String {
        let parts = Calendar.widget.dateComponents([.day], from: entry.date)
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = .current
        formatter.dateFormat = "EEE"
        let weekday = formatter.string(from: entry.date).replacingOccurrences(of: ".", with: "")
        formatter.dateFormat = "MMM"
        let month = formatter.string(from: entry.date).replacingOccurrences(of: ".", with: "")
        let day = parts.day ?? 1
        return String(localized: "HEUTE · \(weekday) \(day). \(month)")
    }

    private func nutrition(_ intake: SnapshotIntake) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(IntakeFormat.kcalNumber(intake.kcal, estimated: intake.hasEstimate))
                    .font(.title3.weight(.semibold).monospacedDigit())
                Text("/ \(IntakeFormat.grouped(intake.goalKcal)) kcal").font(.caption2).foregroundStyle(.secondary)
                ProgressView(value: min(1, intake.kcal / Double(max(1, intake.goalKcal)))).tint(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(water(intake.waterMilliliters)) / \(IntakeFormat.liters(intake.goalWaterMilliliters))")
                    .font(.caption.monospacedDigit())
                ProgressView(value: min(1, Double(intake.waterMilliliters) / Double(max(1, intake.goalWaterMilliliters)))).tint(.cyan)
            }
            // Steps only on the home screen (this view); the lock-screen families never show intake values.
            if let steps = intake.steps {
                let goal = intake.goalSteps ?? 0
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal > 0 ? "\(IntakeFormat.steps(steps)) / \(IntakeFormat.grouped(goal))"
                                  : String(localized: "\(IntakeFormat.steps(steps)) Schritte"))
                        .font(.caption.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if goal > 0 {
                        ProgressView(value: min(1, Double(steps) / Double(goal))).tint(.indigo)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Schritte")
                .accessibilityValue(goal > 0 ? String(localized: "\(IntakeFormat.steps(steps)) von \(IntakeFormat.grouped(goal))")
                                             : IntakeFormat.steps(steps))
            }
        }
        .privacySensitive()
    }

    private func water(_ milliliters: Int) -> String {
        milliliters == 0 ? "0" : IntakeFormat.litersNumber(milliliters)
    }
}
