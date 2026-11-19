import Foundation
import Observation
import SwiftUI
import TagwerkCore

/// The thoughts note of the morning start and the evening wrap-up (phase 7 design §7.6): one note per day and kind in the
/// shared `NoteRecord` store. Text is saved while typing (debounced) and when the sheet closes, before anything could be sent.
@MainActor
@Observable
final class NoteFieldModel {
    var text: String
    var selection: TextSelection?
    private(set) var noteID: UUID?
    private(set) var wasDictated: Bool

    let kind: NoteKind
    let day: PlanDay
    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let sleep: (Duration) async -> Void
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    /// What the store holds (trimmed), so an unchanged text is not written again.
    @ObservationIgnored private var savedText: String
    /// Text behind the cursor while a recording runs, and the text before the recording.
    @ObservationIgnored private var dictationTail = ""
    @ObservationIgnored private var dictationBase = ""
    @ObservationIgnored private var wasDictatedBeforeRecording = false

    init(store: NoteStore, kind: NoteKind, day: PlanDay, debounce: Duration = .milliseconds(500),
         sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }) {
        precondition(kind != .free)
        self.store = store
        self.kind = kind
        self.day = day
        self.debounce = debounce
        self.sleep = sleep
        let note = store.note(kind: kind, dayKey: day.dayKey)
        text = note?.text ?? ""
        noteID = note?.id
        wasDictated = note?.wasDictated ?? false
        savedText = note?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: Saving

    /// Call after each change of `text`; saves after the debounce.
    func textChanged() {
        pendingSave?.cancel()
        let sleep = self.sleep, debounce = self.debounce
        pendingSave = Task { [weak self] in
            await sleep(debounce)
            guard !Task.isCancelled else { return }
            self?.persist()
        }
    }

    /// Saves at once; called when the sheet closes.
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        persist()
    }

    /// Waits for the scheduled save; tests use it instead of timing.
    func waitForSave() async { await pendingSave?.value }

    private func persist() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != savedText else { return }
        let record = store.saveThought(text, kind: kind, dayKey: day.dayKey, wasDictated: wasDictated)
        noteID = record?.id
        savedText = record == nil ? "" : trimmed
    }

    // MARK: Dictation

    /// The text before the cursor (the whole text without a selection); dictation continues after it.
    func draftBeforeCursor() -> String {
        let cursor = cursorIndex()
        dictationTail = String(text[cursor...])
        dictationBase = String(text[..<cursor])
        wasDictatedBeforeRecording = wasDictated
        return dictationBase
    }

    /// The recognizer's current draft (text before the cursor plus what was said); the text behind the cursor is put
    /// back after it, so speaking in the middle of a note does not swallow the rest.
    func writeDictation(_ draft: String) {
        let tail = dictationTail
        if tail.isEmpty {
            text = draft
        } else if draft.isEmpty {
            text = tail
        } else {
            let separator = tail.first?.isNewline == true ? "" : " "
            text = draft.trimmingCharacters(in: .whitespaces) + separator + tail
        }
        // A cancelled recording writes the original draft back: the note was not dictated then.
        wasDictated = draft == dictationBase ? wasDictatedBeforeRecording : true
        textChanged()
    }

    private func cursorIndex() -> String.Index {
        guard let selection, case .selection(let range) = selection.indices,
              range.lowerBound <= text.endIndex else { return text.endIndex }
        return range.lowerBound
    }

    // MARK: Tasks from the note

    /// The first non-empty line, for "Als Aufgabe anlegen"; `nil` for an empty note.
    var taskTitle: String? {
        let title = NoteText.title(text)
        return title.isEmpty ? nil : title
    }

    /// A task was created by hand from this note ("2 Aufgaben daraus").
    func taskCreated() {
        flush()
        if let noteID { store.addDerivedAction(noteID) }
    }
}

/// The section "Gedanken" of both sheets: a multi-line field with a microphone and "Als Aufgabe anlegen".
struct NoteField: View {
    let model: NoteFieldModel
    @Environment(AppEnvironment.self) private var environment
    @State private var voice: VoiceInputModel?
    @State private var creatingTask = false

    var body: some View {
        Section {
            // One row, so the lifecycle and the sheet below attach once and not to every row of the section.
            VStack(alignment: .leading, spacing: 8) {
                if let voice { VoiceNoticeRow(voice: voice) }
                if let voice, voice.isRecording {
                    // The arrow stays off: dictation only fills the field, nothing is sent from here.
                    VoiceRecordingBar(voice: voice, canSend: false)
                } else {
                    HStack(alignment: .top, spacing: 4) {
                        TextEditor(text: Bindable(model).text, selection: Bindable(model).selection)
                            .frame(minHeight: 110)
                            .overlay(alignment: .topLeading) {
                                if model.text.isEmpty {
                                    Text("Was geht dir durch den Kopf?").foregroundStyle(.tertiary).padding(.top, 8).padding(.leading, 5)
                                        .allowsHitTesting(false)
                                }
                            }
                        if environment.settings.voiceInputEnabled, let voice {
                            VoiceMicrophoneButton(voice: voice, isEnabled: true,
                                                  language: VoiceAvailability.recognitionLanguage(setting: environment.settings.voiceRecognitionLanguage))
                        }
                    }
                }
                if model.taskTitle != nil {
                    Button { creatingTask = true } label: { Label("Als Aufgabe anlegen", systemImage: "plus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            .onChange(of: model.text) { _, _ in model.textChanged() }
            .onAppear(perform: prepareVoice)
            .onDisappear {
                voice?.cancel()
                model.flush()
            }
            .sheet(isPresented: $creatingTask) {
                NewTaskSheet(model: environment.taskList, prefilledTitle: model.taskTitle, onCreated: { model.taskCreated() })
            }
        } header: {
            Text("Gedanken")
        }
    }

    private func prepareVoice() {
        guard voice == nil else { return }
        let input = VoiceInputFactory.make(environment)
        input.readDraft = { model.draftBeforeCursor() }
        input.writeDraft = { model.writeDictation($0) }
        input.onSend = { _ in }
        voice = input
    }
}
