import Foundation
import Testing
@testable import TagwerkCore

struct NoteTextTests {
    @Test func title_isFirstNonEmptyLine_max60() {
        #expect(NoteText.title("\n  Ideen Hausarbeit \nGliederung") == "Ideen Hausarbeit")
        #expect(NoteText.title(String(repeating: "x", count: 90)).count == 60)
        #expect(NoteText.title("   ") == "")
    }

    @Test func preview_isTheRest() {
        #expect(NoteText.preview("Ideen Hausarbeit\nGliederung\nQuellen") == "Gliederung\nQuellen")
        #expect(NoteText.preview("\n\nIdeen Hausarbeit\n\n Gliederung \n") == "Gliederung")
        #expect(NoteText.preview("Nur eine Zeile") == "")
        #expect(NoteText.preview("") == "")
    }

    @Test func dayKey_roundTrips_andRejectsGarbage() {
        #expect(NoteDayKey.string(PlanDay(year: 2026, month: 11, day: 8)) == "2026-11-08")
        #expect(NoteDayKey.day("2026-11-18") == PlanDay(year: 2026, month: 11, day: 18))
        #expect(NoteDayKey.day("18.11.2026") == nil)
        #expect(NoteDayKey.day("2026-13-01") == nil)
        #expect(NoteDayKey.day("2026-11-18T10:00") == nil)
    }

    @Test func kind_hasStableRawValues() {
        // Stored in the database and in backups: never rename, only append.
        #expect(NoteKind.allCases.map(\.rawValue) == ["free", "morning", "evening", "journal", "bibleStudy", "dream"])
        #expect(NoteKind(rawValue: "dream") == .dream)
    }

    @Test func matches_ignoresCaseAccentsAndOrder() {
        #expect(NoteText.matches("Gliederung für die Hausarbeit", query: "hausarbeit GLIEDERUNG"))
        #expect(NoteText.matches("Straße", query: "strasse"))
        #expect(NoteText.matches("anything", query: "  "))
        #expect(!NoteText.matches("Gliederung", query: "Gliederung Quellen"))
    }

    @Test func journalAndBibleStudyArePrivate_otherKindsAreNot() {
        #expect(NoteKind.journal.isPrivate && NoteKind.bibleStudy.isPrivate)
        #expect(NoteKind.allCases.filter(\.isPrivate) == [.journal, .bibleStudy])
        #expect(NoteKind(rawValue: "journal") == .journal)
    }

    @Test func onlyTheThoughtNotesMayBeSentForSuggestions() {
        #expect(NoteKind.allCases.filter(\.allowsSuggestions) == [.morning, .evening])
        // The dream log is not private in the sense of the backup opt-in, but it is never sent.
        #expect(!NoteKind.dream.isPrivate && !NoteKind.dream.allowsSuggestions)
    }
}
