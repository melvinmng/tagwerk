import Foundation
import SwiftData
import Testing
import TagwerkCore
@testable import Tagwerk

/// A device check the test controls: it answers at once, or waits until the test lets it answer.
final class FakeDeviceOwnerAuthenticator: DeviceOwnerAuthenticating, @unchecked Sendable {
    private let lock = NSLock()
    private var state = (passcode: true, result: true, prompts: 0, holds: false)
    private var waiting: [CheckedContinuation<Void, Never>] = []

    var passcode: Bool { get { lock.withLock { state.passcode } } set { lock.withLock { state.passcode = newValue } } }
    var result: Bool { get { lock.withLock { state.result } } set { lock.withLock { state.result = newValue } } }
    var holds: Bool { get { lock.withLock { state.holds } } set { lock.withLock { state.holds = newValue } } }
    var prompts: Int { lock.withLock { state.prompts } }

    func canAuthenticate() -> Bool { passcode }
    func biometry() -> DeviceBiometry { .faceID }

    func authenticate(reason: String) async -> Bool {
        lock.withLock { state.prompts += 1 }
        if holds {
            await withCheckedContinuation { continuation in lock.withLock { waiting.append(continuation) } }
        }
        return result
    }

    /// Lets every waiting check answer.
    func release() {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            state.holds = false
            defer { waiting = [] }
            return waiting
        }
        for continuation in continuations { continuation.resume() }
    }

    var waitingCount: Int { lock.withLock { waiting.count } }
}

@MainActor
struct NoteLockTests {
    let container: ModelContainer
    let settings: AppSettings
    let authenticator = FakeDeviceOwnerAuthenticator()
    let lock: NoteLock

    init() throws {
        container = try ModelContainerFactory.make(inMemory: true)
        settings = try AppSettings.current(in: container.mainContext)
        lock = NoteLock(settings: settings, authenticator: authenticator)
    }

    @Test func unlock_success_setsUnlocked() async {
        #expect(await lock.unlock(reason: "Test"))
        #expect(lock.isUnlocked)
        // Unlocked once: the next request does not ask again.
        #expect(await lock.unlock(reason: "Test"))
        #expect(authenticator.prompts == 1)
    }

    @Test func unlock_failure_staysLocked() async {
        authenticator.result = false
        #expect(!(await lock.unlock(reason: "Test")))
        #expect(!lock.isUnlocked)
    }

    @Test func unlock_twoCalls_promptOnce() async {
        authenticator.holds = true
        async let first = lock.unlock(reason: "Test")
        // The second call comes while the first prompt is open.
        while authenticator.waitingCount == 0 { await Task.yield() }
        async let second = lock.unlock(reason: "Test")
        for _ in 0..<20 { await Task.yield() }
        authenticator.release()
        let results = await [first, second]
        #expect(results == [true, true])
        #expect(authenticator.prompts == 1)
    }

    @Test func lockNow_locks() async {
        _ = await lock.unlock(reason: "Test")
        lock.lockNow()
        #expect(!lock.isUnlocked)
    }

    @Test func background_locks() async {
        _ = await lock.unlock(reason: "Test")
        lock.appDidEnterBackground()
        #expect(!lock.isUnlocked)
    }

    @Test func setEnabledOn_asksOnce_andTurnsProtectionOn() async {
        #expect(await lock.setEnabled(true))
        #expect(settings.noteLockEnabled && lock.protection.isActive)
        #expect(authenticator.prompts == 1)
    }

    @Test func setEnabledOn_withFailedCheck_staysOff() async {
        authenticator.result = false
        #expect(!(await lock.setEnabled(true)))
        #expect(!settings.noteLockEnabled)
    }

    @Test func setEnabledOn_withoutPasscode_fails() async {
        authenticator.passcode = false
        #expect(!(await lock.setEnabled(true)))
        #expect(!settings.noteLockEnabled)
        #expect(authenticator.prompts == 0)
    }

    @Test func setEnabledOff_requiresAuthentication_keepsMarks() async throws {
        let notes = NoteStore(context: container.mainContext)
        lock.attach(to: notes)
        let note = try #require(notes.create(text: "Geheim"))
        #expect(await lock.setEnabled(true))
        notes.setLocked([note.id], true)
        lock.lockNow()
        // A failed check leaves the protection on.
        authenticator.result = false
        #expect(!(await lock.setEnabled(false)))
        #expect(settings.noteLockEnabled)
        // A passed check turns it off, the mark stays, and the note stays held back from the assistant (rule 8 and rule 4): with
        // the protection off nothing can be unlocked.
        authenticator.result = true
        #expect(await lock.setEnabled(false))
        #expect(!settings.noteLockEnabled)
        #expect(note.isLocked && notes.isPrivate(note))
        #expect(!lock.isConcealed(note, in: notes))
    }

