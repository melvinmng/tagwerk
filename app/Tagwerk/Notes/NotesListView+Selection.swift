import SwiftUI
import TagwerkCore

/// The "⋯" menu, the selection mode and the date groups of the notes list (design NO7b, NO8b).
extension NotesListView {
    /// One block of the list: a date group, or all notes when nothing is grouped.
    struct NoteListSection: Identifiable {
        let id: String
        let group: NoteDateGroups.Group?
        let notes: [NoteRecord]
    }

    // MARK: Groups

    /// The notes cut into date groups by the date the list is sorted by; one section without a group for the title order
    /// and when grouping is off. The notes keep their order.
    static func sections(of notes: [NoteRecord], order: NoteSortOrder, groupsByDate: Bool, now: Date,
                         calendar: Calendar) -> [NoteListSection] {
        guard groupsByDate, order != .title else { return [NoteListSection(id: "all", group: nil, notes: notes)] }
        let byID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        let items = notes.compactMap { note -> (id: UUID, date: Date, isPinned: Bool)? in
            order.groupingDate(of: NoteStore.sortKey(note)).map { (note.id, $0, note.isPinned) }
        }
        return NoteDateGroups.grouped(items, now: now, calendar: calendar).map { entry in
            NoteListSection(id: String(describing: entry.group), group: entry.group, notes: entry.ids.compactMap { byID[$0] })
        }
    }

