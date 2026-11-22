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

    @Test func header_sumsMinutes() {
        #expect(LeftoverSheetText.header(count: 3, minutes: 150) == "3 Aufgaben · 2 h 30")
        #expect(LeftoverSheetText.header(count: 1, minutes: 45) == "1 Aufgabe · 45 min")
    }

    @Test func moveAllSubtitle_namesDayAndFit() {
        let saturday = PlanDay(year: 2026, month: 11, day: 21)
        let tomorrow = PlanDay(year: 2026, month: 11, day: 20)
        #expect(LeftoverSheetText.moveAllSubtitle(fit: .fits(freeMinutes: 240), day: saturday, today: today, calendar: calendar)
                == "Samstag hat 4 h frei · passt")
        #expect(LeftoverSheetText.moveAllSubtitle(fit: .tight(freeMinutes: 90, neededMinutes: 150), day: tomorrow, today: today, calendar: calendar)
                == "Morgen: knapp, 1 h 30 frei, 2 h 30 nötig")
        #expect(LeftoverSheetText.moveAllSubtitle(fit: .dayOff, day: saturday, today: today, calendar: calendar) == "Samstag ist kein Arbeitstag")
        #expect(LeftoverSheetText.moveAllSubtitle(fit: .unknown, day: saturday, today: today, calendar: calendar) == nil)
    }

    @Test func taskList_joinsAndTruncatesAfterThree() {
        #expect(LeftoverSheetText.taskList(["Exposé Kapitel 2", "Mail an Vermieter", "Wäsche"]) == "Exposé Kapitel 2 · Mail an Vermieter · Wäsche")
        #expect(LeftoverSheetText.taskList(["A", "B", "C", "D", "E"]) == "A · B · C und 2 weitere")
        #expect(LeftoverSheetText.taskList(["A"]) == "A")
    }

    @Test func unplacedReason_withAndWithoutDue() {
        #expect(LeftoverSheetText.unplacedReason(due: PlanDay(year: 2026, month: 11, day: 23), calendar: calendar)
                == "Kein freier Platz vor der Fälligkeit (Mo.)")
        #expect(LeftoverSheetText.unplacedReason(due: nil, calendar: calendar) == "Kein freier Platz in den nächsten Tagen")
    }

    @Test func report_carriesUnplacedTasks() {
        let id = TaskID(source: .local, rawValue: "1")
        let due = PlanDay(year: 2026, month: 11, day: 23)
        let report = LeftoverSheet.Report(moved: 2, late: 0, unplaced: 1, moves: [],
                                          unplacedTasks: [.init(id: id, title: "Wäsche", due: due)])
        #expect(report.unplacedTasks.map(\.title) == ["Wäsche"] && report.unplacedTasks.first?.due == due)
        // The default keeps the reports of the other callers as they were.
        #expect(LeftoverSheet.Report(moved: 1, late: 0, unplaced: 0, moves: []).unplacedTasks.isEmpty)
    }
}
