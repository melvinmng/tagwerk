import Foundation
import Testing
import TagwerkCore
@testable import RemindersKit

@Suite struct SearchEventIDTests {
    /// `SearchEventID.base` lives in TagwerkCore and must stay in step with the ID rules of this package.
    @Test func baseMatchesCalendarBlockRules() {
        for id in ["abc", "abc|1795000000", "abc#cal-1|1795000000", "a|b|1795000000", "abc|x"] {
            let (scoped, _) = CalendarBlockRules.parseOccurrenceID(id)
            #expect(SearchEventID.base(id) == CalendarBlockRules.parseCalendarScope(scoped).0)
        }
    }
}
