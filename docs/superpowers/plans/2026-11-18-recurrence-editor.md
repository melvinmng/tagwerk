# Wiederholungsplan anlegen und ändern (RK3) – Umsetzungsplan

**Stand:** 18. November 2026 · **Status:** Freigegeben am 18.11.2026 (RK3, alle Vorschläge der offenen Fragen übernommen)
**Mockups:** `docs/superpowers/mockups/2026-11-18-recurrence-editor-mockups.html` (RK0 bis RK3, Empfehlung RK3 vorläufig)

## 1. Ziel und Abgrenzung

Im Aufgaben-Editor und in „Neue Aufgabe“ lässt sich eine Wiederholung anlegen, ändern und entfernen: Häufigkeit (Tag, Woche, Monat, Jahr) mit Intervall, Wochentage, Monatsoption („am Tag X“ oder „am n-ten Wochentag“), Ende (nie, bis Datum, nach Anzahl), Vorgaben, Klartext und Vorschau der nächsten Termine.

- **Stufe 1 (dieser Plan im Detail):** Erinnerungen. Die Regel wird als `EKRecurrenceRule` geschrieben.
- **Stufe 2 (nur skizziert, eigene Freigabe):** lokale Aufgaben.
- **Nicht Teil des Plans:** GitHub-Issues (kein Feld für Wiederholungen), Wiederholungen über den Assistenten, stündliche Regeln, „letzter Tag des Monats“, mehrere Regeln je Erinnerung.

Der Plan setzt die offenen Fragen aus der Mockup-Datei als entschieden im Sinne der dortigen Vorschläge voraus. Abweichende Antworten ändern vor allem Abschnitt 5 (Fragen 2 bis 4) und den Umfang (Frage 1).

## 2. Ausgangslage (im Code nachgelesen)

| Befund | Fundstelle |
|---|---|
| Regel wird nur gelesen; `recurrence` ist als „read-only“ dokumentiert | `RemindersKit/ReminderRecord.swift:15–16` |
| `save` und `create` schreiben keine Regel | `RemindersKit/EventKitGateway.swift:104–121`, `:128–144` |
| Lesen: nur die erste Regel, nur mit Fälligkeitsdatum; jährlich und „n-ter Wochentag“ werden `.unsupported` | `RemindersKit/EventKitGateway.swift:182–199` |
| Kernmodell: `daily`, `weekly`, `monthly(day)`, `unsupported` | `TagwerkCore/Recurrence.swift:4–10` |
| `TaskItem`, `TaskField`, `TaskDraft`, `TaskEdit` ohne Wiederholung | `TagwerkCore/TaskItem.swift:42–44`, `:47`, `:94`; `TagwerkCore/TaskEdit.swift:15–24` |
| Serien sind im Planungsmodell fest an die Quelle „reminders“ gebunden | `Tagwerk/Planning/PlanningModel.swift:516`, `:523`, `:850` |
| Lokale Aufgaben ohne Feld; neue Attribute müssen optional sein | `Tagwerk/Persistence/LocalTask.swift:6–24` |
| Editor zeigt für Serien nur das Aufwandsfeld | `Tagwerk/Editor/TaskEditorView.swift:93–97` |
| `RecurrenceRule` wird nirgends dauerhaft gespeichert (Suche in `Tagwerk/Persistence/`) | – |

## 3. Stufe 0: Verhalten von EventKit am Gerät klären (vor dem Bau)

Diese Punkte sind ungeprüft und entscheiden über Details der Abbildung. Ergebnis jeweils im Plan nachtragen.

1. Lässt sich eine `EKRecurrenceRule` ohne Zugriff auf den Store erzeugen und auslesen (Voraussetzung für reine Unit-Tests der Abbildung)?
2. Welche Schreibweise erzeugt die Erinnerungen-App für „am 3. Mittwoch“ (Wochentag mit Wochennummer oder Wochentag mit `setPositions`), und zeigt sie eine von Tagwerk geschriebene Regel korrekt an?
3. Ende „nach Anzahl“: Zeigt die Erinnerungen-App es an, und sinkt `occurrenceCount` beim Abhaken oder bleibt es stehen?
4. Monatlich am 31.: Welche Termine erzeugt EventKit in kürzeren Monaten?
5. Was macht EventKit, wenn das Fälligkeitsdatum nicht auf einen Wochentag der Regel fällt?
6. Enddatum: Welche Uhrzeit und Zeitzone muss geschrieben werden, damit beim Lesen derselbe Kalendertag entsteht?
7. Kann eine Erinnerung mehr als eine Regel tragen?

