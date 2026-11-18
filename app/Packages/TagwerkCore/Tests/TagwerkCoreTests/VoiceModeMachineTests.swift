import Foundation
import Testing
@testable import TagwerkCore

struct VoiceModeMachineTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private let card = OpenCards(ids: ["c1"], deletes: 0)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    /// A machine that is listening, started at t0.
    private func listening(sendDelay: TimeInterval = 2, silenceLimit: TimeInterval = 30) -> VoiceModeMachine {
        var machine = VoiceModeMachine(language: .german, sendDelay: sendDelay, silenceLimit: silenceLimit)
        _ = machine.start(now: t0)
        machine.recordingStarted(now: t0)
        return machine
    }

    /// A machine that has sent "Wie ist mein Tag?" and waits for the answer.
    private func sending() -> VoiceModeMachine {
        var machine = listening()
        machine.heard(final: "Wie ist mein Tag?", volatile: "", now: at(1))
        _ = machine.tick(now: at(3))
        _ = machine.recognizerFinished(text: "Wie ist mein Tag?", now: at(3.2))
        return machine
    }

    // MARK: Start and listening

    @Test func start_beginsListeningInLanguage() {
        var machine = VoiceModeMachine(language: .english, sendDelay: 2, silenceLimit: 30)
        let effects = machine.start(now: t0)
        #expect(machine.phase == .starting)
        #expect(effects == [.startListening(.english)])
        machine.recordingStarted(now: t0)
        #expect(machine.phase == .listening)
    }

    @Test func recordingStarted_ignoredOutsideStarting() {
        var machine = VoiceModeMachine(language: .german, sendDelay: 2, silenceLimit: 30)
        machine.recordingStarted(now: t0)
        #expect(machine.phase == .idle)
    }

    @Test func heard_updatesText() {
        var machine = listening()
        machine.heard(final: "Leg die Mail", volatile: "auf sechzehn", now: at(1))
        #expect(machine.text == "Leg die Mail auf sechzehn")
    }

    // MARK: Countdown

    @Test func pauseAfterText_startsCountdown_thenFinalizes() {
        var machine = listening()
        machine.heard(final: "Leg die Mail auf sechzehn Uhr", volatile: "", now: at(1))
        #expect(machine.tick(now: at(1.3)).isEmpty)
        #expect(machine.phase == .listening)
        #expect(machine.tick(now: at(1.7)).isEmpty)
        #expect(machine.phase == .countdown(deadline: at(3)))
        #expect(machine.remaining(now: at(2)) == 1)
        let effects = machine.tick(now: at(3))
        #expect(machine.phase == .finalizing)
        #expect(effects == [.stopListening])
    }

    @Test func sendDelay_isConfigurable() {
        var machine = listening(sendDelay: 3)
        machine.heard(final: "Hallo", volatile: "", now: at(1))
        _ = machine.tick(now: at(2))
        #expect(machine.phase == .countdown(deadline: at(4)))
        #expect(machine.tick(now: at(3.9)).isEmpty)
        #expect(machine.tick(now: at(4)) == [.stopListening])
    }

    @Test func newSpeechDuringCountdown_returnsToListening() {
        var machine = listening()
        machine.heard(final: "Leg die Mail", volatile: "", now: at(1))
        _ = machine.tick(now: at(2))
        #expect(machine.phase == .countdown(deadline: at(3)))
        machine.heard(final: "Leg die Mail", volatile: "auf sechzehn", now: at(2.5))
        #expect(machine.phase == .listening)
        #expect(machine.tick(now: at(3)).isEmpty)
        #expect(machine.phase == .listening)
    }

    @Test func noText_neverCountsDown() {
        var machine = listening()
        machine.heard(final: "", volatile: "  ", now: at(1))
        _ = machine.tick(now: at(5))
        #expect(machine.phase == .listening)
    }

    // MARK: Sending

    @Test func finalText_isSent_notTheDisplayedOne() {
        var machine = listening()
        machine.heard(final: "", volatile: "Leg die Mail auf 16", now: at(1))
        _ = machine.tick(now: at(3))
        let effects = machine.recognizerFinished(text: "Leg die Mail auf 16 Uhr.", now: at(3.3))
        #expect(machine.phase == .sending)
        #expect(effects == [.send("Leg die Mail auf 16 Uhr.")])
    }

    @Test func emptyFinalText_listensAgain() {
        var machine = listening()
        machine.heard(final: "", volatile: "äh", now: at(1))
        _ = machine.tick(now: at(3))
        let effects = machine.recognizerFinished(text: "  ", now: at(3.3))
        #expect(machine.phase == .starting)
        #expect(effects == [.startListening(.german)])
        #expect(machine.text == "")
    }

    @Test func sendingTimesOut() {
        var machine = sending()
        #expect(machine.tick(now: at(3.2 + VoiceModeMachine.sendTimeout - 1)).isEmpty)
        let effects = machine.tick(now: at(3.2 + VoiceModeMachine.sendTimeout))
        #expect(machine.phase == .paused(.failed))
        #expect(effects == [.announce(.failed)])
    }

    // MARK: Answer

    @Test func answer_isSpoken_thenToneThenListening() {
        var machine = sending()
        #expect(machine.turnFinished(.answered(speech: "Drei Termine.", cards: .none), now: at(5)) == [.speak("Drei Termine.")])
        #expect(machine.phase == .speaking)
        #expect(machine.speakingFinished(now: at(7)) == [.playTone])
        #expect(machine.phase == .tone)
        #expect(machine.toneFinished(now: at(7.4)) == [.startListening(.german)])
        #expect(machine.phase == .starting)
    }

    @Test func emptyAnswer_goesStraightToTone() {
        var machine = sending()
        #expect(machine.turnFinished(.answered(speech: "", cards: .none), now: at(5)) == [.playTone])
    }

    @Test func toneTimesOut() {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "", cards: .none), now: at(5))
        #expect(machine.tick(now: at(5 + VoiceModeMachine.toneTimeout)) == [.startListening(.german)])
    }

    @Test func shortSendDelay_keepsCountdownVisible() {
        var machine = listening(sendDelay: 1)
        machine.heard(final: "Hallo", volatile: "", now: at(1))
        _ = machine.tick(now: at(1.7))
        #expect(machine.phase == .countdown(deadline: at(2.6)))
        #expect(machine.tick(now: at(2.5)).isEmpty)
    }

    @Test func endWhilePaused_stopsAnnouncement() {
        var machine = sending()
        _ = machine.turnFinished(.failed(offline: true), now: at(5))
        #expect(machine.end() == [.stopSpeaking, .endSession])
    }

    @Test func offline_pausesAndAnnounces() {
        var machine = sending()
        #expect(machine.turnFinished(.failed(offline: true), now: at(5)) == [.announce(.offline)])
        #expect(machine.phase == .paused(.offline))
    }

    @Test func failure_pausesAndAnnounces() {
        var machine = sending()
        #expect(machine.turnFinished(.failed(offline: false), now: at(5)) == [.announce(.failed)])
        #expect(machine.phase == .paused(.failed))
    }

    @Test func rejected_pauses() {
        var machine = sending()
        _ = machine.turnFinished(.rejected, now: at(5))
        #expect(machine.phase == .paused(.failed))
    }

    // MARK: User controls

    @Test func userInterrupt_stopsVoice_andListensWithoutTone() {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "Lange Antwort.", cards: .none), now: at(5))
        #expect(machine.userInterrupt(now: at(6)) == [.stopSpeaking, .startListening(.german)])
        #expect(machine.phase == .starting)
    }

    @Test func doNotSend_movesTextToDraftAndEnds() {
        var machine = listening()
        machine.heard(final: "Leg die Mail", volatile: "auf 16", now: at(1))
        _ = machine.tick(now: at(2))
        let effects = machine.doNotSend()
        #expect(effects == [.cancelListening, .moveToDraft("Leg die Mail auf 16"), .endSession])
        #expect(machine.phase == .ended)
    }

    @Test func pause_keepsTextInDraft_resumeListens() {
        var machine = listening()
        machine.heard(final: "Halb", volatile: "", now: at(1))
        #expect(machine.pause() == [.cancelListening, .moveToDraft("Halb")])
        #expect(machine.phase == .paused(.user))
        #expect(machine.resume(now: at(5)) == [.stopSpeaking, .startListening(.german)])
        #expect(machine.phase == .starting)
        #expect(machine.text == "")
    }

    @Test func typeInstead_whileSpeaking_stopsAndEnds() {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "Antwort.", cards: .none), now: at(5))
        #expect(machine.typeInstead() == [.stopSpeaking, .endSession])
        #expect(machine.phase == .ended)
    }

    // MARK: Silence, failures, interruptions

    @Test func silence_pauses() {
        var machine = listening(silenceLimit: 15)
        #expect(machine.tick(now: at(14.9)).isEmpty)
        #expect(machine.tick(now: at(15)) == [.cancelListening])
        #expect(machine.phase == .paused(.silence))
    }

    @Test func silence_countsFromListeningAfterAnswer() {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "", cards: .none), now: at(50))
        _ = machine.toneFinished(now: at(51))
        machine.recordingStarted(now: at(52))
        #expect(machine.tick(now: at(70)).isEmpty)
        #expect(machine.phase == .listening)
    }

    @Test func recognizerFailed_keepsTextAndPauses() {
        var machine = listening()
        machine.heard(final: "Halb", volatile: "", now: at(1))
        #expect(machine.recognizerFailed() == [.moveToDraft("Halb"), .announce(.failed)])
        #expect(machine.phase == .paused(.failed))
    }

    @Test func recognizerEndingUnasked_keepsTextAndPauses() {
        var machine = listening()
        machine.heard(final: "Halb", volatile: "", now: at(1))
        #expect(machine.recognizerFinished(text: "Halb", now: at(2)) == [.moveToDraft("Halb"), .announce(.failed)])
        #expect(machine.phase == .paused(.failed))
    }

    @Test func routeChange_restartsListening() {
        var machine = listening()
        machine.heard(final: "Halb", volatile: "", now: at(1))
        #expect(machine.routeChanged(now: at(2)) == [.cancelListening, .moveToDraft("Halb"), .startListening(.german)])
        #expect(machine.phase == .starting)
        #expect(machine.text == "")
        #expect(machine.tick(now: at(2 + VoiceModeMachine.startTimeout)) == [.cancelListening, .announce(.failed)])
    }

    @Test(arguments: [0, 1, 2])
    func systemInterruption_ends(_ stage: Int) {
        var machine = listening()
        var expected: [VoiceModeMachine.Effect] = [.cancelListening, .endSession]
        if stage >= 1 {
            machine = sending()
            expected = [.endSession]
        }
        if stage == 2 {
            _ = machine.turnFinished(.answered(speech: "Antwort.", cards: .none), now: at(5))
            expected = [.stopSpeaking, .endSession]
        }
        #expect(machine.systemInterruption() == expected)
        #expect(machine.phase == .ended)
    }

    @Test func noSendFromPausedOrEnded() {
        var machine = listening()
        machine.heard(final: "Hallo", volatile: "", now: at(1))
        _ = machine.pause()
        #expect(machine.tick(now: at(10)).isEmpty)
        #expect(machine.recognizerFinished(text: "Hallo", now: at(10)).isEmpty)
        _ = machine.end()
        #expect(machine.recognizerFinished(text: "Hallo", now: at(11)).isEmpty)
        #expect(machine.resume(now: at(12)).isEmpty)
        #expect(machine.phase == .ended)
    }

    @Test func end_fromSpeaking_stopsVoice() {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "Antwort.", cards: .none), now: at(5))
        #expect(machine.end() == [.stopSpeaking, .endSession])
        #expect(machine.end().isEmpty)
    }

    @Test func startingTimesOut() {
        var machine = VoiceModeMachine(language: .german, sendDelay: 2, silenceLimit: 30)
        _ = machine.start(now: t0)
        #expect(machine.tick(now: at(VoiceModeMachine.startTimeout)) == [.cancelListening, .announce(.failed)])
        #expect(machine.phase == .paused(.failed))
    }

    // MARK: Spoken replies to cards (issue #120)

    /// Listening again after an answer that left `cards` open.
    private func listeningWithCards(_ cards: OpenCards) -> VoiceModeMachine {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "Vorschlag.", cards: cards), now: at(5))
        _ = machine.speakingFinished(now: at(6))
        _ = machine.toneFinished(now: at(6.3))
        machine.recordingStarted(now: at(7))
        return machine
    }

    /// Says `text` and lets the countdown run out, as the controller would.
    private func reply(_ machine: inout VoiceModeMachine, _ text: String, at seconds: TimeInterval) -> [VoiceModeMachine.Effect] {
        machine.heard(final: text, volatile: "", now: at(seconds))
        _ = machine.tick(now: at(seconds + 3))
        return machine.recognizerFinished(text: text, now: at(seconds + 3.2))
    }

    @Test func openCard_keepsListeningAfterTheAnswer() {
        let machine = listeningWithCards(card)
        #expect(machine.phase == .listening)
        #expect(machine.openCards == card)
    }

    @Test func ja_confirmsAfterCountdown() {
        var machine = listeningWithCards(card)
        #expect(reply(&machine, "Ja.", at: 8) == [.startListening(.german)])
        #expect(machine.tick(now: at(15)).isEmpty)
        machine.recordingStarted(now: at(15.5))
        #expect(machine.phase == .confirming(deadline: at(17.5)))
        #expect(machine.tick(now: at(17.4)).isEmpty)
        #expect(machine.tick(now: at(17.5)) == [.cancelListening, .confirm(ids: ["c1"])])
        #expect(machine.phase == .sending)
        #expect(machine.turnFinished(.answered(speech: "Ausgeführt.", cards: .none), now: at(14)) == [.speak("Ausgeführt.")])
    }

    @Test func speechDuringCountdown_stopsIt_andNeinThenOnlyCancels() {
        var machine = listeningWithCards(card)
        _ = reply(&machine, "Ja", at: 8)
        machine.heard(final: "", volatile: "Nein", now: at(12))
        #expect(machine.phase == .listening)
        _ = machine.tick(now: at(15))
        #expect(machine.recognizerFinished(text: "Nein.", now: at(15.2)) == [.prompt(.cancelled)])
        #expect(machine.openCards == card)
    }

    @Test func correctionDuringCountdown_isSent() {
        var machine = listeningWithCards(card)
        _ = reply(&machine, "Ja", at: 8)
        machine.heard(final: "Nimm den Arbeitskalender", volatile: "", now: at(12))
        _ = machine.tick(now: at(15))
        #expect(machine.recognizerFinished(text: "Nimm den Arbeitskalender.", now: at(15.2)) == [.send("Nimm den Arbeitskalender.")])
    }

    @Test func cancelButton_keepsCardsAndListens() {
        var machine = listeningWithCards(card)
        _ = reply(&machine, "Ja", at: 8)
        #expect(machine.cancelConfirmation(now: at(12)).isEmpty)
        #expect(machine.phase == .listening)
        #expect(machine.tick(now: at(20)).isEmpty)
    }

    @Test func nein_declines() {
        var machine = listeningWithCards(card)
        #expect(reply(&machine, "Nein", at: 8) == [.decline(ids: ["c1"])])
        #expect(machine.phase == .sending)
    }

    @Test func stopp_isNeverSent() {
        var machine = listeningWithCards(card)
        #expect(reply(&machine, "Stopp!", at: 8) == [.startListening(.german)])
        var plain = listening()
        #expect(reply(&plain, "Stopp", at: 1) == [.send("Stopp")])
    }

    @Test func correction_isSentAsMessage() {
        var machine = listeningWithCards(card)
        #expect(reply(&machine, "Ja, aber um 11", at: 8) == [.send("Ja, aber um 11")])
    }

    @Test func withoutCards_jaIsAMessage() {
        var machine = listening()
        #expect(reply(&machine, "Ja", at: 1) == [.send("Ja")])
    }

    @Test func deletion_needsJaLoeschen() {
        let deletion = OpenCards(ids: ["d1"], deletes: 1)
        var machine = listeningWithCards(deletion)
        #expect(reply(&machine, "Ja", at: 8) == [.prompt(.sayDelete)])
        #expect(machine.phase == .speaking)
        _ = machine.speakingFinished(now: at(13))
        _ = machine.toneFinished(now: at(13.3))
        machine.recordingStarted(now: at(14))
        #expect(reply(&machine, "Ja, löschen.", at: 15) == [.startListening(.german)])
        machine.recordingStarted(now: at(18.5))
        #expect(machine.tick(now: at(20.5)) == [.cancelListening, .confirm(ids: ["d1"])])
    }

    @Test func severalCards_needAllConfirm() {
        let cards = OpenCards(ids: ["a", "b"], deletes: 0)
        var machine = listeningWithCards(cards)
        #expect(reply(&machine, "Ja", at: 8) == [.prompt(.severalCards(2))])
        _ = machine.speakingFinished(now: at(13))
        _ = machine.toneFinished(now: at(13.3))
        machine.recordingStarted(now: at(14))
        #expect(reply(&machine, "Alle bestätigen", at: 15) == [.startListening(.german)])
        machine.recordingStarted(now: at(18.5))
        #expect(machine.tick(now: at(20.5)) == [.cancelListening, .confirm(ids: ["a", "b"])])
    }

    @Test func confirmAll_withDeletion_needsTaps() {
        var machine = listeningWithCards(OpenCards(ids: ["a", "d"], deletes: 1))
        #expect(reply(&machine, "Alle bestätigen", at: 8) == [.prompt(.deletesNeedTap)])
    }

    @Test func tapWhileListening_takesTheAnswer() {
        var machine = listeningWithCards(card)
        machine.heard(final: "Äh", volatile: "", now: at(8))
        let effects = machine.turnFinished(.answered(speech: "Ausgeführt.", cards: .none), now: at(9))
        #expect(effects == [.cancelListening, .speak("Ausgeführt.")])
        #expect(machine.openCards.isEmpty)
    }

    @Test func tapWhileSpeaking_replacesTheAnswer() {
        var machine = sending()
        _ = machine.turnFinished(.answered(speech: "Zwei Änderungen.", cards: card), now: at(5))
        let effects = machine.turnFinished(.answered(speech: "Ausgeführt.", cards: .none), now: at(6))
        #expect(effects == [.stopSpeaking, .speak("Ausgeführt.")])
    }

    @Test func confirmation_withoutMicrophone_runsNothing() {
        var machine = listeningWithCards(card)
        _ = reply(&machine, "Ja", at: 8)
        #expect(machine.tick(now: at(11.2 + VoiceModeMachine.startTimeout)) == [.cancelListening, .announce(.failed)])
        #expect(machine.phase == .paused(.failed))
    }

    @Test func cancelledFlag_endsWithTheUtterance() {
        var machine = listeningWithCards(card)
        _ = reply(&machine, "Ja", at: 8)
        machine.heard(final: "", volatile: "hm", now: at(12))
        _ = machine.tick(now: at(15))
        #expect(machine.recognizerFinished(text: "", now: at(15.2)) == [.startListening(.german)])
        machine.recordingStarted(now: at(16))
        #expect(reply(&machine, "Nein", at: 17) == [.decline(ids: ["c1"])])
    }

    @Test func start_withOpenCards_listens() {
        var machine = VoiceModeMachine(language: .german, sendDelay: 2, silenceLimit: 30)
        #expect(machine.start(now: t0, cards: card) == [.startListening(.german)])
        #expect(machine.openCards == card)
    }
}
