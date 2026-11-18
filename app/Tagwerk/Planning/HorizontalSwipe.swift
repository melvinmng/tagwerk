import SwiftUI

/// A horizontal swipe that does not compete with vertical scrolling: at least 80 pt sideways and
/// twice as far sideways as up or down. `onSwipe` gets 1 for a swipe to the left (next), -1 for previous.
func horizontalSwipe(_ onSwipe: @escaping (Int) -> Void) -> some Gesture {
    DragGesture(minimumDistance: 30).onEnded { value in
        let dx = value.translation.width, dy = value.translation.height
        guard abs(dx) > 80, abs(dx) > 2 * abs(dy) else { return }
        withAnimation(.snappy) { onSwipe(dx < 0 ? 1 : -1) }
    }
}
