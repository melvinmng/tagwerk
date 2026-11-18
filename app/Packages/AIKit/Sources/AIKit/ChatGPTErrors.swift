import Foundation

/// Errors of ChatGPT calls that the app shows to the user.
public enum ChatGPTError: Error, Equatable, Sendable {
    /// No usable session; the user has to sign in.
    case notSignedIn
    /// HTTP 429 `subscription_sharing_usage_limit_exceeded`.
    case usageLimit
    /// HTTP 401 `subscription_sharing_invalid_user`.
    case invalidUser
    /// Transport failure (offline, timeout, connection lost).
    case network
    /// Any other server answer: HTTP status and, if present, the error code.
    case server(Int, String?)
    /// The stream ended before `response.completed`.
    case incomplete

    public var userMessage: String {
        switch self {
        case .notSignedIn: String(localized: "Melde dich in den Einstellungen mit ChatGPT an.", bundle: .module)
        case .usageLimit: String(localized: "Das Nutzungslimit deines ChatGPT-Abos ist erreicht. Versuche es später erneut.", bundle: .module)
        case .invalidUser: String(localized: "Dein ChatGPT-Konto kann hier nicht genutzt werden. Melde dich neu an.", bundle: .module)
        case .network: String(localized: "Keine Verbindung zu ChatGPT.", bundle: .module)
        case .server(let status, _): String(localized: "ChatGPT hat einen Fehler gemeldet (HTTP \(status)).", bundle: .module)
        case .incomplete: String(localized: "Die Antwort von ChatGPT wurde unterbrochen.", bundle: .module)
        }
    }
}

/// Errors of the sign-in flow.
public enum ChatGPTAuthError: Error, Equatable, Sendable {
    case stateMismatch
    case missingCode
    case missingIssuedClientID
    /// The callback names another client than the one registered earlier.
    case clientIDMismatch
    /// The ID token's `nonce` claim differs from the value sent with the authorize request.
    case nonceMismatch
    /// The authorize endpoint answered with an `error` parameter.
    case authorizationFailed(String)
    /// The token endpoint rejected the code exchange.
    case tokenExchangeFailed(status: Int, code: String?)
    /// Port 1455 on 127.0.0.1 is taken by another process.
    case portInUse
    /// The loopback server could not start for another reason.
    case serverFailed(String)
    /// The user closed the sign-in sheet.
    case cancelled
    /// No callback arrived in time.
    case timedOut
    case network

    public var userMessage: String {
        switch self {
        case .portInUse:
            String(localized: "Die Anmeldung braucht Port 1455, der gerade belegt ist. Schließe andere Apps mit ChatGPT-Anmeldung und versuche es erneut.", bundle: .module)
        case .cancelled: String(localized: "Anmeldung abgebrochen.", bundle: .module)
        case .timedOut: String(localized: "Die Anmeldung hat zu lange gedauert. Versuche es erneut.", bundle: .module)
        case .network: String(localized: "Keine Verbindung zu ChatGPT.", bundle: .module)
        case .authorizationFailed(let message): String(localized: "ChatGPT hat die Anmeldung abgelehnt: \(message)", bundle: .module)
        case .tokenExchangeFailed(let status, let code):
            // The code is part of the whole sentence, so that a translation can place it freely.
            code.map { String(localized: "Die Anmeldung ist fehlgeschlagen (HTTP \(status), \($0)).", bundle: .module) }
                ?? String(localized: "Die Anmeldung ist fehlgeschlagen (HTTP \(status)).", bundle: .module)
        case .stateMismatch, .missingCode, .missingIssuedClientID, .clientIDMismatch, .nonceMismatch, .serverFailed:
            String(localized: "Die Anmeldung ist fehlgeschlagen. Versuche es erneut.", bundle: .module)
        }
    }
}
