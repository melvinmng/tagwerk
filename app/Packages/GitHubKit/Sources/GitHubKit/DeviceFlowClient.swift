import Foundation

/// Code the user enters on github.com/login/device.
public struct DeviceCode: Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationURL: URL
    public let expiresIn: Int
    public let interval: Int

    public init(deviceCode: String, userCode: String, verificationURL: URL, expiresIn: Int, interval: Int) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// OAuth device flow and token refresh for a GitHub OAuth app without client secret.
public struct DeviceFlowClient: Sendable {
    public static let scope = "repo project offline_access"
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    private let clientID: String
    private let transport: HTTPTransport
    private let sleep: @Sendable (Duration) async throws -> Void
    private let now: @Sendable () -> Date

    public init(
        clientID: String,
        transport: HTTPTransport,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.clientID = clientID
        self.transport = transport
        self.sleep = sleep
        self.now = now
    }

    public func requestCode() async throws -> DeviceCode {
        let json = try await post(Self.deviceCodeURL, [("client_id", clientID), ("scope", Self.scope)])
        if let error = json["error"] as? String { throw GitHubAuthError.server(error) }
        guard let deviceCode = json["device_code"] as? String,
              let userCode = json["user_code"] as? String,
              let uri = (json["verification_uri"] as? String).flatMap(URL.init(string:)) else {
            throw GitHubAuthError.server("invalid device code response")
        }
        return DeviceCode(
            deviceCode: deviceCode, userCode: userCode, verificationURL: uri,
            expiresIn: json["expires_in"] as? Int ?? 900, interval: json["interval"] as? Int ?? 5
        )
    }

    /// Polls until the user confirms, honouring `slow_down`, `expired_token` and `access_denied`.
    public func pollForToken(_ code: DeviceCode) async throws -> GitHubCredentials {
        let deadline = now().addingTimeInterval(TimeInterval(code.expiresIn))
        var interval = code.interval
        while now() < deadline {
            try await sleep(.seconds(interval))
            let json: [String: Any]
            do {
                json = try await post(Self.tokenURL, [
                    ("client_id", clientID),
                    ("device_code", code.deviceCode),
                    ("grant_type", "urn:ietf:params:oauth:grant-type:device_code"),
                ])
            } catch GitHubAuthError.network {
                // iOS suspends the app while the user confirms in Safari, which drops the
                // in-flight request. The device code stays valid, so keep polling.
                continue
            }
            switch json["error"] as? String {
            case nil:
                return try credentials(from: json)
            case "authorization_pending":
                continue
            case "slow_down":
                interval = json["interval"] as? Int ?? interval + 5
            case "expired_token":
                throw GitHubAuthError.expired
            case "access_denied":
                throw GitHubAuthError.denied
            case let error?:
                throw GitHubAuthError.server(error)
            }
        }
        throw GitHubAuthError.expired
    }

    /// Exchanges a refresh token for new credentials. The refresh token rotates and is single-use.
    public func refresh(_ refreshToken: String) async throws -> GitHubCredentials {
        let json = try await post(Self.tokenURL, [
            ("client_id", clientID),
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
        ])
        if let error = json["error"] as? String { throw GitHubAuthError.server(error) }
        return try credentials(from: json)
    }

    private func credentials(from json: [String: Any]) throws -> GitHubCredentials {
        guard let accessToken = json["access_token"] as? String else {
            throw GitHubAuthError.server("missing access_token")
        }
        let issuedAt = now()
        return GitHubCredentials(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            accessExpiresAt: (json["expires_in"] as? Int).map { issuedAt.addingTimeInterval(TimeInterval($0)) },
            refreshExpiresAt: (json["refresh_token_expires_in"] as? Int).map { issuedAt.addingTimeInterval(TimeInterval($0)) }
        )
    }

    private func post(_ url: URL, _ fields: [(String, String)]) async throws -> [String: Any] {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(.formPost(url, fields))
        } catch {
            throw GitHubAuthError.network(error.localizedDescription)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAuthError.server("HTTP \(response.statusCode)")
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw GitHubAuthError.server("invalid response")
        }
        return json
    }
}
