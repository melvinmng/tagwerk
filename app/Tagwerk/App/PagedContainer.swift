import SwiftUI
import UIKit

/// Which page the container asks its content for.
enum PageSlot {
    /// The real, interactive page.
    case current
    /// A preview of the day or week before / after the shown one; shown beside the real page while dragging.
    case previous, next
    /// A preview of the page that was just paged to, laid over the real page until its content has caught up.
    case arrived
}

/// Shows the real page with the neighbouring pages built beside it (outside the screen) and moves them along with the
/// finger while it drags sideways; pages on release. There is no clip: the real page must stay the one scroll view the
/// navigation bar tracks, otherwise a large title would not show. The window clips what lies beyond the screen.
///
/// The drag is a UIKit pan recognizer (spike #134, variant C): it begins only for mostly sideways movement and
/// cancels the touches of the content once it has begun, so buttons under the finger do not fire. Vertical
/// scrolling, holding a block, dragging a task and context menus are not touched. At a blocked edge the page
/// follows as a rubber band and springs back.
struct PagedContainer<Page: View>: View {
    let canGoBack: Bool
    let canGoForward: Bool
    /// A block or task is being dragged in the grid: the container ignores every drag.
    let isLocked: Bool
    /// Pushed screens: drags that start at the leading edge stay the system back gesture.
    var excludesLeadingEdge = false
    /// Identity of the real content. After paging, the neighbour preview stays until this changes (the model has
    /// loaded the new day); `nil` pages without waiting.
    var contentID: () -> AnyHashable? = { nil }
    /// The container is as tall as the real page: the neighbours (and the arrival preview) are laid behind and over it
    /// instead of beside it in the same stack. The month needs this, its neighbour can have another number of weeks.
    var sizesToCurrentPage = false
    let onPage: (PageSwipe) -> Void
    /// A drag begins; the neighbour pages take over what they need from the shown page (e.g. its scroll offset).
    var onDragBegan: () -> Void = {}
    /// Called when the prevailing page changes during a drag (a neighbour covers more than half of the width), and with
    /// nil when it ends: the page settles, pages or the drag is cancelled. The header shows the period of that page.
    var onPrevailingPage: (PageSwipe?) -> Void = { _ in }
    /// A drag at a blocked edge ended (no later day in "Erfassen").
    let onBlockedEdge: () -> Void
    @ViewBuilder let page: (_ slot: PageSlot) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0
    @State private var width: CGFloat = 390
    /// The page change of a finished drag; runs when its animation ends or when the next drag starts.
    @State private var pendingCommit: (() -> Void)?
    @State private var commitGeneration = 0
    @State private var isArriving = false
    @State private var arrivalGeneration = 0
    @State private var prevailing: PageSwipe?

