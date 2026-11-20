import Foundation
import Testing
import TagwerkCore
@testable import Tagwerk

/// Texts of shared items; invented data.
@MainActor
struct ShareImportTextTests {
    private let mail = MailMessage(subject: "Angebot", senderName: "Erika Muster", senderAddress: "erika@example.com",
                                   messageID: "abc@mail.example.com", bodyText: "Bitte bis Freitag senden.")

    @Test func mailAsNote_keepsTheTextAndTheLink() {
        let item = ShareInboxItem(createdAt: .now, target: .note, title: "Angebot", mail: mail)
        let text = ShareNoteSheet.initialText(for: item)
        #expect(text == "Angebot\n\nVon: Erika Muster\n\nBitte bis Freitag senden.\n\nmessage://%3Cabc@mail.example.com%3E")
        #expect(!text.contains("erika@example.com"))
    }

    @Test func mailAsTask_notesHaveTheNameAndTheLinkButNoAddress() {
        let item = ShareInboxItem(createdAt: .now, target: .task, title: "Angebot", mail: mail)
        let notes = ShareImportSheet.taskNotes(for: item)
        #expect(notes == "Von: Erika Muster\nmessage://%3Cabc@mail.example.com%3E")
        var anonymous = mail
        anonymous.senderName = nil
        anonymous.messageID = nil
        #expect(ShareImportSheet.taskNotes(for: ShareInboxItem(createdAt: .now, target: .task, title: "x", mail: anonymous)) == nil)
    }

    @Test func urlAsNote_hasTitleTextAndLink() {
        let item = ShareInboxItem(createdAt: .now, target: .note, title: "Guter Artikel", text: "Guter Artikel\nAuszug daraus",
                                  url: URL(string: "https://example.com/a")!)
        // No page title was told and the text has more lines than the title: the host names the link.
        #expect(ShareNoteSheet.initialText(for: item) == "Guter Artikel\n\nAuszug daraus\n\n[example.com](https://example.com/a)")
    }

    @Test func noteFromSafari_hasMarkdownLink_notRawURL() {
        // A selection shared with the page: the text, and the page as a link with its title.
        let item = ShareInboxItem(createdAt: .now, target: .note, title: "Der markierte Absatz", text: "Der markierte Absatz\nund eine zweite Zeile",
                                  url: URL(string: "https://www.example.com/artikel?id=7")!, pageTitle: "Ein guter Artikel")
        let text = ShareNoteSheet.initialText(for: item)
        #expect(text == "Der markierte Absatz\n\nund eine zweite Zeile\n\n[Ein guter Artikel](https://www.example.com/artikel?id=7)")
        // The raw address stands only inside the link, not on a line of its own.
        #expect(!text.split(separator: "\n").contains { $0.hasPrefix("https://") })
    }

    @Test func noteFromSafari_withoutSelection_isJustTheLink() {
        let item = ShareInboxItem(createdAt: .now, target: .note, title: "Ein guter Artikel", url: URL(string: "https://example.com/a")!,
                                  pageTitle: "Ein guter Artikel")
        #expect(ShareNoteSheet.initialText(for: item) == "[Ein guter Artikel](https://example.com/a)")
        // The classic page share: the title came as text, there is no page title.
        let classic = ShareInboxItem(createdAt: .now, target: .note, title: "Ein guter Artikel", text: "Ein guter Artikel",
                                     url: URL(string: "https://example.com/a")!)
        #expect(ShareNoteSheet.initialText(for: classic) == "[Ein guter Artikel](https://example.com/a)")
        // A plain address: the host is the title and the link text.
        let plain = ShareInboxItem(createdAt: .now, target: .note, title: "example.com", url: URL(string: "https://example.com/a")!)
        #expect(ShareNoteSheet.initialText(for: plain) == "[example.com](https://example.com/a)")
    }

    @Test func taskFromSafari_hasNoMarkdownLink() {
        // The task gets the raw address through its link field; its notes do not render Markdown and hold only the text.
        let item = ShareInboxItem(createdAt: .now, target: .task, title: "Der markierte Absatz", text: "Der markierte Absatz\nund mehr",
                                  url: URL(string: "https://example.com/a")!, pageTitle: "Ein guter Artikel")
        #expect(ShareImportSheet.taskNotes(for: item) == "und mehr")
        #expect(NewTaskPrefill.notes(text: "und mehr", url: item.url) == "und mehr\nhttps://example.com/a")
    }
}
