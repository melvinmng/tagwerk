import Foundation
import LocalAuthentication
import Observation
import TagwerkCore

/// Checks that the person holding the phone is its owner: Face ID or Touch ID, then the device passcode.
protocol DeviceOwnerAuthenticating: Sendable {
    /// The device can check its owner: a passcode is set.
    func canAuthenticate() -> Bool
    /// What the device offers first, for the wording of the switch ("Mit Face ID schützen").
    func biometry() -> DeviceBiometry
    /// Face ID or Touch ID, then the device passcode. `false` when the user cancels or fails.
    func authenticate(reason: String) async -> Bool
}

enum DeviceBiometry: Sendable, Equatable {
    case faceID, touchID, opticID, none
}

/// The system check (`LocalAuthentication`, policy `deviceOwnerAuthentication`).
struct SystemDeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    func canAuthenticate() -> Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    func biometry() -> DeviceBiometry {
        let context = LAContext()
        var error: NSError?
        // `biometryType` is only filled after a policy was evaluated for the biometric policy.
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else { return .none }
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        case .opticID: return .opticID
        default: return .none
        }
    }

    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Answers the checks with fixed results, for the UI tests (`UITestMode.lockAuthentication`). The simulator has no Face ID
/// prompt the tests could answer. The answers are used in turn, the last one repeats.
final class FixedDeviceOwnerAuthenticator: DeviceOwnerAuthenticating, @unchecked Sendable {
    private let answers: [Bool]
    private let lock = NSLock()
    private var next = 0

    init(answers: [Bool]) { self.answers = answers }

    func canAuthenticate() -> Bool { true }
    func biometry() -> DeviceBiometry { .faceID }
    func authenticate(reason: String) async -> Bool {
        lock.withLock {
            defer { next += 1 }
            return answers[min(next, answers.count - 1)]
        }
    }
}
#endif

/// The lock session of the notes (NL1a): one unlock opens every protected note and folder until the app goes to the
/// background or "Jetzt sperren" is tapped. It hides content. While it is open the assistant may read and edit the notes the user
/// locked, but never private kinds and folders (`NoteStore.isPrivate`, `NoteStore.lockHoldsBack`); when it closes the assistant's
/// note session ends (`onSessionClosed`), so no unlocked text stays in it.
@MainActor
@Observable
final class NoteLock {
    private(set) var isUnlocked = false
    /// The device has a passcode; read again when the app becomes active (`refresh()`).
    private(set) var canAuthenticate: Bool
    private(set) var biometry: DeviceBiometry

    @ObservationIgnored private let settings: AppSettings
    @ObservationIgnored private let authenticator: any DeviceOwnerAuthenticating
    /// The check that runs right now; a second request waits for it instead of asking again.
    @ObservationIgnored private var pending: Task<Bool, Never>?
    /// Runs when the lock closes (`lockNow`, the app leaving the foreground).
    @ObservationIgnored var onLock: (@MainActor () -> Void)?
    /// Runs when an open session ends (`lockNow`, the app leaving the foreground, turning the protection off): the assistant forgets
    /// what it read of unlocked notes. Not called when the lock was closed anyway.
    @ObservationIgnored var onSessionClosed: (@MainActor () -> Void)?

    init(settings: AppSettings, authenticator: any DeviceOwnerAuthenticating) {
        self.settings = settings
        self.authenticator = authenticator
        canAuthenticate = authenticator.canAuthenticate()
        biometry = authenticator.biometry()
    }

    /// The settings as the rules read them.
    var protection: NoteProtection.Settings {
        NoteProtection.Settings(isEnabled: settings.noteLockEnabled, locksPrivateFolders: settings.noteLockPrivateFolders,
                                canAuthenticate: canAuthenticate)
    }

    /// Reads the passcode state again (it may have changed in the iOS settings).
    func refresh() {
        canAuthenticate = authenticator.canAuthenticate()
        biometry = authenticator.biometry()
    }

    // MARK: Session

    /// Asks once; a second call while a prompt is open waits for the first. `true` when the lock is open afterwards.
    func unlock(reason: String) async -> Bool {
        if isUnlocked { return true }
        guard canAuthenticate else { return false }
        if let pending { return await pending.value }
        let task = Task { [authenticator] in
            let succeeded = await authenticator.authenticate(reason: reason)
            if succeeded { self.isUnlocked = true }
            return succeeded
        }
        pending = task
        let succeeded = await task.value
        pending = nil
        return succeeded
    }

    /// "Jetzt sperren".
    func lockNow() {
        closeSession()
        onLock?()
    }

    /// Closes the session; tells `onSessionClosed` only when it was open.
    private func closeSession() {
        let wasOpen = isUnlocked
        isUnlocked = false
        if wasOpen { onSessionClosed?() }
    }

    /// The app went to the background: everything is closed again.
    func appDidEnterBackground() {
        lockNow()
    }

    // MARK: Settings

