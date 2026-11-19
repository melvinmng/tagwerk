import Foundation
import Testing
@testable import TagwerkCore

struct SharePayloadTests {
    private let page = URL(string: "https://www.example.com/artikel/1")!

    @Test func url_withText_usesTextAsTitle() {
        let payload = SharePayload.classify([.url(page), .text("Ein guter Artikel")])
        #expect(payload?.kind == .url)
        #expect(payload?.title == "Ein guter Artikel")
        #expect(payload?.url == page)
    }

    @Test func url_withoutText_usesHost() {
        let payload = SharePayload.classify([.url(page)])
        #expect(payload?.title == "example.com")
    }

    @Test func url_textEqualToTheLink_isNotATitle() {
        let payload = SharePayload.classify([.url(page), .text(page.absoluteString)])
        #expect(payload?.title == "example.com")
        #expect(payload?.text == nil)
    }

    @Test func emlFile_isMail() {
        let byType = SharePayload.classify([.file(typeIdentifier: "com.apple.mail.email", name: "Angebot.eml", byteCount: 900)])
        #expect(byType?.kind == .mail)
        #expect(byType?.title == "Angebot")
        let byExtension = SharePayload.classify([.file(typeIdentifier: "public.data", name: "Angebot.eml", byteCount: 900)])
        #expect(byExtension?.kind == .mail)
        #expect(byExtension?.suggestedTarget == .mailTask)
    }

    @Test func image_isImage() {
        let payload = SharePayload.classify([.file(typeIdentifier: "public.jpeg", name: "IMG_1.jpg", byteCount: 4_000)])
        #expect(payload?.kind == .image)
        #expect(payload?.fileNames == ["IMG_1.jpg"])
    }

    @Test func mixedFiles_firstDecides() {
        let imageFirst = SharePayload.classify([.file(typeIdentifier: "public.png", name: "a.png", byteCount: 1),
                                                .file(typeIdentifier: "com.adobe.pdf", name: "b.pdf", byteCount: 1)])
        #expect(imageFirst?.kind == .image)
        #expect(imageFirst?.fileNames == ["a.png", "b.pdf"])
        let pdfFirst = SharePayload.classify([.file(typeIdentifier: "com.adobe.pdf", name: "b.pdf", byteCount: 1),
                                              .file(typeIdentifier: "public.png", name: "a.png", byteCount: 1)])
        #expect(pdfFirst?.kind == .file)
    }

    @Test func whitespaceOnly_isNil() {
        #expect(SharePayload.classify([]) == nil)
        #expect(SharePayload.classify([.text("  \n\t ")]) == nil)
        #expect(SharePayload.classify([.url(URL(string: "ftp://example.com/x")!)]) == nil)
    }

    @Test func longText_titleIsFirstLineCut() {
        let long = String(repeating: "a", count: 300)
        let payload = SharePayload.classify([.text("\n  \(long)\nzweite Zeile")])
        #expect(payload?.kind == .text)
        #expect(payload?.title == String(repeating: "a", count: SharePayload.maximumTitleLength))
        #expect(payload?.suggestedTarget == .note)
    }

    @Test func recipeURL_suggestsRecipe() {
        let recipe = SharePayload.classify([.url(URL(string: "https://www.chefkoch.de/rezepte/123/Lasagne.html")!)])
        #expect(recipe?.suggestedTarget == .recipe)
        let byTitle = SharePayload.classify([.url(page), .text("Das beste Rezept für Pizza")])
        #expect(byTitle?.suggestedTarget == .recipe)
        #expect(SharePayload.classify([.url(page)])?.suggestedTarget == .task)
    }

    @Test func shortLines_suggestShopping() {
        #expect(SharePayload.classify([.text("Milch\nEier\nBrot")])?.suggestedTarget == .shopping)
        #expect(SharePayload.classify([.text("Milch\nEier\nBrot\nButter")])?.suggestedTarget == .note)
        let longLine = String(repeating: "x", count: 41)
        #expect(SharePayload.classify([.text(longLine)])?.suggestedTarget == .note)
    }

    @Test func pdf_suggestsNote() {
        let payload = SharePayload.classify([.file(typeIdentifier: "com.adobe.pdf", name: "Vertrag.pdf", byteCount: 5_000)])
        #expect(payload?.kind == .file)
        #expect(payload?.suggestedTarget == .note)
    }

    @Test func targets_offerMailTaskOnlyForMailOrText() {
        #expect(SharePayload.classify([.url(page)])?.availableTargets.contains(.mailTask) == false)
        #expect(SharePayload.classify([.text("Hallo Welt")])?.availableTargets.contains(.mailTask) == true)
        let mail = SharePayload.classify([.file(typeIdentifier: "public.data", name: "x.eml", byteCount: 1)])
        #expect(mail?.availableTargets == [.task, .note, .mailTask])
    }
}
