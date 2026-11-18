import SwiftUI
import TagwerkCore

/// Month calendar to jump to a day or week (mockup A1, PK2, EK1), shared by "Planen", "Erfassen" and the review.
/// `latest` limits the choice (only back in time in "Erfassen"); picking closes the popover.
struct DateJumpPopover: View {
    let selected: PlanDay
    let today: PlanDay
    var latest: PlanDay?
    let calendar: Calendar
    let todayTitle: LocalizedStringKey
    var secondaryTitle: LocalizedStringKey?
    var onSecondary: (() -> Void)?
    let onPick: (PlanDay) -> Void

    var body: some View {
        VStack(spacing: 8) {
            picker
                .datePickerStyle(.graphical)
                .environment(\.calendar, calendar)
            HStack {
                Button(todayTitle) { onPick(today) }
                Spacer()
                if let secondaryTitle, let onSecondary { Button(secondaryTitle, action: onSecondary) }
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .frame(minWidth: 320)
        .presentationCompactAdaptation(.popover)
    }

    @ViewBuilder
    private var picker: some View {
        if let latest {
            DatePicker("Datum", selection: date, in: ...latest.startDate(in: calendar), displayedComponents: .date)
        } else {
            DatePicker("Datum", selection: date, displayedComponents: .date)
        }
    }

    private var date: Binding<Date> {
        Binding(get: { selected.startDate(in: calendar) },
                set: { onPick(PlanDay(date: $0, calendar: calendar)) })
    }
}
