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

    @Test func sessionEnd_isTheEndOfTheLastPhase() {
        #expect(FocusTimerRules.sessionEnd(of: state(pomodoro: false)) == at(25))
        // 4 x 25 min work, 3 x 5 min short break, 15 min long break.
        #expect(FocusTimerRules.sessionEnd(of: state()) == at(130))
    }

    @Test func sessionEnd_movesBehindEveryFinishedPause() {
        let paused = state(pomodoro: false, pauses: [DateInterval(start: at(5), end: at(8))])
        #expect(FocusTimerRules.sessionEnd(of: paused) == at(28))
    }

    @Test func sessionEnd_isNilWhilePaused() {
        #expect(FocusTimerRules.sessionEnd(of: state(pomodoro: false, pausedSince: at(5))) == nil)
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

    // MARK: Work intervals

    private func minutes(_ intervals: [DateInterval]) -> [[Double]] {
        intervals.map { [$0.start.timeIntervalSince(start) / 60, $0.end.timeIntervalSince(start) / 60] }
    }

    @Test func workIntervals_skipBreaksAndStopAtTheEnd() {
        let pomodoro = state(rounds: 2, endedAt: at(40))
        // 25 work, 5 break, 25 work, but the session ended after 10 minutes of the second round.
        #expect(minutes(FocusTimerRules.workIntervals(of: pomodoro)) == [[0, 25], [30, 40]])
    }

    @Test func workIntervals_splitAtPausesAndAddUpToTheFocusedTime() {
        // A pause of 10 minutes inside the first work phase moves its end from minute 25 to 35.
        let paused = state(pomodoro: false, pauses: [DateInterval(start: at(10), end: at(20))], endedAt: at(60))
        let intervals = FocusTimerRules.workIntervals(of: paused)
        #expect(minutes(intervals) == [[0, 10], [20, 35]])
        #expect(Int(intervals.reduce(0) { $0 + $1.duration }) == FocusTimerRules.snapshot(of: paused, at: at(60)).focusedSeconds)
    }

    @Test func workIntervals_runningSessionEndsAtTheGivenMoment() {
        let running = state(pomodoro: false, pausedSince: at(12))
        #expect(minutes(FocusTimerRules.workIntervals(of: running, at: at(18))) == [[0, 12]])
        #expect(minutes(FocusTimerRules.workIntervals(of: state(pomodoro: false), at: at(7))) == [[0, 7]])
    }

    @Test func workIntervals_skippedBreakStartsTheNextRoundEarlier() {
        let skipped = state(rounds: 2, skips: [at(27)], endedAt: at(60))
        // Break skipped after 2 minutes: the second work phase runs 27-52.
        #expect(minutes(FocusTimerRules.workIntervals(of: skipped)) == [[0, 25], [27, 52]])
    }
}
