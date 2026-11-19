import SwiftUI
import TagwerkCore

/// The notes page: cards, quick capture at the bottom, pinning and deleting. Notes stay on this device.
/// It has no navigation stack of its own.
struct NotesListView: View {
    @Environment(AppEnvironment.self) private var environment
    let store: NoteStore

    @State private var filter: NoteStore.Filter = .all
    @State private var draft = ""
    @State private var draftWasDictated = false
    @State private var voice: VoiceInputModel?
    @State private var deleting: NoteRecord?

    init(store: NoteStore) {
        self.store = store
    }

    var body: some View {
        let hasThoughts = store.hasThoughts
        let notes = store.notes(hasThoughts ? filter : .all)
        List {
            if hasThoughts {
                Picker("Filter", selection: $filter) {
                    Text("Alle").tag(NoteStore.Filter.all)
                    Text("Gedanken").tag(NoteStore.Filter.thoughts)
                    Text("Eigene").tag(NoteStore.Filter.own)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if notes.isEmpty {
                Text("Noch keine Notizen. Schreib oder diktiere unten die erste.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(notes, id: \.id) { card($0) }
            } footer: {
                Text(Self.listFootnote)
            }
        }
        .navigationTitle("Notizen")
        .safeAreaInset(edge: .bottom) { captureBar }
        .confirmationDialog("Notiz endgültig löschen?", isPresented: deletingBinding, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let deleting { store.delete(deleting.id) }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .onAppear(perform: prepareVoice)
        .onDisappear { voice?.cancel() }
    }

    // MARK: Cards

    private func card(_ note: NoteRecord) -> some View {
        let title = NoteText.title(note.text)
        let preview = NoteText.preview(note.text)
        return Button {
            environment.tasksPath.append(.note(note.id))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                    Spacer(minLength: 4)
                    if note.isPinned {
                        Image(systemName: "pin.fill").font(.footnote).foregroundStyle(.secondary)
                            .accessibilityLabel("Angeheftet")
                    }
                }
                if !preview.isEmpty {
                    Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Text(Self.footer(for: note, now: .now, calendar: environment.planning.calendar))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
        .swipeActions(edge: .trailing) {
            // Without a trash there is no way back, so deleting asks first.
            Button { deleting = note } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
        }
        .swipeActions(edge: .leading) {
            Button {
                store.setPinned(note.id, !note.isPinned)
            } label: {
                Label(note.isPinned ? "Anheftung lösen" : "Anheften", systemImage: note.isPinned ? "pin.slash" : "pin")
            }
            .tint(.orange)
        }
    }

    // MARK: Quick capture

    private var captureBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let voice { VoiceNoticeRow(voice: voice) }
            if let voice, voice.isRecording {
                VoiceRecordingBar(voice: voice)
            } else {
                HStack(alignment: .bottom, spacing: 4) {
                    TextField("Neue Notiz", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .padding(.vertical, 10)
                    if environment.settings.voiceInputEnabled, let voice {
                        VoiceMicrophoneButton(voice: voice, isEnabled: true,
                                              language: VoiceAvailability.recognitionLanguage(setting: environment.settings.voiceRecognitionLanguage))
                    }
                    if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Button {
                            save(draft, dictated: draftWasDictated)
                        } label: {
                            Image(systemName: "arrow.up.circle.fill").font(.title)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                        .frame(minHeight: 44)
                        .accessibilityLabel("Notiz sichern")
                    }
                }
                .padding(.leading, 14).padding(.trailing, 6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .onChange(of: draft) { _, newValue in
            if newValue.isEmpty { draftWasDictated = false }
        }
    }

    private func prepareVoice() {
        guard voice == nil else { return }
        let model = VoiceInputFactory.make(environment)
        model.readDraft = { draft }
        model.writeDraft = { spoken in
            draft = spoken
            draftWasDictated = true
        }
        // ↑ in the recording bar is the tap that saves the dictated note.
        model.onSend = { spoken in save(spoken, dictated: true) }
        voice = model
    }

    private func save(_ text: String, dictated: Bool) {
        guard store.create(text: text, wasDictated: dictated) != nil else { return }
        draft = ""
        draftWasDictated = false
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }
}

// MARK: Texts

extension NotesListView {
    /// Under the list. A thought note can go to ChatGPT, but only by a tap on "Vorschläge holen" with the consent
    /// of the routine settings (phase 7); own notes have no such button and are never sent.
    static var listFootnote: String {
        String(localized: "Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Gedanken-Notiz nur, wenn du bei ihr auf „Vorschläge holen“ tippst.")
    }

    /// Own notes: when they were changed last ("heute 08:12", "Dienstag" within the last six days, "12. Nov."),
    /// with "· diktiert" for dictated ones. Thought notes: their origin and day ("Tagesabschluss · 18.11.").
    static func footer(for note: NoteRecord, now: Date, calendar: Calendar) -> String {
        switch note.kind {
        case .free:
            let date = relativeDate(note.updatedAt, now: now, calendar: calendar)
            return note.wasDictated ? String(localized: "\(date) · diktiert") : date
        case .morning, .evening:
            let origin = note.kind == .morning ? String(localized: "Tagesstart") : String(localized: "Tagesabschluss")
            let day = note.dayKey.flatMap(NoteDayKey.day) ?? PlanDay(date: note.createdAt, calendar: calendar)
            let text = "\(origin) · \(DateText.numericDay(day, calendar: calendar))"
            switch note.derivedActionCount {
            case ...0: return text
            case 1: return text + " · " + String(localized: "1 Aufgabe daraus")
            default: return text + " · " + String(localized: "\(note.derivedActionCount) Aufgaben daraus")
            }
        }
    }

    /// The line under "Notizen" in the task list: the note changed last, or that there is none.
    static func entrySubtitle(latest: NoteRecord?, now: Date, calendar: Calendar) -> String {
        guard let latest else { return String(localized: "Noch keine Notizen") }
        return String(localized: "zuletzt: „\(NoteText.title(latest.text))“ · \(relativeDate(latest.updatedAt, now: now, calendar: calendar))")
    }

    static func relativeDate(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        if days == 0 { return String(localized: "heute \(DateText.time(date, calendar: calendar))") }
        let style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
        if (1...6).contains(days) { return date.formatted(style.weekday(.wide)) }
        return date.formatted(style.day().month(.abbreviated))
    }
}
