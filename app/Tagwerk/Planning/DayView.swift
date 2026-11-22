import SwiftUI
import TagwerkCore

/// Day view: the hour grid by default (design §13.15 S1), the row list as an alternative. Both open the same
/// sheet for events, blocks and the lunch break (U1).
struct DayView: View {
    @Bindable var model: PlanningModel
    @Environment(AppEnvironment.self) private var environment
    let onOpenTask: (TaskID) -> Void
    let onShowTask: (TaskID) -> Void
    let onOpenEvent: (CalendarEvent) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions
    let deadlineActions: DeadlineActions
    @State private var editingHours = false
    /// Event menu (list mode, all-day row): series question, deadline picker and removal with links (DL2).
    @State private var markingSeries: CalendarEvent?
    @State private var linkingToDeadline: CalendarEvent?
    @State private var unmarking: CalendarEvent?
    @State private var blockFor: TaskItem?
    @State private var sheetEntry: DayEntry?
    /// The event whose travel time is edited from the travel menu (PL11b).
    @State private var editingTravel: CalendarEvent?
    @State private var showsGrid = true
    /// A block or task is being dragged in the grid; the page container ignores sideways drags meanwhile.
    @State private var gridLocked = false
    /// The vertical offset of the shown page; the neighbour previews stand at the same height while one is dragged in.
    @State private var offsetBox = ScrollOffsetBox()
    @State private var previewOffset: CGFloat = 0
    /// Bumped every minute so the list places the "now" row anew.
    @State private var nowTick = 0

    var body: some View {
        Group {
            if let plan = model.days.first {
                PagedContainer(canGoBack: true, canGoForward: true, isLocked: gridLocked,
                               contentID: { model.days.first?.day },
                               onPage: { model.step($0.step) },
                               onDragBegan: { previewOffset = offsetBox.y },
                               onPrevailingPage: { model.titlePreviewStep = $0?.step }, onBlockedEdge: {}) { slot in
                    switch slot {
                    case .current: pageContent(plan)
                    case .previous: preview(of: plan.day.adding(days: -1, calendar: model.calendar))
                    case .next: preview(of: plan.day.adding(days: 1, calendar: model.calendar))
                    case .arrived: preview(of: model.anchor)
                    }
                }
            } else {
                // Keeps a view in place before the first load; otherwise the parent's `.task` would never run.
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { showsGrid = model.showsHourGrid }
        .environment(\.editTravel) { editingTravel = $0 }
        // The page "Fahrzeit" of the event with its own navigation stack (a sheet over the day, not over another sheet).
        .sheet(item: $editingTravel) { event in
            NavigationStack {
                TravelOverrideView(event: event, model: model)
                    .toolbar { ToolbarItem(placement: .cancellationAction) { TravelSheetCloseButton() } }
            }
        }
        .sheet(item: $sheetEntry) { entry in EntrySheet(entry: entry, model: model, onShowTask: onShowTask) }
        .sheet(item: $linkingToDeadline) { event in DeadlinePickerSheet(event: event, model: model) }
        .seriesMarkQuestion(isPresented: Binding(get: { markingSeries != nil }, set: { if !$0 { markingSeries = nil } }),
                            event: markingSeries, model: model)
        .unmarkConfirmation(event: $unmarking, model: model)
        .sheet(isPresented: $editingHours) {
            if let plan = model.days.first {
                DayOverrideSheet(day: plan.day, calendar: model.calendar, current: model.workHours(on: plan.day)) { value in
                    model.setDayOverride(value, on: plan.day)
                    Task { await model.reload() }
                }
            }
        }
        .sheet(item: $blockFor) { task in
            if let plan = model.days.first {
                BlockSheet(task: task, day: plan.day, hours: model.workHours(on: plan.day), now: model.now(),
                           minutes: model.suggestedBlockMinutes(for: task), calendar: model.calendar) { start, minutes in
                    Task { await model.createBlock(for: task, start: start, minutes: minutes) }
                }
            }
        }
    }

    /// The page of a day: grid or list. The preview of a neighbour is the very same view built from its preloaded plan
    /// and cards, so nothing moves when the page arrives (#134 follow-up).
    @ViewBuilder
    private func pageContent(_ plan: DayPlan, extras: DayPageExtras? = nil, isPreview: Bool = false) -> some View {
        if showsGrid {
            DayGridScreen(model: model, plan: plan, onOpenTask: onOpenTask, onEditRecurring: onEditRecurring,
                          menuActions: plannedActions, summary: { summary(plan) },
                          timelineHeader: { timelineHeader }, onOpenEntry: { sheetEntry = $0 },
                          onPlanTask: { blockFor = $0 }, isLocked: isPreview ? .constant(false) : $gridLocked,
                          offsetBox: isPreview ? nil : offsetBox, previewOffset: isPreview ? previewOffset : nil)
        } else {
            listContent(plan, extras: extras, isPreview: isPreview)
        }
    }

    /// The neighbouring day beside the shown page: its preloaded page without interaction; the date and a progress
    /// indicator while it is not loaded yet.
    @ViewBuilder
    private func preview(of day: PlanDay) -> some View {
        if let plan = model.neighbourPlans[day], let extras = model.neighbourExtras[day] {
            pageContent(plan, extras: extras, isPreview: true)
                .environment(\.dayPageExtras, extras)
                .environment(\.isPagePreview, true)
        } else {
            DayPagePreview(model: model, day: day)
        }
    }

    // MARK: Shared parts

    /// Header, deadlines, capacity and all-day events (above the timeline in both modes).
    @ViewBuilder
    private func summary(_ plan: DayPlan) -> some View {
        PlanIntakeLine(model: model, day: plan.day)
        // The one new element of phase 7: the morning card or today's focus, in the day view of today only.
        if model.scope == .day, plan.day == model.today { RoutineCard(model: environment.routines, plan: plan) }
        DeadlineCard(model: model, actions: deadlineActions)
        DeadlineSuggestionCard(model: model)
        CapacityCard(model: model, plan: plan) { editingHours = true }
        if !model.allDayEvents(for: plan).isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    Text("Ganztägig").font(.caption.weight(.semibold)).foregroundStyle(.secondaryText)
                    ForEach(model.allDayEvents(for: plan)) { event in
                        Button { sheetEntry = .event(event, plan.links[event.id]) } label: {
                            Text(event.title).font(.subheadline).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .contextMenu { eventMenu(event, taskID: plan.links[event.id]) }
                    }
                }
            }
        }
    }

