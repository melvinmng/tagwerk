import SwiftUI
import TagwerkCore

/// The "Planen" tab: Tag / Woche / Monat with navigation (design §7).
struct PlanView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onShowTask: (TaskID) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    @State private var deleting: TaskItem?
    @State private var planningDateFor: TaskItem?
    @State private var dueDateFor: TaskItem?
    @State private var creatingEvent = false

    @Environment(AppEnvironment.self) private var environment

    /// "Vorschläge verworfen" with "Rückgängig" after "Verwerfen".
    @ViewBuilder
    private var dismissUndo: some View {
        let dismissed = environment.planner.lastDismissed
        if !dismissed.isEmpty {
            let count = environment.planner.dismissedCount
            UndoCapsule(title: String(localized: "\(count) Vorschläge"), caption: "Verworfen",
                        symbol: "sparkles", duration: 5,
                        onUndo: { Task { await environment.planner.undoDismissAll() } },
                        onExpire: { environment.planner.clearDismissUndo() })
                .padding(.bottom, 60)
        }
    }

    /// "Dupliziert" with "Rückgängig" after duplicating a block (mockup DU1).
    @ViewBuilder
    private var duplicateUndo: some View {
        if let copy = model.lastDuplicate {
            UndoCapsule(title: copy.title, caption: "Dupliziert", symbol: "plus.square.on.square", duration: 5,
                        onUndo: { Task { await model.undoDuplicate() } },
                        onExpire: { if model.lastDuplicate?.id == copy.id { model.clearDuplicateUndo() } })
                .padding(.bottom, 60)
        }
    }

    /// After dragging a task to another day (mockup WT1): which blocks came along, with "Rückgängig".
    @ViewBuilder
    private var moveUndo: some View {
        if let move = model.lastMove, let task = model.taskList.items.first(where: { $0.id == move.taskID }) {
            let caption: LocalizedStringResource = switch move.movedBlocks {
            case 0: "Verschoben"
            default: "Verschoben · \(move.movedBlocks) Zeitblöcke mitgenommen"
            }
            UndoCapsule(title: task.title, caption: caption, symbol: "arrow.left.arrow.right.circle.fill", duration: 5,
                        onUndo: { Task { await model.undoMove() } },
                        onExpire: { if model.lastMove == move { model.clearMoveUndo() } })
                .padding(.bottom, 60)
        }
    }

    /// After "Alle übernehmen": one "Rückgängig" for blocks, days, hours and moves (mockup AW1).
    @ViewBuilder
    private var acceptAllUndo: some View {
        if let undo = environment.planner.lastAcceptAll {
            UndoCapsule(title: String(localized: "\(undo.count) Vorschläge"), caption: "Übernommen",
                        symbol: "sparkles", duration: 6,
                        onUndo: { Task { await environment.planner.undoAcceptAll() } },
                        onExpire: { environment.planner.clearAcceptUndo() })
                .padding(.bottom, 60)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.scope {
                case .day: DayView(model: model, onOpenTask: onOpenTask, onShowTask: onShowTask, onOpenEvent: onOpenEvent,
                                   onEditRecurring: onEditRecurring, menuActions: menuActions)
                case .week: WeekView(model: model, onOpenTask: onOpenTask, menuActions: menuActions)
                case .month:
                    MonthView(model: model, onSelectDay: { day in
                        model.anchor = day
                        model.scope = .day
                    }, onOpenEvent: onOpenEvent, onOpenTask: onOpenTask)
                }
            }
            .safeAreaInset(edge: .top) { header }
            .overlay(alignment: .bottom) { dismissUndo }
            .overlay(alignment: .bottom) { duplicateUndo }
            .overlay(alignment: .bottom) { moveUndo }
            .overlay(alignment: .bottom) { acceptAllUndo }
            .navigationTitle("Planen")
            .toolbar(.hidden, for: .navigationBar)  // the tab bar already says "Planen" (mockup A1)
            .task(id: "\(model.scope)-\(model.anchor)") { await model.reload() }
            .refreshable { await model.taskList.reload(); await model.reload() }
            .onChange(of: model.taskList.items) { _, _ in Task { await model.reload() } }
            .confirmationDialog("Zeitblöcke mitverschieben?", isPresented: hasPendingDecision, titleVisibility: .visible) {
                Button("Mitverschieben") { Task { await model.resolveBlocks(move: true) } }
                Button("Blöcke löschen", role: .destructive) { Task { await model.resolveBlocks(move: false) } }
                Button("Abbrechen", role: .cancel) { model.cancelBlockDecision() }
            } message: {
                Text("Für diese Aufgabe gibt es geplante Zeitblöcke im Kalender.")
            }
            .confirmationDialog(deleting.map(TaskListView.deleteQuestion) ?? "", isPresented: isDeleting,
                                titleVisibility: .visible, presenting: deleting) { item in
                Button(TaskListView.deleteTitle(for: item), role: .destructive) {
                    Task { await model.taskList.delete(item.id); await model.reload() }
                }
            }
            .sheet(item: $planningDateFor) { item in
                RescheduleDateSheet(item: item, calendar: model.calendar, now: model.now()) { day in
                    Task { await model.assign(item.id, to: PlanDay(day)) }
                }
            }
            .sheet(item: $dueDateFor) { item in
                RescheduleDateSheet(item: item, calendar: model.calendar, now: model.now()) { day in
                    Task { await model.taskList.reschedule(item.id, option: .date(day)) }
                }
            }
            .sheet(isPresented: $creatingEvent) { EventEditSheet(model: model, existing: nil, day: model.anchor) }
            .alert("Hinweis", isPresented: hasError) {
                Button("OK") { model.clearError() }
            } message: { Text(model.lastError ?? "") }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Picker("Ansicht", selection: $model.scope) {
                    ForEach(PlanScope.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Button { creatingEvent = true } label: { Image(systemName: "plus").frame(width: 22, height: 22) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Neuer Termin")
                AssistantButton { .planning(scope: model.scope, anchor: model.anchor) }
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func menuActions(for item: TaskItem) -> TaskMenuActions {
        let writable = model.taskList.sourceStates[item.id.source]?.isOffline != true
        return TaskMenuActions(
            plan: { option in Task { await model.plan(item.id, option: option) } },
            planOnDate: { planningDateFor = item },
            moveDue: { option in Task { await model.taskList.reschedule(item.id, option: option) } },
            moveDueOnDate: { dueDateFor = item },
            complete: { Task { await model.taskList.complete(item.id); await model.reload() } },
            delete: { deleting = item },
            editEffort: model.recurringItem(for: item, on: model.anchor).map { recurring in
                { onEditRecurring(recurring, model.anchor) }
            },
            isWritable: writable,
            plannedText: model.plannedText(for: item.id)
        )
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var hasPendingDecision: Binding<Bool> {
        Binding(get: { model.pendingBlockDecision != nil }, set: { if !$0 { model.cancelBlockDecision() } })
    }

    private var hasError: Binding<Bool> {
        Binding(get: { model.lastError != nil }, set: { if !$0 { model.clearError() } })
    }
}
