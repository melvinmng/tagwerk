import XCTest

/// Automatic accessibility audit (`performAccessibilityAudit`) of the core screens in the default text size.
/// One launch covers all screens, to keep the run short. Findings must be fixed or sit on `AuditAllowlist` with a reason.
final class AccessibilityAuditUITests: UITestCase {
    // A fixed time of day: the hour grid of "Planen" scrolls to the current time, so without it the audited part of the
    // grid (and with it the findings) would depend on the hour of the run.
    override var extraLaunchArguments: [String] { AuditAllowlist.fixedClockArguments }

    /// Runs the audit on the screen that is open now; findings that are not on the allowlist fail the test.
    private func audit(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: screen, for: .all)
    }

    func testAuditDefaultSize() throws {
        waitFor("Sprechstunde")
        try audit("Planen (Tag)")

        tab("Aufgaben")
        waitFor("Pflanzen gießen")
        try audit("Aufgaben")

        tab("Erfassen")
        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout))
        try audit("Tagesabschluss")
        tapButton("Abschließen")
        waitUntilGone(app.navigationBars["Tagesabschluss"])

        openShoppingList()
        for item in ["Milch", "Brot"] {
            app.textFields["Artikel hinzufügen"].tap()
            app.textFields["Artikel hinzufügen"].typeText(item + "\n")
            waitFor(item)
        }
        // The notice above the input ("1 hinzugefügt") fades out after four seconds; audited while it is visible, it adds a
        // finding that depends on how fast the run is.
        waitUntilStaysGone(app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", "hinzugefügt")).firstMatch)
        try audit("Einkaufsliste")
        app.navigationBars.buttons.firstMatch.tap()

        openNotes()
        let allNotes = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Alle Notizen")).firstMatch
        XCTAssertTrue(allNotes.waitForExistence(timeout: Self.timeout))
        allNotes.tap()
        XCTAssertTrue(app.navigationBars["Alle Notizen"].waitForExistence(timeout: Self.timeout))
        try audit("Notizenliste")


        tab("Planen")
        // The return key closes the keyboard, so its suggestion bar is not part of the audit.
        openSearch(typing: "Pretest\n")
        waitFor("Pretest vorbereiten", timeout: 20)
        try audit("Suche")
    }
}

extension UITestCase {
    /// One drag of a fixed length (no inertia) that moves the content of the page down (`towardsTop`) or up.
    func dragPage(towardsTop: Bool) {
        let from = towardsTop ? 0.35 : 0.7, to = towardsTop ? 0.65 : 0.4
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)))
    }

    /// Drags the page in steps of the same length until the element can be hit (at most 40 steps): down while the element lies
    /// above the screen, up otherwise.
    func dragUntilHittable(_ element: XCUIElement) {
        var steps = 0
        while !element.isHittable, steps < 40 {
            dragPage(towardsTop: element.frame.maxY <= 0)
            steps += 1
        }
    }
}

/// The leftover row and section ("Unerledigtes verschieben", "Unerledigt von heute") exist only after the end of work. In the
/// standard run (09:30) they never show, so they get their own run with the clock pinned to 19:30 (today is a working day in the
/// UI test mode, so the result does not depend on the weekday). `LeftoverLine` has to wrap at accessibility sizes: the large text
/// variant checks that.
@MainActor
class EveningAuditCase: UITestCase {
    override var extraLaunchArguments: [String] { UITestCase.eveningClockArguments }

    /// "Planen" (capacity card with the leftover row) and "Tagesabschluss" (leftover section).
    func auditLeftovers(planScreen: String, eveningScreen: String, audit: (String) throws -> Void) throws {
        // The hour grid scrolls to "now" (19:30), which moves the capacity card with the leftover row above the visible part:
        // the row exists in the tree but is not on screen, and the audit only sees what is shown. The page is moved down in drags
        // of a fixed length (a swipe ends in inertia that differs from run to run, which showed other parts of the grid each time).
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Unerledigtes verschieben")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The leftover row is missing at 19:30")
        waitUntilScreenIsStable()
        dragUntilHittable(row)
        XCTAssertTrue(row.isHittable, "The leftover row cannot be scrolled into view")
        try audit(planScreen)

        tab("Erfassen")
        // In the large text size the entry lies below the fold of the list. "Planen" and "Erfassen" keep copies of the
        // neighbouring pages in the tree, so only a hittable match counts.
        let entries = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "Tagesabschluss.*"))
        var opened = false
        for _ in 0..<12 where !opened {
            if let entry = entries.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                entry.tap()
                opened = true
            } else {
                dragPage(towardsTop: false)
            }
        }
        XCTAssertTrue(opened, "The entry Tagesabschluss is not reachable by scrolling")
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout))
        waitFor("Unerledigt von heute")
        try audit(eveningScreen)
    }
}

final class AccessibilityAuditEveningUITests: EveningAuditCase {
    func testAuditLeftoversInTheEvening() throws {
        try auditLeftovers(planScreen: "Planen (Abend)", eveningScreen: "Tagesabschluss (Abend)") {
            try AuditAllowlist.audit(app, screen: $0, for: .all)
        }
    }
}

final class AccessibilityAuditEveningLargeTextUITests: EveningAuditCase {
    override var extraLaunchArguments: [String] { super.extraLaunchArguments + ["-TagwerkUITestTextSize", "accessibility5", "-TagwerkUITestDark"] }

    func testAuditLeftoversInTheEveningLargestTextAndDark() throws {
        try auditLeftovers(planScreen: "AX5/dark Planen (Abend)", eveningScreen: "AX5/dark Tagesabschluss (Abend)") {
            try AuditAllowlist.audit(app, screen: $0, for: [.textClipped, .contrast])
        }
    }
}
