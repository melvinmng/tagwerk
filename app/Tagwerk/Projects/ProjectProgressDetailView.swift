import SwiftUI
import TagwerkCore

/// The page of one project in the project progress (#332). Pushed onto the navigation stack of the tab "Aufgaben" with
/// `TasksDestination.projectProgress`; the global search opens it the same way.
struct ProjectProgressDetailView: View {
    let reference: ProjectProgressReference

    var body: some View {
        List {
            Text(reference.title).font(.headline)
        }
        .navigationTitle(reference.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
