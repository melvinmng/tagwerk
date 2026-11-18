import CoreGraphics

/// State of the hold-and-drag gesture on a grid entry (plan-tomorrow, SR1, design §13.15 G1): until the hold is
/// recognised the grid scrolls freely; from the moment it is held, scrolling is blocked, even before the finger
/// moves, and the vertical movement since the hold began is the entry's offset.
struct HoldMoveState: Equatable {
    enum Phase: Equatable {
        case idle, held, moving
    }

    private(set) var phase: Phase = .idle
    /// Vertical movement since the hold began, in points.
    private(set) var delta: CGFloat = 0
    private var startY: CGFloat = 0

    var blocksScroll: Bool { phase != .idle }

    /// The hold was recognised with the finger at `y` (any fixed coordinate space).
    mutating func begin(atY y: CGFloat) {
        phase = .held
        startY = y
        delta = 0
    }

    /// The held finger moved to `y`; ignored without a hold.
    mutating func move(toY y: CGFloat) {
        guard phase != .idle else { return }
        phase = .moving
        delta = y - startY
    }

    /// Released or cancelled: back to idle, scrolling is free again.
    mutating func end() {
        self = HoldMoveState()
    }
}
