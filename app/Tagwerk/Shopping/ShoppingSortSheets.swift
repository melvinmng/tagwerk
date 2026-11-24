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
                        .font(.footnote).foregroundStyle(.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Du kannst das in den Einstellungen unter „Einkaufsliste“ widerrufen.")
                        .font(.footnote).foregroundStyle(.secondaryText)
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

/// "Vorschlag von ChatGPT": the proposed changes, each with a checkmark, to apply or discard. A row can be moved to another
/// category by hand and talked about with ChatGPT (plan ki-vorschlaege-anpassen, task D4); nothing is stored before
/// "Vorschlag übernehmen".
struct ShoppingSortResultSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let draft: ShoppingSortDraft
    let onApply: (ShoppingSorter.Proposal) -> Void
    let onDiscard: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if draft.changes.isEmpty {
                    Text("ChatGPT schlägt keine andere Einteilung vor.").foregroundStyle(.secondaryText)
                }
                if !draft.newCategories.isEmpty {
                    Section("Neue Kategorien") {
                        ForEach(draft.newCategories, id: \.self) { name in
                            checkRow(isOn: !draft.deselectedCategories.contains(name)) {
                                Text("Neue Kategorie „\(name)“ anlegen")
                            } toggle: {
                                draft.toggleCategory(name)
                            }
                        }
                    }
                }
                if !draft.changes.isEmpty {
                    Section("Änderungen") {
                        ForEach(draft.changes) { change in
                            let categoryOff = draft.deselectedCategories.contains(change.toCategory)
                            VStack(alignment: .leading, spacing: 4) {
                                checkRow(isOn: !categoryOff && !draft.deselectedItems.contains(change.id)) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(change.itemName)
                                        Text(verbatim: "\(change.fromCategory) → \(change.toCategory)").font(.subheadline).foregroundStyle(.secondaryText)
                                        PreviewRowMark(mark: draft.followUp.mark(of: change.id))
                                    }
                                } toggle: {
                                    draft.toggleItem(change.id)
                                }
                                .disabled(categoryOff)
                                // Below the name, so the name keeps the width of the row at large text sizes.
                                HStack(spacing: 8) {
                                    Spacer(minLength: 0)
                                    categoryMenu(change)
                                    if draft.hasFollowUp {
                                        Button("Mit ChatGPT zu diesem Artikel schreiben", systemImage: "sparkles") { draft.followUp.focus = change.id }
                                            .labelStyle(.iconOnly).buttonStyle(.borderless).minimumTapTarget()
                                    }
                                }
                            }
                        }
                    }
                }
                if draft.hasFollowUp { followUpSection }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Vorschlag von ChatGPT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(draft.changes.isEmpty ? "Schließen" : "Verwerfen", action: onDiscard)
                }
                if !draft.changes.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Vorschlag übernehmen") { onApply(draft.selection) }.disabled(draft.selection.changes.isEmpty)
                    }
                }
            }
            .onDisappear { draft.followUp.discard() }
        }
        .presentationDetents([.medium, .large])
    }

    /// The category of one row: the categories of the list, the fixed section and the proposed new ones (AN9a).
    private func categoryMenu(_ change: ShoppingSorter.Change) -> some View {
        Menu {
            Picker("Kategorie", selection: Binding(get: { change.toCategory }, set: { draft.pick($0, for: change.id) })) {
                ForEach(draft.categoryChoices, id: \.self) { Text($0).tag($0) }
            }
        } label: {
            Image(systemName: "folder").minimumTapTarget()
        }
        .accessibilityLabel("Kategorie wählen")
        .accessibilityValue(change.toCategory)
    }

    private var followUpSection: some View {
        PreviewFollowUpSection(
            model: draft.followUp,
            availability: FollowUpAvailability.state(hasConsent: environment.settings.hasShoppingSortConsent,
                                                     isSignedIn: environment.ai.isSignedIn, isOffline: false),
            place: .shopping,
            quickReplies: [String(localized: "Keine neuen Kategorien"), String(localized: "Gröber einteilen")],
            placeholder: "Zur Einteilung etwas sagen …",
            footer: Text("Senden gibt die Namen deiner offenen Artikel und deiner Kategorien, den Vorschlag mit deinen Änderungen und deine Nachricht an ChatGPT. Mengen gehen nicht mit."),
            focusLabel: { String(localized: "Zu: \($0.itemName)") }, onSend: { message in Task { await draft.send(message) } })
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
                    .foregroundStyle(isOn ? Color.accentColor : Color.secondaryText)
                label().foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
        }
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
