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

    /// Lets the listening task pick up queued events.
    func settle() async { for _ in 0..<20 { await Task.yield() } }
}

@MainActor
struct VoiceInputModelTests {
    @Test func firstTap_explainsBeforeRecording_continueStarts() async {
        let harness = VoiceInputModelHarness(explained: false)
        harness.model.tapMicrophone()
        #expect(harness.model.phase == .explaining)
        #expect(harness.recognizer.started.isEmpty)
        harness.model.continueAfterExplanation()
        await harness.settle()
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
        await harness.settle()
        harness.recognizer.send(.text(final: "", volatile: "leg die Mail"))
        await harness.settle()
        #expect(harness.model.displayText == "Bitte leg die Mail")
        harness.recognizer.finalOnStop = "leg die Mail auf 16 Uhr."
        harness.model.finish()
        await harness.settle()
        #expect(harness.draft == "Bitte leg die Mail auf 16 Uhr.")
        #expect(harness.model.draftIsSpoken)
        #expect(harness.sent.isEmpty)
        #expect(harness.model.phase == .idle)
    }

    @Test func send_waitsForFinalTextThenSends() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.settle()
        harness.recognizer.send(.text(final: "", volatile: "Was steht"))
        await harness.settle()
        harness.recognizer.finalOnStop = "Was steht heute an?"
        harness.model.send()
        await harness.settle()
        #expect(harness.sent == ["Was steht heute an?"])
        #expect(harness.draft == "")
    }

    @Test func cancel_restoresDraft() async {
        let harness = VoiceInputModelHarness()
        harness.draft = "Vorher"
        harness.model.tapMicrophone()
        await harness.settle()
        harness.recognizer.send(.text(final: "weg damit", volatile: ""))
        await harness.settle()
        harness.model.cancel()
        await harness.settle()
        #expect(harness.draft == "Vorher")
        #expect(harness.recognizer.cancels == 1)
        #expect(harness.model.phase == .idle)
    }

    @Test func silence_finishesAfterEightSeconds() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.settle()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.settle()
        harness.clock += 9
        harness.model.tick()
        await harness.settle()
        #expect(harness.recognizer.stops == 1)
        #expect(harness.draft == "Hallo")
    }

    @Test func emptyRecording_showsNothingHeard_thenClears() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.settle()
        harness.model.finish()
        await harness.settle()
        #expect(harness.model.phase == .notice(.nothingHeard))
        harness.clock += 5
        harness.model.tick()
        #expect(harness.model.phase == .idle)
    }

    @Test func interruption_keepsTextAndShowsNotice() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.settle()
        harness.recognizer.send(.text(final: "Bis hierhin", volatile: ""))
        harness.recognizer.send(.failed(.interrupted))
        await harness.settle()
        #expect(harness.draft == "Bis hierhin")
        #expect(harness.model.phase == .notice(.interrupted))
    }

    @Test func microphoneDenied_showsPermissionNotice() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.settle()
        harness.recognizer.send(.failed(.microphoneDenied))
        await harness.settle()
        #expect(harness.model.phase == .notice(.permissionDenied))
    }

    @Test func languageSwitch_restartsInEnglishKeepingText() async {
        let harness = VoiceInputModelHarness()
        harness.model.tapMicrophone()
        await harness.settle()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.settle()
        harness.model.switchLanguage()
        await harness.settle()
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
        await harness.settle()
        harness.model.switchLanguage()
        await harness.settle()
        harness.model.switchLanguage()
        await harness.settle()
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
        await harness.settle()
        harness.recognizer.finalOnStop = "Hallo"
        harness.model.finish()
        await harness.settle()
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
        await harness.settle()
        harness.recognizer.send(.text(final: "Hallo", volatile: ""))
        await harness.settle()
        harness.recognizer.ignoresStop = true
        harness.model.finish()
        await harness.settle()
        #expect(harness.model.isRecording)
        harness.clock += 4
        harness.model.tick()
        await harness.settle()
        #expect(harness.model.phase == .idle)
        #expect(harness.draft == "Hallo")
    }
}
