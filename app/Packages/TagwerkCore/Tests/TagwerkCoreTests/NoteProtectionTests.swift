import Testing
@testable import TagwerkCore

struct NoteProtectionTests {
    private func settings(enabled: Bool = true, privateFolders: Bool = false, passcode: Bool = true) -> NoteProtection.Settings {
        NoteProtection.Settings(isEnabled: enabled, locksPrivateFolders: privateFolders, canAuthenticate: passcode)
    }

    @Test func lockedNote_protectedOnlyWhileEnabled() {
        #expect(NoteProtection.isProtected(isLocked: true, isPrivateContent: false, settings: settings()))
        #expect(!NoteProtection.isProtected(isLocked: true, isPrivateContent: false, settings: settings(enabled: false)))
        #expect(!NoteProtection.isProtected(isLocked: false, isPrivateContent: false, settings: settings()))
    }

    @Test func privateNote_protectedOnlyWithFolderSwitch() {
        #expect(!NoteProtection.isProtected(isLocked: false, isPrivateContent: true, settings: settings(privateFolders: false)))
        #expect(NoteProtection.isProtected(isLocked: false, isPrivateContent: true, settings: settings(privateFolders: true)))
        // The folder switch does nothing while the main switch is off.
        #expect(!NoteProtection.isProtected(isLocked: false, isPrivateContent: true, settings: settings(enabled: false, privateFolders: true)))
    }

    @Test func withoutPasscode_nothingIsProtected() {
        let none = settings(privateFolders: true, passcode: false)
        #expect(!NoteProtection.isProtected(isLocked: true, isPrivateContent: true, settings: none))
        #expect(!NoteProtection.isProtectedFolder(isPrivateFolder: true, settings: none))
    }

    @Test func canLock_ownAndRoutineNotes_yes() {
        for kind in [NoteKind.free, .morning, .evening] {
            #expect(NoteProtection.canLock(kind: kind, isInPrivateFolder: false, settings: settings(privateFolders: true)))
        }
    }

    @Test func canLock_privateKinds_never() {
        for kind in [NoteKind.journal, .bibleStudy, .dream] {
            #expect(!NoteProtection.canLock(kind: kind, isInPrivateFolder: true, settings: settings(privateFolders: false)))
            #expect(!NoteProtection.canLock(kind: kind, isInPrivateFolder: false, settings: settings(privateFolders: false)))
        }
    }

    @Test func canLock_noteInPrivateFolder_followsFolderSwitch() {
        #expect(!NoteProtection.canLock(kind: .free, isInPrivateFolder: true, settings: settings(privateFolders: true)))
        #expect(NoteProtection.canLock(kind: .free, isInPrivateFolder: true, settings: settings(privateFolders: false)))
        #expect(NoteProtection.canLock(kind: .free, isInPrivateFolder: true, settings: settings(enabled: false, privateFolders: true)))
    }

    @Test func folder_privateWithSwitch() {
        #expect(NoteProtection.isProtectedFolder(isPrivateFolder: true, settings: settings(privateFolders: true)))
        #expect(!NoteProtection.isProtectedFolder(isPrivateFolder: true, settings: settings(privateFolders: false)))
        #expect(!NoteProtection.isProtectedFolder(isPrivateFolder: false, settings: settings(privateFolders: true)))
        #expect(!NoteProtection.isProtectedFolder(isPrivateFolder: true, settings: settings(enabled: false, privateFolders: true)))
    }
}
