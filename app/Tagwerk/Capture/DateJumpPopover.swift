import SwiftUI
import TagwerkCore

/// Month calendar to jump to a day or week, styled like the date picker in "Planen" (mockup A1).
/// Only days up to today can be picked; picking closes the popover.
struct DateJumpPopover: View {
    let selected: PlanDay
    let today: PlanDay
    let calendar: Calendar
    let todayTitle: LocalizedStringKey
    let onPick: (PlanDay) -> Void

    var body: some View {
        VStack(spacing: 8) {
            DatePicker("Datum", selection: date, in: ...today.startDate(in: calendar), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, calendar)
            HStack {
                Button(todayTitle) { onPick(today) }
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .frame(minWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    private var date: Binding<Date> {
        Binding(get: { selected.startDate(in: calendar) },
                set: { onPick(PlanDay(date: $0, calendar: calendar)) })
    }
}
