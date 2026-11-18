import SwiftUI

/// One swipe recogniser for every page change: day and week in "Planen", day in "Erfassen", week in the review.
/// Right goes back, left forward. At least 80 pt sideways and twice as far sideways as up or down, so list
/// scrolling, the hour grid and dragging blocks keep working. In pushed screens drags from the leading edge
/// stay the system back gesture.
enum PageSwipe: Equatable {
    case back
    case forward

    static let minimumDistance: CGFloat = 80
    static let leadingEdgeWidth: CGFloat = 30

    static func direction(start: CGPoint, translation: CGSize, excludesLeadingEdge: Bool = false) -> PageSwipe? {
        if excludesLeadingEdge, start.x <= leadingEdgeWidth { return nil }
        guard abs(translation.width) >= minimumDistance,
              abs(translation.width) > 2 * abs(translation.height) else { return nil }
        return translation.width > 0 ? .back : .forward
    }

    /// `-1` back, `1` forward, as `PlanningModel.step` expects.
    var step: Int { self == .back ? -1 : 1 }
}

/// The gesture: recognises on release and runs `onSwipe` inside a snappy animation.
/// The start location is read in global coordinates, so the edge check holds inside list rows too.
func pageSwipeGesture(excludesLeadingEdge: Bool = false, _ onSwipe: @escaping @MainActor (PageSwipe) -> Void) -> some Gesture {
    DragGesture(minimumDistance: 30, coordinateSpace: .global).onEnded { value in
        guard let direction = PageSwipe.direction(start: value.startLocation, translation: value.translation,
                                                  excludesLeadingEdge: excludesLeadingEdge) else { return }
        MainActor.assumeIsolated { withAnimation(.snappy) { onSwipe(direction) } }
    }
}

extension View {
    /// Adds the page swipe next to the view's own gestures (taps and scrolling keep working).
    func pageSwipe(excludesLeadingEdge: Bool = false, _ onSwipe: @escaping @MainActor (PageSwipe) -> Void) -> some View {
        simultaneousGesture(pageSwipeGesture(excludesLeadingEdge: excludesLeadingEdge, onSwipe))
    }
}
