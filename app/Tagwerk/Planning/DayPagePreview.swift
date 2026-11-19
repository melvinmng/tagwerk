import SwiftUI
import TagwerkCore

/// The neighbouring day while the page is dragged (#134): the real hour grid or list of that day from its
/// preloaded plan, without any interaction. Without a plan yet it shows the date and a progress indicator.
struct DayPagePreview: View {
    let model: PlanningModel
    let day: PlanDay
    let plan: DayPlan?
    let showsGrid: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                title
                if let plan {
                    capacity(plan)
                    Text("Ablauf").font(.headline)
                    if showsGrid { grid(plan) } else { list(plan) }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 80)
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

    private var title: some View {
        let range = day...day
        return VStack(alignment: .leading, spacing: 0) {
            Text(PlanHeaderText.caption(scope: .day, anchor: day, today: model.today, range: range, calendar: model.calendar))
                .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(PlanHeaderText.title(scope: .day, anchor: day, range: range, calendar: model.calendar))
                .font(.title3.bold())
        }
    }

    private func capacity(_ plan: DayPlan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(plan.isPast ? String(localized: "Vergangen") : CapacityText.remaining(plan.capacity)).font(.headline)
            CapacityBar(capacity: plan.capacity)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func grid(_ plan: DayPlan) -> some View {
        var entries: [DayEntry] = plan.events.filter { !$0.isAllDay }.map { .event($0, nil) }
        entries += plan.blocks.map { .event($0, plan.links[$0.id]) }
        if !plan.capacity.isDayOff, let lunch = model.lunch(on: plan.day) { entries.append(.lunch(day: plan.day, range: lunch)) }
        return TimelineCanvas(model: model, plan: plan, entries: entries, selectingIDs: nil, taskPreview: nil,
                              onTap: { _ in }, onToggleSelection: { _ in }, onCommit: { _ in }, isDragging: .constant(false))
    }

    @ViewBuilder
    private func list(_ plan: DayPlan) -> some View {
        let rows = model.timelineWithGaps(for: plan)
        if rows.isEmpty { Text("Keine Termine").foregroundStyle(.secondary) }
        ForEach(rows) { row in
            if case .gap = row { EmptyView() } else {
                HStack(alignment: .top, spacing: 10) {
                    Text(DateText.time(minutes: model.startMinutes(of: row, on: plan.day), calendar: model.calendar))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                    Text(row.label)
                }
            }
        }
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
