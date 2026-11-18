import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
struct VoiceOutputModelTests {
    let speaker = FakeSpeaker()
    let audio = FakeAudioSession()

    func makeModel(voiceOver: Bool = false) -> VoiceOutputModel {
        VoiceOutputModel(speaker: speaker, audio: audio,
                         preferences: { VoiceOutputModel.Preferences(germanVoiceID: nil, englishVoiceID: nil, rate: 0.5) },
                         isVoiceOverRunning: { voiceOver })
    }

    @Test func speak_detectsLanguagePreparesTextAndPicksBestVoice() {
        let model = makeModel()
        model.speak(id: "a1", text: "Heute sind **drei** Termine. Die Mail hat P2.", explicit: true, fallback: .german)
        let call = try! #require(speaker.spoken.first)
        #expect(call.language == .german)
        #expect(call.voiceID == "de.premium")
        #expect(call.sentences.joined(separator: " ").contains("Priorität zwei"))
        #expect(!call.sentences.joined().contains("**"))
        #expect(model.speakingID == "a1")
        #expect(audio.modes == [.speakingExplicit])
    }

    @Test func speak_english() {
        let model = makeModel()
        model.speak(id: "a1", text: "You have three meetings today and two open tasks.", explicit: true, fallback: .german)
        #expect(speaker.spoken.first?.language == .english)
        #expect(speaker.spoken.first?.voiceID == "en.default")
    }

    @Test func automatic_usesAmbient() {
        let model = makeModel()
        model.speak(id: "a1", text: "Heute sind drei Termine.", explicit: false, fallback: .german)
        #expect(audio.modes == [.speakingAutomatic])
    }

    @Test func automatic_suppressedWhileVoiceOverRuns_explicitStillSpeaks() {
        let model = makeModel(voiceOver: true)
        model.speak(id: "a1", text: "Heute sind drei Termine.", explicit: false, fallback: .german)
        #expect(speaker.spoken.isEmpty)
        model.speak(id: "a1", text: "Heute sind drei Termine.", explicit: true, fallback: .german)
        #expect(speaker.spoken.count == 1)
    }

    @Test func sentenceEvents_trackCurrentSentence_finishedClears() {
        let model = makeModel()
        model.speak(id: "a1", text: "Erster Satz hier. Zweiter Satz dort.", explicit: true, fallback: .german)
        speaker.emit(.sentenceStarted(1))
        #expect(model.currentSentence == 1)
        speaker.emit(.finished)
        #expect(model.speakingID == nil)
        #expect(audio.deactivations == 1)
    }

    @Test func stop_clearsStateAndStopsSpeaker() {
        let model = makeModel()
        model.speak(id: "a1", text: "Erster Satz hier.", explicit: true, fallback: .german)
        model.stop()
        #expect(model.speakingID == nil)
        #expect(speaker.stopCount >= 1)
        #expect(audio.deactivations == 1)
    }

    @Test func speakAgain_stopsPrevious() {
        let model = makeModel()
        model.speak(id: "a1", text: "Erster Satz hier.", explicit: true, fallback: .german)
        model.speak(id: "a2", text: "Zweiter Satz dort.", explicit: true, fallback: .german)
        #expect(model.speakingID == "a2")
        #expect(speaker.stopCount >= 1)
    }

    @Test func audioFailure_showsNotice() {
        audio.failing = true
        let model = makeModel()
        model.speak(id: "a1", text: "Erster Satz hier.", explicit: true, fallback: .german)
        #expect(model.speakingID == nil)
        #expect(model.notice == "Vorlesen nicht möglich")
        #expect(speaker.spoken.isEmpty)
    }

    @Test func emptyText_doesNothing() {
        let model = makeModel()
        model.speak(id: "a1", text: "✦  ", explicit: true, fallback: .german)
        #expect(speaker.spoken.isEmpty)
        #expect(model.speakingID == nil)
    }

    @Test func recording_blocksReading_explicitShowsNotice() throws {
        try audio.activate(.recording)
        let model = makeModel()
        model.speak(id: "a1", text: "Heute sind drei Termine.", explicit: false, fallback: .german)
        #expect(speaker.spoken.isEmpty)
        #expect(model.notice == nil)
        model.speak(id: "a1", text: "Heute sind drei Termine.", explicit: true, fallback: .german)
        #expect(speaker.spoken.isEmpty)
        #expect(model.notice == "Erst die Aufnahme beenden")
        #expect(audio.currentMode == .recording)
    }
}
