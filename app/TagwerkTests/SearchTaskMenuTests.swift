import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// The entries of the context menu on a task hit of the search (mockup SU1b).
struct SearchTaskMenuTests {
    private func issue(url: URL? = URL(string: "https://github.com/o/r/issues/1")) -> TaskItem {
        var item = makeTask("Login", source: .github)
        item.url = url
        return item
    }

    private func entries(_ item: TaskItem, isPlanned: Bool = false, isOffline: Bool = false) -> [SearchTaskMenu.Entry] {
        SearchTaskMenu.entries(for: item, isPlanned: isPlanned, isOffline: isOffline)
    }

    @Test func entries_localTask_hasNoGitHubEntry() {
        #expect(!entries(makeTask("Wäsche", source: .local)).contains(.openOnGitHub))
        #expect(!entries(makeTask("Anruf", source: .reminders)).contains(.openOnGitHub))
    }

    @Test func entries_issue_offersOpenOnGitHub() {
        #expect(entries(issue()).contains(.openOnGitHub))
    }

    @Test func entries_issueWithoutURL_hasNoGitHubEntry() {
        #expect(!entries(issue(url: nil)).contains(.openOnGitHub))
    }

    @Test func entries_plannedTask_offersShowInPlan() {
        let planned = entries(makeTask("Wäsche", source: .local), isPlanned: true)
        #expect(planned.contains(.showInPlan))
        #expect(!planned.contains(.showInTasks))
        let unplanned = entries(makeTask("Wäsche", source: .local), isPlanned: false)
        #expect(unplanned.contains(.showInTasks))
        #expect(!unplanned.contains(.showInPlan))
    }

    @Test func entries_offline_hasNoComplete_butPlanning() {
        let offline = entries(issue(), isOffline: true)
        #expect(!offline.contains(.complete))
        #expect(offline.contains(.planToday) && offline.contains(.planTomorrow) && offline.contains(.planOnDate))
        #expect(entries(issue(), isOffline: false).contains(.complete))
    }

    @Test func entries_completedTask_hasNoFocusStart() {
        var done = makeTask("Wäsche", source: .local)
        done.isCompleted = true
        #expect(!entries(done).contains(.startFocus))
        #expect(entries(makeTask("Wäsche", source: .local)).contains(.startFocus))
    }

    @Test func entries_orderMatchesTheMockup() {
        #expect(entries(issue(), isPlanned: false) == [
            .open, .showInTasks, .planToday, .planTomorrow, .planOnDate, .startFocus, .openOnGitHub, .complete,
        ])
        #expect(entries(makeTask("Wäsche", source: .local), isPlanned: true, isOffline: false) == [
            .open, .showInPlan, .planToday, .planTomorrow, .planOnDate, .startFocus, .complete,
        ])
    }

    @Test func searchTaskMenu_neverOffersDeleteOrStatus() {
        let allowed: Set<SearchTaskMenu.Entry> = [
            .open, .showInTasks, .showInPlan, .planToday, .planTomorrow, .planOnDate, .startFocus, .openOnGitHub, .complete,
        ]
        let items = [makeTask("Wäsche", source: .local), makeTask("Anruf", source: .reminders), issue()]
        for item in items {
            for planned in [true, false] {
                for offline in [true, false] {
                    #expect(Set(entries(item, isPlanned: planned, isOffline: offline)).isSubset(of: allowed))
                }
            }
        }
        // The entry type itself has no case for deleting, closing, status, due date, weekend, next week, effort or AI.
        let names = SearchTaskMenu.Entry.allCases.map { String(describing: $0).lowercased() }
        for forbidden in ["delete", "close", "status", "due", "weekend", "nextweek", "effort", "ai"] {
            #expect(!names.contains { $0.contains(forbidden) }, "Unexpected entry containing \(forbidden)")
        }
    }

    @Test func plannedAnnouncement_namesTodayTomorrowAndOtherDays() {
        let calendar = testCalendar()
        let today = PlanDay(year: 2026, month: 11, day: 18)
        #expect(SearchTaskMenu.plannedAnnouncement(day: today, today: today, calendar: calendar) == "Für heute eingeplant")
        #expect(SearchTaskMenu.plannedAnnouncement(day: PlanDay(year: 2026, month: 11, day: 19), today: today, calendar: calendar)
                == "Für morgen eingeplant")
        let other = SearchTaskMenu.plannedAnnouncement(day: PlanDay(year: 2026, month: 11, day: 21), today: today, calendar: calendar)
        #expect(other.hasPrefix("Eingeplant für "))
        #expect(other.contains("21"))
    }
}
