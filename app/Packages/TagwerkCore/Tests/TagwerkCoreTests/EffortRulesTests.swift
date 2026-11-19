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

    @Test func focusTime_winsOverBlocks() {
        // A past block of 60 minutes and 25 minutes of focus: only the focus time counts.
        let result = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))], focusedSeconds: 25 * 60)
        #expect(result.actualMinutes == 25)
        #expect(result.method == .focus)
        // A running block is cut anyway, and the focus time still decides the effort.
        let running = EffortRules.outcome(completedAt: completed(14, 20), blocks: [block("r", 19, (14, 0), (15, 0))], focusedSeconds: 18 * 60)
        #expect(running.actualMinutes == 18)
        #expect(running.trim == BlockTrim(blockID: "r", newEnd: completed(14, 20), oldEnd: completed(15, 0)))
        // Under a minute of focus is no measurement.
        let tiny = EffortRules.outcome(completedAt: completed(15, 0), blocks: [block("a", 19, (9, 0), (10, 0))], focusedSeconds: 40)
        #expect(tiny.method == .blocks)
    }

    @Test func completionInsideBlock_trimsToCompletionRoundedUp() {
        let planned = [block("b", 19, (14, 0), (15, 0))]
        // 14:20 is on the grid: the block ends there and the sample counts 20 minutes.
        let exact = EffortRules.outcome(completedAt: completed(14, 20), blocks: planned, focusedSeconds: 0)
        #expect(exact.actualMinutes == 20)
        #expect(exact.method == .partialBlock)
        #expect(exact.trim?.newEnd == completed(14, 20))
        // 14:21 is rounded up to 14:25; the sample keeps the real 21 minutes.
        let rounded = EffortRules.outcome(completedAt: completed(14, 21), blocks: planned, focusedSeconds: 0)
        #expect(rounded.trim?.newEnd == completed(14, 25))
        #expect(rounded.actualMinutes == 21)
        // The grid is the clock, not the block start: a block from 14:03 also ends at 14:25.
        let offset = EffortRules.outcome(completedAt: completed(14, 21), blocks: [block("o", 19, (14, 3), (15, 0))], focusedSeconds: 0)
        #expect(offset.trim?.newEnd == completed(14, 25))
        // Rounding up never extends the block: at 14:57 the end would be 15:00, the old end, so nothing is cut.
        let late = EffortRules.outcome(completedAt: completed(14, 57), blocks: planned, focusedSeconds: 0)
        #expect(late.trim == nil)
        #expect(late.actualMinutes == 57)
    }

    @Test func completionInsideBlock_withinFiveMinutes_doesNotTrim() {
        let result = EffortRules.outcome(completedAt: completed(14, 3), blocks: [block("b", 19, (14, 0), (15, 0))], focusedSeconds: 0)
        #expect(result.trim == nil)
        #expect(result.tooShortToTrim)
        #expect(result.actualMinutes == 3)
        // Exactly five minutes is enough.
        let five = EffortRules.outcome(completedAt: completed(14, 5), blocks: [block("b", 19, (14, 0), (15, 0))], focusedSeconds: 0)
        #expect(five.trim?.newEnd == completed(14, 5))
        #expect(!five.tooShortToTrim)
    }

    @Test func completionAfterBlockEnd_countsTheFullBlock() {
        let result = EffortRules.outcome(completedAt: completed(10, 5), blocks: [block("b", 19, (9, 0), (10, 0))], focusedSeconds: 0)
        #expect(result.actualMinutes == 60)
        #expect(result.method == .blocks)
        #expect(result.trim == nil)
    }

    @Test func completionHoursLater_countsTheFullBlockAndChangesNothing() {
        let result = EffortRules.outcome(completedAt: completed(17, 0), blocks: [block("b", 19, (9, 0), (10, 0))], focusedSeconds: 0)
        #expect(result.actualMinutes == 60)
        #expect(result.trim == nil)
        #expect(!result.tooShortToTrim)
    }

    @Test func noBlockNoFocus_givesNoSample() {
        let none = EffortRules.outcome(completedAt: completed(17, 0), blocks: [], focusedSeconds: 0)
        #expect(none.actualMinutes == nil && none.method == nil && none.trim == nil)
        // A block that lies ahead is not measured and not changed.
        let future = EffortRules.outcome(completedAt: completed(8, 0), blocks: [block("f", 19, (9, 0), (10, 0))], focusedSeconds: 0)
        #expect(future.actualMinutes == nil && future.trim == nil)
    }

    @Test func severalBlocks_pastOnesCountFully() {
        let blocks = [block("a", 18, (9, 0), (10, 0)), block("b", 19, (9, 0), (9, 30)), block("c", 19, (14, 0), (15, 0)),
                      block("d", 20, (9, 0), (10, 0))]
        let result = EffortRules.outcome(completedAt: completed(14, 20), blocks: blocks, focusedSeconds: 0)
        // 60 + 30 + 20; the block of the next day is neither counted nor touched.
        #expect(result.actualMinutes == 110)
        #expect(result.method == .partialBlock)
        #expect(result.trim?.blockID == "c")
    }

    @Test func recurringTask_onlyCountsSinceThePreviousCompletion() {
        let blocks = [block("old", 17, (9, 0), (10, 0)), block("prevRunning", 18, (14, 0), (14, 25)), block("new", 19, (9, 0), (9, 45))]
        let previous = completed(14, 21, day: 18)
        let result = EffortRules.outcome(completedAt: completed(12, 0), blocks: blocks, focusedSeconds: 0, since: previous)
        // The block that was running at the previous completion started before it and is not counted again.
        #expect(result.actualMinutes == 45)
        #expect(result.method == .blocks)
    }
}
