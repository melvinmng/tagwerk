import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers
import WebKit

/// The rendered Markdown of a note. It shows the HTML of `NoteHTMLRenderer` in a web view that can do almost nothing:
///
/// - JavaScript of the page is off.
/// - The page carries a Content Security Policy (`NoteHTMLRenderer.contentSecurityPolicy`).
/// - A content rule list blocks every load over http, https, ws, wss, ftp, data and blob.
/// - The page has no base URL and the web view only follows the links this view lets through: web, mail and phone
///   links open outside the app, attachments open in Quick Look, checkbox links flip the checkbox.
/// - Images come from `tagwerk-attachment://<id>`, answered from `NoteAttachmentStore` and nowhere else.
struct NoteMarkdownView: UIViewRepresentable {
    let markdown: String
    let attachments: NoteAttachmentStore?
    /// The attachments of the note by ID: names links without a label and shows files as chips.
    var attachmentDisplays: [UUID: NoteAttachmentDisplay] = [:]
    let onToggleCheckbox: (Int) -> Void
    let onOpenAttachment: (UUID) -> Void
    /// A tap on text: the source line, or `nil` for "end of the note". Without it the page has no edit links.
    var onEdit: ((_ line: Int?) -> Void)?
    /// A tap the page did not answer: the fraction of the page height (stage B of the line mapping).
    var onUnansweredTap: ((_ fraction: Double) -> Void)?
    /// Native context menu for a long press on a link of the page (attachments, checkboxes); `nil` shows none.
    var contextMenu: ((_ url: URL) -> UIMenu?)?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onToggleCheckbox: onToggleCheckbox, onOpenAttachment: onOpenAttachment)
        coordinator.onEdit = onEdit
        coordinator.onUnansweredTap = onUnansweredTap
        coordinator.contextMenu = contextMenu
        return coordinator
    }

    /// The configuration of the web view: no JavaScript, no stored website data, attachment images through the handler.
    /// The content rule list is added by the coordinator once it is compiled.
    static func makeConfiguration(attachments: NoteAttachmentStore?) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(AttachmentSchemeHandler(attachments: attachments), forURLScheme: HTMLSanitizer.imageScheme)
        return configuration
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = Self.makeConfiguration(attachments: attachments)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // Sees every tap without taking it from the page; the page answers links, the coordinator the rest.
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.cancelsTouchesInView = false
        tap.delegate = context.coordinator
        webView.addGestureRecognizer(tap)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.allowsLinkPreview = false
        context.coordinator.webView = webView
        context.coordinator.installRules(on: configuration.userContentController)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onToggleCheckbox = onToggleCheckbox
        context.coordinator.onOpenAttachment = onOpenAttachment
        context.coordinator.onEdit = onEdit
        context.coordinator.onUnansweredTap = onUnansweredTap
        context.coordinator.contextMenu = contextMenu
        let options = NoteHTMLRenderer.RenderOptions(attachments: attachmentDisplays, editLinks: onEdit != nil)
        let body = NoteHTMLRenderer.html(markdown: markdown, options: options)
        context.coordinator.show(NoteHTMLRenderer.page(body: body, textScale: Self.textScale(for: dynamicTypeSize)))
    }

    /// The scale of the page text against the standard size: 1 for "Large", the body size of the chosen text size over 17 points.
    static func textScale(for size: DynamicTypeSize) -> Double {
        let points: Double = switch size {
        case .xSmall: 14
        case .small: 15
        case .medium: 16
        case .large: 17
        case .xLarge: 19
        case .xxLarge: 21
        case .xxxLarge: 23
        case .accessibility1: 28
        case .accessibility2: 33
        case .accessibility3: 40
        case .accessibility4: 47
        case .accessibility5: 53
        @unknown default: 17
        }
        return points / 17
    }

    // MARK: Content rules

    /// Blocks every request to the network or to inline data. The page has no reason to load any of them.
    static let contentRules = """
    [
      {"trigger": {"url-filter": "^https?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^wss?:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^ftp:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^data:"}, "action": {"type": "block"}},
      {"trigger": {"url-filter": "^blob:"}, "action": {"type": "block"}}
    ]
    """

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, UIGestureRecognizerDelegate {
        /// How long a tap waits for the page to answer it with a link navigation.
        static let unansweredTapDelay: Duration = .milliseconds(150)

        var onToggleCheckbox: (Int) -> Void
        var onOpenAttachment: (UUID) -> Void
        var onEdit: ((Int?) -> Void)?
        var onUnansweredTap: ((Double) -> Void)?
        var contextMenu: ((URL) -> UIMenu?)?
        weak var webView: WKWebView?
        private var rulesReady = false
        private var pendingPage: String?
        private var shownPage: String?
        private var restoredOffset: CGPoint?
        /// The wait of the last tap; a link navigation inside `unansweredTapDelay` cancels it.
        private(set) var pendingTap: Task<Void, Never>?
        private var lastLinkActivation: ContinuousClock.Instant?
        private let delay: Duration

        init(onToggleCheckbox: @escaping (Int) -> Void, onOpenAttachment: @escaping (UUID) -> Void,
             unansweredTapDelay: Duration = Coordinator.unansweredTapDelay) {
            self.onToggleCheckbox = onToggleCheckbox
            self.onOpenAttachment = onOpenAttachment
            self.delay = unansweredTapDelay
        }

        // MARK: Taps the page does not answer (stage B)

        /// Remembers a tap at `fraction` of the page height. When no link navigation follows within the delay, the tap was
        /// on a gap between the text, and `onUnansweredTap` gets it.
        func registerTap(fraction: Double) {
            pendingTap?.cancel()
            // The navigation may come first: a tap that was answered a moment ago is not a gap.
            if let last = lastLinkActivation, ContinuousClock.now - last < delay { return }
            pendingTap = Task { [delay] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                onUnansweredTap?(fraction)
            }
        }

        /// A link of the page was activated: the page answered the tap.
        private func registerLinkActivation() {
            lastLinkActivation = ContinuousClock.now
            pendingTap?.cancel()
        }

        @objc func tapped(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, onUnansweredTap != nil, let webView else { return }
            let scrollView = webView.scrollView
            // A tap that stops a scrolling page is not meant for the text.
            guard !scrollView.isDragging, !scrollView.isDecelerating, scrollView.contentSize.height > 0 else { return }
            let y = recognizer.location(in: webView).y
            registerTap(fraction: Double((scrollView.contentOffset.y + y) / scrollView.contentSize.height))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        // MARK: Context menu

        func webView(_ webView: WKWebView, contextMenuConfigurationForElement elementInfo: WKContextMenuElementInfo,
                     completionHandler: @escaping (UIContextMenuConfiguration?) -> Void) {
            guard let url = elementInfo.linkURL, let menu = contextMenu?(url) else {
                completionHandler(nil)
                return
            }
            completionHandler(UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu })
        }

        /// The page is loaded only after the rule list is in place, so there is no moment without it.
        func installRules(on controller: WKUserContentController) {
            Task { @MainActor in
                let list = try? await WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "TagwerkNoteRules", encodedContentRuleList: NoteMarkdownView.contentRules)
                if let list { controller.add(list) }
                // Without rules the page stays empty: the CSP alone is not what we want to rely on.
                rulesReady = list != nil
                if let page = pendingPage { pendingPage = nil; show(page) }
            }
        }

        func show(_ page: String) {
            guard page != shownPage else { return }
            guard rulesReady, let webView else {
                pendingPage = page
                return
            }
            shownPage = page
            // A reload (a flipped checkbox) keeps the scroll position.
            if webView.url != nil { restoredOffset = webView.scrollView.contentOffset }
            webView.loadHTMLString(page, baseURL: nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let offset = restoredOffset else { return }
            restoredOffset = nil
            webView.scrollView.setContentOffset(offset, animated: false)
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            let scheme = url.scheme?.lowercased() ?? ""
            // The page itself.
            if scheme == "about", navigationAction.targetFrame?.isMainFrame ?? false { return .allow }
            guard navigationAction.navigationType == .linkActivated else { return .cancel }
            await activate(url)
            return .cancel
        }

        /// Carries out a link of the page.
        func activate(_ url: URL) async {
            registerLinkActivation()
            switch url.scheme?.lowercased() ?? "" {
            case NoteHTMLRenderer.toggleScheme:
                if let index = Int(url.absoluteString.dropFirst(NoteHTMLRenderer.toggleScheme.count + 1)) { onToggleCheckbox(index) }
            case NoteEditTarget.scheme:
                if let target = NoteEditTarget.parse(url.absoluteString) { onEdit?(target.isEnd ? nil : target.line) }
            case MarkdownText.attachmentScheme:
                if let id = HTMLSanitizer.attachmentID(inReference: url.absoluteString) { onOpenAttachment(id) }
            case "http", "https", "mailto", "tel":
                await UIApplication.shared.open(url)
            default:
                break
            }
        }
    }

    // MARK: Attachment images

    /// Answers `tagwerk-attachment://<id>` with the picture of that attachment. Everything else is a 404: unknown IDs and
    /// files that are not pictures.
    @MainActor
    final class AttachmentSchemeHandler: NSObject, WKURLSchemeHandler {
        private let attachments: NoteAttachmentStore?

        init(attachments: NoteAttachmentStore?) { self.attachments = attachments }

        func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
            let url = urlSchemeTask.request.url
            guard let url, let host = url.host(), let id = UUID(uuidString: host), let record = attachments?.record(id: id),
                  let type = UTType(record.typeIdentifier), type.conforms(to: .image), let data = attachments?.data(for: id) else {
                fail(urlSchemeTask, url: url)
                return
            }
            let headers = ["Content-Type": type.preferredMIMEType ?? "image/jpeg", "Content-Length": String(data.count)]
            if let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers) {
                urlSchemeTask.didReceive(response)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } else {
                fail(urlSchemeTask, url: url)
            }
        }

        func webView(_ webView: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {}

        private func fail(_ task: any WKURLSchemeTask, url: URL?) {
            if let url, let response = HTTPURLResponse(url: url, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil) {
                task.didReceive(response)
                task.didFinish()
            } else {
                task.didFailWithError(URLError(.fileDoesNotExist))
            }
        }
    }
}
