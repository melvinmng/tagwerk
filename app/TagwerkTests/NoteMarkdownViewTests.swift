import SwiftData
import SwiftUI
import Testing
import TagwerkCore
import UIKit
import WebKit
@testable import Tagwerk

/// The web view of the note page: the settings that make it safe, tried in a real WKWebView.
@MainActor
struct NoteMarkdownViewTests {
    /// Waits for a page to finish loading.
    final class Loader: NSObject, WKNavigationDelegate {
        var continuation: CheckedContinuation<Void, Never>?
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { continuation?.resume(); continuation = nil }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) { continuation?.resume(); continuation = nil }
    }

    private func load(_ page: String, configuration: WKWebViewConfiguration) async -> WKWebView {
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let loader = Loader()
        webView.navigationDelegate = loader
        await withCheckedContinuation { continuation in
            loader.continuation = continuation
            webView.loadHTMLString(page, baseURL: nil)
        }
        // Give a late script or image a moment; the delegate is kept alive by this local until here.
        try? await Task.sleep(for: .milliseconds(300))
        withExtendedLifetime(loader) {}
        return webView
    }

    @Test func contentRules_compile() async throws {
        let list = try await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "TagwerkNoteRulesTest",
                                                                                      encodedContentRuleList: NoteMarkdownView.contentRules)
        #expect(list != nil)
    }

    @Test func textScale_followsTheTextSize() {
        #expect(NoteMarkdownView.textScale(for: .large) == 1)
        #expect(NoteMarkdownView.textScale(for: .xSmall) < 1)
        #expect(NoteMarkdownView.textScale(for: .accessibility5) > 3)
    }

    @Test func page_withScript_doesNotRunIt() async {
        // Even a script that reached the page unsanitized must not run: JavaScript of the page is off.
        let body = "<p>Text</p><script>document.title = 'ran'</script>"
        let webView = await load(NoteHTMLRenderer.page(body: body), configuration: NoteMarkdownView.makeConfiguration(attachments: nil))
        #expect(webView.title != "ran")
        #expect(webView.configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
    }

    @Test func attachmentImage_isServedFromTheStore_andOthersAre404() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let directory = FileManager.default.temporaryDirectory.appending(path: "webview-" + UUID().uuidString, directoryHint: .isDirectory)
        let attachments = NoteAttachmentStore(context: container.mainContext, directory: directory)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 30), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 30))
        }
        let record = try attachments.addImage(image, to: UUID())
        let file = directory.deletingLastPathComponent().appending(path: "x-\(UUID().uuidString).pdf")
        try Data(repeating: 1, count: 10).write(to: file)
        let pdf = try attachments.addFile(at: file, to: UUID())
        let body = "<img id=\"a\" src=\"tagwerk-attachment://\(record.id.uuidString)\"><img id=\"b\" src=\"tagwerk-attachment://\(pdf.id.uuidString)\">"
            + "<img id=\"c\" src=\"tagwerk-attachment://\(UUID().uuidString)\">"
        // Page script is off, so the result is read from the app's own world.
        let webView = await load(NoteHTMLRenderer.page(body: body), configuration: NoteMarkdownView.makeConfiguration(attachments: attachments))
        let widths = try await webView.evaluateJavaScript("[...document.images].map(i => i.naturalWidth)", in: nil, contentWorld: .defaultClient) as? [Int]
        #expect(widths == [40, 0, 0])
    }
}
