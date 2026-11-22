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

    /// The text colour the system-scheme page computes while the web view is in the given interface style.
    private func bodyColor(style: UIUserInterfaceStyle) async throws -> String? {
        let configuration = NoteMarkdownView.makeConfiguration(attachments: nil)
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 480), configuration: configuration)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
        window.overrideUserInterfaceStyle = style
        let controller = UIViewController()
        controller.view.addSubview(webView)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        let loader = Loader()
        webView.navigationDelegate = loader
        await withCheckedContinuation { continuation in
            loader.continuation = continuation
            webView.loadHTMLString(NoteHTMLRenderer.page(body: "<p>x</p>"), baseURL: nil)
        }
        try? await Task.sleep(for: .milliseconds(500))
        withExtendedLifetime(loader) {}
        return try await webView.evaluateJavaScript("getComputedStyle(document.body).color", in: nil, contentWorld: .defaultClient) as? String
    }

    @Test func systemPage_followsTheInterfaceStyle() async throws {
        // The app uses the system scheme: the page's own media query must follow the web view's style.
        #expect(try await bodyColor(style: .dark) == "rgb(242, 242, 247)")
        #expect(try await bodyColor(style: .light) == "rgb(28, 28, 30)")
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

    /// The natural sizes of two pictures of the page, read from the app's own world (the page script is off).
    private func naturalSizes(_ body: String, attachments: NoteAttachmentStore) async throws -> [[Int]] {
        let webView = await load(NoteHTMLRenderer.page(body: body), configuration: NoteMarkdownView.makeConfiguration(attachments: attachments))
        return try await webView.evaluateJavaScript("[...document.images].map(i => [i.naturalWidth, i.naturalHeight])", in: nil,
                                                    contentWorld: .defaultClient) as? [[Int]] ?? []
    }

    /// The store and the container it lives in; the store needs the container alive.
    private func makeStore() throws -> (store: NoteAttachmentStore, container: ModelContainer) {
        let container = try ModelContainerFactory.make(inMemory: true)
        let directory = FileManager.default.temporaryDirectory.appending(path: "webview-" + UUID().uuidString, directoryHint: .isDirectory)
        return (NoteAttachmentStore(context: container.mainContext, directory: directory), container)
    }

    @Test func schemeHandler_servesFirstPageOfPDF() async throws {
        let (attachments, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let page = UIGraphicsImageRenderer(size: CGSize(width: 300, height: 400), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 300, height: 400))
        }
        let scan = try attachments.addData(ScanPDFBuilder.pdf(pages: [page, page]), fileName: "Scan.pdf", type: .pdf, role: .scan, to: UUID(), pageCount: 2)
        let sizes = try await naturalSizes("<img src=\"tagwerk-attachment://\(scan.id.uuidString)\">", attachments: attachments)
        #expect(sizes.count == 1)
        // The first page, portrait, with the longer side at the preview edge.
        #expect(sizes.first?[1] == Int(NoteMarkdownView.AttachmentSchemeHandler.pdfPreviewEdge))
        #expect(sizes.first?[0] == 768)
    }

    @Test func schemeHandler_stillRejectsOtherFiles() async throws {
        let (attachments, container) = try makeStore()
        defer { withExtendedLifetime(container) {} }
        let text = try attachments.addData(Data("Hallo".utf8), fileName: "Notiz.txt", type: .plainText, role: .plain, to: UUID())
        let strokes = try attachments.addData(Data([1, 2, 3]), fileName: "Zeichnung.strokes", type: .data, role: .strokes, to: UUID(), companionOf: UUID())
        let body = [text.id, strokes.id, UUID()].map { "<img src=\"tagwerk-attachment://\($0.uuidString)\">" }.joined()
        let sizes = try await naturalSizes(body, attachments: attachments)
        #expect(sizes == [[0, 0], [0, 0], [0, 0]])
    }

    // MARK: Taps on the page

    private func makeCoordinator(delay: Duration = .milliseconds(20)) -> NoteMarkdownView.Coordinator {
        NoteMarkdownView.Coordinator(onToggleCheckbox: { _ in }, onOpenAttachment: { _ in }, unansweredTapDelay: delay)
    }

    @Test func coordinator_editLink_callsOnEditWithLine() async {
        let coordinator = makeCoordinator()
        var lines: [Int?] = []
        coordinator.onEdit = { lines.append($0) }
        await coordinator.activate(URL(string: "tagwerk-edit:12")!)
        #expect(lines == [12])
    }

    @Test func coordinator_endLink_callsOnEditWithNil() async {
        let coordinator = makeCoordinator()
        var lines: [Int?] = []
        coordinator.onEdit = { lines.append($0) }
        await coordinator.activate(URL(string: "tagwerk-edit:end")!)
        #expect(lines.count == 1 && lines[0] == nil)
        // A malformed edit link does nothing.
        await coordinator.activate(URL(string: "tagwerk-edit:x")!)
        #expect(lines.count == 1)
    }

    @Test func coordinator_toggleLink_doesNotCallOnEdit() async {
        var toggled: [Int] = []
        let coordinator = NoteMarkdownView.Coordinator(onToggleCheckbox: { toggled.append($0) }, onOpenAttachment: { _ in })
        var edits = 0
        coordinator.onEdit = { _ in edits += 1 }
        await coordinator.activate(URL(string: "tagwerk-toggle:3")!)
        #expect(toggled == [3] && edits == 0)
    }

    @Test func coordinator_tableLink_callsOnEditTableWithIndex() async {
        let coordinator = makeCoordinator()
        var tables: [Int] = []
        var edits = 0
        coordinator.onEditTable = { tables.append($0) }
        coordinator.onEdit = { _ in edits += 1 }
        await coordinator.activate(URL(string: "tagwerk-table:2")!)
        #expect(tables == [2] && edits == 0)
        // A malformed table link does nothing.
        await coordinator.activate(URL(string: "tagwerk-table:x")!)
        #expect(tables == [2])
    }

    @Test func coordinator_unansweredTap_firesAfterDelay() async {
        let coordinator = makeCoordinator()
        var fractions: [Double] = []
        coordinator.onUnansweredTap = { fractions.append($0) }
        coordinator.registerTap(fraction: 0.4)
        #expect(fractions.isEmpty)
        await coordinator.pendingTap?.value
        #expect(fractions == [0.4])
    }

    @Test func coordinator_linkWithinWindow_cancelsUnansweredTap() async {
        let coordinator = makeCoordinator(delay: .seconds(5))
        var fractions: [Double] = []
        coordinator.onUnansweredTap = { fractions.append($0) }
        coordinator.registerTap(fraction: 0.4)
        await coordinator.activate(URL(string: "tagwerk-toggle:0")!)
        await coordinator.pendingTap?.value
        #expect(fractions.isEmpty)
    }

    @Test func coordinator_linkJustBeforeTap_isNotAGap() async {
        let coordinator = makeCoordinator(delay: .seconds(5))
        var fractions: [Double] = []
        coordinator.onUnansweredTap = { fractions.append($0) }
        await coordinator.activate(URL(string: "tagwerk-toggle:0")!)
        coordinator.registerTap(fraction: 0.4)
        await coordinator.pendingTap?.value
        #expect(fractions.isEmpty)
    }

    @Test func coordinator_secondTapReplacesTheFirst() async {
        let coordinator = makeCoordinator()
        var fractions: [Double] = []
        coordinator.onUnansweredTap = { fractions.append($0) }
        coordinator.registerTap(fraction: 0.1)
        coordinator.registerTap(fraction: 0.9)
        await coordinator.pendingTap?.value
        #expect(fractions == [0.9])
    }

    @Test func configuration_stillDisablesJavaScript() {
        let configuration = NoteMarkdownView.makeConfiguration(attachments: nil)
        #expect(configuration.defaultWebpagePreferences.allowsContentJavaScript == false)
        #expect(configuration.userContentController.userScripts.isEmpty)
    }
}
