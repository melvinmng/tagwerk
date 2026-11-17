import XCTest
@testable import TagwerkSpike

final class ChatGPTAuthTests: XCTestCase {
    func test_codeChallenge_matchesRFC7636AppendixB() {
        XCTAssertEqual(
            ChatGPTAuth.codeChallenge(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
            "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
        )
    }

    func test_authorizeURL_registration_containsRequiredParameters() throws {
        let url = ChatGPTAuth.authorizeURL(
            clientID: nil, hostID: "urn:uuid:11111111-2222-4333-8444-555555555555",
            state: "s1", nonce: "n1", challenge: "c1"
        )
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(url.host, "auth.openai.com")
        XCTAssertEqual(url.path, "/api/accounts/authorize")
        XCTAssertEqual(query["client_id"], "dynamic_agent_client")
        XCTAssertEqual(query["agent_name_hint"], "Tagwerk")
        XCTAssertEqual(query["ext_agent_host_id"], "urn:uuid:11111111-2222-4333-8444-555555555555")
        XCTAssertEqual(query["response_type"], "code")
        XCTAssertEqual(query["redirect_uri"], "http://127.0.0.1:1455/auth/callback")
        XCTAssertEqual(query["scope"], "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct")
        XCTAssertEqual(query["resource"], "https://api.openai.com/v1")
        XCTAssertEqual(query["code_challenge_method"], "S256")
        XCTAssertEqual(query["code_challenge"], "c1")
        XCTAssertEqual(query["state"], "s1")
        XCTAssertEqual(query["nonce"], "n1")
    }

    func test_authorizeURL_reauthorization_usesIssuedIDWithoutNameHint() throws {
        let url = ChatGPTAuth.authorizeURL(clientID: "oaiapp_abc", hostID: "urn:uuid:x", state: "s", nonce: "n", challenge: "c")
        let items = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertTrue(items.contains(URLQueryItem(name: "client_id", value: "oaiapp_abc")))
        XCTAssertFalse(items.contains { $0.name == "agent_name_hint" })
    }

    func test_parseCallback_stateMismatch_throws() {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?code=abc&state=wrong&client_id=oaiapp_1")!
        XCTAssertThrowsError(try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: true))
    }

    func test_parseCallback_registrationWithoutClientID_throws() {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?code=abc&state=s1")!
        XCTAssertThrowsError(try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: true))
    }

    func test_parseCallback_valid_returnsCodeAndClientID() throws {
        let url = URL(string: "http://127.0.0.1:1455/auth/callback?code=abc&state=s1&client_id=oaiapp_1")!
        let callback = try ChatGPTAuth.parseCallback(url, expectedState: "s1", isRegistration: true)
        XCTAssertEqual(callback.code, "abc")
        XCTAssertEqual(callback.clientID, "oaiapp_1")
    }

    func test_tokenRequest_isFormEncodedAuthorizationCodeGrant() throws {
        let request = ChatGPTAuth.tokenRequest(clientID: "oaiapp_1", code: "abc", verifier: "v1")
        XCTAssertEqual(request.url?.absoluteString, "https://auth.openai.com/api/accounts/oauth/token")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let fields = Set(body.split(separator: "&").map(String.init))
        XCTAssertTrue(fields.contains("grant_type=authorization_code"))
        XCTAssertTrue(fields.contains("client_id=oaiapp_1"))
        XCTAssertTrue(fields.contains("code=abc"))
        XCTAssertTrue(fields.contains("code_verifier=v1"))
        XCTAssertTrue(fields.contains("redirect_uri=http%3A%2F%2F127.0.0.1%3A1455%2Fauth%2Fcallback"))
        XCTAssertTrue(fields.contains("resource=https%3A%2F%2Fapi.openai.com%2Fv1"))
    }

    func test_refreshRequest_usesRefreshTokenGrantWithoutScope() throws {
        let request = ChatGPTAuth.refreshRequest(clientID: "oaiapp_1", refreshToken: "r1")
        let body = try XCTUnwrap(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        let fields = Set(body.split(separator: "&").map(String.init))
        XCTAssertTrue(fields.contains("grant_type=refresh_token"))
        XCTAssertTrue(fields.contains("refresh_token=r1"))
        XCTAssertTrue(fields.contains("client_id=oaiapp_1"))
        XCTAssertFalse(fields.contains { $0.hasPrefix("scope=") })
    }
}

