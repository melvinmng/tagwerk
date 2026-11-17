import SwiftUI
import TagwerkCore

/// Week view (mockup b-A): days as rows with capacity, deadlines and planned tasks; drop targets.
struct WeekView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    @State private var targetedDay: PlanDay?

    var body: some View {
        List {
            ForEach(model.days) { plan in
                Section {
                    ForEach(plan.assigned) { task in
                        PlannedTaskRow(task: task, isPastDue: plan.isPastDue.contains(task.id))
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenTask(task.id) }
                    }
                    ForEach(plan.deadlines) { deadline in
                        Label(deadline.title, systemImage: "flag.fill").foregroundStyle(.red).font(.subheadline)
                    }
                    if plan.assigned.isEmpty && plan.deadlines.isEmpty {
                        Text(targetedDay == plan.day ? "Hier ablegen" : "–").foregroundStyle(.secondary).font(.caption)
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(plan.day.startDate(in: model.calendar).formatted(.dateTime.weekday(.abbreviated).day()))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(plan.day == model.today ? Color.accentColor : .primary)
                            Spacer()
                            Text(CapacityText.summary(plan.capacity))
                                .font(.caption)
                                .foregroundStyle(plan.capacity.isOverbooked ? .red : .secondary)
                        }
                        CapacityBar(capacity: plan.capacity)
                    }
                    .textCase(nil)
                }
                .dropDestination(for: String.self) { keys, _ in
                    let ids = keys.compactMap(TaskID.init(key:))
                    Task { for id in ids { await model.assign(id, to: plan.day) } }
                    return !ids.isEmpty
                } isTargeted: { targeted in
                    targetedDay = targeted ? plan.day : (targetedDay == plan.day ? nil : targetedDay)
                }
            }
        }
        .safeAreaInset(edge: .bottom) { UnplannedTray(model: model) }
    }
}

/// Unplanned tasks to drag onto days (mockup b-A); dragging is never the only way (see the menu).
struct UnplannedTray: View {
    let model: PlanningModel

    var body: some View {
        if !model.unplanned.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Ungeplant · \(model.unplanned.count)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.unplanned.prefix(40)) { task in
                            Text(task.title)
                                .font(.subheadline)
                                .lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(.thinMaterial, in: Capsule())
                                .draggable(task.id.key)
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}