    private var timelineHeader: some View {
        HStack {
            Text("Ablauf").font(.headline)
            Spacer()
            Button {
                showsGrid.toggle()
                model.showsHourGrid = showsGrid
            } label: {
                Image(systemName: showsGrid ? "list.bullet" : "calendar.day.timeline.left")
                    .touchTargetLabel()
            }
            .touchTargetInset(horizontal: 11, vertical: 14)
            .accessibilityLabel(showsGrid ? "Als Liste zeigen" : "Als Stundenraster zeigen")
        }
    }

    /// The shared menu plus the day-only entries that replaced the swipe actions.
    private func plannedActions(_ task: TaskItem) -> TaskMenuActions {
        var actions = menuActions(task)
        actions.createBlock = { blockFor = task }
        actions.shownDay = model.anchor
        // Focus belongs to today: the menu entry exists in the day view of today only, not for recurring occurrences.
        if model.scope == .day, model.anchor == model.today, !environment.routines.isRecurring(task) {
            actions.toggleFocus = { environment.routines.toggleFocus(task) }
            actions.isFocus = environment.routines.isFocus(task.id)
        }
        if model.planStore.assignment(for: task.id) != nil {
            actions.unassign = { Task { await model.unassign(task.id) } }
        }
        return actions
    }

    // MARK: List mode

    private func listContent(_ plan: DayPlan, extras: DayPageExtras? = nil, isPreview: Bool = false) -> some View {
        let marks = extras ?? model.currentExtras
        let rows = model.timelineWithGaps(for: plan)
        return List {
            Section {
                summary(plan)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                let nowIndex = nowTick >= 0 ? model.nowRowIndex(in: rows, on: plan.day) : nil
                if rows.isEmpty { Text("Keine Termine").foregroundStyle(.secondaryText) }
                ForEach(rows.prefix(nowIndex ?? rows.count)) { row in timelineRow(row, plan: plan, marks: marks) }
                NowRowSlot(model: model, day: plan.day, isShown: nowIndex != nil)
                ForEach(rows.dropFirst(nowIndex ?? rows.count)) { row in timelineRow(row, plan: plan, marks: marks) }
                // Open AI suggestions in list mode (mockup W3).
                ForEach(plan.suggestions.filter { $0.kind == .block }.sorted { ($0.startMinutes ?? 0) < ($1.startMinutes ?? 0) }) { suggestion in
                    SuggestionRow(suggestion: suggestion)
                        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                }
            } header: {
                timelineHeader.textCase(nil)
            }
            TaskSections(model: model, plan: plan, onOpenTask: onOpenTask, onEditRecurring: onEditRecurring,
                         menuActions: plannedActions)
        }
        .modifier(NowListBehavior(model: model, day: plan.day, tick: $nowTick, isEnabled: !isPreview,
                                  openingRowID: rows.first.map { AnyHashable($0.id) }))
    }

