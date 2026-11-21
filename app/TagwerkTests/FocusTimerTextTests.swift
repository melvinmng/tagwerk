import Foundation
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
        #expect(FocusTimerText.collectionSummary(FocusReward.summary(of: [.completed(.one)])) == "1 Baustein")
        #expect(FocusTimerText.collectionSummary(FocusReward.summary(of: Array(repeating: FocusRewardPiece.completed(.two), count: 7))) == "7 Bausteine")
        let mixed: [FocusRewardPiece] = Array(repeating: .completed(.two), count: 5) + [.endedEarly(.one), .endedEarly(.three)]
        #expect(FocusTimerText.collectionSummary(FocusReward.summary(of: mixed)) == "7 Bausteine · 2 vorzeitig beendet")
        #expect(FocusTimerText.focusedText(seconds: 42 * 60 + 10) == "42 min Fokus")
    }

    @Test func weekHeader_showsTheStartAndTheFocusTime() {
        let start = Calendar.tagwerk.date(from: DateComponents(year: 2026, month: 11, day: 16))!
        #expect(FocusTimerText.weekHeader(start: start, focusedMinutes: 275) == "Woche ab 16. Nov. · 4 h 35 min Fokus")
        #expect(FocusTimerText.weekHeader(start: start, focusedMinutes: 40) == "Woche ab 16. Nov. · 40 min Fokus")
    }

    @Test func weekdayNames_followTheCalendarsWeek() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "de_DE")
        calendar.firstWeekday = 2
        let names = FocusTimerText.weekdayNames(calendar: calendar)
        #expect(names.short.first == "Mo" && names.short.last == "So")
        #expect(names.long.first == "Montag" && names.long.last == "Sonntag")
    }

    @Test func dayAccessibility_countsBricksMinutesAndEarlyEnds() {
        let bricks = [FocusBrick(piece: .completed(.three), focusedMinutes: 25), FocusBrick(piece: .endedEarly(.three), focusedMinutes: 25)]
        #expect(FocusTimerText.dayAccessibility(weekday: "Montag", bricks: bricks) == "Montag: 2 Bausteine, 50 Minuten Fokus, 1 vorzeitig beendet")
        #expect(FocusTimerText.dayAccessibility(weekday: "Dienstag", bricks: []) == "Dienstag: keine Bausteine")
    }
}
