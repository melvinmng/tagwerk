import SwiftUI
import TagwerkCore

/// The neighbouring day beside the shown page while its plan is not loaded yet: the date and a progress indicator.
/// Once the plan is there, the preview is the real page itself (`DayView.preview(of:)`).
struct DayPagePreview: View {
    let model: PlanningModel
    let day: PlanDay

    var body: some View {
        let range = day...day
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(PlanHeaderText.caption(scope: .day, anchor: day, today: model.today, range: range, calendar: model.calendar))
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(PlanHeaderText.title(scope: .day, anchor: day, range: range, calendar: model.calendar))
                    .font(.title3.bold())
            }
            ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background(Color(.systemBackground), ignoresSafeAreaEdges: [])
    }
}

/// The neighbouring week while the page is dragged: one row per day with capacity and planned tasks, no interaction.
struct WeekPagePreview: View {
    let model: PlanningModel
    let weekStart: PlanDay
    let plans: [DayPlan]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if plans.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
                }
                ForEach(plans) { plan in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(plan.day.startDate(in: model.calendar).formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(CapacityText.summary(plan.capacity)).font(.caption)
                                .foregroundStyle(plan.capacity.isOverbooked ? .red : .secondary)
                        }
                        CapacityBar(capacity: plan.capacity)
                        ForEach(plan.assigned) { task in Text(task.title).font(.subheadline).lineLimit(1) }
                        ForEach(plan.deadlines) { deadline in
                            Text(deadline.title).font(.subheadline).foregroundStyle(.red).lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollDisabled(true)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background(Color(.systemBackground))
    }
}
