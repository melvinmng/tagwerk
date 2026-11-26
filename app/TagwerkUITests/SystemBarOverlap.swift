import CoreGraphics

/// Decides whether an element lies (mostly) under a system bar, i.e. under the navigation bar or the tab bar.
///
/// Used by the accessibility audit (`AuditAllowlist`): the contrast check measures text that a scroll view moved under a Liquid Glass bar
/// against the glass and not against the background the text was designed for. Plain geometry, no UIKit and no XCTest, so the rule is
/// unit tested in `TagwerkTests` (`SystemBarOverlapTests`).
enum SystemBarOverlap {
    /// A system bar of the app window with its frame in screen coordinates.
    struct Bar: Equatable {
        let name: String
        let frame: CGRect
    }

    /// The share of the visible height of an element that must lie inside a bar. The element is only partly hidden below this value,
    /// so its remaining part is measured against its own background and the finding is a real one.
    static let minimumCoveredShare: CGFloat = 0.5

    /// The share (0 to 1) of the visible height of `element` that lies in the vertical band of `bar`.
    ///
    /// - The part of the element outside `screen` is not visible and does not count (a block that continues below the tab bar and beyond
    ///   the lower edge of the screen is judged by what is on the screen).
    /// - Only the vertical extent is compared. The bars span the full width of the window in the accessibility tree, and the glass
    ///   capsule of the tab bar is inset by a few points; a text that starts a few points left of it is still measured against the glass.
    static func coveredShare(of element: CGRect, by bar: CGRect, within screen: CGRect) -> CGFloat {
        guard !element.isNull, !element.isEmpty, element.height > 0 else { return 0 }
        let visibleTop = max(element.minY, screen.minY)
        let visibleBottom = min(element.maxY, screen.maxY)
        let visibleHeight = visibleBottom - visibleTop
        guard visibleHeight > 0 else { return 0 }
        let overlapHeight = min(visibleBottom, bar.maxY) - max(visibleTop, bar.minY)
        guard overlapHeight > 0 else { return 0 }
        return overlapHeight / visibleHeight
    }

    /// The bar that covers at least `minimumCoveredShare` of the visible height of `element`; the bar with the larger share when both do.
    static func bar(covering element: CGRect, in bars: [Bar], within screen: CGRect) -> Bar? {
        bars
            .map { (bar: $0, share: coveredShare(of: element, by: $0.frame, within: screen)) }
            .filter { $0.share >= minimumCoveredShare }
            .max { $0.share < $1.share }?
            .bar
    }
}
