import SwiftUI
import UIKit

/// Hold 0.3 s (moving at most 10 pt meanwhile) to pick up a grid entry, then drag it (plan-tomorrow SR1, path B).
/// As a UIKit recognizer it takes part in UIKit's arbitration with the grid's scroll view: a swipe that starts
/// before the hold is recognised makes the hold fail, so the grid scrolls; once the hold is recognised, the
/// scroll view's pan can no longer start. Locations are reported in the global space, which stays fixed while
/// the dragged entry moves.
struct HoldToMoveRecognizer: UIGestureRecognizerRepresentable {
    enum Event: Equatable {
        case began(y: CGFloat)
        case changed(y: CGFloat)
        case ended
        case cancelled
    }

    /// Off for entries that cannot move and in the "Auswählen" mode; the recognizer stays attached.
    var isEnabled: Bool
    var minimumDuration: TimeInterval = 0.3
    var allowableMovement: CGFloat = 10
    let onEvent: (Event) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        configure(recognizer)
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        configure(recognizer)
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let y = context.converter.location(in: .global).y
        switch recognizer.state {
        case .began: onEvent(.began(y: y))
        case .changed: onEvent(.changed(y: y))
        case .ended: onEvent(.ended)
        case .cancelled, .failed: onEvent(.cancelled)
        default: break
        }
    }

    private func configure(_ recognizer: UILongPressGestureRecognizer) {
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = allowableMovement
        recognizer.isEnabled = isEnabled
    }
}
