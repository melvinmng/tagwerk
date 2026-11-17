import SwiftUI
import TagwerkCore

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            PlanView(model: environment.planning,
                     onOpenTask: { _ in selectedTab = 1 },
                     onOpenEvent: { _ in },
                     onEditRecurring: { _, _ in })
                .tabItem { Label("Planen", systemImage: "calendar") }
                .tag(0)

            TaskListView(model: environment.taskList)
                .tabItem { Label("Aufgaben", systemImage: "checklist") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
                .tag(2)
        }
        .fullScreenCover(isPresented: showsSetup) {
            SetupView(model: environment.makeSetupModel(), loginModel: environment.makeGitHubLoginModel()) {
                await environment.taskList.reload()
            }
        }
    }

    private var showsSetup: Binding<Bool> {
        Binding(get: { !environment.settings.setupCompleted }, set: { _ in })
    }
}