    /// "Angeheftet", "Heute", "Letzte 7 Tage" or the month and year ("Oktober 2026").
    static func groupTitle(_ group: NoteDateGroups.Group, calendar: Calendar, locale: Locale = .current) -> String {
        switch group {
        case .pinned: return String(localized: "Angeheftet")
        case .today: return String(localized: "Heute")
        case .lastSevenDays: return String(localized: "Letzte 7 Tage")
        case .month(let year, let month):
            guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return "" }
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide).year())
        }
    }

    // MARK: Menu

    /// Whether the menu offers the sort order: not in the trash and not in the routine folders, whose entries are days.
    var offersSortOptions: Bool { !isTrash && folderRole?.noteKind == nil }

    /// The names of the two directions of an order: the default one first.
    static func directionNames(for order: NoteSortOrder) -> (standard: String, reversed: String) {
        order == .title ? (String(localized: "A bis Z"), String(localized: "Z bis A"))
                        : (String(localized: "Neueste zuerst"), String(localized: "Älteste zuerst"))
    }

    static func sortName(_ order: NoteSortOrder) -> String { NotesSettingsView.sortName(order) }

    /// The menu "⋯": selection, sort order, direction and date groups.
    var optionsMenu: some View {
        let settings = Bindable(environment.settings)
        let order = environment.settings.noteSortOrder
        let names = Self.directionNames(for: order)
        return Menu {
            Button { editMode = .active } label: { Label("Notizen auswählen", systemImage: "checkmark.circle") }
            if offersSortOptions {
                Picker("Sortieren nach", selection: settings.noteSortOrder) {
                    ForEach(NoteSortOrder.allCases, id: \.self) { Text(Self.sortName($0)).tag($0) }
                }
                Picker("Richtung", selection: settings.noteSortAscending) {
                    Text(names.standard).tag(false)
                    Text(names.reversed).tag(true)
                }
                Toggle("Nach Datum gruppieren", isOn: settings.noteGroupsByDate)
                    .disabled(order == .title)
            }
        } label: {
            Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Mehr")
        .accessibilityIdentifier("notes.listMenu")
    }

    // MARK: Lock

    /// "Sperren" / "Sperre aufheben" / "Jetzt sperren" of the context menu of a card (NL2a).
    @ViewBuilder
    func lockItems(_ note: NoteRecord, privateFolderIDs: Set<UUID>) -> some View {
        let lock = environment.noteLock
        if note.isLocked {
            Button { lock.removeLock([note.id], store: store) } label: { Label("Sperre aufheben", systemImage: "lock.open") }
        } else if lock.canLock(note, privateFolderIDs: privateFolderIDs) {
            Button {
                lock.requestLock([note.id], store: store, introFor: { lockIntroIDs = $0 })
            } label: { Label("Sperren", systemImage: "lock") }
                .disabled(!lock.canAuthenticate)
        }
        if lock.isUnlocked, lock.isProtected(note, privateFolderIDs: privateFolderIDs) {
            Button { lock.lockNow() } label: { Label("Jetzt sperren", systemImage: "lock") }
        }
    }

    /// The notes of a selection that "Sperren" locks: the ones the rules allow (rule 6), the others are skipped.
    static func lockableIDs(of notes: [NoteRecord], privateFolderIDs: Set<UUID>, settings: NoteProtection.Settings) -> [UUID] {
        notes.filter {
            !$0.isLocked && NoteProtection.canLock(kind: $0.kind, isInPrivateFolder: $0.folderID.map(privateFolderIDs.contains) ?? false,
                                                  settings: settings)
        }.map(\.id)
    }

    /// What a card shows instead of the preview of a hidden note.
    static func lockedPreview() -> String { String(localized: "Gesperrt") }

    // MARK: Selection

    /// "N ausgewählt"; without a selection the title says what to do.
    static func selectionTitle(_ count: Int) -> String {
        count == 0 ? String(localized: "Notizen auswählen") : String(localized: "\(count) ausgewählt")
    }

    /// Whether "Anheften" (true) or "Lösen" (false) is offered: pin as soon as one chosen note is not pinned.
    static func shouldPin(_ notes: [NoteRecord]) -> Bool { notes.contains { !$0.isPinned } }

    func toggleSelectAll(_ notes: [NoteRecord]) {
        let ids = Set(notes.map(\.id))
        selection = selection.isSuperset(of: ids) && !ids.isEmpty ? [] : ids
    }

    func endSelection() {
        selection = []
        editMode = .inactive
    }

    /// The bottom bar of the selection mode.
    @ViewBuilder var selectionActions: some View {
        if isTrash {
            Button("Wiederherstellen") {
                for id in selection { store.restore(id) }
                selection = []
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button("Löschen", role: .destructive) {
                let ids = Array(selection)
                let lock = environment.noteLock
                let concealed = ids.compactMap { store.note(id: $0) }.contains { lock.isConcealed($0, in: store) }
                lock.afterUnlock(whenConcealed: concealed) { deletingForGood = ids }
            }
            .disabled(selection.isEmpty)
        } else {
            let chosen = selection.compactMap { store.note(id: $0) }
            let lock = environment.noteLock
            let concealed = chosen.contains { lock.isConcealed($0, in: store) }
            // The entries of a routine folder belong there; moving them is not offered.
            if folderRole?.noteKind == nil {
                Button("Bewegen") {
                    let ids = Array(selection)
                    lock.afterUnlock(whenConcealed: concealed) { movingNoteIDs = ids }
                }
                .disabled(selection.isEmpty)
                Spacer()
            }
            lockSelectionButton(chosen)
            Spacer()
            let pins = Self.shouldPin(chosen)
            let pinTitle: LocalizedStringKey = pins ? "Anheften" : "Lösen"
            Button(pinTitle) {
                for note in chosen { store.setPinned(note.id, pins) }
                selection = []
            }
            .disabled(selection.isEmpty)
            Spacer()
            Button("Löschen", role: .destructive) {
                let ids = Array(selection)
                // A hidden note asks the device owner first (rule 7).
                lock.afterUnlock(whenConcealed: concealed) { for id in ids { store.trash(id) } }
                selection = []
            }
            .disabled(selection.isEmpty)
        }
    }

    /// "Sperren" locks the chosen notes the rules allow; when every chosen note is locked already, the button removes the mark.
    @ViewBuilder
    private func lockSelectionButton(_ chosen: [NoteRecord]) -> some View {
        let lock = environment.noteLock
        let privateFolderIDs = NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info))
        let lockable = Self.lockableIDs(of: chosen, privateFolderIDs: privateFolderIDs, settings: lock.protection)
        if !chosen.isEmpty, chosen.allSatisfy(\.isLocked) {
            Button("Entsperren") {
                lock.removeLock(chosen.map(\.id), store: store)
                selection = []
            }
        } else {
            Button("Sperren") {
                lock.requestLock(lockable, store: store, introFor: { lockIntroIDs = $0 })
                selection = []
            }
            .disabled(lockable.isEmpty || !lock.canAuthenticate)
        }
    }
}
