import Foundation
import Network

/// One-shot HTTP listener on 127.0.0.1 that captures the OAuth callback and redirects the
/// authentication sheet to a custom scheme so it closes itself.
final class LoopbackServer: @unchecked Sendable {
    static let finishURL = "tagwerkspike://auth/done"

    private let port: UInt16
    private let queue = DispatchQueue(label: "com.melvinmng.tagwerk.loopback")
    private let lock = NSLock()
    private var listener: NWListener?
    private var continuation: CheckedContinuation<URL, Error>?
    private var capturedURL: URL?

    init(port: UInt16 = 1455) {
        self.port = port
    }

    func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
        listener.start(queue: queue)
        self.listener = listener
    }

    /// Stops listening and fails a pending wait, e.g. when the user cancels the sheet.
    func stop() {
        listener?.cancel()
        listener = nil
        finish(.failure(CancellationError()))
    }

    /// Waits for the callback request; fails after `timeout` seconds.
    func waitForCallback(timeout: TimeInterval = 300) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if let capturedURL {
                lock.unlock()
                continuation.resume(returning: capturedURL)
                return
            }
            self.continuation = continuation
            lock.unlock()
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finish(.failure(URLError(.timedOut)))
            }
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8),
                  let requestLine = request.split(separator: "\r\n").first else {
                connection.cancel()
                return
            }
            let parts = requestLine.split(separator: " ")
            let path = parts.count > 1 ? String(parts[1]) : "/"
            let response: String
            if path.hasPrefix("/auth/callback"), let url = URL(string: "http://127.0.0.1:\(self.port)\(path)") {
                response = "HTTP/1.1 302 Found\r\nLocation: \(Self.finishURL)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                self.finish(.success(url))
            } else {
                response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        lock.lock()
        if case .success(let url) = result, capturedURL == nil { capturedURL = url }
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}
