import CryptoKit
import Foundation

/// Code and issued client of a sign-in callback.
public struct ChatGPTCallback: Equatable, Sendable {
    public let code: String
    public let clientID: String?
}

/// Claims of the ID token that the app uses. Decoded only, never verified: the token comes over TLS
/// straight from the token endpoint.
public struct ChatGPTIDTokenClaims: Equatable, Sendable {
    public var nonce: String?
    public var email: String?
    public var accountID: String?
}

/// Pure building blocks of the "Sign in with ChatGPT" self-serve flow (OAuth 2.0 with PKCE).
public enum ChatGPTAuth {
    static let authorizeEndpoint = "https://auth.openai.com/api/accounts/authorize"
    static let tokenEndpoint = "https://auth.openai.com/api/accounts/oauth/token"
    static let redirectURI = "http://127.0.0.1:1455/auth/callback"
    static let callbackPath = "/auth/callback"
    static let resource = "https://api.openai.com/v1"
    static let scope = "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct"
    static let registrationClientID = "dynamic_agent_client"
    static let agentName = "Tagwerk"
    /// Lifetime assumed when the token endpoint omits `expires_in`.
    static let defaultLifetime: TimeInterval = 3600

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

    /// The `state` parameter of a callback URL, if any.
    static func state(of url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "state" }?.value
    }

    static func parseCallback(_ url: URL, expectedState: String, isRegistration: Bool) throws -> ChatGPTCallback {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        guard value("state") == expectedState else { throw ChatGPTAuthError.stateMismatch }
        if let error = value("error") {
            throw ChatGPTAuthError.authorizationFailed(value("error_description") ?? error)
        }
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

    /// Decodes the payload of a JWT without verifying it.
    static func idTokenClaims(_ token: String) -> ChatGPTIDTokenClaims? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        var payload = parts[1].replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let auth = json["https://api.openai.com/auth"] as? [String: Any]
        return ChatGPTIDTokenClaims(
            nonce: json["nonce"] as? String,
            email: json["email"] as? String,
            accountID: auth?["chatgpt_account_id"] as? String
        )
    }

    /// Result of a token endpoint call.
    enum TokenResponse {
        case tokens(access: String, refresh: String?, idToken: String?, expiresIn: TimeInterval?)
        /// Non-200 answer with the OAuth error code, if the body carried one.
        case failure(status: Int, code: String?)
    }

    static func parseTokenResponse(status: Int, body: Data) -> TokenResponse {
        let json = (try? JSONSerialization.jsonObject(with: body) as? [String: Any]) ?? [:]
        if status == 200, let access = json["access_token"] as? String, !access.isEmpty {
            return .tokens(
                access: access,
                refresh: json["refresh_token"] as? String,
                idToken: json["id_token"] as? String,
                expiresIn: (json["expires_in"] as? NSNumber)?.doubleValue
            )
        }
        return .failure(status: status, code: errorCode(in: json))
    }

    /// The error code of an OAuth (`{"error":"code"}`) or OpenAI (`{"error":{"code":…}}`) error body.
    static func errorCode(in json: [String: Any]) -> String? {
        if let code = json["error"] as? String { return code }
        if let error = json["error"] as? [String: Any] {
            return error["code"] as? String ?? error["type"] as? String
        }
        return nil
    }

    private static func formRequest(_ fields: [(String, String)]) -> URLRequest {
        var request = URLRequest(url: URL(string: tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        request.httpBody = Data(fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&").utf8)
        return request
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
