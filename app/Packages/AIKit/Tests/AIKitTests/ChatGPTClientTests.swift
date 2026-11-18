import Foundation
import Synchronization
import Testing
@testable import AIKit

enum Fixture {
    static func text(_ name: String) throws -> String {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func json(_ name: String) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: Data(text(name).utf8)) as? [String: Any])
    }
}

/// Collects every event of a response stream, or the error that ended it.
func collect(_ stream: AsyncThrowingStream<StreamEvent, Error>) async -> (events: [StreamEvent], error: Error?) {
    var events: [StreamEvent] = []
    do {
        for try await event in stream { events.append(event) }
        return (events, nil)
    } catch {
        return (events, error)
    }
}

struct ChatGPTClientTests {
    let transport = StubAITransport()
    static let responsesPath = "/v1/responses"
    static let tokenPath = "/api/accounts/oauth/token"
    let tokens = ChatGPTTokens(accessToken: "at_valid", refreshToken: "rt_valid", idToken: nil,
                               expiresAt: fixedNow.addingTimeInterval(3600), clientID: "oaiapp_1", accountID: nil)

    func makeClient() -> ChatGPTClient {
        let session = ChatGPTSessionStore(store: InMemoryChatGPTCredentialStore(tokens: tokens), transport: transport, now: { fixedNow })
        return ChatGPTClient(session: session, transport: transport)
    }

    func respond(_ client: ChatGPTClient, input: [InputItem] = [.user("Hallo")]) -> AsyncThrowingStream<StreamEvent, Error> {
        client.respond(model: "gpt-test", instructions: "Antworte knapp.", input: input, tools: [], jsonSchema: nil)
    }

    static let createTask = ToolDefinition(
        name: "create_task", description: "Creates a local task.",
        parameters: Data(#"{"type":"object","additionalProperties":false,"required":["title","due","priority"],"properties":{"title":{"type":"string"},"due":{"type":["string","null"],"description":"YYYY-MM-DD"},"priority":{"type":["string","null"],"enum":["P1","P2","P3","P4",null]}}}"#.utf8),
        strict: true
    )
    static let rescheduleTask = ToolDefinition(
        name: "reschedule_task", description: "Moves the due date of an existing task.",
        parameters: Data(#"{"type":"object","additionalProperties":false,"required":["task_id","due"],"properties":{"task_id":{"type":"string"},"due":{"type":"string","description":"YYYY-MM-DD"}}}"#.utf8),
        strict: true
    )

    // MARK: Streams

    @Test func stream_textDeltasThenCompleted() async {
        transport.enqueueJSON(Self.responsesPath, """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hal"}
        data: {"type":"response.output_text.delta","delta":"lo"}
        data: {"type":"response.completed","response":{"status":"completed","usage":{"total_tokens":12}}}
        """)
        let (events, error) = await collect(respond(makeClient()))
        #expect(error == nil)
        #expect(events == [.textDelta("Hal"), .textDelta("lo"), .completed(usage: 12)])
    }

    @Test func stream_parallelFunctionCalls_bothEmitted() async throws {
        transport.enqueueJSON(Self.responsesPath, try Fixture.text("responses-function-calls.sse"))
        let (events, error) = await collect(respond(makeClient()))
        #expect(error == nil)
        #expect(events == [
            .functionCall(callID: "call_fixture1", name: "create_task",
                          arguments: #"{"due": "2026-11-18", "priority": "P2", "title": "Testaufgabe"}"#),
            .functionCall(callID: "call_fixture2", name: "reschedule_task",
                          arguments: #"{"due": "2026-11-19", "task_id": "local-7"}"#),
            .completed(usage: 285),
        ])
    }

    @Test func stream_followUpFixture_textThenCompleted() async throws {
        transport.enqueueJSON(Self.responsesPath, try Fixture.text("responses-follow-up.sse"))
        let (events, error) = await collect(respond(makeClient()))
        #expect(error == nil)
        let text = events.compactMap { event -> String? in
            if case .textDelta(let delta) = event { return delta } else { return nil }
        }.joined()
        #expect(text.hasPrefix("„Testaufgabe“ wurde für morgen"))
        #expect(events.last == .completed(usage: 370))
    }

    @Test func stream_endsWithoutCompleted_throwsIncomplete() async {
        transport.enqueueJSON(Self.responsesPath, """
        data: {"type":"response.output_text.delta","delta":"Hal"}
        """)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .incomplete)
    }

    @Test func stream_cutBeforeCompleted_emitsNoFunctionCalls() async throws {
        let full = try Fixture.text("responses-function-calls.sse")
        let cut = full.components(separatedBy: "\n").filter { !$0.contains("response.completed") }.joined(separator: "\n")
        transport.enqueueJSON(Self.responsesPath, cut)
        let (events, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .incomplete)
        #expect(events.isEmpty)
    }

    @Test func stream_failedEvent_mapsUsageLimit() async {
        transport.enqueueJSON(Self.responsesPath, """
        data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}
        """)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .usageLimit)
    }

