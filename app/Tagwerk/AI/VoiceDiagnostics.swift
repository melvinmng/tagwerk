import AIKit
import AVFoundation
import Foundation
import SwiftUI

/// One checked voice endpoint: what was called and what came back (never the token).
struct VoiceCheck: Identifiable, Equatable {
    enum Outcome: Equatable { case available, unavailable, failed }

    let id: String
    let title: String
    var outcome: Outcome
    var detail: String
}

/// Probes which OpenAI voice endpoints accept the app's ChatGPT login. Runs only on a tap (§8.4).
enum VoiceDiagnostics {
    struct Probe {
        let id: String
        let title: String
        let url: URL
    }

    static let transcriptions = Probe(id: "transcriptions", title: "OpenAI Spracherkennung",
                                      url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
    static let speech = Probe(id: "speech", title: "OpenAI Vorlesen (marin)",
                              url: URL(string: "https://api.openai.com/v1/audio/speech")!)
    static let realtimeCalls = Probe(id: "realtime", title: "OpenAI Sprechmodus (WebRTC)",
                                     url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
    static let clientSecrets = Probe(id: "secrets", title: "OpenAI Sprechmodus (Sitzung)",
                                     url: URL(string: "https://api.openai.com/v1/realtime/client_secrets")!)
    static let chatGPTTranscribe = Probe(id: "chatgpt", title: "ChatGPT Spracherkennung",
                                         url: URL(string: "https://chatgpt.com/backend-api/transcribe")!)

    static let sampleSentence = "Verschiebe das Blumengießen bitte auf morgen um neun Uhr."

    /// Reads a reply into a row. A rejected dummy WebRTC offer still proves that the endpoint is open.
    static func check(_ probe: Probe, status: Int, body: Data) -> VoiceCheck {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = json?["error"] as? [String: Any]
        let code = (error?["code"] as? String) ?? (error?["type"] as? String) ?? (json?["detail"] as? String)
        let message = (error?["message"] as? String).map { String($0.prefix(140)) }
        if (200..<300).contains(status) {
            if let text = json?["text"] as? String {
                return VoiceCheck(id: probe.id, title: probe.title, outcome: .available, detail: "Erkannt: „\(text)“")
            }
            if json == nil {
                return VoiceCheck(id: probe.id, title: probe.title, outcome: .available,
                                  detail: "Audio erhalten (\(ByteCountFormatter.string(fromByteCount: Int64(body.count), countStyle: .file)))")
            }
            return VoiceCheck(id: probe.id, title: probe.title, outcome: .available, detail: "HTTP \(status)")
        }
        if status == 400, code == "invalid_offer" {
            return VoiceCheck(id: probe.id, title: probe.title, outcome: .available,
                              detail: "Erreichbar (Testangebot erwartungsgemäß abgelehnt)")
        }
        let reason = [code, message].compactMap { $0 }.joined(separator: ": ")
        return VoiceCheck(id: probe.id, title: probe.title, outcome: .unavailable,
                          detail: "HTTP \(status)" + (reason.isEmpty ? "" : " – \(reason)"))
    }

    static func speechBody() -> Data {
        let body: [String: Any] = ["model": "gpt-4o-mini-tts", "voice": "marin", "response_format": "mp3",
                                   "input": "Ich habe das Blumengießen auf morgen um neun Uhr verschoben."]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    static func realtimeBody(sdp: String) -> Data {
        let body: [String: Any] = ["sdp": sdp, "session": ["type": "realtime", "model": "gpt-realtime"]]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    static func clientSecretBody() -> Data {
        let body: [String: Any] = ["session": ["type": "realtime", "model": "gpt-realtime"]]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    /// 16-bit mono PCM samples as a WAV file.
    static func wav(samples: [Int16], sampleRate: Int) -> Data {
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        let payload = samples.count * 2
        data.append(Data("RIFF".utf8)); append(UInt32(36 + payload)); data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8)); append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(sampleRate)); append(UInt32(sampleRate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append(Data("data".utf8)); append(UInt32(payload))
        for sample in samples { append(sample) }
        return data
    }
}

/// Speaks the sample sentence into memory with the system voice, as test audio for the recognizers.
@MainActor
final class SpeechSampleRecorder {
    private let synthesizer = AVSpeechSynthesizer()

    func germanSample() async -> Data? {
        let utterance = AVSpeechUtterance(string: VoiceDiagnostics.sampleSentence)
        utterance.voice = AVSpeechSynthesisVoice(language: "de-DE")
        return await withCheckedContinuation { continuation in
            var samples: [Int16] = []
            var rate = 0
            var finished = false
            synthesizer.write(utterance) { buffer in
                guard !finished else { return }
                guard let pcm = buffer as? AVAudioPCMBuffer, pcm.frameLength > 0 else {
                    finished = true
                    continuation.resume(returning: samples.isEmpty ? nil : VoiceDiagnostics.wav(samples: samples, sampleRate: rate))
                    return
                }
                rate = Int(pcm.format.sampleRate)
                let count = Int(pcm.frameLength)
                if let floats = pcm.floatChannelData?[0] {
                    samples += (0..<count).map { Int16(max(-1, min(1, floats[$0])) * Float(Int16.max)) }
                } else if let ints = pcm.int16ChannelData?[0] {
                    samples += (0..<count).map { ints[$0] }
                }
            }
        }
    }
}

@MainActor @Observable
final class VoiceDiagnosticsModel {
    private(set) var checks: [VoiceCheck] = []
    private(set) var isRunning = false
    private(set) var speechAudio: Data?
    private var player: AVAudioPlayer?
    private let recorder = SpeechSampleRecorder()

    func run(client: ChatGPTClient) async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        checks = []
        speechAudio = nil

        let sample = await recorder.germanSample()
        if let sample {
            let form = ChatGPTClient.multipart(fields: [("model", "gpt-4o-mini-transcribe")], file: sample,
                                               fileName: "audio.wav", mimeType: "audio/wav")
            await probe(VoiceDiagnostics.transcriptions, client: client, body: form.body, contentType: form.contentType)
        }
        await probe(VoiceDiagnostics.speech, client: client, body: VoiceDiagnostics.speechBody(), contentType: "application/json") { data in
            self.speechAudio = data
        }
        await probe(VoiceDiagnostics.realtimeCalls, client: client, body: VoiceDiagnostics.realtimeBody(sdp: "v=0"),
                    contentType: "application/json")
        await probe(VoiceDiagnostics.clientSecrets, client: client, body: VoiceDiagnostics.clientSecretBody(),
                    contentType: "application/json")
        if let sample {
            let form = ChatGPTClient.multipart(fields: [], file: sample, fileName: "audio.wav", mimeType: "audio/wav")
            await probe(VoiceDiagnostics.chatGPTTranscribe, client: client, body: form.body, contentType: form.contentType)
        } else {
            checks.append(VoiceCheck(id: "sample", title: "Testaufnahme", outcome: .failed,
                                     detail: "Die Systemstimme hat keine Testaufnahme geliefert."))
        }
    }

    func playSpeech() {
        guard let speechAudio else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        player = try? AVAudioPlayer(data: speechAudio)
        player?.play()
    }

    private func probe(_ probe: VoiceDiagnostics.Probe, client: ChatGPTClient, body: Data, contentType: String,
                       onAudio: ((Data) -> Void)? = nil) async {
        do {
            let reply = try await client.post(probe.url, body: body, contentType: contentType)
            let check = VoiceDiagnostics.check(probe, status: reply.status, body: reply.body)
            if check.outcome == .available, (200..<300).contains(reply.status) { onAudio?(reply.body) }
            checks.append(check)
        } catch {
            checks.append(VoiceCheck(id: probe.id, title: probe.title, outcome: .failed, detail: error.localizedDescription))
        }
    }
}

struct VoiceDiagnosticsView: View {
    let client: ChatGPTClient
    @State private var model = VoiceDiagnosticsModel()

    var body: some View {
        List {
            Section {
                Button {
                    Task { await model.run(client: client) }
                } label: {
                    if model.isRunning {
                        HStack { ProgressView(); Text("Prüfe …") }
                    } else {
                        Text("Sprachdienste prüfen")
                    }
                }
                .disabled(model.isRunning)
            } footer: {
                Text("Sendet einen gesprochenen Testsatz und einen kurzen Text an OpenAI und ChatGPT, um zu sehen, welche Sprachdienste dein Abo freigibt. Es werden nur Statuscodes angezeigt.")
            }
            if !model.checks.isEmpty {
                Section("Ergebnis") {
                    ForEach(model.checks) { check in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(check.title, systemImage: icon(check.outcome))
                                .foregroundStyle(color(check.outcome))
                            Text(check.detail).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                            if check.id == VoiceDiagnostics.speech.id, model.speechAudio != nil {
                                Button("Abspielen", systemImage: "play.fill") { model.playSpeech() }
                                    .buttonStyle(.bordered)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sprachdienste")
    }

    private func icon(_ outcome: VoiceCheck.Outcome) -> String {
        switch outcome {
        case .available: "checkmark.circle.fill"
        case .unavailable: "xmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private func color(_ outcome: VoiceCheck.Outcome) -> Color {
        switch outcome {
        case .available: .green
        case .unavailable: .red
        case .failed: .orange
        }
    }
}
