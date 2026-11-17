import AuthenticationServices
import SwiftUI

struct ContentView: View {
    @State private var anthropicKey = ""
    @State private var githubToken = ""
    @State private var results: [ProbeResult] = []
    @State private var isRunning = false
    @State private var saveMessage = ""
    @State private var chatGPTStatus = ""
    @State private var chatGPTSignedIn = false
    @AppStorage("launchesSinceInstall") private var launchesSinceInstall = 0
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    private let probes: [any Probe] = [
        EventKitProbe(), HealthKitProbe(), AppleModelProbe(), ChatGPTProbe(), ClaudeProbe(), GitHubProbe(),
    ]

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

                Section("ChatGPT-Abo") {
                    Button(chatGPTSignedIn ? "Erneut mit ChatGPT anmelden" : "Mit ChatGPT anmelden") {
                        Task { await signInWithChatGPT() }
                    }
                    Button("Token-Erneuerung testen") {
                        Task { await testRefresh() }
                    }
                    .disabled(!chatGPTSignedIn)
                    if !chatGPTStatus.isEmpty { Text(chatGPTStatus).font(.footnote) }
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
                            Text("\(result.skipped ? "⏭️" : (result.ok ? "✅" : "❌")) \(result.name)").font(.headline)
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
        .task { chatGPTSignedIn = await ChatGPTSessionStore.shared.isSignedIn }
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

    private func signInWithChatGPT() async {
        let attempt = await ChatGPTSessionStore.shared.beginSignIn()
        let server = LoopbackServer()
        defer { server.stop() }
        do {
            try server.start()
            let callbackTask = Task { try await server.waitForCallback() }
            do {
                _ = try await webAuthenticationSession.authenticate(
                    using: attempt.url,
                    callback: .customScheme("tagwerkspike"),
                    additionalHeaderFields: [:]
                )
            } catch {
                server.stop()
                throw error
            }
            let callbackURL = try await callbackTask.value
            try await ChatGPTSessionStore.shared.completeSignIn(callbackURL: callbackURL, attempt: attempt)
            chatGPTSignedIn = true
            chatGPTStatus = attempt.isRegistration ? "Registriert und angemeldet" : "Angemeldet"
        } catch {
            chatGPTStatus = "Login fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func testRefresh() async {
        do {
            let rotated = try await ChatGPTSessionStore.shared.forceRefresh()
            chatGPTStatus = rotated ? "Token erneuert, neuer Refresh-Token gespeichert" : "Token erneuert, Refresh-Token unverändert"
        } catch {
            chatGPTStatus = "Erneuerung fehlgeschlagen: \(error.localizedDescription)"
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
