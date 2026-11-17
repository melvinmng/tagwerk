import SwiftUI

struct RootView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        TabView {
            TaskListView(model: environment.taskList)
                .tabItem { Label("Aufgaben", systemImage: "checklist") }

            NavigationStack {
                Text("Einstellungen folgen hier.")
                    .navigationTitle("Einstellungen")
            }
            .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}
