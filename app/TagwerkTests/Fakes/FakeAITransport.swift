import AIKit
import Foundation
import Synchronization

/// Scripted ChatGPT transport for app tests: answers per URL path and records every request.
final class FakeAITransport: AIHTTPTransport {
    private let state = Mutex<(replies: [String: [(Int, String)]], requests: [URLRequest])>(([:], []))

    func enqueue(_ path: String, status: Int = 200, _ body: String) {
        state.withLock { $0.replies[path, default: []].append((status, body)) }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let reply = state.withLock { state -> (Int, String)? in
            state.requests.append(request)
            let path = request.url?.path ?? ""
            guard var queue = state.replies[path], !queue.isEmpty else { return nil }
            let next = queue.removeFirst()
            state.replies[path] = queue
            return next
        }
        guard let (status, body) = reply else { throw URLError(.notConnectedToInternet) }
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        return (AsyncThrowingStream { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }, response)
    }
}

extension ChatGPTTokens {
    static func valid(now: Date) -> ChatGPTTokens {
        ChatGPTTokens(accessToken: "at_test", refreshToken: "rt_test", idToken: nil,
                      expiresAt: now.addingTimeInterval(3600), clientID: "oaiapp_test", accountID: nil)
    }
}
