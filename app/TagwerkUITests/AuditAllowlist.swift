import XCTest

/// Accepted accessibility audit findings. Every entry names the element and the audit type, and says why it is
/// accepted. A finding that needs a design decision points to the section "Designpunkte für #188" of the plan
/// (docs/superpowers/plans/2026-11-19-g3-uitests-a11y.md). Blanket exceptions per audit type are not allowed. The only rule that is not an entry
/// is geometric and narrow: contrast findings of content that lies mostly under a system bar (`underSystemBar`).
@MainActor
enum AuditAllowlist {
    /// Pins the time of day of the app for the audits (see `UITestMode.now`): morning, so the hour grid of "Planen" shows the
    /// seminar, the lunch break, the demo deadline and the "now" line, and "Tagesabschluss" is still reachable. The weekday is pinned to
    /// Sunday, so "Tagesabschluss" always contains the section "Wochenplanung starten" instead of only on the Sundays of the runs.
    static let fixedClockArguments = UITestCase.morningSundayClockArguments

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

    /// The screens that show the hour grid of "Planen": default size and AX5 in dark mode, in the morning run and in the evening run.
    private static let gridScreens = ["Planen (Tag)", "AX5/dark Planen", "Planen (Abend)", "AX5/dark Planen (Abend)"]
    /// The two screens of the pinned evening run (after the end of work): the capacity card with the leftover row on top of the hour grid.
    private static let eveningSheetScreens = ["Tagesabschluss (Abend)", "AX5/dark Tagesabschluss (Abend)"]
    private static let eveningPlanScreens = ["Planen (Abend)", "AX5/dark Planen (Abend)"]
    /// Texts of the entries in the hour grid: titles of the demo events and their time line ("10:00–12:30", with marks after a dot).
    private static let gridCellLabels = [
        "\\d\\d:\\d\\d–\\d\\d:\\d\\d( · .*)?", "Seminar", "Sprechstunde", "Mittagspause", "(⚑ )?Abgabe Kurzbericht",
    ]

    /// The screens of the recipe audits (`AccessibilityAuditRecipesUITests`) in the default size and their AX5/dark names.
    private static let recipeScreens = [
        "Rezepte", "Rezept-Notiz", "Zutaten (Rezept)", "Rezept anlegen (Eingabe)", "Rezept anlegen (Einwilligung)",
        "Rezept anlegen (Bestätigung)", "Einkauf › Rezept hinzufügen", "Einkauf › Rezept hinzufügen (Notiz)",
        "Einkaufsliste › Karte „übersetzen“", "Einkaufsliste › Übersetzung",
        "Einstellungen › Sprachen", "Einstellungen › KI › Sprache", "Einstellungen › Erfassen", "Einstellungen › Einkaufsliste",
        "Einstellungen › Siri & Kurzbefehle",
    ]
    private static let recipeScreensLargeText = recipeScreens.map { "AX5/dark " + $0 }
    /// The page "Siri & Kurzbefehle" in both audit runs.
    private static let siriScreens = ["Einstellungen › Siri & Kurzbefehle", "AX5/dark Einstellungen › Siri & Kurzbefehle"]

    /// The pages of the data backup (`BackupUITests`).
    private static let backupScreens = [
        "Einstellungen › Datensicherung", "Einstellungen › Datensicherung › Was wird gesichert?",
        "Einstellungen › Datensicherung › Verschlüsselung", "Einstellungen › Datensicherung › Sicherheitskopien",
    ]

    /// A screen name and its name in the large text run (AX5, dark mode).
    private static func withLargeText(_ screens: [String]) -> [String] { screens + screens.map { "AX5/dark " + $0 } }
    /// The screens on which the secondary texts of the first contrast entry were reported (collect runs of 2026-11-25), with
    /// "Erfassen" for its patterns of the capture page; restricting the entry keeps new grey texts on other pages visible.
    private static let secondaryTextScreens = withLargeText([
        "Aufgaben", "Notizenliste", "Rezepte", "Suche", "Einkaufsliste", "Einkaufsliste › Karte „übersetzen“", "Erfassen",
        "Tagesabschluss", "Tagesabschluss (Abend)", "Einstellungen › Suche",
    ]) + gridScreens
    /// The screens with bar buttons, filter marks and quick entry buttons on Liquid Glass (collect runs of 2026-11-25).
    private static let glassButtonScreens = withLargeText([
        "Aufgaben", "Suche", "Erfassen", "Tagesabschluss", "Tagesabschluss (Abend)", "Einkauf › Rezept hinzufügen",
        "Einkauf › Rezept hinzufügen (Notiz)", "Rezept anlegen (Eingabe)", "Strichcode (Nummer eingeben)", "Strichcode (nicht gefunden)",
        // The picker sheets of a GitHub issue: the audit reported only "Abbrechen" on the glass of the bar (run of 2026-11-25).
        "Neue Aufgabe › Repository wählen", "Neue Aufgabe › Projekte",
    ]) + gridScreens

