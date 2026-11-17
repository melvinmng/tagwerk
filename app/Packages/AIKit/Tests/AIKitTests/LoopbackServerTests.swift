import Foundation
import Testing
@testable import AIKit

struct LoopbackServerTests {
    @Test func start_waitsForReady() async throws {
        let port = TestPorts.make()
        let server = LoopbackServer(port: port, expectedState: "s1")
        try await server.start()
        #expect(server.isReady)
        // Ready means a client can connect right away.
        let response = try await RawHTTPClient.get("/auth/callback?code=c&state=s1", port: port)
        #expect(response.hasPrefix("HTTP/1.1 302"))
        await server.stop()
    }

    @Test func server_callback_redirectsToAppSchemeAndDeliversURL() async throws {
        let port = TestPorts.make()
        let server = LoopbackServer(port: port, expectedState: "s1")
        try await server.start()
        let response = try await RawHTTPClient.get("/auth/callback?code=c1&state=s1&client_id=oaiapp_1", port: port)
        #expect(response.contains("Location: tagwerk://auth/done"))
        let url = try await server.waitForCallback(timeout: 2)
        #expect(url.absoluteString == "http://127.0.0.1:1455/auth/callback?code=c1&state=s1&client_id=oaiapp_1")
        await server.stop()
    }

    @Test func server_wrongState_ignored_thenCorrectAccepted() async throws {
        let port = TestPorts.make()
        let server = LoopbackServer(port: port, expectedState: "s1")
        try await server.start()
        let rejected = try await RawHTTPClient.get("/auth/callback?code=evil&state=wrong", port: port)
        #expect(rejected.hasPrefix("HTTP/1.1 400"))
        let unknownPath = try await RawHTTPClient.get("/favicon.ico", port: port)
        #expect(unknownPath.hasPrefix("HTTP/1.1 404"))
        _ = try await RawHTTPClient.get("/auth/callback?code=good&state=s1", port: port)
        let url = try await server.waitForCallback(timeout: 2)
        #expect(url.query?.contains("code=good") == true)
        await server.stop()
    }

    @Test func server_requestInTwoChunks() async throws {
        let port = TestPorts.make()
        let server = LoopbackServer(port: port, expectedState: "s1")
        try await server.start()
        let response = try await RawHTTPClient.send(
            ["GET /auth/callback?code=c1&state=s1 HTTP/1.1\r\nHo", "st: 127.0.0.1\r\n\r\n"], port: port
        )
        #expect(response.hasPrefix("HTTP/1.1 302"))
        let url = try await server.waitForCallback(timeout: 2)
        #expect(url.query == "code=c1&state=s1")
        await server.stop()
    }

    @Test func server_portInUse_reportsError() async throws {
        let port = TestPorts.make()
        let first = LoopbackServer(port: port, expectedState: "s1")
        try await first.start()
        let second = LoopbackServer(port: port, expectedState: "s2")
        await #expect(throws: ChatGPTAuthError.portInUse) { try await second.start() }
        await first.stop()
    }

    @Test func stop_freesPort_evenRightAfterServingARequest() async throws {
        let port = TestPorts.make()
        let first = LoopbackServer(port: port, expectedState: "s1")
        try await first.start()
        _ = try await RawHTTPClient.get("/auth/callback?code=c&state=s1", port: port)
        _ = try await first.waitForCallback(timeout: 2)
        await first.stop()
        let second = LoopbackServer(port: port, expectedState: "s2")
        try await second.start()
        await second.stop()
    }

    @Test func stop_failsPendingWait() async throws {
        let port = TestPorts.make()
        let server = LoopbackServer(port: port, expectedState: "s1")
        try await server.start()
        let wait = Task { try await server.waitForCallback(timeout: 10) }
        try await Task.sleep(for: .milliseconds(50))
        await server.stop()
        await #expect(throws: ChatGPTAuthError.cancelled) { try await wait.value }
    }

    @Test func waitForCallback_timesOut() async throws {
        let port = TestPorts.make()
        let server = LoopbackServer(port: port, expectedState: "s1")
        try await server.start()
        await #expect(throws: ChatGPTAuthError.timedOut) { try await server.waitForCallback(timeout: 0.1) }
        await server.stop()
    }
}
