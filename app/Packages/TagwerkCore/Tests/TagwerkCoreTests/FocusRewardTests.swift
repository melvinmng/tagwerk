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
        #expect(FocusReward.piece(focusedMinutes: 25, outcome: .completed) == .completed(.three))
        #expect(FocusReward.piece(focusedMinutes: 0, outcome: .completed) == nil)
    }

    @Test func piece_aborted_keepsTheReachedStage_asEndedEarly() {
        #expect(FocusReward.piece(focusedMinutes: 10, outcome: .aborted) == .endedEarly(.two))
        #expect(FocusReward.piece(focusedMinutes: 10, outcome: .aborted)?.isEndedEarly == true)
        #expect(FocusReward.piece(focusedMinutes: 10, outcome: .aborted)?.stage == .two)
    }

    @Test func piece_completedEarly_hasTheReachedStage() {
        // Finished with "Erledigt" after 18 of 25 minutes: the brick of the reached stage, not marked as ended early.
        let piece = FocusReward.piece(focusedMinutes: 18, outcome: .completed)
        #expect(piece == .completed(.two))
        #expect(piece?.isEndedEarly == false)
    }

    @Test func abortWithinAMinute_isDiscarded() {
        #expect(FocusReward.outcomeOfStop(focusedSeconds: 30) == .discarded)
        #expect(FocusReward.outcomeOfStop(focusedSeconds: 59) == .discarded)
        #expect(FocusReward.outcomeOfStop(focusedSeconds: 60) == .aborted)
        #expect(FocusReward.piece(focusedMinutes: 1, outcome: .discarded) == nil)
    }

    @Test func summary_countsEndedEarly() {
        let pieces: [FocusRewardPiece] = [.completed(.one), .completed(.five), .endedEarly(.two)]
        let summary = FocusReward.summary(of: pieces)
        #expect(summary.completed == 2 && summary.endedEarly == 1 && summary.total == 3)
        #expect(FocusReward.summary(of: []).total == 0)
    }
}
