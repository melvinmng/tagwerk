import SwiftUI
import TagwerkCore

/// Week view (mockup b-A, #259): the days as sections with capacity, then everything the day list shows in the same rows:
/// all-day events on top, the timed events and time blocks in order, planned tasks without a time and deadlines; drop targets.
struct WeekView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let onShowTask: (TaskID) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    let deadlineActions: DeadlineActions
    @State private var targetedDay: PlanDay?
    /// The sheet of an event or block, opened as in the day view, and the event menu's questions (series, deadline, removal).
    @State private var sheetEntry: DayEntry?
    @State private var markingSeries: CalendarEvent?
    @State private var linkingToDeadline: CalendarEvent?
    @State private var unmarking: CalendarEvent?

    private func incomingMoves(to day: PlanDay) -> [PlanSuggestion] {
        model.suggestionBatches.flatMap(\.suggestions).filter { $0.kind == .move && $0.day == day && $0.fromDay != day }
    }

    var body: some View {
        PagedContainer(canGoBack: true, canGoForward: true, isLocked: false, contentID: { model.days.first?.day },
                       onPage: { model.step($0.step) }, onPrevailingPage: { model.titlePreviewStep = $0?.step },
                       onBlockedEdge: {}) { slot in
            switch slot {
            case .current: weekList
            case .previous: weekPreview(offset: -7)
            case .next: weekPreview(offset: 7)
            case .arrived: weekPreview(offset: 0)
            }
        }
        .sheet(item: $sheetEntry) { entry in EntrySheet(entry: entry, model: model, onShowTask: onShowTask) }
        .sheet(item: $linkingToDeadline) { event in DeadlinePickerSheet(event: event, model: model) }
        .seriesMarkQuestion(isPresented: Binding(get: { markingSeries != nil }, set: { if !$0 { markingSeries = nil } }),
                            event: markingSeries, model: model)
        .unmarkConfirmation(event: $unmarking, model: model)
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
            let marks = model.currentExtras
            ForEach(model.days) { plan in
                let content = model.weekContent(for: plan)
                Section {
                    ForEach(content.allDay) { event in allDayRow(event, plan: plan) }
                    ForEach(content.timed) { entry in entryRow(entry, plan: plan, marks: marks) }
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
                    ForEach(content.deadlines) { deadline in
                        DeadlineLine(deadline: deadline)
                            .deadlineInteractions(deadline, model: model, actions: deadlineActions)
                    }
                    if !content.hasEntries && plan.assigned.isEmpty && content.deadlines.isEmpty && plan.suggestions.isEmpty
                        && incomingMoves(to: plan.day).isEmpty {
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

    // MARK: Rows

    /// An all-day event: the row of the day list without a time, "Ganztägig" as its detail.
    private func allDayRow(_ event: CalendarEvent, plan: DayPlan) -> some View {
        Button { sheetEntry = .event(event, plan.links[event.id]) } label: {
            TimelineLine(time: "", title: event.title,
                         detail: (event.isBusy ? [String(localized: "Ganztägig")] : [String(localized: "Ganztägig"), String(localized: "Frei")])
                             .joined(separator: " · "),
                         color: event.isBusy ? .blue : .gray) { EmptyView() }
        }
        .foregroundStyle(.primary)
        .contextMenu { eventMenu(event, taskID: plan.links[event.id], deadline: nil) }
    }

    /// An event or a time block with its trips: the rows of the day list, one row per entry.
    @ViewBuilder
    private func entryRow(_ entry: WeekEntry, plan: DayPlan, marks: DayPageExtras) -> some View {
        if let taskID = entry.taskID {
            BlockEntryRow(model: model, plan: plan, event: entry.event, taskID: taskID, marks: marks, trips: entry.trips) {
                sheetEntry = .event(entry.event, taskID)
            }
        } else {
            EventEntryRow(model: model, day: plan.day, event: entry.event, marks: marks, trips: entry.trips) {
                sheetEntry = .event(entry.event, nil)
            }
            .contextMenu { eventMenu(entry.event, taskID: nil, deadline: entry.deadline) }
        }
    }

    /// The menu of the day list's event rows; an event that is a deadline keeps the entry of its deadline line.
    @ViewBuilder
    private func eventMenu(_ event: CalendarEvent, taskID: TaskID?, deadline: ImportantDeadline?) -> some View {
        EventDeadlineMenu(event: event, model: model, onOpen: { sheetEntry = .event(event, taskID) },
                          onMarkSeries: { markingSeries = event }, onLinkToDeadline: { linkingToDeadline = event },
                          onConfirmUnmark: { unmarking = event })
        if let deadline {
            Button("Zum Tag springen", systemImage: "arrow.right") { deadlineActions.showDay(deadline.day) }
            Button("Termin zuordnen …", systemImage: "link") { deadlineActions.prepare(deadline) }
        }
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
