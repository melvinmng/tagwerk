import Foundation
import GitHubKit
import Synchronization
@testable import Tagwerk

/// Scripted device login.
final class FakeDeviceLogin: DeviceLogin {
    let code = DeviceCode(deviceCode: "dev", userCode: "ABCD-1234",
                          verificationURL: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5)
    private let outcome: Mutex<Result<GitHubCredentials, GitHubAuthError>>

    init(outcome: Result<GitHubCredentials, GitHubAuthError>) {
        self.outcome = Mutex(outcome)
    }

    func requestCode() async throws -> DeviceCode { code }

    func pollForToken(_ code: DeviceCode) async throws -> GitHubCredentials {
        try outcome.withLock { $0 }.get()
    }
}

final class MemoryCredentials: CredentialStore {
    private let stored = Mutex<GitHubCredentials?>(nil)
    var current: GitHubCredentials? { stored.withLock { $0 } }
    func load() throws -> GitHubCredentials? { stored.withLock { $0 } }
    func save(_ credentials: GitHubCredentials) throws { stored.withLock { $0 = credentials } }
    func delete() throws { stored.withLock { $0 = nil } }
}

func makeTokenManager(_ store: MemoryCredentials) -> TokenManager {
    let client = DeviceFlowClient(clientID: "client", transport: URLSessionTransport())
    return TokenManager(store: store, client: client)
}
