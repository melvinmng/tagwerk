import GitHubKit
import RemindersKit
import SwiftUI

/// "GitHub" section of the settings: login state, project choice and sign-out.
struct GitHubSettingsSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var loginModel: GitHubLoginModel?

    var body: some View {
        @Bindable var settings = environment.settings
        Section {
            if environment.isGitHubActive {
                LabeledContent("Angemeldet als", value: environment.gitHub.login ?? "…")
                NavigationLink {
                    SourceSelectionView(title: "Projects", items: projectItems,
                                        defaultSelection: environment.gitHub.defaultSelectedProjectIDs,
                                        selection: $settings.selectedProjectIDs)
                } label: {
                    LabeledContent("Projects", value: projectSummary)
                }
                Button("Abmelden", role: .destructive) {
                    Task { await (loginModel ?? environment.makeGitHubLoginModel()).signOut() }
                }
            } else if let loginModel {
                GitHubLoginView(model: loginModel)
            }
        } header: {
            Text("GitHub")
        } footer: {
            Text("Die Anmeldung erneuert sich automatisch. Ohne Nutzung läuft sie nach etwa 6 Monaten ab. Vollständig widerrufen: github.com → Settings → Applications → Authorized OAuth Apps.")
        }
        .task { if loginModel == nil { loginModel = environment.makeGitHubLoginModel() } }
        .onChange(of: settings.selectedProjectIDs) { _, _ in
            Task { await environment.taskList.reload() }
        }
    }

    private var projectItems: [ListInfo] {
        environment.gitHub.projects.map { ListInfo(id: $0.id, title: $0.title, colorHex: nil, kind: .other) }
    }

    private var projectSummary: String {
        let all = environment.gitHub.projects
        guard !all.isEmpty else { return "–" }
        let selected = environment.settings.selectedProjectIDs.map(Set.init) ?? environment.gitHub.defaultSelectedProjectIDs
        let count = selected.intersection(all.map(\.id)).count
        return "\(count) von \(all.count)"
    }
}
