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
    /// Upper bound for each close step in `stop()`. Only a hang guard: Network.framework normally reports
    /// `.cancelled` within milliseconds, but on a starved machine (CI runner with parallel jobs) it was seen to
    /// take many seconds, and returning earlier leaves the port bound.
    static let closeGuard: TimeInterval = 20

    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<URL, Error>
    }

    /// What `stop()` waits for before it returns.
    private enum Drain {
        /// Every connection socket (until it reported `.cancelled`).
        case sockets
        /// The listening socket.
        case listener
    }

    private struct DrainWaiter {
        let id: UUID
        let drain: Drain
        let continuation: CheckedContinuation<Bool, Never>
    }

    private struct State {
        var listener: NWListener?
        /// Accepted connections that are not closed yet.
        var connections: [ObjectIdentifier: NWConnection] = [:]
        /// Connections that were accepted and have not reported `.cancelled` yet, so their sockets may still be open.
        var openSockets: Set<ObjectIdentifier> = []
        var listenerClosed = true
        var drainWaiters: [DrainWaiter] = []
        /// The port the listener is bound to, known once it is ready (relevant when port 0 was requested).
        var boundPort: UInt16?
        var stopWasClean: Bool?
        var onWaiterRegistered: (@Sendable () -> Void)?
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
    /// The port the listener is bound to, once it is ready. Differs from the requested port only for port 0.
    public var listeningPort: UInt16? { state.withLock { $0.boundPort } }
    var capturedURL: URL? { state.withLock { $0.capturedURL } }
    /// `true` when the last `stop()` saw the listener and every connection report `.cancelled`, `false` when a
    /// hang guard ended the wait, `nil` before the first stop.
    var stopWasClean: Bool? { state.withLock { $0.stopWasClean } }

    /// Test hook: called once a `waitForCallback` call is registered and waiting.
    var onWaiterRegistered: (@Sendable () -> Void)? {
        get { state.withLock { $0.onWaiterRegistered } }
        set { state.withLock { $0.onWaiterRegistered = newValue } }
    }

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
        state.withLock { $0.listener = listener; $0.listenerClosed = false; $0.stopWasClean = nil }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let pending = Mutex<CheckedContinuation<Void, Error>?>(continuation)
            let resume: @Sendable (Result<Void, Error>) -> Void = { result in
                pending.withLock { $0.take() }?.resume(with: result)
            }
            listener.stateUpdateHandler = { [weak self] newState in
                switch newState {
                case .ready:
                    self?.state.withLock { state in
                        state.isReady = true
                        state.boundPort = listener.port?.rawValue
                    }
                    resume(.success(()))
                case .failed(let error), .waiting(let error):
                    let mapped = Self.map(error)
                    resume(.failure(mapped))
                    self?.fail(with: mapped)
                    listener.cancel()
                case .cancelled:
                    self?.markListenerClosed()
                    resume(.failure(ChatGPTAuthError.cancelled))
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    /// Stops listening, closes open connections and fails a pending wait. Returns once the port is released,
    /// which means the listening socket and every accepted socket reported `.cancelled`.
    public func stop() async {
        let (listener, connections) = state.withLock { state -> (NWListener?, [NWConnection]) in
            state.isStopped = true
            state.isReady = false
            defer { state.listener = nil; state.connections = [:] }
            state.listenerClosed = state.listener == nil
            return (state.listener, Array(state.connections.values))
        }
        fail(with: .cancelled)
        connections.forEach { $0.cancel() }
        if let listener {
            listener.stateUpdateHandler = { [weak self] newState in
                if case .cancelled = newState { self?.markListenerClosed() }
            }
            if case .cancelled = listener.state { markListenerClosed() }
            listener.cancel()
        }
        // Connections that `close()` already cancelled are not in the snapshot above but may still hold their socket.
        var clean = await awaitDrained(.sockets, timeout: Self.closeGuard)
        clean = await awaitDrained(.listener, timeout: Self.closeGuard) && clean
        state.withLock { $0.stopWasClean = clean }
    }

    private func isDrained(_ drain: Drain, in state: State) -> Bool {
        switch drain {
        case .sockets: state.openSockets.isEmpty
        case .listener: state.listenerClosed
        }
    }

    /// Suspends until `drain` is complete. Returns `false` when `timeout` ended the wait first.
    private func awaitDrained(_ drain: Drain, timeout: TimeInterval) async -> Bool {
        let id = UUID()
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let alreadyDrained = state.withLock { state -> Bool in
                if isDrained(drain, in: state) { return true }
                state.drainWaiters.append(DrainWaiter(id: id, drain: drain, continuation: continuation))
                return false
            }
            if alreadyDrained {
                continuation.resume(returning: true)
                return
            }
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                let waiter = self?.state.withLock { state -> DrainWaiter? in
                    guard let index = state.drainWaiters.firstIndex(where: { $0.id == id }) else { return nil }
                    return state.drainWaiters.remove(at: index)
                }
                waiter?.continuation.resume(returning: false)
            }
        }
    }

    /// Resumes the waiters whose drain is complete. Call after every change of the sets they watch.
    private func notifyDrained() {
        let ready = state.withLock { state -> [DrainWaiter] in
            let ready = state.drainWaiters.filter { isDrained($0.drain, in: state) }
            state.drainWaiters.removeAll { waiter in ready.contains { $0.id == waiter.id } }
            return ready
        }
        ready.forEach { $0.continuation.resume(returning: true) }
    }

    private func markListenerClosed() {
        state.withLock { $0.listenerClosed = true }
        notifyDrained()
    }

    /// Waits for the callback request with the expected `state`.
    public func waitForCallback(timeout: TimeInterval = 300) async throws -> URL {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let (immediate, registered) = state.withLock { state -> (Result<URL, Error>?, (@Sendable () -> Void)?) in
                if let url = state.capturedURL { return (.success(url), nil) }
                if let error = state.terminalError { return (.failure(error), nil) }
                state.waiter = Waiter(id: id, continuation: continuation)
                return (nil, state.onWaiterRegistered)
            }
            if let immediate {
                continuation.resume(with: immediate)
                return
            }
            registered?()
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
            state.openSockets.insert(ObjectIdentifier(connection))
            return true
        }
        guard accepted else {
            connection.cancel()
            return
        }
        let identifier = ObjectIdentifier(connection)
        connection.stateUpdateHandler = { [weak self] newState in
            switch newState {
            case .failed:
                self?.close(connection)
            case .cancelled:
                self?.state.withLock { _ = $0.openSockets.remove(identifier) }
                self?.notifyDrained()
            default:
                break
            }
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
