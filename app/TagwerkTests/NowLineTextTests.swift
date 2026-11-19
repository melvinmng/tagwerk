import Foundation
import Testing
@testable import Tagwerk

struct NowLineTextTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return calendar
    }()
    let german = Locale(identifier: "de_DE")
    let english = Locale(identifier: "en_US")

    @Test func time_german_usesTwentyFourHours() {
        #expect(NowText.time(minutes: 14 * 60 + 32, calendar: calendar, locale: german) == "14:32")
    }

    @Test func time_english_usesTwelveHours() {
        let text = NowText.time(minutes: 14 * 60 + 32, calendar: calendar, locale: english)
        #expect(text.hasPrefix("2:32"))
        #expect(text.contains("PM"))
    }

    @Test func rowTitle_namesNowAndTime() {
        #expect(NowText.rowTitle(time: "14:32") == "Jetzt · 14:32")
    }

    @Test func accessibilityLabel_namesNowAndTime() {
        #expect(NowText.accessibilityLabel(time: "14:32") == "Jetzt, 14:32")
    }
}
