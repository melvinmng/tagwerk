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
        if let plan = Self.planAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": plan]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
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

    private static func event(_ object: [String: Any]) -> String {
        "data: " + String(decoding: (try? JSONSerialization.data(withJSONObject: object)) ?? Data(), as: UTF8.self)
    }

    private static func stream(_ lines: [String], request: URLRequest) -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        (AsyncThrowingStream { continuation in
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                lines.forEach { continuation.yield($0) }
                continuation.finish()
            }
        }, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    /// A schema-valid plan for the tasks and days in the request. The first answer contains one block
    /// at 03:00 that the local check rejects; the follow-up leaves it out, so it ends up as "nicht eingeplant".
    private static func planAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              let name = format["name"] as? String,
              let input = json["input"] as? [[String: Any]],
              let first = (input.first?["content"] as? [[String: Any]])?.first?["text"] as? String,
              let plan = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else { return nil }
        let isRetry = input.count > 1
        let tasks = (plan["tasks"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let days = (plan["days"] as? [[String: Any]] ?? []).filter { $0["dayOff"] as? Bool == false }
        var answer: [String: Any] = ["unscheduled": [], "risks": ["Demo: Die Woche ist knapp."],
                                     "estimates": tasks.prefix(3).map { ["taskId": $0, "minutes": 45] }]
        if name == "day_plan" {
            let starts = ["16:00", "17:00", "03:00"]
            var blocks: [[String: Any]] = []
            for (index, task) in tasks.prefix(3).enumerated() where !(isRetry && index == 2) {
                blocks.append(["taskId": task, "start": starts[index], "minutes": 45, "reason": "Demo-Vorschlag"])
            }
            answer["blocks"] = blocks
        } else {
            var assignments: [[String: Any]] = []
            for (index, task) in tasks.prefix(4).enumerated() where !days.isEmpty && !(isRetry && index == 3) {
                let day = index == 3 ? "1999-01-01" : (days[index % days.count]["day"] as? String ?? "")
                assignments.append(["taskId": task, "day": day, "reason": "Demo-Vorschlag"])
            }
            answer["assignments"] = assignments
        }
        return (try? JSONSerialization.data(withJSONObject: answer)).map { String(decoding: $0, as: UTF8.self) }
    }
}
#endif