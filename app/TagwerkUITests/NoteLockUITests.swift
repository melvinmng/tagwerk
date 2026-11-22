import XCTest

/// Shared steps of the lock tests (NL1a–NL5a). The device check is replaced by fixed answers
/// (`-TagwerkUITestLockAuthentication`), because the simulator has no Face ID prompt the tests could answer.
@MainActor
class NoteLockUITestCase: UITestCase {
    /// The answers of the device check in turn; the last one repeats (see `UITestMode.lockAuthentication`).
    var authenticationAnswers: String { "succeed" }

    override var extraLaunchArguments: [String] { ["-TagwerkUITestLockAuthentication", authenticationAnswers] }

    /// The two demo notes of "Notizen".
    static let giftTitle = "Geschenkidee für Lea"
    static let giftPreview = "Kochbuch oder Konzertkarten"
    static let ideasTitle = "Ideen Hausarbeit"

    /// Aufgaben › Notizen › the default folder "Notizen".
    func openOwnNotes(file: StaticString = #filePath, line: UInt = #line) {
        openNotes(file: file, line: line)
        let folder = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notizen, ")).firstMatch
        XCTAssertTrue(folder.waitForExistence(timeout: Self.timeout), "The folder \"Notizen\" is missing", file: file, line: line)
        folder.tap()
    }

    func card(_ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
    }

    /// Opens the context menu of a card and taps an entry.
    func choose(_ entry: String, onCard title: String, file: StaticString = #filePath, line: UInt = #line) {
        let target = card(title)
        XCTAssertTrue(target.waitForExistence(timeout: Self.timeout), "The card \(title) is missing", file: file, line: line)
        target.press(forDuration: 1.0)
        let item = app.buttons[entry].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: Self.timeout), "The menu has no entry \(entry)", file: file, line: line)
        item.tap()
    }

    /// The first lock: the explanation, then "Mit Face ID sperren" (the check passes once and leaves the session open).
    func lockWithIntro(_ title: String, file: StaticString = #filePath, line: UInt = #line) {
        choose("Sperren", onCard: title, file: file, line: line)
        let confirm = app.buttons["lock.intro.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: Self.timeout), "The explanation did not show", file: file, line: line)
        confirm.tap()
        XCTAssertTrue(confirm.waitForNonExistence(timeout: Self.timeout), "The explanation did not close", file: file, line: line)
    }

    /// "Jetzt sperren": the session closes, so locked notes are hidden.
    func closeLock(onCard title: String, file: StaticString = #filePath, line: UInt = #line) {
        choose("Jetzt sperren", onCard: title, file: file, line: line)
    }

    /// An element of the rendered page of an open note.
    func pageText(_ text: String) -> XCUIElement {
        app.webViews.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    /// Opens Einstellungen › Notizen.
    func openNotesSettings(file: StaticString = #filePath, line: UInt = #line) {
        tab("Einstellungen", file: file, line: line)
        let row = app.cells.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Notizen")).firstMatch
        var steps = 0
        while !(row.exists && row.isHittable), steps < 20 {
            let list = app.collectionViews.firstMatch
            list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.05, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)))
            steps += 1
        }
        XCTAssertTrue(row.exists && row.isHittable, "Settings row Notizen is not reachable", file: file, line: line)
        row.tap()
    }
}

