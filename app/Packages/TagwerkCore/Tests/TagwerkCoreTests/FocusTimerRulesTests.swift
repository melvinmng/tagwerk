import Foundation
import Testing
@testable import TagwerkCore

struct FocusTimerRulesTests {
    let start = instant(2026, 11, 19, 10, 0)

    private func at(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

    private func state(pomodoro: Bool = true, rounds: Int = 4, pauses: [DateInterval] = [], pausedSince: Date? = nil,
                       skips: [Date] = [], endedAt: Date? = nil) -> FocusTimerState {
        FocusTimerState(start: start, settings: FocusTimerSettings(rounds: rounds, isPomodoro: pomodoro), pauses: pauses,
                        pausedSince: pausedSince, skips: skips, endedAt: endedAt)
    }

    @Test func single_endsAfterWorkMinutes() {
        let single = state(pomodoro: false)
        let running = FocusTimerRules.snapshot(of: single, at: at(10))
        #expect(running.phase == .work(round: 1))
        #expect(running.remainingSeconds == 15 * 60)
        #expect(running.phaseEnd == at(25))
        let finished = FocusTimerRules.snapshot(of: single, at: at(30))
        #expect(finished.phase == .finished)
        #expect(finished.focusedSeconds == 25 * 60)
        #expect(finished.finishedAt == at(25))
    }

    @Test func pomodoro_sequenceOfFourRounds_endsWithLongBreak() {
        let pomodoro = state()
        let expected: [(Double, FocusPhase)] = [
            (1, .work(round: 1)), (26, .shortBreak(round: 1)), (31, .work(round: 2)), (56, .shortBreak(round: 2)),
            (61, .work(round: 3)), (86, .shortBreak(round: 3)), (91, .work(round: 4)), (116, .longBreak), (129, .longBreak), (130, .finished),
            (131, .finished)
        ]
        for (minutes, phase) in expected {
            #expect(FocusTimerRules.snapshot(of: pomodoro, at: at(minutes)).phase == phase, "at minute \(minutes)")
        }
        let end = FocusTimerRules.snapshot(of: pomodoro, at: at(200))
        #expect(end.focusedSeconds == 100 * 60)
        #expect(end.completedRounds == 4)
        #expect(end.finishedAt == at(130))
    }

    @Test func pause_stopsTheClock() {
        // Paused from minute 10 to 20: work ends at minute 35 instead of 25.
        let paused = state(pauses: [DateInterval(start: at(10), end: at(20))])
        let during = FocusTimerRules.snapshot(of: paused, at: at(15))
        #expect(during.focusedSeconds == 10 * 60)
        let after = FocusTimerRules.snapshot(of: paused, at: at(30))
        #expect(after.phase == .work(round: 1))
        #expect(after.remainingSeconds == 5 * 60)
        #expect(after.phaseEnd == at(35))
        // An open pause shows no end and a frozen remaining time.
        let open = state(pausedSince: at(10))
        let frozen = FocusTimerRules.snapshot(of: open, at: at(50))
        #expect(frozen.isPaused)
        #expect(frozen.phaseEnd == nil)
        #expect(frozen.remainingSeconds == 15 * 60)
        #expect(frozen.focusedSeconds == 10 * 60)
    }

    @Test func skipBreak_startsTheNextRoundImmediately() {
        // The break would run from minute 25 to 30; skipped at minute 27, round 2 starts there.
        let skipped = state(skips: [at(27)])
        let snapshot = FocusTimerRules.snapshot(of: skipped, at: at(28))
        #expect(snapshot.phase == .work(round: 2))
        #expect(snapshot.remainingSeconds == 24 * 60)
        #expect(snapshot.completedRounds == 1)
        // A skip inside a work phase changes nothing.
        let ignored = state(skips: [at(10)])
        #expect(FocusTimerRules.snapshot(of: ignored, at: at(26)).phase == .shortBreak(round: 1))
    }

    @Test func focusedSeconds_countOnlyWorkPhases() {
        let pomodoro = state()
        // 25 (round 1) + 5 break + 10 of round 2.
        let snapshot = FocusTimerRules.snapshot(of: pomodoro, at: at(40))
        #expect(snapshot.focusedSeconds == 35 * 60)
        // Stopping at minute 12 freezes the value.
        let stopped = state(endedAt: at(12))
        #expect(FocusTimerRules.snapshot(of: stopped, at: at(90)).focusedSeconds == 12 * 60)
    }

    @Test func state_afterBackgroundGap_isDerivedFromTimestamps() {
        // Started at 10:00 with 25/5, the app was closed right away.
        let pomodoro = state()
        // 10:26: the work phase is over and booked with its 25 minutes, the break has 4 minutes left.
        let inBreak = FocusTimerRules.snapshot(of: pomodoro, at: at(26))
        #expect(inBreak.phase == .shortBreak(round: 1))
        #expect(inBreak.remainingSeconds == 4 * 60)
        #expect(inBreak.focusedSeconds == 25 * 60)
        #expect(inBreak.completedRounds == 1)
        // 10:31: the break is over as well, round 2 has run for one minute.
        let nextRound = FocusTimerRules.snapshot(of: pomodoro, at: at(31))
        #expect(nextRound.phase == .work(round: 2))
        #expect(nextRound.remainingSeconds == 24 * 60)
        #expect(nextRound.focusedSeconds == 26 * 60)
    }

    @Test func settings_areClampedToTheirBounds() {
        let low = FocusTimerSettings(workMinutes: 1, shortBreakMinutes: 0, longBreakMinutes: 1, rounds: 0)
        #expect(low.workMinutes == 5 && low.shortBreakMinutes == 1 && low.longBreakMinutes == 5 && low.rounds == 1)
        let high = FocusTimerSettings(workMinutes: 500, shortBreakMinutes: 99, longBreakMinutes: 999, rounds: 40)
        #expect(high.workMinutes == 120 && high.shortBreakMinutes == 30 && high.longBreakMinutes == 60 && high.rounds == 8)
        var edited = FocusTimerSettings()
        edited.workMinutes = 3
        #expect(edited.clamped.workMinutes == 5)
    }
}
