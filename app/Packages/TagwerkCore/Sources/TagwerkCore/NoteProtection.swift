import Foundation

/// Which notes and folders the lock covers (NL1a). One lock for locked notes and private folders: the switch "Mit Face ID
/// schützen" turns it on, "Private Ordner sperren" adds the private notes and folders, and one unlock opens everything
/// until the app goes to the background.
///
/// The lock hides content in the app. Whether a note may leave the device is decided by `NoteFolderRules.mayLeaveDevice`: private
/// kinds and folders never leave, a note the user locked is available to the assistant only while the lock session is open
/// (`holdsBack`), because the user unlocked it on purpose until they leave Tagwerk.
public enum NoteProtection {
    public struct Settings: Sendable, Equatable {
        /// "Mit Face ID schützen".
        public var isEnabled: Bool
        /// "Private Ordner sperren".
        public var locksPrivateFolders: Bool
        /// The device can check its owner: a passcode is set.
        public var canAuthenticate: Bool

        public init(isEnabled: Bool, locksPrivateFolders: Bool, canAuthenticate: Bool) {
            self.isEnabled = isEnabled
            self.locksPrivateFolders = locksPrivateFolders
            self.canAuthenticate = canAuthenticate
        }

        /// The lock does anything at all: it is on and the device can check its owner. Without a passcode nothing is protected.
        public var isActive: Bool { isEnabled && canAuthenticate }
    }

    /// Rule 1: a note is protected when the lock is active and the note is locked itself or, with the switch "Private Ordner
    /// sperren", private by its kind or folder. Protected content is hidden until the lock is unlocked.
    public static func isProtected(isLocked: Bool, isPrivateContent: Bool, settings: Settings) -> Bool {
        guard settings.isActive else { return false }
        return isLocked || (settings.locksPrivateFolders && isPrivateContent)
    }

    /// Rule 4: whether the lock keeps a note away from the assistant, suggestions and translations right now. Only a note the user
    /// locked is held back, and only while it is not unlocked: the lock is active and its session is open (unlocked with Face ID or
    /// the passcode, until the app goes to the background or "Jetzt sperren"). With the switch off or without a passcode nothing can
    /// be unlocked, so a locked note stays held back. Private kinds and folders are not decided here; they never leave the device.
    public static func holdsBack(isLocked: Bool, isSessionOpen: Bool, settings: Settings) -> Bool {
        isLocked && !(settings.isActive && isSessionOpen)
    }

    /// Rule 6: which notes the menu entry "Sperren" is offered for: the user's own notes and the notes of Tagesstart,
    /// Tagesabschluss, Brain Dump and Rezepte. A private note (journal, Bible Study, dream log, or anything in a private folder)
    /// is protected by the folder switch instead; the entry is missing there while "Private Ordner sperren" is on. Private notes
    /// of a kind that is private by itself are never offered (their folder is the way to protect them).
    public static func canLock(kind: NoteKind, isInPrivateFolder: Bool, settings: Settings) -> Bool {
        guard !kind.isPrivate else { return false }
        return !(isInPrivateFolder && settings.isEnabled && settings.locksPrivateFolders)
    }

    /// Whether a folder shows the lock screen instead of its list: a private folder with the switch "Private Ordner sperren".
    public static func isProtectedFolder(isPrivateFolder: Bool, settings: Settings) -> Bool {
        settings.isActive && settings.locksPrivateFolders && isPrivateFolder
    }
}
