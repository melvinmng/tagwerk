import CoreGraphics

/// Rules of dragging a task from the "Ohne Uhrzeit" panel into the grid, kept apart from the view so they can be tested.
/// The drag state itself lives in a `@GestureState` of the screen: the system resets it when the gesture ends or is
/// cancelled (for example when a context menu opens), so no lock can outlive the finger.
enum TaskGripDrag {
    /// Distance in points before a touch on the grip counts as a drag (the list behind it keeps scrolling below it).
    static let startDistance: CGFloat = 8
    /// Distance from the top or bottom edge of the visible grid at which the grid scrolls on its own.
    static let edgeMargin: CGFloat = 60

    /// Whether a touch moved far enough to be a drag.
    static func hasStarted(translation: CGSize) -> Bool {
        hypot(translation.width, translation.height) >= startDistance
    }

    /// -1 scrolls the grid up, 1 down, 0 not at all. `lowerLimit` is the top of the panel, `upperLimit` the top of the
    /// visible grid.
    static func edgeScrollDirection(atY y: CGFloat, upperLimit: CGFloat, lowerLimit: CGFloat) -> Int {
        if y > lowerLimit - edgeMargin { return 1 }
        if y < upperLimit + edgeMargin { return -1 }
        return 0
    }
}
