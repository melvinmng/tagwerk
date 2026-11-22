import Testing
@testable import TagwerkCore

struct BibleStudyOfferTests {
    @Test func offer_eveningIsDefault() {
        #expect(BibleStudyOffer.evening.isOffered(in: .routineEvening))
        #expect(!BibleStudyOffer.evening.isOffered(in: .routineStart))
        #expect(BibleStudyOffer(rawValue: "evening") == .evening)
    }

    @Test func offer_bothAndNever() {
        #expect(BibleStudyOffer.both.isOffered(in: .routineStart) && BibleStudyOffer.both.isOffered(in: .routineEvening))
        #expect(!BibleStudyOffer.never.isOffered(in: .routineStart) && !BibleStudyOffer.never.isOffered(in: .routineEvening))
        #expect(BibleStudyOffer.morning.isOffered(in: .routineStart) && !BibleStudyOffer.morning.isOffered(in: .routineEvening))
    }

    @Test func offer_otherRoutesAreNeverOffered() {
        for offer in BibleStudyOffer.allCases { #expect(!offer.isOffered(in: .routineWeek)) }
    }
}
