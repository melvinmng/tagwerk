import SwiftUI

/// Banner shown when the task changed in its source while the editor was open.
struct ConflictBanner: View {
    let onReload: () -> Void
    let onSaveAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diese Aufgabe wurde geändert, seit du sie geöffnet hast.")
                .font(.subheadline)
            // Borderless buttons: inside a Form row, default buttons all fire on a tap of the row.
            HStack(spacing: 16) {
                Button("Neu laden", action: onReload)
                    .buttonStyle(.borderless)
                Button("Trotzdem sichern", action: onSaveAnyway)
                    .buttonStyle(.borderless)
                    .fontWeight(.semibold)
            }
            .font(.subheadline)
        }
        .foregroundStyle(.orange)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
    }
}
