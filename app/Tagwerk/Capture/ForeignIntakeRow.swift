import SwiftUI
import TagwerkCore

/// The row "Aus Health · andere Apps" in the list "Essen" (decision NU5b): the day total of the nutrition that other apps wrote to
/// Health, with the names of those apps. It cannot be edited or deleted here; a tap shows the values per nutrient.
struct ForeignIntakeRow: View {
    let foreign: ForeignIntake

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "heart.text.square").foregroundStyle(.pink).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text("Aus Health · andere Apps")
                let sources = IntakeFormat.foreignSources(foreign.sources)
                if !sources.isEmpty { Text(verbatim: sources).font(.caption).foregroundStyle(.secondaryText) }
            }
            Spacer()
            // Values of other apps carry no "~": Tagwerk does not know whether they are estimates. The source name is the hint.
            Text(foreign.kcal.map { IntakeFormat.kcal($0, estimated: false) } ?? "–").monospacedDigit()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("foreignIntakeRow")
    }
}

/// The values of the entries of other apps per nutrient, and why they may be missing.
struct ForeignIntakeSheet: View {
    let foreign: ForeignIntake
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row("Kalorien", foreign.kcal.map { IntakeFormat.kcal($0, estimated: false) })
                    row("Eiweiß", grams(foreign.protein))
                    row("Kohlenhydrate", grams(foreign.carbs))
                    row("Fett", grams(foreign.fat))
                    ForEach(Nutrient.allCases, id: \.self) { nutrient in
                        row(nutrient.displayName, grams(foreign.nutrients[nutrient], digits: nutrient.fractionDigits), verbatim: true)
                    }
                    row("Wasser", foreign.waterMilliliters.map { IntakeFormat.liters(Int($0.rounded())) })
                } header: {
                    let sources = IntakeFormat.foreignSources(foreign.sources)
                    if sources.isEmpty { Text("Aus Health · andere Apps") } else { Text(verbatim: sources) }
                } footer: {
                    Text("Tagwerk liest dafür Ernährungseinträge aus Health, die nicht von Tagwerk stammen. iOS teilt Tagwerk nicht mit, ob du das Lesen erlaubt hast; ohne Erlaubnis sieht es so aus, als gäbe es keine fremden Einträge. Prüfen kannst du es in Health › Teilen › Apps › Tagwerk. Ein Strich heißt: kein Wert bekannt.")
                }
            }
            .navigationTitle("Aus Health · andere Apps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func grams(_ value: Double?, digits: Int = 0) -> String? {
        value.map { String(localized: "\($0.formatted(.number.precision(.fractionLength(digits)))) g") }
    }

    @ViewBuilder
    private func row(_ title: String, _ value: String?, verbatim: Bool = false) -> some View {
        LabeledContent {
            Text(verbatim: value ?? "–").monospacedDigit()
        } label: {
            if verbatim { Text(verbatim: title) } else { Text(LocalizedStringKey(title)) }
        }
    }
}