    private static let entries: [Entry] = [
        // MARK: Contrast (every group needs a colour decision, section "Designpunkte für #188")
        Entry(auditType: .contrast, labels: [
            "zuletzt: „(Römer|Demo Linsensuppe)“ · heute \\d+:\\d+", "HEUTE · KW \\d+", "\\d\\d:00", "Überfällig", "Heute", "·", "Lokal",
            "Aufgaben, 1 offen", "Vergangene Termine", "Durchsucht: 6 Monate zurück, 12 Monate voraus\\.",
            "1 Aufgabe ohne Aufwand mit Standarddauer gerechnet", "Pflanzen gießen",
            "Trinkportionen", "heute \\d+:\\d+( · diktiert)?",
            // Section headers of the notes overview and the date groups of the notes list (NF1, NF3), in the tone `secondaryText` like the others.
            "Meine Ordner", "Persönlich", "Angeheftet", "Letzte 7 Tage",
            "(Januar|Februar|März|April|Mai|Juni|Juli|August|September|Oktober|November|Dezember) \\d{4}",
            // Titles and previews of the demo notes (the label of a note preview can have several lines). The preview of a note whose
            // title is a heading line starts with the first body line, so these lines are listed as well.
            "(?s)(Demo Linsensuppe|Portionen: 4|Ideen Hausarbeit|Gliederung|Generelle Gedanken|Literaturliste|Handwerker anrufen|Heute lief die Gliederung gut|Geschenkidee für Lea|Kochbuch oder Konzertkarten|Römer|Allgemeine Stimmung|Alte Einkaufsidee|Ruhig und dankbar\\.|Heizung entlüften|1 Einleitung, 2 Methode, 3 Ergebnisse|Drei Quellen zur Statistik).*",
            "Ganztägig", "Leitfragen einfügen", "Punkte in den Einstellungen anlegen",
            "[A-Z]{2}\\.,? .* · KW \\d+", "Ablauf", "Schlafzeit \\d+:\\d+",
            "Routinen", "Gewohnheiten", "Woche", "Starten", "noch [\\d.]+", "Wasser", "Schritte", "Training · Woche",
            // The line under a hit of the settings search: the pages that lead to the setting (`SettingsSearchResults`).
            "KI", "KI › Spracheingabe und Vorlesen",
            "ab (jetzt · )?\\d+:\\d+ bis \\d+:\\d+ · ganzer Tag .*",
        ], screens: secondaryTextScreens, reason: "Secondary text in the tone `secondaryText` (78 % of the label colour, strand K) on the grouped background or on a card: captions, "
            + "counts, section headers, hour labels. Strand K cut the findings of this group from 279 to 102 in three repetitions each "
            + "(measured with `--collect-all`, see docs/superpowers/reports/2026-11-21-g3-contrast-measurements.md); these patterns were still reported "
            + "in at least one repetition after the change. The audit measures the rendered small text, and 78 % is the value the calculation "
            + "gave (KO1a). Next step (plan K5, step 3): raise the asset value and measure again; not done within the measurement limit of "
            + "three repetitions, and a darker grey changes the look of the default size, so the value is the user's decision (#188)."
            + " Decision D1 (2026-11-25) moved the plain `Text` of the section headers and footers of the shopping list, the evening sheet and "
            + "the settings, recipe, voice and backup pages from the system grey to `secondaryText` (`scripts/check-colors.py` guards these files); "
            + "the value of `secondaryText` stays (D2). Struck because a collect run on the code before the change reported them and two runs "
            + "after it reported none: \"Brot & Backwaren\", \"Kühlregal\", \"Erledigt: Erinnerungen.*\", \"Abend-Checkliste · Schlafzeit .*\", "
            + "\"Brain Dump\" and the footer of \"Zeit mit Gott\"."
            + " Patterns that no finding matched in either measurement stay: the evening runs of the measurement are incomplete (one of three failed "
            + "each time) and earlier runs reported them; only patterns that were reported in every repetition before and in none after were struck."),
        Entry(auditType: .contrast, labels: [
            "heute", "Kalender Demo Uni(, .*)?",
            "„Seminar“ aus „Demo Freigabe“ liegt zur selben Zeit wie „Seminar“\\.", "Künftig immer bei „Seminar“ aus „Demo Freigabe“",
            "Mit ChatGPT planen: in Einstellungen › KI anmelden", "Derselbe Termin\\?", "1 überfällig", "Abgabe Kurzbericht", "Pretest vorbereiten",
            "Deadlines", "in 3 Tagen", "P1",
            "\\d+:\\d+–\\d+:\\d+ · .*", "Tagesabschluss", "morgen", "Klausur Statistik", "Anmeldung Abschlussarbeit", "\\d+ h \\d+ noch frei",
        ], screens: gridScreens + ["Aufgaben", "AX5/dark Aufgaben"], reason: "Text on tinted cards (red deadline card, pink suggestion card), on the translucent bar of the day view and on the capacity line and "
            + "the \"Tagesabschluss\" line of the day card (#268; \"9:00–18:00 · 1 h Pause · …\"), in the tones "
            + "`redText`, `orangeText`, `purpleText` or `secondaryText`. Part of the overdue/deadline texts pass since strand K "
            + "(default size and AX5: 65 findings before, 26 after in three repetitions each, measured before the day card of #268 existed). The tint of the card changes with the content behind the translucent bar, so the "
            + "pair is not fixed by a colour alone (#188, \"Sekundärtexte auf getönten Karten\")."
            + " Decision D4 (2026-11-25) gave the day panel of \"Planen\" and the capacity card a solid `secondarySystemGroupedBackground` instead of "
            + "`.bar` and `.thinMaterial`; \"Ohne Uhrzeit\", \"0 · 0 min\" and \"+N offen\" (the header line of the panel) were reported on the code "
            + "before and in none of two runs after it, and are struck. What remains here is the merge suggestion card on its purple tint and "
            + "texts that do not sit on the card."
            + " Patterns that no finding matched in either measurement stay: the evening runs of the measurement are incomplete (one of three failed "
            + "each time) and earlier runs reported them; only patterns that were reported in every repetition before and in none after were struck."),
        Entry(auditType: .contrast, labels: ["P\\d", "Demo Aufgaben"], screens: ["Aufgaben"], reason: "The priority mark and the section title of the last rows that reach under the translucent tab bar of "
            + "\"Aufgaben\" (frame at the lower edge of the screen, behind the bar). The row \"Bible Study\" above the list moved the rows down, so "
            + "the audit measures the mark against the glass of the bar; it is a position artefact of the demo list, not a colour of the mark itself "
            + "(same group as the other texts on the translucent bar, #188)."),
        Entry(auditType: .contrast, labels: ["7-Tage-Mittel am Ende der Woche.*"], screens: ["Wochenrückblick"], reason:
            "Footer of the weight section of the weekly review at the lower edge of the first screen: measured on 2026-11-25 at the frame "
            + "(16, 807, 370 × 62 pt) on a screen 874 pt high, that is completely behind the translucent tab bar (it starts at about 791 pt), "
            + "so the audit measures the text in `secondaryText` against the glass of the bar, not against the grouped background. Position "
            + "artefact of the demo data, the same group as the last rows of \"Aufgaben\" behind the bar."),
        Entry(auditType: .contrast, labels: [
            "Auswählen", "Getrennt lassen", "Zusammenfassen", "Abbrechen", "Fertig", "Termine", "✓ Erledigte", "Essen", "Trinken", "Training",
        ], screens: glassButtonScreens, reason: "Button and segment texts on Liquid Glass or on bordered tint (navigation bar, filter marks, quick entry). The accent colour "
            + "(`AccentColor`, #005FCC) is not the cause any more: \"Alle\" and the accent texts of the recipe screens pass since strand K. What "
            + "remains is text whose background the system draws and lets the list scroll behind; no own colour to change without replacing the "
            + "system style (#188, \"Schrift auf Liquid Glass\")."
            + " The all-day pill \"Projektwoche\" has a solid fill since D4 (2026-11-25) and was struck after two collect runs that did not report "
            + "it; CI reported it again (see the entry for the translucent bars of \"AX5/dark Planen\" below), so it is not accepted here."
            + " Patterns that no finding matched in either measurement stay: the evening runs of the measurement are incomplete (one of three failed "
            + "each time) and earlier runs reported them; only patterns that were reported in every repetition before and in none after were struck."),

        Entry(auditType: .contrast, labels: ["Abschließen"], screens: ["Tagesabschluss", "Tagesabschluss (Abend)", "AX5/dark Tagesabschluss (Abend)"], reason:
            "Confirmation button of the wrap-up sheet in the navigation bar: the text sits on the Liquid Glass of the bar, whose background "
            + "lets the list scroll behind it. \"Fertig\" was narrower and passed; the longer \"Abschließen\" (#188 TA3) reaches over more of the "
            + "list and is reported (morning and evening run at the default size, and the AX5 run of the evening sheet in dark mode). The system draws the background; same group as \"Verwerfen\" and \"Auswählen\" above (#188, "
            + "\"Schrift auf Liquid Glass\")."),
        Entry(auditType: .contrast, labels: [
            "Morgen planen", "30 min zu viel", "Arbeitszeit vorbei · .*", "[A-Z][a-z]\\. \\d+\\. [A-Za-zä]+\\. · .* frei · \\d+ von heute übrig",
            "Unerledigtes verschieben · \\d+ Aufgaben?",
        ], screens: eveningPlanScreens, reason:
            "Texts of the capacity card of today after the end of work (\"Arbeitszeit vorbei\", the next planning day, the leftover row, the "
            + "\"Tagesabschluss\" line). The card has a solid `secondarySystemGroupedBackground` since D4 (2026-11-25; it was `.thinMaterial`), which "
            + "did not remove the group: the next planning day line (\"Do. 26. Nov. · … frei · 1 von heute übrig\"), the leftover row and \"Morgen "
            + "planen\" were still reported after the change (two runs; before the change: one run), so the material was not the (only) cause. "
            + "\"Klausur Statistik\", \"Anmeldung Abschlussarbeit\" and \"Tagesabschluss\" were struck: the entry of the tinted cards above "
            + "lists them as well and is matched first on the same screens, so they could never match here. "
            + "The patterns that no finding matched before or after the change stay until the list is pruned: earlier runs reported them in "
            + "some repetitions and not in others."),

        Entry(auditType: .contrast, labels: [
            "Mit ChatGPT besprechen", "Britisches Englisch", "Markennamen lassen",
            "Senden gibt die Namen deiner offenen Artikel, die Übersetzung mit deinen Änderungen und deine Nachricht an ChatGPT\\. Mengen gehen nicht mit\\.",
        ], screens: ["Einkaufsliste › Übersetzung", "AX5/dark Einkaufsliste › Übersetzung"], reason:
            "Header, footer and quick replies of the follow-up section of the translation preview (plan ki-vorschlaege-anpassen, task D5): "
            + "the header and the footer in `secondaryText` (the tone of strand K) and the quick replies of the shared follow-up bar, on the "
            + "grouped background of the half-height sheet. Decision D3 (2026-11-25) changed the quick replies from the system `.bordered` "
            + "style with `.tint(.purple)` to `purpleText` on a 15 % purple tint (`FollowUpChipButtonStyle`). The audit still reports the two "
            + "chips in the default size and at AX5 and the footer at AX5 (2 findings per chip before the change, 2 after), as it reports every "
            + "text of this sheet, including the primary text of \"Milk\" and \"Milch\" below; the measurement on this sheet is the cause, not "
            + "the colour pair (#188, \"Schrift auf Tönung\")."),

        Entry(auditType: .contrast, labels: [
            "Mit ChatGPT besprechen", "Senden gibt das Rezept .*", "Fehlt etwas\\?",
        ], screens: recipeScreens + recipeScreensLargeText, reason:
            "Header, footer and quick replies of the follow-up section of the recipe sheets (plan ki-vorschlaege-anpassen, task D2): the "
            + "header and footer in `secondaryText` and the quick replies of the shared follow-up bar on the grouped background. Decision D3 "
            + "(2026-11-25) changed the quick replies to `purpleText` on a 15 % purple tint (`FollowUpChipButtonStyle`); \"Ohne Gewürze\" and "
            + "\"Mengen runden\" were reported on the code before and in none of two runs after the change and are struck. \"Fehlt etwas?\" is "
            + "still reported (1 finding before, 1 after per run) with the same text colour as the struck chips, so it is a measurement or "
            + "position effect (the chip at the right edge of the row), not the colour pair (#188, \"Schrift auf Tönung\")."),
        Entry(auditType: .contrast, labels: ["\\d+\\. .*"], screens: ["Rezept anlegen (Bestätigung)", "AX5/dark Rezept anlegen (Bestätigung)"], reason:
            "Steps of the recipe on the confirmation of \"Rezept speichern\" (plan ki-vorschlaege-anpassen, task D2): with the follow-up section "
            + "above them the list is longer than the screen, and the audit measures the rows that lie partly under the translucent bottom bar "
            + "with \"Rezept speichern\" against the material of the bar (primary text, normally 15:1 on the grouped background). The row "
            + "scrolls clear of the bar; the finding is the measurement on the material, like the other rows under a bar."),
        Entry(auditType: .contrast, labels: gridCellLabels, screens: gridScreens, reason:
            "Title of the grey entries of the hour grid of \"Planen\" (\"Sprechstunde\", \"Mittagspause\"): primary text on the event colour at "
            + "24 % (grey). The time line (`gridTimeText`, 85 %, KO3a) and the titles on blue, green and red pass since strand K; the grey "
            + "tint is the colour code of the grid (break, appointment without calendar colour), and the audit still reports its title in "
            + "default size (6 findings before, 4 after, three repetitions each). Contrast on tint is a design question (#188)."),

        // MARK: Dynamic Type
        Entry(auditType: .dynamicType, labels: ["\\d\\d:\\d\\d"] + gridCellLabels, screens: ["Planen (Tag)", "Planen (Abend)"], reason:
            "Hour labels and entries of the hour grid of \"Planen\": the grid is time-proportional (fixed height per hour), so its texts are "
            + "text styles but cannot grow with the size; the audit reports the partial support. Plan g3-uitests-a11y: the grid stays "
            + "proportional, visibility at large sizes is decided in #188; the full text is in the accessibility label of each entry."),
        Entry(auditType: .dynamicType, labels: [
            "HEUTE · KW \\d+", "[A-Z][a-z]\\. \\d+\\. [A-Z][a-zä]+\\.", "[A-Z][a-zäöü]+, \\d+\\. [A-Z][a-zä]+\\.?", "Auswählen",
        ], screens: ["Aufgaben"] + gridScreens, reason:
            "The date title in the bar of \"Planen\" is fixed in size on purpose (a toolbar item gets no width; it shows the longest form that "
            + "fits next to the bar buttons, measured in the font of the title, see PlanHeaderText.displayedTitle, PL16b; the full form "
            + "\"Samstag, 21. Nov.\" is the same element as the shorter ones that were listed here before); \"Auswählen\" is a system bar button. "
            + "Header design: #188 / #175."),
        Entry(auditType: .dynamicType, labels: [
            "Punkte in den Einstellungen anlegen", "(Morgen|[A-Z][a-z]\\.) planen", "Abschließen", "Brain Dump", "Leitfragen einfügen", "\\d+\\.\\d+\\.", "Wochenplanung starten",
            "Tagebuch schreiben", "Bible Study starten", "Zuletzt: .*", "Unerledigtes verschieben · .*",
        ], screens: ["Tagesabschluss", "Tagesabschluss (Abend)"], reason: "Texts of the evening sheet (hint line, buttons, date of the next planning day, the rows of "
            + "\"Zeit mit Gott\", the leftover row with `.subheadline` that wraps) report a partial lack of Dynamic Type support; no fixed frame, line limit or fixed font in the code, 15 view "
            + "variants gave the same findings, no clipping in the large text run. Stays on the device test list (largest text size)."),
        Entry(auditType: .dynamicType, labels: ["Bible Study", "Zuletzt: .*", "Sitzung läuft · .*"], screens: ["Aufgaben"], reason:
            "Title and second line of the row \"Bible Study\" in \"Aufgaben\" (where the last session ended): `.subheadline` in the same entry label as the "
            + "row of the notes, so it grows with the text size and is not clipped in the large text run; the audit reports a partial lack of "
            + "support for single-line `.subheadline` texts from run to run, as for the evening sheet above. Stays on the device test list (large text)."),
        Entry(auditType: .dynamicType, labels: [
            "P1", "Ältere Termine durchsuchen · vor .*", "Durchsucht: 6 Monate zurück, 12 Monate voraus\\.",
        ], screens: ["Suche", "Aufgaben"], reason: "Priority capsule and the hint rows of the search sheet use text styles; the audit still reports a partial lack of "
            + "support. Not reproduced by eye in the large text run (no clipping there); stays on the device test list."),

        Entry(auditType: .dynamicType, labels: ["DE", "EN"], screens: ["Einkaufsliste", "Einkaufsliste › Karte „übersetzen“"], reason:
            "Language mark of the shopping list (\"DE\"/\"EN\" in the input field): a capsule with a text style (caption2), like the priority "
            + "capsule above; the audit reports a partial lack of support. The mark keeps its 44 pt hit area and has a full VoiceOver label "
            + "(\"Sprache der Einkaufsliste …\"); not reported in the large text run. Stays on the device test list (large text)."),

        Entry(auditType: .dynamicType, labels: [
            "Britisches Englisch", "Markennamen lassen", "Ohne Gewürze", "Mengen runden", "Fehlt etwas\\?",
        ], screens: ["Einkaufsliste › Übersetzung"] + recipeScreens, reason:
            "Quick replies of the follow-up of the translation preview and of the recipe sheets (plan ki-vorschlaege-anpassen, tasks D2 and D5): bordered buttons with a text "
            + "style in a horizontal scroll row, shared with the quick replies of \"Tag planen\" (`FollowUpBar`). The audit reports a partial "
            + "lack of support in some runs (it does so for different texts of the screen from run to run); the buttons grow with the text size "
            + "and are not clipped in the large text run. Stays on the device test list (large text)."),

        // MARK: Text clipped
        Entry(auditType: .textClipped, labels: ["Britisches Englisch", "Markennamen lassen"], screens: ["Einkaufsliste › Übersetzung", "AX5/dark Einkaufsliste › Übersetzung"], reason:
            "Quick replies of the follow-up of the translation preview (plan ki-vorschlaege-anpassen, task D5): bordered buttons in a horizontal "
            + "scroll row (`FollowUpBar`, shared with the quick replies of \"Tag planen\"). The row scrolls sideways, so a chip wider than the "
            + "screen is reached by swiping and its text is complete; the audit reports the chip at the edge of the visible area. Large text is "
            + "checked on the device (large text test list)."),
        Entry(auditType: .textClipped, labels: [
            "Mit ChatGPT planen: in Einstellungen › KI anmelden", "1 Aufgabe ohne Aufwand mit Standarddauer gerechnet",
            "zuletzt: „(Römer|Demo Linsensuppe)“ · heute \\d+:\\d+", "Wochenrückblick", "Punkte in den Einstellungen anlegen",
            "Ältere Termine durchsuchen · vor .*",
        ], screens: withLargeText(["Aufgaben", "Suche", "Erfassen", "Tagesabschluss"]) + eveningSheetScreens + gridScreens, reason: "Reported in the default size for texts that are shown completely on the screenshot of the run (cards of \"Planen\", "
            + "entry rows of \"Aufgaben\", \"Erfassen\"). Not reproducible by eye; stays on the device test list (large text)."),
        Entry(auditType: .textClipped, labels: ["\\d+\\.[–-][^ ]+ [A-Za-zä]+\\.?", "\\d+\\. [A-Za-zä]+\\.? [–-] .*"], screens: ["Wochenrückblick"], reason:
            "Week title of the weekly review (\"23.–29. Nov.\"): the title of `PageTitleLabel`, one line in `title3.bold()` that shrinks to 80 % "
            + "(the component of the day and week headers, #188 / #175). Measured on 2026-11-25 at the frame (36, 183, 115 × 24 pt): the title is "
            + "complete on the screenshot of the run; the audit reports its generic warning \"may be clipped at larger Dynamic Type sizes\". The AX5 "
            + "run of the same screen (\"AX5/dark Wochenrückblick\") reports nothing for it. Stays on the device test list (large text)."),
        Entry(auditType: .textClipped, labels: ["Unerledigtes verschieben · \\d+ Aufgaben?"], screens: eveningPlanScreens + eveningSheetScreens, reason:
            "Row \"Unerledigtes verschieben\" (`LeftoverLine`): the text wraps (`fixedSize(horizontal: false, vertical: true)`) and the row is at least "
            + "44 pt high. Checked on the frames of the findings: 266 × 18 pt (one line) in the capacity card at the default size, 206 × 38 pt "
            + "(two lines, nothing cut) in the wrap-up. The audit reports its generic warning \"may be clipped at larger Dynamic Type sizes\" "
            + "for the row; the AX5 run of the capacity card (screen \"AX5/dark Planen (Abend)\") reports nothing for it."),
        Entry(auditType: .textClipped, labels: ["(?s)Erledigt: Erinnerungen.*"], screens: ["AX5/dark Tagesabschluss (Abend)"], reason:
            "Footer of the wrap-up in the AX5 run of the evening sheet. Checked on the frame of the finding: 370 × 217 pt, completely inside the "
            + "screen (874 pt high), so the text wraps and nothing is cut; the audit reports its generic warning \"may be clipped at larger "
            + "Dynamic Type sizes\". Stays on the device test list (large text)."),
        Entry(auditType: .textClipped, labels: ["[\\d.]+ / [\\d.]+", "[\\d,]+ l / [\\d,]+ l"], reason:
            "Steps and water values of \"Erfassen\" in the largest text size: single-line summary cells of the same tile row (the water "
            + "value was first reported on 25.11.2026 at frame 152.7 × 44 pt, right above the tab bar). Layout for AX sizes is a "
            + "design decision (#188, \"Layout bei Bedienungshilfen-Schriftgrößen\"). The date caption above the day title wraps at "
            + "accessibility sizes (`PageTitleLabel`), so it needs no entry; its weekday changes every day."),
        Entry(auditType: .textClipped, labels: [""], elementType: .textField, reason:
            "Text fields (shopping input, search field) report their placeholder as clipped; the field itself is a single line with a fixed "
            + "pill height. Layout for AX sizes: #188."),

        // MARK: Recipe screens and settings (G1, G2)
        Entry(auditType: .contrast, labels: [
            "Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert\\. .*",
            "Portionen", "Schon auf der Liste · \\d+",
            "(?s)Notizen liegen nur auf diesem iPhone\\..*", "(?s)Sendet auf dein Tippen die Namen .*",
            "(?s)„Rezept hinzufügen“ sendet .*", "Vorrat & Konserven", "\\d+ h \\d+ min", "Zubereitung",
            "Nährwerte", "Apple Health",
            "(?s)(Zum Schätzen sendet|Ein Teil der Aktivitätsenergie|Ballaststoffe und Zucker sind immer dabei).*",
            "Die drei Schnellknöpfe im Tab .*", "\\d+ von \\d+ Artikeln · .*", "(?s)Portionen: \\d+\\nZutaten.*", "wird mit ChatGPT gelesen",
            "Rezepte", "Schätzung", "Anzeige", "In Planen anzeigen", "(?s)(Gesendet wird|Nicht gesendet werden|Um ein Rezept zu lesen).*",
            "(?s)„In Planen anzeigen“ zeigt .*", "Einkaufsliste jetzt auf (Englisch|Deutsch)",
        ], screens: recipeScreens + recipeScreensLargeText, reason: "Footers, values and previews in the secondary text tone on the "
            + "grouped background of a form or list; the last footer or row of a settings page also lies behind the tab bar (\"Sendet auf dein Tippen …\", "
            + "\"„Rezept hinzufügen“ sendet …\", \"Notizen liegen nur auf diesem iPhone …\", \"Ein Teil der Aktivitätsenergie …\", \"Apple Health\"), "
            + "and the rows of the translation preview sheet are reported like the other texts of that sheet (\"\\d+ von \\d+ Artikeln\"). "
            + "Strand K cut the findings of this group from 168 to 102 (three repetitions each). Decision D1 (2026-11-25) then moved the plain "
            + "`Text` of the section headers and footers of these pages from the system grey to `secondaryText`; the patterns that a collect run "
            + "on the code before the change reported and two runs after it did not report were struck (most headers of the recipe input and result "
            + "pages, the language, voice and capture settings, and the footers in the middle of the pages: 34 findings before, 6 per run after). The value "
            + "of `secondaryText` stays (D2)."
            + " Patterns that no finding matched in either measurement stay: the evening runs of the measurement are incomplete (one of three failed "
            + "each time) and earlier runs reported them; only patterns that were reported in every repetition before and in none after were struck."),
        Entry(auditType: .contrast, labels: ["Milk", "Milch"], screens: ["Einkaufsliste › Übersetzung", "AX5/dark Einkaufsliste › Übersetzung"], reason:
            "Names in the rows of the translation preview: primary text and `secondaryText` of the second line inside a row button on the grouped "
            + "background of a half-height sheet; the audit reports \"failed\" or \"nearly passed\" depending on the text size (12 findings before "
            + "and after strand K, in every repetition). The ingredient rows of the recipe result, which looked the same, pass since strand K; "
            + "these rows sit in a button, whose tint the audit may measure instead of the row background. Open (#188)."),
        Entry(auditType: .contrast, labels: [
            "Tag und Fokus",
            "250 ml, im Hintergrund", "Notizen und Gewohnheiten", "Einkaufsliste", "Termine, Blöcke, Deadlines; nur entsperrt",
            "Freier Fokus-Timer, im Hintergrund", "Brain Dump mit laufendem Diktat", "Hakt eine Gewohnheit für heute ab",
            "auch: „Fokus beenden in Tagwerk“", "(?s)Erkennt Siri einen Satz nicht.*",
        ], screens: siriScreens, reason: "Section headers, footers and the effect line of each phrase on the page \"Siri & Kurzbefehle\", in `secondaryText` "
            + "on the grouped background. Same group as the grey texts above; 36 findings before, 13 after strand K (three repetitions "
            + "each). Decision D1 (2026-11-25) moved the plain headers and footers of the page to `secondaryText`; \"Alle Sätze stehen dort bereit …\", "
            + "\"Erfassen\" and \"Einkauf\" were reported on the code before and in none of two runs after the change and are struck. What remains is "
            + "the last header \"Tag und Fokus\" at the lower edge of the page, behind the tab bar."
            + " Patterns that no finding matched in either measurement stay: the evening runs of the measurement are incomplete (one of three failed "
            + "each time) and earlier runs reported them; only patterns that were reported in every repetition before and in none after were struck."),
        Entry(auditType: .textClipped, labels: ["Repository suchen", "Projekt suchen", "Einstellungen durchsuchen"], screens: withLargeText(["Neue Aufgabe › Repository wählen", "Neue Aufgabe › Projekte", "Einstellungen › Suche"]), reason: "The system search field (`UISearchBarTextField`) of the picker sheets and of the settings search in the largest text size: the audit "
            + "reports its prompt as possibly clipped at larger Dynamic Type sizes (run of 2026-11-25). The field is drawn by the system "
            + "(`.searchable`) and wraps nothing itself; the folder list of the notes reports the same finding for its search field (see "
            + "`acceptsFindingWithoutElement`), here with the element."),
        Entry(auditType: .dynamicType, labels: [
            "Abbrechen", "Fertig", "Zuletzt verwendet", "Alle Repositories \\(.*\\)", "Verknüpft mit .*", "Weitere Projekte \\(.*\\)", "Alle Projekte \\(.*\\)",
        ], screens: ["Neue Aufgabe › Repository wählen", "Neue Aufgabe › Projekte"], reason:
            "The navigation bar buttons \"Abbrechen\" and \"Fertig\" and the section headers of the picker sheets of a GitHub issue: the audit reports a partial lack "
            + "of Dynamic Type support at the default size, for one of them per run (runs of 2026-11-25: \"Abbrechen\", \"Weitere Projekte (2)\", \"Fertig\"); "
            + "in the AX5 run of the same sheets every text grows and passes. The button is the same `Button(\"Abbrechen\")` in a "
            + "`ToolbarItem(placement: .cancellationAction)` as on the other sheets (see the entry for the recipe screens above), the headers are "
            + "plain `Text` with a text style in a `Section` header."),
        Entry(auditType: .textClipped, labels: ["Tagwerk-Kurzbefehle"], screens: siriScreens, reason: "The `ShortcutsLink` is a system control; its "
            + "label \"Tagwerk-Kurzbefehle\" is drawn by the system, and the audit reports it as possibly clipped (default size and AX5). The control "
            + "is not part of the app's own layout and cannot be given a line limit or another style (#188 SI2b)."),
        Entry(auditType: .contrast, labels: [
            "Verwerfen", "Rezept holen", "Zutaten holen", "Zutaten auf die Einkaufsliste", "Nur als Rezept speichern", "Zurücksetzen", "Probe hören", "Übernehmen", "Demo Linsensuppe",
        ], screens: recipeScreens + recipeScreensLargeText, reason: "What the accent colour did not fix: \"Rezept holen\", \"Zutaten holen\", \"Zutaten auf die Einkaufsliste\" and \"Nur als Rezept speichern\" are dimmed by the system "
            + "while the text field is empty (gewollt schwach), \"Verwerfen\" and \"Übernehmen\" sit in the navigation bar, whose Liquid Glass "
            + "background lets the list scroll behind it, and \"Zurücksetzen\" and \"Probe hören\" are list buttons in the accent colour on a "
            + "grouped row. The system draws the background; no own colour to change without replacing the system style (#188). All other "
            + "accent texts of these screens pass since strand K (72 findings before, 36 after, three repetitions each)."),

        Entry(auditType: .dynamicType, labels: [
            "Abbrechen", "Verwerfen", "Die Kategorien kommen aus deiner Einkaufsliste\\.", "Beides legt auf Wunsch eine Notiz im Ordner „Rezepte“ an\\.", "Das Rezept wird als Notiz im Ordner „Rezepte“ gespeichert\\. .*",
            "\\d\\. .*", "Vorlesen", "Eiweiß-Ziel", "(?s)Sendet auf dein Tippen die Namen .*", "Rezepte mit ChatGPT lesen und übersetzen", "ChatGPT",
            "(?s)Notizen liegen nur auf diesem iPhone\\..*", "Stimme", "Sprachchat-Antwort", "Einkaufsliste",
            "Stimme (Deutsch|English)", "Tempo", "Mikrofon, Sprachpakete, Stimmen, Tempo und Sprechmodus\\.", "Übernehmen",
            "Rezept holen", "Zutaten auf die Einkaufsliste", "Nur als Rezept speichern",
        ], screens: recipeScreens, reason: "Navigation bar buttons, form rows, footers, steps and the buttons that end the recipe input (EK3b) use text "
            + "styles; the audit still reports a partial lack of support, for the last button of the input on each of the two input screens "
            + "(a text style with `fontWeight(.semibold)`, as before EK3b; the allowlist names the buttons because the audit picks one of them). "
            + "In the AX5 run of the same screens (`AccessibilityAuditRecipesLargeTextUITests`) every one of these texts grows and wraps."),
        Entry(auditType: .textClipped, labels: [
            "Rezept mit ChatGPT anlegen", "Neues Rezept", "Demo Linsensuppe", "Andere Notiz wählen …", "Füge die Zutatenliste oder das ganze Rezept ein\\. .*",
            "(?s)(Um ein Rezept zu lesen|Gesendet wird|Nicht gesendet werden|Nur auf dein Tippen|Wenn du zu einem Vorschlag etwas zurückschreibst|Eine Notiz mit den Abschnitten|Die gewählte Liste erscheint|Portionen: \\d+\\nZutaten).*",
            "Du kannst das in den Einstellungen unter „Einkaufsliste“ widerrufen\\.", "Mikrofon in Gesprächen",
            "Beides legt auf Wunsch eine Notiz im Ordner „Rezepte“ an\\.",
            "Rezepte mit ChatGPT lesen und übersetzen", "Mit ChatGPT sortieren und übersetzen", "(?s)Sendet auf dein Tippen die Namen .*",
            "Einkaufsliste jetzt auf (Englisch|Deutsch)", "Neue Artikel kommen auf (Englisch|Deutsch)\\. .*", "Mit ChatGPT übersetzen", "Übersetzung",
            "\\d+ von \\d+ Artikeln · .*", "(?s)Mengen bleiben, wie sie sind\\..*", "Verwerfen", "Übernehmen",
        ], screens: recipeScreens + recipeScreensLargeText, reason: "The audit warns that these texts \"may be clipped at larger Dynamic Type sizes\". "
            + "Checked on the AX5 screenshots of these screens: headings, buttons, notes and footers wrap completely, some run past the lower edge "
            + "of the scroll view (the audit counts that as clipped). The navigation title of the recipe input was \"Rezept mit ChatGPT anlegen\" and "
            + "was truncated by the system bar; it is \"Rezept anlegen\" now (owner decision D6) and the finding is gone (2 of 2 repetitions "
            + "before, 0 of 2 after, screen \"Rezept anlegen (Eingabe)\"). The pattern stays for the button of the same name in the list of "
            + "\"Rezepte\" (default size and AX5/dark)."),

        // MARK: Data backup pages (DS1, DS3, DS4)
        Entry(auditType: .contrast, labels: [
            "(?s)Gilt für „Jetzt sichern“.*", "Was wird gesichert\\?", "Anmeldung bei ChatGPT und GitHub", "Zugriff auf Kalender, Erinnerungen und Health",
        ], screens: backupScreens, reason:
            "What is left of the backup pages after decision D1 (2026-11-25): the section headers and footers are in `secondaryText` now (they were "
            + "in the system grey, which the user had accepted; strand K had already darkened the same grey everywhere else). Measured with "
            + "`--collect-all` on `BackupUITests`, two runs each: 30 findings in 15 patterns on the code before the change, 8 findings in the 4 "
            + "patterns listed here after it. They are rows and the last footer at the lower edge of the pages, which lie under the Liquid Glass of the "
            + "tab bar, whose background the system draws and lets the list scroll behind it (same group as \"Schrift auf Liquid Glass\" above)."),
        Entry(auditType: .dynamicType, labels: [
            "An dieses Gerät gebunden", "(?s)Gilt für „Jetzt sichern“.*", "Noch keine Sicherheitskopien\\.", "(?s)Kein Sicherungsordner gewählt\\. .*",
        ], screens: backupScreens, reason:
            "Headers, footers and the empty-state row of the backup pages use text styles (`footnote`, body) that scale; the audit still reports "
            + "a partial lack of support, as it does for the footers of the recipe screens above. Not measured at AX5 for these pages: "
            + "device test list (Dynamic Type at the largest size on all four pages)."),
        Entry(auditType: .textClipped, labels: [
            "(?s)Gilt für „Jetzt sichern“.*", "(?s)Vor jedem Wiederherstellen legt Tagwerk .*", "(?s)Kein Sicherungsordner gewählt\\. .*",
        ], screens: backupScreens, reason:
            "The audit warns that these texts \"may be clipped at larger Dynamic Type sizes\": a long footer of the password page and the header and "
            + "footer of the list of safety copies, plain `Text` in a `Section` without a line limit, so they wrap. Not measured at AX5 for these "
            + "pages: device test list (Dynamic Type at the largest size on all four pages)."),

        // MARK: Barcode scan sheet (#319)
        Entry(auditType: .contrast, labels: ["Suchen", "Erneut scannen", "Selbst anlegen"],
              screens: ["AX5/dark Strichcode (Nummer eingeben)", "AX5/dark Strichcode (nicht gefunden)"], reason:
            "Button rows of the scan sheet in the accent tone on the grouped background, at AX5 in dark mode (\"Suchen\" of the digit entry, \"Erneut scannen\" and "
            + "\"Selbst anlegen\" of the result): reported as \"nearly passed\" in 2 of 2 repetitions of a collect run on 2026-11-25, in no run at the default size. "
            + "Same cause as the accent buttons of the other forms: the dark `AccentColor` stays as it is (decision D5, 2026-11-25). Headers and "
            + "footers of the sheet are in `secondaryText` (D1) and were reported before that change, not after."),
        Entry(auditType: .dynamicType, labels: ["Abbrechen", "Beim Anlegen wird der Strichcode mit dem Lebensmittel gespeichert\\."],
              screens: ["Strichcode (Nummer eingeben)", "Strichcode (nicht gefunden)"], reason:
            "The cancel button of the navigation bar (system control) and the footer of the result form, plain `Text` styles; the audit reports a "
            + "partial lack of Dynamic Type support at the default size in 2 of 2 repetitions of a collect run on 2026-11-25, the same finding as for "
            + "\"Abbrechen\" and the footers of the recipe screens above. At AX5 the sheet is audited for clipping and contrast, and both texts grow and wrap."),

        // MARK: Hit area
        Entry(auditType: .hitRegion, labels: ["Eingabe löschen"], screens: ["Suche"], reason:
            "The clear button of the search field (`SearchSheet`) has a 44 × 44 pt frame around its 17 pt glyph, but the audit still "
            + "reports its hit region on \"Suche\" (3 of 3 repetitions of the collect run on 2026-11-25, after the frame was added). Why the "
            + "audit measures less than the frame is not known; the button sits inside the 44 pt high field. Design question, "
            + "together with the check circle of the lists (#188)."),
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
        logDefinitionsOnce()
        let passes = auditTypes.contains(.contrast) && auditTypes != .contrast ? [.contrast, auditTypes.subtracting(.contrast)] : [auditTypes]
        for pass in passes {
            // Before each pass: a screen that is still changing (late loading, layout, an animation) gives findings that
            // depend on the speed of the run. The Dynamic Type pass switches the system text size, so the wait also runs
            // between the passes and after the last one, so that the switch back does not run into the next test step.
            try waitForStableScreen(app, screen: screen, file: file, line: line)
            let rejected = try rejectedFindings(app, screen: screen, pass: pass)
            guard !rejected.isEmpty else { continue }
            // Another pass confirms or drops each finding (`AuditConfirmation`; Dynamic Type needs three passes in all, the other
            // types two). A further pass only runs when the earlier ones reported something, so a clean screen costs nothing.
            let outcomes = try AuditConfirmation.judge(rejected) {
                try waitForStableScreen(app, screen: screen, file: file, line: line)
                return Set(try rejectedFindings(app, screen: screen, pass: pass).map(\.key))
            }
            for (finding, outcome) in outcomes {
                switch outcome {
                case .confirmed:
                    XCTFail(finding.message, file: file, line: line)
                case .unconfirmed(let passes):
                    print("Unconfirmed audit finding (reported by \(passes) of \(AuditConfirmation.requiredPasses(for: finding)) required passes): \(finding.message)")
                }
            }
        }
        try waitForStableScreen(app, screen: screen, file: file, line: line)
        recordStats(screen: screen)
    }

