import AVFoundation
import Foundation
import UIKit
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

    /// The synthesizer only pauses when the app leaves or a call comes in; the highlight must not stay behind.
    @Test(arguments: [UIApplication.didEnterBackgroundNotification, AVAudioSession.interruptionNotification])
    func leavingOrInterruption_stopsReading(_ name: Notification.Name) {
        let center = NotificationCenter()
        let model = VoiceOutputModel(speaker: speaker, audio: audio,
                                     preferences: { VoiceOutputModel.Preferences(germanVoiceID: nil, englishVoiceID: nil, rate: 0.5) },
                                     isVoiceOverRunning: { false }, notifications: center)
        model.speak(id: "a1", text: "Erster Satz hier. Zweiter Satz dort.", explicit: true, fallback: .german)
        speaker.emit(.sentenceStarted(1))
        center.post(name: name, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue])
        #expect(model.speakingID == nil)
        #expect(model.sentences.isEmpty)
        #expect(speaker.stopCount >= 1)
        #expect(audio.deactivations == 1)
    }

    @Test func interruptionEnded_keepsNewReading() {
        let center = NotificationCenter()
        let model = VoiceOutputModel(speaker: speaker, audio: audio,
                                     preferences: { VoiceOutputModel.Preferences(germanVoiceID: nil, englishVoiceID: nil, rate: 0.5) },
                                     isVoiceOverRunning: { false }, notifications: center)
        model.speak(id: "a1", text: "Erster Satz hier.", explicit: true, fallback: .german)
        center.post(name: AVAudioSession.interruptionNotification, object: nil,
                    userInfo: [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue])
        #expect(model.speakingID == "a1")
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

    // MARK: Completion (voice mode, plan stage 2 point 10)

    @Test func completion_firesOnceWhenFinished() {
        let model = makeModel()
        var ends: [VoiceOutputModel.Ending] = []
        model.speak(id: "a1", text: "Erster Satz.", explicit: true, fallback: .german) { ends.append($0) }
        speaker.emit(.finished)
        speaker.emit(.finished)
        model.stop()
        #expect(ends == [.finished])
    }

    @Test func completion_firesOnStopAndInterruption() {
        let model = makeModel()
        var ends: [VoiceOutputModel.Ending] = []
        model.speak(id: "a1", text: "Erster Satz.", explicit: true, fallback: .german) { ends.append($0) }
        model.stop()
        model.speak(id: "a2", text: "Zweiter Satz.", explicit: true, fallback: .german) { ends.append($0) }
        speaker.emit(.interrupted)
        #expect(ends == [.stopped, .stopped])
    }

    @Test func completion_firesWhenReplacedByAnotherReading() {
        let model = makeModel()
        var ends: [VoiceOutputModel.Ending] = []
        model.speak(id: "a1", text: "Erster Satz.", explicit: true, fallback: .german) { ends.append($0) }
        model.speak(id: "a2", text: "Zweiter Satz.", explicit: true, fallback: .german)
        #expect(ends == [.stopped])
    }

    @Test func completion_firesOnEverySilentReturn() throws {
        var ends: [VoiceOutputModel.Ending] = []
        makeModel(voiceOver: true).speak(id: "a", text: "Satz.", explicit: false, fallback: .german) { ends.append($0) }
        makeModel().speak(id: "b", text: "✦ ", explicit: true, fallback: .german) { ends.append($0) }
        audio.failing = true
        makeModel().speak(id: "c", text: "Satz.", explicit: true, fallback: .german) { ends.append($0) }
        audio.failing = false
        try audio.activate(.recording)
        makeModel().speak(id: "d", text: "Satz.", explicit: true, fallback: .german) { ends.append($0) }
        #expect(ends == [.notSpoken, .notSpoken, .notSpoken, .notSpoken])
    }

    @Test func conversation_speaksInsideTheSessionWithoutEndingIt() throws {
        try audio.activate(.conversation)
        let model = makeModel()
        model.speak(id: "a1", text: "Antwort.", explicit: true, fallback: .german)
        speaker.emit(.finished)
        #expect(speaker.spoken.count == 1)
        #expect(audio.currentMode == .conversation)
        #expect(audio.deactivations == 0)
    }

    @Test func missingFinish_isGivenUpAfterTimeLimit() async {
        var wake: (() -> Void)?
        let model = VoiceOutputModel(speaker: speaker, audio: audio,
                                     preferences: { VoiceOutputModel.Preferences(germanVoiceID: nil, englishVoiceID: nil, rate: 0.5) },
                                     isVoiceOverRunning: { false },
                                     sleep: { _ in await withCheckedContinuation { continuation in wake = { continuation.resume() } } })
        var ends: [VoiceOutputModel.Ending] = []
        model.speak(id: "a1", text: "Erster Satz.", explicit: true, fallback: .german) { ends.append($0) }
        await awaitCondition("the time limit started to wait") { wake != nil }
        wake?()
        await awaitCondition("the reading was given up") { ends == [.stopped] }
        #expect(ends == [.stopped])
        #expect(model.speakingID == nil)
    }
}
