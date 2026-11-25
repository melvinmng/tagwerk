# Designgruppe 2 „Notizen, Routinen und Persönliches“ (#188), Teil 2: Routinen, Bible Study, Gewohnheiten, Datensicherung, Einkauf, Import – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Stand 20.11.2026. Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Code-Stand der Befunde: `547a88b`.

**Diese Datei setzt Teil 1 fort:** `2026-11-20-g2-notizen-routinen.md` enthält Entscheidungen, **Global Constraints**, **Abgrenzung zu laufenden Arbeiten**, **Review Focus**, die Tabelle der gemeinsam berührten Dateien, **Reihenfolge und Wellen**, **offene Fragen** und **Risiken** für beide Teile. Sie gelten hier unverändert, ebenso die Testbefehle `PKG`, `APP`, `UI`, `ALL`. Pfade relativ zu `app/Tagwerk/`; `TagwerkCore/…` = `app/Packages/TagwerkCore/Sources/TagwerkCore/…`.

## Ausgangslage (Befund, Teil 2)

| Stelle | Ist |
|---|---|
| `Routines/MorningSheet.swift:31–39` | Reihenfolge Brain Dump (`NoteField`), „Dankbar für“, Dream Log; kein Symbol in den Überschriften; kein Hinweis auf den Tagesfokus. |
| `Routines/NoteField.swift:168–270` | Abschnitt mit Feld, „Als Aufgabe anlegen“, „Leitfragen einfügen“; „Vorschläge holen“ als eigene Zeile; Einladung „Willst du etwas ändern? …“ und Datenschutzsatz als Fußtext, auch bei leerem Feld. |
| `Routines/EveningSheet.swift:77–100` | Zwei einzelne Abschnitte „Tagebuch schreiben“ (mit Fußnote) und „Bible Study starten“, ohne Zustand; die Bible-Study-Zeile steht immer und nur im Tagesabschluss. |
| `TagwerkCore/RoutineSchedule.swift:79–97, 156–176` | `suggestedItems`: „Helle Lichter ausmachen“ ohne Zeit; drei erinnernde Punkte (90, 60, 30); `maximumReminders = 4`. |
| `Routines/RoutineSettingsView.swift:33–62, 156, 196–217` | Checkliste mit Abstand je Punkt; Fußtext „Die Zeiten folgen der Schlafzeit. Höchstens vier Punkte erinnern …“. |
| `Routines/WeekReflectionSections.swift:72–88` | Drei Felder, die Frage steht als Platzhalter. |
| `Routines/LeftoverSheet.swift:9–14, 66–92, 171–206` | Blatt mit drei Optionen ohne Vorschau; `Report(moved:late:unplaced:moves:)`; Ergebnis als ein Satz (`LeftoverSheetText.outcome`). |
| `Planning/DayView.swift:261–285` | `CapacityCard` zeigt bereits `LeftoverLine`, sobald `model.leftFromToday` nicht leer ist. RO10a ist damit im Kern gebaut; zu prüfen sind Bedingung und Wortlaut. |
| `Routines/WeekPlanningSheet.swift:26–58, 199–203` | Fünf Schritte, Textzeile „Schritt 2 von 5“, „Zurück“/„Weiter“/„Fertig“; kein „Überspringen“. Einstiege: Wochenrückblick, Sonntags-Tagesabschluss. |
| `Notes/BibleStudyStartSheet.swift`, `NoteStore+BibleStudy.swift:40–70`, `BibleStudySessionRecord.swift` | Auswahlliste mit 66 Büchern, Freitextfeld; `passage` „wie getippt“; `lastBookKey` über alle Bücher; `completeSession` setzt nur `completedAt`; Abschließen im Menü des Editors und in der Ordnerliste. |
| `TagwerkCore/BibleBooks.swift` | Nummer, deutscher und englischer Name, Aliase; keine Kapitel- oder Verszahlen. |
| `TagwerkCore/NotificationBudget.swift`, `RoutineNotificationScheduler.swift` | Auf diesem Stand 50/6/1/7 und nur wiederholende Routine-Mitteilungen; Strang E von #173 ändert auf 46/14/1/3 und führt datierte Mitteilungen ein. Es gibt keine Mitteilungskategorien mit Aktionen (`UNNotificationCategory` kommt im Code nicht vor). |
| `TagwerkCore/HabitRules.swift:15–17, 153–164`, `HabitSuggestions.swift:19`, `Routines/HabitsSection.swift:50–96`, `HabitText.swift` | Quellen `manual, water, workout, steps, daylight, eveningClosed, journal, bibleStudy`; Vorschlag „Bewegung“ mit `.workout`; Zeile mit Haken oder leerem Kreis, „automatisch · …“ nur bei erfüllter Quelle; Tipp auf eine automatisch erfüllte Zeile tut nichts. |
| `Backup/BackupSettingsView.swift`, `BackupService.swift:90–149`, `TagwerkCore/BackupRules.swift` | Formular mit vier Abschnitten; unverschlüsseltes JSON (`schemaVersion = 2`); Wiederherstellen über einen Dialog mit Zahlen der Datei; Sicherheitskopien in `Dokumente/Sicherungen`, nie gelöscht, über `UIFileSharingEnabled` sichtbar. |
| `Tagwerk.entitlements`, `project.yml` | HealthKit und App Group; **keine iCloud-Berechtigung**. Signiert wird laut Projektnotiz mit dem kostenlosen „Personal Team“. |
| `Packages/SecureStore/Sources/SecureStore/SecureStore.swift` | Schlüsselbund für Zeichenketten, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. |
| `Shopping/ShoppingListView.swift:273–316` | Menü mit fünf Einträgen in einer Gruppe; „Alle erledigten löschen“, „Liste leeren“; beide fragen nach. |
| `Shopping/RecipeSheets.swift:163–170, 246–335, 503–630` | `RecipePurpose` als Auswahl vor der Quelle; ein Knopf mit wechselndem Text; Ergebnis mit zwei Portionen-Steppern, einer Liste, „schon auf der Liste“ in der Unterzeile. |
| `Notes/NotionImportView.swift`, `NotionImportModel.swift`, `Settings/NotesSettingsView.swift` | Eine Seite in den Einstellungen mit Segment, Anleitung als Fußtext, Vorschau, „Importieren“. |

## Stränge, Branches und Dateien (Teil 2)

| Strang | Branch | Tasks | Dateien (ändern; **neu** fett) |
|---|---|---|---|
| **RO** Routinen | `feat/g2-routines` | RO1–RO8 | `Routines/MorningSheet.swift`, `EveningSheet.swift`, `NoteField.swift`, **`Routines/TimeWithGodSection.swift`**, `RoutinesModel.swift`, `RoutineSettingsView.swift`, `WeekReflectionSections.swift`, `LeftoverSheet.swift`, `WeekPlanningSheet.swift`, `WeekPlanningModel.swift`, **`Routines/WeekPlanningCard.swift`**, `Planning/DayView.swift`, `TagwerkCore/RoutineSchedule.swift`, **`TagwerkCore/LeftoverPreview.swift`**, **`TagwerkCore/BibleStudyOffer.swift`**, `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift` |
| **BS** Bible Study | `feat/g2-bible-study` | BS1–BS8 | **`TagwerkCore/BibleVerseCounts.swift`** (+ **`Resources/schlachter2000-verses.json`**), **`TagwerkCore/BiblePassage.swift`**, **`TagwerkCore/BibleStudyReminders.swift`**, **`TagwerkCore/BibleStudyHabitTime.swift`**, `TagwerkCore/BibleBooks.swift` (`BibleStudyTemplate`), `TagwerkCore/NotificationBudget.swift`, `TagwerkCore/RoutineSchedule.swift`, `TagwerkCore/AppRoute.swift`, `Notes/BibleStudySessionRecord.swift`, `Notes/NoteStore+BibleStudy.swift`, `Notes/BibleStudyStartSheet.swift`, **`Notes/BibleBookPicker.swift`**, **`Notes/BibleSessionBar.swift`**, `Notes/NoteEditorView.swift` (ein Modifier), `Notes/NoteEditorView+Menu.swift`, `Notes/NotesListView.swift` (Zeile offener Sitzungen), **`Routines/BibleStudySettingsView.swift`**, `Routines/RoutineSettingsView.swift`, `Routines/RoutineNotificationScheduler.swift`, `Notifications/NotificationCenterClient.swift`, Mitteilungs-Delegate, `App/AppEnvironment.swift`, `App/RootView.swift`, `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, **`docs/research/2026-11-20-schlachter-2000-verszahlen.md`** |
| **GW** Gewohnheiten | `feat/g2-habits` | GW1–GW3 | `TagwerkCore/HabitRules.swift`, `HabitSuggestions.swift`, `Routines/HabitsModel.swift`, `HabitsSection.swift`, `HabitText.swift`, `HabitSheet.swift`, **`Routines/HabitMarkerTint.swift`**, `Persistence/AppSettings.swift`, `Assets.xcassets` |
| **DS** Datensicherung | `feat/g2-backup` | DS1–DS4 | **`TagwerkCore/BackupStatus.swift`**, **`TagwerkCore/BackupCrypto.swift`**, `TagwerkCore/BackupRules.swift`, `Backup/BackupService.swift`, **`Backup/BackupKeyStore.swift`**, `Backup/BackupSettingsView.swift`, **`Backup/BackupCoverageView.swift`**, **`Backup/BackupEncryptionView.swift`**, **`Backup/RestoreComparisonSheet.swift`**, `Backup/BackupDocument.swift`, `Backup/BackupDTOs.swift`, `Persistence/AppSettings.swift`, `project.yml`, **`Backup/SafetyCopyStore.swift`**, **`Backup/SafetyCopiesView.swift`** |
| **EK** Einkauf und Rezept | `feat/g2-shopping-recipe` | EK1–EK3 | `Shopping/ShoppingListView.swift`, `Shopping/RecipeSheets.swift`, `Shopping/ShoppingModel.swift`, **`TagwerkCore/ShoppingQuantity.swift`** |
| **TB** Notion-Import | `feat/g2-notion-import` | TB1–TB2 | `Notes/NotionImportView.swift`, `NotionImportModel.swift`, `Notes/NotesListView.swift` (Zeile im leeren Ordner), `Settings/NotesSettingsView.swift` |

---

## Strang RO: Routinen

**Voraussetzung:** G3 Strang T gemergt (Blattknopf „Abschließen“); RO4 zusätzlich #173 Strang E.

### Task RO1: Tagesstart in neuer Reihenfolge, Symbole der Ordner, Hinweis auf den Tagesfokus (RO1b, RO3b, RO4)

**Files:**
- Modify: `Routines/MorningSheet.swift:31–39`, `Routines/NoteField.swift:155–240` (Überschrift mit Symbol), `Routines/RoutinesModel.swift` (Zähler der Fokus-Marken, falls nicht vorhanden), Kataloge
- Test: `app/TagwerkUITests/RoutineUITests.swift`, `app/TagwerkTests/NoteFieldModelTests.swift`

**Interfaces:**

```swift
// NoteField
/// Symbol and named colour of the folder the field writes into (RO4): brain.head.profile / FolderBrainDump,
/// cloud.moon / FolderEvening. Uses `NotesFoldersView.symbol(for:)` and `NoteFolderTint` from NF1.
static func headerLabel(for kind: NoteKind) -> (title: LocalizedStringKey, symbol: String, role: NoteFolderRole)
// MorningSheet
/// "In „Planen“ setzen · 1 von 3 gewählt"
static func focusHint(chosen: Int, maximum: Int) -> String
```

Reihenfolge: Dream Log (mit Fußtext „Bleibt auf diesem iPhone, geht nie an ChatGPT.“), „Dankbar für“ (Symbol `sun.horizon`, nummerierte Felder 1 bis 3, weitere erscheinen beim Füllen wie heute), Brain Dump (mit „Leitfragen einfügen“), zuletzt die Zeile „★ Fokus für heute“ mit `focusHint`; Tipp schließt das Blatt (ohne den Tagesstart als erledigt zu markieren, Eingaben werden gesichert) und zeigt „Planen“ auf heute. Die Blätter zeigen die festen Bezeichnungen „Brain Dump“ und „Dream Log“, nicht umbenannte Ordnernamen (NO4). Liegt NF1 noch nicht auf `main`, legt RO1 `NoteFolderTint` nicht selbst an, sondern wartet (Welle 2).

- [ ] **Step 1: Tests.** UI: `testMorningSheetOrder` (Reihenfolge der Überschriften), `testFocusHintOpensPlanWithoutCompleting`. Unit: `focusHint_counts`, `headerLabel_dreamUsesCloudMoon`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: reorder the morning start and point to today's focus`.