    @Test func setLocksPrivateFolders_off_asksFirst() async {
        #expect(await lock.setEnabled(true))
        #expect(await lock.setLocksPrivateFolders(true))
        lock.lockNow()
        authenticator.result = false
        #expect(!(await lock.setLocksPrivateFolders(false)))
        #expect(settings.noteLockPrivateFolders)
    }

    @Test func isConcealed_followsSessionAndRules() async throws {
        let notes = NoteStore(context: container.mainContext)
        let locked = try #require(notes.create(text: "Gesperrt"))
        let free = try #require(notes.create(text: "Frei"))
        let journal = notes.openJournalEntry(dayKey: "2026-11-18", locale: Locale(identifier: "de_DE"))
        notes.setLocked([locked.id], true)
        // Switch off: nothing is concealed, although the mark stays.
        #expect(!lock.isConcealed(locked, in: notes))
        #expect(await lock.setEnabled(true))
        lock.lockNow()
        #expect(lock.isConcealed(locked, in: notes))
        #expect(!lock.isConcealed(free, in: notes))
        // Private folders follow their own switch.
        #expect(!lock.isConcealed(journal, in: notes))
        #expect(await lock.setLocksPrivateFolders(true))
        #expect(lock.isConcealed(journal, in: notes))
        #expect(await lock.unlock(reason: "Test"))
        #expect(!lock.isConcealed(locked, in: notes) && !lock.isConcealed(journal, in: notes))
    }

    // MARK: Rule 4: the assistant and the session

    /// A locked note is private while the lock is closed, open to the assistant while it is unlocked, and private again when the
    /// lock closes. Private kinds and folders stay private in every state.
    @Test func isPrivate_lockedNote_followsTheSession() async throws {
        let notes = NoteStore(context: container.mainContext)
        lock.attach(to: notes)
        let locked = try #require(notes.create(text: "Gesperrt"))
        let free = try #require(notes.create(text: "Frei"))
        let journal = notes.openJournalEntry(dayKey: "2026-11-18", locale: Locale(identifier: "de_DE"))
        notes.setLocked([locked.id], true)
        // Before the protection is on nothing can be unlocked: the mark keeps the note back.
        #expect(notes.isPrivate(locked) && !notes.isPrivate(free) && notes.isPrivate(journal))
        #expect(await lock.setEnabled(true))
        // The check that turned the protection on left the session open: the locked note is open to the assistant.
        #expect(lock.isUnlocked)
        #expect(!notes.isPrivate(locked) && !notes.isPrivate(free) && notes.isPrivate(journal))
        #expect(NoteToolAccess(store: notes).visibleNotes().map(\.id).contains(locked.id))
        lock.lockNow()
        #expect(notes.isPrivate(locked) && !notes.isPrivate(free) && notes.isPrivate(journal))
        #expect(!NoteToolAccess(store: notes).visibleNotes().map(\.id).contains(locked.id))
        #expect(await lock.unlock(reason: "Test"))
        #expect(!notes.isPrivate(locked) && notes.isPrivate(journal))
    }

    /// The folder switch protects the private folders as well, but an unlocked private folder still never reaches the assistant,
    /// and a locked note inside one stays private, too.
    @Test func privateFolders_neverReachTheAssistant_evenUnlocked() async throws {
        let notes = NoteStore(context: container.mainContext)
        lock.attach(to: notes)
        #expect(await lock.setEnabled(true))
        #expect(await lock.setLocksPrivateFolders(true))
        let journalFolder = notes.ensureJournalFolder()
        let inJournal = try #require(notes.create(text: "Freie Notiz im Tagebuch-Ordner", folderID: journalFolder.id))
        let lockedInJournal = try #require(notes.create(text: "Gesperrte Notiz im Tagebuch-Ordner", folderID: journalFolder.id))
        let dream = try #require(notes.create(text: "Traum", kind: .dream, dayKey: "2026-11-18"))
        notes.setLocked([lockedInJournal.id], true)
        #expect(await lock.unlock(reason: "Test"))
        #expect(lock.isUnlocked)
        for note in [inJournal, lockedInJournal, dream] { #expect(notes.isPrivate(note), "\(note.kind)") }
        #expect(NoteToolAccess(store: notes).visibleNotes().isEmpty)
    }

    @Test func onSessionClosed_firesWhenAnOpenSessionEnds() async {
        var calls = 0
        lock.onSessionClosed = { calls += 1 }
        // A lock that is closed anyway ends nothing.
        lock.lockNow()
        lock.appDidEnterBackground()
        #expect(calls == 0)
        #expect(await lock.unlock(reason: "Test"))
        lock.lockNow()
        #expect(calls == 1)
        #expect(await lock.unlock(reason: "Test"))
        lock.appDidEnterBackground()
        #expect(calls == 2)
        lock.lockNow()
        #expect(calls == 2)
    }

    @Test func turningTheProtectionOff_endsTheOpenSession() async {
        var calls = 0
        #expect(await lock.setEnabled(true))
        lock.onSessionClosed = { calls += 1 }
        #expect(await lock.setEnabled(false))
        #expect(!lock.isUnlocked && calls == 1)
    }
}
