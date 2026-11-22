import SwiftUI
import TagwerkCore

/// Settings → Notizen → "Gesperrte Notizen": every note with the lock mark, titles only. The list opens after the device owner
/// was checked; a tap opens the note, where "Sperre aufheben" is in the menu.
struct LockedNotesView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let lock = environment.noteLock
        let store = environment.notes
        // With the protection off the list is open like the notes themselves.
        let isHidden = lock.protection.isActive && !lock.isUnlocked
        Group {
            if isHidden {
                LockedContentView(kind: .folder) { _ = await lock.unlock(reason: NoteLock.reason) }
            } else {
                List {
                    let notes = store.notes(.all).filter(\.isLocked) + store.notes(.trash).filter(\.isLocked)
                    if notes.isEmpty {
                        Text("Keine gesperrten Notizen.").foregroundStyle(.secondaryText)
                    }
                    ForEach(notes, id: \.id) { note in
                        NavigationLink {
                            NoteEditorView(noteID: note.id, store: store, showsAssistant: false)
                        } label: {
                            let title = NoteText.title(note.text)
                            Label(title.isEmpty ? String(localized: "Ohne Titel") : title, systemImage: note.deletedAt == nil ? "lock" : "trash")
                        }
                    }
                }
            }
        }
        .navigationTitle("Gesperrte Notizen")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { if lock.protection.isActive, scenePhase != .active { LockCoverView() } }
        .task(id: isHidden && scenePhase == .active) {
            guard isHidden, scenePhase == .active else { return }
            _ = await lock.unlock(reason: NoteLock.reason)
        }
    }
}
