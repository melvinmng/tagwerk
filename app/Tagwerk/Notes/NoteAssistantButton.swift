import SwiftUI
import TagwerkCore

/// Where the assistant opens a chat about notes from (#233): the notes overview, a folder and an open note.
enum NoteAssistantEntry {
    enum Target: Equatable {
        /// The notes overview, "Alle Notizen" and "Notizen": the chat about all notes.
        case overview
        /// An own folder or "Brain Dump": the chat about all notes, new notes go to this folder.
        case folder(UUID)
        /// "Zuletzt gelöscht": the assistant has nothing to do there.
        case trash
        /// The chat about one note.
        case note(UUID)

        /// The entry of a list of notes (`NotesScope`).
        init(scope: NotesScope) {
            switch scope {
            case .all, .standard: self = .overview
            case .trash: self = .trash
            case .folder(let id): self = .folder(id)
            }
        }
    }

    /// Whether the entry shows: not in "Zuletzt gelöscht", not in a private folder (also not in a folder below one) and not
    /// for a private or trashed note. A pure rule on top of `NoteToolAccess`, the only place that selects notes for ChatGPT.
    @MainActor
    static func isOffered(target: Target, store: NoteStore) -> Bool {
        let access = NoteToolAccess(store: store)
        switch target {
        case .overview: return true
        case .trash: return false
        case .folder(let id): return access.visibleFolders().contains { $0.id == id }
        case .note(let id): return access.visibleNote(key: NoteToolAccess.key(for: id)) != nil
        }
    }

    /// Opens the chat; the caller made sure that the consent is on.
    @MainActor
    static func open(_ target: Target, assistant: AssistantModel) {
        switch target {
        case .overview, .trash: assistant.open(notes: nil)
        case .folder(let id): assistant.open(notes: id)
        case .note(let id): assistant.open(note: id)
        }
    }
}

/// The assistant button of the notes: the same purple glass circle as `AssistantButton`, outermost trailing.
struct NoteAssistantToolbarItems: ToolbarContent {
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
            Button(action: action) {
                Image(systemName: "sparkles")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(.purple.opacity(0.75)).interactive(), in: .circle)
            .contentShape(Circle())
            .accessibilityLabel("Assistent")
            .accessibilityHint("Öffnet ChatGPT für deine Notizen")
        }
        .sharedBackgroundVisibility(.hidden)
    }
}

/// Adds the assistant button of the notes to a page. Without the consent "Notizen mit ChatGPT" a tap shows
/// `NoteAssistantConsentSheet` first; "Einverstanden" sets the consent and opens the chat. The sheet hangs on the page,
/// not on the toolbar item.
private struct NoteAssistantEntryModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var environment
    let target: NoteAssistantEntry.Target
    let store: NoteStore
    let isEnabled: Bool
    /// Runs before the chat opens, e.g. the editor saves its text so the assistant reads what is on the screen.
    let beforeOpening: () -> Void
    @State private var asksConsent = false

    func body(content: Content) -> some View {
        content
            .toolbar {
                if isEnabled, NoteAssistantEntry.isOffered(target: target, store: store) {
                    NoteAssistantToolbarItems(action: request)
                }
            }
            .sheet(isPresented: $asksConsent) {
                NoteAssistantConsentSheet(
                    privateFolderNames: NoteToolAccess(store: store).privateFolderNames(),
                    onAgree: {
                        environment.settings.noteAssistantConsent = true
                        asksConsent = false
                        open()
                    },
                    onDecline: { asksConsent = false })
            }
    }

    private func request() {
        if environment.settings.noteAssistantConsent { open() } else { asksConsent = true }
    }

    private func open() {
        beforeOpening()
        NoteAssistantEntry.open(target, assistant: environment.assistant)
    }
}

extension View {
    /// The assistant button of the notes for `target`; hidden where the assistant has no access (see `NoteAssistantEntry.isOffered`).
    func noteAssistantEntry(_ target: NoteAssistantEntry.Target, store: NoteStore, isEnabled: Bool = true,
                            beforeOpening: @escaping () -> Void = {}) -> some View {
        modifier(NoteAssistantEntryModifier(target: target, store: store, isEnabled: isEnabled, beforeOpening: beforeOpening))
    }
}