final class ChatGPTProbeTests: XCTestCase {
    func test_filterModels_keepsOnlyListedModels() {
        let body = Data(#"{"models":[{"slug":"gpt-a","display_name":"A","visibility":"list"},{"slug":"gpt-b","visibility":"hide"},{"slug":"gpt-c"}]}"#.utf8)
        XCTAssertEqual(ChatGPTProbe.filterModels(body), ["gpt-a"])
    }

    func test_summarizeModels_showsIdsAndVisibility() {
        let body = Data(#"{"models":[{"slug":"gpt-x","visibility":"hidden"},{"slug":"gpt-y"}]}"#.utf8)
        let summary = ChatGPTProbe.summarizeModels(body)
        XCTAssertTrue(summary.contains("2 Modelle"))
        XCTAssertTrue(summary.contains("gpt-x[hidden]"))
        XCTAssertTrue(summary.contains("gpt-y[-]"))
    }

    func test_summarizeModels_unexpectedShape_showsRawPrefix() {
        let summary = ChatGPTProbe.summarizeModels(Data(#"{"models":["a"]}"#.utf8))
        XCTAssertTrue(summary.contains("{\"models\""))
    }

    func test_parseStream_accumulatesDeltasAndDetectsCompletion() {
        let stream = """
        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"Hal"}

        event: response.output_text.delta
        data: {"type":"response.output_text.delta","delta":"lo"}

        event: response.completed
        data: {"type":"response.completed","response":{"status":"completed"}}

        """
        let outcome = ChatGPTProbe.parseStream(stream)
        XCTAssertEqual(outcome.text, "Hallo")
        XCTAssertTrue(outcome.completed)
        XCTAssertNil(outcome.errorCode)
    }

    func test_parseStream_failedEvent_reportsErrorCode() {
        let stream = """
        data: {"type":"response.failed","response":{"error":{"code":"subscription_sharing_usage_limit_exceeded","message":"limit"}}}

        """
        let outcome = ChatGPTProbe.parseStream(stream)
        XCTAssertFalse(outcome.completed)
        XCTAssertEqual(outcome.errorCode, "subscription_sharing_usage_limit_exceeded")
    }

    func test_describe_usageLimit_isReadable() {
        let body = Data(#"{"error":{"code":"subscription_sharing_usage_limit_exceeded"}}"#.utf8)
        XCTAssertTrue(ChatGPTProbe.describe(status: 429, body: body).contains("Kontingent"))
    }

    func test_describe_invalidUser_asksForLogin() {
        let body = Data(#"{"error":{"code":"subscription_sharing_invalid_user"}}"#.utf8)
        XCTAssertTrue(ChatGPTProbe.describe(status: 401, body: body).contains("anmelden"))
    }

    func test_responsesRequest_followsPreviewRules() throws {
        let request = ChatGPTProbe.makeResponsesRequest(
            accessToken: "t", model: "gpt-a", instructions: "i", prompt: "p", imageJPEG: Data([1, 2]), jsonSchema: nil
        )
        XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer t")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(json["store"] as? Bool, false)
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["instructions"] as? String, "i")
        XCTAssertNil(json["max_output_tokens"])
        XCTAssertNil(json["temperature"])
        let input = try XCTUnwrap(json["input"] as? [[String: Any]])
        let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
        XCTAssertEqual(content.last?["type"] as? String, "input_image")
        XCTAssertEqual(content.last?["image_url"] as? String, "data:image/jpeg;base64,AQI=")
    }

    func test_responsesRequest_withSchema_setsTextFormat() throws {
        let schema: [String: Any] = ["type": "object", "properties": [:], "additionalProperties": false, "required": []]
        let request = ChatGPTProbe.makeResponsesRequest(
            accessToken: "t", model: "gpt-a", instructions: "i", prompt: "p", imageJPEG: nil, jsonSchema: ("meal", schema)
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
        let format = try XCTUnwrap((json["text"] as? [String: Any])?["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "json_schema")
        XCTAssertEqual(format["name"] as? String, "meal")
        XCTAssertEqual(format["strict"] as? Bool, true)
    }
}

final class ProbeStatusTests: XCTestCase {
    func test_claudeProbe_withoutKey_isSkipped() async {
        let result = await ClaudeProbe(keyLoader: { nil }).run()
        XCTAssertTrue(result.skipped)
        XCTAssertTrue(result.detail.contains("übersprungen"))
    }
}
