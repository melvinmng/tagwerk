import SwiftUI

/// The card "Dankbar für" above the text of a morning note and on the page of a day that only has gratitude (design NO13b).
/// It shows the gratitude of the routine record as numbered lines; the text of the note is never changed by it. A tap opens
/// the morning routine of that day, where the entries can be changed.
struct GratitudeCard: View {
    let entries: [String]
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Dankbar für").font(.subheadline.weight(.semibold))
                ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                    Text("\(index + 1). \(entry)").font(.body)
                }
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Öffnet den Tagesstart dieses Tages zum Ändern.")
        .accessibilityIdentifier("notes.gratitudeCard")
    }
}
