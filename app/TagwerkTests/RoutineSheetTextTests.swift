import Foundation
import Testing
@testable import Tagwerk

/// Texts of the routine sheets (design group 2, strand RO).
struct RoutineSheetTextTests {
    @Test func focusHint_counts() {
        #expect(MorningSheet.focusHint(chosen: 1, maximum: 3) == "In „Planen“ setzen · 1 von 3 gewählt")
        #expect(MorningSheet.focusHint(chosen: 0, maximum: 3) == "In „Planen“ setzen · 0 von 3 gewählt")
    }
}
