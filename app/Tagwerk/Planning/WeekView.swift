import SwiftUI
import TagwerkCore

/// Week view (mockup b-A): days as rows with capacity, deadlines and planned tasks; drop targets.
struct WeekView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    let deadlineActions: DeadlineActions
    @State private var targetedDay: PlanDay?

    private func incomingMoves(to day: PlanDay) -> [PlanSuggestion] {
        model.suggestionBatches.flatMap(\.suggestions).filter { $0.kind == .move && $0.day == day && $0.fromDay != day }
    }

    var body: some View {
        PagedContainer(canGoBack: true, canGoForward: true, isLocked: false, contentID: { model.days.first?.day },
                       onPage: { model.step($0.step) }, onBlockedEdge: {}) { slot in
            switch slot {
            case .current: weekList
            case .previous: weekPreview(offset: -7)
            case .next: weekPreview(offset: 7)
            case .arrived: weekPreview(offset: 0)
            }
        }
    }

    /// The neighbouring week while the page is dragged; `offset` counts days from the shown week.
    private func weekPreview(offset: Int) -> some View {
        let start = model.range.lowerBound.adding(days: offset, calendar: model.calendar)
        let plans = (0..<7).compactMap { model.neighbourPlans[start.adding(days: $0, calendar: model.calendar)] }
        return WeekPagePreview(model: model, weekStart: start, plans: plans)
    }

    private var weekList: some View {
        List {
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
                    ForEach(plan.suggestions.filter { $0.kind != .move }) { suggestion in
                        SuggestionRow(suggestion: suggestion)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    // The target side of moves from other days (proposal §5).
                    ForEach(incomingMoves(to: plan.day)) { suggestion in
                        MoveGhostRow(suggestion: suggestion)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    ForEach(plan.suggestions.filter { $0.kind == .move && !plan.assigned.map(\.id.key).contains($0.taskKey) }) { move in
                        MoveSuggestionRow(suggestion: move)
                            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    }
                    ForEach(plan.assigned) { task in
                        if let move = plan.suggestions.first(where: { $0.kind == .move && $0.taskKey == task.id.key }) {
                            MoveSuggestionRow(suggestion: move)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                        } else {
                        PlannedTaskRow(task: task, isPastDue: plan.isPastDue.contains(task.id))
                            .contentShape(Rectangle())
                            .draggable(task.id.key)  // mockup WT1: drag to another day
                            .onTapGesture { onOpenTask(task.id) }
                            .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
                        }
                    }
                    ForEach(plan.deadlines) { deadline in
                        DeadlineLine(deadline: deadline)
                            .deadlineInteractions(deadline, model: model, actions: deadlineActions)
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
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: model.unplanned.isEmpty ? 0 : 56) }
        .overlay(alignment: .bottom) { UnplannedDrawer(model: model) }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }
}

/// A deadline in the week and the month: flag, title and the mark "markiert" (DL2).
struct DeadlineLine: View {
    let deadline: ImportantDeadline

    var body: some View {
        HStack(spacing: 6) {
            Label(deadline.title, systemImage: deadline.kind == .epic ? "diamond.fill" : "flag.fill")
                .foregroundStyle(.red).font(.subheadline)
            if deadline.kind == .markedEvent { DeadlineBadge(text: String(localized: "markiert")) }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
