import Foundation
import Testing
@testable import TagwerkCore

/// Fixtures are invented mails; addresses use example.com.
struct MailMessageParserTests {
    private func parse(_ eml: String) -> MailMessage? {
        MailMessageParser.parse(Data(eml.replacingOccurrences(of: "\n", with: "\r\n").utf8))
    }

    @Test func plainMail_parsesHeaders() throws {
        let mail = try #require(parse("""
        From: "Erika Muster" <erika@example.com>
        To: max@example.com
        Subject: Angebot für das Projekt
        Date: Tue, 17 Nov 2026 09:30:00 +0100
        Message-ID: <abc123.def@mail.example.com>
        Content-Type: text/plain; charset=utf-8

        Hallo Max,
        bitte schick mir das Angebot bis Freitag.
        """))
        #expect(mail.subject == "Angebot für das Projekt")
        #expect(mail.senderName == "Erika Muster")
        #expect(mail.senderAddress == "erika@example.com")
        #expect(mail.messageID == "abc123.def@mail.example.com")
        #expect(mail.bodyText == "Hallo Max,\nbitte schick mir das Angebot bis Freitag.")
        let expected = DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(identifier: "UTC"),
                                      year: 2026, month: 11, day: 17, hour: 8, minute: 30).date
        #expect(mail.date == expected)
    }

    @Test func encodedSubject_isDecoded() throws {
        let base64 = Data("Grüße aus Köln".utf8).base64EncodedString()
        let mail = try #require(parse("""
        From: =?utf-8?Q?J=C3=BCrgen_M=C3=BCller?= <j@example.com>
        Subject: =?UTF-8?B?\(base64)?=
        Message-ID: <x@example.com>

        Text
        """))
        #expect(mail.subject == "Grüße aus Köln")
        #expect(mail.senderName == "Jürgen Müller")
        let latin = try #require(parse("Subject: =?iso-8859-1?Q?Gr=FC=DFe_aus_?= =?iso-8859-1?Q?K=F6ln?=\n\nText"))
        #expect(latin.subject == "Grüße aus Köln")
    }

    @Test func foldedHeader_isJoined() throws {
        let mail = try #require(parse("""
        From: erika@example.com
        Subject: Ein sehr langer Betreff,
         der über zwei Zeilen geht
        Message-ID: <y@example.com>

        Text
        """))
        #expect(mail.subject == "Ein sehr langer Betreff, der über zwei Zeilen geht")
        #expect(mail.senderName == nil)
        #expect(mail.senderAddress == "erika@example.com")
    }

    @Test func multipartAlternative_prefersPlain() throws {
        let mail = try #require(parse("""
        From: a@example.com
        Subject: Mehrteilig
        MIME-Version: 1.0
        Content-Type: multipart/mixed; boundary="outer"

        --outer
        Content-Type: multipart/alternative; boundary="inner"

        --inner
        Content-Type: text/html; charset=utf-8

        <p>Nur <b>HTML</b></p>
        --inner
        Content-Type: text/plain; charset=utf-8

        Nur Text
        --inner--
        --outer
        Content-Type: application/pdf
        Content-Disposition: attachment; filename="x.pdf"
        Content-Transfer-Encoding: base64

        JVBERi0xLjQK
        --outer--
        """))
        #expect(mail.bodyText == "Nur Text")
    }

    @Test func htmlOnly_stripsTags() throws {
        let mail = try #require(parse("""
        From: a@example.com
        Subject: HTML
        Content-Type: text/html; charset=utf-8

        <html><body><p>Hallo <b>Welt</b></p><script>alert(1)</script><p>Zweite &amp; letzte Zeile</p></body></html>
        """))
        #expect(mail.bodyText == "Hallo Welt\nZweite & letzte Zeile")
    }

    @Test func quotedPrintable_isDecoded() throws {
        let mail = try #require(parse("""
        From: a@example.com
        Subject: QP
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: quoted-printable

        Gr=C3=BC=C3=9Fe, das ist eine lange Zeile, die umgebrochen wur=
        de.
        """))
        #expect(mail.bodyText == "Grüße, das ist eine lange Zeile, die umgebrochen wurde.")
    }

    @Test func base64Body_isDecoded() throws {
        let body = Data("Zeile eins\nZeile zwei".utf8).base64EncodedString()
        let mail = try #require(parse("""
        From: a@example.com
        Subject: B64
        Content-Type: text/plain; charset=utf-8
        Content-Transfer-Encoding: base64

        \(body)
        """))
        #expect(mail.bodyText == "Zeile eins\nZeile zwei")
    }

    @Test func garbage_returnsNil() {
        #expect(MailMessageParser.parse(Data()) == nil)
        #expect(MailMessageParser.parse(Data([0xFF, 0xFE, 0x00, 0x01])) == nil)
        #expect(MailMessageParser.parse(Data("just some words without any header".utf8)) == nil)
        // A broken multipart does not crash and leaves the text empty.
        let broken = parse("Subject: Kaputt\nContent-Type: multipart/mixed; boundary=\"x\"\n\n--x\nContent-Type: text/plain\n")
        #expect(broken?.subject == "Kaputt")
    }

    @Test func overlongBody_isCut() throws {
        let long = String(repeating: "a", count: MailMessageParser.maximumBodyLength + 500)
        let mail = try #require(parse("Subject: Lang\n\n\(long)"))
        #expect(mail.bodyText.count == MailMessageParser.maximumBodyLength)
    }
}
