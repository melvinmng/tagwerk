#if DEBUG
import AIKit
import SwiftUI

/// Temporary debug tool (phase 2b-2, task 2 step 0): signs in with ChatGPT and records a real
/// Responses stream with two parallel function calls plus two follow-up variants, so the
/// function-call format can be fixed from real data. The file holds request bodies and raw SSE
/// lines only, never headers or tokens.
struct ChatGPTCaptureSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var status: String?
    @State private var isBusy = false
    @State private var captureFile: URL?

    var body: some View {
        Section {
            Button("Funktionsaufruf mitschneiden") { Task { await capture() } }
                .disabled(isBusy)
            if let captureFile {
                ShareLink("Mitschnitt teilen", item: captureFile)
            }
            if isBusy { ProgressView() }
            if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("Debug")
        } footer: {
            Text("Nur für die Entwicklung: Der Mitschnitt schickt eine Testanfrage ohne persönliche Daten an OpenAI.")
        }
    }

    private func capture() async {
        isBusy = true
        defer { isBusy = false }
        status = "Mitschnitt läuft …"
        let recorder = ChatGPTCaptureRecorder(session: environment.ai.session)
        let log = await recorder.run()
        do {
            let url = URL.documentsDirectory.appending(path: "chatgpt-capture.txt")
            try log.text.write(to: url, atomically: true, encoding: .utf8)
            captureFile = url
            status = log.summary
        } catch {
            status = "Datei konnte nicht gespeichert werden: \(error.localizedDescription)"
        }
    }
}

/// Runs the capture requests and collects everything in a plain-text log.
struct ChatGPTCaptureRecorder {
    struct Log {
        var text = ""
        var summary = ""
    }

    let session: ChatGPTSessionStore
    private let transport = URLSessionAITransport()
    private let base = URL(string: "https://api.openai.com/v1")!

