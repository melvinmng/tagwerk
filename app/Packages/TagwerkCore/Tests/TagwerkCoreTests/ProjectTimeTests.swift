import Foundation
import Testing
@testable import TagwerkCore

struct ProjectTimeTests {
    let calendar = makeCalendar()
    /// Wednesday, 25 Nov 2026, 10:00 (Europe/Berlin); the week starts on Monday, 23 Nov. Four weeks start on Monday, 2 Nov.
    var now: Date { instant(2026, 11, 25, 10, 0, in: calendar) }
    var range: ProjectRange { ProjectProgress.range(of: .fourWeeks, now: now, calendar: calendar) }

    private func date(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
        instant(2026, month, day, hour, minute, in: calendar)
    }

    private func block(_ key: String, _ day: Int, from startHour: Int, to endHour: Int, month: Int = 11,
                       plannedUntil: Int? = nil) -> ProjectTimeBlock {
        ProjectTimeBlock(taskKey: key, start: date(month, day, startHour), end: date(month, day, endHour),
                         plannedEnd: plannedUntil.map { date(month, day, $0) })
    }

    private func focus(_ key: String, _ day: Int, from startHour: Int, to endHour: Int) -> ProjectFocusSpan {
        ProjectFocusSpan(taskKey: key, start: date(11, day, startHour), end: date(11, day, endHour))
    }

    private func summary(_ inputs: ProjectTimeInputs, keys: Set<String> = ["a"], range override: ProjectRange? = nil) -> ProjectTimeSummary {
        ProjectTime.summary(inputs: inputs, taskKeys: keys, range: override ?? range, calendar: calendar)
    }

    private func hours(_ seconds: TimeInterval) -> Double { seconds / 3600 }

    // MARK: Invested: focus

    @Test func time_sumsFocusSessionsPerWeek() {
        let result = summary(ProjectTimeInputs(focus: [
            focus("a", 3, from: 9, to: 10),    // week of 2 Nov
            focus("a", 4, from: 9, to: 11),    // week of 2 Nov
            focus("a", 24, from: 14, to: 15),  // week of 23 Nov
        ]))
        #expect(result.weeks.count == 4)
        #expect(hours(result.weeks[0].investedSeconds) == 3)
        #expect(hours(result.weeks[1].investedSeconds) == 0)
        #expect(hours(result.weeks[3].investedSeconds) == 1)
        #expect(hours(result.investedSeconds) == 4)
        #expect(result.hasInvested)
        #expect(!result.hasPlanned)
    }

    @Test func time_focusOutsideThePeriodDoesNotCount() {
        let result = summary(ProjectTimeInputs(focus: [focus("a", 1, from: 9, to: 10)]))
        #expect(result.investedSeconds == 0)
        #expect(!result.hasInvested)
    }

    @Test func time_focusOverlappingTheStartIsCutAtTheStart() {
        // Sunday 1 Nov 23:00 to Monday 2 Nov 01:00; the period starts on Monday 2 Nov 00:00.
        let span = ProjectFocusSpan(taskKey: "a", start: date(11, 1, 23), end: date(11, 2, 1))
        #expect(hours(summary(ProjectTimeInputs(focus: [span])).investedSeconds) == 1)
    }

    // MARK: Planned: blocks

    @Test func time_sumsLinkedBlocksPerWeek() {
        let result = summary(ProjectTimeInputs(blocks: [
            block("a", 3, from: 9, to: 11),
            block("a", 10, from: 9, to: 10),
            block("a", 25, from: 8, to: 9),
        ]))
        #expect(hours(result.weeks[0].plannedSeconds) == 2)
        #expect(hours(result.weeks[1].plannedSeconds) == 1)
        #expect(hours(result.weeks[3].plannedSeconds) == 1)
        #expect(hours(result.plannedSeconds) == 4)
        #expect(result.hasPlanned)
    }

    @Test func time_blockSplitsAtTheWeekBoundary() {
        // Sunday 8 Nov 22:00 to Monday 9 Nov 02:00.
        let night = ProjectTimeBlock(taskKey: "a", start: date(11, 8, 22), end: date(11, 9, 2))
        let result = summary(ProjectTimeInputs(blocks: [night]))
        #expect(hours(result.weeks[0].plannedSeconds) == 2)
        #expect(hours(result.weeks[1].plannedSeconds) == 2)
    }

    @Test func time_runningBlockCountsUpToNow() {
        // Wednesday 25 Nov 09:00 to 12:00 while it is 10:00.
        let result = summary(ProjectTimeInputs(blocks: [block("a", 25, from: 9, to: 12)]))
        #expect(hours(result.plannedSeconds) == 1)
    }

    @Test func time_blockAfterNowDoesNotCount() {
        let result = summary(ProjectTimeInputs(blocks: [block("a", 25, from: 14, to: 15)]))
        #expect(result.plannedSeconds == 0)
        #expect(!result.hasPlanned)
    }

    @Test func time_plannedUsesTheEndBeforeTheCut() {
        // The block was planned until 12:00 and cut to 10:30 when the task was completed.
        let cut = block("a", 10, from: 9, to: 10, plannedUntil: 12)
        #expect(hours(summary(ProjectTimeInputs(blocks: [cut])).plannedSeconds) == 3)
    }

    @Test func time_overlappingBlocksOfTwoTasksCountOnce() {
        let result = summary(ProjectTimeInputs(blocks: [block("a", 10, from: 9, to: 11), block("b", 10, from: 10, to: 12)]),
                             keys: ["a", "b"])
        #expect(hours(result.plannedSeconds) == 3)
    }

