import SwiftUI
import TagwerkCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab = 0
    @State private var editingTask: TaskItem?
    @State private var openEvent: CalendarEvent?
    @State private var recurringEdit: RecurringEdit?

    struct RecurringEdit: Identifiable {
        var id: String { item.reminderID + "\(day)" }
        let item: RecurringItem
        let day: PlanDay
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanView(model: environment.planning,
                     onOpenTask: { id in editingTask = environment.taskList.items.first { $0.id == id } },
                     onOpenEvent: { event in openEvent = event },
                     onShowTask: showTask,
                     onEditRecurring: { item, day in recurringEdit = RecurringEdit(item: item, day: day) })
                .tabItem { Label("Planen", systemImage: "calendar") }
                .tag(0)

            TaskListView(model: environment.taskList, onShowDay: showDay,
                         onEditRecurring: { item, day in recurringEdit = RecurringEdit(item: item, day: day) })
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(2)
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

    private func showDay(_ day: PlanDay) {
        environment.planning.anchor = day
        environment.planning.scope = .day
        selectedTab = 0
    }

    private var showsSetup: Binding<Bool> {
        Binding(get: { !environment.settings.setupCompleted }, set: { _ in })
    }
}
