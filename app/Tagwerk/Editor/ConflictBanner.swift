import SwiftUI

/// Banner shown when the task changed in its source while the editor was open.
struct ConflictBanner: View {
    let onReload: () -> Void
    let onSaveAnyway: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diese Aufgabe wurde geändert, seit du sie geöffnet hast.")
                .font(.subheadline)
            HStack(spacing: 16) {
                Button("Neu laden", action: onReload)
                Button("Trotzdem sichern", action: onSaveAnyway)
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
