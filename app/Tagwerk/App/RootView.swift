import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            NavigationStack {
                Text("Aufgaben folgen hier.")
                    .navigationTitle("Aufgaben")
            }
            .tabItem { Label("Aufgaben", systemImage: "checklist") }

            NavigationStack {
                Text("Einstellungen folgen hier.")
                    .navigationTitle("Einstellungen")
            }
            .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
    }
}

#Preview {
    RootView()
}