    @Test func time_withoutCalendarNoBlockIsKnown() {
        let result = summary(ProjectTimeInputs(blocks: [block("a", 10, from: 9, to: 11)], calendarAvailable: false))
        #expect(result.plannedSeconds == 0)
        #expect(!result.hasPlanned)
        #expect(!result.calendarAvailable)
    }

    // MARK: Invested: blocks of completed tasks

    @Test func time_blocksCountAsInvestedOnlyAfterACompletionThatCountedBlocks() {
        let blocks = [block("a", 10, from: 9, to: 11)]
        let none = summary(ProjectTimeInputs(blocks: blocks))
        #expect(none.investedSeconds == 0, "a block of an open task is only planned")
        let focusOnly = summary(ProjectTimeInputs(blocks: blocks, completions: [
            ProjectCompletion(taskKey: "a", completedAt: date(11, 10, 11), countsBlocks: false)]))
        #expect(focusOnly.investedSeconds == 0, "a measurement from focus alone did not count the blocks")
        let counted = summary(ProjectTimeInputs(blocks: blocks, completions: [
            ProjectCompletion(taskKey: "a", completedAt: date(11, 10, 12), countsBlocks: true)]))
        #expect(hours(counted.investedSeconds) == 2)
    }

    @Test func time_blockCountsUpToTheCompletion() {
        let blocks = [block("a", 10, from: 9, to: 12)]
        let result = summary(ProjectTimeInputs(blocks: blocks, completions: [
            ProjectCompletion(taskKey: "a", completedAt: date(11, 10, 10, 30), countsBlocks: true)]))
        #expect(hours(result.investedSeconds) == 1.5)
    }

    @Test func time_blockBeforeTheCompletionIsNotCountedForALaterOne() {
        // The completion lies before the block starts (task reopened, block planned afterwards): the block is not counted for it.
        let blocks = [block("a", 12, from: 9, to: 10)]
        let result = summary(ProjectTimeInputs(blocks: blocks, completions: [
            ProjectCompletion(taskKey: "a", completedAt: date(11, 10, 12), countsBlocks: true)]))
        #expect(result.investedSeconds == 0)
    }

    @Test func time_focusInsideACountedBlockCountsOnce() {
        let result = summary(ProjectTimeInputs(
            blocks: [block("a", 10, from: 9, to: 11)],
            focus: [focus("a", 10, from: 9, to: 10), focus("a", 10, from: 11, to: 12)],
            completions: [ProjectCompletion(taskKey: "a", completedAt: date(11, 10, 13), countsBlocks: true)]))
        // Block 9-11 plus the focus 11-12 outside of it; the focus 9-10 lies inside the block.
        #expect(hours(result.investedSeconds) == 3)
    }

    // MARK: Project selection

    @Test func time_ignoresTasksOutsideTheProject() {
        let inputs = ProjectTimeInputs(
            blocks: [block("a", 10, from: 9, to: 10), block("other", 10, from: 13, to: 15)],
            focus: [focus("a", 11, from: 9, to: 10), focus("other", 11, from: 13, to: 16)],
            completions: [ProjectCompletion(taskKey: "other", completedAt: date(11, 10, 16), countsBlocks: true)])
        let result = summary(inputs, keys: ["a"])
        #expect(hours(result.plannedSeconds) == 1)
        #expect(hours(result.investedSeconds) == 1)
        #expect(summary(inputs, keys: []).hasData == false)
    }

    @Test func time_noRecordedTimeIsNoData() {
        let result = summary(ProjectTimeInputs())
        #expect(!result.hasData)
        #expect(result.weeks.count == 4)
    }

    @Test func time_customRangeCutsToTheRange() {
        let custom = ProjectProgress.range(of: .custom(start: PlanDay(year: 2026, month: 11, day: 10),
                                                       end: PlanDay(year: 2026, month: 11, day: 10)), now: now, calendar: calendar)
        let result = summary(ProjectTimeInputs(focus: [focus("a", 9, from: 9, to: 10), focus("a", 10, from: 9, to: 11)]), range: custom)
        #expect(hours(result.investedSeconds) == 2)
        #expect(result.weeks.count == 1)
    }

    // MARK: Open estimate

    @Test func time_openEstimateAndCountWithoutEstimate() {
        let facts = [
            ProjectItemFact(id: "1", title: "1", state: .open, estimateMinutes: 120),
            ProjectItemFact(id: "2", title: "2", state: .open, estimateMinutes: 90),
            ProjectItemFact(id: "3", title: "3", state: .open),
            ProjectItemFact(id: "4", title: "4", state: .open, estimateMinutes: 0),
            ProjectItemFact(id: "5", title: "5", state: .completed, estimateMinutes: 600),
            ProjectItemFact(id: "6", title: "6", state: .closedNotPlanned),
        ]
        let estimate = ProjectTime.openEstimate(facts: facts)
        #expect(estimate.minutes == 210)
        #expect(estimate.estimatedCount == 2)
        #expect(estimate.withoutEstimateCount == 2)
        #expect(estimate.openCount == 4)
    }

    // MARK: Shared weeks

    @Test func weeks_bucketsAndTimeUseTheSameIntervals() {
        let intervals = ProjectProgress.weekIntervals(of: range, calendar: calendar)
        let buckets = ProjectProgress.buckets(facts: [], range: range, calendar: calendar)
        #expect(intervals.map(\.start) == buckets.map(\.start))
        #expect(intervals.last?.end == now)
    }
}