## 4. Betroffene Dateien (Stufe 1)

**TagwerkCore** (`app/Packages/TagwerkCore/Sources/TagwerkCore/`)
- `Recurrence.swift`: neue Fälle, `nextOccurrence`, Prüfung der Werte.
- `RecurrenceText.swift` (neu): Klartext der Regel.
- `RecurrencePreset.swift` (neu): Vorgaben und ihr Abgleich mit einer Regel.
- `TaskItem.swift`, `TaskEdit.swift`: Feld `recurrence`.
- `AIPlanning.swift:1051`: `sessionWindowStart` für die neuen Fälle.
- `Resources/Localizable.xcstrings`: deutsche und englische Texte.

**RemindersKit** (`app/Packages/RemindersKit/Sources/RemindersKit/`)
- `RecurrenceMapping.swift` (neu): Abbildung in beide Richtungen, ohne Store.
- `EventKitGateway.swift`: `save`, `create`, `recurrence(_:)` nutzen die Abbildung.
- `ReminderStore.swift`, `ReminderRecord.swift`, `ReminderMapping.swift`, `RemindersTaskProvider.swift`.

**App** (`app/Tagwerk/`)
- `Editor/RecurrenceEditorModel.swift`, `Editor/RecurrenceEditorView.swift` (neu).
- `Editor/TaskEditorView.swift`, `Editor/TaskEditorModel.swift`, `Editor/ConflictChange.swift`.
- `Tasks/NewTaskSheet.swift`.
- `Planning/PlanningModel.swift`: Hilfsfunktion für betroffene Blöcke.
- `App/DemoData.swift`: je ein Beispiel für die neuen Regeln.

**Tests:** `TagwerkCoreTests/RecurrenceTests.swift`, `RecurrenceTextTests.swift` (neu), `RecurrencePresetTests.swift` (neu), `TaskEditTests.swift`, `AIPlanningTests.swift`; `RemindersKitTests/RecurrenceMappingTests.swift` (neu), `ReminderMappingTests.swift`, `RemindersTaskProviderTests.swift`, `FakeReminderStore.swift`; `TagwerkTests/RecurrenceEditorModelTests.swift` (neu), `TaskEditorModelTests.swift`, `EstimateAndConflictTests.swift`, `PlanningModelTests.swift`, `Fakes/FakeAccessStore.swift`.

## 5. Änderungen am Kernmodell

```swift
public enum RecurrenceRule: Sendable, Hashable, Codable {
    case daily(interval: Int)
    case weekly(interval: Int, weekdays: Set<Int>)
    case monthly(interval: Int, day: Int)
    /// Ordinal 1...4 within the month; weekday 1 = Sunday … 7 = Saturday.
    case monthlyWeekday(interval: Int, ordinal: Int, weekday: Int)
    /// Month and day come from the start of the series.
    case yearly(interval: Int)
    case unsupported
}
```

- Bestehende Fälle bleiben unverändert, damit vorhandene Tests und Aufrufer gültig bleiben. Jeder `switch` über die Regel wird durch den Compiler gefunden (`Recurrence.swift:50`, `AIPlanning.swift:1052`).
- `matches`: `monthlyWeekday` trifft, wenn Wochentag stimmt und `(day.day - 1) / 7 + 1 == ordinal`; `yearly` trifft bei gleichem Monat und Tag wie `start` und passendem Jahresabstand. Der 29. Februar entfällt in Nicht-Schaltjahren (wie `monthly` am 31.).
- `sessionWindowStart`: `monthlyWeekday` wie `monthly`; `yearly` ab dem Tag nach demselben Datum des Vorjahres (bzw. vor `interval` Jahren).
- `nextOccurrence(of:onOrAfter:calendar:) -> PlanDay?`: erster Termin ab einem Tag; Grundlage für Vorschau, Vorschlag des Fälligkeitsdatums und (Stufe 2) das Weiterrücken.
- `Recurrence.isValid`: Intervall ≥ 1, Wochentage in 1...7, Tag in 1...31, Ordinal in 1...4, Anzahl ≥ 1, Ende nicht vor Start, nicht Ende und Anzahl zugleich.
- `RecurrenceText.summary(_:locale:calendar:)`: Sätze laut Tabelle in der Mockup-Datei („Alle 2 Wochen am Mo und Do“, „Jeden Werktag (Mo bis Fr)“, „…, bis 31. März 2027“, „…, 12 Mal“). Wochentage in der Reihenfolge der Woche des Kalenders.
- `RecurrencePreset`: `daily`, `weekdays`, `weekend`, `weekly`, `biweekly`, `monthly`, `yearly`; `rule(for:start:)` und `preset(matching:start:)`.
- `TaskItem.recurrence: Recurrence?` (Standard `nil`), `TaskField.recurrence`, `TaskDraft.recurrence`, `TaskEdit.recurrence: FieldChange<Recurrence?>`. `TaskEdit.diff` vergleicht Regel, Ende und Anzahl, nicht `start` (der Start folgt dem Fälligkeitsdatum); `isEmpty` berücksichtigt das Feld.

