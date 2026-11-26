import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

struct ProjectProgressTextsTests {
    let calendar = testCalendar()
    let now = testNow()

    @Test func trendText_namesEveryCase() {
        let texts = [ProjectTrend.empty, .finished, .resting(days: 21), .advancing, .growingBacklog, .steady].map(ProjectProgressTexts.trendText)
        #expect(Set(texts).count == 6)
        #expect(texts[2].contains("21"))
    }

    @Test func movementText_todayYesterdayAndDaysAgo() {
        #expect(ProjectProgressTexts.movementText(now, now: now, calendar: calendar).contains("heute"))
        #expect(ProjectProgressTexts.movementText(now.addingTimeInterval(-86_400), now: now, calendar: calendar).contains("gestern"))
        #expect(ProjectProgressTexts.movementText(now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar).contains("3"))
        #expect(!ProjectProgressTexts.movementText(nil, now: now, calendar: calendar).isEmpty)
    }

    @Test func sourceFilter_includesTheKinds() {
        #expect(ProjectSourceFilter.all.includes(.local))
        #expect(ProjectSourceFilter.gitHub.includes(.gitHubProject) && ProjectSourceFilter.gitHub.includes(.gitHubRepository))
        #expect(!ProjectSourceFilter.gitHub.includes(.remindersList))
        #expect(ProjectSourceFilter.reminders.includes(.remindersList) && !ProjectSourceFilter.reminders.includes(.local))
        #expect(ProjectSourceFilter.local.includes(.local) && !ProjectSourceFilter.local.includes(.gitHubProject))
    }

    @Test func itemDetail_listsNumberStatusDueAndBlocks() {
        let item = ProjectItemFact(id: "a", title: "A", number: 12, state: .open, due: DueDate(year: 2026, month: 11, day: 18), status: "Blocked")
        let detail = ProjectProgressTexts.itemDetail(item, now: now, calendar: calendar)
        #expect(detail.contains("#12") && detail.contains("Blocked") && detail.contains("heute"))
        #expect(detail.localizedCaseInsensitiveContains("blockiert"))
    }

    @Test func eventText_namesTheIssue() {
        let item = ProjectItemFact(id: "a", title: "Strichcode", number: 319)
        let text = ProjectProgressTexts.eventText(ProjectEvent(kind: .completed, date: now, item: item))
        #expect(text.contains("#319 Strichcode"))
    }

    @Test func chartSummary_namesEveryWeekAndTheStock() {
        let buckets = [ProjectWeekBucket(start: now, created: 2, completed: 1, closedNotPlanned: 0, openAtEnd: 5),
                       ProjectWeekBucket(start: now.addingTimeInterval(7 * 86_400), created: 0, completed: 3, closedNotPlanned: 0, openAtEnd: 2)]
        let text = ProjectProgressTexts.chartSummary(buckets, calendar: calendar)
        #expect(text.contains("3 erledigt") && text.contains("5") && text.contains("2"))
        #expect(!ProjectProgressTexts.chartSummary([], calendar: calendar).isEmpty)
    }

    @Test func periodChoice_freeRangeNamesItsDays() {
        let range = ProjectRange(start: calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!,
                                 end: calendar.date(from: DateComponents(year: 2026, month: 11, day: 9))!)
        let name = ProjectPeriodChoice.custom.periodName(range: range, calendar: calendar)
        #expect(name.contains("2") && name.contains("8"), "the end day is the last day inside the range, not the day after")
    }
}
