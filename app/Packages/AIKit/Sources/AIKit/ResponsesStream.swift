import Foundation

/// Parses the server-sent events of a Responses stream line by line.
///
/// Only `data:` lines are evaluated; `event:` lines and blank lines are ignored, because the
/// `type` field inside each payload names the event.
struct ResponsesStreamParser {
    private(set) var isCompleted = false
    private var pendingCalls: [StreamEvent] = []

    /// Returns the events produced by one line; throws when the stream reports a failure.
    mutating func consume(_ line: String) throws -> [StreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard payload != "[DONE]",
              let event = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any],
              let type = event["type"] as? String else { return [] }

        switch type {
        case "response.output_text.delta":
            guard let delta = event["delta"] as? String, !delta.isEmpty else { return [] }
            return [.textDelta(delta)]
        case "response.output_item.done":
            guard let item = event["item"] as? [String: Any], item["type"] as? String == "function_call",
                  let callID = item["call_id"] as? String, let name = item["name"] as? String else { return [] }
            pendingCalls.append(.functionCall(callID: callID, name: name, arguments: item["arguments"] as? String ?? "{}"))
            return []
        case "response.completed":
            isCompleted = true
            let response = event["response"] as? [String: Any]
            let usage = (response?["usage"] as? [String: Any])?["total_tokens"] as? Int
            defer { pendingCalls = [] }
            return pendingCalls + [.completed(usage: usage)]
        case "response.failed":
            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
            throw Self.error(for: error?["code"] as? String, status: 200)
        case "response.incomplete":
            throw ChatGPTError.incomplete
        case "error":
            let code = event["code"] as? String ?? (event["error"] as? [String: Any])?["code"] as? String
            throw Self.error(for: code, status: 200)
        default:
            return []
        }
    }

    /// Maps an error code from a stream event or an error body to the user-facing error.
    static func error(for code: String?, status: Int) -> ChatGPTError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": .usageLimit
        case "subscription_sharing_invalid_user": .invalidUser
        default: .server(status, code)
        }
    }
}
