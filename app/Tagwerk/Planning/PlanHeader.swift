import SwiftUI
import TagwerkCore

/// Texts of the "Planen" header (mockup PK2): title, caption, current period and arrow labels.
enum PlanHeaderText {
    /// The shown period contains today; a month only when it is today's month, not a neighbour whose grid shows today.
    static func isCurrent(scope: PlanScope, anchor: PlanDay, today: PlanDay, range: ClosedRange<PlanDay>) -> Bool {
        guard range.contains(today) else { return false }
        return scope != .month || (anchor.month == today.month && anchor.year == today.year)
    }

    /// The anchor one page further (`step` ±1): a day, a week or a month, as `PlanningModel.step` moves it.
    static func shiftedAnchor(scope: PlanScope, anchor: PlanDay, step: Int, calendar: Calendar) -> PlanDay {
        switch scope {
        case .day: anchor.adding(days: step, calendar: calendar)
        case .week: anchor.adding(days: 7 * step, calendar: calendar)
        case .month:
            calendar.date(byAdding: .month, value: step, to: anchor.startDate(in: calendar))
                .map { PlanDay(date: $0, calendar: calendar) } ?? anchor
        }
    }

    /// Day "Mittwoch, 18. Nov.", week "16.–22. Nov.", month "November".
    static func title(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar, locale: Locale = .current) -> String {
        let start = anchor.startDate(in: calendar)
        switch scope {
        case .day:
            return start.formatted(.dateTime.weekday(.wide).day().month(.abbreviated).locale(locale))
        case .week:
            // The interval style orders day and month as the language does: "16.–22. Nov." / "Nov 16 – 22".
            let first = range.lowerBound.startDate(in: calendar), last = range.upperBound.startDate(in: calendar)
            return (first..<last).formatted(.interval.day().month(.abbreviated).locale(locale))
        case .month:
            return start.formatted(.dateTime.month(.wide).locale(locale))
        }
    }

    /// The title in decreasing length, longest first; the first is `title(...)`. The header shows the longest one
    /// that fits, so the title is never cut off with an ellipsis:
    /// day "Donnerstag, 19. Nov." → "Do. 19. Nov." → "19. Nov.", week "16.–22. Nov." → "16.–22.11.", month "November" → "Nov".
    static func titleCandidates(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar,
                                locale: Locale = .current) -> [String] {
        let start = anchor.startDate(in: calendar)
        var candidates = [title(scope: scope, anchor: anchor, range: range, calendar: calendar, locale: locale)]
        switch scope {
        case .day:
            candidates.append(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale)))
            candidates.append(start.formatted(.dateTime.day().month(.abbreviated).locale(locale)))
        case .week:
            let first = range.lowerBound.startDate(in: calendar), last = range.upperBound.startDate(in: calendar)
            candidates.append((first..<last).formatted(.interval.day().month(.twoDigits).locale(locale)))
        case .month:
            candidates.append(start.formatted(.dateTime.month(.abbreviated).locale(locale)))
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    /// The longest candidate that is not wider than `availableWidth`; the shortest when none fits. The candidates run
    /// from the longest to the shortest form (`titleCandidates`).
    static func fittingTitle(_ candidates: [String], availableWidth: CGFloat, width: (String) -> CGFloat) -> String {
        candidates.first { width($0) <= availableWidth } ?? candidates.last ?? ""
    }