### Task RO2: Karte „Willst du etwas ändern?“ (RO5b)

**Files:**
- Modify: `Routines/NoteField.swift:168–270`, Kataloge
- Test: `NoteFieldModelTests.swift`, `RoutineUITests.swift`

Regel: Sobald das Brain-Dump-Feld Text enthält (`!text.trimmed.isEmpty`), erscheint unter dem Feld eine Karte mit der Überschrift „Willst du etwas ändern?“, dem Satz „Vielleicht hat dir der Brain Dump Klarheit gegeben.“ und den beiden Handlungen „Vorschläge holen“ (nur unter den heutigen Bedingungen aus `NoteField.swift:133–140`) und „Als Aufgabe anlegen“. Der Datenschutzsatz steht als Fußtext direkt unter der Karte: „„Vorschläge holen“ sendet diese Notiz mit deinen Aufgaben und Terminen der nächsten 7 Tage an ChatGPT. Nichts wird ohne deine Bestätigung geändert.“ Ohne Text gibt es weder Karte noch Fußtext. Gilt gleich in Tagesstart und Tagesabschluss; für den Dream Log gibt es die Karte nie. Mit NS1 entfällt „Vorschläge holen“ für gesperrte Notizen.

- [ ] **Step 1: Tests.** `changeCard_hiddenWhileEmpty`, `changeCard_showsBothActionsWithSignIn`, `changeCard_withoutSignIn_offersOnlyTask`, `changeCard_neverForDream`, `privacyFooter_onlyWithSuggestions`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: turn the invitation below the brain dump into a card`.

### Task RO3: Abschnitt „Zeit mit Gott“ mit Zustand, Ort der Bible-Study-Zeile (TB1b, BS6c)

**Files:**
- Create: `TagwerkCore/BibleStudyOffer.swift`, `Routines/TimeWithGodSection.swift`
- Modify: `Routines/EveningSheet.swift:77–100`, `Routines/MorningSheet.swift`, `Routines/RoutineSettingsView.swift` (Abschnitt „Bible Study“ mit der Auswahl; BS6 verschiebt ihn auf eine eigene Seite), `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, Kataloge
- Test: neu `TagwerkCoreTests/BibleStudyOfferTests.swift`, `app/TagwerkTests/RoutinesModelTests.swift`, `RoutineUITests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/BibleStudyOffer.swift
/// Where "Bible Study starten" is offered (BS6c).
public enum BibleStudyOffer: String, Sendable, CaseIterable { case evening, morning, both, never
    public func isOffered(in routine: AppRoute) -> Bool }      // .routineStart / .routineEvening
// AppSettings
var bibleStudyOfferRaw: String = "evening"                     // today's behaviour
// TimeWithGodSection
struct TimeWithGodSection: View {
    let day: PlanDay
    let showsJournal: Bool            // evening only
    let showsBibleStudy: Bool
    let onJournal: () -> Void
    let onBibleStudy: () -> Void
}
enum TimeWithGodText {
    /// "Heute geschrieben · 21:40"; nil without an entry that is more than the template.
    static func journalState(entry: NoteRecord?, calendar: Calendar) -> String?
    /// "Zuletzt: Römer 3,21–31 · Dienstag"; nil without a session.
    static func bibleState(last: BibleStudySessionRecord?, today: PlanDay, calendar: Calendar, locale: Locale) -> String?
}
```

Regeln: Eine Überschrift „Zeit mit Gott“, eine Fußnote „Beides bleibt auf deinem iPhone und geht nie an ChatGPT.“ (mit nur einer Zeile: „Bleibt auf deinem iPhone und geht nie an ChatGPT.“). Zeile Tagebuch: vor dem Schreiben „Tagebuch schreiben“, danach „Tagebuch öffnen“ mit Haken und Unterzeile. Zeile Bible Study: „Bible Study starten“ mit „Zuletzt: …“; bei offener Sitzung „Bible Study fortsetzen“. Im Tagesstart steht der Abschnitt nur, wenn `BibleStudyOffer` ihn dort anbietet (dann ohne Tagebuch-Zeile); im Tagesabschluss immer mit Tagebuch, mit Bible Study je nach Einstellung. Die Stelle in `bibleState` nutzt bis BS2 den gespeicherten Freitext `passage`.

- [ ] **Step 1: Tests.** `offer_eveningIsDefault`, `offer_bothAndNever`, `journalState_templateOnly_isNil`, `journalState_namesTime`, `bibleState_openSession_saysContinue`, `backup_roundTripsOffer`. UI: `testEveningShowsTimeWithGodWithState`, `testMorningShowsBibleStudyWhenOfferedThere`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: group journal and Bible Study in the routines and let the place of Bible Study be chosen`.

### Task RO4: Abend-Checkliste: „Lichter“ relativ zur Schlafzeit, vier Erinnerungen, Glocke in der Liste (RO6b, RO7b)

**Voraussetzung:** #173 Strang E auf `main`.

**Files:**
- Modify: `TagwerkCore/RoutineSchedule.swift:86–112` (`suggestedItems`, `legacySuggestionTitles`, `isLegacySuggestion`), `Routines/RoutineRecords.swift:240–254` (`replaceLegacySuggestion`), `Routines/EveningSheet.swift:51–75`, `Routines/RoutineSettingsView.swift:33–62, 156`, Kataloge (Paket und App)
- Test: `TagwerkCoreTests/RoutineScheduleTests.swift`, `app/TagwerkTests/RoutinesModelTests.swift`, `RoutineNotificationTests.swift`

**Interfaces:**

```swift
// RoutineSchedule
/// The former five-point suggestion in which "Helle Lichter ausmachen" had no time. An untouched list of exactly these
/// points gets the offset 60 for that point once (RO6b); a list the user changed stays as it is.
public static func upgradedLightsOffset(_ items: [ChecklistItem]) -> [ChecklistItem]?
// EveningSheet / RoutineSettingsView texts
enum ChecklistText {
    /// "22:00" for a point that reminds today; "abgehakt, erinnert heute nicht mehr" once checked; nil without an offset.
    static func sheetDetail(_ item: ChecklistItem, bedtime: Int, isChecked: Bool, reminds: Bool, calendar: Calendar) -> String?
    /// "60 min vorher · 22:00"
    static func settingsDetail(_ item: ChecklistItem, bedtime: Int, calendar: Calendar) -> String?
}
```

Regeln: Der Vorschlag gibt „Helle Lichter ausmachen“ den Abstand 60; damit erinnern vier Punkte (90, 60, 60, 30). **Hinweis:** Zwei Punkte liegen dann auf derselben Uhrzeit; das ist gewollt (Mockup RO6b zeigt 22:00 für beide) und der Planer muss zwei Mitteilungen zur selben Minute zulassen. Die Glocke (`bell`, mit `accessibilityLabel("erinnert")`) steht in Blatt und Einstellungen an jedem Punkt, der unter die ersten vier erinnernden fällt (`RoutineSchedule.reminderItems`). Fußtext im Blatt: „🔔 erinnert zur Uhrzeit. Die Zeiten folgen der Schlafzeit. Höchstens vier Punkte erinnern.“ (das Symbol als `Image` im Text, nicht als Emoji).

- [ ] **Step 1: Tests.** `suggestedItems_lightsRemindSixtyMinutesBefore`, `suggestedItems_fourPointsRemind`, `upgradedLightsOffset_untouchedList_setsSixty`, `upgradedLightsOffset_changedList_isNil`, `upgradedLightsOffset_runsOnce` (zweiter Lauf `nil`), `eveningNotifications_twoItemsAtSameMinute_bothPlanned`, `sheetDetail_checked_saysNoReminderToday`, `settingsDetail_namesOffsetAndTime`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: remind to switch off bright lights relative to bedtime and mark reminding points`.

### Task RO5: Wochenreflexion mit Frage über dem Feld (RO8b)

**Files:**
- Modify: `Routines/WeekReflectionSections.swift:72–88`, Kataloge
- Test: `app/TagwerkUITests/` (Wochenplanung), `AccessibilityAudit…` falls die Seite geprüft wird

Jede der drei Fragen („Was lief gut?“, „Belastet mich etwas?“, „Wie laufen meine Ziele, Projekte und Tasks?“) steht als Beschriftung über ihrem Feld (`.font(.subheadline.weight(.semibold))`), das Feld hat den Platzhalter „Antwort“ und als `accessibilityLabel` die Frage. Gleicher Aufbau im Wochenrückblick und im Schritt „Reflexion“ (beide nutzen `WeekReflectionFields`).

- [ ] **Step 1:** UI-Test `testReflectionQuestionsStayVisibleWithAnswer`. **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: keep the reflection questions visible above their fields`.

### Task RO6: „Unerledigtes verschieben“ mit Vorschau und Ergebnisliste (RO9c, RO11b)

**Files:**
- Create: `TagwerkCore/LeftoverPreview.swift`
- Modify: `Routines/LeftoverSheet.swift:9–14, 66–130, 171–206`, `Routines/EveningSheet.swift:164–193`, Kataloge
- Test: neu `TagwerkCoreTests/LeftoverPreviewTests.swift`, `app/TagwerkTests/LeftoverSheetTextTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/LeftoverPreview.swift
public enum LeftoverPreview {
    public enum Fit: Sendable, Equatable { case fits(freeMinutes: Int), tight(freeMinutes: Int, neededMinutes: Int), dayOff }
    /// Whether the estimated minutes of the tasks fit into the free minutes of the target day.
    public static func fit(neededMinutes: Int, freeMinutes: Int?, isDayOff: Bool) -> Fit
}
// LeftoverSheet
struct Report: Equatable {
    var moved: Int; var late: Int; var unplaced: Int; var moves: [PlanningModel.DayMove]
    /// Tasks that found no free place, with the reason shown in the result list (RO11b).
    var unplacedTasks: [Unplaced] = []
    struct Unplaced: Equatable, Identifiable { let id: TaskID; let title: String; let due: PlanDay? }
}
enum LeftoverSheetText {
    static func header(count: Int, minutes: Int) -> String                  // "3 Aufgaben · 2 h 30"
    static func moveAllSubtitle(fit: LeftoverPreview.Fit, day: PlanDay, calendar: Calendar) -> String   // "Samstag hat 4 h frei · passt"
    static func taskList(_ titles: [String]) -> String                      // "Exposé Kapitel 2 · Mail an Vermieter · Wäsche"
    static func unplacedReason(due: PlanDay?, calendar: Calendar) -> String // "Kein freier Platz vor der Fälligkeit (Mo.)"
}
```

Regeln: Das Blatt bleibt (RO9c). Kopf mit Anzahl und Summe der Schätzungen (Aufgaben ohne Schätzung zählen mit `defaultTaskMinutes`). „Alles auf morgen“ zeigt, ob der Zieltag Platz hat („passt“, „knapp: 1 h 30 frei, 2 h 30 nötig“, „kein Arbeitstag“); „Einzeln entscheiden“ nennt die Titel. Nach dem Verschieben zeigt der Tagesabschluss statt eines Satzes: Zeile „✓ 2 verschoben“ mit „Rückgängig“ und je nicht platzierter Aufgabe eine Zeile mit Grund und Menü: „Datum …“ (öffnet die vorhandene Datumswahl), „Trotzdem auf morgen“, „Erledigt“ (nur für Quellen, die sich offline abhaken lassen; sonst ausgegraut).

- [ ] **Step 1: Tests.** `fit_fits`, `fit_tight`, `fit_dayOff`, `header_sumsMinutes`, `moveAllSubtitle_namesDayAndFit`, `taskList_joinsAndTruncatesAfterThree` („… und 2 weitere“), `unplacedReason_withAndWithoutDue`, `report_carriesUnplacedTasks`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: preview the leftover move and list tasks that found no place`.

