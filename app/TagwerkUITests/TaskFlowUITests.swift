import XCTest

final class TaskFlowUITests: UITestCase {
    func testCreateEditCompleteUndo() {
        tab("Aufgaben")
        tapButton("Neue Aufgabe")

        // A local task: no calendar or reminder write, so the list of the demo data stays as it is.
        onScreen(label: "Lokal").tap()
        typeIn("Titel", text: "UI-Test Aufgabe")
        tapButton("Hinzufügen")
        let created = app.descendants(matching: .any)[AccessibilityID.Tasks.row("UI-Test Aufgabe")]
        // A task without a due date sits at the end of the list, which builds its rows only when scrolled to.
        scrollTo(created)

        // Edit: change the title in the editor.
        created.tap()
        replaceText(of: app.textFields[AccessibilityID.Tasks.editorTitle].firstMatch, with: "UI-Test Aufgabe geändert")
        tapButton("Sichern")
        let edited = app.descendants(matching: .any)[AccessibilityID.Tasks.row("UI-Test Aufgabe geändert")]
        scrollTo(edited)
        waitUntilGone(created)

        // Complete with the swipe action; the capsule offers "Rückgängig".
        edited.swipeRight()
        tapButton("Erledigt")
        waitUntilGone(edited)
        tapButton("Rückgängig")
        scrollTo(edited)
    }
}
