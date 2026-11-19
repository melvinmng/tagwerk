import SwiftUI
import TagwerkCore

/// The notes entry page: "Alle Notizen", the default folder, "Gedanken", the user's folders as a tree, the system
/// folders and "Zuletzt gelöscht". It has no navigation stack of its own.
struct NotesFoldersView: View {
    @Environment(AppEnvironment.self) private var environment
    let store: NoteStore

    @State private var isCreating = false
    @State private var creatingParentID: UUID?
    @State private var renaming: NoteFolderRecord?
    @State private var nameText = ""
    @State private var deleting: NoteFolderRecord?
    @State private var movingFolder: NoteFolderRecord?
    @State private var errorText: String?

    init(store: NoteStore) {
        self.store = store
    }

    var body: some View {
        let counts = store.folderCounts()
        let tree = store.folderTree()
        let own = tree.filter { $0.folder.role == nil }.flatMap(\.flattened)
        let system = tree.filter { $0.folder.role != nil }.flatMap(\.flattened)
        List {
            Section {
                scopeRow(.all, symbol: "tray.full", title: "Alle Notizen", count: store.count)
                scopeRow(.standard, symbol: "note.text", title: "Notizen", count: store.notes(.own).count)
                if store.hasThoughts {
                    scopeRow(.thoughts, symbol: "moon.stars", title: "Gedanken", count: store.notes(.thoughts).count)
                }
            }
            if !own.isEmpty {
                Section("Ordner") {
                    ForEach(own) { folderRow($0, count: counts[$0.id] ?? 0) }
                }
            }
            Section {
                ForEach(system) { folderRow($0, count: counts[$0.id] ?? 0) }
                // The journal folder is created when it is first opened.
                if store.folder(role: .journal) == nil {
                    Button { openJournal() } label: {
                        rowLabel(symbol: Self.symbol(for: .journal), title: Text("Tagebuch mit Gott"), count: 0, depth: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            Section {
                scopeRow(.trash, symbol: "trash", title: "Zuletzt gelöscht", count: store.trashedCount)
            }
        }
        .navigationTitle("Notizen")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    startCreating(under: nil)
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .accessibilityLabel("Neuer Ordner")
            }
        }
        .onAppear { store.purgeExpired(calendar: environment.planning.calendar) }
        .alert(creatingParentID == nil ? "Neuer Ordner" : "Neuer Unterordner", isPresented: $isCreating) {
            TextField("Name", text: $nameText)
            Button("Anlegen", action: create)
            Button("Abbrechen", role: .cancel) {}
        }
        .alert("Ordner umbenennen", isPresented: renamingBinding) {
            TextField("Name", text: $nameText)
            Button("Sichern", action: rename)
            Button("Abbrechen", role: .cancel) {}
        }
        .alert(errorText ?? "", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        }
        .confirmationDialog(deleting.map { Self.deleteQuestion(name: $0.name, noteCount: store.notesAffectedByDeleting(folder: $0.id)) } ?? "",
                            isPresented: deletingBinding, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                if let deleting { run { try store.deleteFolder(deleting.id) } }
            }
            Button("Abbrechen", role: .cancel) {}
        }
        .sheet(item: $movingFolder) { folder in
            NoteFolderPickerSheet(store: store, title: "Ordner bewegen", movingFolderID: folder.id, currentFolderID: folder.parentID) { target in
                run { try store.moveFolder(folder.id, to: target) }
            }
        }
    }

    // MARK: Rows

    private func scopeRow(_ scope: NotesScope, symbol: String, title: LocalizedStringKey, count: Int) -> some View {
        Button {
            environment.tasksPath.append(.notesFolder(scope))
        } label: {
            rowLabel(symbol: symbol, title: Text(title), count: count, depth: 1)
        }
        .buttonStyle(.plain)
    }

    private func folderRow(_ node: NoteFolderNode, count: Int) -> some View {
        let folder = node.folder
        return Button {
            environment.tasksPath.append(.notesFolder(.folder(folder.id)))
        } label: {
            rowLabel(symbol: folder.role == nil ? "folder" : Self.symbol(for: folder.role), title: Text(folder.name), count: count, depth: node.depth)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if NoteFolderRules.canCreateFolder(under: folder.id, in: store.folders().map(\.info)) {
                Button { startCreating(under: folder.id) } label: { Label("Neuer Unterordner", systemImage: "folder.badge.plus") }
            }
            Button { startRenaming(folder.id) } label: { Label("Umbenennen", systemImage: "pencil") }
            if folder.role == nil {
                Button { movingFolder = store.folder(id: folder.id) } label: { Label("Bewegen", systemImage: "folder") }
                Button(role: .destructive) { deleting = store.folder(id: folder.id) } label: { Label("Löschen", systemImage: "trash") }
            }
        }
        .swipeActions(edge: .trailing) {
            if folder.role == nil {
                Button { deleting = store.folder(id: folder.id) } label: { Label("Löschen", systemImage: "trash") }.tint(.red)
            }
            Button { startRenaming(folder.id) } label: { Label("Umbenennen", systemImage: "pencil") }.tint(.indigo)
        }
    }

    private func rowLabel(symbol: String, title: Text, count: Int, depth: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
            title.foregroundStyle(.primary)
            Spacer(minLength: 8)
            Text("\(count)").monospacedDigit().foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.leading, CGFloat(depth - 1) * 18)
        .contentShape(Rectangle())
    }