## 6. Abbildung auf `EKRecurrenceRule`

| Tagwerk | Schreiben | Lesen |
|---|---|---|
| `daily(n)` | Häufigkeit täglich, Intervall n | täglich ohne Wochentage (wie heute) |
| `weekly(n, Tage)` | wöchentlich, `daysOfTheWeek` aus den Tagen (leer: keine Angabe) | wöchentlich ohne `setPositions` (wie heute) |
| `monthly(n, Tag)` | monatlich, `daysOfTheMonth = [Tag]` | monatlich, höchstens ein Tag, keine Wochentage (wie heute) |
| `monthlyWeekday(n, k, Wochentag)` | monatlich, ein Wochentag mit Wochennummer k (Schreibweise nach Stufe 0, Punkt 2) | beide Schreibweisen: Wochennummer k oder ein Wochentag mit `setPositions = [k]`; k außerhalb 1...4 bleibt `.unsupported` |
| `yearly(n)` | jährlich, Intervall n, ohne weitere Angaben | jährlich ohne Wochentage, Wochen, Tage des Jahres, Positionen; `monthsOfTheYear` leer oder gleich dem Monat der Fälligkeit |
| Ende „bis Datum“ | `EKRecurrenceEnd` mit Datum (Uhrzeit nach Stufe 0, Punkt 6) | Kalendertag in der Zeitzone des Geräts (wie heute, `:196`) |
| Ende „nach Anzahl“ | `EKRecurrenceEnd` mit Anzahl | Anzahl > 0 (wie heute, `:197`) |
| `unsupported` | wird nie geschrieben | alles andere |

Regeln für den Schreibweg:

1. **Nur bei Änderung schreiben.** `ReminderStore.save(_:recurrence:)` erhält ein `FieldChange<Recurrence?>`; `.unchanged` fasst die Regeln der Erinnerung nicht an. Ein Vergleich über den `ReminderRecord` genügt nicht, weil `Recurrence.start` dem Fälligkeitsdatum folgt und eine nicht darstellbare Regel sonst beim Verschieben der Fälligkeit überschrieben würde.
2. **Ersetzen:** vorhandene Regeln entfernen, eine neue setzen; `.set(nil)` entfernt alle.
3. **Fälligkeitsdatum:** Eine Regel ohne Fälligkeitsdatum wird abgelehnt (`TaskWriteError.failed`); der Editor verhindert den Fall vorher. Wird „Fällig“ ausgeschaltet, setzt der Editor `recurrence` auf `.set(nil)`.
4. **Anlegen:** `create(..., recurrence:)` setzt die Regel vor dem ersten Sichern.
5. **Konflikte:** unverändert über `lastModifiedDate`; `ConflictChange` bekommt die Zeile „Wiederholung“ mit dem Klartext.
6. `ReminderMapping.taskItem` übernimmt `recurrence` und nimmt `.recurrence` in `editableFields` auf; GitHub und (in Stufe 1) lokale Aufgaben nicht.

## 7. Oberfläche (RK3)

