import Foundation
import GitHubKit
import Observation

/// The device-flow steps the login needs; `DeviceFlowClient` is the real implementation.
protocol DeviceLogin: Sendable {
    func requestCode() async throws -> DeviceCode
    func pollForToken(_ code: DeviceCode) async throws -> GitHubCredentials
}

extension DeviceFlowClient: DeviceLogin {}

/// "Mit GitHub anmelden": shows the user code, waits for confirmation on github.com, stores the tokens.
@MainActor
@Observable
final class GitHubLoginModel {
    enum Phase: Equatable {
        case idle
        case requestingCode
        case showingCode(DeviceCode)
        case signedIn(String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private let login: any DeviceLogin
    private let tokens: TokenManager
    private let onSignedIn: () async -> String?
    private let onSignedOut: () async -> Void
    @ObservationIgnored private var loginTask: Task<Void, Never>?

    init(login: any DeviceLogin, tokens: TokenManager,
         onSignedIn: @escaping () async -> String?, onSignedOut: @escaping () async -> Void) {
        self.login = login
        self.tokens = tokens
        self.onSignedIn = onSignedIn
        self.onSignedOut = onSignedOut
    }

    /// Runs the whole device flow; returns when signed in, failed or cancelled.
    func start() async {
        loginTask?.cancel()
        let task = Task { await runLogin() }
        loginTask = task
        await task.value
    }

    func cancel() {
        loginTask?.cancel()
        loginTask = nil
        phase = .idle
    }

    func signOut() async {
        try? await tokens.signOut()
        await onSignedOut()
        phase = .idle
    }

    private func runLogin() async {
        phase = .requestingCode
        do {
            let code = try await login.requestCode()
            phase = .showingCode(code)
            let credentials = try await login.pollForToken(code)
            try await tokens.store(credentials)
            let name = await onSignedIn()
            phase = .signedIn(name ?? "GitHub")
        } catch is CancellationError {
            phase = .idle
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    static func message(for error: Error) -> String {
        switch error {
        case GitHubAuthError.expired: "Der Code ist abgelaufen. Bitte neu starten."
        case GitHubAuthError.denied: "Die Anmeldung wurde auf GitHub abgelehnt."
        case GitHubAuthError.network: "Keine Verbindung zu GitHub."
        default: "Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
