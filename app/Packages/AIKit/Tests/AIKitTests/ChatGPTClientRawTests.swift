import Foundation
import Testing
@testable import AIKit

struct ChatGPTClientRawTests {
    let transport = StubAITransport()
    let tokens = ChatGPTTokens(accessToken: "at_valid", refreshToken: "rt_valid", idToken: nil,
                               expiresAt: fixedNow.addingTimeInterval(3600), clientID: "oaiapp_1", accountID: "acc_1")

    func makeClient() -> ChatGPTClient {
        let session = ChatGPTSessionStore(store: InMemoryChatGPTCredentialStore(tokens: tokens), transport: transport, now: { fixedNow })
        return ChatGPTClient(session: session, transport: transport)
    }

    @Test func post_sendsBodyWithTokenAndReturnsAnyStatus() async throws {
        transport.enqueueJSON("/v1/audio/speech", status: 403, #"{"error":{"code":"unsupported"}}"#)
        let reply = try await makeClient().post(URL(string: "https://api.openai.com/v1/audio/speech")!,
                                                body: Data("{}".utf8), contentType: "application/json")
        #expect(reply.status == 403)
        #expect(String(decoding: reply.body, as: UTF8.self).contains("unsupported"))
        let request = try #require(transport.requests(to: "/v1/audio/speech").first)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer at_valid")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acc_1")
        #expect(request.httpBody == Data("{}".utf8))
    }

    @Test func post_refreshesOnceOn401() async throws {
        transport.enqueueJSON("/v1/audio/speech", status: 401, #"{"error":{"code":"token_expired"}}"#)
        transport.enqueueJSON("/api/accounts/oauth/token", #"{"access_token":"at_new","refresh_token":"rt_new","expires_in":3600}"#)
        transport.enqueueJSON("/v1/audio/speech", #"{}"#)
        let reply = try await makeClient().post(URL(string: "https://api.openai.com/v1/audio/speech")!,
                                                body: Data(), contentType: "application/json")
        #expect(reply.status == 200)
        #expect(transport.requests(to: "/v1/audio/speech").last?.value(forHTTPHeaderField: "Authorization") == "Bearer at_new")
    }

    @Test func multipart_buildsFileAndFields() {
        let form = ChatGPTClient.multipart(fields: [("model", "m1")], file: Data([1, 2]), fileName: "audio.wav",
                                           mimeType: "audio/wav", boundary: "B")
        let text = String(decoding: form.body, as: UTF8.self)
        #expect(form.contentType == "multipart/form-data; boundary=B")
        #expect(text.contains("--B\r\nContent-Disposition: form-data; name=\"model\"\r\n\r\nm1\r\n"))
        #expect(text.contains("name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n"))
        #expect(text.hasSuffix("\r\n--B--\r\n"))
    }
}
