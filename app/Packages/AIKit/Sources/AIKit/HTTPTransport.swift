import Foundation

/// Sends HTTP requests. Injected so that all ChatGPT logic can be tested without network.
public protocol AIHTTPTransport: Sendable {
    /// A complete request and response body.
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// A streamed response, delivered line by line (server-sent events).
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse)
}

/// Production transport backed by its own `URLSession`. Streams may stay idle for a long time
/// while the model thinks, so the idle timeout is generous.
public final class URLSessionAITransport: AIHTTPTransport {
    private let session: URLSession

    public init(idleTimeout: TimeInterval = 300) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = idleTimeout
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }

    public func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // Ending the consumer cancels the read, which cancels the request.
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, http)
    }
}