    /// Turning protection on asks once; turning it off asks too and leaves the marks of the notes alone (rule 8: the notes
    /// are then open without a prompt, but stay private). Without a passcode nothing can be protected, so it cannot be turned
    /// on; it can always be turned off then, because nothing is protected anyway.
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != settings.noteLockEnabled else { return true }
        refresh()
        if enabled {
            guard canAuthenticate, await unlock(reason: Self.reason) else { return false }
            settings.noteLockEnabled = true
            return true
        }
        if canAuthenticate, !(await unlock(reason: Self.reason)) { return false }
        settings.noteLockEnabled = false
        closeSession()
        return true
    }

    /// "Private Ordner sperren": turning it on needs no check, turning it off opens the private folders and asks first.
    func setLocksPrivateFolders(_ locks: Bool) async -> Bool {
        guard locks != settings.noteLockPrivateFolders else { return true }
        if !locks, protection.isActive, !(await unlock(reason: Self.reason)) { return false }
        settings.noteLockPrivateFolders = locks
        return true
    }

    /// Lets the store read the session: a locked note is open to the assistant while this session is open
    /// (`NoteProtection.holdsBack`), and held back otherwise. With an assistant, the end of the session ends its note session too.
    func attach(to store: NoteStore, endingNoteSessionOf assistant: AssistantModel? = nil) {
        store.lockHoldsBack = { [weak self] isLocked in
            guard let self else { return isLocked }
            return NoteProtection.holdsBack(isLocked: isLocked, isSessionOpen: isUnlocked, settings: protection)
        }
        onSessionClosed = { [weak assistant] in assistant?.endNoteSession() }
    }

    // MARK: Concealment

    /// The note is covered by the lock (rule 1), whether or not it is unlocked right now.
    func isProtected(_ note: NoteRecord, privateFolderIDs: Set<UUID>) -> Bool {
        let isPrivateContent = !NoteFolderRules.mayLeaveDevice(kind: note.kind, folderID: note.folderID, privateFolderIDs: privateFolderIDs)
        return NoteProtection.isProtected(isLocked: note.isLocked, isPrivateContent: isPrivateContent, settings: protection)
    }

    func isProtected(_ note: NoteRecord, in store: NoteStore) -> Bool {
        guard protection.isActive else { return false }
        return isProtected(note, privateFolderIDs: NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info)))
    }

    /// Protected content that is not unlocked: it shows the lock screen and no text, preview, picture or count.
    func isConcealed(_ note: NoteRecord, privateFolderIDs: Set<UUID>) -> Bool {
        !isUnlocked && isProtected(note, privateFolderIDs: privateFolderIDs)
    }

    func isConcealed(_ note: NoteRecord, in store: NoteStore) -> Bool {
        guard !isUnlocked, protection.isActive else { return false }
        return isConcealed(note, privateFolderIDs: NoteFolderRules.privateFolderIDs(in: store.folders().map(\.info)))
    }

    /// Whether "Sperren" is offered for the note (rule 6).
    func canLock(_ note: NoteRecord, privateFolderIDs: Set<UUID>) -> Bool {
        NoteProtection.canLock(kind: note.kind, isInPrivateFolder: note.folderID.map(privateFolderIDs.contains) ?? false,
                               settings: protection)
    }

    /// Locking for the first time, or with the switch off, shows the explanation first (`NoteLockIntroSheet`).
    var needsIntro: Bool { !settings.noteLockEnabled || !settings.noteLockExplained }

    func markExplained() { settings.noteLockExplained = true }

    /// Runs `action` at once when nothing in `concealed` hides, otherwise after the device owner passed the check. Deleting,
    /// moving and removing the mark of hidden notes goes through here (rule 7).
    func afterUnlock(whenConcealed concealed: Bool, _ action: @escaping @MainActor () -> Void) {
        guard concealed else { return action() }
        Task {
            if await unlock(reason: Self.reason) { action() }
        }
    }

    /// A private folder with the switch "Private Ordner sperren" that is not unlocked.
    func isConcealed(folderID: UUID, privateFolderIDs: Set<UUID>) -> Bool {
        !isUnlocked && NoteProtection.isProtectedFolder(isPrivateFolder: privateFolderIDs.contains(folderID), settings: protection)
    }

    /// The sentence for a locked note where the assistant is offered (#233 B9 shows it under "Mit ChatGPT bearbeiten"). The
    /// assistant reads and edits a locked note while it is unlocked, until the user leaves Tagwerk.
    static func assistantNotice(isUnlocked: Bool) -> String {
        isUnlocked
            ? String(localized: "Entsperrt: Der Assistent kann diese Notiz lesen und ändern, bis du Tagwerk verlässt.")
            : String(localized: "Gesperrt: Diese Notiz geht nicht an ChatGPT. Entsperre sie, wenn der Assistent sie lesen soll.")
    }

    /// The reason the system prompt shows.
    static var reason: String { String(localized: "Tagwerk entsperrt damit gesperrte Notizen und private Ordner.") }
}
