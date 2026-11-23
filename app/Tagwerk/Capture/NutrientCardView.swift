import SwiftUI
import TagwerkCore

/// The card "Nährwerte" in "Erfassen" (decision NU2b): one bar row per nutrient. Protein, carbohydrates and fat are always shown;
/// the further nutrients fold out with "Mehr" / "Weniger", and the state is remembered per device.
struct NutrientCardView: View {
    let rows: [NutrientRow]
    @AppStorage("tagwerk.nutrientCardExpanded") private var expanded = true

    private var hasFurtherRows: Bool { rows.contains { !$0.kind.isMacro } }
    private var shownRows: [NutrientRow] { expanded ? rows : rows.filter { $0.kind.isMacro } }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Nährwerte").font(.headline)
                Spacer()
                if hasFurtherRows {
                    Button(expanded ? "Weniger" : "Mehr") { withAnimation(.snappy) { expanded.toggle() } }
                        .font(.subheadline)
                        // Borderless: only the button reacts, not the whole card row.
                        .buttonStyle(.borderless)
                        .accessibilityIdentifier("nutrientCard.toggle")
                }
            }
            ForEach(shownRows) { row in
                bar(row)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nutrientCard")
    }

    private func bar(_ row: NutrientRow) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(verbatim: row.title).font(.subheadline)
                Spacer(minLength: 8)
                Text(verbatim: row.valueText)
                    .font(.subheadline).monospacedDigit()
                    .foregroundStyle(row.isOverLimit ? Color.orangeText : Color.secondaryText)
                    .multilineTextAlignment(.trailing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let progress = row.progress {
                ProgressView(value: min(1, max(0, progress))).tint(row.isOverLimit ? .orange : Self.tint(row.kind))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.title))
        .accessibilityValue(Text(verbatim: row.spokenValue + (row.isOverLimit ? ", " + String(localized: "Obergrenze überschritten") : "")))
    }

    private static func tint(_ kind: NutrientRow.Kind) -> Color {
        switch kind {
        case .protein: .pink
        case .carbohydrates: .blue
        case .fat: .yellow
        case .further(let nutrient):
            switch nutrient {
            case .fiber: .green
            case .sugar: .purple
            case .saturatedFat: .brown
            case .salt: .gray
            }
        }
    }
}
