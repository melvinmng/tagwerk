#if DEBUG
import AIKit
import SwiftUI

/// Temporary debug tool (phase 2b-2, task 2 step 0): signs in with ChatGPT and records a real
/// Responses stream with two parallel function calls plus two follow-up variants, so the
/// function-call format can be fixed from real data. The file holds request bodies and raw SSE
/// lines only, never headers or tokens.
struct ChatGPTCaptureSection: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var isSignedIn = false
    @State private var email: String?
    @State private var status: String?
    @State private var isBusy = false
    @State private var captureFile: URL?
    @State private var authenticator = SystemWebAuthenticator()

    var body: some View {
        Section {
            if isSignedIn {
                LabeledContent("ChatGPT", value: email ?? "angemeldet")
                Button("Funktionsaufruf mitschneiden") { Task { await capture() } }
                    .disabled(isBusy)
                if let captureFile {
                    ShareLink("Mitschnitt teilen", item: captureFile)
                }
                Button("Abmelden", role: .destructive) {
                    Task {
                        try? await environment.chatGPT.signOut()
                        await refresh()
                    }
                }
            } else {
                Button("Mit ChatGPT anmelden") { Task { await signIn() } }
                    .disabled(isBusy)
            }
            if isBusy { ProgressView() }
            if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
        } header: {
            Text("ChatGPT (Debug)")
        } footer: {
            Text("Nur für die Entwicklung: Der Mitschnitt schickt eine Testanfrage ohne persönliche Daten an OpenAI.")
        }
        .task { await refresh() }
    }

    private func refresh() async {
        isSignedIn = await environment.chatGPT.isSignedIn
        email = await environment.chatGPT.accountEmail
    }

    private func signIn() async {
        isBusy = true
        defer { isBusy = false }
        do {
            try await ChatGPTLogin(session: environment.chatGPT, authenticator: authenticator).signIn()
            status = "Angemeldet."
        } catch let error as ChatGPTAuthError {
            status = error.userMessage
        } catch {
            status = "Anmeldung fehlgeschlagen: \(error.localizedDescription)"
        }
        await refresh()
    }

    private func capture() async {
        isBusy = true
        defer { isBusy = false }
        status = "Mitschnitt läuft …"
        let recorder = ChatGPTCaptureRecorder(session: environment.chatGPT)
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
        do {
            let token = try await session.validAccessToken()
            write("# Tagwerk ChatGPT capture \(ISO8601DateFormatter().string(from: .now))")

            var modelsRequest = URLRequest(url: base.appending(path: "models"))
            modelsRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let (modelsData, modelsResponse) = try await transport.data(for: modelsRequest)
            write("\n## GET /v1/models → HTTP \(modelsResponse.statusCode)")
            write(String(decoding: modelsData, as: UTF8.self))
            let model = Self.firstListedModel(modelsData) ?? "gpt-5"

            // Request 1: two tools, the prompt asks for both at once.
            let userMessage: [String: Any] = ["role": "user", "content": [[
                "type": "input_text",
                "text": "Lege die Aufgabe „Testaufgabe“ für morgen mit Priorität P2 an und verschiebe die Aufgabe local-7 auf übermorgen.",
            ]]]
            let first = try await stream(model: model, token: token, input: [userMessage], label: "request 1: tools", write: write)

            let outputs: [[String: Any]] = first.calls.map { call in
                ["type": "function_call_output", "call_id": call["call_id"] ?? "", "output": #"{"ok":true}"#]
            }
            // Variant A: every output item of request 1 is sent back verbatim (including reasoning items).
            let variantA = try await stream(model: model, token: token, input: [userMessage] + first.items + outputs,
                                            label: "request 2A: all items echoed", write: write)
            // Variant B: only the function_call items, reduced to type, call_id, name and arguments.
            let reducedCalls: [[String: Any]] = first.calls.map { call in
                ["type": "function_call", "call_id": call["call_id"] ?? "", "name": call["name"] ?? "",
                 "arguments": call["arguments"] ?? ""]
            }
            let variantB = try await stream(model: model, token: token, input: [userMessage] + reducedCalls + outputs,
                                            label: "request 2B: function calls only", write: write)

            let itemTypes = first.items.compactMap { $0["type"] as? String }.joined(separator: ", ")
            log.summary = """
            Modell \(model). Antwort 1: \(first.status), Items: \(itemTypes.isEmpty ? "keine" : itemTypes). \
            Folgeaufruf A: \(variantA.status). Folgeaufruf B: \(variantB.status).
            """
        } catch {
            write("\n## error: \(error)")
            log.summary = "Fehler: \(error)"
        }
        return log
    }

    private struct StreamResult {
        var status = "kein Ende"
        var items: [[String: Any]] = []
        var calls: [[String: Any]] = []
    }

    private func stream(model: String, token: String, input: [[String: Any]], label: String,
                        write: (String) -> Void) async throws -> StreamResult {
        let body: [String: Any] = [
            "model": model,
            "instructions": "Du verwaltest Aufgaben in einer App. Heute ist \(Date.now.formatted(.iso8601.year().month().day())). "
                + "Erledige Bitten über die Funktionen; rufe mehrere Funktionen parallel auf, wenn es passt.",
            "input": input,
            "tools": Self.tools,
            "store": false,
            "stream": true,
        ]
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
