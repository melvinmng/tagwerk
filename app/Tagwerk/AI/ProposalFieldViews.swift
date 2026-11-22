import SwiftUI
import TagwerkCore

/// Small field rows that the proposal editors share.

/// A time of day (minutes since midnight) as a time picker.
struct ProposalTimeRow: View {
    let title: LocalizedStringKey
    @Binding var minutes: Int
    let calendar: Calendar

    /// A day without a daylight-saving change, so every minute of the day exists.
    private var reference: Date { calendar.date(from: DateComponents(year: 2001, month: 1, day: 2)) ?? Date(timeIntervalSince1970: 0) }

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { reference.addingTimeInterval(TimeInterval(minutes * 60)) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
    }
}

/// A calendar day as a date picker.
struct ProposalDayRow: View {
    let title: LocalizedStringKey
    @Binding var day: PlanDay
    let calendar: Calendar

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { day.startDate(in: calendar) },
            set: { day = PlanDay(date: $0, calendar: calendar) }), displayedComponents: .date)
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
    }
}

/// A day with an optional time of day as one date picker; `due.minutes == nil` means a date only.
struct ProposalMomentRow: View {
    let title: LocalizedStringKey
    @Binding var moment: ProposalDue
    let calendar: Calendar

    var body: some View {
        DatePicker(title, selection: Binding(
            get: { moment.day.startDate(in: calendar).addingTimeInterval(TimeInterval((moment.minutes ?? 0) * 60)) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                moment = ProposalDue(day: PlanDay(date: date, calendar: calendar),
                                     minutes: moment.minutes == nil ? nil : (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            }), displayedComponents: moment.minutes == nil ? .date : [.date, .hourAndMinute])
            .environment(\.calendar, calendar)
            .environment(\.timeZone, calendar.timeZone)
    }
}

extension ProposalDue {
    /// Minutes since the start of the day for ordering two moments; a date-only moment counts as its day's start.
    var orderingKey: Int { day.year * 100_000_000 + day.month * 1_000_000 + day.day * 10_000 + (minutes ?? 0) }
}