    @ViewBuilder
    private func timelineRow(_ row: TimelineRow, plan: DayPlan, marks: DayPageExtras) -> some View {
        switch row {
        case .event(let event):
            EventEntryRow(model: model, day: plan.day, event: event, marks: marks) { sheetEntry = .event(event, nil) }
                .contextMenu { eventMenu(event, taskID: nil) }
        case .block(let event, let taskID):
            BlockEntryRow(model: model, plan: plan, event: event, taskID: taskID, marks: marks) {
                sheetEntry = .event(event, taskID)
            }
        case .lunch(let start, let minutes):
            let remaining = model.runningRemaining(range: start..<(start + minutes), on: plan.day)
            Button { sheetEntry = .lunch(day: plan.day, range: start..<(start + minutes)) } label: {
                TimelineLine(time: plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(start * 60)),
                             title: String(localized: "Mittagspause"),
                             detail: remaining.map { NowText.runningDetail(remainingMinutes: $0) } ?? CapacityText.duration(minutes),
                             color: .gray, isRunning: remaining != nil)
            }
            .foregroundStyle(.primary)
        case .travel(let segment):
            TravelRow(segment: segment, transport: segment.transport ?? model.settings.travelTransport,
                      time: clock(segment.range.lowerBound, on: plan.day),
                      event: (plan.events + plan.blocks).first { $0.id == segment.eventID }, model: model)
        case .gap(let range):
            GapLine(text: String(localized: "frei \(clock(range.lowerBound, on: plan.day))–\(clock(range.upperBound, on: plan.day))"))
                .dropDestination(for: String.self) { keys, _ in
                    guard let key = keys.first else { return false }
                    Task { await model.dropTask(key: key, atMinutes: range.lowerBound, on: plan.day) }
                    return true
                }
        }
    }

    /// The event menu of list mode and the all-day row (DL2).
    private func eventMenu(_ event: CalendarEvent, taskID: TaskID?) -> some View {
        EventDeadlineMenu(event: event, model: model, onOpen: { sheetEntry = .event(event, taskID) },
                          onMarkSeries: { markingSeries = event }, onLinkToDeadline: { linkingToDeadline = event },
                          onConfirmUnmark: { unmarking = event })
    }

    private func clock(_ minutes: Int, on day: PlanDay) -> String {
        day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Remaining time today (B1) or the day's capacity; opens the working hours of the day.
struct CapacityCard: View {
    @Environment(AppEnvironment.self) private var environment
    let model: PlanningModel
    let plan: DayPlan
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            details
            if !plan.isPast && !plan.capacity.isDayOff {
                Divider()
                AIPlanBar(scope: .day)
            }
            if plan.day == model.today, let entry = model.eveningEntry {
                Divider()
                eveningLine(entry)
            }
            if plan.day == model.today, model.showsLeftoverLine(overbooked: plan.capacity.isOverbooked) {
                Divider()
                LeftoverLine(count: model.openFromToday.count) { environment.routines.openLeftover() }
            }
            if plan.day == model.today, environment.routines.eveningLine != nil {
                Divider()
                wrapUpLine
            }
        }
        .padding(12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// "🛏 Tagesabschluss · Schlafzeit 23:00 · Checkliste 0 von 3 ›", independent of "Morgen planen"; after "Abschließen"
    /// with a checkmark. Opens the sheet; nothing is written by looking at it.
    private var wrapUpLine: some View {
        let routines = environment.routines
        let isDone = routines.eveningLine?.isDone == true
        return Button {
            routines.openEvening()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "bed.double")
                    .foregroundStyle(isDone ? Color.green : Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Tagesabschluss").font(.subheadline.weight(.semibold))
                    Text(routines.captureEveningDetail(routines.eveningDay)).font(.caption).foregroundStyle(.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet den Tagesabschluss")
    }

    /// "☾ Morgen planen · Do. 19. Nov. · 3 h 15 frei · 2 von heute übrig" (MP2): a tap only shows that day;
    /// nothing is sent.
    private func eveningLine(_ entry: PlanningModel.EveningEntry) -> some View {
        Button {
            model.jump(to: entry.day)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "moon.stars").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DayPanelText.eveningTitle(day: entry.day, today: model.today, calendar: model.calendar))
                        .font(.subheadline.weight(.semibold))
                    Text(DayPanelText.eveningDetail(day: entry.day, freeMinutes: entry.freeMinutes, leftCount: entry.leftCount,
                                                    calendar: model.calendar))
                        .font(.caption).foregroundStyle(.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondaryText)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Suggested minutes of the day, counted apart until accepted (mockup V1).
    private var suggestedMinutes: Int { plan.suggestions.compactMap(\.minutes).reduce(0, +) }

    private var details: some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(plan.isPast ? String(localized: "Vergangen") : CapacityText.remaining(plan.capacity)).font(.headline)
                    Spacer()
                    Image(systemName: "slider.horizontal.3").foregroundStyle(.secondaryText)
                }
                if plan.capacity.remainingMinutes != nil, let hours = model.workHours(on: plan.day) {
                    Text(remainingDetail(hours)).font(.caption).foregroundStyle(.secondaryText)
                }
                CapacityBar(capacity: plan.capacity)
                if !plan.isPast, let explanation = CapacityText.explanation(plan.capacity, hours: model.workHours(on: plan.day), clock: clock) {
                    Text(explanation).font(.caption).foregroundStyle(.secondaryText)
                }
                if plan.capacity.estimatedCount > 0 {
                    Text("\(plan.capacity.estimatedCount) Aufgabe(n) ohne Aufwand mit Standarddauer gerechnet")
                        .font(.caption).foregroundStyle(.secondaryText)
                }
                if suggestedMinutes > 0 {
                    let suggested = CapacityText.duration(suggestedMinutes)
                    let freeAfter = CapacityText.duration(PlanningModel.freeAfterAccepting(
                        free: plan.capacity.remainingMinutes ?? plan.capacity.freeMinutes, suggestions: plan.suggestions,
                        counted: plan.planInput?.countedTaskMinutes ?? [:]))
                    Label(String(localized: "\(suggested) vorgeschlagen · nach dem Übernehmen \(freeAfter) frei"), systemImage: "sparkles")
                        .font(.caption).foregroundStyle(.purpleText)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Arbeitszeit an diesem Tag ändern")
    }

    /// "ab jetzt · 13:20 bis 18:00 · ganzer Tag …", or "Arbeitszeit vorbei" after the end of work.
    private func remainingDetail(_ hours: WorkHours) -> String {
        let nowMinutes = Int(model.now().timeIntervalSince(plan.day.startDate(in: model.calendar)) / 60)
        let summary = CapacityText.summary(plan.capacity)
        let end = clock(hours.endMinutes)
        if nowMinutes >= hours.endMinutes { return String(localized: "Arbeitszeit vorbei · ganzer Tag \(summary)") }
        if nowMinutes > hours.startMinutes {
            return String(localized: "ab jetzt · \(clock(nowMinutes)) bis \(end) · ganzer Tag \(summary)")
        }
        return String(localized: "ab \(clock(hours.startMinutes)) bis \(end) · ganzer Tag \(summary)")
    }

    private func clock(_ minutes: Int) -> String {
        plan.day.startDate(in: model.calendar).addingTimeInterval(TimeInterval(minutes * 60)).formatted(date: .omitted, time: .shortened)
    }
}

/// Below the timeline: planned tasks (list mode), "Heute offen, nicht zugeordnet" and "Überfällig"
/// (design §13.15 D1, user feedback 2026-11-18). Recurring reminders appear in these sections with their effort.
struct TaskSections: View {
    let model: PlanningModel
    let plan: DayPlan
    var showsPlanned = true
    let onOpenTask: (TaskID) -> Void
    let onEditRecurring: (RecurringItem, PlanDay) -> Void
    let menuActions: (TaskItem) -> TaskMenuActions

    var body: some View {
        let today = model.today
        if showsPlanned {
            Section("Geplant ohne Uhrzeit") {
                if plan.assigned.isEmpty {
                    Text(DayPanelText.emptyPlannedHint(day: plan.day, today: today, calendar: model.calendar))
                        .font(.subheadline).foregroundStyle(.secondaryText)
                }
                ForEach(plan.assigned) { task in taskRow(task, isPastDue: plan.isPastDue.contains(task.id)) }
            }
        }
        let leftovers = model.leftovers(on: plan.day)
        if !leftovers.isEmpty {
            Section {
                ForEach(leftovers) { task in commitRow(task, moves: true) }
            } header: {
                HStack {
                    Text("Von heute übrig")
                    Spacer()
                    Button(DayPanelText.moveAllTitle(day: plan.day, today: today, calendar: model.calendar)) {
                        let day = plan.day
                        Task { await model.moveTasks(leftovers.map(\.id), to: day) }
                    }
                    .textCase(nil)
                }
            }
        }
        if !plan.openToday.isEmpty {
            Section {
                ForEach(plan.openToday) { task in commitRow(task) }
            } header: {
                Text(DayPanelText.dueSectionTitle(day: plan.day, today: today, calendar: model.calendar))
            } footer: {
                Text(DayPanelText.commitFooter(day: plan.day, today: today, calendar: model.calendar))
            }
        }
        if model.showsOverdue(on: plan.day), !model.overdue.isEmpty {
            Section("Überfällig") {
                ForEach(model.overdue) { task in commitRow(task, overdue: true) }
            }
        }
    }

    private func taskRow(_ task: TaskItem, isPastDue: Bool) -> some View {
        PlannedTaskRow(task: task, isPastDue: isPastDue, isFocus: isFocus(task.id))
            .contentShape(Rectangle())
            .onTapGesture { onOpenTask(task.id) }
            .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
    }

    /// The star of a focus task; only in the plan of today.
    private func isFocus(_ id: TaskID) -> Bool { plan.day == model.today && model.focusTaskIDs.contains(id) }

    /// A task that is not yet committed to the shown day, with its effort for recurring reminders and the commit
    /// button ("Heute", "Morgen", "Einplanen"); leftovers from today move with their blocks (`moves`).
    private func commitRow(_ task: TaskItem, overdue: Bool = false, moves: Bool = false) -> some View {
        let recurring = model.recurringItem(for: task, on: plan.day)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((recurring != nil ? "↻ " : "") + (isFocus(task.id) ? "★ " : "") + task.title).lineLimit(2)
                HStack(spacing: 6) {
                    if let recurring, recurring.minutes > 0 {
                        Text("\(CapacityText.duration(recurring.minutes)) reserviert")
                    } else {
                        Text(EstimateHours.text(minutes: task.estimateMinutes))
                    }
                    if overdue, let due = task.due {
                        Text("fällig \(DueText.text(due, now: model.now(), calendar: model.calendar))").foregroundStyle(.redText)
                    } else if overdue, let planned = model.planStore.assignment(for: task.id) {
                        Text("geplant \(planned.startDate(in: model.calendar).formatted(.dateTime.weekday(.abbreviated).day().month()))")
                            .foregroundStyle(.orangeText)
                    }
                }
                .font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
            Button(DayPanelText.commitTitle(day: plan.day, today: model.today, calendar: model.calendar)) {
                let day = plan.day
                Task {
                    if moves { await model.moveTask(task.id, to: day) } else { await model.commitToShownDay(task.id) }
                }
            }
            .buttonStyle(.bordered)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenTask(task.id) }
        .contextMenu { TaskContextMenu(item: task, actions: menuActions(task)) }
    }
}

/// A free stretch in the timeline; tasks can be dropped on it (mockup C2).
private struct GapLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 48)
            RoundedRectangle(cornerRadius: 2).strokeBorder(.secondary, style: StrokeStyle(lineWidth: 1, dash: [3])).frame(width: 4)
            Text(text).font(.caption).foregroundStyle(.secondaryText)
            Spacer()
            Image(systemName: "plus.circle").font(.caption).foregroundStyle(.tertiary)
        }
        .frame(minHeight: 24)
        .accessibilityLabel(String(localized: "\(text), Aufgabe hier ablegen"))
    }
}

/// A planned task without time (day and week views).
struct PlannedTaskRow: View {
    let task: TaskItem
    let isPastDue: Bool
    /// The task is today's focus: a star next to the title.
    var isFocus = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text((isFocus ? "★ " : "") + task.title).lineLimit(2)
                HStack(spacing: 6) {
                    Text(EstimateHours.text(minutes: task.estimateMinutes))
                    if isPastDue { Label("nach Fälligkeit", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orangeText) }
                }
                .font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
            if let priority = task.priority {
                Text(priority.label).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(priority == .p1 ? Color.red.opacity(0.25) : Color.secondary.opacity(0.2), in: Capsule())
            }
        }
        .draggable(task.id.key)
    }
}
