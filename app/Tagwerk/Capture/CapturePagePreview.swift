import SwiftUI
import TagwerkCore

/// The neighbouring week of the weekly review while the page is dragged: only the week title.
struct WeekReviewPagePreview: View {
    let model: WeekReviewModel
    let weekStart: PlanDay

    var body: some View {
        let range = weekStart...weekStart.adding(days: 6, calendar: model.calendar)
        VStack(alignment: .leading, spacing: 0) {
            Text(PlanHeaderText.caption(scope: .week, anchor: weekStart, today: model.today, range: range, calendar: model.calendar))
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondaryText)
            Text(PlanHeaderText.title(scope: .week, anchor: weekStart, range: range, calendar: model.calendar)).font(.title3.bold())
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 120)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(.systemGroupedBackground))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
