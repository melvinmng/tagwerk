import SwiftUI
import TagwerkCore

/// Texts of the "Planen" header (mockup PK2): title, caption, current period and arrow labels.
enum PlanHeaderText {
    /// The shown period contains today; a month only when it is today's month, not a neighbour whose grid shows today.
    static func isCurrent(scope: PlanScope, anchor: PlanDay, today: PlanDay, range: ClosedRange<PlanDay>) -> Bool {
        guard range.contains(today) else { return false }
        return scope != .month || (anchor.month == today.month && anchor.year == today.year)
    }

    /// Day "Mittwoch, 18. Nov.", week "16.–22. Nov.", month "November".
    static func title(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar) -> String {
        let start = anchor.startDate(in: calendar)
        switch scope {
        case .day:
            return start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
        case .week:
            // The interval style orders day and month as the language does: "16.–22. Nov." / "Nov 16 – 22".
            let first = range.lowerBound.startDate(in: calendar), last = range.upperBound.startDate(in: calendar)
            return (first..<last).formatted(.interval.day().month(.abbreviated))
        case .month:
            return start.formatted(.dateTime.month(.wide))
        }
    }

    /// The title in decreasing length, longest first; the first is `title(...)`. The header shows the longest one
    /// that fits, so the title is never cut off with an ellipsis:
    /// day "Donnerstag, 19. Nov." → "Do. 19. Nov." → "19. Nov.", week "16.–22. Nov." → "16.–22.11.", month "November" → "Nov".
    static func titleCandidates(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar) -> [String] {
        let start = anchor.startDate(in: calendar)
        var candidates = [title(scope: scope, anchor: anchor, range: range, calendar: calendar)]
        switch scope {
        case .day:
            candidates.append(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
            candidates.append(start.formatted(.dateTime.day().month(.abbreviated)))
        case .week:
            let first = range.lowerBound.startDate(in: calendar), last = range.upperBound.startDate(in: calendar)
            candidates.append((first..<last).formatted(.interval.day().month(.twoDigits)))
        case .month:
            candidates.append(start.formatted(.dateTime.month(.abbreviated)))
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// The title the header shows. `ViewThatFits` in a toolbar item gets no usable width (it always took the
    /// shortest candidate, seen on the iPhone 17 simulator), so the form is fixed: the day view takes the middle
    /// candidate, the others the full one, and with accessibility text sizes everything takes the shortest.
    static func displayedTitle(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar,
                               largeText: Bool) -> String {
        let candidates = titleCandidates(scope: scope, anchor: anchor, range: range, calendar: calendar)
        if largeText { return candidates[candidates.count - 1] }
        return scope == .day && candidates.count > 1 ? candidates[1] : candidates[0]
    }

    /// Day "HEUTE · KW 47", week "DIESE WOCHE · KW 47", month "DIESER MONAT · 2026".
    static func caption(scope: PlanScope, anchor: PlanDay, today: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar) -> String {
        let week = calendar.component(.weekOfYear, from: anchor.startDate(in: calendar))
        let current = isCurrent(scope: scope, anchor: anchor, today: today, range: range)
        switch scope {
        case .day:
            let distance = calendar.dateComponents([.day], from: today.startDate(in: calendar), to: anchor.startDate(in: calendar)).day ?? 0
            let relative: String = switch distance {
            case 0: String(localized: "Heute")
            case 1: String(localized: "Morgen")
            case -1: String(localized: "Gestern")
            case let days where days > 1: String(localized: "In \(days) Tagen")
            default: String(localized: "Vor \(-distance) Tagen")
            }
            return "\(relative) · \(String(localized: "KW \(week)"))".uppercased()
        case .week:
            return (current ? String(localized: "Diese Woche · KW \(week)") : String(localized: "KW \(week)")).uppercased()
        case .month:
            let year = String(anchor.year)
            return (current ? String(localized: "Dieser Monat · \(year)") : year).uppercased()
        }
    }

    /// "~1.240 / 2.300 kcal · 2,1 l · ✓ 3 von 5"; the counter alone when there is no intake text, `nil` without both.
    static func statusLine(intake: String?, habits: HabitCounter?) -> String? {
        let parts = [intake, habits.map(habitCounter)].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "✓ 3 von 5".
    static func habitCounter(_ counter: HabitCounter) -> String {
        String(localized: "✓ \(counter.done) von \(counter.total)")
    }

    static func stepLabel(scope: PlanScope, direction: Int) -> String {
        switch (scope, direction < 0) {
        case (.day, true): String(localized: "Vorheriger Tag")
        case (.day, false): String(localized: "Nächster Tag")
        case (.week, true): String(localized: "Vorherige Woche")
        case (.week, false): String(localized: "Nächste Woche")
        case (.month, true): String(localized: "Vorheriger Monat")
        case (.month, false): String(localized: "Nächster Monat")
        }
    }
}

/// Leading item of the navigation bar (PK2): caption above the date title, ▾ opens the month picker.
struct PlanTitleButton: View {
    @Bindable var model: PlanningModel
    @State private var picking = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let current = PlanHeaderText.isCurrent(scope: model.scope, anchor: model.anchor, today: model.today, range: model.range)
        let caption = PlanHeaderText.caption(scope: model.scope, anchor: model.anchor, today: model.today,
                                             range: model.range, calendar: model.calendar)
        let title = PlanHeaderText.title(scope: model.scope, anchor: model.anchor, range: model.range, calendar: model.calendar)
        let shown = PlanHeaderText.displayedTitle(scope: model.scope, anchor: model.anchor, range: model.range,
                                                  calendar: model.calendar, largeText: typeSize.isAccessibilitySize)
        Button { picking = true } label: {
            // VoiceOver always reads the full title (below).
            PageTitleLabel(caption: caption, title: shown, isCurrent: current, titleScales: false).fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(caption.capitalized)
        .accessibilityHint("Datum wählen")
        .accessibilityAddTraits(.isHeader)
        .popover(isPresented: $picking) {
            DateJumpPopover(selected: model.anchor, today: model.today, calendar: model.calendar, todayTitle: "Heute",
                            secondaryTitle: model.scope == .month ? nil : "Monatsansicht ›",
                            onSecondary: { picking = false; model.scope = .month }) { day in
                model.jump(to: day)
                picking = false
            }
        }
    }
}

/// Control row below the bar (PK2): Tag / Woche / Monat, "Heute" while another period is shown, arrows.
struct PlanControlRow: View {
    @Bindable var model: PlanningModel

    var body: some View {
        let current = PlanHeaderText.isCurrent(scope: model.scope, anchor: model.anchor, today: model.today, range: model.range)
        HStack(spacing: 8) {
            Picker("Ansicht", selection: $model.scope) {
                ForEach(PlanScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            if !current { PageTodayButton { model.showToday() } }
            PageArrowCapsule(backLabel: PlanHeaderText.stepLabel(scope: model.scope, direction: -1),
                             forwardLabel: PlanHeaderText.stepLabel(scope: model.scope, direction: 1)) { model.step($0.step) }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
    }
}

/// Phase 4 (mockup P1a): calories and water of today in the day view, from the first entry of the day.
struct PlanIntakeLine: View {
    let model: PlanningModel
    /// The day of the page the line belongs to (a neighbour page is not the model's anchor).
    var day: PlanDay?
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        let intake = environment.capture.planHeaderLine
        if model.scope == .day, (day ?? model.anchor) == model.today,
           let line = PlanHeaderText.statusLine(intake: intake, habits: environment.habits.todayCounter) {
            Button { environment.router.open(.capture) } label: {
                HStack(spacing: 4) {
                    // The flame belongs to the nutrition text; the habit counter may stand alone.
                    if intake != nil { Image(systemName: "flame.fill").foregroundStyle(.orange) }
                    Text(line).monospacedDigit()
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet Erfassen")
        }
    }
}
