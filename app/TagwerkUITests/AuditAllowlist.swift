import XCTest

/// Accepted accessibility audit findings. Every entry names the element and the audit type, and says why it is
/// accepted. A finding that needs a design decision points to the section "Designpunkte für #188" of the plan
/// (docs/superpowers/plans/2026-11-19-g3-uitests-a11y.md). Blanket exceptions per audit type are not allowed.
@MainActor
enum AuditAllowlist {
    /// Pins the time of day of the app for the audits (see `UITestMode.now`): morning, so the hour grid of "Planen" shows the
    /// seminar, the lunch break, the demo deadline and the "now" line, and "Tagesabschluss" is still reachable.
    static let fixedClockArguments = ["-TagwerkUITestNow", "09:30"]

    /// One accepted group of findings of one audit type. `labels` are regular expressions that must match the whole label
    /// (or the identifier) of the element; there is no entry without labels.
    private struct Entry {
        let auditType: XCUIAccessibilityAuditType
        let labels: [String]
        var elementType: XCUIElement.ElementType?
        /// Only on these screens (`currentScreen`); `nil` for every screen.
        var screens: [String]?
        let reason: String
    }

    /// The two screens that show the hour grid of "Planen": default size and AX5 in dark mode.
    private static let gridScreens = ["Planen (Tag)", "AX5/dark Planen"]
    /// Texts of the entries in the hour grid: titles of the demo events and their time line ("10:00–12:30", with marks after a dot).
    private static let gridCellLabels = [
        "\\d\\d:\\d\\d–\\d\\d:\\d\\d( · .*)?", "Seminar", "Sprechstunde", "Mittagspause", "(⚑ )?Abgabe Kurzbericht",
    ]

    /// The screens of the recipe audits (`AccessibilityAuditRecipesUITests`) in the default size and their AX5/dark names.
    private static let recipeScreens = [
        "Rezepte", "Rezept-Notiz", "Zutaten (Rezept)", "Rezept anlegen (Eingabe)", "Rezept anlegen (Einwilligung)",
        "Rezept anlegen (Bestätigung)", "Einkauf › Rezept hinzufügen", "Einkauf › Rezept hinzufügen (Notiz)",
        "Einstellungen › KI › Sprache", "Einstellungen › Erfassen", "Einstellungen › Einkaufsliste",
    ]
    private static let recipeScreensLargeText = recipeScreens.map { "AX5/dark " + $0 }

