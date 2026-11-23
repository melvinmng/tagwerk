import AVFoundation
import Foundation
import Testing
import TagwerkCore
import UIKit
@testable import Tagwerk

@MainActor
final class FakeVoiceAssistant: VoiceModeAssistant {
    var onTurnFinished: ((AssistantModel.TurnOutcome) -> Void)?
    var openCards = OpenCards.none
    var sent: [String] = []
    var confirmed: [[String]] = []
    var declined: [[String]] = []
    /// Outcomes reported for the next sends, in order.
    var replies: [AssistantModel.TurnOutcome] = []

    func send(_ text: String, spoken: Bool) async {
        sent.append(text)
        reply()
    }

    func confirmCards(_ ids: [String]) async {
        confirmed.append(ids)
        reply()
    }

    func declineCards(_ ids: [String]) async {
        declined.append(ids)
        reply()
    }

    private func reply() {
        guard !replies.isEmpty else { return }
        onTurnFinished?(replies.removeFirst())
    }
}

@MainActor
final class FakeTone: ToneSounding {
    var plays = 0
    private var completion: (@MainActor () -> Void)?
    func play(completion: @escaping @MainActor () -> Void) { plays += 1; self.completion = completion }
    func stop() { finish() }
    func finish() { let completion = completion; self.completion = nil; completion?() }
}

@MainActor
final class VoiceModeHarness {
    let recognizer = FakeSpeechRecognizer()
    let speaker = FakeSpeaker()
    let audio = FakeAudioSession()
    let tone = FakeTone()
    let assistant = FakeVoiceAssistant()
    let center = NotificationCenter()
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var draft: [String] = []
    var ended = 0
    var screenOn: [Bool] = []
    lazy var output = VoiceOutputModel(speaker: speaker, audio: audio,
                                       preferences: { VoiceOutputModel.Preferences(germanVoiceID: nil, englishVoiceID: nil, rate: 0.5) },
                                       isVoiceOverRunning: { false }, notifications: NotificationCenter(),
                                       sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
    lazy var controller: VoiceModeController = {
        let controller = VoiceModeController(
            assistant: assistant, makeRecognizer: { self.recognizer }, output: output, tone: tone, audio: audio,
            settings: { .init(language: .german, sendDelay: 2, silenceLimit: 30) },
            now: { self.clock }, sleep: { _ in try? await Task.sleep(for: .seconds(3600)) },
            keepScreenOn: { self.screenOn.append($0) }, notifications: center)
        controller.onMoveToDraft = { self.draft.append($0) }
        controller.onEnded = { self.ended += 1 }
        return controller
    }()

    /// Distinct values for the barrier events of `waitForListening`.
    private var barrierLevel: Float = 0

    /// Waits until the recognizer was started `starts` times in total and the controller processed the `.started` event
    /// of the last start. The recognizer's stream delivers its events in order, so a level event sent now arrives after
    /// `.started` and tells that the controller has seen it.
    func waitForListening(starts: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("\(starts) recognizer start(s)", sourceLocation: sourceLocation) { recognizer.started.count == starts }
        barrierLevel += 0.01
        let barrier = barrierLevel
        recognizer.send(.level(barrier))
        await awaitCondition("the recognizer's started event", sourceLocation: sourceLocation) { controller.level == barrier }
    }

    func waitForPhase(_ phase: VoiceModeMachine.Phase, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("phase \(phase)", sourceLocation: sourceLocation) { controller.phase == phase }
    }

    /// Gives queued work a chance to run before a test asserts that something did NOT happen. A turn count cannot prove
    /// absence, but it cannot make a test fail spuriously either; positive expectations use `awaitCondition`.
    func drain() async { for _ in 0..<50 { await Task.yield() } }

    /// Starts the mode and waits until the recognizer reports that it runs.
    func startListening() async {
        controller.start()
        await waitForListening(starts: recognizer.started.count + 1)
    }

    /// Says `text`, waits out the countdown, lets the final text arrive and waits until `handled` holds.
    func say(_ text: String, until handled: () -> Bool, sourceLocation: SourceLocation = #_sourceLocation) async {
        recognizer.send(.text(final: text, volatile: ""))
        await awaitCondition("the controller heard \"\(text)\"", sourceLocation: sourceLocation) { controller.machine.text == text }
        recognizer.finalOnStop = text
        clock += 3
        controller.tick()
        await awaitCondition("the utterance \"\(text)\" was handled", sourceLocation: sourceLocation, until: handled)
    }

    /// Says `text` and waits until the assistant received it.
    func sayAndSend(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        await say(text, until: { assistant.sent.last == text }, sourceLocation: sourceLocation)
    }
}

@MainActor
struct VoiceModeControllerTests {
    @Test func loop_listenSendSpeakListen() async {
        let harness = VoiceModeHarness()
        harness.assistant.replies = [.answered(id: "message-1", speech: "Drei Termine heute.", cards: .none)]
        await harness.startListening()
        #expect(harness.audio.currentMode == .conversation)
        #expect(harness.controller.phase == .listening)
        #expect(harness.screenOn == [true])
        await harness.sayAndSend("Was steht heute an?")
        #expect(harness.assistant.sent == ["Was steht heute an?"])
        #expect(harness.controller.phase == .speaking)
        #expect(harness.speaker.spoken.count == 1)
        #expect(harness.output.speakingID == "message-1")
        harness.speaker.emit(.finished)
        #expect(harness.controller.phase == .tone)
        #expect(harness.tone.plays == 1)
        harness.tone.finish()
        await harness.waitForListening(starts: 2)
        #expect(harness.controller.phase == .listening)
        #expect(harness.recognizer.started.count == 2)
        #expect(harness.audio.currentMode == .conversation)
    }