    @Test func stream_incompleteEvent_mapsIncomplete() async {
        transport.enqueueJSON(Self.responsesPath, """
        data: {"type":"response.incomplete","response":{"incomplete_details":{"reason":"max_output_tokens"}}}
        """)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .incomplete)
    }

    @Test func stream_errorEvent_mapsCode() async {
        transport.enqueueJSON(Self.responsesPath, """
        data: {"type":"error","code":"server_overloaded","message":"busy"}
        """)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .server(200, "server_overloaded"))
    }

    @Test func stream_transportFailsBeforeResponse_mapsNetwork() async {
        transport.enqueue(Self.responsesPath, .failure(.notConnectedToInternet))
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .network)
    }

    @Test func stream_cancelled_cancelsRequest() async throws {
        let hanging = HangingStreamTransport()
        let session = ChatGPTSessionStore(store: InMemoryChatGPTCredentialStore(tokens: tokens), transport: hanging, now: { fixedNow })
        let client = ChatGPTClient(session: session, transport: hanging)
        let consumer = Task { await collect(respond(client)) }
        try await hanging.started.waitOrFail()
        consumer.cancel()
        _ = await consumer.value
        try await hanging.terminated.waitOrFail()
    }

    // MARK: HTTP errors

    @Test func http429_jsonBody_onStreamEndpoint() async {
        transport.enqueueJSON(Self.responsesPath, status: 429,
                              #"{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}"#)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .usageLimit)
        #expect(ChatGPTError.usageLimit.userMessage
            == "Das Nutzungslimit deines ChatGPT-Abos ist erreicht. Versuche es später erneut.")
    }

    @Test func error401_retriesOnceAfterRefresh() async {
        transport.enqueueJSON(Self.responsesPath, status: 401, #"{"error":{"code":"token_expired"}}"#)
        transport.enqueueJSON(Self.tokenPath, #"{"access_token":"at_new","refresh_token":"rt_new","expires_in":3600}"#)
        transport.enqueueJSON(Self.responsesPath, #"data: {"type":"response.completed","response":{}}"#)
        let (events, error) = await collect(respond(makeClient()))
        #expect(error == nil)
        #expect(events == [.completed(usage: nil)])
        let calls = transport.requests(to: Self.responsesPath)
        #expect(calls.count == 2)
        #expect(calls.last?.value(forHTTPHeaderField: "Authorization") == "Bearer at_new")
    }

    @Test func error401_twice_doesNotLoop() async {
        transport.enqueueJSON(Self.responsesPath, status: 401, #"{"error":{"code":"token_expired"}}"#)
        transport.enqueueJSON(Self.tokenPath, #"{"access_token":"at_new","refresh_token":"rt_new","expires_in":3600}"#)
        transport.enqueueJSON(Self.responsesPath, status: 401, #"{"error":{"code":"token_expired"}}"#)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .server(401, "token_expired"))
        #expect(transport.requests(to: Self.responsesPath).count == 2)
    }

    @Test func error401_invalidUser_noRefresh() async {
        transport.enqueueJSON(Self.responsesPath, status: 401, #"{"error":{"code":"subscription_sharing_invalid_user"}}"#)
        let (_, error) = await collect(respond(makeClient()))
        #expect(error as? ChatGPTError == .invalidUser)
        #expect(transport.requests(to: Self.tokenPath).isEmpty)
    }

    // MARK: Requests

    @Test func request_hasStoreFalseStreamTrue_noMaxTokens() async throws {
        transport.enqueueJSON(Self.responsesPath, #"data: {"type":"response.completed","response":{}}"#)
        _ = await collect(respond(makeClient()))
        let request = try #require(transport.requests(to: Self.responsesPath).first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/responses")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer at_valid")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(json["store"] as? Bool == false)
        #expect(json["stream"] as? Bool == true)
        #expect(json["model"] as? String == "gpt-test")
        #expect(json["instructions"] as? String == "Antworte knapp.")
        #expect(json["max_output_tokens"] == nil)
        #expect(json["temperature"] == nil)
        #expect(json["previous_response_id"] == nil)
        #expect(json["tools"] == nil)
        #expect(json["text"] == nil)
    }

    @Test func request_followUp_matchesCapturedShape() throws {
        let body = try ChatGPTClient.requestBody(
            model: "gpt-6.2-sol",
            instructions: "Du verwaltest Aufgaben in einer App. Heute ist 2026-11-17. Erledige Bitten über die Funktionen; rufe mehrere Funktionen parallel auf, wenn es passt.",
            input: [
                .user("Lege die Aufgabe „Testaufgabe“ für morgen mit Priorität P2 an und verschiebe die Aufgabe local-7 auf übermorgen."),
                .functionCall(callID: "call_fixture1", name: "create_task",
                              arguments: #"{"due": "2026-11-18", "priority": "P2", "title": "Testaufgabe"}"#),
                .functionCall(callID: "call_fixture2", name: "reschedule_task",
                              arguments: #"{"due": "2026-11-19", "task_id": "local-7"}"#),
                .functionOutput(callID: "call_fixture1", output: #"{"ok":true}"#),
                .functionOutput(callID: "call_fixture2", output: #"{"ok":true}"#),
            ],
            tools: [Self.createTask, Self.rescheduleTask],
            jsonSchema: nil
        )
        let built = try #require(try JSONSerialization.jsonObject(with: body) as? NSDictionary)
        let captured = try Fixture.json("responses-follow-up-request.json") as NSDictionary
        #expect(built == captured)
    }

    @Test func request_assistantText_isOutputTextMessage() throws {
        let body = try ChatGPTClient.requestBody(model: "m", instructions: "i", input: [.assistant("Erledigt.")],
                                                 tools: [], jsonSchema: nil)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let item = try #require((json["input"] as? [[String: Any]])?.first)
        #expect(item["type"] as? String == "message")
        #expect(item["role"] as? String == "assistant")
        let content = try #require((item["content"] as? [[String: Any]])?.first)
        #expect(content["type"] as? String == "output_text")
        #expect(content["text"] as? String == "Erledigt.")
    }

    @Test func request_jsonSchema_setsStrictTextFormat() throws {
        let schema = Data(#"{"type":"object","properties":{},"required":[],"additionalProperties":false}"#.utf8)
        let body = try ChatGPTClient.requestBody(model: "m", instructions: "i", input: [.user("p")], tools: [],
                                                 jsonSchema: (name: "day_plan", schema: schema))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let format = try #require((json["text"] as? [String: Any])?["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        #expect(format["name"] as? String == "day_plan")
        #expect(format["strict"] as? Bool == true)
        #expect((format["schema"] as? [String: Any])?["type"] as? String == "object")
    }

    @Test func inputItem_codableRoundTrip() throws {
        let items: [InputItem] = [.user("a"), .assistant("b"), .functionCall(callID: "c", name: "n", arguments: "{}"),
                                  .functionOutput(callID: "c", output: "ok")]
        let decoded = try JSONDecoder().decode([InputItem].self, from: JSONEncoder().encode(items))
        #expect(decoded == items)
    }

    // MARK: Models

    @Test func models_filtersListVisibility_keepsServerOrder() async throws {
        transport.enqueueJSON("/v1/models", """
        {"models":[
          {"slug":"gpt-b","display_name":"GPT-B","visibility":"list","base_instructions":"long"},
          {"slug":"gpt-hidden","display_name":"Hidden","visibility":"hide"},
          {"slug":"gpt-a","display_name":"GPT-A","visibility":"list"},
          {"slug":"gpt-none"}
        ]}
        """)
        let models = try await makeClient().models()
        #expect(models == [AIModel(slug: "gpt-b", displayName: "GPT-B"), AIModel(slug: "gpt-a", displayName: "GPT-A")])
        let request = try #require(transport.requests(to: "/v1/models").first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer at_valid")
    }

    @Test func models_readReasoningLevels() async throws {
        transport.enqueueJSON("/v1/models", #"{"models":[{"slug":"gpt-a","display_name":"A","visibility":"list","default_reasoning_level":"low","supported_reasoning_levels":[{"effort":"low","description":"x"},{"effort":"high"}]}]}"#)
        let model = try #require(try await makeClient().models().first)
        #expect(model.reasoningLevels == ["low", "high"])
        #expect(model.defaultReasoning == "low")
    }

    @Test func request_reasoningEffort_isSentOnlyWhenSet() throws {
        let plain = try JSONSerialization.jsonObject(with: ChatGPTClient.requestBody(
            model: "m", instructions: "i", input: [.user("p")], tools: [], jsonSchema: nil)) as? [String: Any]
        #expect(plain?["reasoning"] == nil)
        let set = try JSONSerialization.jsonObject(with: ChatGPTClient.requestBody(
            model: "m", instructions: "i", input: [.user("p")], tools: [], jsonSchema: nil, reasoningEffort: "high")) as? [String: Any]
        #expect((set?["reasoning"] as? [String: Any])?["effort"] as? String == "high")
    }

    @Test func models_missingDisplayName_usesSlug() async throws {
        transport.enqueueJSON("/v1/models", #"{"models":[{"slug":"gpt-x","visibility":"list"}]}"#)
        #expect(try await makeClient().models() == [AIModel(slug: "gpt-x", displayName: "gpt-x")])
    }

    @Test func models_429_mapsUsageLimit() async {
        transport.enqueueJSON("/v1/models", status: 429, #"{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}"#)
        await #expect(throws: ChatGPTError.usageLimit) { try await makeClient().models() }
    }

    @Test func models_401_retriesOnceAfterRefresh() async throws {
        transport.enqueueJSON("/v1/models", status: 401, #"{"error":{"code":"token_expired"}}"#)
        transport.enqueueJSON(Self.tokenPath, #"{"access_token":"at_new","refresh_token":"rt_new","expires_in":3600}"#)
        transport.enqueueJSON("/v1/models", #"{"models":[{"slug":"gpt-a","display_name":"A","visibility":"list"}]}"#)
        #expect(try await makeClient().models().map(\.slug) == ["gpt-a"])
    }
}

/// Streams nothing until the consumer goes away, and records that the stream was terminated.
final class HangingStreamTransport: AIHTTPTransport {
    let started = Gate()
    let terminated = Gate()

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.unsupportedURL)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let terminated = self.terminated
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.onTermination = { _ in terminated.open() }
        }
        started.open()
        return (stream, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }
}

extension Gate {
    /// Waits for the gate with a timeout, so a broken test fails instead of hanging.
    func waitOrFail(timeout: Duration = .seconds(2)) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while !isOpen {
            guard clock.now < deadline else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}
