import SwiftUI
import TagwerkCore

/// The "Planen" tab: Tag / Woche / Monat with navigation (design §7).
struct PlanView: View {
    @Bindable var model: PlanningModel
    let onOpenTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    @State private var deleting: TaskItem?
    @State private var planningDateFor: TaskItem?
    @State private var dueDateFor: TaskItem?

    var body: some View {
        NavigationStack {
            Group {
                switch model.scope {
                case .day: DayView(model: model, onOpenTask: onOpenTask, onOpenEvent: onOpenEvent,
                                   onEditRecurring: onEditRecurring, menuActions: menuActions)
                case .week: WeekView(model: model, onOpenTask: onOpenTask, menuActions: menuActions)
                case .month:
                    MonthView(model: model) { day in
                        model.anchor = day
                        model.scope = .day
                    }
                }
            }
            .safeAreaInset(edge: .top) { header }
            .navigationTitle("Planen")
            .navigationBarTitleDisplayMode(.inline)
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
            .alert("Hinweis", isPresented: hasError) {
                Button("OK") { model.clearError() }
            } message: { Text(model.lastError ?? "") }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Picker("Ansicht", selection: $model.scope) {
                ForEach(PlanScope.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            HStack {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Zurück")
                Spacer()
                Text(title).font(.headline)
                Spacer()
                Button { step(1) } label: { Image(systemName: "chevron.right") }.accessibilityLabel("Weiter")
            }
            if model.anchor != model.today {
                Button("Heute") { model.anchor = model.today }.font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private var title: String {
        let date = model.anchor.startDate(in: model.calendar)
        switch model.scope {
        case .day:
            return date.formatted(.dateTime.weekday(.wide).day().month(.wide)) + (model.anchor == model.today ? " · Heute" : "")
        case .week:
            let range = model.range
            return "\(range.lowerBound.day).–\(range.upperBound.startDate(in: model.calendar).formatted(.dateTime.day().month(.wide)))"
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }

    private func step(_ direction: Int) {
        switch model.scope {
        case .day: model.anchor = model.anchor.adding(days: direction, calendar: model.calendar)
        case .week: model.anchor = model.anchor.adding(days: 7 * direction, calendar: model.calendar)
        case .month:
            let moved = model.calendar.date(byAdding: .month, value: direction, to: model.anchor.startDate(in: model.calendar))
            model.anchor = moved.map { PlanDay(date: $0, calendar: model.calendar) } ?? model.anchor
        }
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
            isWritable: writable
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