    /// Runs one audit pass and returns the findings that are not on the allowlist, each with the message that fails the test and a
    /// key that identifies it again in another pass (type, text of the finding and label of the element, not its frame, which moves
    /// with the scroll position).
    private static func rejectedFindings(_ app: XCUIApplication, screen: String, pass: XCUIAccessibilityAuditType) throws
        -> [AuditFinding] {
        var findings: [(issue: XCUIAccessibilityAuditIssue, element: XCUIElement?)] = []
        systemBars = pass.contains(.contrast) ? readSystemBars(of: app) : SystemBars()
        let auditStarted = Date()
        try runAudit(app, for: pass) { issue in
            findings.append((issue, issue.element))
        }
        stats.auditSeconds += Date().timeIntervalSince(auditStarted)
        stats.findings += findings.count
        return findings.filter { !isAccepted($0.issue, element: $0.element) }.map { finding in
            let element = finding.element
            let message = "\(screen): \(finding.issue.compactDescription) | \(finding.issue.detailedDescription) | "
                + "label=\(element?.label ?? "-") id=\(element?.identifier ?? "-") frame=\(element?.frame ?? .zero)"
            return AuditFinding(key: "\(finding.issue.auditType.rawValue)|\(finding.issue.compactDescription)|\(element?.label ?? "-")",
                                message: message, isDynamicType: finding.issue.auditType == .dynamicType)
        }
    }