    func run() async -> Log {
        var log = Log()
        func write(_ line: String) { log.text += line + "\n" }
        var summary: [String] = []
        write("# Tagwerk ChatGPT capture \(ISO8601DateFormatter().string(from: .now))")
        do {
            let token = try await session.validAccessToken()

            var modelsRequest = URLRequest(url: base.appending(path: "models"))
            modelsRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (modelsData, modelsResponse) = try await transport.data(for: modelsRequest)
            write("\n## GET /v1/models → HTTP \(modelsResponse.statusCode)")
            write(String(decoding: modelsData, as: UTF8.self))
            let model = Self.firstListedModel(modelsData) ?? "gpt-5"
            summary.append("Modell \(model).")

            // Request 1: two tools, the prompt asks for both at once.
            let userMessage: [String: Any] = ["role": "user", "content": [[
                "type": "input_text",
                "text": "Lege die Aufgabe „Testaufgabe“ für morgen mit Priorität P2 an und verschiebe die Aufgabe local-7 auf übermorgen.",
            ]]]
            let first = try await stream(model: model, token: token, input: [userMessage], include: nil,
                                         label: "request 1: tools", write: write)
            let itemTypes = first.items.compactMap { $0["type"] as? String }.joined(separator: ", ")
            summary.append("Antwort 1: \(first.status), Items: \(itemTypes.isEmpty ? "keine" : itemTypes).")

            func outputs(for calls: [[String: Any]]) -> [[String: Any]] {
                calls.map { ["type": "function_call_output", "call_id": $0["call_id"] ?? "", "output": #"{"ok":true}"#] }
            }
            // Each variant is caught on its own, so one failure does not skip the others.
            func variant(_ name: String, _ input: [[String: Any]]) async {
                do {
                    let result = try await stream(model: model, token: token, input: input, include: nil,
                                                  label: "request 2\(name)", write: write)
                    summary.append("\(name): \(result.status).")
                } catch {
                    write("### error: \(String(reflecting: error))")
                    summary.append("\(name): Fehler.")
                }
            }
            // Variant A: every output item of request 1 is sent back verbatim (including reasoning items).
            await variant("A (all items echoed)", [userMessage] + first.items + outputs(for: first.calls))
            // Variant B: only the function_call items, reduced to type, call_id, name and arguments.
            let reducedCalls: [[String: Any]] = first.calls.map { call in
                ["type": "function_call", "call_id": call["call_id"] ?? "", "name": call["name"] ?? "",
                 "arguments": call["arguments"] ?? ""]
            }
            await variant("B (function calls only)", [userMessage] + reducedCalls + outputs(for: first.calls))
            // Variant C: request 1 again with encrypted reasoning, then every item echoed.
            do {
                let encrypted = try await stream(model: model, token: token, input: [userMessage],
                                                 include: ["reasoning.encrypted_content"],
                                                 label: "request 1C: tools with encrypted reasoning", write: write)
                await variant("C (encrypted reasoning echoed)",
                              [userMessage] + encrypted.items + outputs(for: encrypted.calls))
            } catch {
                write("### error: \(String(reflecting: error))")
                summary.append("C: Fehler.")
            }
        } catch {
            write("\n## error: \(String(reflecting: error))")
            summary.append("Fehler: \(String(reflecting: error))")
        }

        await recordRefreshChecks(write: write, summary: &summary)
        log.summary = summary.joined(separator: " ")
        return log
    }

    /// Records how the token endpoint behaves: a forced refresh of the real session (only whether
    /// the tokens rotated, never their values) and a refresh with a made-up refresh token, whose
    /// error status and body decide when the app signs out.
    private func recordRefreshChecks(write: (String) -> Void, summary: inout [String]) async {
        let store = KeychainChatGPTCredentialStore()
        write("\n## forced refresh")
        do {
            let before = try store.loadTokens()
            let token = try await session.validAccessToken()
            let fresh = try await session.handleUnauthorized(failedToken: token)
            let after = try store.loadTokens()
            let accessRotated = fresh != token
            let refreshRotated = before?.refreshToken != after?.refreshToken
            write("access token changed: \(accessRotated), refresh token rotated: \(refreshRotated)")
            summary.append("Erneuerung: ok, Refresh-Token rotiert: \(refreshRotated ? "ja" : "nein").")
        } catch {
            write("error: \(String(reflecting: error))")
            summary.append("Erneuerung: Fehler \(String(reflecting: error)).")
        }

        write("\n## refresh with a made-up refresh token")
        guard let clientID = try? store.loadClientID() else {
            write("no client id stored")
            return
        }
        var request = URLRequest(url: URL(string: "https://auth.openai.com/api/accounts/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        let fields = [("grant_type", "refresh_token"), ("client_id", clientID),
                      ("refresh_token", "tagwerk-invalid-refresh-token"), ("resource", "https://api.openai.com/v1")]
        request.httpBody = Data(fields.map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? $0.1)" }
            .joined(separator: "&").utf8)
        do {
            let (data, response) = try await transport.data(for: request)
            write("HTTP \(response.statusCode)")
            write(String(decoding: data, as: UTF8.self))
            summary.append("Ungültiger Refresh-Token: HTTP \(response.statusCode).")
        } catch {
            write("error: \(String(reflecting: error))")
        }
    }

    private struct StreamResult {
        var status = "kein Ende"
        var items: [[String: Any]] = []
        var calls: [[String: Any]] = []
    }

    private func stream(model: String, token: String, input: [[String: Any]], include: [String]?, label: String,
                        write: (String) -> Void) async throws -> StreamResult {
        var body: [String: Any] = [
            "model": model,
            "instructions": "Du verwaltest Aufgaben in einer App. Heute ist \(Date.now.formatted(.iso8601.year().month().day())). "
                + "Erledige Bitten über die Funktionen; rufe mehrere Funktionen parallel auf, wenn es passt.",
            "input": input,
            "tools": Self.tools,
            "store": false,
            "stream": true,
        ]
        if let include { body["include"] = include }
        var request = URLRequest(url: base.appending(path: "responses"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])

        write("\n## \(label)")
        write("### request body")
        write(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
        let (lines, response) = try await transport.lines(for: request)
        write("### response HTTP \(response.statusCode)")
        var result = StreamResult()
        for try await line in lines {
            write(line)
            guard line.hasPrefix("data:"),
                  let event = try? JSONSerialization.jsonObject(with: Data(line.dropFirst(5).utf8)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "response.output_item.done":
                if let item = event["item"] as? [String: Any] {
                    result.items.append(item)
                    if item["type"] as? String == "function_call" { result.calls.append(item) }
                }
            case "response.completed": result.status = "completed"
            case "response.failed", "response.incomplete", "error": result.status = type
            default: break
            }
        }
        if response.statusCode != 200 { result.status = "HTTP \(response.statusCode)" }
        return result
    }

    private static func firstListedModel(_ data: Data) -> String? {
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let models = json?["models"] as? [[String: Any]] ?? []
        return models.first { $0["visibility"] as? String == "list" }?["slug"] as? String
    }

    private static var tools: [[String: Any]] { [
        [
            "type": "function", "name": "create_task", "strict": true,
            "description": "Creates a local task.",
            "parameters": [
                "type": "object", "additionalProperties": false,
                "required": ["title", "due", "priority"],
                "properties": [
                    "title": ["type": "string"],
                    "due": ["type": ["string", "null"], "description": "YYYY-MM-DD"],
                    "priority": ["type": ["string", "null"], "enum": ["P1", "P2", "P3", "P4", NSNull()]],
                ],
            ],
        ],
        [
            "type": "function", "name": "reschedule_task", "strict": true,
            "description": "Moves the due date of an existing task.",
            "parameters": [
                "type": "object", "additionalProperties": false,
                "required": ["task_id", "due"],
                "properties": [
                    "task_id": ["type": "string"],
                    "due": ["type": "string", "description": "YYYY-MM-DD"],
                ],
            ],
        ],
    ] }
}
#endif
