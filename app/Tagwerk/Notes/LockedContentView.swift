import SwiftUI
import TagwerkCore

/// What stands in place of a protected note or folder while the lock is closed: the lock symbol, a sentence and the button
/// that asks for the device owner (NL3a, NO10c). It holds no text of the note.
struct LockedContentView: View {
    enum Kind { case note, folder }

    @Environment(AppEnvironment.self) private var environment
    let kind: Kind
    let onUnlock: () async -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondaryText)
                .accessibilityHidden(true)
            Text(kind == .note ? "Diese Notiz ist gesperrt." : "Dieser Ordner ist gesperrt.")
                .font(.headline)
            Button { Task { await onUnlock() } } label: {
                Text(Self.openTitle(environment.noteLock.biometry)).fontWeight(.semibold).frame(minWidth: 200, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("lock.open")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(kind == .note ? "lock.note" : "lock.folder")
    }

    /// The wording follows what the device offers first.
    static func openTitle(_ biometry: DeviceBiometry) -> LocalizedStringKey {
        switch biometry {
        case .faceID: "Mit Face ID öffnen"
        case .touchID: "Mit Touch ID öffnen"
        case .opticID: "Mit Optic ID öffnen"
        case .none: "Mit Gerätecode öffnen"
        }
    }
}

/// An opaque cover over protected content while the app is not active, so the app switcher shows no text.
struct LockCoverView: View {
    var body: some View {
        ZStack {
            Color(.systemBackground)
            Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(.secondaryText)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .accessibilityIdentifier("lock.cover")
    }
}