    /// Fails with the elements that kept changing when the screen does not settle. In collect mode the instability is
    /// written to the collect file as a finding of its own and the run goes on, so the flaky screens can be listed.
    private static func waitForStableScreen(_ app: XCUIApplication, screen: String, file: StaticString, line: UInt) throws {
        guard let changing = try UITestCase.unstableElements(of: app) else { return }
        if collectsFindings {
            recordLine("\(screen) | unstable screen | \(changing)\n")
        } else {
            XCTFail("\(screen): the screen did not settle before the audit; elements that changed last: \(changing)", file: file, line: line)
        }
    }

    /// Error of `performAccessibilityAudit` when the audit did not finish in its (not configurable) time limit: domain
    /// "com.apple.xcode.xctest.accessibilityAudit", code -56, "Audit failed to complete in time".
    private static func isAuditTimeout(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == "com.apple.xcode.xctest.accessibilityAudit" && nsError.code == -56
    }

    /// Runs one audit pass and hands every issue to `collect`. The audit has no timeout setting, and it runs out of time when the
    /// machine is loaded (several checkouts testing at once). Such a run reports nothing about the screen, so it is repeated
    /// from scratch, up to three attempts; the issues of an aborted attempt are dropped, so no finding is lost or counted twice.
    /// Every other error, and a timeout in the last attempt, still fails the test.
    private static func runAudit(_ app: XCUIApplication, for auditTypes: XCUIAccessibilityAuditType,
                                 attempts: Int = 3, collect: (XCUIAccessibilityAuditIssue) -> Void) throws {
        for attempt in 1...attempts {
            var issues: [XCUIAccessibilityAuditIssue] = []
            do {
                try app.performAccessibilityAudit(for: auditTypes) { issue in
                    issues.append(issue)
                    return true
                }
            } catch where isAuditTimeout(error) && attempt < attempts {
                print("Accessibility audit timed out (attempt \(attempt) of \(attempts)), running it again")
                continue
            }
            issues.forEach(collect)
            return
        }
    }

