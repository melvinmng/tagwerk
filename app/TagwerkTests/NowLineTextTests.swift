import Foundation
import Testing
import TagwerkCore
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

    @Test func runningDetail_inBothLanguages() {
        #expect(NowText.runningDetail(remainingMinutes: 28) == "läuft · noch 28 min")
        #expect(Localized.string("läuft · noch \(28) min", in: .english, bundle: .main) == "running · 28 min left")
    }

    @Test func runningAccessibility_pluralForms() {
        #expect(NowText.runningAccessibility(remainingMinutes: 28) == "läuft, noch 28 Minuten")
        #expect(NowText.runningAccessibility(remainingMinutes: 1) == "läuft, noch 1 Minute")
        #expect(Localized.string("läuft, noch \(28) Minuten", in: .english, bundle: .main) == "running, 28 minutes left")
        #expect(Localized.string("läuft, noch \(1) Minuten", in: .english, bundle: .main) == "running, 1 minute left")
    }
}
