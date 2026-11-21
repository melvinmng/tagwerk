import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Reference: Wednesday, 18 Nov 2026 (KW 47); the week runs Mon 16 – Sun 22.
struct PlanHeaderTextTests {
    let calendar = Calendar.tagwerk
    let today = PlanDay(year: 2026, month: 11, day: 18)
    let week = PlanDay(year: 2026, month: 11, day: 16)...PlanDay(year: 2026, month: 11, day: 22)

    private func caption(_ scope: PlanScope, _ anchor: PlanDay, range: ClosedRange<PlanDay>? = nil) -> String {
        PlanHeaderText.caption(scope: scope, anchor: anchor, today: today, range: range ?? anchor...anchor, calendar: calendar)
    }

    @Test func titleCandidates_shortenWithoutEllipsis() {
        let thursday = PlanDay(year: 2026, month: 11, day: 19)
        #expect(PlanHeaderText.titleCandidates(scope: .day, anchor: thursday, range: thursday...thursday, calendar: calendar)
                == ["Donnerstag, 19. Nov.", "Do. 19. Nov.", "19. Nov."])
        #expect(PlanHeaderText.titleCandidates(scope: .week, anchor: today, range: week, calendar: calendar)
                == ["16.–22. Nov.", "16.–22.11."])
        #expect(PlanHeaderText.titleCandidates(scope: .month, anchor: today, range: week, calendar: calendar) == ["November", "Nov"])
    }

    @Test func displayedTitle_isFixedPerScopeAndShortWithLargeText() {
        let thursday = PlanDay(year: 2026, month: 11, day: 19)
        func shown(_ scope: PlanScope, large: Bool) -> String {
            PlanHeaderText.displayedTitle(scope: scope, anchor: thursday, range: scope == .week ? week : thursday...thursday,
                                          calendar: calendar, largeText: large)
        }
        #expect(shown(.day, large: false) == "Do. 19. Nov.")
        #expect(shown(.day, large: true) == "19. Nov.")
        #expect(shown(.week, large: false) == "16.–22. Nov.")
        #expect(shown(.week, large: true) == "16.–22.11.")
        #expect(shown(.month, large: false) == "November")
        #expect(shown(.month, large: true) == "Nov")
    }

    @Test func titleCandidates_startWithTheFullTitle() {
        for scope in PlanScope.allCases {
            let candidates = PlanHeaderText.titleCandidates(scope: scope, anchor: today, range: week, calendar: calendar)
            #expect(candidates.first == PlanHeaderText.title(scope: scope, anchor: today, range: week, calendar: calendar))
        }
    }

    @Test func dayCaption_relativeDays() {
        #expect(caption(.day, today) == "HEUTE · KW 47")
        #expect(caption(.day, PlanDay(year: 2026, month: 11, day: 19)) == "MORGEN · KW 47")
        #expect(caption(.day, PlanDay(year: 2026, month: 11, day: 17)) == "GESTERN · KW 47")
        #expect(caption(.day, PlanDay(year: 2026, month: 11, day: 21)) == "IN 3 TAGEN · KW 47")
        #expect(caption(.day, PlanDay(year: 2026, month: 11, day: 15)) == "VOR 3 TAGEN · KW 46")
    }

    @Test func weekCaption_currentAndOther() {
        #expect(caption(.week, today, range: week) == "DIESE WOCHE · KW 47")
        let next = PlanDay(year: 2026, month: 11, day: 23)...PlanDay(year: 2026, month: 11, day: 29)
        #expect(caption(.week, PlanDay(year: 2026, month: 11, day: 25), range: next) == "KW 48")
    }

    @Test func monthCaption_currentAndOther() {
        let november = PlanDay(year: 2026, month: 10, day: 26)...PlanDay(year: 2026, month: 12, day: 6)
        #expect(caption(.month, PlanDay(year: 2026, month: 11, day: 1), range: november) == "DIESER MONAT · 2026")
        #expect(caption(.month, PlanDay(year: 2025, month: 11, day: 1)) == "2025")
    }

    @Test func isCurrent_perScope() {
        #expect(PlanHeaderText.isCurrent(scope: .day, anchor: today, today: today, range: today...today))
        #expect(!PlanHeaderText.isCurrent(scope: .day, anchor: PlanDay(year: 2026, month: 11, day: 19), today: today,
                                          range: PlanDay(year: 2026, month: 11, day: 19)...PlanDay(year: 2026, month: 11, day: 19)))
        #expect(PlanHeaderText.isCurrent(scope: .week, anchor: today, today: today, range: week))
        // The December grid shows the last days of November, but December is not the current month.
        let decemberGrid = PlanDay(year: 2026, month: 11, day: 30)...PlanDay(year: 2027, month: 1, day: 3)
        #expect(!PlanHeaderText.isCurrent(scope: .month, anchor: PlanDay(year: 2026, month: 12, day: 1), today: PlanDay(year: 2026, month: 11, day: 30),
                                          range: decemberGrid))
    }

    @Test func stepLabels() {
        #expect(PlanHeaderText.stepLabel(scope: .day, direction: -1) == "Vorheriger Tag")
        #expect(PlanHeaderText.stepLabel(scope: .week, direction: 1) == "Nächste Woche")
        #expect(PlanHeaderText.stepLabel(scope: .month, direction: -1) == "Vorheriger Monat")
    }

    @Test func statusLine_appendsTheHabitCounter() {
        #expect(PlanHeaderText.statusLine(intake: "~1.240 / 2.300 kcal · 2,1 l", habits: HabitCounter(done: 3, total: 5))
                == "~1.240 / 2.300 kcal · 2,1 l · ✓ 3 von 5")
    }

    @Test func statusLine_counterAlone() {
        #expect(PlanHeaderText.statusLine(intake: nil, habits: HabitCounter(done: 3, total: 5)) == "✓ 3 von 5")
    }

    @Test func statusLine_withoutBoth_isNil() {
        #expect(PlanHeaderText.statusLine(intake: nil, habits: nil) == nil)
        #expect(PlanHeaderText.statusLine(intake: "~1.240 / 2.300 kcal", habits: nil) == "~1.240 / 2.300 kcal")
    }

    // MARK: Title while dragging (PL6b)

    @Test func shiftedAnchor_movesByTheScope() {
        #expect(PlanHeaderText.shiftedAnchor(scope: .day, anchor: today, step: 1, calendar: calendar)
                == PlanDay(year: 2026, month: 11, day: 19))
        #expect(PlanHeaderText.shiftedAnchor(scope: .day, anchor: today, step: -1, calendar: calendar)
                == PlanDay(year: 2026, month: 11, day: 17))
        #expect(PlanHeaderText.shiftedAnchor(scope: .week, anchor: today, step: 1, calendar: calendar)
                == PlanDay(year: 2026, month: 11, day: 25))
        #expect(PlanHeaderText.shiftedAnchor(scope: .month, anchor: today, step: 1, calendar: calendar)
                == PlanDay(year: 2026, month: 12, day: 18))
        #expect(PlanHeaderText.shiftedAnchor(scope: .month, anchor: today, step: -1, calendar: calendar)
                == PlanDay(year: 2026, month: 10, day: 18))
    }

    // MARK: Title by available width (PL16b)

    /// Ten points per character: the tests do not depend on the font.
    private let tenPerCharacter: (String) -> CGFloat = { CGFloat($0.count) * 10 }

    @Test func fittingTitle_takesTheLongestThatFits() {
        let candidates = ["Donnerstag, 19. Nov.", "Do. 19. Nov.", "19. Nov."]
        #expect(PlanHeaderText.fittingTitle(candidates, availableWidth: 250, width: tenPerCharacter) == "Donnerstag, 19. Nov.")
        #expect(PlanHeaderText.fittingTitle(candidates, availableWidth: 200, width: tenPerCharacter) == "Donnerstag, 19. Nov.")
        #expect(PlanHeaderText.fittingTitle(candidates, availableWidth: 150, width: tenPerCharacter) == "Do. 19. Nov.")
        #expect(PlanHeaderText.fittingTitle(candidates, availableWidth: 90, width: tenPerCharacter) == "19. Nov.")
    }

    @Test func fittingTitle_nothingFits_takesTheShortest() {
        let candidates = ["Donnerstag, 19. Nov.", "Do. 19. Nov.", "19. Nov."]
        #expect(PlanHeaderText.fittingTitle(candidates, availableWidth: 20, width: tenPerCharacter) == "19. Nov.")
        #expect(PlanHeaderText.fittingTitle(candidates, availableWidth: 0, width: tenPerCharacter) == "19. Nov.")
    }

    @Test func fittingTitle_singleCandidate_isReturnedAlways() {
        #expect(PlanHeaderText.fittingTitle(["November"], availableWidth: 5, width: tenPerCharacter) == "November")
    }

    @Test func displayedTitle_withoutWidth_keepsTheFixedForm() {
        let thursday = PlanDay(year: 2026, month: 11, day: 19)
        let fixed = PlanHeaderText.displayedTitle(scope: .day, anchor: thursday, range: thursday...thursday, calendar: calendar,
                                                  largeText: false)
        #expect(fixed == "Do. 19. Nov.")
        let explicit = PlanHeaderText.displayedTitle(scope: .day, anchor: thursday, range: thursday...thursday, calendar: calendar,
                                                     largeText: false, availableWidth: nil)
        #expect(explicit == fixed)
    }

    @Test func displayedTitle_withWidth_choosesByWidthAlsoWithLargeText() {
        let thursday = PlanDay(year: 2026, month: 11, day: 19)
        func shown(width: CGFloat, large: Bool) -> String {
            PlanHeaderText.displayedTitle(scope: .day, anchor: thursday, range: thursday...thursday, calendar: calendar,
                                          largeText: large, availableWidth: width, width: tenPerCharacter)
        }
        // "Donnerstag, 19. Nov." is 20 characters, "Do. 19. Nov." 12.
        #expect(shown(width: 220, large: false) == "Donnerstag, 19. Nov.")
        #expect(shown(width: 130, large: false) == "Do. 19. Nov.")
        #expect(shown(width: 60, large: false) == "19. Nov.")
        // The measured font grows with the text size, so the same rule holds with large text.
        #expect(shown(width: 220, large: true) == "Donnerstag, 19. Nov.")
    }

    @Test func headerMetrics_availableWidth_isTheWindowMinusTheReserve() {
        #expect(PlanHeaderMetrics.availableTitleWidth(windowWidth: 402) == 402 - PlanHeaderMetrics.trailingReserve)
        #expect(PlanHeaderMetrics.availableTitleWidth(windowWidth: 402, typeSize: .xxxLarge)
                == 402 - PlanHeaderMetrics.trailingReserveLargeText)
        #expect(PlanHeaderMetrics.availableTitleWidth(windowWidth: 100) == 0)
    }

    @Test func headerMetrics_titleWidth_growsWithTextAndTextSize() {
        let short = PlanHeaderMetrics.titleWidth("19. Nov.", typeSize: .large)
        let long = PlanHeaderMetrics.titleWidth("Donnerstag, 19. Nov.", typeSize: .large)
        #expect(short > 0)
        #expect(long > short)
        #expect(PlanHeaderMetrics.titleWidth("Donnerstag, 19. Nov.", typeSize: .xxLarge) > long)
        // The navigation bar does not grow its text beyond XXXL, so neither does the measurement.
        #expect(PlanHeaderMetrics.titleWidth("Donnerstag, 19. Nov.", typeSize: .accessibility3)
                == PlanHeaderMetrics.titleWidth("Donnerstag, 19. Nov.", typeSize: .xxxLarge))
        #expect(PlanHeaderMetrics.titleWidth("Donnerstag, 19. Nov.", typeSize: .xxxLarge)
                == PlanHeaderMetrics.titleWidth("Donnerstag, 19. Nov.", typeSize: .xxLarge))
    }
}

