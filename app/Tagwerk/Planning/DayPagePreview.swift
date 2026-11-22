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
                        weekRows(of: plan)
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

    /// The rows the shown week has for this day, in the same order and rows, without interaction.
    @ViewBuilder
    private func weekRows(of plan: DayPlan) -> some View {
        let content = model.weekContent(for: plan)
        let marks = DayPageExtras(deadlineEventIDs: Set(content.timed.compactMap { $0.deadline?.eventID }))
        VStack(alignment: .leading, spacing: 8) {
            ForEach(content.allDay) { event in
                TimelineLine(time: "", title: event.title, detail: String(localized: "Ganztägig"), color: event.isBusy ? .blue : .gray) {
                    EmptyView()
                }
            }
            ForEach(content.timed) { entry in
                if let taskID = entry.taskID {
                    BlockEntryRow(model: model, plan: plan, event: entry.event, taskID: taskID, marks: marks, trips: entry.trips) {}
                } else {
                    EventEntryRow(model: model, day: plan.day, event: entry.event, marks: marks, trips: entry.trips) {}
                }
            }
            ForEach(plan.assigned) { task in Text(task.title).font(.subheadline).lineLimit(1) }
            ForEach(content.deadlines) { deadline in
                Text(deadline.title).font(.subheadline).foregroundStyle(.red).lineLimit(1)
            }
        }
    }
}
