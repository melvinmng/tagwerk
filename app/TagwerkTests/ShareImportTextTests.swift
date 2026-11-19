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
        #expect(ShareNoteSheet.initialText(for: item) == "Guter Artikel\n\nAuszug daraus\n\nhttps://example.com/a")
    }
}