/// The device check always passes.
final class NoteLockUITests: NoteLockUITestCase {
    func testLockFromMenuShowsIntroOnce() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        // The second note is locked at once: the explanation was shown and the protection is on.
        choose("Sperren", onCard: Self.ideasTitle)
        XCTAssertFalse(app.buttons["lock.intro.confirm"].waitForExistence(timeout: 2), "The explanation showed a second time")
        // Both notes carry the mark: the menu now offers to remove it.
        let target = card(Self.ideasTitle)
        target.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Sperre aufheben"].firstMatch.waitForExistence(timeout: Self.timeout), "The second note was not locked")
    }

    func testLockedCardHidesPreviewAndThumbnail() {
        openOwnNotes()
        XCTAssertTrue(card(Self.giftPreview).waitForExistence(timeout: Self.timeout), "The card does not show its preview before the lock")
        lockWithIntro(Self.giftTitle)
        closeLock(onCard: Self.giftTitle)
        let hidden = card(Self.giftTitle)
        XCTAssertTrue(hidden.waitForExistence(timeout: Self.timeout), "The title of a locked note must stay visible")
        XCTAssertTrue(hidden.label.contains("Gesperrt"), "The card does not say \"Gesperrt\": \(hidden.label)")
        XCTAssertFalse(hidden.label.contains(Self.giftPreview), "The preview of a locked note is visible: \(hidden.label)")
    }

    func testOpeningLockedNoteAsksAndShowsTextAfterSuccess() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        closeLock(onCard: Self.giftTitle)
        card(Self.giftTitle).tap()
        // The check passes at once, so the page shows the text.
        XCTAssertTrue(pageText(Self.giftPreview).waitForExistence(timeout: 3 * Self.timeout), "The note did not open after the check")
        XCTAssertFalse(app.otherElements["lock.note"].exists, "The lock screen is still there")
    }

    func testBackgroundRelocks() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        XCTAssertTrue(card(Self.giftPreview).waitForExistence(timeout: Self.timeout), "The unlocked card does not show its text")
        XCUIDevice.shared.press(.home)
        app.activate()
        let hidden = card(Self.giftTitle)
        XCTAssertTrue(hidden.waitForExistence(timeout: Self.timeout))
        eventually("The note was not locked again after the app left the foreground: \(hidden.label)") {
            self.card(Self.giftTitle).label.contains("Gesperrt")
        }
    }

    func testUnlockRemovesMark() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        choose("Sperre aufheben", onCard: Self.giftTitle)
        let target = card(Self.giftTitle)
        target.press(forDuration: 1.0)
        XCTAssertTrue(app.buttons["Sperren"].firstMatch.waitForExistence(timeout: Self.timeout), "The mark is still set")
        XCTAssertFalse(app.buttons["Sperre aufheben"].exists)
    }
}

/// The first check passes (it turns the protection on), every later one fails.
final class NoteLockDeniedUITests: NoteLockUITestCase {
    override var authenticationAnswers: String { "succeed,fail" }

    func testFailedAuthenticationKeepsLockScreen() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        closeLock(onCard: Self.giftTitle)
        card(Self.giftTitle).tap()
        XCTAssertTrue(app.descendants(matching: .any)["lock.note"].waitForExistence(timeout: Self.timeout), "The lock screen did not show")
        XCTAssertTrue(app.buttons["lock.open"].exists, "The lock screen has no button to try again")
        XCTAssertFalse(pageText(Self.giftPreview).exists, "The text is visible behind the lock screen")
    }

    func testDeleteLockedNoteAsksFirst() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        closeLock(onCard: Self.giftTitle)
        let target = card(Self.giftTitle)
        target.swipeLeft()
        let delete = app.buttons["Löschen"].firstMatch
        XCTAssertTrue(delete.waitForExistence(timeout: Self.timeout), "The swipe shows no delete action")
        delete.tap()
        // The check fails: the note stays.
        XCTAssertTrue(card(Self.giftTitle).waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(card(Self.giftTitle).exists, "A hidden note was deleted without the check")
    }

    func testPrivateFolderShowsLockScreen() {
        openOwnNotes()
        lockWithIntro(Self.giftTitle)
        // Settings › Notizen › "Private Ordner sperren" (turning it on needs no check).
        app.navigationBars.buttons.firstMatch.tap()
        openNotesSettings()
        let toggle = app.switches["notes.lock.privateFolders"]
        XCTAssertTrue(toggle.waitForExistence(timeout: Self.timeout), "The switch \"Private Ordner sperren\" is missing")
        toggle.tap()
        eventually("The switch did not turn on") { (self.app.switches["notes.lock.privateFolders"].value as? String) == "1" }
        // Close the session through the card of the list, then open the private folder.
        tab("Aufgaben")
        let journal = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Tagebuch mit Gott")).firstMatch
        XCTAssertTrue(journal.waitForExistence(timeout: Self.timeout), "The folder of the journal is missing")
        XCUIDevice.shared.press(.home)
        app.activate()
        journal.tap()
        XCTAssertTrue(app.descendants(matching: .any)["lock.folder"].waitForExistence(timeout: Self.timeout), "The private folder opened without the check")
    }
}