### Task RO7: Zeile in der Kapazitätskarte prüfen und angleichen (RO10a)

**Files:**
- Modify: `Planning/DayView.swift:261–285` (`CapacityCard`, `LeftoverLine`), ggf. `PlanningModel` (`leftFromToday`), Kataloge
- Test: `app/TagwerkTests/PlanningModelTests.swift`, `DayPanelTextTests.swift`

Befund: Die Zeile ist gebaut. Zu prüfen und, wo nötig, anzugleichen: (1) Sie erscheint nur, wenn es Unerledigtes von heute gibt **und** entweder die Kapazität überschritten ist oder es später Nachmittag ist (ab zwei Stunden vor Ende der Arbeitszeit); sonst bleibt die Karte zweizeilig. (2) Wortlaut „Unerledigtes verschieben · 3 Aufgaben“ mit Pfeil `arrowshape.turn.up.right`. (3) Trefferfläche 44 pt. **Dieser Task läuft nach dem G1-Strang „Planen“ oder in Absprache mit ihm** (Teil 1, offene Frage 9); ändert G1 die Karte grundlegend, wird nur die Bedingung als reine Funktion geliefert.

```swift
// TagwerkCore (next to LeftoverPreview)
/// Whether the capacity card offers "Unerledigtes verschieben" (RO10a).
public static func showsLeftoverLine(leftoverCount: Int, isOverCapacity: Bool, minutesOfDay: Int, workdayEndMinutes: Int) -> Bool
```

- [ ] **Step 1:** Tests `showsLeftoverLine_noTasks_false`, `…_overCapacity_true`, `…_lateAfternoon_true`, `…_morningWithinCapacity_false`. **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: show the leftover line in the capacity card only when it matters`.

### Task RO8: Wochenplanung mit Balken, Schritt-Titel, „Überspringen“ und Karte in „Planen“ (RO12b, RO15b)

**Files:**
- Create: `Routines/WeekPlanningCard.swift`
- Modify: `Routines/WeekPlanningSheet.swift:20–58, 199–203`, `Routines/WeekPlanningModel.swift`, `Planning/DayView.swift` (Karte am Planungstag, an der Stelle der Karte „Tagesstart“), `Routines/RoutinesModel.swift`, `Persistence/AppSettings.swift` (`weekPlanningCardDismissedDayKey: String? = nil`), Kataloge
- Test: `app/TagwerkTests/RoutinesModelTests.swift`, UI-Test der Wochenplanung

**Interfaces:**

```swift
// WeekPlanningSheet texts
static func stepSubtitle(number: Int, count: Int, next: String?) -> String   // "Schritt 2 von 5 · danach: Fälligkeiten der neuen Woche"
// RoutinesModel
/// The card "Wochenplanung" in "Planen": only on the weekday of the weekly planning reminder, only on today,
/// until the planning was finished or the card was hidden for today.
var showsWeekPlanningCard: Bool { get }
func hideWeekPlanningCardToday()
```

Regeln: Fünf Segmente als Balken (`accessibilityValue("Schritt 2 von 5")`), großer Titel des Schritts, Unterzeile mit dem nächsten Schritt; „Überspringen“ in der Leiste (wie „Weiter“, ohne zu speichern, was der Schritt verlangt hätte; im letzten Schritt entfällt es). Die Karte zeigt „Wochenplanung“, „Rückblick auf KW 47, dann KW 48 planen · etwa 10 min“, „Starten“ und „Heute ausblenden“; maßgeblich ist `weekPlanningReminderWeekday`, auch wenn die Erinnerung selbst aus ist. Die beiden bisherigen Einstiege bleiben. `DayView` wird wie in RO7 mit G1 abgestimmt.

- [ ] **Step 1: Tests.** `stepSubtitle_namesNext`, `stepSubtitle_lastStepHasNoNext`, `weekPlanningCard_onlyOnPlanningWeekday`, `weekPlanningCard_hiddenAfterFinish`, `weekPlanningCard_hideIsForTodayOnly`. UI: `testSkipAdvancesWithoutSaving`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: show progress in the weekly planning and offer it in the plan on the planning day`.

---

## Strang BS: Bible Study

### Task BS1: Kapitel- und Verszahlen der Schlachter 2000 (BV3a) – Rechercheaufgabe für einen eigenen Sonnet-Umsetzer

**Dieser Task wird nicht aus dem Gedächtnis gelöst und dieser Plan nennt bewusst keine Verszahlen.** Die Zahlen kommen aus einer nachprüfbaren Quelle; der Umsetzer dokumentiert sie.

**Files:**
- Create: `TagwerkCore/BibleVerseCounts.swift`, `app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/schlachter2000-verses.json`, `docs/research/2026-11-20-schlachter-2000-verszahlen.md`, `scripts/check-verse-table.py`
- Test: neu `TagwerkCoreTests/BibleVerseCountsTests.swift`

**Interfaces (Produces):**

```swift
/// Chapter and verse counts in the numbering of German Bibles (edition: Schlachter 2000). One number per chapter.
public enum BibleVerseCounts {
    public static let edition = "Schlachter 2000"
    /// Number of chapters of a book (`BibleBook.number`, 1…66); 0 for an unknown book.
    public static func chapterCount(book: Int) -> Int
    /// Number of verses of a chapter; 0 for an unknown book or chapter.
    public static func verseCount(book: Int, chapter: Int) -> Int
    public static func isValid(book: Int, chapter: Int, verse: Int) -> Bool
}
```

Vorgehen (verbindlich):
- [ ] **Step 1: Quelle wählen und belegen.** Eine maschinenlesbare Quelle, die ausdrücklich die Verszählung der Schlachter 2000 wiedergibt (Verlagsangabe, Online-Ausgabe oder ein veröffentlichter Versifikationsdatensatz). In `docs/research/…-verszahlen.md` stehen: Name und Adresse der Quelle, Abrufdatum, wie die Zahlen gewonnen wurden (Befehle oder Skript), die Lizenzlage (übernommen werden nur Zahlen, kein Bibeltext), eine Prüfsumme der JSON-Datei.
- [ ] **Step 2: Gegenprobe.** Eine **zweite, unabhängige** Quelle für dieselbe Ausgabe; `scripts/check-verse-table.py` vergleicht alle Kapitel und listet Abweichungen. Jede Abweichung wird im Dokument einzeln aufgeführt und begründet entschieden; lässt sie sich nicht klären, steht sie unter „Offen“ und geht als Frage an den Nutzer (Teil 1, offene Frage 10). Lässt sich keine zweite Quelle finden, steht das ausdrücklich im Dokument und die Hauptsitzung entscheidet, ob eine Stichprobe von mindestens 40 Kapiteln gegen eine gedruckte oder gescannte Ausgabe genügt.
- [ ] **Step 3: Unterschiede zur englischen Zählung dokumentieren.** Mindestens die in der Entscheidung genannten Stellen: Psalmen mit Überschrift (in deutschen Ausgaben zählt die Überschrift als Vers), Joel (Kapiteleinteilung), Maleachi (Kapitel 3 gegenüber 3 und 4). Für jede Stelle stehen im Dokument beide Zählungen nebeneinander mit Quelle für die englische Seite (eine gängige englische Ausgabe, benannt). Weitere Abweichungen, die der Vergleich zeigt, kommen in dieselbe Tabelle.
- [ ] **Step 4: Tests** (alle erwarteten Zahlen stammen aus dem Dokument von Step 1–3, mit Verweis im Testkommentar):
  - Struktur: `table_has66Books`, `table_totalChapterCountMatchesSource`, `table_totalVerseCountMatchesSource`, `table_noChapterIsEmpty`, `table_matchesBibleBooksOrder` (Nummern 1–66 wie `BibleBooks.all`).
  - Abweichungen: je ein Test für mindestens drei Psalmen mit Überschrift (deutsche Verszahl ungleich der englischen, beide aus dem Dokument), `joel_chapterCountFollowsGermanNumbering`, `malachi_chapterCountFollowsGermanNumbering`, dazu die Verszahl des jeweils letzten Kapitels von Joel und Maleachi.
  - Regeln: `isValid_rejectsVerseBeyondChapter`, `isValid_rejectsChapterBeyondBook`, `unknownBook_isZero`.
  - Datei: `resource_checksumMatchesDocumentation`.
- [ ] **Step 5:** `PKG TagwerkCore BibleVerseCountsTests` rot, dann Tabelle einbinden (JSON als Ressource des Pakets, einmal gelesen und zwischengespeichert), grün, `ALL`.
- [ ] **Step 6:** Commit `feat: add the chapter and verse counts of the Schlachter 2000 numbering`. Der Pull Request verlinkt das Dokument und nennt offene Abweichungen.

### Task BS2: Stelle als Zahlen, nächster Vers, Sitzungsdaten

**Files:**
- Create: `TagwerkCore/BiblePassage.swift`
- Modify: `Notes/BibleStudySessionRecord.swift`, `Notes/NoteStore+BibleStudy.swift:40–70`, `TagwerkCore/BibleBooks.swift:114–127` (`BibleStudyTemplate`), `Backup/BackupDTOs.swift:757–788`
- Test: neu `TagwerkCoreTests/BiblePassageTests.swift`, `app/TagwerkTests/BibleStudyStoreTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/BiblePassage.swift
public struct BibleReference: Sendable, Hashable, Comparable { public var chapter: Int; public var verse: Int }
public struct BiblePassage: Sendable, Hashable {
    public var start: BibleReference
    /// `nil` while the end is open (BV2b).
    public var end: BibleReference?
    /// "3,21–31", "3,21–4,9", "3,21–" (open end).
    public func text() -> String
    /// Reads "3,21-31", "3,21–4,9", "3,21" and "3, 21 - 31"; anything else is `nil` (free text stays free text).
    public static func parse(_ text: String) -> BiblePassage?
}
public enum BibleProgress {
    public enum Next: Sendable, Equatable {
        case start(BibleReference)                    // the next verse, or 1,1 for a first session
        case bookFinished(last: BibleReference)       // the last session ended on the last verse of the book
    }
    /// The verse after `end` in the book: next verse, first verse of the next chapter, or `bookFinished`.
    public static func next(after end: BibleReference, book: Int) -> Next
    /// The suggestion for a new session from the latest session of the book: after its end, or "Weiter ab" its start
    /// while it has no end.
    public static func suggestion(lastStart: BibleReference?, lastEnd: BibleReference?, book: Int) -> Next
    /// The end offered when a session is completed: the chosen end, else the end of the start chapter.
    public static func defaultEnd(start: BibleReference, chosenEnd: BibleReference?, book: Int) -> BibleReference
}

// BibleStudySessionRecord (0 = unknown, for sessions typed as free text)
var startChapter: Int = 0
var startVerse: Int = 0
var endChapter: Int = 0
var endVerse: Int = 0

// NoteStore+BibleStudy
func lastSession(bookKey: String) -> BibleStudySessionRecord?          // latest by `startedAt`, open ones included
func recentBookKeys(limit: Int = 3) -> [String]
func startSession(book: BibleBook, passage: BiblePassage?, freeText: String?, dayKey: String, dateText: String, locale: Locale = .current) -> (note: NoteRecord, session: BibleStudySessionRecord)
/// Completes the session, stores the end and completes the heading of its section in the note when the line is still
/// exactly the one written at the start.
func completeSession(_ id: UUID, end: BibleReference?)
// BibleStudyTemplate
public static func replacingSessionHeading(in text: String, dateText: String, oldPassage: String, newPassage: String) -> String
```

