import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Reference: Wednesday, 18 Nov 2026; tomorrow is Thursday 19, Friday 20 is "later".
struct DayPanelTextTests {
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let tomorrow = PlanDay(year: 2026, month: 11, day: 19)
    let friday = PlanDay(year: 2026, month: 11, day: 20)

    @Test func commitTitle_today_tomorrow_later() {
        #expect(DayPanelText.commitTitle(day: today, today: today, calendar: calendar) == "Heute")
        #expect(DayPanelText.commitTitle(day: tomorrow, today: today, calendar: calendar) == "Morgen")
        #expect(DayPanelText.commitTitle(day: friday, today: today, calendar: calendar) == "Einplanen")
    }

    @Test func dueSectionTitle_today_tomorrow_later() {
        #expect(DayPanelText.dueSectionTitle(day: today, today: today, calendar: calendar) == "Heute offen, nicht zugeordnet")
        #expect(DayPanelText.dueSectionTitle(day: tomorrow, today: today, calendar: calendar) == "Morgen fällig, nicht zugeordnet")
        #expect(DayPanelText.dueSectionTitle(day: friday, today: today, calendar: calendar) == "An diesem Tag fällig, nicht zugeordnet")
    }

    @Test func lunchLine_namesTheShownDay() {
        let lunch = 720..<780
        #expect(DayPanelText.lunchLine(lunch, day: today, today: today, calendar: calendar) == "Pause heute 12:00–13:00")
        #expect(DayPanelText.lunchLine(lunch, day: tomorrow, today: today, calendar: calendar) == "Pause morgen 12:00–13:00")
        #expect(DayPanelText.lunchLine(lunch, day: friday, today: today, calendar: calendar) == "Pause Fr. 12:00–13:00")
        #expect(DayPanelText.lunchLine(nil, day: today, today: today, calendar: calendar) == "Heute keine Pause")
        #expect(DayPanelText.lunchLine(nil, day: tomorrow, today: today, calendar: calendar) == "Morgen keine Pause")
        #expect(DayPanelText.lunchLine(nil, day: friday, today: today, calendar: calendar) == "Fr. keine Pause")
    }

    @Test func planTitle_tomorrowSaysMorgenPlanen() {
        #expect(DayPanelText.planTitle(scope: .day, day: today, today: today, leftCount: 0, calendar: calendar) == "Tag planen")
        #expect(DayPanelText.planTitle(scope: .day, day: tomorrow, today: today, leftCount: 0, calendar: calendar) == "Morgen planen")
        #expect(DayPanelText.planTitle(scope: .day, day: tomorrow, today: today, leftCount: 2, calendar: calendar)
                == "Morgen planen mit 2 von heute")
        #expect(DayPanelText.planTitle(scope: .day, day: friday, today: today, leftCount: 0, calendar: calendar) == "Tag planen")
        #expect(DayPanelText.planTitle(scope: .week, day: tomorrow, today: today, leftCount: 0, calendar: calendar) == "Woche planen")
    }

    @Test func eveningEntry_titleAndDetail() {
        #expect(DayPanelText.eveningTitle(day: tomorrow, today: today, calendar: calendar) == "Morgen planen")
        #expect(DayPanelText.eveningTitle(day: PlanDay(year: 2026, month: 11, day: 23), today: today, calendar: calendar) == "Mo. planen")
        #expect(DayPanelText.eveningDetail(day: tomorrow, freeMinutes: 195, leftCount: 2, calendar: calendar)
                == "Do. 19. Nov. · 3 h 15 frei · 2 von heute übrig")
        #expect(DayPanelText.eveningDetail(day: tomorrow, freeMinutes: 195, leftCount: 0, calendar: calendar)
                == "Do. 19. Nov. · 3 h 15 frei")
    }

    @Test func moveAllTitle_and_hints() {
        #expect(DayPanelText.moveAllTitle(day: tomorrow, today: today, calendar: calendar) == "Alle auf morgen")
        #expect(DayPanelText.moveAllTitle(day: friday, today: today, calendar: calendar) == "Alle einplanen")
        #expect(DayPanelText.commitFooter(day: today, today: today, calendar: calendar)
                == "„Heute“ legt die Aufgabe für heute fest; dann lässt sie sich ins Raster ziehen.")
        #expect(DayPanelText.commitFooter(day: tomorrow, today: today, calendar: calendar)
                == "„Morgen“ legt die Aufgabe für morgen fest; dann lässt sie sich ins Raster ziehen.")
        #expect(DayPanelText.commitFooter(day: friday, today: today, calendar: calendar)
                == "„Einplanen“ legt die Aufgabe für diesen Tag fest; dann lässt sie sich ins Raster ziehen.")
        #expect(DayPanelText.emptyPlannedHint(day: tomorrow, today: today, calendar: calendar)
                == "Nutze „Morgen“ unten oder „Einplanen“ im Menü einer Aufgabe.")
    }
}
