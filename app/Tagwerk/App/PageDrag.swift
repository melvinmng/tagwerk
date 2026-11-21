import CoreGraphics

/// Rules for dragging a page with the finger: when a drag counts as a page drag, how far the page follows, and
/// what happens on release. The thresholds follow `PageSwipe`: at least 80 pt sideways and twice as far sideways
/// as up or down, so scrolling, the hour grid and dragging blocks keep working.
struct PageDrag {
    /// Movement before a drag is classified (page drag or something else).
    static let activationDistance: CGFloat = 12
    /// Sideways movement must be at least this many times the vertical movement.
    static let horizontalRatio: CGFloat = 2
    /// Share of the drag that a page follows at a blocked edge, and the most it moves there.
    static let rubberBandFactor: CGFloat = 0.25
    static let rubberBandLimit: CGFloat = 40
    /// A flick pages when the finger would end this far (share of the width) from where it started ...
    static let flickFraction: CGFloat = 0.5
    /// ... and has already moved at least this far.
    static let flickMinimumDistance: CGFloat = 24

    /// Horizontal offset to show while dragging; nil while the drag is not (yet) horizontal.
    /// At a blocked edge (no later day in "Erfassen") the offset is damped to a rubber band.
    static func offset(translation: CGSize, canGoBack: Bool, canGoForward: Bool) -> CGFloat? {
        guard isHorizontal(translation) else { return nil }
        let blocked = translation.width > 0 ? !canGoBack : !canGoForward
        guard blocked else { return translation.width }
        let damped = min(abs(translation.width) * rubberBandFactor, rubberBandLimit)
        return translation.width > 0 ? damped : -damped
    }

    /// Decision on release: page back, forward or settle, from translation and predicted end translation.
    static func outcome(translation: CGSize, predicted: CGSize, width: CGFloat,
                        canGoBack: Bool, canGoForward: Bool) -> PageSwipe? {
        guard isHorizontal(translation) else { return nil }
        let direction: PageSwipe = translation.width > 0 ? .back : .forward
        guard direction == .back ? canGoBack : canGoForward else { return nil }
        let distance = abs(translation.width)
        if distance >= min(PageSwipe.minimumDistance, width / 3) { return direction }
        let flicks = distance >= flickMinimumDistance
            && abs(predicted.width) >= width * flickFraction
            && (predicted.width > 0) == (translation.width > 0)
        return flicks ? direction : nil
    }

    /// Past the activation distance and clearly sideways.
    static func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) >= activationDistance && abs(translation.width) > horizontalRatio * abs(translation.height)
    }

    /// The neighbour that covers more than half of the width during a drag; nil while the shown page prevails.
    /// A damped rubber band at a blocked edge never gets there, and a blocked direction never prevails.
    static func prevailingPage(offset: CGFloat, width: CGFloat, canGoBack: Bool, canGoForward: Bool) -> PageSwipe? {
        guard width > 0 else { return nil }
        if offset > width / 2, canGoBack { return .back }
        if offset < -width / 2, canGoForward { return .forward }
        return nil
    }
}