Regeln: Die bisherige Funktion `startSession(book:passage:…)` mit Freitext bleibt als Hülle erhalten. Alte Sitzungen werden beim Lesen ausgewertet, soweit `BiblePassage.parse(passage)` etwas liefert (keine Datenmigration). Eine Stelle außerhalb der Tabelle (`BibleVerseCounts.isValid == false`) gilt als Freitext. Hat die Nutzerin die Überschrift geändert, bleibt der Notiztext unberührt und nur die Sitzung bekommt das Ende. Aus Notion importierte Notizen haben keine Sitzungen und liefern keinen Vorschlag. Sicherung: die vier Felder optional in `BibleStudySessionBackup`.

- [ ] **Step 1: Tests.** `parse_singleChapterRange`, `parse_acrossChapters`, `parse_startOnly`, `parse_withSpacesAndHyphen`, `parse_garbage_isNil`, `text_openEnd`, `next_withinChapter`, `next_chapterEnd_goesToNextChapter`, `next_bookEnd_isFinished` (Kapitel- und Versgrenzen aus `BibleVerseCounts`, nicht als feste Zahlen im Test), `suggestion_firstSession_isOneOne`, `suggestion_openSession_continuesAtItsStart`, `defaultEnd_isChapterEnd`; Store: `lastSession_perBook`, `recentBookKeys_distinctNewestFirst`, `completeSession_storesEndAndCompletesHeading`, `completeSession_changedHeading_leavesTextAlone`, `legacySession_isParsedOnRead`; `BackupTests.session_roundTripsReferenceFields`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: store Bible passages as chapter and verse and suggest the next verse`.

### Task BS3: Startblatt mit „Zuletzt“, Suche und Rädern (BS2b, BV1b, BV2b, BV3a)

**Files:**
- Create: `Notes/BibleBookPicker.swift`
- Modify: `Notes/BibleStudyStartSheet.swift` (Neuaufbau), Kataloge
- Test: neu `app/TagwerkTests/BibleStudyStartModelTests.swift`, UI-Test der Bible Study

**Interfaces:**

```swift
@MainActor @Observable final class BibleStudyStartModel {
    private(set) var recentBooks: [BibleBook]            // up to three
    var book: BibleBook
    var from: BibleReference
    var to: BibleReference?                              // nil = "offen"
    var usesFreeText = false
    var freeText = ""
    /// "Weiter nach 3,1–20 vom 17.11." / "Weiter ab 3,21 (Sitzung vom 20.11. ist noch offen)" / nil for a first session.
    var hint: String? { get }
    /// "Römer ist zu Ende gelesen (16,27 am 14.01.). Wähle ein anderes Buch oder beginne Römer neu."
    var finishedNotice: String? { get }
    var startTitle: String { get }                       // "Sitzung starten · Römer 3,21"
    func select(_ book: BibleBook)                       // sets `from` to the suggestion of that book, `to` to nil
    func start(store: NoteStore, day: PlanDay) -> UUID
}
```

Aufbau: Abschnitt „Buch“ mit bis zu drei Chips der zuletzt gelesenen Bücher und „Anderes …“ (öffnet `BibleBookPicker`: Liste „Altes Testament“/„Neues Testament“ mit Suchfeld, das auch die Aliase aus `BibleBooks` findet). Abschnitt „Stelle“: Zeile „Von“ mit dem Vorschlag und dem Hinweis; Tipp klappt zwei Räder (Kapitel, Vers) auf, begrenzt durch `BibleVerseCounts`; Zeile „Bis“ mit „offen“ als Vorgabe, Räder ab „Von“. Unter den Rädern „Stelle frei eingeben“: zeigt ein Textfeld statt der Räder; eine frei eingegebene Stelle wird ausgewertet, wenn sie dem Muster folgt, sonst als Text gespeichert (dann ohne Vorschlag beim nächsten Mal). Buch zu Ende: Hinweis und „Von 1,1 · von vorn“; kein Sprung ins nächste Buch. Fußtext wie heute. Knopf unten `startTitle`; „Starten“ in der Leiste entfällt. Kapitel und Verse bleiben auch bei vorgewähltem Buch änderbar.

- [ ] **Step 1: Tests.** `model_preselectsLastBookAndNextVerse`, `model_firstSessionStartsAtOneOne`, `select_otherBook_resetsFromAndTo`, `hint_namesLastPassageAndDate`, `finishedNotice_onlyAfterLastVerse`, `startTitle_withOpenEnd`, `freeText_parsable_storesNumbers`, `freeText_unparsable_storesText`, `toCannotPrecedeFrom`. UI: `testStartSheetSuggestsNextVerse`, `testOtherBookSearchFindsAlias`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: start a Bible Study session from recent books with chapter and verse wheels`.

### Task BS4: Sitzungsleiste in der Notiz, Abschließen mit „Bis wohin gelesen?“ (BS1b, BV2b)

**Voraussetzung:** NE gemergt.

**Files:**
- Create: `Notes/BibleSessionBar.swift`
- Modify: `Notes/NoteEditorView.swift` (ein `safeAreaInset(edge: .top)`), `Notes/NoteEditorView+Menu.swift` (Eintrag „Bible Study abschließen“ entfällt), `Notes/NotesListView.swift:159–181` („Abschließen“ in der Ordnerliste öffnet dieselbe Abfrage), Kataloge
- Test: `BibleStudyStoreTests.swift`, UI-Test

Regeln: Solange `store.openSession(noteID:)` etwas liefert, steht über dem Text die Leiste „Sitzung läuft · Römer ab 3,21“ mit „Abschließen“. Tipp klappt „Bis wohin gelesen?“ mit zwei Rädern auf, vorbelegt mit `BibleProgress.defaultEnd`; der Knopf darunter heißt „Abschließen · 3,21–26“. Bestätigen ruft `saveText()` und `completeSession(_:end:)`; die Leiste wird für zwei Sekunden grün („Sitzung abgeschlossen ✓“, zusätzlich als VoiceOver-Ansage) und verschwindet. Bei einer Sitzung mit Freitext-Stelle schließt „Abschließen“ ohne Räder ab. Zurückgehen lässt die Sitzung offen (wie heute). Die geänderte Überschrift im Notiztext kommt über den Store; der Editor übernimmt sie über A5 (`adoptStoredText`).

- [ ] **Step 1: Tests.** UI: `testSessionBarCompletesWithChosenEnd` (Überschrift im Text ergänzt, Leiste weg), `testLeavingKeepsSessionOpen`, `testCompleteFromFolderList`. Unit: `completeFromEditor_adoptsNewHeading` (über `NoteEditorSync`).
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: show the running Bible Study session in the note and confirm its end`.

### Task BS5: „Als Aufgabe anlegen“ an einer Checkbox (BS5b)

**Voraussetzung:** NE gemergt (Kontextmenü-Haken `NoteMarkdownView.contextMenu`).

**Files:**
- Modify: `Notes/NoteEditorView.swift` bzw. `+Menu.swift` (Menü für `tagwerk-toggle:`-Links), `TagwerkCore/MarkdownText.swift` (zwei Funktionen), `TagwerkCore/NoteHTMLRenderer.swift` (Marke), Kataloge
- Test: `TagwerkCoreTests/MarkdownTextTests.swift`, `NoteHTMLRendererTests`, UI-Test

**Interfaces:**

```swift
// MarkdownText
public static let taskMarker = "→ Aufgabe"            // also recognised: "→ Task"
/// The text of the checkbox line at `index` without the box and without the marker.
public static func checkboxTitle(at index: Int, in markdown: String) -> String?
/// Appends the marker to the checkbox line at `index`; a line that already has it is unchanged.
public static func markingCheckboxAsTask(at index: Int, in markdown: String) -> String
```

Regeln: Nur in Bible-Study-Notizen. Halten auf einer Checkbox-Zeile der Ansicht zeigt „Als Aufgabe anlegen“ und „Abhaken“. „Als Aufgabe anlegen“ öffnet das vorhandene Blatt „Neue Aufgabe“ mit dem Titel der Zeile und dem Hinweis „Der Titel wird eine normale Aufgabe und ist dann nicht mehr privat (Erinnerungen, Assistent).“; erst nach dem Sichern bekommt die Zeile die Marke (über `saveText()`). Der Renderer zeigt die Marke am Zeilenende in `--muted`. Nichts wird automatisch angelegt.

- [ ] **Step 1: Tests.** `checkboxTitle_stripsBoxAndMarker`, `markingCheckboxAsTask_appendsOnce`, `markingCheckboxAsTask_keepsOtherLines`, `renderer_marksTaskSuffixMuted`. UI: `testCreateTaskFromBibleStudyCheckbox`, `testCancelLeavesLineUnmarked`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: create a task from a checkbox of a Bible Study note`.

### Task BS6: Seite „Bible Study“ unter Routinen: Ort und Erinnerungszeiten (BS6c, BE2b)

**Voraussetzung:** RO3 gemergt.

**Files:**
- Create: `Routines/BibleStudySettingsView.swift`
- Modify: `Routines/RoutineSettingsView.swift` (Abschnitt aus RO3 wird eine Zeile, die auf die Seite führt), `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, Kataloge
- Test: neu `TagwerkCoreTests/BibleStudyRemindersTests.swift` (Teil Zeiten), `BackupTests`

**Interfaces (Produces):**

```swift
// TagwerkCore/BibleStudyReminders.swift
/// One reminder time with its weekdays (alarm model, BE2b). Weekdays as in `Calendar` (1 = Sunday).
public struct BibleStudyReminderTime: Sendable, Hashable, Codable, Identifiable {
    public var id: UUID; public var minutes: Int; public var weekdays: Set<Int>
}
public enum BibleStudyReminderTimes {
    /// Every weekday belongs to at most one time: adding or changing a time removes its weekdays from the others;
    /// a time left without weekdays is dropped.
    public static func saving(_ time: BibleStudyReminderTime, into times: [BibleStudyReminderTime]) -> [BibleStudyReminderTime]
    /// Weekdays that other times already use (shown as not selectable in the sheet of `time`).
    public static func takenWeekdays(for time: BibleStudyReminderTime, in times: [BibleStudyReminderTime]) -> Set<Int>
    public static func minutes(on weekday: Int, in times: [BibleStudyReminderTime]) -> Int?
    public static func summary(_ time: BibleStudyReminderTime, locale: Locale) -> String   // "06:45 · Mo Di Mi Do Fr"
}
// AppSettings
var bibleStudyReminderEnabled: Bool = false
var bibleStudyReminderTimesData: Data? = nil
var bibleStudyReminderShowsPassage: Bool = true
var bibleStudySkippedDayKey: String? = nil            // "Heute nicht"
var bibleStudySuggestionSnoozedUntil: Date? = nil     // "Nicht jetzt" (BS8)
```

Seite: „Anbieten im“ (Tagesstart, Tagesabschluss, beides, nicht anzeigen); Schalter „Erinnerung“; Liste „Zeiten“ mit „Zeit hinzufügen“ (Blatt: Uhrzeit in 5-Minuten-Schritten, Wochentage als sieben Knöpfe, vergebene Tage ausgegraut mit dem Satz „Mo–Fr sind schon bei 06:45 vergeben und hier nicht wählbar.“, „Zeit löschen“); Schalter „Stelle in der Mitteilung zeigen“ mit Fußtext „Die Mitteilung nennt Buch und nächsten Vers, zum Beispiel „Weiter in Römer ab 3,27“. Sie steht auch auf dem Sperrbildschirm. Ausgeschaltet heißt es nur „Zeit für Bible Study.““; Abschnitt „Vorschlag aus deinen Sitzungen“ (BS8); Fußtext „Übernommene Zeiten ändern sich nicht von selbst. Entfällt an Tagen mit abgeschlossener Sitzung. Tagwerk plant die Erinnerung für die nächsten 3 Tage und füllt sie nach, sobald du die App öffnest.“ Fehlt die Mitteilungserlaubnis, fragt der Schalter danach.

- [ ] **Step 1: Tests.** `saving_movesWeekdaysToTheNewTime`, `saving_dropsTimeWithoutWeekdays`, `takenWeekdays_excludesOwn`, `minutes_onWeekday`, `summary_ordersWeekdaysFromMonday`, `backup_roundTripsTimesAndSwitches`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: add Bible Study settings with reminder times per weekday`.

