import SwiftUI
import TagwerkCore

/// One entry of a day as a list row: time, colour bar, title and a detail line, with an optional accessory under the
/// detail. The day list and the week view use this row, so both read the same.
struct TimelineLine<Accessory: View>: View {
    /// The clock time of the entry; empty for an all-day event (the column stays, so titles line up).
    let time: String
    let title: String
    let detail: String
    let color: Color
    /// The entry runs now: the colour bar is wider (PL3c).
    let isRunning: Bool
    let accessory: Accessory

    init(time: String, title: String, detail: String, color: Color, isRunning: Bool = false,
         @ViewBuilder accessory: () -> Accessory) {
        self.time = time
        self.title = title
        self.detail = detail
        self.color = color
        self.isRunning = isRunning
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(time)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: isRunning ? 6 : 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                accessory
            }
        }
        .accessibilityElement(children: .combine)
    }
}

extension TimelineLine where Accessory == EmptyView {
    init(time: Date, title: String, detail: String, color: Color, isRunning: Bool = false) {
        self.init(time: time.formatted(date: .omitted, time: .shortened), title: title, detail: detail, color: color,
                  isRunning: isRunning) { EmptyView() }
    }
}

extension TimelineLine {
    init(time: Date, title: String, detail: String, color: Color, isRunning: Bool = false,
         @ViewBuilder accessory: () -> Accessory) {
        self.init(time: time.formatted(date: .omitted, time: .shortened), title: title, detail: detail, color: color,
                  isRunning: isRunning, accessory: accessory)
    }
}

/// The trips of an entry under its detail line: "Los 15:05 · 25 min" with the way there, "25 min nach Hause" for the way
/// back, and the capsule "10 min zu früh" behind a trip that starts before the previous event ends. In the day list the
/// trips are rows of their own (`TravelRow`); the week keeps one row per entry and shows them compactly here.
struct TimelineTrips: View {
    let trips: [TravelSegment]
    let transport: TravelTransport
    let day: PlanDay
    let calendar: Calendar

    var body: some View {
        ForEach(trips) { trip in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Label(TravelText.gridText(trip, departure: clock(trip.range.lowerBound)), systemImage: TravelText.symbol(trip.transport ?? transport))
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityLabel(TravelText.accessibilityLabel(trip, transport: trip.transport ?? transport))
                if trip.isTight { TravelWarningCapsule(minutes: trip.overlapMinutes) }
            }
        }
    }

    private func clock(_ minutes: Int) -> String {
        day.startDate(in: calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// An event as a row of the day list and the week: button to its sheet, with the marks of deadlines and preparation.
struct EventEntryRow: View {
    let model: PlanningModel
    let day: PlanDay
    let event: CalendarEvent
    let marks: DayPageExtras
    /// The trips shown under the event (week); the day list has rows of their own for them.
    var trips: [TravelSegment] = []
    let onOpen: () -> Void

    var body: some View {
        let isDeadline = marks.deadlineEventIDs.contains(event.id)
        let remaining = model.runningRemaining(of: event, on: day)
        Button(action: onOpen) {
            TimelineLine(time: event.start, title: (isDeadline ? "⚑ " : "") + event.title,
                         detail: detail(remaining: remaining),
                         color: isDeadline ? .red : (event.isBusy ? .blue : .gray), isRunning: remaining != nil) {
                TimelineTrips(trips: trips, transport: model.settings.travelTransport, day: day, calendar: model.calendar)
            }
        }
        .foregroundStyle(.primary)
    }

    private func detail(remaining: Int?) -> String {
        // A running entry shows what is left instead of its end (PL3c).
        var parts = [remaining.map { NowText.runningDetail(remainingMinutes: $0) }
            ?? String(localized: "bis \(event.end.formatted(date: .omitted, time: .shortened))")]
        if !event.isBusy { parts.append(String(localized: "Frei")) }
        if !event.mergedCalendarIDs.isEmpty { parts.append(String(localized: "\(event.mergedCalendarIDs.count + 1) Kalender")) }
        let text = DeadlineText(calendar: model.calendar)
        if marks.deadlineEventIDs.contains(event.id) {
            parts.append(text.timelineMark(isMarked: !model.isInDeadlineCalendar(event)))
        }
        if let target = marks.preparationTargets[event.id] {
            parts.append(text.preparationMark(target, today: model.today))
        }
        return parts.joined(separator: " · ")
    }
}

/// A time block of a task as a row of the day list and the week, with the focus button of the block that is next (FO4b).
struct BlockEntryRow: View {
    let model: PlanningModel
    let plan: DayPlan
    let event: CalendarEvent
    let taskID: TaskID
    let marks: DayPageExtras
    var trips: [TravelSegment] = []
    let onOpen: () -> Void

    var body: some View {
        let remaining = model.runningRemaining(of: event, on: plan.day)
        let trimmed = marks.trimmedBlocks[event.id]
        HStack(spacing: 8) {
            Button(action: onOpen) {
                TimelineLine(time: event.start,
                             title: (trimmed != nil ? "✓ " : "")
                                 + (plan.day == model.today && model.focusTaskIDs.contains(taskID) ? "★ " : "") + event.title,
                             detail: trimmed.map { FocusTimerText.trimDetail($0) } ?? runningOrPlannedDetail(remaining: remaining),
                             color: .green, isRunning: remaining != nil) {
                    TimelineTrips(trips: trips, transport: model.settings.travelTransport, day: plan.day, calendar: model.calendar)
                }
            }
            .foregroundStyle(.primary)
            // The button of the focus (FO4b) next to the row, not inside its button.
            if model.focusBlockID(in: plan) == event.id { FocusPlanButton(event: event, model: model) }
        }
    }

    private func runningOrPlannedDetail(remaining: Int?) -> String {
        (remaining.map { NowText.runningDetail(remainingMinutes: $0) }
            ?? CapacityText.duration(Int(event.end.timeIntervalSince(event.start) / 60))) + " · "
            + (model.canEditAsBlock(event) ? String(localized: "Zeitblock") : String(localized: "verknüpft"))
    }
}
