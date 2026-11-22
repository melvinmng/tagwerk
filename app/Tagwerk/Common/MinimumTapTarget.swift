import SwiftUI

extension View {
    /// An icon-only button needs at least 44 × 44 points to hit (the accessibility audit measures it). The whole frame takes the tap.
    func minimumTapTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }
}