    private static let entries: [Entry] = [
        // MARK: Contrast (every group needs a colour decision, section "Designpunkte für #188")
        Entry(auditType: .contrast, labels: [
            "Nichts offen", "zuletzt: „(Römer|Demo Linsensuppe)“ · heute \\d+:\\d+", "[89]", "HEUTE · KW \\d+", "FR\\. .* · KW \\d+", "Ablauf", "\\d\\d:\\d\\d",
            "Schlafzeit \\d+:\\d+", "Ganztägig", "Überfällig", "Heute", "Einkaufsliste", "Notizen", "\\d+\\.\\d+\\.", "·", "Demo Aufgaben",
            "Lokal", "Routinen", "Gewohnheiten", "Woche", "Starten", "noch [\\d.]+", "Wasser", "Schritte", "Training · Woche",
            "\\d+ offen · Liste „Demo Einkauf“ in Erinnerungen", "Brot & Backwaren", "Kühlregal", "Aufgaben, 1 offen", "Vergangene Termine",
            "Ältere Termine durchsuchen · vor .*", "Durchsucht: 6 Monate zurück, 12 Monate voraus\\.",
            "ab \\d+:\\d+ bis \\d+:\\d+ · ganzer Tag .*", "1 Aufgabe ohne Aufwand mit Standarddauer gerechnet", "Pflanzen gießen",
            "Erledigt: Erinnerungen und lokale Aufgaben, ohne GitHub\\.", "Abend-Checkliste · Schlafzeit .*", "Punkte in den Einstellungen anlegen",
            "Brain Dump", "Leitfragen einfügen", "Schreib auf, was in deinen Kopf kommt\\. Sortier deine Gedanken\\.",
            "Der Eintrag bleibt auf deinem iPhone und geht nie an ChatGPT\\.", "heute \\d+:\\d+( · diktiert)?", "Bible Study · heute .*",
            "Tagebuch · .*",
            // Titles and previews of the demo notes (the label of a note preview can have several lines). The preview of a note whose
            // title is a heading line starts with the first body line, so these lines are listed as well.
            "(?s)(Demo Linsensuppe|Portionen: 4|Ideen Hausarbeit|Gliederung|Generelle Gedanken|Literaturliste|Handwerker anrufen|Heute lief die Gliederung gut|Geschenkidee für Lea|Kochbuch oder Konzertkarten|Römer|Allgemeine Stimmung|Alte Einkaufsidee|Ruhig und dankbar\\.|Heizung entlüften|1 Einleitung, 2 Methode, 3 Ergebnisse|Drei Quellen zur Statistik).*",
        ], reason: "Secondary text in the system grey (.secondary) on the grouped background or on a card: captions, counts, section "
            + "headers. Darkening it would change the look of the default size; decided together with the other grey texts in #188."),
        Entry(auditType: .contrast, labels: [
            "Ohne Uhrzeit", "0 · 0 min", "\\+3 offen", "1 überfällig", "Abgabe Kurzbericht", "Pretest vorbereiten", "Deadlines", "heute",
            "morgen", "in 3 Tagen", "Kalender Demo Uni(, .*)?", "P1", "„Seminar“ aus „Demo Freigabe“ liegt zur selben Zeit wie „Seminar“\\.",
            "Künftig immer bei „Seminar“ aus „Demo Freigabe“", "Mit ChatGPT planen: in Einstellungen › KI anmelden", "Derselbe Termin\\?",
        ], reason: "Text on tinted cards (red deadline card, pink suggestion card) and on the translucent bar of the day view, in red, orange "
            + "or grey. The colours are part of the card design; contrast on tint is a design question (#188, \"Sekundärtexte auf getönten Karten\")."),
        Entry(auditType: .contrast, labels: [
            "Auswählen", "Getrennt lassen", "Zusammenfassen", "Projektwoche", "Abbrechen", "Alle", "Termine", "✓ Erledigte", "Essen", "Trinken", "Training",
        ], reason: "Button and segment texts in the accent colour or on Liquid Glass / bordered tint (navigation bar, filter marks, quick entry). "
            + "The system draws the background; no own colour to change without replacing the system style (#188)."),

        Entry(auditType: .contrast, labels: gridCellLabels, screens: gridScreens, reason:
            "Title and time of the entries in the hour grid of \"Planen\": text in the primary or secondary colour on the event colour at 24 % "
            + "(blue, green, red, grey). The tint is the colour code of the grid (calendar, block, deadline, break); contrast on tint is a "
            + "design question (#188, \"Sekundärtexte auf getönten Karten\")."),

        // MARK: Dynamic Type
        Entry(auditType: .dynamicType, labels: ["\\d\\d:\\d\\d"] + gridCellLabels, screens: ["Planen (Tag)"], reason:
            "Hour labels and entries of the hour grid of \"Planen\": the grid is time-proportional (fixed height per hour), so its texts are "
            + "text styles but cannot grow with the size; the audit reports the partial support. Plan g3-uitests-a11y: the grid stays "
            + "proportional, visibility at large sizes is decided in #188; the full text is in the accessibility label of each entry."),
        Entry(auditType: .dynamicType, labels: ["HEUTE · KW \\d+", "[A-Z][a-z]\\. \\d+\\. [A-Z][a-zä]+\\.", "Auswählen"], reason:
            "The date title in the bar of \"Planen\" is fixed in size on purpose (a toolbar item gets no width; with accessibility sizes it shows the "
            + "shortest form, see PlanHeaderText.displayedTitle); \"Auswählen\" is a system bar button. Header design: #188 / #175."),
        Entry(auditType: .dynamicType, labels: [
            "Punkte in den Einstellungen anlegen", "Mo\\. planen", "Fertig", "Brain Dump", "Leitfragen einfügen", "\\d+\\.\\d+\\.",
        ], screens: ["Tagesabschluss"], reason: "Texts of the evening sheet (hint line, buttons, date of the next planning day) report a partial lack of "
            + "Dynamic Type support; no clipping in the large text run. Stays on the device test list."),
        Entry(auditType: .dynamicType, labels: [
            "P1", "Ältere Termine durchsuchen · vor .*", "Durchsucht: 6 Monate zurück, 12 Monate voraus\\.",
        ], reason: "Priority capsule and the hint rows of the search sheet use text styles; the audit still reports a partial lack of "
            + "support. Not reproduced by eye in the large text run (no clipping there); stays on the device test list."),

        // MARK: Text clipped
        Entry(auditType: .textClipped, labels: gridCellLabels, screens: gridScreens, reason:
            "Title and time of the entries in the hour grid of \"Planen\": the grid is time-proportional with a fixed height per hour, and "
            + "overlapping events share the width (up to four columns). Short or narrow entries cut their text by design; the full text is "
            + "in the accessibility label of the entry. Plan g3-uitests-a11y (\"Das Raster in Planen bleibt zeitproportional\"), visibility "
            + "in #188."),
        Entry(auditType: .textClipped, labels: [
            "Mit ChatGPT planen: in Einstellungen › KI anmelden", "1 Aufgabe ohne Aufwand mit Standarddauer gerechnet",
            "zuletzt: „(Römer|Demo Linsensuppe)“ · heute \\d+:\\d+", "Wochenrückblick", "Punkte in den Einstellungen anlegen",
            "Ältere Termine durchsuchen · vor .*",
        ], reason: "Reported in the default size for texts that are shown completely on the screenshot of the run (cards of \"Planen\", "
            + "entry rows of \"Aufgaben\", \"Erfassen\"). Not reproducible by eye; stays on the device test list (large text)."),
        Entry(auditType: .textClipped, labels: ["FR\\. .* · KW \\d+", "[\\d.]+ / [\\d.]+"], reason:
            "Date caption and steps value of \"Erfassen\" in the largest text size: single-line summary cells. Layout for AX sizes is a "
            + "design decision (#188, \"Layout bei Bedienungshilfen-Schriftgrößen\")."),
        Entry(auditType: .textClipped, labels: [""], elementType: .textField, reason:
            "Text fields (shopping input, search field) report their placeholder as clipped; the field itself is a single line with a fixed "
            + "pill height. Layout for AX sizes: #188."),

        // MARK: Recipe screens and settings (G1, G2)
        Entry(auditType: .contrast, labels: [
            "Rezepttext", "Füge die Zutatenliste oder das ganze Rezept ein\\. .*", "Du kannst das in den Einstellungen unter „Einkaufsliste“ widerrufen\\.",
            "Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert\\. .*", "Portionen", "\\d+", "Die Kategorien kommen aus deiner Einkaufsliste\\.",
            "Vorlesen", "ChatGPT", "Notiz", "(?s)Eine Notiz mit den Abschnitten .*", "(?s)Notizen liegen nur auf diesem iPhone\\..*",
            "(?s)Die gewählte Liste erscheint als Einkaufsliste\\..*", "(?s)Sendet auf dein Tippen die Namen .*", "(?s)„Rezept hinzufügen“ sendet .*",
            "(?s)Portionen: \\d+\\nZutaten.*", "strukturiert", "wird mit ChatGPT gelesen",
            "(?s)(Gesendet wird|Nicht gesendet werden|Um ein Rezept zu lesen).*", "(?s)„In Planen anzeigen“ zeigt .*",
        ], screens: recipeScreens + recipeScreensLargeText, reason: "Section headers, footers, values and previews in the system grey (.secondary) on the "
            + "grouped background of a form or list; the last footer of a settings page also lies behind the tab bar. Same group as the "
            + "grey texts above; darkening it would change the look of the default size, decided in #188."),
        Entry(auditType: .contrast, labels: [
            "Einverstanden", "Nicht jetzt", "Rezept speichern", "\\d+ Artikel hinzufügen", "Verwerfen", "Neues Rezept", "Rezept mit ChatGPT anlegen",
            "Andere Notiz wählen …", "Demo Linsensuppe",
        ], screens: recipeScreens + recipeScreensLargeText, reason: "Texts in the accent colour (list buttons, note title in the picker), white on the "
            + "prominent button (system style) and \"Verwerfen\" in the navigation bar, whose Liquid Glass background lets the list scroll behind it. "
            + "The system draws the background; no own colour to change without replacing the system style (#188)."),

        Entry(auditType: .dynamicType, labels: [
            "Abbrechen", "Verwerfen", "Die Kategorien kommen aus deiner Einkaufsliste\\.", "Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert\\. .*",
            "\\d\\. .*", "Vorlesen", "Eiweiß-Ziel", "(?s)Sendet auf dein Tippen die Namen .*", "Rezepte mit ChatGPT lesen", "ChatGPT",
            "(?s)Notizen liegen nur auf diesem iPhone\\..*",
        ], screens: recipeScreens, reason: "Navigation bar buttons, form rows, footers and steps use text styles; the audit still reports a partial lack of "
            + "support. In the AX5 run of the same screens (`AccessibilityAuditRecipesLargeTextUITests`, screenshots checked) every one of these texts "
            + "grows and wraps."),
        Entry(auditType: .textClipped, labels: [
            "Rezept mit ChatGPT anlegen", "Neues Rezept", "Demo Linsensuppe", "Andere Notiz wählen …", "Füge die Zutatenliste oder das ganze Rezept ein\\. .*",
            "(?s)(Um ein Rezept zu lesen|Gesendet wird|Nicht gesendet werden|Eine Notiz mit den Abschnitten|Die gewählte Liste erscheint|Portionen: \\d+\\nZutaten).*",
            "Du kannst das in den Einstellungen unter „Einkaufsliste“ widerrufen\\.", "Mikrofon in Gesprächen",
        ], screens: recipeScreens + recipeScreensLargeText, reason: "The audit warns that these texts \"may be clipped at larger Dynamic Type sizes\". "
            + "Checked on the AX5 screenshots of these screens: headings, buttons, notes and footers wrap completely, some run past the lower edge "
            + "of the scroll view (the audit counts that as clipped). The navigation title \"Rezept mit ChatGPT anlegen\" is truncated by the "
            + "system bar (large title at AX sizes still cuts it): device test list, design decision in #188."),

        // MARK: Hit area
        Entry(auditType: .hitRegion, labels: ["Eingabe löschen"], reason:
            "The clear button of the search field is a 17 pt glyph inside the 44 pt high field; a bigger frame would shift the field text. "
            + "Design question, together with the check circle of the lists (#188)."),
    ]

