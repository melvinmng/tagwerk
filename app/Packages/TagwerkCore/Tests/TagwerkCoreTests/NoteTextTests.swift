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

    @Test func journalBibleStudyAndDreamsArePrivate_otherKindsAreNot() {
        #expect(NoteKind.journal.isPrivate && NoteKind.bibleStudy.isPrivate && NoteKind.dream.isPrivate)
        #expect(NoteKind.allCases.filter(\.isPrivate) == [.journal, .bibleStudy, .dream])
        // Only journal and Bible Study need the backup switch; dreams are backed up like the morning notes.
        #expect(NoteKind.allCases.filter { !$0.isInDefaultBackup } == [.journal, .bibleStudy])
        #expect(NoteKind(rawValue: "journal") == .journal)
    }

    @Test func onlyTheThoughtNotesMayBeSentForSuggestions() {
        #expect(NoteKind.allCases.filter(\.allowsSuggestions) == [.morning, .evening])
        // The dream log is private (never sent) but part of the default backup.
        #expect(NoteKind.dream.isPrivate && !NoteKind.dream.allowsSuggestions && NoteKind.dream.isInDefaultBackup)
    }

    @Test func title_ofMarkdownHeading_isPlain() {
        #expect(NoteText.title("# Einkauf\n- Milch") == "Einkauf")
        #expect(NoteText.preview("# Einkauf\n- Milch\n**Brot**") == "Milch\nBrot")
        // A first line that is only an image is skipped.
        #expect(NoteText.title("![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)\nUrlaub") == "Urlaub")
    }

    @Test func matches_findsWordInsideBold() {
        #expect(NoteText.matches("Das ist **wichtig** heute", query: "wichtig"))
        #expect(NoteText.matches("[Rechnung](https://example.com)", query: "rechnung"))
        #expect(!NoteText.matches("[Rechnung](https://example.com)", query: "example"))
    }

    @Test func matches_doesNotFindAttachmentUUID() {
        let text = "Foto\n![Bild](attachment:3F2504E0-4F89-41D3-9A0C-0305E82C3301)"
        #expect(!NoteText.matches(text, query: "3F2504E0"))
        #expect(!NoteText.matches(text, query: "attachment"))
        #expect(NoteText.matches(text, query: "foto"))
    }
}
