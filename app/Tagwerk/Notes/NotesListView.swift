import SwiftUI
import TagwerkCore

/// The notes of one folder (or of "Alle Notizen", "Zuletzt gelöscht"): search, sorting, selection, quick
/// capture at the bottom, pinning, moving and deleting. Notes stay on this device. It has no navigation stack of its own.
struct NotesListView: View {
    @Environment(AppEnvironment.self) private var environment
    let store: NoteStore
    let scope: NotesScope

    @State private var draft = ""
    @State private var draftWasDictated = false
    @State private var voice: VoiceInputModel?
    @State private var searchText = ""
    @State private var editMode: EditMode = .inactive
    @State private var selection = Set<UUID>()
    @State private var movingNoteIDs: [UUID] = []
    @State private var confirmsEmptyTrash = false
    @State private var deletingForGood: [UUID] = []
    @State private var isStartingBibleStudy = false

    init(store: NoteStore, scope: NotesScope = .all) {
        self.store = store
        self.scope = scope
    }

    private var isTrash: Bool { scope == .trash }

    /// The system folder of the journal: it opens with "Heute schreiben".
    private var isJournal: Bool {
        if case .folder(let id) = scope { return store.folder(id: id)?.role == .journal }
        return false
    }

    /// The system folder of Bible Study: it opens with "Bible Study starten".
    private var isBibleStudy: Bool {
        if case .folder(let id) = scope { return store.folder(id: id)?.role == .bibleStudy }
        return false
    }

    /// The role of the shown folder, if it is a system folder.
    private var folderRole: NoteFolderRole? {
        if case .folder(let id) = scope { return store.folder(id: id)?.role }
        return nil
    }

    /// Whether the quick capture bar is offered: not in the trash and not in folders that only the routines fill.
    private var allowsCapture: Bool { scope.allowsCapture && (folderRole?.acceptsOwnNotes ?? true) }