    /// Runs the audit on the open screen and fails the test for every finding that is not on the allowlist.
    ///
    /// The contrast check runs as a pass of its own. In a combined run (`.all`) the audit also switches the system text size for
    /// the Dynamic Type check, and the elements of the contrast findings can no longer be resolved afterwards: they arrive
    /// as `nil` ("Contrast nearly passed" for a `SwiftUI.AccessibilityNode` without label and frame), which no allowlist entry
    /// can match. Run alone, the same findings come with their elements. The findings are collected in the handler and judged
    /// after the audit, so the slow element queries of the judgement do not run while the audit is still reporting.
    static func audit(_ app: XCUIApplication, screen: String, for auditTypes: XCUIAccessibilityAuditType,
                      file: StaticString = #filePath, line: UInt = #line) throws {
        currentScreen = screen
        let passes = auditTypes.contains(.contrast) && auditTypes != .contrast ? [.contrast, auditTypes.subtracting(.contrast)] : [auditTypes]
        for pass in passes {
            var findings: [(issue: XCUIAccessibilityAuditIssue, element: XCUIElement?)] = []
            try app.performAccessibilityAudit(for: pass) { issue in
                findings.append((issue, issue.element))
                return true
            }
            for finding in findings where !isAccepted(finding.issue, element: finding.element) {
                let element = finding.element
                XCTFail("\(screen): \(finding.issue.compactDescription) | \(finding.issue.detailedDescription) | "
                    + "label=\(element?.label ?? "-") id=\(element?.identifier ?? "-") frame=\(element?.frame ?? .zero)", file: file, line: line)
            }
        }
    }

