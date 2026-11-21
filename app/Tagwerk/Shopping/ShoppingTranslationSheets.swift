import SwiftUI
import TagwerkCore

/// The card above the input field after the language of the list changed (mockup SPC1a): it offers to translate the open items
/// with ChatGPT or to leave them as they are.
struct ShoppingTranslationCard: View {
    let offer: ShoppingTranslationModel.Offer
    let isSignedIn: Bool
    let onTranslate: () -> Void
    let onKeep: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            Text(offer.message ?? Self.text(language: offer.language, count: offer.openCount))
                .font(.subheadline).foregroundStyle(.secondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { translateButton; keepButton }
                VStack(alignment: .leading, spacing: 8) { translateButton; keepButton }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        // A solid fill instead of a material: the audit measures text on a material against whatever scrolls behind it.
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16).padding(.top, 8)
        .accessibilityElement(children: .contain)
    }

    private var title: LocalizedStringKey {
        offer.language == .english ? "Einkaufsliste jetzt auf Englisch" : "Einkaufsliste jetzt auf Deutsch"
    }

    /// "Neue Artikel kommen auf Englisch. Die 10 offenen Artikel bleiben, wie sie sind."
    static func text(language: VoiceLanguage, count: Int) -> String {
        let first = language == .english ? String(localized: "Neue Artikel kommen auf Englisch.") : String(localized: "Neue Artikel kommen auf Deutsch.")
        let second = count == 1 ? String(localized: "Der offene Artikel bleibt, wie er ist.")
                                : String(localized: "Die \(count) offenen Artikel bleiben, wie sie sind.")
        return first + " " + second
    }

    private var translateButton: some View {
        Button(action: onTranslate) {
            VStack(spacing: 2) {
                Label(offer.message == nil ? "Mit ChatGPT übersetzen" : "Noch einmal versuchen", systemImage: "sparkles")
                if !isSignedIn { Text("Anmeldung unter Einstellungen › KI").font(.caption2) }
            }
        }
        .buttonStyle(.borderedProminent)
        .disabled(!isSignedIn)
    }

    private var keepButton: some View {
        Button("So lassen", action: onKeep).buttonStyle(.bordered)
    }
}

/// "Übersetzung": every item with its new name below the old one and a check; "Übernehmen" writes the checked ones (mockup SPC2a).
struct ShoppingTranslationResultSheet: View {
    let preview: ShoppingTranslationModel.Preview
    let language: VoiceLanguage
    let onApply: ([ShoppingTranslationPlan.Change]) -> Void
    let onDiscard: () -> Void

    @State private var deselected: Set<String> = []

    private var applicable: [ShoppingTranslationPlan.Change] { preview.changes.filter { $0.blocked == nil } }
    private var blocked: [ShoppingTranslationPlan.Change] { preview.changes.filter { $0.blocked != nil } }
    private var selected: [ShoppingTranslationPlan.Change] {
        ShoppingTranslationModel.selection(preview.changes, deselected: deselected)
    }

    var body: some View {
        NavigationStack {
            List {
                if !applicable.isEmpty {
                    Section {
                        ForEach(applicable) { change in row(change) }
                    } header: {
                        Text("\(selected.count) von \(applicable.count) Artikeln · \(ShoppingTranslationModel.languageName(language))")
                    }
                }
                if !blocked.isEmpty {
                    Section {
                        ForEach(blocked) { change in
                            HStack(spacing: 12) {
                                Image(systemName: "minus").foregroundStyle(Color.secondary).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(change.oldName)
                                    Text(reason(change)).font(.subheadline).foregroundStyle(Color.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("Bleibt unverändert")
                    }
                }
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Mengen bleiben, wie sie sind. Die Namen ändern sich in Apple Erinnerungen; in einer geteilten Liste sehen auch die anderen die neuen Namen.")
                        if preview.leftOut > 0 {
                            Text("\(preview.leftOut) weitere Artikel: danach noch einmal über „•••“ übersetzen.")
                        }
                    }
                    .font(.footnote).foregroundStyle(Color.secondary)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                }
            }
            .navigationTitle("Übersetzung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Verwerfen", action: onDiscard) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") { onApply(selected) }.disabled(selected.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ change: ShoppingTranslationPlan.Change) -> some View {
        let isOn = !deselected.contains(change.id)
        return Button {
            if isOn { deselected.insert(change.id) } else { deselected.remove(change.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.newName).foregroundStyle(.primary)
                    // A deselected item stays as it is: the row says so, like "abgewählt, bleibt „Sahne“" in the mockup.
                    Text(isOn ? change.oldName : String(localized: "\(change.oldName) · abgewählt, bleibt „\(change.oldName)“"))
                        .font(.subheadline).foregroundStyle(Color.secondary)
                }
                Spacer(minLength: 8)
                if let quantity = change.quantity { Text(quantity).font(.subheadline).foregroundStyle(Color.secondary) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(change, isSelected: isOn))
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }

    /// "Äpfel wird Apples, ausgewählt"
    static func accessibilityLabel(_ change: ShoppingTranslationPlan.Change, isSelected: Bool) -> String {
        let state = isSelected ? String(localized: "ausgewählt") : String(localized: "nicht ausgewählt")
        return String(localized: "\(change.oldName) wird \(change.newName), \(state)")
    }

    private func reason(_ change: ShoppingTranslationPlan.Change) -> String {
        switch change.blocked {
        case .alreadyOnList, .sameTranslationTwice:
            String(localized: "„\(change.newName)“ steht dann schon auf der Liste")
        case nil:
            ""
        }
    }
}
