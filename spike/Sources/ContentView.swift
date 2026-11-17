import SwiftUI

struct ContentView: View {
    @State private var anthropicKey = ""
    @State private var githubToken = ""
    @State private var results: [ProbeResult] = []
    @State private var isRunning = false
    @State private var saveMessage = ""
    @AppStorage("launchesSinceInstall") private var launchesSinceInstall = 0

    private let probes: [any Probe] = [EventKitProbe(), HealthKitProbe(), ClaudeProbe(), GitHubProbe()]

    var body: some View {
        NavigationStack {
            Form {
                Section("Zugangsdaten") {
                    SecureField(Secrets.load(account: "anthropic") == nil ? "Anthropic API-Key" : "API-Key gespeichert ✓", text: $anthropicKey)
                    SecureField(Secrets.load(account: "github") == nil ? "GitHub-Token" : "GitHub-Token gespeichert ✓", text: $githubToken)
                    Button("Speichern", action: saveSecrets)
                        .disabled(anthropicKey.isEmpty && githubToken.isEmpty)
                    if !saveMessage.isEmpty { Text(saveMessage).font(.footnote) }
                }

                Section {
                    Button(isRunning ? "Prüfe …" : "Alle Prüfungen starten") {
                        Task { await runAll() }
                    }
                    .disabled(isRunning)
                }

                Section("Ergebnisse") {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(result.ok ? "✅" : "❌") \(result.name)").font(.headline)
                            Text(result.detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Neuinstallation") {
                    Text("Starts seit Installation: \(launchesSinceInstall)")
                }
            }
            .navigationTitle("Tagwerk Spike")
        }
        .onAppear { launchesSinceInstall += 1 }
    }

    private func saveSecrets() {
        do {
            if !anthropicKey.isEmpty { try Secrets.save(anthropicKey, account: "anthropic") }
            if !githubToken.isEmpty { try Secrets.save(githubToken, account: "github") }
            anthropicKey = ""
            githubToken = ""
            saveMessage = "Gespeichert"
        } catch {
            saveMessage = error.localizedDescription
        }
    }

    private func runAll() async {
        isRunning = true
        results = []
        for probe in probes {
            results.append(await probe.run())
        }
        isRunning = false
    }
}
