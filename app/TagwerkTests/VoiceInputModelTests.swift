import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

@MainActor
final class VoiceInputModelHarness {
    let recognizer = FakeSpeechRecognizer()
    var draft = ""
    var sent: [String] = []
    var explained: Bool
    var clock = Date(timeIntervalSince1970: 1_800_000_000)
    var speechStops = 0
    lazy var model: VoiceInputModel = {
        let model = VoiceInputModel(language: .german, makeRecognizer: { self.recognizer }, isExplained: { self.explained },
                                    markExplained: { self.explained = true }, now: { self.clock },
                                    sleep: { _ in try? await Task.sleep(for: .seconds(3600)) })
        model.readDraft = { self.draft }
        model.writeDraft = { self.draft = $0 }
        model.onSend = { self.sent.append($0) }
        model.onRecordingStarts = { self.speechStops += 1 }
        return model
    }()

    init(explained: Bool = true) { self.explained = explained }

    /// Waits until the recognizer runs and the model reports the recording state.
    func waitForRecording(sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("recording phase", sourceLocation: sourceLocation) { model.phase == .recording }
    }

    func waitForPhase(_ phase: DictationMachine.Phase, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("phase \(phase)", sourceLocation: sourceLocation) { model.phase == phase }
    }

    func waitForDisplayText(_ text: String, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("display text \"\(text)\"", sourceLocation: sourceLocation) { model.displayText == text }
    }

    /// Waits until the recognizer was started `count` times in total.
    func waitForStarts(_ count: Int, sourceLocation: SourceLocation = #_sourceLocation) async {
        await awaitCondition("\(count) recognizer start(s)", sourceLocation: sourceLocation) { recognizer.started.count == count }
    }
}

@MainActor
struct VoiceInputModelTests {
    @Test func firstTap_explainsBeforeRecording_continueStarts() async {
        let harness = VoiceInputModelHarness(explained: false)
        harness.model.tapMicrophone()
        #expect(harness.model.phase == .explaining)
        #expect(harness.recognizer.started.isEmpty)
        harness.model.continueAfterExplanation()
        await harness.waitForRecording()
        #expect(harness.explained)
        #expect(harness.recognizer.started == [.german])
        #expect(harness.model.phase == .recording)
        #expect(harness.speechStops == 1)
    }

    @Test func notNow_staysIdle() {
        let harness = VoiceInputModelHarness(explained: false)
        harness.model.tapMicrophone()
        harness.model.dismissExplanation()
        #expect(harness.model.phase == .idle)
        #expect(!harness.explained)
    }

