import CoreGraphics
import Testing
@testable import Tagwerk

struct UndoCapsuleMetricsTests {
    @Test func bottomInset_growsByTheFocusBar() {
        let hidden = UndoCapsuleMetrics.bottomInset(focusBarVisible: false)
        let shown = UndoCapsuleMetrics.bottomInset(focusBarVisible: true)
        #expect(hidden == UndoCapsuleMetrics.baseInset)
        #expect(shown - hidden == UndoCapsuleMetrics.focusBarHeight)
        #expect(hidden == CGFloat(60))
    }
}
