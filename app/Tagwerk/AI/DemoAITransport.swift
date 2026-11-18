#if DEBUG && targetEnvironment(simulator)
import AIKit
import Foundation

/// Scripted ChatGPT answers for checking the AI screens in the simulator without an account,
/// enabled with the launch argument `-TagwerkDemoAI`.
final class DemoAITransport: AIHTTPTransport {
    static let launchArgument = "-TagwerkDemoAI"

    static var tokens: ChatGPTTokens {
        ChatGPTTokens(accessToken: "demo", refreshToken: "demo", idToken: nil,
                      expiresAt: .distantFuture, clientID: "demo", accountID: nil)
    }

    static let modelsBody = """
    {"models":[{"slug":"demo-sol","display_name":"Demo Sol","visibility":"list"},\
    {"slug":"demo-terra","display_name":"Demo Terra","visibility":"list"},\
    {"slug":"demo-luna","display_name":"Demo Luna","visibility":"list"}]}
    """

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await Task.sleep(for: .milliseconds(300))
        let body = request.url?.path == "/v1/models" ? Self.modelsBody : #"{"error":{"code":"demo_unsupported"}}"#
        let status = request.url?.path == "/v1/models" ? 200 : 400
        return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let lines = [
            #"data: {"type":"response.output_text.delta","delta":"Das ist eine Demo-Antwort."}"#,
            #"data: {"type":"response.completed","response":{"usage":{"total_tokens":1}}}"#,
        ]
        return (AsyncThrowingStream { continuation in
            Task {
                for line in lines {
                    try? await Task.sleep(for: .milliseconds(150))
                    continuation.yield(line)
                }
                continuation.finish()
            }
        }, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}
#endif