    @Test func openCard_keepsListening_andJaConfirmsAfterCountdown() async {
        let harness = VoiceModeHarness()
        let card = OpenCards(ids: ["c1"], deletes: 0)
        harness.assistant.replies = [.answered(id: "message-1", speech: "Ich lege die Mail auf 16 Uhr.", cards: card),
                                     .answered(id: "message-3", speech: "Ausgeführt.", cards: .none)]
        await harness.startListening()
        await harness.sayAndSend("Leg die Mail auf 16 Uhr")
        harness.speaker.emit(.finished)
        harness.tone.finish()
        await harness.waitForListening(starts: 2)
        #expect(harness.controller.phase == .listening)
        // "Ja" is not sent: the recognizer restarts and the confirmation countdown begins once it listens again.
        await harness.say("Ja", until: { harness.recognizer.started.count == 3 })
        await harness.waitForListening(starts: 3)
        guard case .confirming = harness.controller.phase else { Issue.record("\(harness.controller.phase)"); return }
        #expect(harness.assistant.confirmed.isEmpty)
        harness.clock += 2
        harness.controller.tick()
        await awaitCondition("the cards were confirmed") { harness.assistant.confirmed == [["c1"]] }
        #expect(harness.assistant.confirmed == [["c1"]])
        #expect(harness.controller.phase == .speaking)
    }

    @Test func openCard_neinDeclines_andCorrectionIsSent() async {
        let harness = VoiceModeHarness()
        let card = OpenCards(ids: ["c1"], deletes: 0)
        harness.assistant.replies = [.answered(id: "message-1", speech: "Vorschlag.", cards: card)]
        await harness.startListening()
        await harness.sayAndSend("Leg einen Termin an")
        harness.speaker.emit(.finished)
        harness.tone.finish()
        await harness.waitForListening(starts: 2)
        await harness.sayAndSend("Nimm den Arbeitskalender")
        #expect(harness.assistant.sent.last == "Nimm den Arbeitskalender")
        #expect(harness.assistant.declined.isEmpty)
    }

    @Test func doNotSend_movesTextToDraft() async {
        let harness = VoiceModeHarness()
        await harness.startListening()
        harness.recognizer.send(.text(final: "Leg die Mail", volatile: ""))
        await awaitCondition("the controller heard the text") { harness.controller.machine.text == "Leg die Mail" }
        harness.clock += 1
        harness.controller.tick()
        harness.controller.doNotSend()
        await harness.drain()
        #expect(harness.draft == ["Leg die Mail"])
        #expect(harness.assistant.sent.isEmpty)
        #expect(harness.ended == 1)
        #expect(harness.audio.currentMode == nil)
        #expect(harness.assistant.onTurnFinished == nil)
        #expect(harness.screenOn == [true, false])
    }

