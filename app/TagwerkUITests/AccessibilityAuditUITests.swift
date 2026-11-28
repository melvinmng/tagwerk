import XCTest

/// Automatic accessibility audit (`performAccessibilityAudit`) of the core screens in the default text size.
/// The screens are split across three focused tests (`testAuditDefaultSizeCoreTabs`, `testAuditDefaultSizeListsAndSearch` and
/// `testAuditProjectProgress`) so no single launch runs long enough to hit the XCTest/audit timeout on the CI runners.
/// Findings must be fixed or sit on `AuditAllowlist` with a reason.
final class AccessibilityAuditUITests: UITestCase {
    // A fixed time of day: the hour grid of "Planen" scrolls to the current time, so without it the audited part of the
    // grid (and with it the findings) would depend on the hour of the run.
    override var extraLaunchArguments: [String] { AuditAllowlist.fixedClockArguments + ["-TagwerkDemoFoodLookup"] }

    /// Runs the audit on the screen that is open now; findings that are not on the allowlist fail the test.
    private func audit(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: screen, for: .all)
    }

    /// The weekly review without the Dynamic Type check: for its plain `Text` rows (body style, no fixed frame, line limit or font) the
    /// audit named a different text in each of four runs on 2026-11-25 ("Do", "Mi", "Verlauf und Ziele öffnen", "Kein Gewicht erfasst"),
    /// the same flakiness the allowlist records for other screens. Large text is checked by the AX5 run (text clipped) and stays on the
    /// device test list.
    private func auditWeekReview(_ screen: String) throws {
        try AuditAllowlist.audit(app, screen: screen, for: XCUIAccessibilityAuditType.all.subtracting(.dynamicType))
    }

    /// The overview of the project progress and the parts of the page of its demo project. A test of its own so the three audited
    /// parts of the project page start from a fresh launch instead of extending the core-screen runs.
    func testAuditProjectProgress() throws {
        try auditProjectProgress(audit)
    }

    /// Core tabs and review sheets: Planen, Aufgaben, Tagesabschluss and Wochenrückblick.
    func testAuditDefaultSizeCoreTabs() throws {
        waitFor("Sprechstunde")
        try audit("Planen (Tag)")

        tab("Aufgaben")
        // The row "Projektfortschritt" at the head of the list pushes the first task below the fold, where a lazy list creates no row:
        // the row stands for the loaded list, and the screen is stable once the tasks are in.
        waitFor(AccessibilityID.ProjectProgress.entryRow)
        waitUntilScreenIsStable()
        try audit("Aufgaben")

        tab("Erfassen")
        onScreen(label: "Tagesabschluss.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Tagesabschluss"].waitForExistence(timeout: Self.timeout))
        try audit("Tagesabschluss")
        tapButton("Abschließen")
        waitUntilGone(app.navigationBars["Tagesabschluss"])

        // The weekly review: its head, the calories and the weight section (the demo data holds no weight, so the hint shows).
        onScreen(label: "Wochenrückblick, Woche.*", matching: true).tap()
        XCTAssertTrue(app.navigationBars["Wochenrückblick"].waitForExistence(timeout: Self.timeout))
        try auditWeekReview("Wochenrückblick")
        app.navigationBars.buttons.firstMatch.tap()
    }

    /// Lists, barcode scan and search: Einkaufsliste, Notizenliste, Strichcode and Suche.
    func testAuditDefaultSizeListsAndSearch() throws {
        waitFor("Sprechstunde")

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

        try auditBarcodeScan(audit)

        tab("Planen")
        // The return key closes the keyboard, so its suggestion bar is not part of the audit.
        openSearch(typing: "Pretest\n")
        waitFor("Pretest vorbereiten", timeout: 20)
        try audit("Suche")
    }
}

extension UITestCase {
    /// The barcode scan sheet in its two screens a user sees without a camera: the field for the digits, and the result of a code that is
    /// not among the own foods (the consent is declined, so nothing is sent). Erfassen › Essen › Meine Lebensmittel › "Strichcode scannen".
    /// Both sheets are closed again at the end, so the test can go on with another tab.
    func auditBarcodeScan(_ audit: (String) throws -> Void) throws {
        tab("Erfassen")
        // In the large text sizes the buttons of the quick entry lie below the fold of the page: drag until "Essen" can be hit.
        let meal = app.buttons.matching(NSPredicate(format: "label == %@", "Essen"))
        var opened = false
        for _ in 0..<12 where !opened {
            if let button = meal.allElementsBoundByIndex.first(where: { $0.isHittable }) {
                button.tap()
                opened = true
            } else {
                dragPage(towardsTop: false)
            }
        }
        XCTAssertTrue(opened, "The button Essen is not reachable by scrolling")
        selectSegment("Meine Lebensmittel")
        let row = app.buttons[AccessibilityID.FoodLookup.scanRow].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "The row Strichcode scannen is missing")
        dragUntilHittable(row)
        row.tap()
        let field = app.textFields[AccessibilityID.FoodLookup.manualField].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "The scan sheet did not open")
        try audit("Strichcode (Nummer eingeben)")

        field.tap()
        field.typeText("4012345678901")
        tapButton(AccessibilityID.FoodLookup.manualSubmit)
        tapButton("Nicht jetzt")
        XCTAssertTrue(app.buttons[AccessibilityID.FoodLookup.scanCreateFood].firstMatch.waitForExistence(timeout: Self.timeout),
                      "The result of the unknown code is missing")
        try audit("Strichcode (nicht gefunden)")

        // The upper sheet (scan) first, then the meal sheet below it; the covered "Abbrechen" is not hittable.
        onScreen(label: "Abbrechen").tap()
        waitUntilGone(app.buttons[AccessibilityID.FoodLookup.scanCreateFood].firstMatch)
        onScreen(label: "Abbrechen").tap()
    }

    /// One drag of a fixed length (no inertia) that moves the content of the page down (`towardsTop`) or up.
    func dragPage(towardsTop: Bool) {
        let from = towardsTop ? 0.35 : 0.7, to = towardsTop ? 0.65 : 0.4
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: from))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: to)))
    }

    /// Drags the page up in steps of the same length until the element exists and can be hit (at most 40 steps). For rows of a list
    /// that the system builds only when they come near the screen, so `dragUntilHittable` cannot ask for their frame yet.
    func dragUpUntilHittable(_ element: XCUIElement) {
        var steps = 0
        while !(element.exists && element.isHittable), steps < 40 {
            dragPage(towardsTop: false)
            steps += 1
        }
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
