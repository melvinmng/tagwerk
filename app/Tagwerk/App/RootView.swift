import SwiftUI
import TagwerkCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab = 0
    @State private var editingTask: TaskItem?
    @State private var openEvent: CalendarEvent?
    @State private var recurringEdit: RecurringEdit?

    /// K1 (the separate place of the tab bar) did not hold on iOS 27: the search tab sits inside the bar.
    /// The fallback K2 puts the button top right in every tab (`AssistantButton`).
    private var tabSelection: Binding<Int> { $selectedTab }

    private var assistantPresented: Binding<Bool> {
        Binding(get: { environment.assistant.isPresented }, set: { environment.assistant.isPresented = $0 })
    }

    struct RecurringEdit: Identifiable {
        var id: String { item.reminderID + "\(day)" }
        let item: RecurringItem
        let day: PlanDay
    }

    var body: some View {
        TabView(selection: tabSelection) {
            Tab("Planen", systemImage: "calendar", value: 0) {
                PlanView(model: environment.planning,
                         onOpenTask: { id in editingTask = environment.taskList.items.first { $0.id == id } },
                         onOpenEvent: { event in openEvent = event },
                         onShowTask: showTask,
                         onEditRecurring: { item, day in recurringEdit = RecurringEdit(item: item, day: day) })
            }

            Tab("Aufgaben", systemImage: "checklist", value: 1) {
                TaskListView(model: environment.taskList, onShowDay: showDay,
                             onEditRecurring: { item, day in recurringEdit = RecurringEdit(item: item, day: day) })
            }

            // Value 3 keeps the existing tab values (0 Planen, 1 Aufgaben, 2 Einstellungen) stable.
            Tab("Erfassen", systemImage: "plus.circle", value: 3) {
                CaptureView(model: environment.capture)
            }

            Tab("Einstellungen", systemImage: "gearshape", value: 2) {
                SettingsView()
            }

        }
        .sheet(isPresented: assistantPresented) {
            ChatView(assistant: environment.assistant)
        }
        .onChange(of: environment.assistant.isPresented) { _, presented in
            // The chat is its own sheet over the tabs; other sheets close first.
            if presented { editingTask = nil; openEvent = nil; recurringEdit = nil }
        }
        .onChange(of: environment.notificationNavigator.receivedCount) { _, _ in openNotificationTarget() }
        .onChange(of: environment.router.receivedCount) { _, _ in openRouterTarget() }
        .onChange(of: environment.settings.setupCompleted) { _, _ in openRouterTarget() }
        .onOpenURL { url in environment.router.open(url) }
        // An intent may set the route before the first render; then `onChange` never fires.
        .onAppear { openRouterTarget() }
        .onChange(of: environment.taskList.loadingSources) { _, _ in openNotificationTarget() }
        .onChange(of: environment.requestedTab) { _, tab in
            guard let tab else { return }
            selectedTab = tab
            environment.requestedTab = nil
        }
        .onAppear {
            environment.assistant.tools.onPlanned = {
                environment.assistant.isPresented = false
                selectedTab = 0
            }
        }
        .sheet(item: $editingTask) { task in
            if let provider = environment.taskList.provider(for: task.id.source) {
                TaskEditorView(item: task, provider: provider, calendar: environment.taskList.calendar, containers: [],
                               onDelete: { version in Task { await environment.taskList.delete(task.id, version: version) } },
                               planning: environment.planning,
                               onShowDay: showDay) { saved in
                    environment.taskList.didSave(saved)
                }
            }
        }
        .sheet(item: $openEvent) { event in
            EntrySheet(entry: .event(event, environment.planning.linkedTask(eventID: event.id)?.id),
                       model: environment.planning, onShowTask: showTask)
        }
        .sheet(item: $recurringEdit) { edit in
            RecurringEffortSheet(item: edit.item, day: edit.day, model: environment.planning)
        }
        .fullScreenCover(isPresented: showsSetup) {
            SetupView(model: environment.makeSetupModel(), loginModel: environment.makeGitHubLoginModel(),
                      chatGPTSignIn: ChatGPTSignInModel(ai: environment.ai)) {
                await environment.taskList.reload()
            }
        }
    }

    /// "Aufgabe zeigen": the task list with the task scrolled into view and marked (design §13.8 G3).
    private func showTask(_ id: TaskID) {
        selectedTab = 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))  // let a sheet close and the tab appear first
            environment.taskList.highlight(id)
        }
    }

    /// Opens the task or day of a tapped notification once the task list can show it.
    private func openNotificationTarget() {
        guard environment.settings.setupCompleted,
              let route = environment.notificationNavigator.takeRoute(taskList: environment.taskList) else { return }
        editingTask = nil
        openEvent = nil
        recurringEdit = nil
        environment.assistant.isPresented = false
        switch route {
        case .task(let id): showTask(id)
        case .tasksTab: selectedTab = 1
        case .day(let day): showDay(day)
        }
    }

    /// Opens the target of a `tagwerk://` link or shortcut once setup is done; links only navigate.
    private func openRouterTarget() {
        guard let request = environment.router.takeRequest(setupCompleted: environment.settings.setupCompleted) else { return }
        editingTask = nil
        openEvent = nil
        recurringEdit = nil
        environment.assistant.isPresented = false
        switch request.route {
        case .planToday: showDay(environment.planning.today)
        case .capture, .captureMeal, .captureWorkout, .review: selectedTab = 3
        }
    }

    private func showDay(_ day: PlanDay) {
        environment.planning.anchor = day
        environment.planning.scope = .day
        selectedTab = 0
    }

    private var showsSetup: Binding<Bool> {
        Binding(get: { !environment.settings.setupCompleted }, set: { _ in })
    }
}
