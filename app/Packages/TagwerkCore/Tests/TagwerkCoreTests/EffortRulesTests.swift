import Foundation
import Testing
@testable import TagwerkCore

struct EffortRulesTests {
    private func block(_ id: String = "b", _ day: Int = 19, _ from: (Int, Int), _ to: (Int, Int)) -> EffortBlock {
        EffortBlock(id: id, start: instant(2026, 11, day, from.0, from.1), end: instant(2026, 11, day, to.0, to.1))
    }

    private func completed(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 19) -> Date {
        instant(2026, 11, day, hour, minute).addingTimeInterval(TimeInterval(second))
    }

    private func focus(_ from: (Int, Int), _ to: (Int, Int), day: Int = 19) -> DateInterval {
        DateInterval(start: instant(2026, 11, day, from.0, from.1), end: instant(2026, 11, day, to.0, to.1))
    }

    @Test func blocksDecide_focusInsideABlockIsNotCountedTwice() {
        // A past block of 60 minutes and 25 minutes of focus inside it: the block time counts, the focus adds nothing.
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))],
                                         focus: [focus((9, 10), (9, 35))])
        #expect(result.actualMinutes == 60)
        #expect(result.method == .blocks)
        // A running block is cut, and the focus inside it adds nothing either.
        let running = EffortRules.outcome(completedAt: completed(14, 20), blocks: [block("r", 19, (14, 0), (15, 0))],
                                          focus: [focus((14, 2), (14, 20))])
        #expect(running.actualMinutes == 20)
        #expect(running.method == .partialBlock)
        #expect(running.trim == BlockTrim(blockID: "r", newEnd: completed(14, 20), oldEnd: completed(15, 0)))
    }

    @Test func focusPartlyInsideABlock_countsOnlyTheOutsidePart() {
        // Block 9:00-10:00, focus 9:40-10:25: 25 minutes of it lie outside the block.
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))],
                                         focus: [focus((9, 40), (10, 25))])
        #expect(result.actualMinutes == 85)
        #expect(result.method == .blocksAndFocus)
        // Focus that starts before the block and runs into it: 10 minutes before, 20 inside.
        let before = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))],
                                         focus: [focus((8, 50), (9, 20))])
        #expect(before.actualMinutes == 70)
        // Focus around a block: 10 minutes before and 10 after.
        let around = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))],
                                         focus: [focus((8, 50), (10, 10))])
        #expect(around.actualMinutes == 80)
    }

    @Test func focusOutsideTheBlocks_isAddedToTheBlocks() {
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))],
                                         focus: [focus((12, 0), (12, 25))])
        #expect(result.actualMinutes == 85)
        #expect(result.method == .blocksAndFocus)
        // Focus time before the completion counts for a running block too: 14:00-14:20 block time plus 25 minutes at 12:00.
        let running = EffortRules.outcome(completedAt: completed(14, 20), blocks: [block("r", 19, (14, 0), (15, 0))],
                                          focus: [focus((12, 0), (12, 25))])
        #expect(running.actualMinutes == 45)
        #expect(running.method == .blocksAndFocus)
        #expect(running.trim?.newEnd == completed(14, 20))
    }

    @Test func withoutBlocks_theFocusTimeAloneIsTheEffort() {
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [], focus: [focus((12, 0), (12, 25)), focus((13, 0), (13, 10))])
        #expect(result.actualMinutes == 35)
        #expect(result.method == .focus)
        // A block that lies ahead is no block time: the focus time stays the effort.
        let future = EffortRules.outcome(completedAt: completed(8, 0), blocks: [block("f", 19, (9, 0), (10, 0))], focus: [focus((7, 0), (7, 30))])
        #expect(future.actualMinutes == 30)
        #expect(future.method == .focus)
        // Under a minute of focus is no measurement.
        let tiny = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))],
                                       focus: [focus((12, 0), (12, 0)).extended(seconds: 40)])
        #expect(tiny.method == .blocks)
        #expect(tiny.actualMinutes == 60)
    }

    @Test func pausesInsideTheFocus_areNotCountedBecauseTheyAreNotInTheIntervals() {
        // Two work stretches around a pause of ten minutes: 12:00-12:10 and 12:20-12:30.
        let intervals = [focus((12, 0), (12, 10)), focus((12, 20), (12, 30))]
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [], focus: intervals)
        #expect(result.actualMinutes == 20)
        // A block 12:05-12:25 spans the pause: it brings its 20 minutes and takes 5 + 5 minutes of the work, 10 remain.
        let withBlock = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (12, 5), (12, 25))], focus: intervals)
        #expect(withBlock.actualMinutes == 30)
    }

    @Test func overlappingBlocks_countOnce() {
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0)), block("b", 19, (9, 30), (10, 30))])
        #expect(result.actualMinutes == 90)
    }

    @Test func focusAfterTheCompletion_isIgnored() {
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [], focus: [focus((15, 0), (15, 20))])
        #expect(result.actualMinutes == nil)
    }

    @Test func completionInsideBlock_trimsToCompletionRoundedUp() {
        let planned = [block("b", 19, (14, 0), (15, 0))]
        // 14:20 is on the grid: the block ends there and the sample counts 20 minutes.
        let exact = EffortRules.outcome(completedAt: completed(14, 20), blocks: planned)
        #expect(exact.actualMinutes == 20)
        #expect(exact.method == .partialBlock)
        #expect(exact.trim?.newEnd == completed(14, 20))
        // 14:21 is rounded up to 14:25; the sample keeps the real 21 minutes.
        let rounded = EffortRules.outcome(completedAt: completed(14, 21), blocks: planned)
        #expect(rounded.trim?.newEnd == completed(14, 25))
        #expect(rounded.actualMinutes == 21)
        // The grid is the clock, not the block start: a block from 14:03 also ends at 14:25.
        let offset = EffortRules.outcome(completedAt: completed(14, 21), blocks: [block("o", 19, (14, 3), (15, 0))])
        #expect(offset.trim?.newEnd == completed(14, 25))
        // Rounding up never extends the block: at 14:57 the end would be 15:00, the old end, so nothing is cut.
        let late = EffortRules.outcome(completedAt: completed(14, 57), blocks: planned)
        #expect(late.trim == nil)
        #expect(late.actualMinutes == 57)
    }

    @Test func completionInsideBlock_withinFiveMinutes_doesNotTrim() {
        let result = EffortRules.outcome(completedAt: completed(14, 3), blocks: [block("b", 19, (14, 0), (15, 0))])
        #expect(result.trim == nil)
        #expect(result.tooShortToTrim)
        #expect(result.actualMinutes == 3)
        // Exactly five minutes is enough.
        let five = EffortRules.outcome(completedAt: completed(14, 5), blocks: [block("b", 19, (14, 0), (15, 0))])
        #expect(five.trim?.newEnd == completed(14, 5))
        #expect(!five.tooShortToTrim)
    }

    @Test func completionAfterBlockEnd_countsTheFullBlock() {
        let result = EffortRules.outcome(completedAt: completed(10, 5), blocks: [block("b", 19, (9, 0), (10, 0))])
        #expect(result.actualMinutes == 60)
        #expect(result.method == .blocks)
        #expect(result.trim == nil)
    }

    @Test func completionHoursLater_countsTheFullBlockAndChangesNothing() {
        let result = EffortRules.outcome(completedAt: completed(17, 0), blocks: [block("b", 19, (9, 0), (10, 0))])
        #expect(result.actualMinutes == 60)
        #expect(result.trim == nil)
        #expect(!result.tooShortToTrim)
    }

    @Test func noBlockNoFocus_givesNoSample() {
        let none = EffortRules.outcome(completedAt: completed(17, 0), blocks: [])
        #expect(none.actualMinutes == nil && none.method == nil && none.trim == nil)
        // A block that lies ahead is not measured and not changed.
        let future = EffortRules.outcome(completedAt: completed(8, 0), blocks: [block("f", 19, (9, 0), (10, 0))])
        #expect(future.actualMinutes == nil && future.trim == nil)
    }

    @Test func severalBlocks_pastOnesCountFully() {
        let blocks = [block("a", 18, (9, 0), (10, 0)), block("b", 19, (9, 0), (9, 30)), block("c", 19, (14, 0), (15, 0)),
                      block("d", 20, (9, 0), (10, 0))]
        let result = EffortRules.outcome(completedAt: completed(14, 20), blocks: blocks)
        // 60 + 30 + 20; the block of the next day is neither counted nor touched.
        #expect(result.actualMinutes == 110)
        #expect(result.method == .partialBlock)
        #expect(result.trim?.blockID == "c")
    }

    @Test func recurringTask_onlyCountsSinceThePreviousCompletion() {
        let blocks = [block("old", 17, (9, 0), (10, 0)), block("prevRunning", 18, (14, 0), (14, 25)), block("new", 19, (9, 0), (9, 45))]
        let previous = completed(14, 21, day: 18)
        let result = EffortRules.outcome(completedAt: completed(12, 0), blocks: blocks, since: previous)
        // The block that was running at the previous completion started before it and is not counted again.
        #expect(result.actualMinutes == 45)
        #expect(result.method == .blocks)
    }

    @Test func runningBlock_isCutEvenWhenAnOlderMeasurementStartsInsideIt() {
        // A completion at 14:05 stayed behind (the task was reopened outside Tagwerk). The block 14:00-15:00 that is
        // running now started before it, but it is the block of this completion and must still be cut.
        let result = EffortRules.outcome(completedAt: completed(14, 20), blocks: [block("b", 19, (14, 0), (15, 0))],
                                         since: completed(14, 5))
        #expect(result.trim == BlockTrim(blockID: "b", newEnd: completed(14, 20), oldEnd: completed(15, 0)))
        #expect(result.actualMinutes == 20)
    }
}

private extension DateInterval {
    func extended(seconds: TimeInterval) -> DateInterval { DateInterval(start: start, duration: seconds) }
}