### Task BS7: Erinnerung planen, Budget, Mitteilung mit „Starten“ und „Heute nicht“ (BS4, BE1c, Zusatz des Nutzers)

**Voraussetzung:** #173 Strang E auf `main` (`DatedRoutineNotification`, `addDated`, Nachfüllen im Hintergrundabruf).

**Budget (verbindlich):** Bible Study braucht je Tag höchstens eine Mitteilung und wird drei Tage im Voraus geplant, also drei Plätze. Die Reserve von drei Plätzen ganz zu verbrauchen ließe keinen Spielraum; deshalb gibt die größte Gruppe zwei Plätze ab und die Reserve einen:

| Gruppe | #173 Strang E | **neu** |
|---|---|---|
| Aufgaben und Deadlines | 46 | **44** |
| Routinen | 14 (Abend 12, Tagesstart 1, Wochenplanung 1) | **17** (zusätzlich Bible Study 3) |
| Fokus | 1 | 1 |
| Reserve | 3 | **2** |
| Summe | 64 | 64 |

**Files:**
- Modify: `TagwerkCore/BibleStudyReminders.swift` (Planung), `TagwerkCore/NotificationBudget.swift`, `TagwerkCore/RoutineSchedule.swift` (`maximumRoutineNotifications = 17`, `bibleStudyHorizonDays = 3`), `TagwerkCore/AppRoute.swift` (`bibleStudyStart = "bible/start"`), `Routines/RoutineNotificationScheduler.swift`, `Notifications/NotificationCenterClient.swift` (Kategorie und Aktionen), der Mitteilungs-Delegate, `Notes/NoteStore+BibleStudy.swift` (Haken nach Start und Abschluss), `App/AppEnvironment.swift`, `App/RootView.swift` (Route öffnet das Startblatt), `Notifications/NotificationScheduler.swift` (nur über das Budget), `TagwerkTests/Fakes/FakeNotificationCenter.swift`, Kataloge
- Test: `TagwerkCoreTests/BibleStudyRemindersTests.swift`, `NotificationBudgetTests.swift`, `app/TagwerkTests/RoutineNotificationTests.swift`, `NotificationSchedulerTests.swift` (Grenze 44), `AppRouterTests.swift`

**Interfaces (Produces):**

```swift
public enum BibleStudyReminders {
    public static let categoryIdentifier = "tagwerk.bible"
    public static let startAction = "tagwerk.bible.start"
    public static let skipAction = "tagwerk.bible.skip"
    /// "tagwerk.routine.bible.<YYYY-MM-DD>"
    public static func identifier(day: PlanDay) -> String
    /// One reminder per day for the next `days` days, starting today. Left out: days without a time for their weekday,
    /// days with a completed session, the skipped day, and moments that are not after `now`.
    /// The body is "Zeit für Bible Study." and, when `nextPassage` is given, " Weiter in Römer ab 3,27."
    public static func notifications(times: [BibleStudyReminderTime], enabled: Bool, completedDays: Set<PlanDay>,
                                     skippedDay: PlanDay?, nextPassage: String?, now: Date, calendar: Calendar,
                                     locale: Locale, days: Int = RoutineSchedule.bibleStudyHorizonDays) -> [DatedRoutineNotification]
    /// "Weiter in Römer ab 3,27" from the book of the latest session and its suggestion; nil without a session, for a
    /// finished book, for a free-text passage and when the switch "Stelle in der Mitteilung zeigen" is off.
    public static func nextPassageText(bookName: String?, next: BibleProgress.Next?, showsPassage: Bool) -> String?
}
```

Regeln:
- `RoutineNotificationScheduler.perform()` fügt die Bible-Study-Mitteilungen über `addDated` hinzu; Kappung auf 17 mit der Reihenfolge Abend (12), Tagesstart, Wochenplanung, Bible Study (3).
- **Neu geplant wird** nach jedem Start und Abschluss einer Sitzung (der Text mit dem nächsten Vers stimmt nur dann), nach jeder Änderung der Einstellungen, beim Aktivwerden der App und im Hintergrundabruf. Beim Abschließen entfällt die Mitteilung von heute sofort.
- Mitteilung: Titel „Bible Study“, Aktionen „Starten“ (öffnet die App mit `AppRoute.bibleStudyStart`) und „Heute nicht“ (ohne die App zu öffnen: setzt `bibleStudySkippedDayKey` auf heute und entfernt die Mitteilung). Ein Tipp auf die Mitteilung öffnet das Startblatt. `threadIdentifier = "routine"`.
- Wie die übrigen Routine-Erinnerungen kommt sie auch in Ruhezeiten; der Hinweis dazu in den Einstellungen bleibt gültig.
- Der Text nennt nie Notizinhalt, nur Buch und Vers; mit ausgeschaltetem Schalter nur „Zeit für Bible Study.“
- Grenze, die in den Einstellungen steht (BS6): Wird die App drei Tage nicht geöffnet und läuft kein Hintergrundabruf, bleibt die Erinnerung danach aus.

- [ ] **Step 1: Tests.** `notifications_planThreeDays`, `notifications_skipDayWithoutTime`, `notifications_skipCompletedDay`, `notifications_skipSkippedDayOnly`, `notifications_skipPastMoment`, `notifications_disabled_isEmpty`, `notifications_bodyWithAndWithoutPassage`, `notifications_summerTimeDay_keepsClockTime`, `nextPassageText_hiddenBySwitch`, `nextPassageText_finishedBook_isNil`, `identifier_isStablePerDay`; `NotificationBudgetTests.allocatedIsSystemLimit` (44 + 17 + 1 + 2); Planer: `reschedule_addsBibleStudyReminders`, `reschedule_neverExceedsSeventeen`, `completeSession_removesTodaysReminderAndReplans`, `skipAction_setsSkippedDayAndRemoves`, `skipFromYesterday_doesNotAffectToday`; `NotificationSchedulerTests`: Grenze 44; `AppRouterTests.bibleStudyStart_opensStartSheet`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: remind of Bible Study at chosen times, planned three days ahead`.

### Task BS8: Gelernter Vorschlag, den man bestätigt (BE1c, BE3b)

**Files:**
- Create: `TagwerkCore/BibleStudyHabitTime.swift`
- Modify: `Notes/BibleSessionBar.swift` (Karte nach dem Abschließen), `Routines/BibleStudySettingsView.swift` (Abschnitt „Vorschlag aus deinen Sitzungen“), Kataloge
- Test: neu `TagwerkCoreTests/BibleStudyHabitTimeTests.swift`

**Interfaces (Produces):**

```swift
public enum BibleStudyHabitTime {
    public static let weeks = 8
    public static let minimumSessions = 5
    public static let windowMinutes = 60
    public static let minimumShare = 2.0 / 3.0
    public static let minimumDifferenceMinutes = 20
    public static let snoozeDays = 28
    public enum Group: Sendable, Equatable { case weekdays, weekend }
    public struct Suggestion: Sendable, Equatable {
        public let group: Group
        public let minutes: Int                 // middle of the window, rounded to 5 minutes
        public let sessionsInWindow: Int
        public let sessions: Int
        public let windowStart: Int, windowEnd: Int
    }
    /// At most one suggestion per group from the start times of completed sessions of the last `weeks` weeks.
    /// None when fewer than `minimumSessions`, when less than `minimumShare` lie within one `windowMinutes` window,
    /// when the time differs by less than `minimumDifferenceMinutes` from the time already set for all days of the
    /// group, or while snoozed.
    public static func suggestions(startTimes: [Date], existing: [BibleStudyReminderTime], snoozedUntil: Date?,
                                   now: Date, calendar: Calendar) -> [Suggestion]
}
```

Regeln: Die Schwellen sind gesetzte Startwerte ohne Messung (Mockup, „Annahme, nicht belegt“); sie stehen als benannte Konstanten an einer Stelle. Nach dem Abschließen einer Sitzung zeigt die Notiz einmal je neuem Vorschlag die Karte „Du beginnst werktags meist gegen 06:40. Soll Tagwerk dich Mo–Fr um 06:45 erinnern?“ mit „Nicht jetzt“ (28 Tage Ruhe), „Zeit ändern“ (öffnet das Zeit-Blatt aus BS6) und „Erinnern“ (übernimmt die Zeit, schaltet die Erinnerung ein, fragt bei Bedarf nach der Erlaubnis). Derselbe Vorschlag steht in den Einstellungen mit der Begründung „An 7 der letzten 8 Wochenenden hast du zwischen 08:10 und 08:50 begonnen.“ (Zahlen aus `Suggestion`). Übernommene Zeiten ändern sich nie von selbst.

- [ ] **Step 1: Tests.** `suggestion_needsFiveSessions`, `suggestion_needsTwoThirdsInOneHour`, `suggestion_roundsToFiveMinutes`, `suggestion_separatesWeekdaysAndWeekend`, `suggestion_ignoresSessionsOlderThanEightWeeks`, `suggestion_noneWhenCloseToExistingTime`, `suggestion_noneWhileSnoozed`, `suggestion_scatteredTimes_none`, `suggestion_windowAcrossMidnight_isNotJoined`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: suggest a Bible Study reminder time from past sessions`.

---

## Strang GW: Gewohnheiten

### Task GW1: Kombinierte Quelle „Training oder Schrittziel“ (GW1c)

**Files:**
- Modify: `TagwerkCore/HabitRules.swift:15–17, 153–164`, `TagwerkCore/HabitSuggestions.swift:19`, `Routines/HabitText.swift:50–97`, `Routines/HabitSheet.swift` (Auswahl „Erfüllt durch“), `Routines/HabitsModel.swift` (einmalige Umstellung), `Persistence/AppSettings.swift` (`movementSourceMigrated: Bool = false`), Kataloge (Paket und App)
- Test: `TagwerkCoreTests/HabitRulesTests.swift`, `HabitSuggestionsTests.swift`, `app/TagwerkTests/HabitTextTests.swift`, `HabitAutomaticSourcesTests.swift`, `HabitsModelTests.swift`, `BackupTests.swift`

**Interfaces:**

```swift
public enum HabitSource: String, Sendable, Codable, CaseIterable {
    case manual, water, workout, steps, daylight, eveningClosed, journal, bibleStudy
    /// "Bewegung": a workout was recorded or the step goal was reached.
    case movement
}
// HabitRules.isSourceFulfilled: .movement → workout fulfilled || steps fulfilled
// HabitText
// sourceTitle(.movement) = "Bewegung", subtitle in the sheet "Training erfasst oder Schrittziel erreicht"
// sourceDetail(.movement): "Laufen 42 min" when a workout counted, else "10.412 von 8.000 Schritten"
// HabitsModel
/// Once: a habit with source `.workout` whose name is the suggestion "Bewegung" (German or English) becomes `.movement`.
func migrateMovementSourceIfNeeded()
```

