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
                               planned: environment.planning.plannedInfo(for: task.id),
                               onShowDay: showDay) { saved in
                    environment.taskList.didSave(saved)
                }
            }
        }
        .sheet(item: $openEvent) { event in
            EventDetailView(event: event, model: environment.planning) { task in
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))  // let the event sheet close first
                    editingTask = task
                }
            }
        }
        .sheet(item: $recurringEdit) { edit in
            RecurringEffortSheet(item: edit.item, day: edit.day, model: environment.planning)
        }
        .fullScreenCover(isPresented: showsSetup) {
            SetupView(model: environment.makeSetupModel(), loginModel: environment.makeGitHubLoginModel()) {
                await environment.taskList.reload()
            }
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
