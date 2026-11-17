import CryptoKit
import Foundation

struct ChatGPTCallback: Equatable {
    let code: String
    let clientID: String?
}

enum ChatGPTAuthError: LocalizedError {
    case stateMismatch
    case missingCode
    case missingIssuedClientID
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .stateMismatch: return "Login abgebrochen: state stimmt nicht überein"
        case .missingCode: return "Login abgebrochen: kein Autorisierungscode"
        case .missingIssuedClientID: return "Registrierung unvollständig: keine client_id im Rücksprung"
        case .serverError(let message): return "Login-Fehler: \(message)"
        }
    }
}

/// Pure building blocks of the "Sign in with ChatGPT" open-source self-serve flow (OAuth 2.0 + PKCE).
enum ChatGPTAuth {
    static let authorizeEndpoint = "https://auth.openai.com/api/accounts/authorize"
    static let tokenEndpoint = "https://auth.openai.com/api/accounts/oauth/token"
    static let redirectURI = "http://127.0.0.1:1455/auth/callback"
    static let resource = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let registrationClientID = "dynamic_agent_client"
    static let agentName = "Tagwerk"

    static func codeChallenge(verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    static func randomURLSafeString(byteCount: Int = 32) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URL(Data(bytes))
    }

    /// Builds the authorize URL. `clientID == nil` means first-time registration.
    static func authorizeURL(clientID: String?, hostID: String, state: String, nonce: String, challenge: String) -> URL {
        var components = URLComponents(string: authorizeEndpoint)!
        var items = [URLQueryItem(name: "client_id", value: clientID ?? registrationClientID)]
        if clientID == nil {
            items.append(URLQueryItem(name: "agent_name_hint", value: agentName))
        }
        items += [
            URLQueryItem(name: "ext_agent_host_id", value: hostID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: scope),
            URLQueryItem(name: "resource", value: resource),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: challenge),
        ]
        components.queryItems = items
        return components.url!
    }

    static func parseCallback(_ url: URL, expectedState: String, isRegistration: Bool) throws -> ChatGPTCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw ChatGPTAuthError.serverError(value("error_description") ?? error)
        }
        guard value("state") == expectedState else { throw ChatGPTAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw ChatGPTAuthError.missingCode }
        let clientID = value("client_id")
        if isRegistration && (clientID == nil || clientID == registrationClientID) {
            throw ChatGPTAuthError.missingIssuedClientID
        }
        return ChatGPTCallback(code: code, clientID: clientID)
    }

    static func tokenRequest(clientID: String, code: String, verifier: String) -> URLRequest {
        formRequest([
            ("grant_type", "authorization_code"),
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("redirect_uri", redirectURI),
            ("resource", resource),
        ])
    }

    static func refreshRequest(clientID: String, refreshToken: String) -> URLRequest {
        formRequest([
            ("grant_type", "refresh_token"),
            ("client_id", clientID),
            ("refresh_token", refreshToken),
            ("resource", resource),
        ])
    }

    private static func formRequest(_ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&")
            .data(using: .utf8)
        return request
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
