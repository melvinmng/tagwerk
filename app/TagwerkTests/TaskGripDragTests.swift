import CoreGraphics
import Testing
@testable import Tagwerk

struct TaskGripDragTests {
    @Test func hasStarted_belowDistance_isFalse() {
        #expect(!TaskGripDrag.hasStarted(translation: .zero))
        #expect(!TaskGripDrag.hasStarted(translation: CGSize(width: 5, height: 5)))
    }

    @Test func hasStarted_atOrBeyondDistance_isTrue() {
        #expect(TaskGripDrag.hasStarted(translation: CGSize(width: 0, height: 8)))
        #expect(TaskGripDrag.hasStarted(translation: CGSize(width: -6, height: 6)))
    }

    @Test func edgeScrollDirection_nearBottom_scrollsDown() {
        #expect(TaskGripDrag.edgeScrollDirection(atY: 560, upperLimit: 100, lowerLimit: 600) == 1)
        // Past the panel's top the direction still points down.
        #expect(TaskGripDrag.edgeScrollDirection(atY: 700, upperLimit: 100, lowerLimit: 600) == 1)
    }

    @Test func edgeScrollDirection_nearTop_scrollsUp() {
        #expect(TaskGripDrag.edgeScrollDirection(atY: 130, upperLimit: 100, lowerLimit: 600) == -1)
    }

    @Test func edgeScrollDirection_inTheMiddle_doesNotScroll() {
        #expect(TaskGripDrag.edgeScrollDirection(atY: 350, upperLimit: 100, lowerLimit: 600) == 0)
        // Exactly at the margin is still inside.
        #expect(TaskGripDrag.edgeScrollDirection(atY: 540, upperLimit: 100, lowerLimit: 600) == 0)
        #expect(TaskGripDrag.edgeScrollDirection(atY: 160, upperLimit: 100, lowerLimit: 600) == 0)
    }
}