    var body: some View {
        let id = contentID()
        ZStack {
            if sizesToCurrentPage {
                page(.current).offset(x: dragOffset)
                    .background(alignment: .top) { neighbours }
                    .overlay(alignment: .top) { arrivedPreview }
            } else {
                // The neighbours stay in place beside the screen, so a drag finds them built (as in a paged scroll view)
                // and they have already taken their data.
                neighbours
                // The real page stays in place (it keeps its scroll position and state). When the model has the new page
                // at once (cached neighbour), `contentID` changes with the paging and nothing lies over it. Otherwise the
                // preview of the new page lies over it until the real content has caught up.
                page(.current).offset(x: dragOffset)
                arrivedPreview
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: id) { _, _ in isArriving = false }
        // A container that goes away in the middle of a drag must not leave the header on the neighbour.
        .onDisappear { setPrevailing(nil) }
        .gesture(PagePanRecognizer(isLocked: isLocked, excludesLeadingEdge: excludesLeadingEdge) { event in
            switch event {
            case .began:
                flush()
                onDragBegan()
            case .changed(let translation): follow(translation)
            case .ended(let translation, let predicted): release(translation: translation, predicted: predicted)
            case .cancelled:
                setPrevailing(nil)
                withAnimation(.snappy) { dragOffset = 0 }
            }
        })
    }

    @ViewBuilder
    private var neighbours: some View {
        if canGoBack { neighbour(.previous, at: dragOffset - width) }
        if canGoForward { neighbour(.next, at: dragOffset + width) }
    }

    @ViewBuilder
    private var arrivedPreview: some View {
        if isArriving {
            page(.arrived).background(.background, ignoresSafeAreaEdges: []).allowsHitTesting(false)
        }
    }

    private func neighbour(_ slot: PageSlot, at x: CGFloat) -> some View {
        page(slot).offset(x: x).allowsHitTesting(false).accessibilityHidden(true)
    }

    /// Runs the page change of an earlier drag at once (a quick second swipe starts before the first one ended).
    private func flush() {
        pendingCommit?()
        pendingCommit = nil
    }

    private func follow(_ translation: CGFloat) {
        guard !isLocked, !reduceMotion else { return }
        dragOffset = PageDrag.offset(translation: CGSize(width: translation, height: 0),
                                     canGoBack: canGoBack, canGoForward: canGoForward) ?? 0
        setPrevailing(PageDrag.prevailingPage(offset: dragOffset, width: width, canGoBack: canGoBack, canGoForward: canGoForward))
    }

    /// Reports a change of the prevailing page once, not on every move of the finger.
    private func setPrevailing(_ page: PageSwipe?) {
        guard page != prevailing else { return }
        prevailing = page
        onPrevailingPage(page)
    }

    private func release(translation: CGFloat, predicted: CGFloat) {
        let outcome = isLocked ? nil : PageDrag.outcome(translation: CGSize(width: translation, height: 0),
                                                        predicted: CGSize(width: predicted, height: 0),
                                                        width: width, canGoBack: canGoBack, canGoForward: canGoForward)
        guard let outcome else {
            setPrevailing(nil)
            let atBlockedEdge = (translation > 0 && !canGoBack) || (translation < 0 && !canGoForward)
            if atBlockedEdge, abs(translation) >= PageDrag.activationDistance { onBlockedEdge() }
            withAnimation(.snappy) { dragOffset = 0 }
            return
        }
        if reduceMotion {
            commit(outcome)
            return
        }
        commitGeneration += 1
        let generation = commitGeneration
        pendingCommit = { commit(outcome) }
        withAnimation(.snappy(duration: 0.25)) { dragOffset = outcome == .back ? width : -width }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(270))
            if commitGeneration == generation { flush() }
        }
    }

    /// Pages without animation and keeps the neighbour preview in place until the new content is loaded.
    private func commit(_ outcome: PageSwipe) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            let before = contentID()
            // The preview of the title ends in the same update in which the page changes.
            setPrevailing(nil)
            onPage(outcome)
            dragOffset = 0
            isArriving = before != nil && contentID() == before
        }
        guard isArriving else { return }
        arrivalGeneration += 1
        let generation = arrivalGeneration
        // Safety net: a failed load must not leave the preview in place.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            if arrivalGeneration == generation { isArriving = false }
        }
    }
}

/// A UIKit pan recognizer that begins only for sideways movement and cancels the touches of the content once it
/// has begun, so a button under the finger does not fire on release.
struct PagePanRecognizer: UIGestureRecognizerRepresentable {
    enum Event {
        case began
        case changed(CGFloat)
        /// Horizontal translation and where the finger would end with its current speed.
        case ended(CGFloat, CGFloat)
        case cancelled
    }

    var isLocked: Bool
    var excludesLeadingEdge: Bool
    let onEvent: (Event) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isLocked = false
        var excludesLeadingEdge = false

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard !isLocked, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let translation = pan.translation(in: pan.view)
            if excludesLeadingEdge {
                let startX = pan.location(in: nil).x - translation.x
                if startX <= PageSwipe.leadingEdgeWidth { return false }
            }
            return abs(translation.x) > PageDrag.horizontalRatio * abs(translation.y)
        }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.isLocked = isLocked
        context.coordinator.excludesLeadingEdge = excludesLeadingEdge
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began:
            onEvent(.began)
            onEvent(.changed(translation))
        case .changed:
            onEvent(.changed(translation))
        case .ended:
            let velocity = recognizer.velocity(in: recognizer.view).x
            onEvent(.ended(translation, translation + velocity * 0.25))
        case .cancelled, .failed:
            onEvent(.cancelled)
        default:
            break
        }
    }
}
