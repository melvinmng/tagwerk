import SwiftUI
import TagwerkCore

/// The explanation before the first lock (NL2a): shown while "Mit Face ID schützen" is still off or was never explained. The
/// button turns the protection on, asks the device owner once and then locks the notes.
struct NoteLockIntroSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let onLock: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.tint)
                        .frame(maxWidth: .infinity)
                        .accessibilityHidden(true)
                    point("faceid", NoteLockIntroSheet.openText(environment.noteLock.biometry), nil)
                    point("textformat", "In Listen und Suche bleibt der Titel sichtbar", "Der Titel ist die erste Zeile der Notiz.")
                    point("icloud.slash", "Geht nur entsperrt an ChatGPT", "Gesperrt sieht der Assistent die Notiz nicht. Entsperrt kann er sie lesen und ändern, bis du Tagwerk verlässt.")
                    point("doc", "Steht unverschlüsselt in der Sicherung", nil)
                    Button { Task { await onLock() } } label: {
                        Text(Self.lockTitle(environment.noteLock.biometry)).fontWeight(.semibold).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!environment.noteLock.canAuthenticate)
                    .accessibilityIdentifier("lock.intro.confirm")
                    if !environment.noteLock.canAuthenticate {
                        Text("Richte zuerst einen Code für dein iPhone ein.").font(.footnote).foregroundStyle(.secondaryText)
                    }
                }
                .padding()
            }
            .navigationTitle("Notiz sperren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen", action: onCancel) }
            }
        }
        .presentationDetents([.large])
    }

    private func point(_ symbol: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey?) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).fontWeight(.semibold)
                if let detail { Text(detail).font(.footnote).foregroundStyle(.secondaryText) }
            }
        }
    }

    static func openText(_ biometry: DeviceBiometry) -> LocalizedStringKey {
        switch biometry {
        case .faceID: "Öffnen nur mit Face ID oder Gerätecode"
        case .touchID: "Öffnen nur mit Touch ID oder Gerätecode"
        case .opticID: "Öffnen nur mit Optic ID oder Gerätecode"
        case .none: "Öffnen nur mit dem Gerätecode"
        }
    }

    static func lockTitle(_ biometry: DeviceBiometry) -> LocalizedStringKey {
        switch biometry {
        case .faceID: "Mit Face ID sperren"
        case .touchID: "Mit Touch ID sperren"
        case .opticID: "Mit Optic ID sperren"
        case .none: "Mit Gerätecode sperren"
        }
    }
}

/// Presents `NoteLockIntroSheet` for the notes in `ids`; a tap on its button turns the protection on and locks them.
private struct NoteLockIntroModifier: ViewModifier {
    @Environment(AppEnvironment.self) private var environment
    @Binding var ids: [UUID]
    let store: NoteStore

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { !ids.isEmpty }, set: { if !$0 { ids = [] } })) {
            NoteLockIntroSheet(
                onLock: {
                    let toLock = ids
                    if await environment.noteLock.setEnabled(true) {
                        environment.noteLock.markExplained()
                        store.setLocked(toLock, true)
                        ids = []
                    }
                },
                onCancel: { ids = [] })
        }
    }
}

extension View {
    /// The explanation before the first lock for the notes in `ids` (empty: not shown).
    func noteLockIntro(ids: Binding<[UUID]>, store: NoteStore) -> some View {
        modifier(NoteLockIntroModifier(ids: ids, store: store))
    }
}

extension NoteLock {
    /// "Sperren": locks at once, or shows the explanation first (`introFor` gets the ids).
    func requestLock(_ ids: [UUID], store: NoteStore, introFor: ([UUID]) -> Void) {
        guard !ids.isEmpty else { return }
        if needsIntro { introFor(ids) } else { store.setLocked(ids, true) }
    }

    /// "Sperre aufheben": asks the device owner first while the mark protects something that is hidden right now (rule 7).
    func removeLock(_ ids: [UUID], store: NoteStore) {
        afterUnlock(whenConcealed: protection.isActive && !isUnlocked) { store.setLocked(ids, false) }
    }
}
