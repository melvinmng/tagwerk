import CoreGraphics
import Testing
@testable import Tagwerk

/// Hold and drag of a grid entry (plan-tomorrow, SR1): scrolling stays free until the hold is recognised.
struct HoldMoveStateTests {
    @Test func idle_doesNotBlockScroll() {
        let state = HoldMoveState()
        #expect(state.phase == .idle)
        #expect(!state.blocksScroll)
        #expect(state.delta == 0)
    }

    @Test func held_blocksScroll_beforeAnyMovement() {
        var state = HoldMoveState()
        state.begin(atY: 200)
        #expect(state.phase == .held)
        #expect(state.blocksScroll)
        #expect(state.delta == 0)
    }

    @Test func moving_accumulatesDelta() {
        var state = HoldMoveState()
        state.begin(atY: 100)
        state.move(toY: 130)
        #expect(state.phase == .moving)
        #expect(state.delta == 30)
        state.move(toY: 90)
        #expect(state.delta == -10)
        #expect(state.blocksScroll)
    }

    @Test func move_withoutHold_isIgnored() {
        var state = HoldMoveState()
        state.move(toY: 50)
        #expect(state == HoldMoveState())
    }

    @Test func ended_orCancelled_returnsToIdle() {
        var ended = HoldMoveState()
        ended.begin(atY: 10)
        ended.move(toY: 40)
        ended.end()
        #expect(ended == HoldMoveState())
        #expect(!ended.blocksScroll)

        var cancelled = HoldMoveState()
        cancelled.begin(atY: 10)
        cancelled.end()
        #expect(cancelled == HoldMoveState())
    }
}
