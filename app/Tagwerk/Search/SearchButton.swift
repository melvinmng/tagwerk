import SwiftUI

/// The magnifier in the bars of "Planen" and "Aufgaben"; opens the search sheet. Off while the voice mode runs,
/// like the other sheets.
struct SearchButton: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Button { environment.openSearch() } label: {
            Label("Suchen", systemImage: "magnifyingglass")
        }
        .disabled(environment.voiceMode.isRunning)
        .accessibilityHint("Durchsucht Termine und Aufgaben")
    }
}
