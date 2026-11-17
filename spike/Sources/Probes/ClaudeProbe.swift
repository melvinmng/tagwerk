import Foundation

/// Sends one small request to the Claude Messages API and checks the answer.
struct ClaudeProbe: Probe {
    let name = "Claude API"

    static func makeRequest(apiKey: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        let body: [String: Any] = [
            "model": "claude-opus-5-5",
            "max_tokens": 1024,
            "fallbacks": "default",
            "output_config": ["effort": "low"],
            "messages": [
                ["role": "user", "content": "Antworte mit einem kurzen Satz: Funktioniert die Verbindung?"],
            ],
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    static func interpret(status: Int, body: Data) -> ProbeResult {
        guard status == 200 else {
            return ProbeResult(name: "Claude API", ok: false, detail: "HTTP \(status): \(errorMessage(from: body))")
        }
        guard let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return ProbeResult(name: "Claude API", ok: false, detail: "Antwort nicht lesbar")
        }
        if json["stop_reason"] as? String == "refusal" {
            return ProbeResult(name: "Claude API", ok: false, detail: "Anfrage vom Modell abgelehnt")
        }
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined(separator: " ")
        let model = json["model"] as? String ?? "?"
        return ProbeResult(name: "Claude API", ok: !text.isEmpty, detail: "\(model): \(text)")
    }

    private static func errorMessage(from body: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        return error?["message"] as? String ?? "keine Details"
    }

    func run() async -> ProbeResult {
        guard let key = Secrets.load(account: "anthropic"), !key.isEmpty else {
            return ProbeResult(name: name, ok: false, detail: "Kein API-Key gespeichert")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: Self.makeRequest(apiKey: key))
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return Self.interpret(status: status, body: data)
        } catch {
            return ProbeResult(name: name, ok: false, detail: "Netzwerkfehler: \(error.localizedDescription)")
        }
    }
}