Regeln: `.movement` ist eine eigene Quelle und darf neben je einer Gewohnheit mit „Training erfasst“ und „Schrittziel erreicht“ bestehen (`takenSources` bleibt je Fall). Der Vorschlag „Bewegung“ nutzt `.movement`. Ohne Zugriff auf Schritte zählt nur das Training. Ein unbekannter Rohwert (ältere App liest neuere Sicherung) fällt wie bisher auf „von Hand“. Die einmalige Umstellung ist Teil 1, offene Frage 8; lehnt der Nutzer sie ab, entfällt `migrateMovementSourceIfNeeded` ersatzlos.

- [ ] **Step 1: Tests.** `movement_fulfilledByWorkout`, `movement_fulfilledBySteps`, `movement_neitherIsOpen`, `movement_withoutStepGoal_usesWorkoutOnly`, `suggestion_movementUsesCombinedSource`, `sourceDetail_movement_namesWhatCounted`, `takenSources_movementDoesNotBlockWorkout`, `migration_renamedHabit_staysWorkout`, `migration_runsOnce`, `backup_roundTripsMovementSource`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: fulfil the habit "Bewegung" by a workout or the step goal`.

### Task GW2: Vier Zustände der Zeile mit Blitz-Marke und Fortschritt (GW3b, GW2a)

**Files:**
- Create: `Routines/HabitMarkerTint.swift`, Farbset `HabitAutomaticMarker` in `Assets.xcassets`
- Modify: `Routines/HabitsModel.swift:22–28, 125–163` (`Row`), `Routines/HabitsSection.swift:44–102`, `Routines/HabitText.swift`, Kataloge
- Test: `HabitsModelTests.swift`, `HabitTextTests.swift`

**Interfaces:**

```swift
// HabitsModel.Row
enum State: Equatable {
    case manualOpen                 // (1) by hand, open
    case automaticDone              // (2) fulfilled by the source; cannot be unchecked
    case automaticPending(progress: Double?)   // (3) source not fulfilled yet; nil for sources without a measure
    case manualDoneSourcePending    // (4) checked by hand while the source is still open
    case manualDone                 // by hand, done
}
let state: State
// HabitText
/// (2) "Automatisch erfüllt · 2,1 l von 2,0 l"   (3) "5.600 von 8.000 Schritten · hakt sich selbst ab"
/// (4) "Von Hand abgehakt · Tagebuch noch offen"  (1), manualDone: nil
static func stateLine(_ row: HabitsModel.Row, …) -> String?
/// Share of the goal for water and steps (0…1); nil for workout, closed evening, journal, Bible Study, movement without steps.
static func sourceProgress(_ habit: Habit, on day: PlanDay, facts: HabitFacts) -> Double?
```

Darstellung: Der grüne Haken bleibt das eine Zeichen für „erfüllt“. Zustand 2: Haken mit kleiner Blitz-Marke (`bolt.fill`) an der Ecke in `HabitAutomaticMarker`. Zustand 3: Fortschrittsring statt des leeren Kreises (ohne Maß ein leerer Kreis mit Blitz-Marke); ein Tipp hakt von Hand ab. Zustand 4: normaler Haken, abwählbar. Die Blitz-Marke im Text der Zustände 3 und 4 ist ein `Image`, die Zeile ersetzt die bisherige Zeile „automatisch · …“. Symbole der Gewohnheiten bleiben grau neben dem Namen (GW2a). VoiceOver nennt den Zustand in Worten („automatisch erfüllt“, „hakt sich selbst ab“).

- [ ] **Step 1: Tests.** `row_states_coverAllFour`, `sourceProgress_waterAndSteps`, `sourceProgress_binarySources_nil`, `stateLine_perState`, `accessibilityValue_namesState`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: distinguish automatic and manual habit checks with a marker and progress`.

### Task GW3: Hinweis beim Tipp, Fußtext, Namen der Symbole (GW4b, Fußtext, GW2)

**Files:**
- Modify: `Routines/HabitsSection.swift`, `Routines/HabitSheet.swift:28–80`, `Routines/HabitText.swift`, Kataloge
- Test: `HabitTextTests.swift`, UI-Test der Gewohnheiten

Regeln: Tipp auf Zustand 2 zeigt für drei Sekunden unter der Liste „Automatisch erfüllt durch das Wasserziel. Lässt sich nicht abwählen.“ (Quelle eingesetzt, über `HabitText.sourceTitle`) mit Haptik `.warning` und VoiceOver-Ansage; der Zustand ändert sich nicht. Fußtext unter „Erfüllt durch“: „Automatische Quellen haken sich selbst ab, auch an Tagen ohne App-Start. Bis dahin kannst du von Hand abhaken; ein automatisch gesetzter Haken lässt sich nicht abwählen. Jede Quelle gilt für höchstens eine Gewohnheit.“ Die 22 Symbole in `HabitText.symbols` bekommen deutsche und englische VoiceOver-Namen (`HabitText.symbolName(_:)`, zum Beispiel „Gehen“ für `figure.walk`).

- [ ] **Step 1: Tests.** `automaticHint_namesSource`, `symbolName_coversEverySymbol` (kein Symbol ohne Namen), `footer_matchesDecision`. UI: `testTapOnAutomaticHabitShowsHintAndKeepsCheck`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: explain automatic habit checks on tap and name the habit symbols`.

---

## Strang DS: Datensicherung

### Task DS0: entfällt (DS7c ohne iCloud-Container, Entscheidung vom 21.11.2026)

Der Nutzer hat DS7c so festgelegt: Die Sicherheitskopien liegen **verborgen im selbst gewählten Sicherungsordner** (zum Beispiel in iCloud Drive), in einem Unterordner `.Sicherheitskopien`. Dateien-App und Finder blenden Ordner mit führendem Punkt aus. Dafür braucht es **keine** iCloud-Berechtigung und keinen eigenen Container; der Zugriff läuft über das vorhandene Security-Scoped Bookmark des Sicherungsordners (`BackupSettingsView`/`BackupService`). Ist kein Sicherungsordner gewählt oder ist er nicht erreichbar, bleibt alles wie heute (`Dokumente/Sicherungen`, sichtbar, ohne Löschregel). Ein Machbarkeitstest entfällt; DS4 wird immer gebaut.

### Task DS1: Seite mit Statuskarte, Unterseite „Was wird gesichert?“ (DS1b)

**Files:**
- Create: `TagwerkCore/BackupStatus.swift`, `Backup/BackupCoverageView.swift`
- Modify: `Backup/BackupSettingsView.swift` (Neuaufbau), `Backup/BackupService.swift` (Zahl und Größe der Dateien im Ordner), Kataloge
- Test: neu `TagwerkCoreTests/BackupStatusTests.swift`, `app/TagwerkTests/BackupTests.swift`, Audit-UI-Test der Seite

**Interfaces (Produces):**

```swift
// TagwerkCore/BackupStatus.swift
public enum BackupStatus: Sendable, Equatable {
    case backedUp(at: Date)
    /// Never backed up automatically, or the last backup is older than two intervals.
    case overdue(since: Date?, days: Int)
    case folderMissing
    case failed(message: String)
    case off
    public static func status(autoEnabled: Bool, hasFolder: Bool, lastBackup: Date?, lastError: String?, now: Date) -> BackupStatus
    public var isWarning: Bool { get }
}
// BackupService
/// Own backup files in the chosen folder: count and total size; nil when the folder cannot be read.
func folderSummary() -> (count: Int, bytes: Int)?
```

Aufbau (Mockup DS1b): Statuskarte („Gesichert · Heute, 07:12“, „Automatisch nach iCloud Drive › Tagwerk · 7 Sicherungen · 41 MB · mit Tagebuch und Bible Study · verschlüsselt“; im Warnzustand orange mit Symbol und Text, zum Beispiel „Nicht gesichert seit 3 Tagen · Ordner nicht erreichbar“); „Jetzt sichern“, „Wiederherstellen …“; Abschnitt „Automatisch“ (Schalter mit „Täglich beim Verlassen der App, die letzten 7 bleiben“, Zeile „Sicherungsordner“); Abschnitt „Inhalt“ (Schalter „Tagebuch und Bible Study einschließen“, Zeile „Mit Passwort verschlüsseln“ (DS3), Zeile „Gesperrte Notizen“ (NS3, falls auf `main`), Zeile „Was wird gesichert?“); Abschnitt „Vor dem Wiederherstellen“ mit „Sicherheitskopien“ nur bei gebautem DS4, sonst der heutige Hinweis auf den Ordner „Sicherungen“. Der Ordnername wird nur angezeigt; ob er in iCloud Drive liegt, behauptet die Karte nicht („nach „Tagwerk““ statt „nach iCloud Drive“, wenn es sich nicht feststellen lässt). `BackupCoverageView`: drei Listen „Gesichert“, „Nicht gesichert“ (Chatverlauf mit dem Assistenten, Zwischenspeicher), „An dieses Gerät gebunden“ (Anmeldung bei ChatGPT und GitHub, Einstellungen der Sperre, Passwort der Sicherung). Einmaliger Hinweis beim Einschalten der automatischen Sicherung ohne Passwort: „Die Sicherung enthält dein Tagebuch unverschlüsselt. Passwort festlegen?“ („Passwort festlegen“, „Ohne Passwort sichern“).

- [ ] **Step 1: Tests.** `status_off`, `status_backedUpToday`, `status_overdueAfterTwoDays`, `status_neverBackedUp`, `status_folderMissing`, `status_errorWins`, `folderSummary_countsOnlyOwnFiles`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: open the backup page with a status card and explain what is backed up`.

### Task DS2: Wiederherstellen mit Vergleichsblatt (DS4b)

**Files:**
- Create: `Backup/RestoreComparisonSheet.swift`
- Modify: `Backup/BackupService.swift` (`Inspection`, Zähler des Geräts), `Backup/BackupSettingsView.swift`, Kataloge
- Test: `BackupTests.swift`

**Interfaces:**

```swift
// BackupService
struct Counts: Equatable { var tasks: Int; var notes: Int; var habits: Int; var meals: Int; var privateNotes: Int }
/// What is on this device right now, counted like `Inspection` counts a file.
func currentCounts() -> Counts
extension Inspection { var counts: Counts { get } }
```

Blatt: Titel „Wiederherstellen“, „Sicherung vom …“, Tabelle „Dieses iPhone | Sicherung“ für Aufgaben, Notizen, Gewohnheiten, Mahlzeiten und „Tagebuch, Bible Study“ (enthält die Datei keine privaten Notizen: „bleibt erhalten“); Hinweis „Alles auf diesem iPhone wird ersetzt. Was seit dem … dazugekommen ist, steht danach nur noch in der Sicherheitskopie, die Tagwerk jetzt anlegt.“; Knopf „Daten ersetzen“ (destruktiv); Fußtext „Nicht betroffen: Chatverlauf, Anmeldung bei ChatGPT und GitHub.“ Es bleibt beim Ersetzen; Zusammenführen wird nicht gebaut. Der Ablauf danach (Sicherheitskopie, `restore`, `reloadAfterRestore`) bleibt unverändert.

