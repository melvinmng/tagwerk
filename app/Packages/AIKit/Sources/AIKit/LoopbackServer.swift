import Foundation
import Network
import Synchronization

/// One-shot HTTP listener on 127.0.0.1 that captures the OAuth callback and redirects the
/// sign-in sheet to `tagwerk://auth/done`, which closes the sheet.
///
/// Rules (Phase 2 design §7): it waits for `.ready` before the sheet opens, reports a taken port
/// as an error instead of sharing it, reads each request up to the blank line, and ignores
/// callbacks with a wrong `state` instead of aborting the sign-in.
public final class LoopbackServer: Sendable {
    public static let finishURL = "tagwerk://auth/done"
    static let maxRequestBytes = 16_384
    /// How long a served connection may stay open waiting for the browser to close it first.
    static let lingerAfterResponse: TimeInterval = 2

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<URL, Error>
    }

    private struct State {
        var listener: NWListener?
        var connections: [ObjectIdentifier: NWConnection] = [:]
        var isReady = false
        var isStopped = false
        var capturedURL: URL?
        /// Set once the server cannot deliver a callback any more (stopped or failed).
        var terminalError: ChatGPTAuthError?
        var waiter: Waiter?
    }

    private let port: UInt16
    private let expectedState: String
    private let queue = DispatchQueue(label: "tagwerk.chatgpt.loopback")
    private let state = Mutex(State())

    public init(port: UInt16 = 1455, expectedState: String) {
        self.port = port
        self.expectedState = expectedState
    }

    public var isReady: Bool { state.withLock { $0.isReady } }
    var capturedURL: URL? { state.withLock { $0.capturedURL } }

    /// Starts listening and returns once the listener is ready.
    public func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = false
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw Self.map(error)
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        state.withLock { $0.listener = listener }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pending = Mutex<CheckedContinuation<Void, Error>?>(continuation)
            let resume: @Sendable (Result<Void, Error>) -> Void = { result in
                pending.withLock { $0.take() }?.resume(with: result)
            }
            listener.stateUpdateHandler = { [weak self] newState in
                switch newState {
                case .ready:
                    self?.state.withLock { $0.isReady = true }
                    resume(.success(()))
                case .failed(let error), .waiting(let error):
                    let mapped = Self.map(error)
                    resume(.failure(mapped))
                    self?.fail(with: mapped)
                    listener.cancel()
                case .cancelled:
                    resume(.failure(ChatGPTAuthError.cancelled))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Stops listening, closes open connections and fails a pending wait. Returns once the port is released.
    public func stop() async {
        let (listener, connections) = state.withLock { state -> (NWListener?, [NWConnection]) in
            state.isStopped = true
            state.isReady = false
            defer { state.listener = nil; state.connections = [:] }
            return (state.listener, Array(state.connections.values))
        }
        fail(with: .cancelled)
        connections.forEach { $0.cancel() }
        guard let listener else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let pending = Mutex<CheckedContinuation<Void, Never>?>(continuation)
            let resume: @Sendable () -> Void = { pending.withLock { $0.take() }?.resume() }
            listener.stateUpdateHandler = { newState in
                if case .cancelled = newState { resume() }
            }
            if case .cancelled = listener.state { resume() }
            listener.cancel()
            // Safety net in case the listener never reports `.cancelled`.
            queue.asyncAfter(deadline: .now() + 1, execute: resume)
        }
    }

    /// Waits for the callback request with the expected `state`.
    public func waitForCallback(timeout: TimeInterval = 300) async throws -> URL {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let immediate: Result<URL, Error>? = state.withLock { state in
                if let url = state.capturedURL { return .success(url) }
                if let error = state.terminalError { return .failure(error) }
                state.waiter = Waiter(id: id, continuation: continuation)
                return nil
            }
            if let immediate {
                continuation.resume(with: immediate)
                return
            }
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                let waiter = self?.state.withLock { state -> Waiter? in
                    guard state.waiter?.id == id else { return nil }
                    return state.waiter.take()
                }
                waiter?.continuation.resume(throwing: ChatGPTAuthError.timedOut)
            }
        }
    }

    // MARK: Connections

    private func accept(_ connection: NWConnection) {
        let accepted = state.withLock { state -> Bool in
            guard !state.isStopped else { return false }
            state.connections[ObjectIdentifier(connection)] = connection
            return true
        }
        guard accepted else {
            connection.cancel()
            return
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    /// Reads until the end of the request headers, which may arrive in several chunks.
    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestBytes) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if buffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                self.respond(to: buffer, on: connection)
            } else if isComplete || error != nil || buffer.count > Self.maxRequestBytes {
                self.close(connection)
            } else {
                self.receive(on: connection, buffer: buffer)
            }
        }
    }

    private func respond(to request: Data, on connection: NWConnection) {
        let requestLine = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n").first ?? ""
        let parts = requestLine.split(separator: " ")
        let target = parts.count > 1 ? String(parts[1]) : "/"
        let response: String
        if target.hasPrefix(ChatGPTAuth.callbackPath),
           let url = URL(string: "http://127.0.0.1:1455\(target)") {
            if ChatGPTAuth.state(of: url) == expectedState {
                deliver(url)
                response = "HTTP/1.1 302 Found\r\nLocation: \(Self.finishURL)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            } else {
                // A request with a foreign `state` is ignored; the sign-in keeps waiting.
                response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
        } else {
            response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        }
        connection.send(content: Data(response.utf8), completion: .contentProcessed { [weak self] _ in
            self?.closeAfterPeer(connection)
        })
    }

    /// Lets the browser close first, so the TIME_WAIT state stays on its side and the port can be
    /// bound again right away. Closes anyway after a short delay.
    private func closeAfterPeer(_ connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.maxRequestBytes) { [weak self] _, _, _, _ in
            self?.close(connection)
        }
        queue.asyncAfter(deadline: .now() + Self.lingerAfterResponse) { [weak self] in
            self?.close(connection)
        }
    }

    private func close(_ connection: NWConnection) {
        state.withLock { _ = $0.connections.removeValue(forKey: ObjectIdentifier(connection)) }
        connection.cancel()
    }

    // MARK: Results

    private func deliver(_ url: URL) {
        let waiter = state.withLock { state -> Waiter? in
            guard state.capturedURL == nil else { return nil }
            state.capturedURL = url
            return state.waiter.take()
        }
        waiter?.continuation.resume(returning: url)
    }

    private func fail(with error: ChatGPTAuthError) {
        let waiter = state.withLock { state -> Waiter? in
            guard state.capturedURL == nil else { return nil }
            if state.terminalError == nil { state.terminalError = error }
            return state.waiter.take()
        }
        waiter?.continuation.resume(throwing: error)
    }

    private static func map(_ error: Error) -> ChatGPTAuthError {
        if case .posix(let code) = error as? NWError, code == .EADDRINUSE { return .portInUse }
        return .serverFailed(String(describing: error))
    }
}