    /// The title the header shows. `ViewThatFits` in a toolbar item gets no usable width (it always took the
    /// shortest candidate, seen on the iPhone 17 simulator), so the width is computed: with `availableWidth` the longest
    /// form that fits is shown (PL16b), measured in the font of the title, so the same rule holds at every text size.
    /// Without it (`nil`, the fallback PL16a) the form is fixed: the day view takes the middle candidate, the others the
    /// full one, and with accessibility text sizes everything takes the shortest.
    static func displayedTitle(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar,
                               largeText: Bool, availableWidth: CGFloat? = nil, locale: Locale = .current,
                               width: (String) -> CGFloat = { PlanHeaderMetrics.titleWidth($0) }) -> String {
        let candidates = titleCandidates(scope: scope, anchor: anchor, range: range, calendar: calendar, locale: locale)
        if let availableWidth { return fittingTitle(candidates, availableWidth: availableWidth, width: width) }
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
    /// Width of the window, 0 before it is known; the title takes the longest form that fits next to the buttons (PL16b).
    var windowWidth: CGFloat = 0
    @State private var picking = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // While a neighbour page prevails during a drag, the header already shows its period (PL6b).
        let anchor = model.titleAnchor, range = model.titleRange
        let current = PlanHeaderText.isCurrent(scope: model.scope, anchor: anchor, today: model.today, range: range)
        let caption = PlanHeaderText.caption(scope: model.scope, anchor: anchor, today: model.today,
                                             range: range, calendar: model.calendar)
        let title = PlanHeaderText.title(scope: model.scope, anchor: anchor, range: range, calendar: model.calendar)
        let shown = PlanHeaderText.displayedTitle(scope: model.scope, anchor: anchor, range: range,
                                                  calendar: model.calendar, largeText: typeSize.isAccessibilitySize,
                                                  availableWidth: windowWidth > 0
                                                      ? PlanHeaderMetrics.availableTitleWidth(windowWidth: windowWidth, typeSize: typeSize) : nil,
                                                  width: { PlanHeaderMetrics.titleWidth($0, typeSize: typeSize) })
        Button { picking = true } label: {
            // VoiceOver always reads the full title (below).
            PageTitleLabel(caption: caption, title: shown, isCurrent: current, titleScales: false).fixedSize()
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.15), value: shown)
        }
        .sensoryFeedback(.selection, trigger: model.titlePreviewStep)
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
                .foregroundStyle(.secondaryText)
                // One footnote line is about 16 pt high; the audit reports a hit area under 44 pt.
                .minimumTapTarget()
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet Erfassen")
        }
    }
}

/// Measurements for the title of the plan header (PL16b).
enum PlanHeaderMetrics {
    /// Width that the three trailing bar buttons, the chevron of the title, the gaps and the margins take. Measured on the
    /// simulators iPhone 17e, 18 Pro and 18 Pro Max with `PlanHeaderLayoutUITests` (the first guess, 196, let the title touch
    /// the buttons on the iPhone 18 Pro): the buttons start 169 to 173 pt from the trailing edge, the title starts 16 to 20 pt
    /// from the leading edge, its chevron takes about 20 pt, and 8 pt stay free between them.
    static let trailingReserve: CGFloat = 220
    /// The same above the default text size: the buttons and the chevron grow (up to 185 pt and 26 pt).
    static let trailingReserveLargeText: CGFloat = 240

    /// Width the title text may take in a window of `windowWidth`. `nil` switches the measurement off: the title then
    /// keeps its fixed form (fallback PL16a).
    static func availableTitleWidth(windowWidth: CGFloat, typeSize: DynamicTypeSize = .large) -> CGFloat? {
        max(0, windowWidth - (typeSize > .large ? trailingReserveLargeText : trailingReserve))
    }

    /// Width of a title in the header font (bold title3), measured with UIKit. `typeSize` is the text size the view
    /// renders with (an app-wide override does not reach UIKit); `nil` uses the size of the system.
    static func titleWidth(_ text: String, typeSize: DynamicTypeSize? = nil) -> CGFloat {
        // The navigation bar stops growing its text early: the title is exactly as wide at XXXL and at accessibility sizes
        // (214 pt for "Samstag, 21. Nov.", measured with `PlanHeaderLayoutUITests`, about the size of XXL), so the
        // measurement stops there as well. A larger measurement would only choose a shorter form than needed.
        let traits = typeSize.map { UITraitCollection(preferredContentSizeCategory: min($0, .xxLarge).contentSizeCategory) }
        let base = UIFont.preferredFont(forTextStyle: .title3, compatibleWith: traits)
        let font = base.fontDescriptor.withSymbolicTraits(.traitBold).map { UIFont(descriptor: $0, size: base.pointSize) } ?? base
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
