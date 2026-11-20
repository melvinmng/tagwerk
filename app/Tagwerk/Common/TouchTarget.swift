import SwiftUI

/// Small controls (a glyph or a short text button in a header row) keep their look and their layout size but get a 44 pt
/// touch target and accessibility frame. Use `touchTargetLabel()` on the label of the button and `touchTargetInset` on the
/// button itself, with the space the glyph or text lacks to 44 pt.
extension View {
    /// The label takes at least 44 × 44 pt, and that whole area takes the tap.
    func touchTargetLabel(minimum: CGFloat = 44) -> some View {
        frame(minWidth: minimum, minHeight: minimum).contentShape(Rectangle())
    }

    /// Takes the extra space of `touchTargetLabel()` back, half per side: the neighbours are laid out as before and the
    /// touch target reaches over the spacing around the control.
    func touchTargetInset(horizontal: CGFloat = 0, vertical: CGFloat = 0) -> some View {
        padding(.horizontal, -horizontal).padding(.vertical, -vertical)
    }
}
