import Foundation
import Testing
@testable import TagwerkCore

struct ProjectProgressTests {
    let calendar = makeCalendar()
    /// Wednesday, 25 Nov 2026, 10:00 (Europe/Berlin); the week starts on Monday, 23 Nov.
    var now: Date { instant(2026, 11, 25, 10, 0, in: calendar) }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12) -> Date { instant(2026, month, day, hour, 0, in: calendar) }

    private func open(_ id: String, created: Date? = nil, due: DueDate? = nil, status: String? = nil, blockedBy: Int = 0,
                      blocking: Int = 0) -> ProjectItemFact {
        ProjectItemFact(id: id, title: id, createdAt: created, state: .open, due: due, status: status,
                        openBlockedByCount: blockedBy, openBlockingCount: blocking)
    }

    private func closed(_ id: String, created: Date?, closedAt: Date?, state: ProjectItemState = .completed) -> ProjectItemFact {
        ProjectItemFact(id: id, title: id, createdAt: created, closedAt: closedAt, state: state)
    }

    private func summary(_ facts: [ProjectItemFact], _ period: ProjectPeriod = .fourWeeks) -> ProjectSummary {
        ProjectProgress.summary(facts: facts, period: period, now: now, calendar: calendar)
    }

    // MARK: Counts

    @Test func summary_countsOpenCompletedAndNotPlanned() {
        let result = summary([
            open("a", created: date(11, 1)),
            closed("b", created: date(10, 1), closedAt: date(11, 3)),
            closed("c", created: date(10, 1), closedAt: date(11, 4), state: .closedNotPlanned),
        ])
        #expect(result.open == 1)
        #expect(result.completed == 1)
        #expect(result.closedNotPlanned == 1)
        #expect(result.total == 3)
        #expect(result.completedShare == 1.0 / 3.0)
    }

    @Test func summary_periodCountsOnlyInsideThePeriod() {
        // Four weeks start on Monday, 2 Nov 2026.
        let result = summary([
            open("created-in", created: date(11, 10)),
            open("created-before", created: date(10, 30)),
            closed("done-in", created: date(10, 1), closedAt: date(11, 12)),
            closed("done-before", created: date(10, 1), closedAt: date(11, 1, 23)),
            closed("not-planned-in", created: date(10, 1), closedAt: date(11, 12), state: .closedNotPlanned),
        ])
        #expect(result.periodCreated == 1)
        #expect(result.periodCompleted == 1, "closing as not planned is no completion")
    }

    @Test func summary_emptyProject() {
        let result = summary([])
        #expect(result.total == 0)
        #expect(result.completedShare == 0)
        #expect(result.trend == .empty)
        #expect(result.lastMovement == nil)
    }

    // MARK: Weekly buckets

    @Test func range_presetsStartOnTheMondayOfTheirFirstWeek() {
        let four = ProjectProgress.range(of: .fourWeeks, now: now, calendar: calendar)
        #expect(four.start == instant(2026, 11, 2, 0, 0, in: calendar))
        #expect(four.end == now)
        let three = ProjectProgress.range(of: .threeMonths, now: now, calendar: calendar)
        #expect(three.start == instant(2026, 8, 31, 0, 0, in: calendar))
        let year = ProjectProgress.range(of: .oneYear, now: now, calendar: calendar)
        #expect(year.start == instant(2025, 12, 1, 0, 0, in: calendar))
    }

    @Test func buckets_fourWeeksHaveFourBucketsFromMonday() {
        let result = summary([])
        #expect(result.buckets.count == 4)
        #expect(result.buckets.map(\.start) == [2, 9, 16, 23].map { instant(2026, 11, $0, 0, 0, in: calendar) })
    }

    @Test func buckets_countCreatedAndCompletedPerWeek() {
        let result = summary([
            closed("a", created: date(11, 3), closedAt: date(11, 4)),
            closed("b", created: date(11, 4), closedAt: date(11, 18)),
            open("c", created: date(11, 24)),
        ])
        #expect(result.buckets.map(\.created) == [2, 0, 0, 1])
        #expect(result.buckets.map(\.completed) == [1, 0, 1, 0])
    }

    @Test func buckets_openAtEndIsReconstructedFromTheDates() {
        let result = summary([
            open("old", created: date(9, 1)),
            closed("b", created: date(11, 3), closedAt: date(11, 18)),
            open("c", created: date(11, 24)),
        ])
        // End of the week of 2 Nov: old, b. 9 Nov: old, b. 16 Nov: old (b closed on the 18th). 23 Nov: old, c.
        #expect(result.buckets.map(\.openAtEnd) == [2, 2, 1, 2])
        #expect(result.open == 2)
    }

    @Test func buckets_itemCreatedAndClosedInTheSameWeek() {
        let result = summary([closed("a", created: date(11, 3), closedAt: date(11, 5))])
        #expect(result.buckets[0].created == 1)
        #expect(result.buckets[0].completed == 1)
        #expect(result.buckets[0].openAtEnd == 0)
    }

    @Test func buckets_completedWithoutKnownDateStaysOutOfTheBuckets() {
        let result = summary([closed("legacy", created: date(10, 1), closedAt: nil)])
        #expect(result.completed == 1)
        #expect(result.buckets.map(\.completed) == [0, 0, 0, 0])
        #expect(result.buckets.map(\.openAtEnd) == [0, 0, 0, 0], "an item closed at an unknown time is not open in the period")
    }

    @Test func buckets_itemWithoutCreationDateExistsFromTheStart() {
        let result = summary([open("unknown")])
        #expect(result.buckets.map(\.openAtEnd) == [1, 1, 1, 1])
        #expect(result.periodCreated == 0)
    }

    @Test func buckets_itemCreatedJustBeforeTheEndOfAWeekIsOpenAtThatEnd() {
        // Monday 23 Nov 00:00 ends the week of 16 Nov; the item is created half a millisecond before.
        let boundary = date(11, 23, 0)
        let result = summary([open("late", created: boundary.addingTimeInterval(-0.0005))])
        #expect(result.buckets.map(\.created) == [0, 0, 1, 0])
        #expect(result.buckets.map(\.openAtEnd) == [0, 0, 1, 1], "created in the bucket and still open: open at its end")
    }

    @Test func buckets_itemClosedJustBeforeTheEndOfAWeekHasLeftAtThatEnd() {
        let boundary = date(11, 23, 0)
        let result = summary([closed("gone", created: date(11, 3), closedAt: boundary.addingTimeInterval(-0.0005))])
        #expect(result.buckets.map(\.completed) == [0, 0, 1, 0])
        #expect(result.buckets.map(\.openAtEnd) == [1, 1, 0, 0])
    }

    @Test func buckets_itemCreatedExactlyAtTheEndBelongsToTheNextWeek() {
        let boundary = date(11, 23, 0)
        let result = summary([open("next", created: boundary)])
        #expect(result.buckets.map(\.created) == [0, 0, 0, 1])
        #expect(result.buckets.map(\.openAtEnd) == [0, 0, 0, 1])
    }

    @Test func buckets_lastWeekEndsAtNow() {
        let result = summary([open("later", created: date(11, 25, 11))])
        #expect(result.buckets.last?.openAtEnd == 0, "an item created after now is not counted")
    }

    // MARK: Free range

    @Test func range_customCoversWholeDaysAndIsCutAtNow() {
        let result = ProjectProgress.range(of: .custom(start: PlanDay(year: 2026, month: 11, day: 10),
                                                       end: PlanDay(year: 2026, month: 12, day: 31)),
                                           now: now, calendar: calendar)
        #expect(result.start == instant(2026, 11, 10, 0, 0, in: calendar))
        #expect(result.end == now)
    }

    @Test func range_customSwapsAStartAfterTheEnd() {
        let result = ProjectProgress.range(of: .custom(start: PlanDay(year: 2026, month: 11, day: 12),
                                                       end: PlanDay(year: 2026, month: 11, day: 10)),
                                           now: now, calendar: calendar)
        #expect(result.start == instant(2026, 11, 10, 0, 0, in: calendar))
        #expect(result.end == instant(2026, 11, 13, 0, 0, in: calendar))
    }

    @Test func range_customIsLimitedToTheMaximumOfWeeks() {
        let result = ProjectProgress.range(of: .custom(start: PlanDay(year: 2015, month: 1, day: 1),
                                                       end: PlanDay(year: 2026, month: 11, day: 25)),
                                           now: now, calendar: calendar)
        let buckets = ProjectProgress.buckets(facts: [], range: result, calendar: calendar)
        #expect(buckets.count == ProjectProgress.maxCustomWeeks)
    }

    @Test func buckets_customRangeCountsOnlyInsideTheRange() {
        let period = ProjectPeriod.custom(start: PlanDay(year: 2026, month: 11, day: 5), end: PlanDay(year: 2026, month: 11, day: 11))
        let result = summary([
            open("before", created: date(11, 4)),
            open("in", created: date(11, 6)),
            open("after", created: date(11, 12)),
        ], period)
        #expect(result.periodCreated == 1)
        #expect(result.buckets.map(\.created) == [1, 0])
    }

    // MARK: Blocked and blockers

    @Test func blocked_byStatusIgnoresCase() {
        #expect(open("a", status: "Blocked").isBlocked)
        #expect(open("a", status: "blocked ").isBlocked)
        #expect(!open("a", status: "In progress").isBlocked)
        #expect(!open("a", status: "Not blocked").isBlocked)
    }

    @Test func blocked_byAnOpenDependency() {
        #expect(open("a", blockedBy: 1).isBlocked)
        #expect(!open("a", blockedBy: 0).isBlocked)
    }

    @Test func blocked_aClosedItemIsNeverBlocked() {
        var item = closed("a", created: date(11, 1), closedAt: date(11, 2))
        item.openBlockedByCount = 2
        item.status = "Blocked"
        #expect(!item.isBlocked)
    }

    @Test func blocker_isAnOpenItemThatOthersWaitFor() {
        #expect(open("a", blocking: 2).isBlocker)
        #expect(!open("a", blocking: 0).isBlocker)
        var done = closed("b", created: date(11, 1), closedAt: date(11, 2))
        done.openBlockingCount = 1
        #expect(!done.isBlocker)
    }

    @Test func blocker_noFreeTextDetection() {
        var item = open("Blocked by the vendor")
        item.notesBlockedHint()
        #expect(!item.isBlocked)
    }

    @Test func summary_countsBlockedAndBlockers() {
        let result = summary([open("a", status: "Blocked"), open("b", blockedBy: 1), open("c", blocking: 1), open("d")])
        #expect(result.blocked == 2)
        #expect(result.blockers == 1)
    }

    // MARK: Trend

    @Test func trend_restsAfterFourteenDaysWithoutMovement() {
        // Last movement on 11 Nov 12:00; "now" is 25 Nov: 14 calendar days.
        let items = [open("a", created: date(11, 11))]
        #expect(summary(items).trend == .resting(days: 14))
    }

    @Test func trend_doesNotRestAfterThirteenDays() {
        let items = [open("a", created: date(11, 12))]
        #expect(summary(items).trend != .resting(days: 13))
        if case .resting = summary(items).trend { Issue.record("13 days must not count as resting") }
    }

    @Test func trend_restingUsesTheNamedConstant() {
        #expect(ProjectProgress.restingAfterDays == 14)
    }

    @Test func trend_aClosingCountsAsMovement() {
        let items = [open("a", created: date(10, 1)), closed("b", created: date(10, 1), closedAt: date(11, 20))]
        #expect(summary(items).trend == .advancing)
    }

    @Test func trend_finishedWhenNothingIsOpen() {
        #expect(summary([closed("a", created: date(10, 1), closedAt: date(10, 2))]).trend == .finished)
    }

    @Test func trend_growingWhenMoreAreCreatedThanCompleted() {
        let items = [open("a", created: date(11, 20)), open("b", created: date(11, 21)),
                     closed("c", created: date(10, 1), closedAt: date(11, 22))]
        #expect(summary(items).trend == .growingBacklog)
        #expect(summary(items).net == 1)
    }

    @Test func trend_steadyWhenBothAreEqual() {
        let items = [open("a", created: date(11, 20)), closed("c", created: date(10, 1), closedAt: date(11, 22))]
        #expect(summary(items).trend == .steady)
    }

    @Test func trend_unknownDatesNeverRest() {
        #expect(summary([open("a")]).trend == .steady)
    }

    @Test func lastMovement_isTheNewestCreationOrClosing() {
        let items = [open("a", created: date(11, 3)), closed("b", created: date(10, 1), closedAt: date(11, 9))]
        #expect(ProjectProgress.lastMovement(facts: items) == date(11, 9))
    }

    // MARK: Events and open items

    @Test func events_areSortedNewestFirstAndSplitIntoKinds() {
        let events = ProjectProgress.events(facts: [
            closed("a", created: date(11, 1), closedAt: date(11, 5)),
            closed("b", created: date(11, 2), closedAt: date(11, 6), state: .closedNotPlanned),
            open("c", created: date(11, 4)),
        ])
        #expect(events.map(\.kind) == [.closedNotPlanned, .completed, .created, .created, .created])
        #expect(events.map(\.item.id) == ["b", "a", "c", "b", "a"])
    }

    @Test func events_restrictedToARange() {
        let range = ProjectRange(start: date(11, 3), end: date(11, 6))
        let events = ProjectProgress.events(facts: [closed("a", created: date(11, 1), closedAt: date(11, 5))], in: range)
        #expect(events.map(\.kind) == [.completed])
    }

    @Test func openGroups_blockedOverdueSoonAndRest() {
        let today = PlanDay(year: 2026, month: 11, day: 25)
        let groups = ProjectProgress.openGroups(facts: [
            open("blocked", due: DueDate(year: 2026, month: 11, day: 1), blockedBy: 1),
            open("blocker", blocking: 1),
            open("overdue", due: DueDate(year: 2026, month: 11, day: 24)),
            open("today", due: DueDate(year: 2026, month: 11, day: 25)),
            open("in-14", due: DueDate(year: 2026, month: 12, day: 9)),
            open("in-15", due: DueDate(year: 2026, month: 12, day: 10)),
            open("none"),
            closed("done", created: date(11, 1), closedAt: date(11, 2)),
        ], today: today, calendar: calendar)
        #expect(groups.blocked.map(\.id) == ["blocked"], "blocked wins over overdue")
        #expect(groups.blockers.map(\.id) == ["blocker"])
        #expect(groups.overdue.map(\.id) == ["overdue"])
        #expect(groups.soon.map(\.id) == ["today", "in-14"])
        #expect(groups.rest.map(\.id) == ["in-15", "none"], "items without a due date come last")
    }

    @Test func counts_sumsAcrossProjects() {
        let first = [open("a", created: date(11, 24)), closed("b", created: date(10, 1), closedAt: date(11, 24))]
        let second = [open("c", created: date(11, 10))]
        let counts = ProjectProgress.counts(facts: [first, second], since: date(11, 18), until: now)
        #expect(counts.created == 1)
        #expect(counts.completed == 1)
    }
}

private extension ProjectItemFact {
    /// A title that mentions a block: nothing in the item may read it.
    mutating func notesBlockedHint() { title += " (blocked)" }
}