- `RecurrenceEditorModel` (reiner Zustand, ohne SwiftUI): Häufigkeit, Intervall, Wochentage, Monatsoption, Ende; `apply(preset:)`, `selectedPreset`, `recurrence`, `summary`, `nextOccurrences(5)`, `suggestedDue`, `isUnsupportedOriginal`. Ein Wechsel der Häufigkeit behält das Intervall und leitet Wochentag bzw. Tag aus dem Fälligkeitsdatum ab; der letzte Wochentag lässt sich nicht abwählen.
- `RecurrenceEditorView`: Ziel einer `navigationDestination` im vorhandenen `NavigationStack` des Editors und von „Neue Aufgabe“. Aufbau wie im Mockup: Satz, Chips, Regler, Ende, „Nächste Termine“, Hinweise. VoiceOver: Wochentag-Kreise als Schalter mit vollem Namen, der Satz als Zusammenfassung.
- `TaskEditorView`: Zeile „Wiederholen“ unter dem Datum, sichtbar bei `isVisible(.recurrence)`; geschrieben wird mit „Sichern“. Liegen künftige Blöcke an Tagen ohne Termin der Serie, erscheint die Rückfrage; sie wird mit der bestehenden Rückfrage zum Aufwand (`:166–177`) zu einer Abfolge zusammengeführt, nicht zu zwei gleichzeitigen Dialogen.
- `NewTaskSheet`: dieselbe Zeile für „Erinnerung“; bei „GitHub-Issue“ deaktiviert mit Begründung; bei „Lokal“ in Stufe 1 ebenfalls deaktiviert („nur für Erinnerungen“). Wird eine Regel gewählt und „Fällig“ ist aus, schaltet das Formular „Fällig“ ein.
- `PlanningModel.blocksOffSeries(for:recurrence:) -> [CalendarEvent]`: künftige Blöcke der Aufgabe (`BlockPlanner.futureBlocks`), deren Tag in keinem Zeitfenster eines Termins liegt (Fenster nach `sessionWindowStart`).
- Nach dem Sichern lädt das Planungsmodell neu, sobald EventKit die Änderung meldet (`AppEnvironment.swift:291–294`); der reservierte Aufwand folgt damit der neuen Regel, ohne dass `RecurringEffortStore` geändert wird.

## 8. Reihenfolge und Tests (TDD, Swift Testing)

Jeder Schritt: Test schreiben, Fehlschlag sehen, umsetzen, Paket- bzw. App-Tests grün.

1. **Kern: neue Regeln.** `RecurrenceTests`: `monthlyWeekday_thirdWednesday` (18.11., 16.12.2026, 20.1.2027), `monthlyWeekday_everySecondMonth`, `monthlyWeekday_endsAfterCount`, `yearly_sameDay`, `yearly_everySecondYear`, `yearly_leapDaySkipsOtherYears`, `nextOccurrence_onOrAfter`, `nextOccurrence_noneAfterEnd`, `isValid_rejectsEndAndCount`. `AIPlanningTests`: `sessionWindowStart` für beide neuen Fälle.
2. **Kern: Klartext und Vorgaben.** `RecurrenceTextTests`: je Zeile der Tabelle ein Fall, deutsch und englisch, Wochenbeginn Montag und Sonntag. `RecurrencePresetTests`: `weekdays_isMondayToFriday`, `biweekly_usesWeekdayOfStart`, `matching_returnsNilForCustomRule`.
3. **Kern: Aufgabenmodell.** `TaskEditTests`: `diff_setsRecurrence`, `diff_ignoresStartShift`, `diff_clearsRecurrence`, `isEmpty_falseWithRecurrence`.
4. **RemindersKit: Abbildung.** `RecurrenceMappingTests`: Hin und zurück für jede Regel, für Enddatum und Anzahl; `reads_monthlyWeekday_bothForms`; `reads_multipleMonthDays_asUnsupported`; `reads_yearlyWithOtherMonth_asUnsupported`; `unsupported_isNeverWritten`. Hängt an Stufe 0, Punkt 1; ist das nicht möglich, wird die Abbildung über eine eigene Zwischenstruktur getestet.
5. **RemindersKit: Schreibweg.** `ReminderMappingTests`: `applying_setsRecurrence`, `applying_keepsRecurrenceWhenUnchanged`, `taskItem_carriesRecurrenceAndField`. `RemindersTaskProviderTests` mit `FakeReminderStore`: `apply_titleOnly_passesUnchangedRecurrence`, `apply_recurrence_replacesRule`, `apply_recurrenceWithoutDue_fails`, `apply_clearingDue_clearsRecurrence`, `create_withRecurrence`.
6. **App: Editor-Modell.** `RecurrenceEditorModelTests`: `preset_weekdays_setsMondayToFriday`, `customWeekdays_deselectsPreset`, `switchToMonth_derivesDayAndOrdinalFromDue`, `lastWeekday_cannotBeRemoved`, `preview_matchesCoreOccurrences`, `unsupportedOriginal_staysUntouchedWithoutChoice`, `suggestedDue_isNextMatchingDay`. `TaskEditorModelTests`: `save_writesRecurrence`, `dueOff_clearsRecurrence`, `github_hidesRecurrence`. `EstimateAndConflictTests`: `conflict_listsRecurrence`.
7. **App: Planung.** `PlanningModelTests`: `ruleChange_reservesOnNewDays`, `blocksOffSeries_findsBlockOutsideWindows`, `blocksOffSeries_keepsBlockBeforeOccurrence`, `removingRule_dropsReservedEffort`.
8. **Ansichten und Texte:** `RecurrenceEditorView`, Zeilen in Editor und „Neue Aufgabe“, Rückfrage, Lokalisierung (`LocalizedTests` deckt fehlende Übersetzungen auf).
9. **Prüfung am Gerät:** Regel in Tagwerk anlegen, in der Erinnerungen-App ansehen und umgekehrt; abhaken und Weiterrücken beobachten; Regel ändern mit vorhandenen Blöcken. Erst danach gilt die Funktion als geprüft.

