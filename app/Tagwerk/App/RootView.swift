import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TabView {
            TaskListView(model: environment.taskList)
                .tabItem { Label("Aufgaben", systemImage: "checklist") }

            SettingsView()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: showsSetup) {
            SetupView(model: environment.makeSetupModel()) {
                await environment.taskList.reload()
            }
        }
    }

    private var showsSetup: Binding<Bool> {
        Binding(get: { !environment.settings.setupCompleted }, set: { _ in })
    }
}
