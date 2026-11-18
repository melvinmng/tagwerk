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

    @Test func wav_hasHeaderAndPayload() {
        let data = VoiceDiagnostics.wav(samples: [1, -1], sampleRate: 16000)
        #expect(data.count == 48)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
        #expect(String(decoding: data[8..<12], as: UTF8.self) == "WAVE")
        #expect(data[24..<28].withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian } == 16000)
    }
}
