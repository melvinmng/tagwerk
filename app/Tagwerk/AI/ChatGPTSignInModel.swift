import AIKit
import Foundation
import Observation

/// A status line below or above the sign-in button (mockup P2): warnings with ⚠︎, a cancellation in grey.
struct AIStatusMessage: Equatable {
    let text: String
    let isWarning: Bool

    static var privacyNotice: String {
        String(localized: "Wenn du KI-Funktionen nutzt, gehen die dafür nötigen Daten (Termine, Aufgaben, bei Issues auch Repo-Inhalte und GitHub-Benutzernamen zuweisbarer und zugewiesener Personen) an OpenAI.")
    }
    static var expired: AIStatusMessage {
        AIStatusMessage(text: String(localized: "Die Anmeldung ist abgelaufen. Melde dich erneut an."), isWarning: true)
    }

    /// Message for a failed sign-in; a cancellation is the user's own choice and not a warning.
    static func signInFailure(_ error: Error) -> AIStatusMessage {
        switch error {
        case ChatGPTAuthError.cancelled:
            AIStatusMessage(text: ChatGPTAuthError.cancelled.userMessage, isWarning: false)
        case let error as ChatGPTAuthError:
            AIStatusMessage(text: error.userMessage, isWarning: true)
        case let error as ChatGPTError:
            AIStatusMessage(text: error.userMessage, isWarning: true)
        default:
            AIStatusMessage(text: String(localized: "Die Anmeldung ist fehlgeschlagen. Versuche es erneut."), isWarning: true)
        }
    }
}

/// Runs "Mit ChatGPT anmelden" for the settings page and the setup step.
@MainActor
@Observable
final class ChatGPTSignInModel {
    private(set) var isSigningIn = false
    var message: AIStatusMessage?
    @ObservationIgnored private let ai: AIEnvironment
    @ObservationIgnored private let authenticator = SystemWebAuthenticator()

    init(ai: AIEnvironment) {
        self.ai = ai
    }

    /// Reads the sign-in state from the keychain; sends nothing.
    func isSignedIn() async -> Bool {
        await ai.refreshAccount()
        return ai.isSignedIn
    }

    /// Returns true after a successful sign-in.
    @discardableResult
    func signIn() async -> Bool {
        guard !isSigningIn else { return false }
        isSigningIn = true
        message = nil
        defer { isSigningIn = false }
        do {
            try await ai.signIn(authenticator: authenticator)
            return true
        } catch {
            message = AIStatusMessage.signInFailure(error)
            return false
        }
    }
}