- [ ] **Step 1: Tests.** `currentCounts_matchInspectionOfOwnBackup`, `counts_privateNotesOnlyWithSwitch`, `comparison_fileWithoutPrivate_saysKept`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: compare this iPhone with the backup before restoring`.

### Task DS3: Optionale Verschlüsselung mit Passwort (DS6b)

**Files:**
- Create: `TagwerkCore/BackupCrypto.swift`, `Backup/BackupKeyStore.swift`, `Backup/BackupEncryptionView.swift`
- Modify: `TagwerkCore/BackupRules.swift` (Dateinamen, Muster, Erkennung), `Backup/BackupService.swift` (Schreiben, Lesen, Sicherheitskopie), `Backup/BackupDocument.swift`, `Backup/BackupSettingsView.swift` (Dateiwahl, Passwortabfrage), `Persistence/AppSettings.swift` (`backupEncryptionEnabled: Bool = false`, `backupPlainHintShown: Bool = false`; **nicht** in `AppSettingsBackup`), `project.yml` (exportierter Dateityp `de.tagwerk.backup`, Endung `tagwerk`), Kataloge
- Test: neu `TagwerkCoreTests/BackupCryptoTests.swift`, `BackupRulesTests.swift`, `app/TagwerkTests/BackupTests.swift`, neu `BackupKeyStoreTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/BackupCrypto.swift
public enum BackupCrypto {
    public static let format = "tagwerk-backup-encrypted"
    public static let version = 1
    public static let iterations = 600_000          // PBKDF2-HMAC-SHA256
    public static let minimumPasswordLength = 8
    public struct KeyMaterial: Sendable, Equatable { public let key: Data; public let salt: Data; public let iterations: Int }
    public enum CryptoError: Error, Equatable { case wrongPassword, damaged, unsupportedVersion(Int), passwordTooShort }
    /// Derives a 256-bit key from the password with a fresh random salt.
    public static func deriveKey(password: String) throws -> KeyMaterial
    public static func deriveKey(password: String, salt: Data, iterations: Int) -> Data
    /// AES-256-GCM with a random nonce. The file is a small JSON header (format, version, salt, iterations, nonce)
    /// followed by the ciphertext; the header is authenticated.
    public static func encrypt(_ plain: Data, with material: KeyMaterial) throws -> Data
    /// Salt and iterations of a file, to derive the key from a typed password; nil for a file that is not encrypted.
    public static func header(of file: Data) -> (salt: Data, iterations: Int)?
    public static func decrypt(_ file: Data, key: Data) throws -> Data
    public static func isEncrypted(_ file: Data) -> Bool
}
// TagwerkCore/BackupRules.swift
public static let encryptedFileExtension = "tagwerk"
public static func fileName(for date: Date, calendar: Calendar, encrypted: Bool) -> String
// isOwnFile, filesToDelete: both extensions; the newest seven across both stay.

// Backup/BackupKeyStore.swift (SecureStore, account "backup.key"; after first unlock, this device only)
struct BackupKeyStore {
    func material() -> BackupCrypto.KeyMaterial?
    func save(_ material: BackupCrypto.KeyMaterial) throws
    func remove() throws
}
// BackupService
enum BackupError { …; case passwordRequired; case wrongPassword; case keyMissing }
/// JSON or, with encryption on, the encrypted file.
func makeBackupFile(includePrivate: Bool? = nil) throws -> (data: Data, fileName: String)
/// Decrypts with the key of this device when the salt matches, else with `password`; throws `.passwordRequired`
/// when neither is available.
func inspectFile(_ data: Data, password: String? = nil) throws -> Inspection
```

Regeln:
- **Schlüssel:** Beim Festlegen des Passworts wird einmal ein Schlüssel abgeleitet und mit Salz und Iterationszahl im Schlüsselbund dieses Geräts abgelegt (nicht das Passwort). Automatische Sicherungen und Sicherheitskopien nutzen ihn; jede Datei trägt Salz und Iterationszahl im Kopf und einen eigenen Nonce. Auf einem neuen iPhone fragt das Wiederherstellen nach dem Passwort.
- **Kein Zurücksetzen:** Tagwerk kennt das Passwort nicht. Fehlt der Schlüssel im Schlüsselbund (`keyMissing`, zum Beispiel nach dem Übertragen auf ein anderes Gerät), schreibt die automatische Sicherung nichts Unverschlüsseltes, sondern meldet in der Statuskarte „Passwort erneut eingeben“.
- **Passwort ändern:** leitet einen neuen Schlüssel mit neuem Salz ab; ältere Dateien behalten ihr altes Passwort. Das steht auf der Seite.
- **Ausschalten:** entfernt den Schlüssel nach Rückfrage; künftige Sicherungen sind unverschlüsselt, vorhandene Dateien bleiben, wie sie sind.
- **Lesen:** Unverschlüsselte JSON-Sicherungen (Versionen 1 und 2) bleiben lesbar. Mit falschem Passwort wird nichts entschlüsselt, nichts ersetzt und keine Sicherheitskopie angelegt.
- **Seite „Verschlüsselung“ (Pflicht aus der Entscheidung):** Oben ein deutlich abgesetzter Warnkasten mit Symbol `exclamationmark.triangle.fill`: „Ohne Passwort lässt sich eine verschlüsselte Sicherung nicht öffnen. Tagwerk kann es nicht zurücksetzen. Vergisst du es, ist die Sicherung unbrauchbar.“ Darunter Schalter „Mit Passwort verschlüsseln“, „Passwort ändern“, Fußtext „Gilt für „Jetzt sichern“, die automatische Sicherung und Sicherheitskopien. Der Schlüssel liegt im Schlüsselbund dieses iPhones, damit automatisch gesichert werden kann. Auf einem neuen iPhone wirst du beim Wiederherstellen nach dem Passwort gefragt.“ Beim Einschalten: Passwort zweimal eingeben (mindestens 8 Zeichen), dann eine Rückfrage, die den Warnsatz wiederholt und mit „Verstanden, verschlüsseln“ bestätigt wird. Kein Passwort in Logs oder Fehlermeldungen; die Felder sind `SecureField` mit `textContentType(.newPassword)`.
- `BackupRules.schemaVersion` bleibt 2 für den Inhalt; der verschlüsselte Umschlag hat seine eigene `version`.

- [ ] **Step 1: Tests.** `BackupCryptoTests`: `roundTrip_encryptDecrypt`, `decrypt_wrongKey_throwsWrongPassword`, `decrypt_tamperedCiphertext_throws`, `decrypt_tamperedHeader_throws`, `encrypt_twice_differs` (Nonce), `deriveKey_sameSalt_sameKey`, `deriveKey_shortPassword_throws`, `header_ofPlainJSON_isNil`, `unsupportedVersion_throws`. `BackupRulesTests`: `fileName_encryptedExtension`, `isOwnFile_bothExtensions`, `filesToDelete_keepsNewestSevenAcrossBoth`, `isOwnFile_safetyCopyNeverMatches`. `BackupKeyStoreTests`: `saveAndRead`, `remove`. `BackupTests`: `encryptedBackup_restoresWithDeviceKey`, `encryptedBackup_onOtherDevice_needsPassword`, `wrongPassword_changesNothing`, `plainBackup_stillRestores`, `autoBackup_withoutKey_writesNothingAndReports`, `safetyCopy_isEncryptedWhenEnabled`, `settingsBackup_doesNotCarryEncryptionSwitch`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`. Die Laufzeit der Schlüsselableitung auf dem Gerät messen (Ziel unter einer Sekunde; sonst Iterationszahl im Pull Request begründet senken, nicht unter 310.000).
- [ ] **Step 5:** Commit `feat: encrypt backups with an optional password`.

### Task DS4: Sicherheitskopien verborgen im Sicherungsordner, begrenzt, mit Liste in der App (DS7c)

**Files:**
- Create: `Backup/SafetyCopyStore.swift`, `Backup/SafetyCopiesView.swift`
- Modify: `Backup/BackupService.swift:135–149` (keine Änderung an Entitlements oder `project.yml`), `Backup/BackupSettingsView.swift`, `TagwerkCore/BackupRules.swift`, Kataloge
- Test: neu `app/TagwerkTests/SafetyCopyStoreTests.swift`, `BackupRulesTests.swift`

**Interfaces:**

```swift
// TagwerkCore/BackupRules.swift
public static let keptSafetyCopies = 3
public static let safetyCopyRetentionDays = 30
/// Safety copies to delete: everything beyond the newest three and everything older than 30 days.
public static func safetyCopiesToDelete(names: [String], now: Date, calendar: Calendar) -> [String]

// Backup/SafetyCopyStore.swift
struct SafetyCopy: Identifiable, Equatable { let id: String; let createdAt: Date; let bytes: Int; let daysLeft: Int; let isInBackupFolder: Bool }
@MainActor final class SafetyCopyStore {
    /// `hiddenDirectory` is `<backup folder>/.Sicherheitskopien`, resolved from the backup folder bookmark;
    /// nil without a reachable backup folder, then copies keep today's behaviour in `localDirectory`.
    init(localDirectory: URL, hiddenDirectory: URL?, now: @escaping () -> Date, calendar: Calendar)
    func write(_ data: Data) throws -> SafetyCopy
    func list() -> [SafetyCopy]
    func data(of copy: SafetyCopy) throws -> Data
    func delete(_ copy: SafetyCopy)
    func prune()
    /// Moves copies from the old visible folder "Dokumente/Sicherungen" once and removes the folder when it is empty.
    func adoptLegacyCopies(from directory: URL)
}
```

Regeln: Ablage im verborgenen Unterordner `.Sicherheitskopien` des gewählten Sicherungsordners; ohne erreichbaren Sicherungsordner wie heute in `Dokumente/Sicherungen`. Vorhandene Kopien aus `Dokumente/Sicherungen` werden einmal übernommen, sobald ein Sicherungsordner erreichbar ist; die letzten 3 bleiben, höchstens 30 Tage. Die Liste zeigt Datum, Größe, „noch N Tage“ und je Kopie „Diesen Stand zurückholen“ (führt über das Vergleichsblatt aus DS2), „Als Datei sichern“ (Teilen), „Löschen“. Sie enthalten immer auch Tagebuch und Bible Study und sind mit DS3 verschlüsselt. Ohne erreichbaren Sicherungsordner sagt die Seite: „Kein Sicherungsordner gewählt. Die Kopien liegen nur auf diesem iPhone.“ Die Meldungen nach dem Wiederherstellen nennen statt des Ordners „Sicherungen“ die Liste in der App.

- [ ] **Step 1: Tests.** `safetyCopiesToDelete_keepsNewestThree`, `safetyCopiesToDelete_dropsOlderThanThirtyDays`, `write_storesLocallyAndInCloudDirectory` (mit zwei Temp-Ordnern), `write_withoutCloud_storesLocallyOnly`, `list_mergesBothPlacesWithoutDuplicates`, `prune_removesFromBoth`, `adoptLegacyCopies_movesAndCleansUp`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`; danach Gerätetest (Z1). Commit `feat: keep safety copies hidden, limited and in iCloud`.

---

## Strang EK: Einkaufsliste und Rezept

**Voraussetzung für EK2 und EK3:** G3 Strang L gemergt (`RecipeSheets.swift`, zweiter Name je Zutat).

### Task EK1: Sammelaktionen in drei Gruppen, Zahl im Eintrag, Wortlaut der Rückfragen (EK1b, EK2a)

**Files:**
- Modify: `Shopping/ShoppingListView.swift:89–104, 273–316`, Kataloge
- Test: UI-Test der Einkaufsliste, bestehende Texttests

Menü: Gruppe 1 „Rezept hinzufügen …“; Gruppe 2 „Mit ChatGPT sortieren“, „Kategorien verwalten“; Gruppe 3 „Erledigte entfernen (5)“ (`checkmark.circle`, nicht rot, ohne erledigte Artikel ausgegraut) und „Liste leeren (17) …“ (rot). Rückfragen bleiben bei beiden: „5 erledigte Artikel entfernen?“ mit „Sie verschwinden auch aus Apple Erinnerungen.“ und dem Knopf „Entfernen“; „Gesamte Liste leeren? 17 Artikel werden gelöscht.“ mit „Liste leeren“.

- [ ] **Step 1:** Tests `removeCompletedTitle_carriesCount`, `clearListTitle_carriesCount`, UI `testRemoveCompletedDisabledWithoutCompletedItems`. **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: group the bulk actions of the shopping list and show their counts`.

