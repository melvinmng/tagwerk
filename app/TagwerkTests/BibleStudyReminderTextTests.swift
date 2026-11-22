import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Texts of the page "Bible Study" in the settings (BS6).
struct BibleStudyReminderTextTests {
    private let german = Locale(identifier: "de_DE")

    private func time(_ minutes: Int, _ weekdays: Set<Int>) -> BibleStudyReminderTime {
        BibleStudyReminderTime(minutes: minutes, weekdays: weekdays)
    }

    @Test func weekdayList_writesRunsAsRanges() {
        #expect(BibleStudyReminderText.weekdayList([2, 3, 4, 5, 6], locale: german) == "Mo–Fr")
        #expect(BibleStudyReminderText.weekdayList([7, 1], locale: german) == "Sa und So")
        #expect(BibleStudyReminderText.weekdayList([2, 4, 6], locale: german) == "Mo, Mi und Fr")
        #expect(BibleStudyReminderText.weekdayList([5], locale: german) == "Do")
        #expect(BibleStudyReminderText.weekdayList([2, 3, 4, 7, 1], locale: german) == "Mo–Mi, Sa und So")
        #expect(BibleStudyReminderText.weekdayList([], locale: german).isEmpty)
    }

    @Test func takenNote_namesDaysAndTimeOfTheOtherTime() {
        let early = time(6 * 60 + 45, [2, 3, 4, 5, 6])
        let own = time(8 * 60 + 30, [7, 1])
        let taken = BibleStudyReminderTimes.takenWeekdays(for: own, in: [early, own])
        #expect(BibleStudyReminderText.takenNote(taken: taken, others: [early, own], own: own, locale: german)
            == "Mo–Fr sind schon bei 06:45 vergeben und hier nicht wählbar.")
        let single = time(7 * 60, [7])
        #expect(BibleStudyReminderText.takenNote(taken: [7], others: [single, own], own: own, locale: german)
            == "Sa ist schon bei 07:00 vergeben und hier nicht wählbar.")
        #expect(BibleStudyReminderText.takenNote(taken: [], others: [own], own: own, locale: german) == nil)
    }
}
