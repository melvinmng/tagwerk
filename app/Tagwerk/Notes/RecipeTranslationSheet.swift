import SwiftUI
import TagwerkCore

/// "Rezept übersetzen": choose the language, wait for ChatGPT, compare the proposal with the original, then replace the
/// original or save a copy. Nothing in the note changes before one of these two buttons. The sheet has its own navigation
/// stack; it never sends anything without the recipe consent and the user's tap on "Übersetzen".
struct RecipeTranslationSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: RecipeTranslationModel
    let store: NoteStore
    /// The copy was saved: the page names it in a notice.
    let onSavedCopy: (NoteRecord) -> Void

    @State private var showsConsent = false
    @State private var showsOriginal = false
    @FocusState private var followUpFocused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isPreview ? "Verwerfen" : "Abbrechen") {
                            model.cancel()
                            dismiss()
                        }
                    }
                }
        }
        // The consent sheet hangs on the outer view, not on a row of the form.
        .sheet(isPresented: $showsConsent) {
            RecipeConsentView {
                environment.settings.shoppingRecipeConsent = true
                showsConsent = false
                model.start()
            } onDecline: {
                showsConsent = false
            }
        }
        // The answer of a request that is still running must not arrive in a sheet that is gone.
        .onDisappear { model.cancel() }
        .interactiveDismissDisabled(model.phase == .translating)
        .presentationDetents([.large])
        .modifier(UITestAppearance())
    }

    private var isPreview: Bool {
        if case .preview = model.phase { return true }
        return false
    }

    private var title: LocalizedStringKey { isPreview ? "Übersetzung" : "Rezept übersetzen" }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .choosing, .failed: chooser
        case .translating: progress
        case .preview(let original, let translated): preview(original: original, translated: translated)
        }
    }

    // MARK: Step 1: language

    private static func name(_ language: VoiceLanguage) -> LocalizedStringKey {
        language == .german ? "Deutsch" : "Englisch"
    }

    private var chooser: some View {
        Form {
            Section {
                ForEach(RecipeLanguage.choices, id: \.self) { language in
                    Button {
                        model.target = language
                    } label: {
                        HStack {
                            Text(Self.name(language)).foregroundStyle(.primary)
                            Spacer()
                            if model.target == language { Image(systemName: "checkmark").foregroundStyle(.tint) }
                        }
                    }
                    .accessibilityAddTraits(model.target == language ? .isSelected : [])
                }
            } header: {
                Text("Übersetzen nach")
            } footer: {
                Text("Tagwerk sendet den Text dieser Notiz an ChatGPT. Du siehst die Übersetzung, bevor sich etwas ändert.")
            }
            if case .failed(let message) = model.phase {
                Section { Text(message).foregroundStyle(.redText) }
            }
            Section {
                Button(action: tapTranslate) {
                    Text("Übersetzen").fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .disabled(!environment.ai.isSignedIn)
            } footer: {
                if !environment.ai.isSignedIn { Text("Anmeldung unter Einstellungen › KI") }
            }
        }
    }

    private func tapTranslate() {
        if !environment.settings.shoppingRecipeConsent {
            showsConsent = true
            return
        }
        model.start()
    }

    // MARK: Waiting

    private var progress: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Rezept wird übersetzt …").foregroundStyle(.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    // MARK: Step 2: preview

    private func preview(original: String, translated: String) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                Picker("Ansicht", selection: $showsOriginal) {
                    Text("Übersetzung").tag(false)
                    Text("Original").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                if showsOriginal {
                    // The original refers to the attachments of the note; nothing in it can be tapped.
                    NoteMarkdownView(markdown: original, attachments: store.attachments,
                                     attachmentNames: Dictionary(uniqueKeysWithValues: (store.attachments?.attachments(of: model.noteID) ?? []).map { ($0.id, $0.fileName) }),
                                     onToggleCheckbox: { _ in }, onOpenAttachment: { _ in })
                        .padding(.horizontal, 16)
                        .allowsHitTesting(false)
                } else {
                    // The translation is text the user can change (task D3); the check before writing keeps the recipe intact.
                    TextEditor(text: Binding(get: { model.editedText }, set: { model.editedText = $0; model.textEdited() }))
                        .font(.body.monospaced())
                        .frame(minHeight: 260)
                        .padding(.horizontal, 12)
                        .accessibilityLabel("Übersetzung bearbeiten")
                }
                if let problem = model.editProblem {
                    Label(problem, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orangeText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                }
                Text("Vorschlag von ChatGPT. Mengen bleiben unverändert; bitte kurz prüfen. Anmerkungen und Anhänge der Notiz bleiben erhalten.")
                    .font(.footnote).foregroundStyle(.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                followUp
                VStack(spacing: 10) {
                    Button {
                        if model.replace() { dismiss() }
                    } label: {
                        Text("Original ersetzen").fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Button {
                        if let copy = model.saveCopy() {
                            onSavedCopy(copy)
                            dismiss()
                        }
                    } label: {
                        Text("Als Kopie sichern").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .padding(16)
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    /// The input line below the translation: the lines of the note, the translation as it is now and the message go to ChatGPT.
    private var followUp: some View {
        VStack(alignment: .leading, spacing: 8) {
            FollowUpBar(availability: FollowUpAvailability.state(hasConsent: environment.settings.shoppingRecipeConsent,
                                                                 isSignedIn: environment.ai.isSignedIn, isOffline: false),
                        state: model.followUpState, place: .notes,
                        quickReplies: [String(localized: "Du statt Sie"), String(localized: "Maßeinheiten lassen")],
                        placeholder: "Zur Übersetzung etwas sagen …",
                        footer: Text("Senden gibt den Text dieser Notiz, die Übersetzung mit deinen Änderungen und deine Nachricht an ChatGPT."),
                        isFocused: $followUpFocused, onSend: { message in Task { await model.revise(message) } },
                        onRetry: { Task { await model.revise(model.lastMessage) } }) {
                if !model.followUpReply.isEmpty {
                    FollowUpAnswerRow(reply: model.followUpReply, mark: model.previousText != nil ? .byAssistant : nil,
                                      onUndo: model.previousText != nil ? { model.undoRevision() } : nil)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
