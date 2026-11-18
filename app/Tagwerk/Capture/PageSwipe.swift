import SwiftUI

/// Maps a horizontal swipe to a page change (day in "Erfassen", week in the review): right goes back, left forward.
/// Mostly vertical drags stay list scrolling, and drags from the leading edge stay the system back gesture.
enum PageSwipe: Equatable {
    case back
    case forward

    static let minimumDistance: CGFloat = 60
    static let leadingEdgeWidth: CGFloat = 30

    static func direction(start: CGPoint, translation: CGSize) -> PageSwipe? {
        guard start.x > leadingEdgeWidth,
              abs(translation.width) >= minimumDistance,
              abs(translation.width) > abs(translation.height) * 1.5 else { return nil }
        return translation.width > 0 ? .back : .forward
    }
}

extension View {
    /// Adds the page swipe next to the view's own gestures (taps and scrolling keep working).
    /// The start location is read in global coordinates, so the edge check holds inside list rows too.
    func pageSwipe(back: @escaping @MainActor () async -> Void, forward: @escaping @MainActor () async -> Void) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .global).onEnded { value in
                switch PageSwipe.direction(start: value.startLocation, translation: value.translation) {
                case .back: Task { await back() }
                case .forward: Task { await forward() }
                case nil: break
                }
            }
        )
    }
}