    @Test func finish_appendsRecognizedTextToDraft_andMarksSpoken() async {
        let harness = VoiceInputModelHarness()
        harness.draft = "Bitte"
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "", volatile: "leg die Mail"))
        await harness.waitForDisplayText("Bitte leg die Mail")
        #expect(harness.model.displayText == "Bitte leg die Mail")
        harness.recognizer.finalOnStop = "leg die Mail auf 16 Uhr."
        harness.model.finish()
        await harness.waitForPhase(.idle)
        #expect(harness.draft == "Bitte leg die Mail auf 16 Uhr.")
        #expect(harness.model.draftIsSpoken)
        #expect(harness.sent.isEmpty)
        #expect(harness.model.phase == .idle)
    }

    @Test func send_waitsForFinalTextThenSends() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "", volatile: "Was steht"))
        await harness.waitForDisplayText("Was steht")
        harness.recognizer.finalOnStop = "Was steht heute an?"
        harness.model.send()
        await awaitCondition("the message was sent") { !harness.sent.isEmpty }
        #expect(harness.sent == ["Was steht heute an?"])
        #expect(harness.draft == "")
    }

    @Test func cancel_restoresDraft() async {
        let harness = VoiceInputModelHarness()
        harness.draft = "Vorher"
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "weg damit", volatile: ""))
        await harness.waitForDisplayText("Vorher weg damit")
        harness.model.cancel()
        await awaitCondition("the recognizer was cancelled") { harness.recognizer.cancels == 1 }
        #expect(harness.draft == "Vorher")
        #expect(harness.recognizer.cancels == 1)
        #expect(harness.model.phase == .idle)
    }

    @Test func silence_finishesAfterEightSeconds() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.waitForDisplayText("Hallo")
        harness.clock += 9
        harness.model.tick()
        await awaitCondition("the recognizer was stopped and the text was filled in") {
            harness.recognizer.stops == 1 && harness.draft == "Hallo"
        }
        #expect(harness.recognizer.stops == 1)
        #expect(harness.draft == "Hallo")
    }

    @Test func emptyRecording_showsNothingHeard_thenClears() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.model.finish()
        await harness.waitForPhase(.notice(.nothingHeard))
        #expect(harness.model.phase == .notice(.nothingHeard))
        harness.clock += 5
        harness.model.tick()
        #expect(harness.model.phase == .idle)
    }

    @Test func interruption_keepsTextAndShowsNotice() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "Bis hierhin", volatile: ""))
        harness.recognizer.send(.failed(.interrupted))
        await harness.waitForPhase(.notice(.interrupted))
        #expect(harness.draft == "Bis hierhin")
        #expect(harness.model.phase == .notice(.interrupted))
    }

    @Test func microphoneDenied_showsPermissionNotice() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.failed(.microphoneDenied))
        await harness.waitForPhase(.notice(.permissionDenied))
        #expect(harness.model.phase == .notice(.permissionDenied))
    }

    @Test func languageSwitch_restartsInEnglishKeepingText() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.waitForDisplayText("Hallo")
        harness.model.switchLanguage()
        await harness.waitForStarts(2)
        #expect(harness.recognizer.started == [.german, .english])
        #expect(harness.model.displayText == "Hallo")
        #expect(harness.model.language == .english)
    }

    // MARK: Language switch per place (L3)

    @Test func switchLanguage_notifiesWithTheNewLanguage() async {
        let harness = VoiceInputModelHarness()
        var notified: [VoiceLanguage] = []
        harness.model.onLanguageSwitched = { notified.append($0) }
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.model.switchLanguage()
        await harness.waitForStarts(2)
        // A switch is only accepted while recording, so wait for the restarted recognizer to report that it runs.
        await harness.waitForRecording()
        harness.model.switchLanguage()
        await harness.waitForStarts(3)
        #expect(notified == [.english, .german])
    }

    @Test func switchLanguage_whileIdle_doesNotNotify() {
        let harness = VoiceInputModelHarness()
        var notified: [VoiceLanguage] = []
        harness.model.onLanguageSwitched = { notified.append($0) }
        harness.model.switchLanguage()
        #expect(notified.isEmpty)
        #expect(harness.model.language == .german)
    }

    @Test func place_defaultsToNotes_andIsKept() {
        let harness = VoiceInputModelHarness()
        #expect(harness.model.place == .notes)
        let model = VoiceInputModel(language: .german, place: .meal, makeRecognizer: { harness.recognizer }, isExplained: { true },
                                    markExplained: {})
        #expect(model.place == .meal)
    }

    @Test func draftConsumed_clearsSpokenFlag() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.finalOnStop = "Hallo"
        harness.model.finish()
        await awaitCondition("the spoken text was filled in") { harness.model.draftIsSpoken }
        #expect(harness.model.draftIsSpoken)
        harness.model.draftConsumed()
        #expect(!harness.model.draftIsSpoken)
    }
}

@MainActor
struct VoiceInputModelStopTests {
    @Test func stuckStop_givesUpAfterThreeSeconds() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.waitForRecording()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.waitForDisplayText("Hallo")
        harness.recognizer.ignoresStop = true
        harness.model.finish()
        await awaitCondition("the recognizer received the stop") { harness.recognizer.stops == 1 }
        #expect(harness.model.isRecording)
        harness.clock += 4
        harness.model.tick()
        await harness.waitForPhase(.idle)
        #expect(harness.model.phase == .idle)
        #expect(harness.draft == "Hallo")
    }
}