    private static func isAccepted(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement?) -> Bool {
        let coverage = coverage(of: issue, element: element)
        let accepted = coverage != .none
        // Collect mode lists the findings that the allowlist does not cover yet; nothing fails. With `AUDIT_COLLECT_ALL=1`
        // every finding is listed, the accepted ones with the entry and the pattern that covers them.
        if collectsFindings {
            if !accepted || collectsAll { record(issue, element: element, coverage: coverage) }
            return true
        }
        return accepted
    }

    /// What covers a finding: an entry of the list (index and the first pattern that matched), one of the fixed rules for findings
    /// without an element, or nothing.
    enum Coverage: Equatable {
        case entry(index: Int, pattern: String)
        case elementlessRule
        /// A contrast finding of an element that lies mostly under a system bar (`SystemBarOverlap`); the name of the bar.
        case underSystemBar(String)
        case none
    }

    private static func coverage(of issue: XCUIAccessibilityAuditIssue, element: XCUIElement?) -> Coverage {
        let started = Date()
        defer { stats.matchSeconds += Date().timeIntervalSince(started) }
        guard let element else { return acceptsFindingWithoutElement(issue) ? .elementlessRule : .none }
        // The entries come first, so that the dead-entry report of the collect mode (`noteHit`) stays truthful.
        guard let match = matchingEntry(issue, element: element) else {
            return underSystemBar(issue, element: element).map(Coverage.underSystemBar) ?? .none
        }
        return .entry(index: match.index, pattern: match.pattern)
    }

