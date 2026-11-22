import AVFoundation
import SwiftUI
import TagwerkCore

/// Device check for the voice mode (plan voice-chat, stage 2, point 18): one `.playAndRecord` session in
/// which speaking, the tone and recording take turns. Round 1: speak after the tone. Round 2: stay silent,
/// to see whether the recognizer hears the voice's echo. Nothing leaves the device.
@MainActor @Observable
final class ConversationSpikeModel {
    struct Round: Identifiable, Equatable {
        let id: Int
        var categoryAfterSpeaking = ""
        var speakingSeconds: Double?
        var firstTextSeconds: Double?
        var text = ""
        var outcome = ""
    }

    private(set) var rounds: [Round] = []
    private(set) var status: String?
    private(set) var route = ""
    private(set) var isRunning = false
    var language: VoiceLanguage = .german

    private let audio: VoiceAudioSession = SystemVoiceAudioSession.shared
    private let speaker = SystemSpeaker()
    private let tone = SystemTonePlayer()
    private var recognizer: AppleSpeechRecognizer?
    private var cancelled = false

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        cancelled = false
        rounds = []
        defer {
            audio.deactivate(.conversation)
            isRunning = false
            status = cancelled ? "Abgebrochen" : "Fertig"
        }
        do {
            try audio.activate(.conversation)
        } catch {
            status = "Session nicht aktiv: \(error.localizedDescription)"
            return
        }
        route = Self.describeRoute()
        let prompts = language == .german
            ? ["Runde eins. Nach dem Ton sag bitte einen Satz.", "Runde zwei. Nach dem Ton bitte nichts sagen."]
            : ["Round one. After the tone, please say a sentence.", "Round two. After the tone, please stay silent."]
        for (index, prompt) in prompts.enumerated() where !cancelled {
            var round = Round(id: index + 1)
            status = "Runde \(index + 1): spricht …"
            let started = Date()
            await speak(prompt)
            round.speakingSeconds = Date().timeIntervalSince(started)
            round.categoryAfterSpeaking = AVAudioSession.sharedInstance().category.rawValue
            if cancelled { break }
            status = "Runde \(index + 1): Ton"
            await withCheckedContinuation { continuation in tone.play { continuation.resume() } }
            if cancelled { break }
            status = "Runde \(index + 1): hört zu (6 s) …"
            await listen(into: &round)
            rounds.append(round)
            route = Self.describeRoute()
        }
    }

    func cancel() {
        cancelled = true
        speaker.stop()
        resumeWaiting?()
        tone.stop()
        if let recognizer { Task { await recognizer.cancel() } }
    }

    /// Resumes the step that is waiting; also called by `cancel()` and the time limit.
    private var resumeWaiting: (() -> Void)?

    private func speak(_ text: String) async {
        let voiceID = speaker.resolvedVoiceID(nil, language: language)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var resumed = false
            let resume = {
                guard !resumed else { return }
                resumed = true
                continuation.resume()
            }
            resumeWaiting = resume
            speaker.onEvent = { event in if event != .sentenceStarted(0) { resume() } }
            speaker.speak([text], language: language, voiceID: voiceID, rate: 0.5)
            Task { try? await Task.sleep(for: .seconds(15)); resume() }
        }
        resumeWaiting = nil
        speaker.onEvent = nil
    }

    private func listen(into round: inout Round) async {
        let recognizer = AppleSpeechRecognizer(kind: .dictation)
        self.recognizer = recognizer
        let started = Date()
        let events = await recognizer.start(language: language)
        let stopper = Task {
            try? await Task.sleep(for: .seconds(6))
            await recognizer.stop()
        }
        for await event in events {
            switch event {
            case .text(let final, let volatile):
                if round.firstTextSeconds == nil, !(final + volatile).trimmingCharacters(in: .whitespaces).isEmpty {
                    round.firstTextSeconds = Date().timeIntervalSince(started)
                }
                round.text = [final, volatile].filter { !$0.isEmpty }.joined(separator: " ")
            case .level: break
            case .finished: round.outcome = "fertig"
            case .failed(let failure): round.outcome = "Fehler: \(failure)"
            }
        }
        stopper.cancel()
        self.recognizer = nil
    }

    /// Port types only, no device names.
    private static func describeRoute() -> String {
        let route = AVAudioSession.sharedInstance().currentRoute
        let outputs = route.outputs.map(\.portType.rawValue).joined(separator: ", ")
        let inputs = route.inputs.map(\.portType.rawValue).joined(separator: ", ")
        return "Aus: \(outputs.isEmpty ? "–" : outputs) · Ein: \(inputs.isEmpty ? "–" : inputs)"
    }
}

struct ConversationSpikeSection: View {
    @State private var model = ConversationSpikeModel()

    var body: some View {
        Section {
            Picker("Sprache", selection: $model.language) {
                ForEach(VoiceLanguage.allCases, id: \.self) { Text($0 == .german ? "Deutsch" : "English").tag($0) }
            }
            .disabled(model.isRunning)
            Button {
                if model.isRunning { model.cancel() } else { Task { await model.run() } }
            } label: {
                Label(model.isRunning ? "Abbrechen" : "Sprechmodus-Probe starten",
                      systemImage: model.isRunning ? "stop.circle.fill" : "waveform.circle.fill")
            }
            if let status = model.status { Text(status).font(.footnote).foregroundStyle(.secondaryText) }
            if !model.route.isEmpty { LabeledContent("Route", value: model.route).font(.footnote) }
            ForEach(model.rounds) { round in
                VStack(alignment: .leading, spacing: 2) {
                    Text("Runde \(round.id)").font(.subheadline.weight(.semibold))
                    Text("Erkannt: \(round.text.isEmpty ? "–" : round.text)").textSelection(.enabled)
                    Group {
                        Text("Kategorie nach dem Sprechen: \(round.categoryAfterSpeaking)")
                        Text(String(format: "Sprechen %.1f s · erster Text %@ · %@", round.speakingSeconds ?? 0,
                                    round.firstTextSeconds.map { String(format: "%.1f s", $0) } ?? "–", round.outcome))
                    }
                    .font(.footnote).foregroundStyle(.secondaryText)
                }
            }
        } header: {
            Text("Sprechmodus auf dem iPhone")
        } footer: {
            Text("Tagwerk spricht, spielt einen Ton und hört 6 s zu, zweimal. In Runde 1 nach dem Ton einen Satz sagen, in Runde 2 schweigen. Einmal ohne und einmal mit Kopfhörern probieren.")
        }
        .onDisappear { model.cancel() }
    }
}
