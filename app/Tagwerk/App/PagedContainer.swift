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

/// Shows the real page and, while the finger drags sideways, the neighbouring page beside it; pages on release.
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
    let onPage: (PageSwipe) -> Void
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

    var body: some View {
        let id = contentID()
        ZStack {
            if dragOffset > 0, canGoBack { page(.previous).offset(x: dragOffset - width).allowsHitTesting(false) }
            if dragOffset < 0, canGoForward { page(.next).offset(x: dragOffset + width).allowsHitTesting(false) }
            // The real page stays in place (it keeps its scroll position and state); after paging, the preview of the
            // new page lies over it until the real content has caught up.
            page(.current).offset(x: dragOffset)
            if isArriving {
                page(.arrived).background(.background).allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onChange(of: id) { _, _ in isArriving = false }
        .gesture(PagePanRecognizer(isLocked: isLocked, excludesLeadingEdge: excludesLeadingEdge) { event in
            switch event {
            case .began: flush()
            case .changed(let translation): follow(translation)
            case .ended(let translation, let predicted): release(translation: translation, predicted: predicted)
            case .cancelled: withAnimation(.snappy) { dragOffset = 0 }
            }
        })
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
    }

    private func release(translation: CGFloat, predicted: CGFloat) {
        let outcome = isLocked ? nil : PageDrag.outcome(translation: CGSize(width: translation, height: 0),
                                                        predicted: CGSize(width: predicted, height: 0),
                                                        width: width, canGoBack: canGoBack, canGoForward: canGoForward)
        guard let outcome else {
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
