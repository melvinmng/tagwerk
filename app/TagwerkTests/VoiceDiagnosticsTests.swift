import AIKit
import Foundation
import Testing
@testable import Tagwerk

struct VoiceDiagnosticsTests {
    @Test func transcriptionText_isAvailableWithRecognizedText() {
        let check = VoiceDiagnostics.check(VoiceDiagnostics.transcriptions, status: 200, body: Data(#"{"text":"Hallo"}"#.utf8))
        #expect(check.outcome == .available)
        #expect(check.detail == "Erkannt: „Hallo“")
    }

    @Test func audioBody_isAvailable() {
        let check = VoiceDiagnostics.check(VoiceDiagnostics.speech, status: 200, body: Data([0xFF, 0xF3, 0x01]))
        #expect(check.outcome == .available)
        #expect(check.detail.hasPrefix("Audio erhalten"))
    }

    @Test func rejectedDummyOffer_countsAsReachable() {
        let body = Data(#"{"error":{"code":"invalid_offer","message":"Failed to parse offer"}}"#.utf8)
        #expect(VoiceDiagnostics.check(VoiceDiagnostics.realtimeCalls, status: 400, body: body).outcome == .available)
    }

    @Test func errorBody_showsStatusAndCode() {
        let body = Data(#"{"error":{"code":"insufficient_quota","message":"No credits."}}"#.utf8)
        let check = VoiceDiagnostics.check(VoiceDiagnostics.speech, status: 429, body: body)
        #expect(check.outcome == .unavailable)
        #expect(check.detail == "HTTP 429 – insufficient_quota: No credits.")
    }

    @Test func unauthorizedAfterRefresh_isUnavailableWithStatus() {
        let check = VoiceDiagnostics.check(VoiceDiagnostics.speech, error: .server(401, "missing_scope"))
        #expect(check.outcome == .unavailable)
        #expect(check.detail == "HTTP 401 – missing_scope (Anmeldung hat keinen Zugriff)")
    }

    @Test func wav_hasHeaderAndPayload() {
        let data = VoiceDiagnostics.wav(samples: [1, -1], sampleRate: 16000)
        #expect(data.count == 48)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } == 16000)
    }

    @Test func realtimeSecret_readsValue() {
        #expect(RealtimeProbe.secret(from: Data(#"{"value":"ek_1","expires_at":1}"#.utf8)) == "ek_1")
        #expect(RealtimeProbe.secret(from: Data(#"{"client_secret":{"value":"ek_2"}}"#.utf8)) == "ek_2")
        #expect(RealtimeProbe.secret(from: Data("{}".utf8)) == nil)
    }

    @Test func resample_doublesSamplesFrom12kTo24k() {
        let data = RealtimeProbe.resample([0, 100], from: 12_000)
        let samples = data.withUnsafeBytes { Array($0.bindMemory(to: Int16.self)) }
        #expect(samples == [0, 50, 100, 100])
    }
}