    static func symbol(for role: NoteFolderRole?) -> String {
        switch role {
        case .journal: "book.closed"
        case .bibleStudy: "book.pages"
        case nil: "folder"
        }
    }

    // MARK: Texts

    /// Names how many notes go to "Zuletzt gelöscht" with the folder.
    static func deleteQuestion(name: String, noteCount: Int) -> String {
        let question = String(localized: "Ordner „\(name)“ löschen?")
        guard noteCount > 0 else { return question }
        return question + " " + String(localized: "\(noteCount) Notizen kommen nach „Zuletzt gelöscht“.")
    }

    static func message(for error: Error) -> String {
        switch error {
        case NoteFolderRules.NameError.empty: String(localized: "Gib einen Namen ein.")
        case NoteFolderRules.NameError.tooLong: String(localized: "Der Name darf höchstens \(NoteFolderRules.nameLimit) Zeichen haben.")
        case NoteFolderRules.NameError.duplicate: String(localized: "Diesen Ordner gibt es auf dieser Ebene schon.")
        case NoteFolderRules.MoveError.tooDeep: String(localized: "Ordner lassen sich höchstens drei Ebenen tief verschachteln.")
        case NoteFolderRules.MoveError.cycle: String(localized: "Ein Ordner lässt sich nicht in sich selbst bewegen.")
        case NoteFolderRules.MoveError.systemFolder: String(localized: "Dieser Ordner ist fest vergeben und lässt sich nicht löschen oder bewegen.")
        default: String(localized: "Das hat nicht geklappt.")
        }
    }

    // MARK: Actions

    private func openJournal() {
        let folder = store.ensureJournalFolder()
        environment.tasksPath.append(.notesFolder(.folder(folder.id)))
    }

    private func startCreating(under parentID: UUID?) {
        nameText = ""
        creatingParentID = parentID
        isCreating = true
    }

    private func startRenaming(_ id: UUID) {
        guard let folder = store.folder(id: id) else { return }
        nameText = folder.name
        renaming = folder
    }

    private func create() {
        run { try store.createFolder(name: nameText, parentID: creatingParentID) }
    }

    private func rename() {
        guard let renaming else { return }
        run { try store.renameFolder(renaming.id, to: nameText) }
    }

    private func run(_ change: () throws -> some Any) {
        do {
            _ = try change()
        } catch {
            errorText = Self.message(for: error)
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var deletingBinding: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })
    }
}

extension NoteFolderRecord: Identifiable {}
