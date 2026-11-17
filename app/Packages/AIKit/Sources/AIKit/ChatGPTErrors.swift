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
        case .notSignedIn: "Melde dich in den Einstellungen mit ChatGPT an."
        case .usageLimit: "Das Nutzungslimit deines ChatGPT-Abos ist erreicht. Versuche es später erneut."
        case .invalidUser: "Dein ChatGPT-Konto kann hier nicht genutzt werden. Melde dich neu an."
        case .network: "Keine Verbindung zu ChatGPT."
        case .server(let status, _): "ChatGPT hat einen Fehler gemeldet (HTTP \(status))."
        case .incomplete: "Die Antwort von ChatGPT wurde unterbrochen."
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
            "Die Anmeldung braucht Port 1455, der gerade belegt ist. Schließe andere Apps mit ChatGPT-Anmeldung und versuche es erneut."
        case .cancelled: "Anmeldung abgebrochen."
        case .timedOut: "Die Anmeldung hat zu lange gedauert. Versuche es erneut."
        case .network: "Keine Verbindung zu ChatGPT."
        case .authorizationFailed(let message): "ChatGPT hat die Anmeldung abgelehnt: \(message)"
        case .tokenExchangeFailed(let status, let code):
            "Die Anmeldung ist fehlgeschlagen (HTTP \(status)\(code.map { ", \($0)" } ?? ""))."
        case .stateMismatch, .missingCode, .missingIssuedClientID, .clientIDMismatch, .nonceMismatch, .serverFailed:
            "Die Anmeldung ist fehlgeschlagen. Versuche es erneut."
        }
    }
}