    private static func isAccepted(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement?) -> Bool {
        let accepted = matchesAllowlist(issue, element: element)
        // Collect mode lists the findings that the allowlist does not cover yet; nothing fails.
        if collectsFindings {
            if !accepted { record(issue, element: element) }
            return true
        }
        return accepted
    }

    private static func matchesAllowlist(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement?) -> Bool {
        // Findings without an element cannot be matched by label; only the ones named here are accepted, per screen.
        guard let element else {
            return currentScreen == "Notizenliste" && issue.auditType == .textClipped
            // Reason: the audit reports one clipped text without an element (frame 0×0) in the note list; nothing on the
            // screen is cut off visually. Stays on the device test list (large text).
        }
        func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: "^(\(pattern))$", options: .regularExpression) != nil }
        // Every read of an element property is a query of its own and slow, so each is read once per finding.
        let label = element.label, identifier = element.identifier, elementType = element.elementType
        return entries.contains { entry in
            guard entry.auditType == issue.auditType, entry.screens == nil || entry.screens?.contains(currentScreen) == true,
                  entry.elementType == nil || entry.elementType == elementType else { return false }
            return entry.labels.contains { pattern in
                matches(label, pattern) || (!identifier.isEmpty && matches(identifier, pattern))
            }
        }
    }

    // MARK: Collect mode

    /// With `TEST_RUNNER_AUDIT_COLLECT_FILE=<path>` the audits do not fail; every finding that is not on the allowlist is appended to the file instead.
    /// Used to list the findings that are neither fixed nor on the allowlist.
    private static var collectFile: String? { ProcessInfo.processInfo.environment["AUDIT_COLLECT_FILE"] }
    static var collectsFindings: Bool { collectFile != nil }

    static var currentScreen = ""

    private static func record(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement?) {
        guard let path = collectFile else { return }
        let line = "\(currentScreen) | \(issue.auditType.rawValue) | \(issue.compactDescription) | label=\(element?.label ?? "-") "
            + "frame=\(element?.frame ?? .zero) id=\(element?.identifier ?? "-") type=\(element?.elementType.rawValue ?? 0)\n"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
