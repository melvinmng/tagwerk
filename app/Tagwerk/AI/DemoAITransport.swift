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
    {"models":[{"slug":"demo-sol","display_name":"Demo Sol","visibility":"list","default_reasoning_level":"low","supported_reasoning_levels":[{"effort":"low"},{"effort":"medium"},{"effort":"high"},{"effort":"xhigh"}]},\
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
        // Checked before the plan answer, whose parser expects a JSON plan as the first input text.
        if let meal = Self.mealAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": meal]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
        if let revision = Self.cardRevisionAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": revision]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
        if let recipe = Self.recipeAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": recipe]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
        if let translation = Self.shoppingTranslationAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": translation]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
        if let sort = Self.shoppingSortAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": sort]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
        if let plan = Self.planAnswer(for: request) {
            return Self.stream([Self.event(["type": "response.output_text.delta", "delta": plan]),
                                Self.event(["type": "response.completed", "response": [:]])], request: request)
        }
        if let chat = Self.chatAnswer(for: request) {
            return Self.stream(chat, request: request)
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

    /// Assistant demo: a user message gets a short answer and a "create_task" call; a function result gets "Erledigt."
    private static func chatAnswer(for request: URLRequest) -> [String]? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              json["tools"] != nil, let last = (json["input"] as? [[String: Any]])?.last else { return nil }
        if last["type"] as? String == "function_call_output" {
            return [event(["type": "response.output_text.delta", "delta": "Erledigt. Die Demo-Aufgabe steht jetzt in deiner Liste."]),
                    event(["type": "response.completed", "response": [:]])]
        }
        let arguments = #"{"title":"Demo-Aufgabe","due":null,"priority":"P3","minutes":30,"notes":null,"source":"local","repository":null,"project_ids":null,"assignees":null}"#
        return [event(["type": "response.output_text.delta", "delta": "Ich schlage vor, dafür eine Aufgabe anzulegen."]),
                event(["type": "response.output_item.done", "item": ["type": "function_call", "call_id": "demo-\(UUID().uuidString)",
                                                                    "name": "create_task", "arguments": arguments]]),
                event(["type": "response.completed", "response": [:]])]
    }

    /// A schema-valid plan for the tasks and days in the request. The first answer contains one block
    /// at 03:00 that the local check rejects; the follow-up leaves it out, so it ends up as "nicht eingeplant".
    /// A fixed estimate for any meal ("2 Brötchen mit Käse" from the feasibility test); empty input finds nothing.
    static func mealAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              format["name"] as? String == "meal_estimate" else { return nil }
        let content = ((json["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { $0["text"] as? String }.joined().lowercased()
        if text.contains("tisch") {
            return #"{"title":"","items":[]}"#
        }
        // A follow-up (task D1): the same estimate with a third item.
        if text.contains("message from the user:") {
            return #"{"title":"Brötchen mit Käse","items":[{"name":"Brötchen","amount":"2 Stück","kcal_min":250,"kcal":300,"kcal_max":350,"protein_g":10,"carbs_g":56,"fat_g":2},{"name":"Käse","amount":"2 Scheiben","kcal_min":150,"kcal":180,"kcal_max":220,"protein_g":12,"carbs_g":0,"fat_g":14},{"name":"Butter","amount":"1 Portion","kcal_min":50,"kcal":70,"kcal_max":90,"protein_g":0,"carbs_g":0,"fat_g":8}]}"#
        }
        return #"{"title":"Brötchen mit Käse","items":[{"name":"Brötchen","amount":"2 Stück","kcal_min":250,"kcal":300,"kcal_max":350,"protein_g":10,"carbs_g":56,"fat_g":2},{"name":"Käse","amount":"2 Scheiben","kcal_min":150,"kcal":180,"kcal_max":220,"protein_g":12,"carbs_g":0,"fat_g":14}]}"#
    }

    /// Follow-up about one action card (task B4): the same arguments with "(später)" behind the title, and a sentence about it.
    /// A request without a title in the arguments changes nothing and says so.
    static func cardRevisionAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              format["name"] as? String == "card_revision" else { return nil }
        let content = ((json["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { $0["text"] as? String }.joined()
        let prefix = "Current arguments (JSON): "
        guard let line = text.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }),
              var arguments = (try? JSONSerialization.jsonObject(with: Data(line.dropFirst(prefix.count).utf8))) as? [String: Any] else { return nil }
        var answer: [String: Any] = ["arguments": arguments, "message": "Dazu kann ich nichts ändern.", "changed": false]
        if let title = arguments["title"] as? String {
            arguments["title"] = title + " (später)"
            answer = ["arguments": arguments, "message": "Titel ergänzt.", "changed": true]
        }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(), as: UTF8.self)
    }

    /// Shopping demo: every item goes to the first category of the request, the first item into a new "Demo" category.
    /// Recipe reading ("Rezept hinzufügen", "Rezept mit ChatGPT anlegen"): a fixed invented recipe for any input.
    static func recipeAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              format["name"] as? String == "recipe_ingredients" else { return nil }
        var items: [[String: Any]] = [["name": "Paprika", "quantity": "2 Stück", "amount": 2, "unit": "Stück", "category": "Obst & Gemüse"],
                                      ["name": "Reis", "quantity": "150 g", "amount": 150, "unit": "g", "category": "Sonstiges"],
                                      ["name": "Salz", "quantity": "nach Geschmack", "category": "Sonstiges"]]
        // A follow-up (task D2): the same recipe with one more ingredient.
        let sent = ((json["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        if sent.compactMap({ $0["text"] as? String }).joined().contains("Message from the user:") {
            items.append(["name": "Zwiebel", "quantity": "1 Stück", "amount": 1, "unit": "Stück", "category": "Obst & Gemüse"])
        }
        let answer: [String: Any] = [
            "title": "Demo Gemüsepfanne", "servings": 2,
            "steps": ["Gemüse schneiden.", "In der Pfanne fünf Minuten braten."],
            "items": items,
        ]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(), as: UTF8.self)
    }

    /// Shopping translation demo: a few known names go German ⇄ English, every other name comes back unchanged.
    static func shoppingTranslationAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              format["name"] as? String == "shopping_translation" else { return nil }
        let content = ((json["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { $0["text"] as? String }.joined()
        let sent = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]) ?? [:]
        let toEnglish = (sent["target"] as? String) == "English"
        let pairs = [("Milch", "Milk"), ("Brot", "Bread"), ("Eier", "Eggs"), ("Äpfel", "Apples")]
        let dictionary = Dictionary(uniqueKeysWithValues: pairs.map { toEnglish ? ($0.0, $0.1) : ($0.1, $0.0) })
        let items = (sent["items"] as? [[String: Any]] ?? []).map { item -> [String: Any] in
            let name = item["text"] as? String ?? ""
            return ["i": item["i"] as? Int ?? 0, "text": dictionary[name] ?? name]
        }
        return String(decoding: (try? JSONSerialization.data(withJSONObject: ["items": items])) ?? Data(), as: UTF8.self)
    }

    static func shoppingSortAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              format["name"] as? String == "shopping_sort" else { return nil }
        let content = ((json["input"] as? [[String: Any]])?.first?["content"] as? [[String: Any]]) ?? []
        let text = content.compactMap { $0["text"] as? String }.joined()
        let sent = (try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: [String]]) ?? [:]
        let items = sent["items"] ?? []
        let first = sent["categories"]?.first ?? ""
        let assignments = items.enumerated().map { index, item in ["item": item, "category": index == 0 ? "Demo" : first] }
        let answer: [String: Any] = ["assignments": assignments, "new_categories": ["Demo"]]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: answer)) ?? Data(), as: UTF8.self)
    }

    private static func planAnswer(for request: URLRequest) -> String? {
        guard let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let format = (json["text"] as? [String: Any])?["format"] as? [String: Any],
              let name = format["name"] as? String,
              let input = json["input"] as? [[String: Any]],
              let first = (input.first?["content"] as? [[String: Any]])?.first?["text"] as? String,
              let plan = try? JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any] else { return nil }
        if name == "suggestion_revision" { return revisionAnswer(plan) }
        let isRetry = input.count > 1
        let tasks = (plan["tasks"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let days = (plan["days"] as? [[String: Any]] ?? []).filter { $0["dayOff"] as? Bool == false }
        var answer: [String: Any] = ["unscheduled": [], "risks": ["Demo: Die Woche ist knapp."],
                                     "estimates": tasks.prefix(3).map { ["taskId": $0, "minutes": 45] }]
        answer["summary"] = "Demo: Der Zeitraum ist knapp, eine Aufgabe passt nur mit längerer Arbeitszeit."
        answer["moves"] = []
        answer["dayChanges"] = []
        if name == "day_plan" {
            let starts = ["16:30", "18:15", "03:00"]
            var blocks: [[String: Any]] = []
            for (index, task) in tasks.prefix(3).enumerated() where !(isRetry && index == 2) {
                blocks.append(["taskId": task, "start": starts[index], "minutes": 45, "reason": "Demo-Vorschlag"])
            }
            answer["blocks"] = blocks
            if let today = days.first?["day"] as? String {
                answer["dayChanges"] = [["day": today, "start": days.first?["workStart"] as? String ?? "09:00", "end": "19:30",
                                         "reason": "Demo: Sonst wird die zweite Aufgabe heute nicht fertig."]]
            }
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

    /// A conversation answer: the commented block moves one hour earlier (a move stays where it is).
    private static func revisionAnswer(_ request: [String: Any]) -> String? {
        let about = request["about"] as? String ?? ""
        let suggestions = request["suggestions"] as? [[String: Any]] ?? []
        var changes: [[String: Any]] = []
        if let target = suggestions.first(where: { $0["ref"] as? String == about }), let day = target["day"] as? String {
            if let start = (target["start"] as? String).flatMap(AIPlanner.minutes) {
                changes.append(["ref": about, "day": day, "start": AIPlanner.time(max(0, start - 60)),
                                "minutes": target["minutes"] as? Int ?? 30])
            }
        }
        let answer: [String: Any] = ["reply": "Demo: Ich habe den Vorschlag eine Stunde früher gelegt.", "changes": changes]
        return (try? JSONSerialization.data(withJSONObject: answer)).map { String(decoding: $0, as: UTF8.self) }
    }
}
#endif