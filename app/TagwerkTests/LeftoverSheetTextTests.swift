import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct LeftoverSheetTextTests {
    let calendar = testCalendar()
    let today = PlanDay(year: 2026, month: 11, day: 19)  // Thursday

    @Test func outcomeText_namesMovedLateAndUnplaced() {
        #expect(LeftoverSheetText.outcome(moved: 3, late: 0, unplaced: 1) == "3 verschoben · 1 ohne freien Platz")
        #expect(LeftoverSheetText.outcome(moved: 4, late: 2, unplaced: 0) == "4 verschoben · 2 nach Fälligkeit")
        #expect(LeftoverSheetText.outcome(moved: 2, late: 1, unplaced: 3) == "2 verschoben · 1 nach Fälligkeit · 3 ohne freien Platz")
        #expect(LeftoverSheetText.outcome(moved: 0, late: 0, unplaced: 2) == "2 ohne freien Platz")
        #expect(LeftoverSheetText.outcome(moved: 0, late: 0, unplaced: 0) == "0 verschoben")
    }

    @Test func titles_followTheNextWorkingDay() {
        let tomorrow = today.adding(days: 1, calendar: calendar)
        let monday = today.adding(days: 4, calendar: calendar)
        #expect(LeftoverSheetText.moveAllTitle(day: tomorrow, today: today, calendar: calendar) == "Alles auf morgen")
        #expect(LeftoverSheetText.moveAllTitle(day: monday, today: today, calendar: calendar) == "Alles auf Montag")
        #expect(LeftoverSheetText.singleMoveTitle(day: tomorrow, today: today, calendar: calendar) == "Morgen")
        #expect(LeftoverSheetText.freeBlockSubtitle(day: monday, today: today, calendar: calendar)
                == "Ab Montag, vor der Fälligkeit, ohne Überschneidung")
        #expect(LeftoverSheetText.freeBlockSubtitle(day: nil, today: today, calendar: calendar) == nil)
    }

    @Test func lineTitle_countsTheTasks() {
        #expect(LeftoverSheetText.lineTitle(count: 1) == "Unerledigtes verschieben · 1 Aufgabe")
        #expect(LeftoverSheetText.lineTitle(count: 3) == "Unerledigtes verschieben · 3 Aufgaben")
    }
}
