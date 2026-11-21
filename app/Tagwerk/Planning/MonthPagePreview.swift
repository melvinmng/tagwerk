import SwiftUI
import TagwerkCore

/// The neighbouring month while the month grid is dragged sideways: the weekday header and the day numbers of its grid,
/// no load bars and no marks (PL7b). The page needs only the date, so nothing is loaded for it. It lays out like the
/// real grid in `MonthView` (same columns, spacing and cell height), so the page does not jump when it arrives.
struct MonthPagePreview: View {
    let model: PlanningModel
    /// Any day of the month to show.
    let anchor: PlanDay

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(DateText.shortStandaloneWeekdaySymbols(calendar: model.calendar), id: \.self) {
                Text($0).font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(PlanningModel.monthGridDays(anchor: anchor, calendar: model.calendar), id: \.self) { day in
                Text("\(day.day)")
                    .font(.callout.weight(day == model.today ? .bold : .regular))
                    .foregroundStyle(day.month == anchor.month ? .primary : .secondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(day == model.today ? Color.accentColor : .clear, lineWidth: 2))
                    .opacity(day.month == anchor.month ? 1 : 0.45)
            }
        }
        .padding(.horizontal)
        .accessibilityHidden(true)
    }
}
