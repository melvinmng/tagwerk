import Foundation
import Testing
@testable import TagwerkCore

struct FocusStartTests {
    private let pomodoro = FocusTimerSettings()
    private let single = FocusTimerSettings(workMinutes: 30, isPomodoro: false)

    @Test func settings_minutes_switchPomodoroOff() {
        let result = FocusStart.settings(base: pomodoro, choice: .minutes(45), blockRemainingMinutes: nil)
        #expect(result.workMinutes == 45 && !result.isPomodoro)
        // Break and round values stay, so a later Pomodoro start still has them.
        #expect(result.shortBreakMinutes == 5 && result.rounds == 4)
        #expect(FocusStart.settings(base: single, choice: .minutes(500), blockRemainingMinutes: nil).workMinutes == 120)
    }

    @Test func settings_untilBlockEnd_usesTheRest_atLeastFive() {
        #expect(FocusStart.settings(base: pomodoro, choice: .untilBlockEnd, blockRemainingMinutes: 28).workMinutes == 28)
        #expect(!FocusStart.settings(base: pomodoro, choice: .untilBlockEnd, blockRemainingMinutes: 28).isPomodoro)
        #expect(FocusStart.settings(base: single, choice: .untilBlockEnd, blockRemainingMinutes: 2).workMinutes == 5)
        #expect(FocusStart.settings(base: single, choice: .untilBlockEnd, blockRemainingMinutes: nil).workMinutes == 30)
    }

    @Test func settings_pomodoro_keepsTheSettingsAndSwitchesItOn() {
        let result = FocusStart.settings(base: single, choice: .pomodoro, blockRemainingMinutes: 28)
        #expect(result.isPomodoro && result.workMinutes == 30)
    }

    @Test func settings_nil_behavesAsToday() {
        // A block without Pomodoro runs to its end, at least five minutes.
        #expect(FocusStart.settings(base: single, choice: nil, blockRemainingMinutes: 40).workMinutes == 40)
        #expect(FocusStart.settings(base: single, choice: nil, blockRemainingMinutes: 2).workMinutes == 5)
        // With Pomodoro, or without a block, nothing changes.
        #expect(FocusStart.settings(base: pomodoro, choice: nil, blockRemainingMinutes: 40) == pomodoro)
        #expect(FocusStart.settings(base: single, choice: nil, blockRemainingMinutes: nil) == single)
    }

    @Test func remainingMinutes_roundsUpAndStartsAtTheBlockStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let end = start.addingTimeInterval(60 * 60)
        #expect(FocusStart.remainingMinutes(blockStart: start, blockEnd: end, now: start.addingTimeInterval(20 * 60 + 5)) == 40)
        #expect(FocusStart.remainingMinutes(blockStart: start, blockEnd: end, now: start.addingTimeInterval(-10 * 60)) == 60)
        #expect(FocusStart.remainingMinutes(blockStart: start, blockEnd: end, now: end.addingTimeInterval(60)) == 0)
    }

    @Test func preselected_blockPrefersItsEnd() {
        #expect(FocusStart.preselected(base: pomodoro, lastMinutes: 45, hasBlock: true) == .untilBlockEnd)
    }

    @Test func preselected_lastChoiceBeforeSettings() {
        #expect(FocusStart.preselected(base: pomodoro, lastMinutes: 45, hasBlock: false) == .minutes(45))
        #expect(FocusStart.preselected(base: pomodoro, lastMinutes: nil, hasBlock: false) == .pomodoro)
        #expect(FocusStart.preselected(base: single, lastMinutes: nil, hasBlock: false) == .minutes(30))
    }

    @Test func plannedMinutes_lastChoiceElseSettings() {
        #expect(FocusStart.plannedMinutes(base: pomodoro, lastMinutes: nil) == 25)
        #expect(FocusStart.plannedMinutes(base: pomodoro, lastMinutes: 45) == 45)
    }

    @Test func preset_matching() {
        #expect(FocusPreset.matching(FocusTimerSettings(workMinutes: 25, shortBreakMinutes: 5)) == .classic)
        #expect(FocusPreset.matching(FocusTimerSettings(workMinutes: 50, shortBreakMinutes: 10)) == .long)
        #expect(FocusPreset.matching(FocusTimerSettings(workMinutes: 25, shortBreakMinutes: 7)) == .custom)
    }

    @Test func preset_appliedKeepsRounds() {
        let base = FocusTimerSettings(workMinutes: 40, shortBreakMinutes: 7, longBreakMinutes: 20, rounds: 3, isPomodoro: false)
        let long = FocusPreset.long.applied(to: base)
        #expect(long.workMinutes == 50 && long.shortBreakMinutes == 10)
        #expect(long.rounds == 3 && long.longBreakMinutes == 20 && !long.isPomodoro)
        #expect(FocusPreset.custom.applied(to: base) == base)
    }
}
