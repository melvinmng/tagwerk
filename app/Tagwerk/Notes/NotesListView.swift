import SwiftUI
import TagwerkCore

/// The notes of one folder (or of "Alle Notizen", "Zuletzt gelöscht"): search, sorting, selection, quick
/// capture at the bottom, pinning, moving and deleting. Notes stay on this device. It has no navigation stack of its own.
struct NotesListView: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    let store: NoteStore
    let scope: NotesScope

    @State private var draft = ""
    @State private var draftWasDictated = false
    @State private var voice: VoiceInputModel?
    @State private var searchText = ""
    @State var editMode: EditMode = .inactive
    @State var selection = Set<UUID>()
    @State var movingNoteIDs: [UUID] = []
    @State private var confirmsEmptyTrash = false
    @State var deletingForGood: [UUID] = []
    @State private var isStartingBibleStudy = false
    @State private var isCreatingRecipe = false
    /// Notes that wait for the explanation before their first lock (`NoteLockIntroSheet`).
    @State var lockIntroIDs: [UUID] = []

    init(store: NoteStore, scope: NotesScope = .all) {
        self.store = store
        self.scope = scope
    }

    var isTrash: Bool { scope == .trash }

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
    var folderRole: NoteFolderRole? {
        if case .folder(let id) = scope { return store.folder(id: id)?.role }
        return nil
    }

    /// Whether the quick capture bar is offered: not in the trash and not in folders that only the routines fill.
    private var allowsCapture: Bool { scope.allowsCapture && (folderRole?.acceptsOwnNotes ?? true) }

    /// A private folder behind the lock shows the lock screen instead of its notes (NO10c, NL3a).
    var body: some View {
        let lock = environment.noteLock
        let isFolderProtected: Bool = {
            guard case .folder(let id) = scope else { return false }
            return NoteProtection.isProtectedFolder(isPrivateFolder: NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info)).contains(id),
                                                    settings: lock.protection)
        }()
        let isFolderConcealed = isFolderProtected && !lock.isUnlocked
        Group {
            if isFolderConcealed {
                LockedContentView(kind: .folder) { _ = await lock.unlock(reason: NoteLock.reason) }
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                listBody
            }
        }
        // The app switcher shows no list of a protected folder.
        .overlay { if isFolderProtected, scenePhase != .active { LockCoverView() } }
        // A hidden folder asks at once; a failed check leaves the lock screen standing.
        .task(id: isFolderConcealed && scenePhase == .active) {
            guard isFolderConcealed, scenePhase == .active else { return }
            _ = await lock.unlock(reason: NoteLock.reason)
        }
        .noteLockIntro(ids: $lockIntroIDs, store: store)
    }

    @ViewBuilder private var listBody: some View {
        let notes = visibleNotes
        let privateFolderIDs = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        // "Tagesstart" also lists the days that only have gratitude (NO14); they are display entries, not notes.
        let gratitudeDays = folderRole == .morningRoutine && !isTrash ? environment.routines.gratitudeDays() : [:]
        let morningEntries = folderRole == .morningRoutine && !isTrash
            ? Self.morningEntries(notes: notes, gratitudeDays: gratitudeDays, query: searchText) : []
        let notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let settings = environment.settings
        let sections = Self.sections(of: notes, order: settings.noteSortOrder,
                                     groupsByDate: settings.noteGroupsByDate && !isTrash && folderRole?.noteKind == nil,
                                     now: .now, calendar: environment.planning.calendar)
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
            if folderRole == .recipes, !editMode.isEditing {
                Section {
                    Button { newRecipe() } label: {
                        Label("Neues Rezept", systemImage: "square.and.pencil").foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    Button { isCreatingRecipe = true } label: {
                        Label("Rezept mit ChatGPT anlegen", systemImage: "sparkles").foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                }
            }
            if notes.isEmpty, morningEntries.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
            ForEach(sections) { section in
                Section {
                    if folderRole == .morningRoutine, !isTrash {
                        ForEach(morningEntries, id: \.self) { entry in
                            switch entry {
                            case .note(let id, _):
                                if let note = notesByID[id] { card(note, attachmentIndex: attachmentIndex, privateFolderIDs: privateFolderIDs) }
                            case .gratitudeOnly(let day):
                                gratitudeOnlyCard(day, gratitude: gratitudeDays[day] ?? [])
                            }
                        }
                    } else {
                        ForEach(section.notes, id: \.id) { card($0, attachmentIndex: attachmentIndex, privateFolderIDs: privateFolderIDs) }
                    }
                } header: {
                    if let group = section.group {
                        Text(Self.groupTitle(group, calendar: environment.planning.calendar)).textCase(nil)
                    } else if isTrash, !notes.isEmpty {
                        Text(Self.trashHeader).textCase(nil)
                    }
                } footer: {
                    if !isTrash, section.id == sections.last?.id { Text(Self.listFootnote) }
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle(editMode.isEditing ? Self.selectionTitle(selection.count) : title)
        .navigationBarBackButtonHidden(editMode.isEditing)
        .searchable(text: $searchText, prompt: "Notizen durchsuchen")
        .environment(\.editMode, $editMode)
        .toolbar {
            if editMode.isEditing {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selection.isSuperset(of: notes.map(\.id)) && !notes.isEmpty ? "Keine auswählen" : "Alle auswählen") {
                        toggleSelectAll(notes)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { endSelection() }.fontWeight(.semibold)
                }
                ToolbarItemGroup(placement: .bottomBar) { selectionActions }
            } else {
                if isTrash, !notes.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Alle löschen", role: .destructive) { confirmsEmptyTrash = true }
                    }
                }
                if !isTrash || !notes.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) { optionsMenu }
                }
            }
        }
        // The notes chat from this list; not in "Zuletzt gelöscht" and not in a private folder.
        .noteAssistantEntry(NoteAssistantEntry.Target(scope: scope), store: store)
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
        .sheet(isPresented: $isCreatingRecipe) {
            RecipeNoteSaveSheet(store: store) { noteID in environment.tasksPath.append(.note(noteID)) }
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
            startRequestedDictation()
        }
        .onChange(of: environment.router.dictationRequested) { _, _ in startRequestedDictation() }
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
                            Text("Sitzung läuft").font(.caption).foregroundStyle(.secondaryText)
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

    /// "Neues Rezept": a note with the skeleton of a recipe in the folder "Rezepte", opened for writing.
    private func newRecipe() {
        guard let note = RecipeNoteWriter.createBlank(language: environment.settings.resolvedRecipeLanguage, store: store) else { return }
        environment.tasksPath.append(.note(note.id))
    }

    /// Opens the entry of today (rule 10: before 04:00 it is still yesterday's), created from the template if needed.
    private func writeToday() {
        let day = RoutineSchedule.routineDay(at: .now, calendar: environment.planning.calendar)
        let entry = store.openJournalEntry(dayKey: NoteDayKey.string(day))
        environment.tasksPath.append(.note(entry.id))
    }

    var visibleNotes: [NoteRecord] {
        let privateFolderIDs = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        let notes = store.notes(scope.filter, sortedBy: environment.settings.noteSortOrder,
                                ascending: environment.settings.noteSortAscending)
            .filter { matchesSearch($0, privateFolderIDs: privateFolderIDs) }
        // The entries of a routine folder are days: newest day first, not by change date.
        return folderRole?.noteKind == nil ? notes : Self.byDayDescending(notes)
    }

    /// The search field of the list: a hidden note matches by its title only (NL4a), everything else by its text.
    private func matchesSearch(_ note: NoteRecord, privateFolderIDs: Set<UUID>) -> Bool {
        let isConcealed = environment.noteLock.isConcealed(note, privateFolderIDs: privateFolderIDs)
        return Self.matchesSearch(note, gratitude: isConcealed ? [] : gratitude(of: note), query: searchText, titleOnly: isConcealed)
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

    // MARK: Cards

    private func card(_ note: NoteRecord, attachmentIndex: [UUID: NoteAttachmentRecord], privateFolderIDs: Set<UUID>) -> some View {
        let lock = environment.noteLock
        // A hidden note shows its title only: no preview, no thumbnail, no count of attachments (NL3a).
        let isConcealed = lock.isConcealed(note, privateFolderIDs: privateFolderIDs)
        let attachmentInfo = isConcealed ? NoteAttachmentStore.CardInfo() : NoteAttachmentStore.cardInfo(text: note.text, index: attachmentIndex)
        let isJournalEntry = note.kind == .journal
        // The entries of the routine folders are named by their day.
        let isRoutineEntry = folderRole?.noteKind != nil
        let calendar = environment.planning.calendar
        let title = isJournalEntry ? Self.journalTitle(note, calendar: calendar)
            : isRoutineEntry ? Self.routineTitle(note, calendar: calendar) : NoteText.title(note.text)
        let preview = isConcealed ? Self.lockedPreview()
            : isJournalEntry ? JournalTemplate.contentLines(note.text).prefix(2).joined(separator: "\n")
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
                        Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        Spacer(minLength: 4)
                        // The open lock marks a locked note that is unlocked (or whose protection is off) right now.
                        if note.isLocked, !isConcealed {
                            Image(systemName: "lock.open").font(.footnote).foregroundStyle(.secondaryText).accessibilityHidden(true)
                        }
                        if isTrash, let deletedAt = note.deletedAt { trashBadge(deletedAt: deletedAt) }
                        if attachmentInfo.fileCount > 0 {
                            Label("\(attachmentInfo.fileCount)", systemImage: "paperclip")
                                .font(.footnote).foregroundStyle(.secondaryText).labelStyle(.titleAndIcon)
                                .accessibilityLabel("Dateien angehängt: \(attachmentInfo.fileCount)")
                        }
                        if note.isPinned {
                            Image(systemName: "pin.fill").font(.footnote).foregroundStyle(.secondaryText)
                                .accessibilityLabel("Angeheftet")
                        }
                    }
                    if isConcealed {
                        Label(preview, systemImage: "lock.fill").font(.subheadline).foregroundStyle(.secondaryText)
                    } else if !preview.isEmpty {
                        Text(preview).font(.subheadline).foregroundStyle(.secondaryText).lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    }
                    Text(footerText(for: note))
                        .font(.caption).foregroundStyle(.secondaryText)
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
        .accessibilityValue(note.isLocked ? (isConcealed ? Text("gesperrt") : Text("entsperrt")) : Text(""))
        .swipeActions(edge: .trailing) {
            if isTrash {
                Button { lock.afterUnlock(whenConcealed: isConcealed) { deletingForGood = [note.id] } } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
            } else {
                // The trash is the way back, so deleting does not ask; a hidden note asks the device owner first (rule 7).
                Button { lock.afterUnlock(whenConcealed: isConcealed) { store.trash(note.id) } } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
                if note.kind == .free {
                    Button { lock.afterUnlock(whenConcealed: isConcealed) { movingNoteIDs = [note.id] } } label: { Label("Bewegen", systemImage: "folder") }.tint(.indigo)
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
                Button(role: .destructive) { lock.afterUnlock(whenConcealed: isConcealed) { deletingForGood = [note.id] } } label: { Label("Endgültig löschen", systemImage: "trash") }
            } else {
                Button { store.setPinned(note.id, !note.isPinned) } label: {
                    Label(note.isPinned ? "Anheftung lösen" : "Anheften", systemImage: note.isPinned ? "pin.slash" : "pin")
                }
                if note.kind == .free {
                    Button { lock.afterUnlock(whenConcealed: isConcealed) { movingNoteIDs = [note.id] } } label: { Label("Bewegen", systemImage: "folder") }
                }
                lockItems(note, privateFolderIDs: privateFolderIDs)
                // The text of a hidden note is not shared.
                if !isConcealed {
                    ShareLink(item: note.text) { Label("Teilen", systemImage: "square.and.arrow.up") }
                }
                Button(role: .destructive) { lock.afterUnlock(whenConcealed: isConcealed) { store.trash(note.id) } } label: { Label("Löschen", systemImage: "trash") }
            }
        }
    }

    /// The card of a day that only has gratitude: the day, the gratitude and where it comes from. A tap opens its page;
    /// the entry cannot be pinned, moved, selected or deleted (the gratitude is cleared in the morning routine).
    private func gratitudeOnlyCard(_ day: PlanDay, gratitude: [String]) -> some View {
        let calendar = environment.planning.calendar
        return Button {
            guard !editMode.isEditing else { return }
            environment.tasksPath.append(.morningDay(day))
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.routineTitle(day: day, calendar: calendar)).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(Self.gratitudeLine(gratitude)).font(.subheadline).foregroundStyle(.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                Text(Self.gratitudeOnlyFooter(day: day, calendar: calendar)).font(.caption).foregroundStyle(.secondaryText)
            }
            .padding(.vertical, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .selectionDisabled()
    }

    private func gratitude(of note: NoteRecord) -> [String] {
        guard note.kind == .morning, let day = note.dayKey.flatMap(NoteDayKey.day) else { return [] }
        return environment.routines.value(day).gratitude
    }

    /// In the trash the footer names the day of the deletion and the folder; elsewhere the usual change date or origin.
    private func footerText(for note: NoteRecord) -> String {
        guard isTrash else { return Self.footer(for: note, now: .now, calendar: environment.planning.calendar) }
        let folderName = note.folderID.flatMap { store.folder(id: $0)?.name } ?? String(localized: "Notizen")
        return Self.trashFooter(for: note, folderName: folderName, now: .now, calendar: environment.planning.calendar)
    }

    /// "noch 3 Tage"; from the last week on with the clock and in the warning colour, so the colour is not the only sign.
    private func trashBadge(deletedAt: Date) -> some View {
        let days = NoteFolderRules.daysLeft(deletedAt: deletedAt, now: .now, calendar: environment.planning.calendar)
        let isUrgent = days < Self.trashWarningDays
        return HStack(spacing: 3) {
            if isUrgent { Image(systemName: "clock") }
            Text(Self.daysLeftText(days))
        }
        .font(.footnote)
        .foregroundStyle(isUrgent ? Color.orangeText : Color.secondaryText)
        .accessibilityElement(children: .combine)
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
                                              language: environment.settings.dictationLanguage(at: .notes))
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

    /// "Notiz diktieren" (control): the recording starts as if the microphone was tapped. The request is used up even
    /// when dictation is off, so it cannot start a recording later.
    private func startRequestedDictation() {
        // Only the list of Brain Dump takes the request; another list that is still on screen while the path changes
        // must not start a recording into the wrong folder.
        guard folderRole == .brainDump, environment.router.dictationRequested else { return }
        let wanted = environment.router.takeDictationRequest()
        if wanted, allowsCapture, environment.settings.voiceInputEnabled { voice?.tapMicrophone() }
    }

    private func prepareVoice() {
        guard voice == nil else { return }
        let model = VoiceInputFactory.make(environment, place: .notes)
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
    /// of the routine settings (phase 7); an own note only when the user picks it as the source of "Rezept hinzufügen".
    static var listFootnote: String {
        String(localized: "Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Brain-Dump-Notiz nur, wenn du bei ihr auf „Vorschläge holen“ tippst, und eine Notiz nur, wenn du sie bei „Rezept hinzufügen“ als Quelle wählst.")
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
        routineTitle(day: note.dayKey.flatMap(NoteDayKey.day) ?? PlanDay(date: note.createdAt, calendar: calendar), calendar: calendar)
    }

    /// The title of a day in a routine folder ("Do., 19. Nov.").
    static func routineTitle(day: PlanDay, calendar: Calendar) -> String {
        let style = Date.FormatStyle(locale: .current, calendar: calendar, timeZone: calendar.timeZone)
        return day.startDate(in: calendar).formatted(style.weekday(.abbreviated).day().month(.abbreviated))
    }

    /// A note matches by its text; an entry of "Tagesstart" also by the gratitude of its day.
    /// `titleOnly` is for a hidden note: only its first line is searched.
    static func matchesSearch(_ note: NoteRecord, gratitude: [String], query: String, titleOnly: Bool = false) -> Bool {
        if titleOnly { return NoteText.matches(NoteText.title(note.text), query: query) }
        // Text and gratitude are searched together, so a query of two words may find one in each.
        return NoteText.matches(([note.text] + gratitude).joined(separator: "\n"), query: query)
    }

    /// Whether the gratitude of a day matches the search of the list; an empty search matches every day with gratitude.
    static func matchesSearch(gratitude: [String], query: String) -> Bool {
        !gratitude.isEmpty && NoteText.matches(gratitude.joined(separator: "\n"), query: query)
    }

    /// The entries of "Tagesstart" for the list: the notes (already filtered by the search) and the days with gratitude only
    /// whose gratitude matches the search, days descending.
    static func morningEntries(notes: [NoteRecord], gratitudeDays: [PlanDay: [String]], query: String) -> [RoutineFolderEntry<UUID>] {
        let matching = Set(gratitudeDays.filter { matchesSearch(gratitude: $0.value, query: query) }.keys)
        return RoutineFolderEntries.merge(notes: notes.map { (id: $0.id, day: $0.dayKey.flatMap(NoteDayKey.day)) }, gratitudeDays: matching)
    }

    /// "Tagesstart · 19.11. · nur Dankbarkeit".
    static func gratitudeOnlyFooter(day: PlanDay, calendar: Calendar) -> String {
        String(localized: "Tagesstart") + " · " + DateText.numericDay(day, calendar: calendar) + " · " + String(localized: "nur Dankbarkeit")
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

    /// The days left from which a deleted note is marked as about to go.
    static let trashWarningDays = 7

    /// The hint at the top of "Zuletzt gelöscht".
    static var trashHeader: String {
        String(localized: "Notizen bleiben \(NoteFolderRules.retentionDays) Tage hier und werden dann endgültig gelöscht, mit ihren Anhängen.")
    }

    /// "Gelöscht am 23.10. · aus „Notizen“"; `folderName` is the folder the note lay in.
    static func trashFooter(for note: NoteRecord, folderName: String, now: Date, calendar: Calendar) -> String {
        guard let deletedAt = note.deletedAt else { return "" }
        let date = DateText.numericDay(PlanDay(date: deletedAt, calendar: calendar), calendar: calendar)
        return String(localized: "Gelöscht am \(date) · aus „\(folderName)“")
    }

    /// "noch 3 Tage", "noch 1 Tag".
    static func daysLeftText(_ days: Int) -> String {
        days == 1 ? String(localized: "noch 1 Tag") : String(localized: "noch \(days) Tage")
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
