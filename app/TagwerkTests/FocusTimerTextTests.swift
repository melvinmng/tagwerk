import Testing
import TagwerkCore
@testable import Tagwerk

struct FocusTimerTextTests {
    @Test func clock_formatsMinutesAndHours() {
        #expect(FocusTimerText.clock(0) == "00:00")
        #expect(FocusTimerText.clock(25 * 60) == "25:00")
        #expect(FocusTimerText.clock(24 * 60 + 5) == "24:05")
        #expect(FocusTimerText.clock(3600 + 65) == "1:01:05")
        #expect(FocusTimerText.clock(-5) == "00:00")
    }

    @Test func roundText_onlyWithPomodoro() {
        let pomodoro = FocusTimerSettings()
        #expect(FocusTimerText.roundText(phase: .work(round: 2), settings: pomodoro) == "Runde 2 von 4")
        #expect(FocusTimerText.roundText(phase: .longBreak, settings: pomodoro) == "Runde 4 von 4")
        #expect(FocusTimerText.roundText(phase: .finished, settings: pomodoro) == nil)
        #expect(FocusTimerText.roundText(phase: .work(round: 1), settings: FocusTimerSettings(isPomodoro: false)) == nil)
    }

    @Test func collectionSummary_germanTexts() {
        #expect(FocusTimerText.collectionSummary(FocusReward.summary(of: [])) == "Noch leer")
        #expect(FocusTimerText.collectionSummary(FocusReward.summary(of: [.grown(.one), .grown(.two), .wilted(.one)])) == "2 gewachsen · 1 gewelkt")
        #expect(FocusTimerText.focusedText(seconds: 42 * 60 + 10) == "42 min Fokus")
    }
}
