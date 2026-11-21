import XCTest

/// The action cards of the assistant offer "Anpassen" (plan ki-vorschlaege-anpassen, task B1). The chat runs on the demo
/// transport (`-TagwerkDemoAI`), whose scripted answer proposes the task "Demo-Aufgabe"; nothing is sent.
@MainActor
class AssistantCardUITestCase: UITestCase {
    override var extraLaunchArguments: [String] { ["-TagwerkDemoAI"] }

    /// Opens the assistant of the task tab, sends a message and waits for the proposed card.
    func openProposedCard(file: StaticString = #filePath, line: UInt = #line) {
        tab("Aufgaben")
        onScreen(label: "Assistent", file: file, line: line).tap()
        let field = app.textFields["Nachricht …"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "The chat has no message field", file: file, line: line)
        field.tap()
        field.typeText("Leg eine Aufgabe an")
        tapButton("Senden")
        XCTAssertTrue(app.buttons["Bestätigen"].firstMatch.waitForExistence(timeout: 20), "The proposed card did not appear", file: file, line: line)
    }
}

final class AssistantCardUITests: AssistantCardUITestCase {
    /// "Anpassen" opens the sheet with the fields; a new title written with "Fertig" shows on the card with the mark, and the
    /// card is still a proposal (nothing was carried out).
    func testActionCard_adjustButton_opensSheet() {
        openProposedCard()
        tapButton("Anpassen")
        XCTAssertTrue(app.navigationBars["Vorschlag anpassen"].waitForExistence(timeout: Self.timeout), "The sheet did not open")

        let title = app.textFields["Titel"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "The sheet has no title field")
        replaceText(of: title, with: "Zahnarzt anrufen")
        // The chat behind the sheet has a "Fertig" of its own; this one belongs to the sheet.
        app.navigationBars["Vorschlag anpassen"].buttons["Fertig"].tap()

        waitFor("Zahnarzt anrufen")
        waitFor("von dir angepasst")
        XCTAssertTrue(app.buttons["Bestätigen"].firstMatch.exists, "The adjusted card must stay a proposal")
        // The sheet offers the way back once the card carries the mark.
        tapButton("Anpassen")
        tapButton("Zurück zum Vorschlag der KI")
        waitFor("Demo-Aufgabe")
        XCTAssertFalse(app.descendants(matching: .any)["von dir angepasst"].exists, "The mark must be gone after the reset")
    }
}

/// The three buttons of a card in the largest text size: "Bestätigen" gets its own row, nothing leaves the screen.
final class AssistantCardLargeTextUITests: AssistantCardUITestCase {
    override var extraLaunchArguments: [String] { super.extraLaunchArguments + ["-TagwerkUITestTextSize", "accessibility5"] }

    func testActionCard_threeButtons_wrapInLargestTextSize() {
        openProposedCard()
        let decline = app.buttons["Verwerfen"].firstMatch
        let adjust = app.buttons["Anpassen"].firstMatch
        let confirm = app.buttons["Bestätigen"].firstMatch
        for button in [decline, adjust, confirm] { XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "\(button) missing") }

        let screen = app.windows.firstMatch.frame
        for (name, button) in [("Verwerfen", decline), ("Anpassen", adjust), ("Bestätigen", confirm)] {
            XCTAssertGreaterThanOrEqual(button.frame.minX, screen.minX, "\(name) leaves the screen on the left")
            XCTAssertLessThanOrEqual(button.frame.maxX, screen.maxX + 1, "\(name) leaves the screen on the right")
            XCTAssertGreaterThan(button.frame.width, 0, "\(name) has no width")
        }
        // "Bestätigen" in its own row below the other two (they may share a row or wrap themselves).
        XCTAssertGreaterThanOrEqual(confirm.frame.minY, max(decline.frame.maxY, adjust.frame.maxY) - 1,
                                    "\"Bestätigen\" must sit below \"Verwerfen\" and \"Anpassen\" in the largest text size "
                                    + "(Verwerfen \(decline.frame), Anpassen \(adjust.frame), Bestätigen \(confirm.frame))")
    }
}

/// The follow-up line of the sheet "Vorschlag anpassen": the answer of the demo ChatGPT fills the title field and carries the
/// mark of ChatGPT, "Rückgängig" brings back the title from before, and the card changes only with "Fertig".
final class AssistantCardFollowUpUITests: AssistantCardUITestCase {
    func testFollowUp_fillsFieldsUndoAndCardChangesOnlyWithDone() {
        openProposedCard()
        tapButton("Anpassen")
        let sheet = app.navigationBars["Vorschlag anpassen"]
        XCTAssertTrue(sheet.waitForExistence(timeout: Self.timeout), "The sheet did not open")

        // A quick reply sends the message; the demo answer adds "(später)" to the title.
        let reply = app.buttons["Später"].firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: Self.timeout), "The sheet has no quick reply")
        reply.tap()
        waitFor("von ChatGPT angepasst")
        let title = app.textFields["Titel"].firstMatch
        eventually("The title field did not take the answer") { ((title.value as? String) ?? "").contains("(später)") }

        // The card behind the sheet has not changed yet.
        tapButton("Rückgängig")
        eventually("Rückgängig did not bring the title back") { ((title.value as? String) ?? "") == "Demo-Aufgabe" }

        // Answer again and take it over with "Fertig": the card shows the new title and the mark of ChatGPT.
        app.buttons["Später"].firstMatch.tap()
        eventually("The title field did not take the second answer") { ((title.value as? String) ?? "").contains("(später)") }
        sheet.buttons["Fertig"].tap()
        waitFor("Demo-Aufgabe (später)")
        waitFor("von ChatGPT angepasst")
        XCTAssertTrue(app.buttons["Bestätigen"].firstMatch.exists, "The adjusted card must stay a proposal")
    }
}

/// "Alle anpassen …": the chip over the input names the reference, "Senden" revises the open cards, the old card stays in the
/// chat as "Überarbeitet" and the demo ChatGPT proposes a new one (task B5).
final class AssistantReviseAllUITests: AssistantCardUITestCase {
    func testReviseAll_marksOldCardAsRevisedAndProposesNew() {
        openProposedCard()
        tapButton("Alle anpassen …")
        waitFor("Zum offenen Vorschlag")
        let field = app.textFields["Nachricht …"].firstMatch
        field.tap()
        field.typeText("Lieber nächste Woche")
        tapButton("Senden")

        waitFor("Überarbeitet")
        // A new proposal follows; the chip is gone with the send.
        XCTAssertTrue(app.buttons["Bestätigen"].firstMatch.waitForExistence(timeout: 20), "No new proposal after the revision")
        XCTAssertFalse(app.descendants(matching: .any)["Zum offenen Vorschlag"].exists, "The reference must end with the send")
    }
}
