import SwiftUI
import TagwerkCore

/// The one-time consent before the first "Mit ChatGPT sortieren" or "Artikel übersetzen" (phase 5 design §5.5, mockup SPC4b).
/// One consent covers both; the text names the one that was tapped and says what the other one sends in addition.
struct ShoppingSortConsentSheet: View {
    enum Purpose { case sort, translate }

    var purpose: Purpose = .sort
    let onAgree: () -> Void
    let onDecline: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch purpose {
                    case .sort:
                        Text("Zum Sortieren sendet Tagwerk die Namen deiner offenen Artikel und die Namen deiner Kategorien an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                        point("paperplane", "**Gesendet wird:** Artikelnamen und Kategorienamen. In einer geteilten Liste auch Artikel, die andere eingetragen haben.")
                        point("eye.slash", "**Nicht gesendet werden:** Mengen, erledigte Artikel, Aufgaben, Termine, Notizen, Daten aus Health.")
                        point("hand.tap", "**Nur auf dein Tippen:** Ohne „Sortieren“ verlässt nichts das iPhone.")
                    case .translate:
                        Text("Zum Übersetzen sendet Tagwerk die Namen deiner offenen Artikel und die Zielsprache an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.")
                        point("paperplane", "**Gesendet wird:** Artikelnamen. In einer geteilten Liste auch Artikel, die andere eingetragen haben.")
                        point("eye.slash", "**Nicht gesendet werden:** Mengen, erledigte Artikel, Aufgaben, Termine, Notizen, Daten aus Health.")
                        point("hand.tap", "**Nur auf dein Tippen:** Ohne „Übersetzen“ verlässt nichts das iPhone.")
                    }
                    ConsentFollowUpPoint()
                    VStack(spacing: 10) {
                        Button(action: onAgree) {
                            Text(purpose == .sort ? "Einverstanden und sortieren" : "Einverstanden und übersetzen")
                                .fontWeight(.semibold).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        Button("Nicht jetzt", action: onDecline)
                    }
                    .padding(.top, 4)
                    Text(purpose == .sort
                         ? "Die Einwilligung gilt auch für „Artikel übersetzen“; dabei gehen die Namen deiner Artikel und die Zielsprache an ChatGPT, ohne Kategorien."
                         : "Die Einwilligung gilt auch für „Mit ChatGPT sortieren“; dabei gehen zusätzlich die Namen deiner Kategorien mit.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Du kannst das in den Einstellungen unter „Einkaufsliste“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle(purpose == .sort ? "Mit ChatGPT sortieren" : "Mit ChatGPT übersetzen")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
    }

    private func point(_ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 24)
            Text(text)
        }
    }
}

/// "Vorschlag von ChatGPT": the proposed changes, each with a checkmark, to apply or discard.
struct ShoppingSortResultSheet: View {
    let proposal: ShoppingSorter.Proposal
    let onApply: (ShoppingSorter.Proposal) -> Void
    let onDiscard: () -> Void

    @State private var deselectedCategories: Set<String> = []
    @State private var deselectedItems: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                if proposal.changes.isEmpty {
                    Text("ChatGPT schlägt keine andere Einteilung vor.").foregroundStyle(.secondary)
                }
                if !proposal.newCategories.isEmpty {
                    Section("Neue Kategorien") {
                        ForEach(proposal.newCategories, id: \.self) { name in
                            checkRow(isOn: !deselectedCategories.contains(name)) {
                                Text("Neue Kategorie „\(name)“ anlegen")
                            } toggle: {
                                toggle(name, in: &deselectedCategories)
                            }
                        }
                    }
                }
                if !proposal.changes.isEmpty {
                    Section("Änderungen") {
                        ForEach(proposal.changes) { change in
                            let categoryOff = deselectedCategories.contains(change.toCategory)
                            checkRow(isOn: !categoryOff && !deselectedItems.contains(change.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.itemName)
                                    Text(verbatim: "\(change.fromCategory) → \(change.toCategory)").font(.subheadline).foregroundStyle(.secondary)
                                }
                            } toggle: {
                                toggle(change.id, in: &deselectedItems)
                            }
                            .disabled(categoryOff)
                        }
                    }
                }
            }
            .navigationTitle("Vorschlag von ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(proposal.changes.isEmpty ? "Schließen" : "Verwerfen", action: onDiscard)
                }
                if !proposal.changes.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Vorschlag übernehmen") { onApply(selected) }.disabled(selected.changes.isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var selected: ShoppingSorter.Proposal {
        Self.selection(proposal: proposal, deselectedCategories: deselectedCategories, deselectedItems: deselectedItems)
    }

    /// What "Übernehmen" stores. `deselectedItems` holds `Change.id`s. Deselecting a new category drops the
    /// changes that would move items into it.
    static func selection(proposal: ShoppingSorter.Proposal, deselectedCategories: Set<String>,
                          deselectedItems: Set<String>) -> ShoppingSorter.Proposal {
        ShoppingSorter.Proposal(
            newCategories: proposal.newCategories.filter { !deselectedCategories.contains($0) },
            changes: proposal.changes.filter { !deselectedItems.contains($0.id) && !deselectedCategories.contains($0.toCategory) })
    }

    private func toggle(_ value: String, in set: inout Set<String>) {
        if set.contains(value) { set.remove(value) } else { set.insert(value) }
    }

    private func checkRow(isOn: Bool, @ViewBuilder label: () -> some View, toggle: @escaping () -> Void) -> some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                label().foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