    // MARK: System bars

    /// The system bars of the open screen, read once before a contrast pass (not in the audit handler, where queries are slow).
    private struct SystemBars {
        var bars: [SystemBarOverlap.Bar] = []
        var screen: CGRect = .zero
        /// The controls and labels of the bars themselves (back button, title, tab items), as `label|frame`. They are never ignored:
        /// their contrast is the contrast of the app against the glass, which is what the audit should measure.
        var ownElements: Set<String> = []
    }
    private static var systemBars = SystemBars()

    private static func elementKey(label: String, frame: CGRect) -> String {
        "\(label)|\(Int(frame.minX.rounded())),\(Int(frame.minY.rounded())),\(Int(frame.width.rounded())),\(Int(frame.height.rounded()))"
    }

    private static func collectOwnElements(of snapshot: XCUIElementSnapshot, into keys: inout Set<String>) {
        keys.insert(elementKey(label: snapshot.label, frame: snapshot.frame))
        for child in snapshot.children { collectOwnElements(of: child, into: &keys) }
    }

    /// Reads the frames of the navigation bars and tab bars of the app (one snapshot each) and the elements inside them.
    private static func readSystemBars(of app: XCUIApplication) -> SystemBars {
        var result = SystemBars()
        result.screen = app.frame
        let queries: [(name: String, query: XCUIElementQuery)] = [("navigation bar", app.navigationBars), ("tab bar", app.tabBars)]
        for (name, query) in queries {
            for bar in query.allElementsBoundByIndex {
                guard let snapshot = try? bar.snapshot(), !snapshot.frame.isEmpty, snapshot.frame.intersects(result.screen) else { continue }
                // A bar that a sheet covers (the tab bar behind a sheet, the navigation bar of the page behind it) is in the tree but not
                // hittable; content of the sheet is not under its glass.
                guard bar.isHittable else {
                    print("System bar of \(currentScreen) skipped, not hittable: \(name) \(snapshot.frame)")
                    continue
                }
                result.bars.append(SystemBarOverlap.Bar(name: name, frame: snapshot.frame))
                collectOwnElements(of: snapshot, into: &result.ownElements)
            }
        }
        // The topmost navigation bar starts below the status bar in the accessibility tree (y 62 pt), but its glass reaches the top of
        // the screen. A sheet adds a second navigation bar lower down; that one keeps its frame.
        if let topmost = result.bars.indices.filter({ result.bars[$0].name == "navigation bar" }).min(by: { result.bars[$0].frame.minY < result.bars[$1].frame.minY }) {
            result.bars[topmost] = result.bars[topmost].extendedToTop(of: result.screen)
        }
        print("System bars of \(currentScreen): "
            + (result.bars.isEmpty ? "none" : result.bars.map { "\($0.name) \($0.frame)" }.joined(separator: ", ")) + "; screen \(result.screen)")
        return result
    }

