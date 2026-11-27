import Foundation
import Network
import Synchronization
import Testing
@testable import AIKit

let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

/// Scripted transport: answers requests per URL path from a queue and records every request.
final class StubAITransport: AIHTTPTransport {
    enum Reply: Sendable {
        case json(Int, String)
        case failure(URLError.Code)
        /// Waits until `release()` is called, then answers with the JSON.
        case gated(Int, String)
    }

    private struct State {
        var replies: [String: [Reply]] = [:]
        var requests: [URLRequest] = []
    }

    private let state = Mutex(State())
    private let gate = Gate()
    /// Opens as soon as a request is parked at the gate, so tests can wait for it instead of sleeping.
    let entered = Gate()

    func enqueue(_ path: String, _ reply: Reply) {
        state.withLock { $0.replies[path, default: []].append(reply) }
    }

    func enqueueJSON(_ path: String, status: Int = 200, _ body: String) {
        enqueue(path, .json(status, body))
    }

    /// Lets gated replies continue.
    func release() { gate.open() }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func requests(to path: String) -> [URLRequest] {
        requests.filter { $0.url?.path == path }
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply: Reply? = state.withLock { state in
            state.requests.append(request)
            let path = request.url?.path ?? ""
            guard var queue = state.replies[path], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            state.replies[path] = queue
            return next
        }
        switch reply {
        case .json(let status, let body):
            return Self.response(request, status, body)
        case .gated(let status, let body):
            entered.open()
            await gate.wait()
            return Self.response(request, status, body)
        case .failure(let code):
            throw URLError(code)
        case nil:
            throw URLError(.resourceUnavailable)
        }
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        return (AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }, response)
    }

    private static func response(_ request: URLRequest, _ status: Int, _ body: String) -> (Data, HTTPURLResponse) {
        (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

/// A one-shot gate that suspends callers until it is opened.
final class Gate: Sendable {
    private let state = Mutex<(open: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))

    func wait() async {
        await withCheckedContinuation { continuation in
            let resumeNow = state.withLock { state -> Bool in
                if state.open { return true }
                state.waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    var isOpen: Bool { state.withLock { $0.open } }

    func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.open = true
            defer { state.waiters = [] }
            return state.waiters
        }
        waiters.forEach { $0.resume() }
    }
}

/// Credential store that can be told to fail writes.
final class FailingTokenWriteStore: ChatGPTCredentialStore {
    let inner = InMemoryChatGPTCredentialStore()
    func loadTokens() throws -> ChatGPTTokens? { try inner.loadTokens() }
    func saveTokens(_ tokens: ChatGPTTokens) throws { throw URLError(.cannotWriteToFile) }
    func deleteTokens() throws { try inner.deleteTokens() }
    func loadClientID() throws -> String? { try inner.loadClientID() }
    func saveClientID(_ clientID: String) throws { try inner.saveClientID(clientID) }
    func loadHostID() throws -> String? { try inner.loadHostID() }
    func saveHostID(_ hostID: String) throws { try inner.saveHostID(hostID) }
}

extension URLRequest {
    var bodyFields: Set<String> {
        Set(String(decoding: httpBody ?? Data(), as: UTF8.self).split(separator: "&").map(String.init))
    }
}

/// Builds an unsigned JWT with the given payload claims (the app only decodes it).
func makeJWT(_ claims: [String: Any]) -> String {
    func encode(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    return "\(encode(["alg": "none"])).\(encode(claims)).signature"
}

/// Minimal raw TCP client for driving the loopback server, so requests can be split into chunks.
enum RawHTTPClient {
    /// Sends `chunks` with a short pause between them and returns the full response text.
    static func send(_ chunks: [String], port: UInt16) async throws -> String {
        let connection = NWConnection(
            host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp
        )
        let queue = DispatchQueue(label: "raw-http-client")
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let resumed = Mutex(false)
            connection.stateUpdateHandler = { state in
                let result: Result<Void, Error>?
                switch state {
                case .ready: result = .success(())
                case .failed(let error), .waiting(let error): result = .failure(error)
                default: result = nil
                }
                guard let result, resumed.withLock({ let was = $0; $0 = true; return !was }) else { return }
                continuation.resume(with: result)
            }
            connection.start(queue: queue)
        }
        for (index, chunk) in chunks.enumerated() {
            if index > 0 { try await Task.sleep(for: .milliseconds(50)) }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                connection.send(content: Data(chunk.utf8), completion: .contentProcessed { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                })
            }
        }
        var received = Data()
        while true {
            let (data, isComplete): (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: (data, isComplete)) }
                }
            }
            if let data { received.append(data) }
            // Responses carry no body, so the blank line ends them. Like a browser, the client closes first.
            if isComplete || data == nil || received.range(of: Data("\r\n\r\n".utf8)) != nil { break }
        }
        connection.cancel()
        return String(decoding: received, as: UTF8.self)
    }

    static func get(_ pathAndQuery: String, port: UInt16) async throws -> String {
        try await send(["GET \(pathAndQuery) HTTP/1.1\r\nHost: 127.0.0.1:\(port)\r\n\r\n"], port: port)
    }
}

extension LoopbackServer {
    /// Starts a server on a port the system picks, so no test depends on a fixed or guessed port, and returns
    /// the port it is bound to.
    static func startOnFreePort(expectedState: String) async throws -> (server: LoopbackServer, port: UInt16) {
        let server = LoopbackServer(port: 0, expectedState: expectedState)
        try await server.start()
        let port = try #require(server.listeningPort, "A ready server reports its port")
        return (server, port)
    }
}
