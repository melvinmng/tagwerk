import Foundation
import Synchronization
@testable import GitHubKit

/// Scripted HTTP transport: answers requests per path from a queue and records every request.
final class StubTransport: HTTPTransport {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError.Code)
    }

    private struct State {
        var replies: [String: [Reply]] = [:]
        var requests: [URLRequest] = []
    }

    private let state = Mutex(State())

    /// Queues a reply for requests whose URL path (plus query, if any) starts with `path`.
    func enqueue(_ path: String, _ reply: Reply) {
        state.withLock { $0.replies[path, default: []].append(reply) }
    }

    func enqueueJSON(_ path: String, status: Int = 200, _ body: String) {
        enqueue(path, .json(status, body))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { Self.key(for: $0).hasPrefix(path) }
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = state.withLock { state in
            state.requests.append(request)
            let key = Self.key(for: request)
            guard let path = state.replies.keys.filter({ key.hasPrefix($0) }).max(by: { $0.count < $1.count }),
                  var queue = state.replies[path], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            state.replies[path] = queue
            return next
        }
        switch reply {
        case .json(let status, let body):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (Data(body.utf8), response)
        case .failure(let code):
            throw URLError(code)
        case nil:
            throw URLError(.resourceUnavailable)
        }
    }

    private static func key(for request: URLRequest) -> String {
        guard let url = request.url else { return "" }
        return url.query.map { "\(url.path)?\($0)" } ?? url.path
    }
}

/// Records requested sleeps instead of sleeping.
final class SleepRecorder: Sendable {
    private let recorded = Mutex<[Duration]>([])
    var sleeps: [Duration] { recorded.withLock { $0 } }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in self.recorded.withLock { $0.append(duration) } }
    }
}

/// In-memory credential store.
final class MemoryCredentialStore: CredentialStore {
    private let stored: Mutex<GitHubCredentials?>
    private let saves = Mutex(0)

    init(_ credentials: GitHubCredentials? = nil) {
        stored = Mutex(credentials)
    }

    var current: GitHubCredentials? { stored.withLock { $0 } }
    var saveCount: Int { saves.withLock { $0 } }

    func load() throws -> GitHubCredentials? { stored.withLock { $0 } }
    func save(_ credentials: GitHubCredentials) throws {
        stored.withLock { $0 = credentials }
        saves.withLock { $0 += 1 }
    }
    func delete() throws { stored.withLock { $0 = nil } }
}

extension URLRequest {
    var bodyString: String { httpBody.map { String(decoding: $0, as: UTF8.self) } ?? "" }
}

let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// Credential store whose reads fail while "locked", like the keychain before the first unlock.
final class LockableCredentialStore: CredentialStore {
    struct Locked: Error {}
    private let stored: Mutex<GitHubCredentials?>
    private let locked = Mutex(true)
    private let deletes = Mutex(0)

    init(_ credentials: GitHubCredentials?) {
        stored = Mutex(credentials)
    }

    var deleteCount: Int { deletes.withLock { $0 } }
    func unlock() { locked.withLock { $0 = false } }

    func load() throws -> GitHubCredentials? {
        if locked.withLock({ $0 }) { throw Locked() }
        return stored.withLock { $0 }
    }
    func save(_ credentials: GitHubCredentials) throws { stored.withLock { $0 = credentials } }
    func delete() throws {
        deletes.withLock { $0 += 1 }
        stored.withLock { $0 = nil }
    }
}
