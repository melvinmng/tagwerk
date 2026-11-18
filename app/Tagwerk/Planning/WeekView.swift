import SwiftUI
import TagwerkCore

/// Week view (mockup b-A): days as rows with capacity, deadlines and planned tasks; drop targets.
struct WeekView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    @State private var targetedDay: PlanDay?

    var body: some View {
        List {
            Section {
                DayHeader(model: model) { model.scope = .month }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            // The AI bar as its own card under the header (mockup V1), like in the month.
            Section {
                AIPlanBar(scope: .week)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(model.days) { plan in
                Section {
                    ForEach(plan.suggestions) { suggestion in
                        SuggestionRow(suggestion: suggestion)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    ForEach(plan.assigned) { task in
                        PlannedTaskRow(task: task, isPastDue: plan.isPastDue.contains(task.id))
                            .contentShape(Rectangle())
                            .draggable(task.id.key)  // mockup WT1: drag to another day
                            .onTapGesture { onOpenTask(task.id) }
                            .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
                    }
                    ForEach(plan.deadlines) { deadline in
                        Label(deadline.title, systemImage: "flag.fill").foregroundStyle(.red).font(.subheadline)
                    }
                    if plan.assigned.isEmpty && plan.deadlines.isEmpty && plan.suggestions.isEmpty {
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
                    Task { for id in ids { await model.moveTask(id, to: plan.day) } }
                    return !ids.isEmpty
                } isTargeted: { targeted in
                    targetedDay = targeted ? plan.day : (targetedDay == plan.day ? nil : targetedDay)
                }
            }
        }
        .simultaneousGesture(horizontalSwipe { model.step($0) })  // next or previous week
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: model.unplanned.isEmpty ? 0 : 56) }
        .overlay(alignment: .bottom) { UnplannedDrawer(model: model) }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