    /// The name of the system bar that a contrast finding is ignored for, or `nil` when the finding stays.
    ///
    /// Reason: when a scroll view moves content under a Liquid Glass bar, the contrast check measures that content against the glass and
    /// not against its own background. In the largest text size the hour grid of "Planen" ends at a different scroll offset from run to
    /// run (`DayGridScreen.scrollToNowOnOpening` aligns to "now" within a window of three seconds; the cause of the varying offset is
    /// probable, not measured), so a different element lands behind a bar each time. Seen in CI on "AX5/dark Planen": the all-day pill
    /// "Projektwoche" (frame y 32 to 101 pt, navigation bar; it has a solid fill since D4), the headline "4 Termine · 10:00–13:00" of the
    /// collapsed group block (y 811 to 913 pt on a 874 pt screen, tab bar; the rendered block measures 16.5:1 in light and 15.9:1 in dark
    /// mode, `MarkerRenderContrastTests.collapsedBlock_renderedContrast`) and the hour label "09:30" (y 809 to 839 pt, tab bar; CI run
    /// 45749510918). A label entry per element never ends, so the rule is geometric: the finding is ignored when at least half of the
    /// visible height of the element lies in the vertical band of a bar (`SystemBarOverlap`). Every ignored finding is printed with its
    /// frame and the frame of the bar, so it stays visible in the test log.
    ///
    /// Scope: contrast only, and every screen. Content scrolls under a bar on any page, and the effect has nothing to do with the grid; a
    /// rule for the grid screens only would bring the same whack-a-mole to the next list. The rule never covers clipping or any other
    /// type: text that is cut off or too small is a real defect wherever it lies. The elements of the bars themselves are excluded (see
    /// `SystemBars.ownElements`), bars that a sheet covers do not count (not hittable), and an element that is only partly under a bar keeps failing.
    private static func underSystemBar(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement) -> String? {
        guard issue.auditType == .contrast, !systemBars.bars.isEmpty else { return nil }
        guard let snapshot = try? element.snapshot() else { return nil }
        stats.elementQueries += 1
        guard !systemBars.ownElements.contains(elementKey(label: snapshot.label, frame: snapshot.frame)),
              let bar = SystemBarOverlap.bar(covering: snapshot.frame, in: systemBars.bars, within: systemBars.screen) else { return nil }
        print("Ignored contrast finding under the \(bar.name): \(currentScreen) | label=\(snapshot.label.replacingOccurrences(of: "\n", with: "⏎")) "
            + "frame=\(snapshot.frame) \(bar.name)=\(bar.frame) | \(issue.compactDescription)")
        return bar.name
    }

