import SwiftUI
import TagwerkCore

/// Wording of the "now" marker, shared by the grid line and the list row.
enum NowText {
    /// "14:32" in German, "2:32 PM" in US English.
    static func time(minutes: Int, calendar: Calendar, locale: Locale = .current) -> String {
        DateText.time(minutes: minutes, calendar: calendar, locale: locale)
    }

    /// The list row: "Jetzt · 14:32".
    static func rowTitle(time: String) -> String {
        String(localized: "Jetzt · \(time)")
    }

    /// What VoiceOver reads: "Jetzt, 14:32".
    static func accessibilityLabel(time: String) -> String {
        String(localized: "Jetzt, \(time)")
    }
}

/// The time of the "now" marker: white on `nowMarkerFill`, bold caption2 with monospaced digits (PL1b). The fill is
/// a capsule, not a text colour: the text keeps 4.5:1 in both appearances, which a red text on the background would not.
struct NowTimeCapsule: View {
    let time: String
    /// The width of the capsule, the label column in the grid. Nil: as wide as the text (list row).
    var width: CGFloat?
    private static let horizontalPadding: CGFloat = 2

    var body: some View {
        Text(time)
            .font(.caption2.weight(.bold).monospacedDigit()).foregroundStyle(.onNowMarker)
            // "2:32 PM" in English is wider than "14:32"; in the fixed column it shrinks instead of being cut off.
            .lineLimit(width == nil ? nil : 1).minimumScaleFactor(width == nil ? 1 : 0.6)
            // The text keeps the whole inner width, like the label it replaces (the audit reports a text that has no room).
            .frame(width: width.map { max(0, $0 - 2 * Self.horizontalPadding) })
            .padding(.horizontal, Self.horizontalPadding).padding(.vertical, 2)
            .background(.nowMarkerFill, in: Capsule())
    }
}

/// The current time in the hour grid of today: the time as a capsule in the label column and a 2-pt line.
/// Draws nothing when the shown day is not today or the time lies outside the shown hours. Moves once a minute.
struct NowLine: View {
    let model: PlanningModel
    let day: PlanDay
    let shown: Range<Int>
    let labelWidth: CGFloat
    /// Width of the whole canvas, label column included.
    let width: CGFloat

    var body: some View {
        TimelineView(.everyMinute) { _ in
            if let minutes = NowMarker.minutes(now: model.now(), day: day, calendar: model.calendar),
               let position = NowMarker.position(nowMinutes: minutes, shown: shown) {
                let time = NowText.time(minutes: minutes, calendar: model.calendar)
                HStack(spacing: 6) {
                    NowTimeCapsule(time: time, width: labelWidth)
                        // Covers the hour label when the line passes it.
                        .background(.background)
                    Rectangle().fill(.nowMarkerFill).frame(height: 2)
                }
                .frame(width: width)
                .offset(y: TimelineCanvas.y(position, shown) - 7)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(NowText.accessibilityLabel(time: time))
                // A marker without an action: the audit must not measure it as a control.
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The "Jetzt · 14:32" row in the list mode of today: the same capsule and a 2-pt line; no action, no separator.
struct NowRow: View {
    let minutes: Int
    let calendar: Calendar

    var body: some View {
        let time = NowText.time(minutes: minutes, calendar: calendar)
        HStack(spacing: 8) {
            NowTimeCapsule(time: NowText.rowTitle(time: time))
            Rectangle().fill(.nowMarkerFill).frame(height: 2)
        }
        .frame(minHeight: 20)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NowText.accessibilityLabel(time: time))
    }
}

/// The "now" row as one list row (or nothing); its time updates itself every minute.
struct NowRowSlot: View {
    let model: PlanningModel
    let day: PlanDay
    let isShown: Bool

    var body: some View {
        if isShown {
            TimelineView(.everyMinute) { _ in
                if let minutes = NowMarker.minutes(now: model.now(), day: day, calendar: model.calendar) {
                    NowRow(minutes: minutes, calendar: model.calendar)
                }
            }
            .id("now-row")
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
        }
    }
}

/// List mode of today: bumps `tick` every minute (the row index is recomputed, not the rows) and scrolls to the
/// "now" row once when a day opens; later reloads leave the position alone.
struct NowListBehavior: ViewModifier {
    let model: PlanningModel
    let day: PlanDay
    @Binding var tick: Int
    /// Off in the preview of a neighbour page: it neither scrolls nor ticks.
    var isEnabled = true
    /// The day this list first showed: only that day is scrolled to the current time, and only when it is today.
    @State private var openedDay: PlanDay?
    @State private var scrolledFor: PlanDay?

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .task(id: day) {
                    guard isEnabled else { return }
                    if openedDay == nil { openedDay = day }
                    guard NowMarker.alignsOnOpening(openedDay: openedDay, shownDay: day, today: model.today),
                          scrolledFor != day else { return }
                    await Task.yield()
                    withAnimation(nil) { proxy.scrollTo("now-row", anchor: UnitPoint(x: 0.5, y: 0.33)) }
                    scrolledFor = day
                }
                .task {
                    guard isEnabled else { return }
                    while !Task.isCancelled {
                        let secondsToNextMinute = 60 - Int(Date.now.timeIntervalSince1970) % 60
                        try? await Task.sleep(for: .seconds(secondsToNextMinute))
                        tick &+= 1
                    }
                }
        }
    }
}

extension PlanningModel {
    /// Start of a timeline row in minutes of the day, for placing the "now" row. Mirrors the ordering of
    /// `timelineWithGaps(for:)`.
    func startMinutes(of row: TimelineRow, on day: PlanDay) -> Int {
        let dayStart = day.startDate(in: calendar)
        switch row {
        case .event(let event), .block(let event, _): return Int(event.start.timeIntervalSince(dayStart) / 60)
        case .lunch(let start, _): return start
        case .gap(let range): return range.lowerBound
        case .travel(let segment): return segment.range.lowerBound
        }
    }

    /// Index in `rows` before which the "now" row goes; nil when the day is not today or has no rows.
    func nowRowIndex(in rows: [TimelineRow], on day: PlanDay) -> Int? {
        guard !rows.isEmpty, let minutes = NowMarker.minutes(now: now(), day: day, calendar: calendar) else { return nil }
        return NowMarker.insertionIndex(rowStarts: rows.map { startMinutes(of: $0, on: day) }, nowMinutes: minutes)
    }
}