## 9. Stufe 2 (Skizze): lokale Aufgaben

- `LocalTask.recurrenceData: Data?` (optional, wie die Schema-Regel verlangt); `LocalTaskProvider` liest und schreibt das Feld und nimmt `.recurrence` in `editableFields` auf.
- Abhaken einer Serie setzt die Fälligkeit auf `nextOccurrence` nach dem aktuellen Termin, senkt eine Anzahl und lässt die Aufgabe offen; ohne weiteren Termin wird sie erledigt. „Rückgängig“ stellt Fälligkeit und Anzahl wieder her.
- Wochenrückschau: erledigte Vorkommen brauchen einen eigenen Eintrag, weil `completedAt` nur einmal je Aufgabe existiert (`LocalTask.swift:23–24`).
- `PlanningModel`, `RecurringItem` und `RecurringEffortStore` von `reminderID` auf eine quellenunabhängige Kennung umstellen; vorhandene Einträge müssen lesbar bleiben.

## 10. Risiken

| Risiko | Folge | Gegenmaßnahme |
|---|---|---|
| Verhalten von EventKit weicht von den Annahmen ab (Anzahl, 31., Schreibweise „n-ter Wochentag“) | Tagwerk und Erinnerungen-App zeigen verschiedene Termine | Stufe 0 vor dem Bau; „Nach Anzahl“ notfalls für Erinnerungen weglassen |
| Nicht darstellbare Regel wird ungewollt überschrieben | Datenverlust in Erinnerungen | Schreiben nur bei `.set`; eigener Test; Hinweis auf der Seite |
| Enddatum verschiebt sich um einen Tag (Zeitzone) | Serie endet zu früh oder zu spät | Hin-und-zurück-Test, Prüfung am Gerät |
| Fälligkeitsdatum passt nicht zur neuen Regel | Liste zeigt einen Tag, der kein Termin ist | Vorschlag des nächsten passenden Tages (offene Frage 3) |
| Zwei Rückfragen beim Sichern (Aufwand und Blöcke) | Verwirrende Abfolge | Eine Abfolge, höchstens zwei Schritte; Test im Editor-Modell |
| Neue Fälle im `enum` werden an einer Stelle vergessen | Falsche Reservierung | Kein `default` in den betroffenen `switch`-Anweisungen |
| Die Empfehlung RK3 ist nicht mit Nutzern oder am Gerät geprüft | Seite zu dicht für kleine Geräte | Früh am Gerät ansehen; Rückfall auf RK1 ändert nur die Ansicht, nicht Modell und Abbildung |

## 11. Offene Fragen

Siehe Abschnitt „Offene Fragen an den Nutzer“ in der Mockup-Datei (Umfang, Blöcke, Fälligkeitsdatum, „Nach Anzahl“, Monatsregeln, „Werktags“, nicht darstellbare Regeln, Aufwand beim Anlegen, Assistent).