    @Test func background_ends() async {
        let harness = VoiceModeHarness()
        await harness.startListening()
        harness.center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        await harness.waitForPhase(.ended)
        await awaitCondition("the recognizer was cancelled") { harness.recognizer.cancels >= 1 }
        #expect(harness.controller.phase == .ended)
        #expect(harness.recognizer.cancels >= 1)
        #expect(harness.audio.currentMode == nil)
        #expect(harness.ended == 1)
    }

    @Test func offline_pauses() async {
        let harness = VoiceModeHarness()
        harness.assistant.replies = [.failed(offline: true)]
        await harness.startListening()
        await harness.sayAndSend("Hallo")
        #expect(harness.controller.phase == .paused(.offline))
        #expect(harness.speaker.spoken.first?.sentences.joined(separator: " ").contains("Keine Verbindung") == true)
        harness.controller.resume()
        await harness.waitForListening(starts: 2)
        #expect(harness.controller.phase == .listening)
    }

    @Test func interrupt_stopsVoiceAndListens() async {
        let harness = VoiceModeHarness()
        harness.assistant.replies = [.answered(id: "message-1", speech: "Eine lange Antwort.", cards: .none)]
        await harness.startListening()
        await harness.sayAndSend("Erzähl")
        harness.controller.interrupt()
        await harness.waitForListening(starts: 2)
        #expect(harness.output.speakingID == nil)
        #expect(harness.tone.plays == 0)
        #expect(harness.controller.phase == .listening)
    }

    @Test func end_whileListening_releasesEverything() async {
        let harness = VoiceModeHarness()
        await harness.startListening()
        harness.controller.end()
        await awaitCondition("the recognizer was cancelled") { harness.recognizer.cancels >= 1 }
        harness.recognizer.send(.text(final: "spät", volatile: ""))
        harness.clock += 10
        harness.controller.tick()
        await harness.drain()
        #expect(harness.assistant.sent.isEmpty)
        #expect(harness.controller.phase == .ended)
        #expect(!harness.controller.isRunning)
    }

    @Test func cardTappedWhileSpeaking_doesNotSkipToTone() async {
        let harness = VoiceModeHarness()
        harness.assistant.replies = [.answered(id: "message-1", speech: "Zwei Änderungen.", cards: OpenCards(ids: ["a", "b"], deletes: 0))]
        await harness.startListening()
        await harness.sayAndSend("Plan meinen Tag")
        harness.assistant.onTurnFinished?(.answered(id: "message-3", speech: "Ausgeführt.", cards: .none))
        #expect(harness.controller.phase == .speaking)
        #expect(harness.tone.plays == 0)
        #expect(harness.output.speakingID == "message-3")
        harness.speaker.emit(.finished)
        #expect(harness.controller.phase == .tone)
    }

    @Test func start_withOpenCards_listens() async {
        let harness = VoiceModeHarness()
        harness.assistant.openCards = OpenCards(ids: ["c1"], deletes: 0)
        await harness.startListening()
        #expect(harness.controller.phase == .listening)
        #expect(harness.controller.machine.openCards.count == 1)
    }

    @Test func end_stopsAnnouncement() async {
        let harness = VoiceModeHarness()
        harness.assistant.replies = [.failed(offline: false)]
        await harness.startListening()
        await harness.sayAndSend("Hallo")
        #expect(harness.output.speakingID != nil)
        harness.controller.end()
        #expect(harness.output.speakingID == nil)
    }

    @Test func audioFailure_pausesWithoutListening() async {
        let harness = VoiceModeHarness()
        harness.audio.failing = true
        harness.controller.start()
        #expect(harness.controller.phase == .paused(.failed))
        await harness.drain()
        #expect(harness.recognizer.started.isEmpty)
    }
}
