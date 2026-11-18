import Foundation
import Testing
@testable import TagwerkCore

struct DictationMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// A machine that is already recording with the given draft.
    private func recordingMachine(draft: String = "", language: VoiceLanguage = .german) -> DictationMachine {
        var machine = DictationMachine(language: language)
        _ = machine.tapMicrophone(draft: draft, explained: true, now: t0)
        machine.recordingStarted(now: t0)
        return machine
    }

    // MARK: Start and explanation

    @Test func initialState_isIdle() {
        let machine = DictationMachine(language: .english)
        #expect(machine.phase == .idle)
        #expect(machine.language == .english)
        #expect(machine.displayText == "")
        #expect(machine.recognizedText == "")
    }

    @Test func constants_matchSpecification() {
        #expect(DictationMachine.maximumDuration == 60)
        #expect(DictationMachine.silenceLimit == 8)
        #expect(DictationMachine.noticeDuration == 4)
    }

    @Test func tap_beforeExplanation_showsExplanation() {
        var machine = DictationMachine(language: .german)
        let effects = machine.tapMicrophone(draft: "Hallo", explained: false, now: t0)
        #expect(machine.phase == .explaining)
        #expect(effects == [.explain])
    }

    @Test func tap_afterExplanation_startsPreparing_andStoresDraft() {
        var machine = DictationMachine(language: .english)
        let effects = machine.tapMicrophone(draft: "Hello", explained: true, now: t0)
        #expect(machine.phase == .preparing)
        #expect(machine.draftBefore == "Hello")
        #expect(effects == [.start(.english)])
    }

    @Test func continueAfterExplanation_marksExplainedAndStarts() {
        var machine = DictationMachine(language: .german)
        _ = machine.tapMicrophone(draft: "x", explained: false, now: t0)
        let effects = machine.continueAfterExplanation(draft: "Hallo", now: t0)
        #expect(machine.phase == .preparing)
        #expect(machine.draftBefore == "Hallo")
        #expect(effects == [.markExplained, .start(.german)])
    }

    @Test func continueAfterExplanation_outsideExplanation_isIgnored() {
        var machine = DictationMachine(language: .german)
        let effects = machine.continueAfterExplanation(draft: "Hallo", now: t0)
        #expect(effects.isEmpty)
        #expect(machine.phase == .idle)
    }

    @Test func dismissExplanation_returnsToIdle() {
        var machine = DictationMachine(language: .german)
        _ = machine.tapMicrophone(draft: "", explained: false, now: t0)
        #expect(machine.dismissExplanation().isEmpty)
        #expect(machine.phase == .idle)
    }

    @Test func recordingStarted_movesPreparingToRecording() {
        var machine = DictationMachine(language: .german)
        _ = machine.tapMicrophone(draft: "", explained: true, now: t0)
        machine.recordingStarted(now: at(1))
        #expect(machine.phase == .recording)
        #expect(machine.elapsed(now: at(4)) == 3)
    }

    @Test func recordingStarted_outsidePreparing_isIgnored() {
        var machine = DictationMachine(language: .german)
        machine.recordingStarted(now: t0)
        #expect(machine.phase == .idle)
    }

    @Test func elapsed_isZeroBeforeRecording() {
        let machine = DictationMachine(language: .german)
        #expect(machine.elapsed(now: at(30)) == 0)
    }

    // MARK: Text

    @Test func displayText_joinsDraftFinalAndVolatileWithSingleSpaces() {
        var machine = recordingMachine(draft: "Hallo ")
        machine.received(final: "Welt", volatile: " wie geht", now: at(1))
        #expect(machine.displayText == "Hallo Welt wie geht")
        #expect(machine.recognizedText == "Welt wie geht")
    }

    @Test func displayText_withoutDraft_hasNoLeadingSpace() {
        var machine = recordingMachine()
        machine.received(final: "", volatile: "Hallo", now: at(1))
        #expect(machine.displayText == "Hallo")
    }

    // MARK: Finish and send

    @Test func finish_thenRecognizerFinished_fillsDraftPlusRecognizedText() {
        var machine = recordingMachine(draft: "Hallo")
        machine.received(final: "Welt", volatile: "", now: at(1))
        #expect(machine.finish() == [.stop])
        #expect(machine.phase == .stopping(.fill))
        let effects = machine.recognizerFinished(now: at(2))
        #expect(effects == [.fill("Hallo Welt")])
        #expect(machine.phase == .idle)
    }

    @Test func finalResultsArrivingWhileStopping_areIncluded() {
        var machine = recordingMachine(draft: "Hallo")
        machine.received(final: "", volatile: "Wel", now: at(1))
        _ = machine.finish()
        machine.received(final: "Welt", volatile: "", now: at(2))
        #expect(machine.recognizerFinished(now: at(2)) == [.fill("Hallo Welt")])
    }

    @Test func tap_whileRecording_behavesLikeFinish() {
        var machine = recordingMachine()
        machine.received(final: "Text", volatile: "", now: at(1))
        let effects = machine.tapMicrophone(draft: "ignored", explained: true, now: at(2))
        #expect(effects == [.stop])
        #expect(machine.phase == .stopping(.fill))
    }

    @Test func finish_whilePreparing_requestsStop() {
        var machine = DictationMachine(language: .german)
        _ = machine.tapMicrophone(draft: "", explained: true, now: t0)
        #expect(machine.finish() == [.stop])
        #expect(machine.phase == .stopping(.fill))
    }

    @Test func finish_whenIdle_doesNothing() {
        var machine = DictationMachine(language: .german)
        #expect(machine.finish().isEmpty)
        #expect(machine.phase == .idle)
    }

    @Test func send_intent_sendsDraftPlusRecognizedText() {
        var machine = recordingMachine(draft: "Bitte")
        machine.received(final: "verschiebe alles", volatile: "", now: at(1))
        #expect(machine.send() == [.stop])
        #expect(machine.phase == .stopping(.send))
        #expect(machine.recognizerFinished(now: at(2)) == [.send("Bitte verschiebe alles")])
        #expect(machine.phase == .idle)
    }

    @Test func send_whenNotRecording_doesNothing() {
        var machine = DictationMachine(language: .german)
        #expect(machine.send().isEmpty)
        #expect(machine.phase == .idle)
    }

    @Test func recognizerFinished_whileRecording_treatedAsFill() {
        var machine = recordingMachine(draft: "A")
        machine.received(final: "B", volatile: "", now: at(1))
        #expect(machine.recognizerFinished(now: at(2)) == [.fill("A B")])
        #expect(machine.phase == .idle)
    }

    @Test func recognizerFinished_whenIdle_doesNothing() {
        var machine = DictationMachine(language: .german)
        #expect(machine.recognizerFinished(now: t0).isEmpty)
        #expect(machine.phase == .idle)
    }

    // MARK: Empty result

    @Test func emptyResult_showsNothingHeard_restoresDraft_thenIdleAfterFourSeconds() {
        var machine = recordingMachine(draft: "Hallo")
        _ = machine.finish()
        let effects = machine.recognizerFinished(now: at(10))
        #expect(effects == [.restoreDraft("Hallo")])
        #expect(machine.phase == .notice(.nothingHeard))

        _ = machine.tick(now: at(13.9))
        #expect(machine.phase == .notice(.nothingHeard))
        _ = machine.tick(now: at(14))
        #expect(machine.phase == .idle)
    }

    @Test func emptyResult_withSendIntent_doesNotSend() {
        var machine = recordingMachine(draft: "Hallo")
        _ = machine.send()
        let effects = machine.recognizerFinished(now: at(5))
        #expect(effects == [.restoreDraft("Hallo")])
        #expect(machine.phase == .notice(.nothingHeard))
    }

    @Test func whitespaceOnlyResult_countsAsEmpty() {
        var machine = recordingMachine()
        machine.received(final: "  ", volatile: " ", now: at(1))
        _ = machine.finish()
        #expect(machine.recognizerFinished(now: at(2)) == [.restoreDraft("")])
        #expect(machine.phase == .notice(.nothingHeard))
    }

    // MARK: Cancel

    @Test func cancel_whileRecording_restoresDraft() {
        var machine = recordingMachine(draft: "Hallo")
        machine.received(final: "Welt", volatile: "", now: at(1))
        let effects = machine.cancel()
        #expect(effects == [.cancel, .restoreDraft("Hallo")])
        #expect(machine.phase == .idle)
    }

    @Test func cancel_whilePreparingAndStopping_restoresDraft() {
        var preparing = DictationMachine(language: .german)
        _ = preparing.tapMicrophone(draft: "A", explained: true, now: t0)
        #expect(preparing.cancel() == [.cancel, .restoreDraft("A")])
        #expect(preparing.phase == .idle)

        var stopping = recordingMachine(draft: "B")
        _ = stopping.finish()
        #expect(stopping.cancel() == [.cancel, .restoreDraft("B")])
        #expect(stopping.phase == .idle)
    }

    @Test func cancel_whenIdle_doesNothing() {
        var machine = DictationMachine(language: .german)
        #expect(machine.cancel().isEmpty)
    }

    @Test func cancel_whileExplaining_justCloses() {
        var machine = DictationMachine(language: .german)
        _ = machine.tapMicrophone(draft: "x", explained: false, now: t0)
        #expect(machine.cancel().isEmpty)
        #expect(machine.phase == .idle)
    }

    // MARK: Timers

    @Test func tick_silenceFor8Seconds_stopsRecording() {
        var machine = recordingMachine()
        machine.received(final: "Hallo", volatile: "", now: at(2))
        #expect(machine.tick(now: at(9.9)).isEmpty)
        #expect(machine.phase == .recording)
        #expect(machine.tick(now: at(10)) == [.stop])
        #expect(machine.phase == .stopping(.fill))
    }

    @Test func tick_textChange_resetsSilenceTimer() {
        var machine = recordingMachine()
        machine.received(final: "", volatile: "Hallo", now: at(5))
        machine.received(final: "", volatile: "Hallo Welt", now: at(10))
        #expect(machine.tick(now: at(15)).isEmpty)
        #expect(machine.phase == .recording)
        #expect(machine.tick(now: at(18)) == [.stop])
    }

    @Test func tick_identicalResult_doesNotResetSilenceTimer() {
        var machine = recordingMachine()
        machine.received(final: "", volatile: "Hallo", now: at(1))
        machine.received(final: "", volatile: "Hallo", now: at(7))
        #expect(machine.tick(now: at(9)) == [.stop])
    }

    @Test func tick_withoutAnyText_stopsAfterEightSecondsFromStart() {
        var machine = recordingMachine()
        #expect(machine.tick(now: at(7.9)).isEmpty)
        #expect(machine.tick(now: at(8)) == [.stop])
    }

    @Test func tick_maximumDuration_stopsEvenWhileTextKeepsChanging() {
        var machine = recordingMachine()
        for second in stride(from: 1, through: 59, by: 1) {
            machine.received(final: "", volatile: "Wort \(second)", now: at(Double(second)))
            #expect(machine.tick(now: at(Double(second))).isEmpty)
        }
        machine.received(final: "", volatile: "Wort 60", now: at(60))
        #expect(machine.tick(now: at(60)) == [.stop])
        #expect(machine.phase == .stopping(.fill))
    }

    @Test func tick_whileIdleOrPreparing_doesNothing() {
        var machine = DictationMachine(language: .german)
        #expect(machine.tick(now: at(100)).isEmpty)
        _ = machine.tapMicrophone(draft: "", explained: true, now: t0)
        #expect(machine.tick(now: at(100)).isEmpty)
        #expect(machine.phase == .preparing)
    }

    @Test func tick_whileStopping_doesNotStopAgain() {
        var machine = recordingMachine()
        _ = machine.finish()
        #expect(machine.tick(now: at(100)).isEmpty)
        #expect(machine.phase == .stopping(.fill))
    }

    // MARK: Failures

    @Test func failure_withRecognizedText_fillsTextAndShowsNotice() {
        var machine = recordingMachine(draft: "Hallo")
        machine.received(final: "Welt", volatile: "", now: at(1))
        let effects = machine.recognizerFailed(.interrupted, now: at(2))
        #expect(effects == [.fill("Hallo Welt")])
        #expect(machine.phase == .notice(.interrupted))
        _ = machine.tick(now: at(6))
        #expect(machine.phase == .idle)
    }

    @Test func failure_withoutText_showsNoticeOnly() {
        var machine = recordingMachine(draft: "Hallo")
        let effects = machine.recognizerFailed(.failed, now: at(2))
        #expect(effects.isEmpty)
        #expect(machine.phase == .notice(.failed))
    }

    @Test func failure_beforeRecording_showsNotice() {
        var machine = DictationMachine(language: .german)
        _ = machine.tapMicrophone(draft: "", explained: true, now: t0)
        #expect(machine.recognizerFailed(.permissionDenied, now: at(1)).isEmpty)
        #expect(machine.phase == .notice(.permissionDenied))
    }

    @Test func tap_duringNotice_startsNewDictation() {
        var machine = recordingMachine()
        _ = machine.recognizerFailed(.assetUnavailable, now: at(1))
        let effects = machine.tapMicrophone(draft: "Neu", explained: true, now: at(2))
        #expect(effects == [.start(.german)])
        #expect(machine.phase == .preparing)
        #expect(machine.draftBefore == "Neu")
        #expect(machine.displayText == "Neu")
    }

    // MARK: Language

    @Test func switchLanguage_keepsTextAndRestarts() {
        var machine = recordingMachine(draft: "Hallo")
        machine.received(final: "Welt", volatile: "wie", now: at(1))
        let effects = machine.switchLanguage(now: at(2))
        #expect(effects == [.restart(.english)])
        #expect(machine.language == .english)
        #expect(machine.phase == .preparing)
        #expect(machine.draftBefore == "Hallo Welt wie")
        #expect(machine.displayText == "Hallo Welt wie")
        #expect(machine.recognizedText == "")

        machine.recordingStarted(now: at(3))
        machine.received(final: "Next", volatile: "", now: at(4))
        _ = machine.finish()
        #expect(machine.recognizerFinished(now: at(5)) == [.fill("Hallo Welt wie Next")])
    }

    @Test func cancelAfterSwitch_restoresTheOriginalDraft() {
        var machine = recordingMachine(draft: "Hallo")
        machine.received(final: "Welt", volatile: "", now: at(1))
        _ = machine.switchLanguage(now: at(2))
        machine.recordingStarted(now: at(3))
        #expect(machine.cancel() == [.cancel, .restoreDraft("Hallo")])
    }

    @Test func switchLanguage_togglesBackToGerman() {
        var machine = recordingMachine(language: .english)
        #expect(machine.switchLanguage(now: at(1)) == [.restart(.german)])
        #expect(machine.language == .german)
    }

    @Test func switchLanguage_whenNotRecording_doesNothing() {
        var machine = DictationMachine(language: .german)
        #expect(machine.switchLanguage(now: t0).isEmpty)
        #expect(machine.language == .german)
    }

    @Test func switchLanguage_withNothingRecognized_cancelAfterwardsRestoresOriginalDraft() {
        var machine = recordingMachine(draft: "Hallo")
        _ = machine.switchLanguage(now: at(1))
        #expect(machine.cancel() == [.cancel, .restoreDraft("Hallo")])
    }

    @Test func setLanguage_onlyWhenIdle() {
        var machine = DictationMachine(language: .german)
        machine.setLanguage(.english)
        #expect(machine.language == .english)

        _ = machine.tapMicrophone(draft: "", explained: true, now: t0)
        machine.setLanguage(.german)
        #expect(machine.language == .english)
        machine.recordingStarted(now: t0)
        machine.setLanguage(.german)
        #expect(machine.language == .english)
    }

    @Test func start_usesCurrentLanguage() {
        var machine = DictationMachine(language: .german)
        machine.setLanguage(.english)
        #expect(machine.tapMicrophone(draft: "", explained: true, now: t0) == [.start(.english)])
    }
}
