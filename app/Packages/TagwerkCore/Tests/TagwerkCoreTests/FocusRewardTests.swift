import Testing
@testable import TagwerkCore

struct FocusRewardTests {
    @Test func stage_thresholds() {
        #expect(FocusReward.stage(focusedMinutes: 0) == nil)
        let expected: [(Int, FocusRewardStage)] = [(1, .one), (9, .one), (10, .two), (24, .two), (25, .three), (49, .three),
                                                   (50, .four), (89, .four), (90, .five), (400, .five)]
        for (minutes, stage) in expected {
            #expect(FocusReward.stage(focusedMinutes: minutes) == stage, "\(minutes) minutes")
        }
        #expect(FocusReward.piece(focusedMinutes: 25, outcome: .completed) == .grown(.three))
        #expect(FocusReward.piece(focusedMinutes: 0, outcome: .completed) == nil)
    }

    @Test func abortedSession_wilts() {
        #expect(FocusReward.piece(focusedMinutes: 10, outcome: .aborted) == .wilted(.two))
        #expect(FocusReward.piece(focusedMinutes: 10, outcome: .aborted)?.isWilted == true)
    }

    @Test func abortWithinAMinute_isDiscarded() {
        #expect(FocusReward.outcomeOfStop(focusedSeconds: 30) == .discarded)
        #expect(FocusReward.outcomeOfStop(focusedSeconds: 59) == .discarded)
        #expect(FocusReward.outcomeOfStop(focusedSeconds: 60) == .aborted)
        #expect(FocusReward.piece(focusedMinutes: 1, outcome: .discarded) == nil)
    }

    @Test func collectionSummary_countsGrownAndWilted() {
        let pieces: [FocusRewardPiece] = [.grown(.one), .grown(.five), .wilted(.two)]
        let summary = FocusReward.summary(of: pieces)
        #expect(summary.grown == 2 && summary.wilted == 1 && summary.total == 3)
        #expect(FocusReward.summary(of: []).total == 0)
    }
}
