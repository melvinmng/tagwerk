import SwiftUI

/// "↪ Unerledigtes verschieben · 3 Aufgaben ›": the row in the capacity card of today and in the evening wrap-up. It
/// only opens the sheet; nothing changes by looking at it.
struct LeftoverLine: View {
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.uturn.forward").foregroundStyle(Color.accentColor)
                Text(LeftoverSheetText.lineTitle(count: count)).font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Öffnet die Auswahl, wohin das Unerledigte soll")
    }
}
