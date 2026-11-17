import Foundation

struct StreamOutcome: Equatable {
    var text = ""
    var completed = false
    var errorCode: String?
}

/// Calls the OpenAI Responses API with a ChatGPT plan token and checks models, text, schema and image input.
struct ChatGPTProbe: Probe {
    let name = "ChatGPT (Abo)"

    static func filterModels(_ body: Data) -> [String] {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let models = json?["data"] as? [[String: Any]] ?? []
        return models.filter { $0["visibility"] as? String == "list" }.compactMap { $0["id"] as? String }
    }

    static func parseStream(_ stream: String) -> StreamOutcome {
        var outcome = StreamOutcome()
        for line in stream.split(separator: "\n") where line.hasPrefix("data:") {
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let data = payload.data(using: .utf8),
                  let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "response.output_text.delta":
                outcome.text += event["delta"] as? String ?? ""
            case "response.completed":
                outcome.completed = true
            case "response.failed", "response.incomplete":
                let response = event["response"] as? [String: Any]
                let error = response?["error"] as? [String: Any]
                outcome.errorCode = error?["code"] as? String ?? type
            case "error":
                outcome.errorCode = event["code"] as? String ?? "error"
            default:
                break
            }
        }
        return outcome
    }

    static func describe(status: Int, body: Data) -> String {
        let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let code = error?["code"] as? String ?? ""
        switch code {
        case "subscription_sharing_usage_limit_exceeded":
            return "HTTP \(status): Kontingent des ChatGPT-Abos für diese App erschöpft"
        case "subscription_sharing_invalid_user":
            return "HTTP \(status): Verbindung getrennt – bitte erneut mit ChatGPT anmelden"
        default:
            let message = error?["message"] as? String ?? "keine Details"
            return "HTTP \(status): \(code.isEmpty ? message : code)"
        }
    }

    static func makeResponsesRequest(
        accessToken: String, model: String, instructions: String, prompt: String,
        imageJPEG: Data?, jsonSchema: (name: String, schema: [String: Any])?
    ) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/responses")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var content: [[String: Any]] = [["type": "input_text", "text": prompt]]
        if let imageJPEG {
            content.append(["type": "input_image", "image_url": "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"])
        }
        var body: [String: Any] = [
            "model": model,
            "instructions": instructions,
            "input": [["role": "user", "content": content]],
            "store": false,
            "stream": true,
        ]
        if let jsonSchema {
            body["text"] = ["format": [
                "type": "json_schema", "name": jsonSchema.name, "schema": jsonSchema.schema, "strict": true,
            ]]
        }
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return request
    }

    func run() async -> ProbeResult {
        do {
            guard let token = try await ChatGPTSessionStore.shared.validAccessToken() else {
                return ProbeResult(name: name, ok: true, detail: "übersprungen (nicht angemeldet)", skipped: true)
            }
            let models = try await listModels(token: token)
            guard let model = models.first else {
                return ProbeResult(name: name, ok: false, detail: "Keine Modelle für dieses Konto freigegeben")
            }
            let plain = try await stream(Self.makeResponsesRequest(
                accessToken: token, model: model, instructions: "Antworte knapp auf Deutsch.",
                prompt: "Sag in einem Satz, dass die Verbindung funktioniert.", imageJPEG: nil, jsonSchema: nil))
            let schema = try await stream(Self.makeResponsesRequest(
                accessToken: token, model: model, instructions: "Schätze Nährwerte. Antworte nur im vorgegebenen Format.",
                prompt: "2 Brötchen mit Käse", imageJPEG: nil, jsonSchema: ("meal", Self.mealSchema)))
            let image = try await stream(Self.makeResponsesRequest(
                accessToken: token, model: model, instructions: "Antworte knapp auf Deutsch.",
                prompt: "Welche Farbe hat dieses Bild?", imageJPEG: Self.sampleImageJPEG(), jsonSchema: nil))
            let ok = plain.completed && schema.completed && image.completed
            let schemaValid = (try? JSONSerialization.jsonObject(with: Data(schema.text.utf8))) != nil
            return ProbeResult(
                name: name, ok: ok,
                detail: """
                Modell \(model) (\(models.count) verfügbar)
                Text: \(plain.completed ? plain.text : "Fehler \(plain.errorCode ?? "?")")
                JSON-Schema: \(schema.completed ? (schemaValid ? "ok " + schema.text : "kein gültiges JSON") : "Fehler \(schema.errorCode ?? "?")")
                Bild: \(image.completed ? image.text : "Fehler \(image.errorCode ?? "?")")
                """
            )
        } catch {
            return ProbeResult(name: name, ok: false, detail: error.localizedDescription)
        }
    }

    private func listModels(token: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw ChatGPTAuthError.serverError(Self.describe(status: status, body: data)) }
        return Self.filterModels(data)
    }

    private func stream(_ request: URLRequest) async throws -> StreamOutcome {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        var raw = ""
        for try await line in bytes.lines { raw += line + "\n" }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            return StreamOutcome(text: "", completed: false, errorCode: Self.describe(status: status, body: Data(raw.utf8)))
        }
        return Self.parseStream(raw)
    }

    static var mealSchema: [String: Any] { [
        "type": "object",
        "properties": [
            "items": ["type": "array", "items": [
                "type": "object",
                "properties": ["name": ["type": "string"], "kcal": ["type": "number"]],
                "required": ["name", "kcal"], "additionalProperties": false,
            ]],
            "totalKcal": ["type": "number"],
        ],
        "required": ["items", "totalKcal"],
        "additionalProperties": false,
    ] }

    /// A tiny solid-red JPEG rendered at runtime, so no binary asset is needed.
    static func sampleImageJPEG() -> Data? {
        #if canImport(UIKit)
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 32, height: 32))
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
        }
        return image.jpegData(compressionQuality: 0.8)
        #else
        return nil
        #endif
    }
}

#if canImport(UIKit)
import UIKit
#endif