### Task EK2: Rezept-Eingabe: Quelle zuerst, Zweck als zwei Knöpfe (EK3b)

**Files:**
- Modify: `Shopping/RecipeSheets.swift:163–340, 420–500`, Kataloge
- Test: `RecipeNoteFlowTests.swift`, `RecipeSaveOnlyTests.swift`, UI-Test

Regeln: Der Abschnitt „Was soll mit dem Rezept geschehen?“ entfällt. Unter der Quelle (Text, Foto, Link, Notiz) stehen zwei Knöpfe: „Zutaten auf die Einkaufsliste“ (hervorgehoben) und „Nur als Rezept speichern“, darunter „Beides legt auf Wunsch eine Notiz im Ordner „Rezepte“ an.“ Beide sind ausgegraut, solange keine Eingabe da ist; der Knopftext wechselt nicht mehr. Der Linktext lautet „Tagwerk lädt die Seite erst beim Tippen auf einen der Knöpfe und sendet nur den gelesenen Text, nicht die Adresse.“ Ist die Quelle schon gesetzt (Teilen-Erweiterung, Rezept-Notiz), bleiben nur die zwei Knöpfe sichtbar unter einer Zeile, die die Quelle nennt. `RecipePurpose` bleibt als Wert für den weiteren Ablauf. Die Einwilligung und der lokale Leseweg strukturierter Rezept-Notizen bleiben unverändert.

- [ ] **Step 1:** Tests `purpose_isChosenByButton`, `buttons_disabledWithoutInput`, `presetSource_showsOnlyButtons`, bestehende Tests zum lokalen Lesen bleiben grün. **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: enter the recipe first and choose its purpose with the last tap`.

### Task EK3: Ergebnisliste mit Abschnitt „Schon auf der Liste“ und antippbarer Menge (EK4b)

**Files:**
- Create: `TagwerkCore/ShoppingQuantity.swift`
- Modify: `Shopping/RecipeSheets.swift:503–685`, `Shopping/ShoppingModel.swift` (Menge eines vorhandenen Artikels erhöhen), Kataloge
- Test: neu `TagwerkCoreTests/ShoppingQuantityTests.swift`, `RecipeServingsTests.swift`, `RecipeImporterTests.swift`

**Interfaces:**

```swift
// TagwerkCore/ShoppingQuantity.swift
public enum ShoppingQuantity {
    /// The sum of two quantities when both are plain numbers or carry the same unit ("2" + "1" → "3",
    /// "200 g" + "125 g" → "325 g"); nil when they cannot be added ("1 Prise" + "2").
    public static func sum(_ existing: String?, _ added: String?, locale: Locale) -> String?
}
```

Regeln: Portionen in einer Zeile „4 im Rezept → 2“ mit einem Stepper für „Ich koche für“; „im Rezept“ wird nur editierbar, wenn das Rezept keine Zahl nennt. Abschnitt „Neu · N“ (vorgewählt) und „Schon auf der Liste · N“ (abgewählt). Unterzeile eines vorhandenen Artikels: „auf der Liste: 2 · anhaken erhöht auf 3“, wenn `ShoppingQuantity.sum` etwas liefert, sonst „auf der Liste: 1 Prise · anhaken legt einen zweiten Eintrag an“. Die Menge rechts ist ein Knopf (44 pt), der ein kleines Feld zum Ändern öffnet. Der Hauptknopf zählt nur die gewählten Zeilen („3 Artikel hinzufügen“). Mit G3 L4 gilt die Dubletten-Erkennung über den Namen, der auf die Liste geht.

- [ ] **Step 1:** Tests `sum_plainNumbers`, `sum_sameUnit`, `sum_differentUnits_isNil`, `sum_decimalCommaLocale`, `sum_missingExisting`, `result_existingItemsStartDeselected` (bleibt), `apply_checkedExistingItem_raisesQuantity`, `apply_checkedExistingItem_withoutSum_addsSecondEntry`, `buttonTitle_countsSelected`. **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: separate ingredients that are already on the list and let quantities be edited`.

---

## Strang TB: Notion-Import

### Task TB1: Import in drei Schritten, Einstieg im leeren Ordner (TB4b)

**Files:**
- Modify: `Notes/NotionImportView.swift`, `Notes/NotionImportModel.swift:44–127`, `Notes/NotesListView.swift` (Zeile „Aus Notion importieren“ im leeren Ordner „Tagebuch mit Gott“ bzw. „Bible Study“), `Settings/NotesSettingsView.swift`, Kataloge
- Test: `app/TagwerkTests/` (Import-Modell), UI-Test

**Interfaces:**

```swift
// NotionImportModel
/// The target is fixed when the import was opened from a folder; the segment is then not shown.
init(store: NoteStore, fixedTarget: NotionImportTarget? = nil)
enum Step: Int { case instructions = 1, preview, result }
var step: Step { get }
```

Aufbau: ein Blatt mit „Schließen“. Schritt 1: Anleitung als drei nummerierte Punkte (in Notion mit „Markdown & CSV“ exportieren; ZIP in der Dateien-App entpacken; entpackten Ordner wählen) und „Ordner wählen“; das Segment (Tagebuch mit Gott / Bible Study) nur ohne festes Ziel. Schritt 2: Vorschau mit Zahlen (Einträge im Export, Zeitraum, Neu, „Tag hat schon einen Eintrag“ mit Pfeil (TB2), Schon importiert, Ohne erkennbares Datum mit Pfeil auf die Liste der Dateinamen), Hinweis „Nichts wird überschrieben.“, Knopf „N Einträge importieren“, „Anderen Ordner wählen“. Schritt 3: Ergebnis mit „Zum Tagebuch“ bzw. „Zu Bible Study“. Überschrift je Schritt „1 · Export wählen“, „2 · Vorschau“, „3 · Ergebnis“. Der Einstieg in den Einstellungen bleibt.

- [ ] **Step 1:** Tests `fixedTarget_hidesTargetChoice`, `step_followsPhase`, `importButtonTitle_countsNewAndAppended`; UI `testEmptyJournalFolderOffersImport`. **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: guide the Notion import in three steps and offer it in the empty folder`.

### Task TB2: Liste der Tage mit vorhandenem Eintrag (TB5a)

**Files:**
- Modify: `Notes/NotionImportModel.swift` (`Preview`), `Notes/NotionImportView.swift` (Unterseite), `TagwerkCore/NotionExportParser.swift` bzw. `NotionJournalPlan` (falls die betroffenen Tage dort noch nicht einzeln vorliegen), Kataloge
- Test: Import-Modell-Tests, `TagwerkCoreTests` (Parser)

**Interfaces:**

```swift
// NotionImportModel.Preview
struct Conflict: Equatable, Identifiable { let id: String; let day: PlanDay; let existingExcerpt: String; let importedExcerpt: String }
var conflicts: [Conflict]            // days that already have an entry, newest first
```

Unterseite „N Tage mit Eintrag“: Kopftext „An diesen Tagen wird der Text aus Notion unter deinem Eintrag angehängt.“; je Tag das Datum und „Tagwerk: „…“ · Notion: „…““ (je höchstens 40 Zeichen). Es bleibt beim Anhängen; keine Auswahl je Tag. Die Ausschnitte verlassen das Gerät nicht und stehen in keinem Log.

- [ ] **Step 1:** Tests `preview_listsConflictsNewestFirst`, `conflict_excerptsAreCut`, `conflict_onlyForDaysWithRealEntry` (reine Vorlage zählt nicht). **Step 2–4:** rot, umsetzen, `ALL`. Commit `feat: list the days whose entry gets the imported text appended`.

**Offen aus #188 (nicht Teil dieses Plans, aber vor der Auslieferung zu erledigen):** Der Notion-Import ordnet Seiten über den Titel zu; die Prüfung mit einem echten Export steht noch aus (Prüfnotiz zum Notizen-PR). Sie gehört in Z1.

---

## Task Z1: Geräteprüfung (nach allen Strängen, Hauptsitzung mit dem Nutzer)

Simulator-Geräte nach den automatischen Läufen löschen. Am iPhone des Nutzers, hell und dunkel, mit Schriftgröße „Large“ und einer Bedienungshilfen-Größe:

| Bereich | Prüfung |
|---|---|
| **NO15b (entscheidet über Stufe C)** | Die sechs Punkte aus Teil 1, Task NE3. Ergebnis als Zahl (Treffer von 20) festhalten. |
| Ordner und Liste | Abschnitte, Farben in beiden Modi, Plus-Knopf, „Namen zurücksetzen“; Datumsgruppen über einen Monatswechsel; Auswahl mit „Alle auswählen“; „Zuletzt gelöscht“ mit Frist unter 7 Tagen. Tag nur mit Dankbarkeit: erscheint, lässt sich nicht löschen, Karte öffnet den Tagesstart. |
| Sperre | Face ID, Gerätecode, Abbrechen, Hintergrund, App-Umschalter, Suche nur im Titel, gesperrte Notiz fehlt beim Assistenten (`search`, `read_note`), Wiederherstellen einer Sicherung mit gesperrter Notiz. |
| Scannen, Zeichnen, Tabellen | Die Liste aus Teil 1 (Ende Strang NX). Dokumentenkamera und Texterkennung nur am Gerät. |
| Routinen | Tagesstart in neuer Reihenfolge; Karte „Willst du etwas ändern?“ erst mit Text; „Zeit mit Gott“ mit Zustand; vier Abend-Erinnerungen, zwei zur selben Minute; Unerledigtes verschieben mit Vorschau und Ergebnisliste; Karte „Wochenplanung“ am Planungstag. |
| Bible Study | Vorschlag „nächster Vers“ über Kapitel- und Buchende; „Stelle frei eingeben“; Sitzungsleiste und Ergänzung der Überschrift; Erinnerung kommt zur gesetzten Zeit, mit und ohne Stelle; „Heute nicht“ und „Starten“; entfällt nach abgeschlossener Sitzung; nach drei Tagen ohne Öffnen der App Verhalten notieren. Stichprobe der Verszahlen an fünf Stellen gegen die gedruckte Schlachter 2000 des Nutzers, darunter ein Psalm mit Überschrift, Joel und Maleachi. |
| Gewohnheiten | Vier Zustände; „Bewegung“ durch Training und durch Schritte; Hinweis beim Tipp; VoiceOver liest Symbolnamen. |
| Datensicherung | Statuskarte in allen Zuständen; Vergleichsblatt; verschlüsselte Sicherung schreiben, App löschen, neu installieren, mit Passwort wiederherstellen; falsches Passwort; unverschlüsselte ältere Datei; automatische Sicherung im Hintergrund mit gesperrtem iPhone. Bei gebautem DS4: Kopie in iCloud nach Neuinstallation wieder da. |
| Einkauf, Import | Menü und Rückfragen; Rezept über Link, Foto, Notiz; vorhandener Artikel erhöht die Menge. Notion-Import mit einem echten Export (offener Punkt aus #188). |
| Budget | In den Diagnosen bzw. per Testausgabe: nie mehr als 64 ausstehende Mitteilungen bei vollem Bestand (44 Aufgaben, 12 Abend, Tagesstart, Wochenplanung, 3 Bible Study, Fokus). |

Befunde gehen als Kommentar in #188; aus NO15b folgt die Entscheidung für Stufe A/B oder Stufe C.
