import SwiftUI
import TagwerkCore

/// Texts and decisions of the shopping input bar, kept apart from the view so they can be tested.
@MainActor
enum ShoppingInput {
    /// Chips are shown for more than one recognized item or for dictated text; a single typed item is added directly.
    static func needsPreview(items: [ParsedItem], wasDictated: Bool) -> Bool {
        items.count > 1 || (wasDictated && !items.isEmpty)
    }

    /// One short line about what happened, e.g. "3 hinzugefügt · Eier steht schon drauf".
    static func feedback(_ report: ShoppingModel.AddReport, droppedCount: Int) -> String {
        var parts: [String] = []
        if !report.added.isEmpty { parts.append(String(localized: "\(report.added.count) hinzugefügt")) }
        if report.alreadyOnList.count == 1 {
            parts.append(String(localized: "\(report.alreadyOnList[0]) steht schon drauf"))
        } else if !report.alreadyOnList.isEmpty {
            parts.append(String(localized: "\(report.alreadyOnList.joined(separator: ", ")) stehen schon drauf"))
        }
        if !report.reopened.isEmpty {
            parts.append(String(localized: "\(report.reopened.joined(separator: ", ")) wieder geöffnet"))
        }
        if !report.failed.isEmpty, let message = report.errorMessage { parts.append(message) }
        if droppedCount > 0 { parts.append(String(localized: "Höchstens 20 Artikel auf einmal")) }
        return parts.joined(separator: " · ")
    }

    static func chipTitle(_ item: ParsedItem) -> String {
        "＋ " + [item.quantity, item.name].compactMap { $0 }.joined(separator: " ")
    }

    /// VoiceOver text of a row: name, quantity and state.
    static func accessibilityLabel(_ item: ShoppingItem) -> String {
        let state = item.isCompleted ? String(localized: "erledigt") : String(localized: "nicht erledigt")
        return [item.name, item.quantity, state].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The field at the bottom of the shopping page: type or dictate one or several items.
/// Several items and dictated text are shown as chips first; nothing dictated is saved without a tap.
struct ShoppingInputBar: View {
    @Environment(AppEnvironment.self) private var environment
    let model: ShoppingModel
    /// The line above the field: what was added, or the text of a write error.
    @Binding var notice: String?

    @State private var text = ""
    @State private var wasDictated = false
    /// Chips the user removed by tapping them.
    @State private var removed: Set<ParsedItem> = []
    @State private var voice: VoiceInputModel?
    @State private var isAdding = false
    @FocusState private var isFocused: Bool

    private var parsed: ShoppingInputParser.ParseResult { ShoppingInputParser.parseAll(text) }
    private var items: [ParsedItem] { parsed.items.filter { !removed.contains($0) } }
    private var showsChips: Bool { ShoppingInput.needsPreview(items: parsed.items, wasDictated: wasDictated) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice {
                Text(notice).font(.footnote).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            if let voice { VoiceNoticeRow(voice: voice) }
            if showsChips { chips }
            if let voice, voice.isRecording {
                VoiceRecordingBar(voice: voice)
            } else {
                field
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .keepsKeyboardOnTap()
        .onChange(of: text) { _, newValue in
            removed = []
            if newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { wasDictated = false }
        }
        .task(id: notice) {
            guard notice != nil else { return }
            try? await Task.sleep(for: .seconds(4))
            if !Task.isCancelled { notice = nil }
        }
        .onAppear(perform: prepareVoice)
        .onDisappear { voice?.cancel() }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Button {
                        removed.insert(item)
                    } label: {
                        Text(ShoppingInput.chipTitle(item)).font(.subheadline)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.accentColor.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Entfernt den Artikel aus der Eingabe")
                }
            }
        }
    }

    private var field: some View {
        HStack(spacing: 4) {
            TextField("Artikel hinzufügen", text: $text)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submit)
            if environment.settings.voiceInputEnabled, let voice {
                VoiceMicrophoneButton(voice: voice, isEnabled: !isAdding,
                                      language: VoiceAvailability.recognitionLanguage(setting: environment.settings.voiceRecognitionLanguage))
            }
            if !items.isEmpty {
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.title)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(isAdding)
                .accessibilityLabel("Hinzufügen")
            }
        }
        .padding(.leading, 14).padding(.trailing, 6).frame(minHeight: 44)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
    }

    private func prepareVoice() {
        guard voice == nil else { return }
        let model = VoiceInputFactory.make(environment)
        model.readDraft = { text }
        model.writeDraft = { spoken in
            text = spoken
            wasDictated = true
        }
        // ↑ in the recording bar only fills the field: dictated items appear as chips and wait for a tap.
        model.onSend = { spoken in
            text = spoken
            wasDictated = true
        }
        voice = model
    }

    private func submit() {
        let toAdd = items
        let dropped = parsed.droppedCount
        guard !toAdd.isEmpty, !isAdding else { return }
        isAdding = true
        Task {
            let report = await model.add(toAdd)
            let feedback = ShoppingInput.feedback(report, droppedCount: dropped)
            notice = feedback.isEmpty ? nil : feedback
            if report.failed.isEmpty {
                text = ""
                wasDictated = false
            }
            isAdding = false
        }
    }
}
