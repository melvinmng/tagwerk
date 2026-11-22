import SwiftUI
import TagwerkCore

/// "Wochenplanung" in "Planen" on the planning day (RO15b): an entry next to the card "Tagesstart", in the same pattern. The two
/// other entries (the weekly review and the wrap-up of a Sunday) stay.
struct WeekPlanningCard: View {
    let model: RoutinesModel

    var body: some View {
        if model.showsWeekPlanningCard {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Wochenplanung").font(.footnote.weight(.semibold))
                    Text(Self.subtitle(today: model.today, calendar: model.calendar)).font(.footnote).foregroundStyle(.secondaryText)
                }
                // Two lines instead of cutting the text off.
                .lineLimit(3)
                Spacer(minLength: 4)
                Button("Starten") { model.openWeek() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button { model.hideWeekPlanningCardToday() } label: { Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondaryText)
                    .accessibilityLabel("Heute ausblenden")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    /// "Rückblick auf KW 47, dann KW 48 planen · etwa 10 min".
    static func subtitle(today: PlanDay, calendar: Calendar) -> String {
        let reviewed = weekNumber(WeekPlanningRules.reviewedWeekStart(today: today, calendar: calendar), calendar: calendar)
        let planned = weekNumber(WeekPlanningRules.plannedWeekStart(today: today, calendar: calendar), calendar: calendar)
        return String(localized: "Rückblick auf KW \(reviewed), dann KW \(planned) planen · etwa 10 min")
    }

    private static func weekNumber(_ monday: PlanDay, calendar: Calendar) -> Int {
        calendar.component(.weekOfYear, from: monday.startDate(in: calendar))
    }
}