    /// Findings without an element cannot be matched by label; only the ones named here are accepted, per screen.
    private static func acceptsFindingWithoutElement(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
        // Reason: the audit reports one clipped text without an element (frame 0×0) in the note list; nothing on the
        // screen is cut off visually. Stays on the device test list (large text). The recipe folder is a note list with the same
        // system search bar and reports the same single finding for the "UISearchBarTextField".
        // The input of "Rezept mit ChatGPT anlegen" (text field, photos, link) reports two "Potentially inaccessible text" findings
        // (element detection) without an element in this environment, also without the share choice; it reproduces on the code before
        // that change; the element cannot be resolved. Stays on the device test list (VoiceOver).
        if issue.auditType == .elementDetection { return currentScreen == "Rezept anlegen (Eingabe)" }
        // The list markers of the rendered recipe note (see the entry "•" above) arrive without an element in the combined run; only
        // elements of the web view are accepted, and only on the screen of the recipe note.
        if issue.auditType == .hitRegion {
            return ["Rezept-Notiz", "AX5/dark Rezept-Notiz"].contains(currentScreen) && issue.detailedDescription.contains("WebAccessibilityObjectWrapper")
        }
        // The rendered recipe note (web view) can report one "Element has no description" without an element (no label, no identifier,
        // frame 0×0) in the combined run (see `audit`: the elements of findings can no longer be resolved after the Dynamic Type
        // check). Alone, the same screen passes (also on the lock branch, which showed this finding once in CI). The finding has no element
        // and no frame, so nothing on the screen can be fixed or matched; only the screen of the recipe note accepts it.
        if issue.auditType == .sufficientElementDescription {
            return ["Rezept-Notiz", "AX5/dark Rezept-Notiz"].contains(currentScreen)
        }
        // The card of "Artikel übersetzen" also reports one "nearly passed" contrast finding without an element (the grey second line or the
        // button on the material of the card; the same texts are reported with their frames and covered by the entries below).
        if issue.auditType == .contrast { return currentScreen == "Einkaufsliste › Karte „übersetzen“" }
        guard issue.auditType == .textClipped else { return false }
        // The card of "Artikel übersetzen" reports two clipped texts without an element (frame 0×0) in the default size; its texts are
        // reported with their own frames and covered by the entries below (the card is a plain stack of texts and buttons, nothing is cut).
        // "Planen (Tag)" at the default size: once the screen has settled, the hour grid has scrolled to "now" (realign on "Heute") and the
        // suggestion card above it ("Derselbe Termin?") lies partly behind the bar. The audit reports the cut card text as "may be clipped"
        // without an element (frame 0×0); the screenshot of the run shows the text only scrolled under the bar, not cut in its own frame.
        // "Einstellungen › KI › Sprache" in the largest text size: the one clipped text of this page is the toggle label "Mikrofon in Gesprächen"
        // (entry above: the label wraps completely, the audit counts the height of the row as clipped). When the page is opened directly
        // with `-TagwerkUITestScreen` the audit reports it without its element; reached through the settings list it came with the element
        // (frame 36, 276, 236 × 187 in both cases, the same single finding on the page).
        return currentScreen == "Notizenliste" || currentScreen == "Einkaufsliste › Karte „übersetzen“" || currentScreen == "Planen (Tag)"
            || currentScreen == "AX5/dark Einstellungen › KI › Sprache"
            || (currentScreen == "Rezepte" && issue.detailedDescription.contains("UISearchBarTextField"))
    }

    /// The first entry of the list that covers a finding with an element, with the pattern that matched.
    private static func matchingEntry(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement) -> (index: Int, pattern: String)? {
        func matches(_ text: String, _ pattern: String) -> Bool { text.range(of: "^(\(pattern))$", options: .regularExpression) != nil }
        // Every read of an element property is a query of its own and slow, so the properties come from one snapshot of the element
        // (one query). When the element cannot be snapshotted, the three reads run as before and fail the same way.
        let label: String, identifier: String, elementType: XCUIElement.ElementType
        if let snapshot = try? element.snapshot() {
            (label, identifier, elementType) = (snapshot.label, snapshot.identifier, snapshot.elementType)
            stats.elementQueries += 1
        } else {
            (label, identifier, elementType) = (element.label, element.identifier, element.elementType)
            stats.elementQueries += 3
        }
        let index = entries.firstIndex { entry in
            guard entry.auditType == issue.auditType, entry.screens == nil || entry.screens?.contains(currentScreen) == true,
                  entry.elementType == nil || entry.elementType == elementType else { return false }
            return entry.labels.contains { pattern in
                matches(label, pattern) || (!identifier.isEmpty && matches(identifier, pattern))
            }
        }
        guard let index else { return nil }
        noteHit(of: index)
        let pattern = entries[index].labels.first { matches(label, $0) || (!identifier.isEmpty && matches(identifier, $0)) } ?? ""
        return (index, pattern)
    }

    /// Collect mode only: lets the report of `scripts/stress-audits.sh --collect` list the entries that no finding of a full
    /// run matched (dead entries). Every entry is written once per process as ENTRY-DEFINED, every first match as ENTRY-HIT.
    private static var matchedEntries: Set<Int> = []
    private static var loggedDefinitions = false

    private static func noteHit(of index: Int) {
        guard collectsFindings, matchedEntries.insert(index).inserted else { return }
        recordLine("ENTRY-HIT \(index)\n")
    }

    /// Collect mode with `AUDIT_COLLECT_ALL=1` (`scripts/stress-audits.sh --collect-all`): every finding is written, the accepted ones with
    /// the index and the pattern of the entry that covers them ("accepted=3:Überfällig"; "accepted=rule" for the fixed rules for
    /// findings without an element), the others with "accepted=-". The patterns of all entries are written as PATTERN-DEFINED.
    private static var collectsAll: Bool { collectsFindings && ProcessInfo.processInfo.environment["AUDIT_COLLECT_ALL"] == "1" }

    private static func logDefinitionsOnce() {
        guard collectsFindings, !loggedDefinitions else { return }
        loggedDefinitions = true
        for (index, entry) in entries.enumerated() {
            let screens = entry.screens.map { "\($0.count) screen(s): \($0.prefix(2).joined(separator: ", "))" } ?? "all screens"
            recordLine("ENTRY-DEFINED \(index) | \(entry.auditType.rawValue) | \(screens) | \(entry.labels.prefix(3).joined(separator: ", "))\n")
            if collectsAll { entry.labels.forEach { recordLine("PATTERN-DEFINED \(index) | \($0)\n") } }
        }
    }

    // MARK: Collect mode

    /// With `TEST_RUNNER_AUDIT_COLLECT_FILE=<path>` the audits do not fail; every finding that is not on the allowlist is appended to the file instead
    /// (with `TEST_RUNNER_AUDIT_COLLECT_ALL=1` every finding, see `collectsAll`). Used to list the findings that are neither fixed nor on the allowlist,
    /// and to measure which entries still cover a finding.
    private static var collectFile: String? { ProcessInfo.processInfo.environment["AUDIT_COLLECT_FILE"] }
    static var collectsFindings: Bool { collectFile != nil }

    static var currentScreen = ""

    /// Cost of judging the findings of one `audit` call, written to `<collect file>.stats` in collect mode (one line per audit call):
    /// the time of `performAccessibilityAudit`, the time of matching the findings against the allowlist (`coverage(of:element:)`,
    /// which includes the queries of the element) and the number of queries of the element. Measurement only; it does not change a result.
    private struct Stats {
        var auditSeconds = 0.0
        var matchSeconds = 0.0
        var findings = 0
        var elementQueries = 0
    }
    private static var stats = Stats()

    private static func recordStats(screen: String) {
        defer { stats = Stats() }
        guard let path = collectFile else { return }
        let line = String(format: "%@ | findings=%d auditSeconds=%.2f matchSeconds=%.2f elementQueries=%d\n", screen, stats.findings,
                          stats.auditSeconds, stats.matchSeconds, stats.elementQueries)
        let statsPath = path + ".stats"
        if let handle = FileHandle(forWritingAtPath: statsPath) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: statsPath, atomically: true, encoding: .utf8)
        }
    }

    private static func record(_ issue: XCUIAccessibilityAuditIssue, element: XCUIElement?, coverage: Coverage) {
        var accepted = ""
        if collectsAll {
            switch coverage {
            case .entry(let index, let pattern): accepted = " accepted=\(index):\(pattern)"
            case .elementlessRule: accepted = " accepted=rule"
            case .underSystemBar(let bar): accepted = " accepted=\(bar)"
            case .none: accepted = " accepted=-"
            }
        }
        recordLine("\(currentScreen) | \(issue.auditType.rawValue) | \(issue.compactDescription) | label=\(element?.label.replacingOccurrences(of: "\n", with: "⏎") ?? "-") "
            + "frame=\(element?.frame ?? .zero) id=\(element?.identifier ?? "-") type=\(element?.elementType.rawValue ?? 0)\(accepted)\n")
    }

    private static func recordLine(_ line: String) {
        guard let path = collectFile else { return }
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}