    var body: some View {
        @Bindable var settings = environment.settings
        let notes = visibleNotes
        let attachmentIndex = store.attachments?.index() ?? [:]
        List(selection: $selection) {
            if isJournal, !editMode.isEditing {
                Section {
                    Button { writeToday() } label: {
                        Label("Heute schreiben", systemImage: "square.and.pencil").foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            if isBibleStudy, !editMode.isEditing {
                bibleStudySection
            }
            if notes.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(notes, id: \.id) { card($0, attachmentIndex: attachmentIndex) }
            } footer: {
                Text(isTrash ? Self.trashFootnote : Self.listFootnote)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "Notizen durchsuchen")
        .environment(\.editMode, $editMode)
        .toolbar {
            if !isTrash || !notes.isEmpty { ToolbarItem(placement: .topBarTrailing) { EditButton() } }
            if !isTrash {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sortieren nach", selection: $settings.noteSortOrder) {
                            Text("Bearbeitet").tag(NoteSortOrder.modified)
                            Text("Erstellt").tag(NoteSortOrder.created)
                            Text("Titel").tag(NoteSortOrder.title)
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sortieren")
                }
            } else if !notes.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Alle löschen", role: .destructive) { confirmsEmptyTrash = true }
                }
            }
            if editMode.isEditing {
                ToolbarItemGroup(placement: .bottomBar) { selectionActions }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if allowsCapture, !editMode.isEditing { captureBar }
        }
        .confirmationDialog("Alle Notizen in „Zuletzt gelöscht“ endgültig löschen?", isPresented: $confirmsEmptyTrash, titleVisibility: .visible) {
            Button("Alle löschen", role: .destructive) { store.emptyTrash() }
            Button("Abbrechen", role: .cancel) {}
        }
        .confirmationDialog("Notiz endgültig löschen?", isPresented: deletingForGoodBinding, titleVisibility: .visible) {
            Button("Endgültig löschen", role: .destructive) {
                for id in deletingForGood { store.delete(id) }
                selection.subtract(deletingForGood)
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(isPresented: $isStartingBibleStudy) {
            BibleStudyStartSheet(store: store) { noteID in environment.tasksPath.append(.note(noteID)) }
        }
        .sheet(isPresented: movingBinding) {
            NoteFolderPickerSheet(store: store, title: "Bewegen nach") { target in
                store.move(noteIDs: movingNoteIDs, to: target)
                selection.subtract(movingNoteIDs)
                if selection.isEmpty { editMode = .inactive }
            }
        }
        .onAppear {
            store.purgeExpired(calendar: environment.planning.calendar)
            prepareVoice()
        }
        .onDisappear { voice?.cancel() }
    }

    // MARK: Content

    /// "Bible Study starten" and the sessions that are still open.
    @ViewBuilder private var bibleStudySection: some View {
        Section {
            Button { isStartingBibleStudy = true } label: {
                Label("Bible Study starten", systemImage: "book.pages").foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
            ForEach(store.sessions().filter { $0.completedAt == nil }.sorted { $0.startedAt > $1.startedAt }, id: \.id) { session in
                HStack {
                    Button { environment.tasksPath.append(.note(session.noteID)) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Self.sessionTitle(session)).foregroundStyle(.primary)
                            Text("Sitzung läuft").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("Abschließen") { store.completeSession(session.id) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    /// "Römer 3,21-31".
    static func sessionTitle(_ session: BibleStudySessionRecord, locale: Locale = .current) -> String {
        let name = BibleBooks.book(key: session.book)?.name(locale: locale) ?? ""
        return session.passage.isEmpty ? name : name + " " + session.passage
    }

    /// Opens the entry of today (rule 10: before 04:00 it is still yesterday's), created from the template if needed.
    private func writeToday() {
        let day = RoutineSchedule.routineDay(at: .now, calendar: environment.planning.calendar)
        let entry = store.openJournalEntry(dayKey: NoteDayKey.string(day))
        environment.tasksPath.append(.note(entry.id))
    }

    private var visibleNotes: [NoteRecord] {
        let notes = store.notes(scope.filter, sortedBy: environment.settings.noteSortOrder)
            .filter { NoteText.matches($0.text, query: searchText) }
        // The entries of a routine folder are days: newest day first, not by change date.
        return folderRole?.noteKind == nil ? notes : Self.byDayDescending(notes)
    }

    private var title: String {
        switch scope {
        case .all: String(localized: "Alle Notizen")
        case .standard: String(localized: "Notizen")
        case .trash: String(localized: "Zuletzt gelöscht")
        case .folder(let id): store.folder(id: id)?.name ?? String(localized: "Notizen")
        }
    }

    private var emptyText: String {
        if !searchText.isEmpty { return String(localized: "Keine Notizen gefunden.") }
        return isTrash ? String(localized: "Keine gelöschten Notizen.")
                       : String(localized: "Noch keine Notizen. Schreib oder diktiere unten die erste.")
    }

    @ViewBuilder private var selectionActions: some View {
        if isTrash {
            Button("Wiederherstellen") {
                for id in selection { store.restore(id) }
                selection = []
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button("Löschen", role: .destructive) { deletingForGood = Array(selection) }
                .disabled(selection.isEmpty)
        } else {
            Button("Bewegen") { movingNoteIDs = Array(selection) }
                .disabled(selection.isEmpty)
            Spacer()
            Button("Löschen", role: .destructive) {
                for id in selection { store.trash(id) }
                selection = []
            }
            .disabled(selection.isEmpty)
        }
    }

    // MARK: Cards

    private func card(_ note: NoteRecord, attachmentIndex: [UUID: NoteAttachmentRecord]) -> some View {
        let attachmentInfo = NoteAttachmentStore.cardInfo(text: note.text, index: attachmentIndex)
        let isJournalEntry = note.kind == .journal
        // The entries of the routine folders are named by their day.
        let isRoutineEntry = folderRole?.noteKind != nil
        let calendar = environment.planning.calendar
        let title = isJournalEntry ? Self.journalTitle(note, calendar: calendar)
            : isRoutineEntry ? Self.routineTitle(note, calendar: calendar) : NoteText.title(note.text)
        let preview = isJournalEntry ? JournalTemplate.contentLines(note.text).prefix(2).joined(separator: "\n")
            : isRoutineEntry ? Self.routinePreview(note, gratitude: gratitude(of: note))
            : NoteText.preview(note.text)
        return Button {
            // In selection mode the list itself toggles the row; a tap must not also open the note.
            guard !editMode.isEditing, !isTrash else { return }
            environment.tasksPath.append(.note(note.id))
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        Spacer(minLength: 4)
                        if attachmentInfo.fileCount > 0 {
                            Label("\(attachmentInfo.fileCount)", systemImage: "paperclip")
                                .font(.footnote).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                                .accessibilityLabel("\(attachmentInfo.fileCount) Dateien angehängt")
                        }
                        if note.isPinned {
                            Image(systemName: "pin.fill").font(.footnote).foregroundStyle(.secondary)
                                .accessibilityLabel("Angeheftet")
                        }
                    }
                    if !preview.isEmpty {
                        Text(preview).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text(footerText(for: note))
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let imageID = attachmentInfo.firstImageID, let thumbnail = store.attachments?.thumbnail(for: imageID) {
                    Image(uiImage: thumbnail).resizable().scaledToFill().frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 8)).accessibilityHidden(true)
                }
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // Without this the whole row takes the accent colour of a button (#173).
        .buttonStyle(.plain)
        .tag(note.id)
        .swipeActions(edge: .trailing) {
            if isTrash {
                Button { deletingForGood = [note.id] } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
            } else {
                // The trash is the way back, so deleting does not ask.
                Button { store.trash(note.id) } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
                if note.kind == .free {
                    Button { movingNoteIDs = [note.id] } label: { Label("Bewegen", systemImage: "folder") }.tint(.indigo)
                }
            }
        }
        .swipeActions(edge: .leading) {
            if isTrash {
                Button { store.restore(note.id) } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }.tint(.green)
            } else {
                Button {
                    store.setPinned(note.id, !note.isPinned)
                } label: {
                    Label(note.isPinned ? "Anheftung lösen" : "Anheften", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                .tint(.orange)
            }
        }
        .contextMenu {
            if isTrash {
                Button { store.restore(note.id) } label: { Label("Wiederherstellen", systemImage: "arrow.uturn.backward") }
                Button(role: .destructive) { deletingForGood = [note.id] } label: { Label("Endgültig löschen", systemImage: "trash") }
            } else {
                Button { store.setPinned(note.id, !note.isPinned) } label: {
                    Label(note.isPinned ? "Anheftung lösen" : "Anheften", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                if note.kind == .free {
                    Button { movingNoteIDs = [note.id] } label: { Label("Bewegen", systemImage: "folder") }
                }
                ShareLink(item: note.text) { Label("Teilen", systemImage: "square.and.arrow.up") }
                Button(role: .destructive) { store.trash(note.id) } label: { Label("Löschen", systemImage: "trash") }
            }
        }
    }

    private func gratitude(of note: NoteRecord) -> [String] {
        guard note.kind == .morning, let day = note.dayKey.flatMap(NoteDayKey.day) else { return [] }
        return environment.routines.value(day).gratitude
    }

    /// In the trash the footer names the days left; elsewhere the usual change date or origin.
    private func footerText(for note: NoteRecord) -> String {
        guard isTrash, let deletedAt = note.deletedAt else {
            return Self.footer(for: note, now: .now, calendar: environment.planning.calendar)
        }
        let days = NoteFolderRules.daysLeft(deletedAt: deletedAt, now: .now, calendar: environment.planning.calendar)
        return String(localized: "Noch \(days) Tage")
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
        .keepsKeyboardOnTap()
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
        guard store.create(text: text, wasDictated: dictated, folderID: scope.captureFolderID) != nil else { return }
        draft = ""
        draftWasDictated = false
    }

    private var movingBinding: Binding<Bool> {
        Binding(get: { !movingNoteIDs.isEmpty }, set: { if !$0 { movingNoteIDs = [] } })
    }

    private var deletingForGoodBinding: Binding<Bool> {
        Binding(get: { !deletingForGood.isEmpty }, set: { if !$0 { deletingForGood = [] } })
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
        case .journal:
            let day = note.dayKey.flatMap(NoteDayKey.day) ?? PlanDay(date: note.createdAt, calendar: calendar)
            return String(localized: "Tagebuch") + " · " + DateText.numericDay(day, calendar: calendar)
        case .bibleStudy:
            return String(localized: "Bible Study") + " · " + relativeDate(note.updatedAt, now: now, calendar: calendar)
        case .dream:
            let day = note.dayKey.flatMap(NoteDayKey.day) ?? PlanDay(date: note.createdAt, calendar: calendar)
            return String(localized: "Dream Log") + " · " + DateText.numericDay(day, calendar: calendar)
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

    /// The title of a journal entry in a list: its weekday and day ("Donnerstag, 19. November 2026").
    static func journalTitle(_ note: NoteRecord, calendar: Calendar) -> String {
        let day = note.dayKey.flatMap(NoteDayKey.day) ?? PlanDay(date: note.createdAt, calendar: calendar)
        let style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.weekday(.wide).day().month(.wide).year())
    }

    /// The title of an entry in a routine folder: its day ("Do., 19. Nov.").
    static func routineTitle(_ note: NoteRecord, calendar: Calendar) -> String {
        let day = note.dayKey.flatMap(NoteDayKey.day) ?? PlanDay(date: note.createdAt, calendar: calendar)
        let style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Dankbar für: A · B · C"; empty without entries. Gratitude stays in the routine record, the card only shows it.
    static func gratitudeLine(_ gratitude: [String]) -> String {
        let entries = gratitude.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !entries.isEmpty else { return "" }
        return String(localized: "Dankbar für: \(entries.joined(separator: " · "))")
    }

    /// The two lines under the day title: the gratitude of a morning entry, then the first lines of its text.
    static func routinePreview(_ note: NoteRecord, gratitude: [String]) -> String {
        let line = note.kind == .morning ? gratitudeLine(gratitude) : ""
        let lines = note.text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return ([line].filter { !$0.isEmpty } + lines).prefix(2).joined(separator: "\n")
    }

    /// Routine entries newest day first; the change date breaks ties.
    static func byDayDescending(_ notes: [NoteRecord]) -> [NoteRecord] {
        notes.sorted { first, second in
            let (a, b) = (first.dayKey ?? "", second.dayKey ?? "")
            return a != b ? a > b : first.updatedAt > second.updatedAt
        }
    }

    static var trashFootnote: String {
        String(localized: "Notizen bleiben hier \(NoteFolderRules.retentionDays) Tage und werden dann endgültig gelöscht.")
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
