# G4 Zahlenfelder per Eingabe (#218) – Implementation Plan

> **For agentic workers:** Implement task by task with TDD. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 20.11.2026, ohne Mockups (Designpunkte → #188). Grundlage `main` auf `98dc20d` (inkl. G2). Nichts gebaut.

**Goal:** Jedes Zahlenfeld, das heute nur über − und + bedient wird (SwiftUI-`Stepper`), lässt sich zusätzlich durch Tippen auf die Zahl direkt eingeben. Plus und Minus bleiben. Datum und Uhrzeit laufen schon über den System-`DatePicker` (Kalender bzw. Rad) und werden nur geprüft, nicht umgebaut.

**Architecture:** Reine Regeln in `TagwerkCore` (`NumberEntry`: Parser je Art, Begrenzen, Runden auf die Schrittweite). Eine gemeinsame App-Komponente `ValueStepper` (`app/Tagwerk/Common/ValueStepper.swift`) ersetzt jeden `Stepper` 1:1, Datei für Datei in kleinen Commits. Das bestehende `EstimateField` (Aufwand im Editor, schon tippbar) bleibt unverändert und dient als Vorbild für Tastatur und „Fertig“.

**Branch:** `feat/number-input`. **Issue:** #218.

## Global Constraints

- **Parallelbetrieb:** G1 (Rezepte, darin der neue Stepper für Portionen) und G3 (UI-Tests, Accessibility-Identifier) laufen gleichzeitig. Jede Datei wird in einem eigenen kleinen Commit umgestellt, nur die `Stepper`-Zeile(n) ändern sich. Keine Umbenennungen, kein Umsortieren. `ValueStepper` nimmt `.accessibilityIdentifier` von außen an, damit G3-Identifier erhalten bleiben.
- **Nicht anfassen:** die Portionen aus G1 (`Rezept für` / `Ich koche für`). Sie kommen als Folgepunkt nach dem Merge von G1 dran.
- **Verhalten bleibt:** Bereich (`in:`) und Schrittweite (`step:`) gelten weiter für − und + und für die Eingabe. Gespeichert wird wie heute über das Binding, kein neues Datenmodell, kein Backup-Eingriff.
- **Ungültige Eingabe:** wird nie still verworfen. Leer oder nicht lesbar → alter Wert bleibt, kurzer Hinweis unter dem Feld („Bitte eine Zahl eingeben“). Außerhalb des Bereichs → auf die Grenze begrenzt. Zwischen zwei Schritten → auf den nächsten Schritt gerundet. Der angepasste Wert steht sofort im Feld, VoiceOver sagt ihn an.
- **Dezimaltrennzeichen** nach `Locale.current`: Komma (de) bzw. Punkt (en). Beide werden beim Lesen akzeptiert, Tausenderpunkte („2.300“, „30.000“) werden in Ganzzahl-Feldern ignoriert.
- **Tastatur:** `.numberPad` für Ganzzahlen, `.decimalPad` für Dezimalzahlen und Dauern; „Fertig“ über `keyboardDoneButton(focus:)` aus `Common/KeyboardDismissal.swift`. Übernommen wird bei „Fertig“ und beim Verlassen des Felds.
- **Bedienungshilfen:** Das Element bleibt ein einstellbares Element (Wischen hoch/runter erhöht und senkt wie heute). Zusätzlich eine benannte Aktion „Wert eingeben“, die das Feld fokussiert. Dynamic Type bis AX5 ohne Abschneiden (bei AX-Größen bricht die Zeile um).
- **Texte:** Deutsch ist Quellsprache, jeder neue Text deutsch und englisch. String-Kataloge nicht neu formatieren: Schlüssel im bestehenden JSON-Format ergänzen, prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`; `scripts/translations/en.json` nachziehen.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI. Tests mit `app/test-all.sh` auf dem eigenen Simulator der Arbeitskopie.

## Bestandsaufnahme (main `98dc20d`)

Art: **Zahl** = Ganzzahl, **Dezimal** = Zahl mit Nachkommastellen, **Dauer** = Minuten (Anzeige über `CapacityText.duration`/`IntakeFormat.duration` bzw. „min“). Datum/Uhrzeit siehe unten.

| # | Datei:Zeile | Feld | Art | Bereich / Schritt | Eingabeeinheit |
|---|---|---|---|---|---|
| 1 | `Settings/CaptureSettingsView.swift:14` | Kalorien-Ziel | Zahl | 1000…6000 / 50 | kcal |
| 2 | `Settings/CaptureSettingsView.swift:16` | Wasser-Ziel | Dezimal | 500…6000 ml / 250 | Liter (Anzeige „2,0 L“) → ml |
| 3 | `Settings/CaptureSettingsView.swift:18` | Training pro Woche | Dauer | 0…1200 / 15 | min |
| 4 | `Settings/CaptureSettingsView.swift:20` | Schritte pro Tag | Zahl | 0…30000 / 500 | Schritte |
| 5 | `Settings/CaptureSettingsView.swift:24` | Eiweiß-Ziel | Zahl | 20…400 / 5 | g |
| 6 | `Settings/SettingsView.swift:24` | Mittagspause Dauer | Dauer | 0…180 / 15 | min |
| 7 | `Settings/SettingsView.swift:28` | Puffer | Dauer | 0…60 / 5 | min |
| 8 | `Settings/PlanningSettingsSection.swift:29` | Standarddauer | Dauer | 15…240 / 15 | min |
| 9 | `Settings/FocusSettingsView.swift:12` | Fokus | Dauer | 5…120 / 5 | min |
| 10 | `Settings/FocusSettingsView.swift:14` | Pause | Dauer | 1…30 / 1 | min |
| 11 | `Settings/FocusSettingsView.swift:15` | Lange Pause | Dauer | 5…60 / 5 | min |
| 12 | `Settings/FocusSettingsView.swift:16` | Runden | Zahl | 1…8 / 1 | – |
| 13 | `Capture/WorkoutSheet.swift:30` | Training Dauer | Dauer | 5…300 / 5 | min |
| 14 | `Capture/MealSheet.swift:374` | Menge (Faktor) je Posten | Dezimal | `MealItem.factorRange` / `factorStep` | Faktor („1,5“) |
| 15 | `Capture/DrinkSheet.swift:16` | Andere Menge | Zahl | 50…2000 / 50 | ml |
| 16 | `Capture/DrinkSheet.swift:90` | Menge (Bearbeiten) | Zahl | 50…2000 / 50 | ml |
| 17 | `Planning/TravelOverrideView.swift:43` | Feste Fahrzeit | Dauer | `TravelOverrideRules` min…max / step | min |
| 18 | `Planning/SuggestionViews.swift:445` | Dauer im Vorschlag | Dauer | 15…360 / 15 | min |
| 19 | `Editor/PlannedSection.swift:32` | Zeitblock Dauer | Dauer | 15…720 / 15 | min |
| 20 | `Editor/PlannedSection.swift:39` | Neuer Zeitblock Dauer | Dauer | 15…720 / 15 | min |
| 21 | `Editor/RecurrenceEditorView.swift:112` | Intervall („alle 2 Wochen“) | Zahl | `model.intervalRange` / 1 | – |
| 22 | `Editor/RecurrenceEditorView.swift:171` | Anzahl Wiederholungen | Zahl | 1…999 / 1 | – |
| 23 | `Routines/HabitSheet.swift:65` | Tage pro Woche | Zahl | 1…7 / 1 | – |
| 24 | `Routines/RoutineSettingsView.swift:206` | Abstand vor Schlafzeit | Dauer | `RoutineSchedule.offsetRange` / `offsetStep` | min |
| 25 | `Reminders/ReminderOffsetPicker.swift:37` | Menge (vorher) | Zahl | 0…`ReminderOffset.maximumAmount` / 1 | – |
| 26 | `Reminders/ReminderOffsetPicker.swift:42` | Tage vorher | Zahl | 0…`ReminderOffset.maximumDaysBefore` / 1 | – |
| – | `Editor/EstimateField.swift` | Aufwand (h) | Dezimal | schon tippbar | bleibt unverändert |
| – | G1: Portionen (zwei Felder) | Portionen | Zahl | – | **Folgepunkt nach Merge von G1** |

Keine eigenen Plus/Minus-Steuerungen außer `EstimateField`; die übrigen `plus.circle`-Treffer sind „hinzufügen“-Knöpfe.

**Datum und Uhrzeit:** alle 31 `DatePicker` in `app/Tagwerk` (u. a. Fälligkeit, Zeitblock, Ruhezeiten, Arbeitszeiten, Schlafzeit, Erinnerungs-Uhrzeit, Training/Mahlzeit/Getränk) sind System-`DatePicker` im Kompaktstil: Tippen öffnet bei Datum den Kalender, bei Uhrzeit das Rad bzw. die Tastatureingabe für Stunde und Minute. Vier Blätter nutzen bewusst `.graphical`. Keine Änderung nötig; Task 8 prüft nur, dass nirgends ein Datum oder eine Uhrzeit als reiner Text mit − / + bedient wird.

## Review Focus

1. **Begrenzen statt verwerfen:** „Puffer“ (0…60, Schritt 5): Eingabe „7“ → 5, „8“ → 10, „99“ → 60, „abc“ → alter Wert + Hinweis. Test `NumberEntryTests.normalize_roundsToNearestStep_andClamps`.
2. **Sprache:** de „1,5“ und en „1.5“ ergeben 1,5; de „2.300“ in kcal ergibt 2300, nicht 2,3. Tests `parse_decimalSeparatorFollowsLocale`, `parse_integerIgnoresGroupingSeparator`.
3. **Dauer:** „90“ → 90 min, „1,5 h“ → 90, „1:30“ → 90, „1 h 30“ → 90. Test `parseDuration_acceptsMinutesHoursAndClock`.
4. **Wasser in Litern:** Eingabe „2,25“ → 2250 ml → auf 250er-Schritt gerundet 2250; „2,1“ → 2000. Test `quantity_litersToMilliliters_roundedToStep`.
5. **Kein Doppelauslösen in Formularen:** die −/+-Knöpfe in einer `Form`-Zeile lösen nicht gemeinsam aus (`.buttonStyle(.borderless)`, wie in `EstimateField`).
6. **VoiceOver:** Wischen hoch/runter ändert in Schrittweite, Aktion „Wert eingeben“ fokussiert das Feld.

---

## Task 1: `NumberEntry` in TagwerkCore

**Files:** Create `app/Packages/TagwerkCore/Sources/TagwerkCore/NumberEntry.swift`, Test `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/NumberEntryTests.swift`.

```swift
public enum NumberEntryKind: Sendable, Equatable {
    case integer                   // Runden, kcal, ml, Schritte
    case decimal(fractionDigits: Int) // Faktor, Liter
    case durationMinutes           // Minuten; akzeptiert h, :, „1 h 30“
}
public enum NumberEntry {
    /// Liest die Eingabe; `nil` bei leer oder nicht lesbar.
    public static func parse(_ text: String, kind: NumberEntryKind, locale: Locale) -> Double?
    /// Begrenzt auf `range` und rundet auf den nächsten Schritt ab `range.lowerBound`.
    public static func normalize(_ value: Double, range: ClosedRange<Double>, step: Double) -> Double
    /// Ob `normalize` den Wert geändert hat (für den Hinweis „angepasst auf …“).
    public static func wasAdjusted(_ raw: Double, normalized: Double) -> Bool
    /// Text für das Eingabefeld (ohne Einheit, ohne Tausendertrennzeichen), z. B. „1,5“.
    public static func editingText(_ value: Double, kind: NumberEntryKind, locale: Locale) -> String
}
```

- [ ] Tests zuerst (rot), dann Implementierung:
  - `parse_integer_plain` („42“ → 42), `parse_integerIgnoresGroupingSeparator` (de „2.300“ → 2300, en „2,300“ → 2300)
  - `parse_decimalSeparatorFollowsLocale` (de „1,5“, en „1.5“ → 1,5; de akzeptiert auch „1.5“ als 1,5, wenn nur ein Trennzeichen vorkommt)
  - `parse_rejectsEmptyAndText` („“, „ “, „abc“, „1,2,3“ → nil)
  - `parse_negativeIsRejected` („-5“ → nil; kein Feld erlaubt negative Werte)
  - `parseDuration_acceptsMinutesHoursAndClock` („90“, „1,5 h“, „1.5h“, „1:30“, „1 h 30“, „1h30min“ → 90; „2 h“ → 120)
  - `normalize_roundsToNearestStep_andClamps` (Bereich 0…60, Schritt 5: 7 → 5, 8 → 10, 99 → 60, −3 → 0)
  - `normalize_stepRelativeToLowerBound` (Bereich 15…720, Schritt 15: 20 → 15, 23 → 30)
  - `normalize_decimalStep` (Faktor 0,25…10, Schritt 0,25: 1,3 → 1,25)
  - `editingText_noGroupingNoUnit` (de 2300 → „2300“, 1,5 → „1,5“; en 1,5 → „1.5“)
- [ ] Commit `feat: add number entry rules for typed stepper values`

## Task 2: Komponente `ValueStepper`

**Files:** Create `app/Tagwerk/Common/ValueStepper.swift`, `app/Tagwerk/Common/ValueEntryModel.swift`; Test `app/TagwerkTests/ValueEntryModelTests.swift`.

- **`ValueEntryModel`** (testbar, ohne View): hält `text`, `isEditing`, `hint: String?`; `begin(value:)`, `commit(current:) -> Int/Double` (nutzt `NumberEntry.parse` + `normalize`; bei `nil` alter Wert + Hinweis „Bitte eine Zahl eingeben.“, bei Anpassung Hinweis „Angepasst auf …“ für 3 s).
- **`ValueStepper`** – zwei Initialisierer, damit die Aufrufer 1:1 umgestellt werden können:
  ```swift
  ValueStepper(_ title: LocalizedStringKey, value: Binding<Int>, in: ClosedRange<Int>, step: Int = 1,
               kind: NumberEntryKind = .integer, unit: LocalizedStringKey? = nil,
               display: @escaping (Int) -> String)           // Anzeige wie bisher, z. B. CapacityText.duration
  ValueStepper(_ title: LocalizedStringKey, value: Binding<Double>, in: ClosedRange<Double>, step: Double,
               kind: NumberEntryKind, unit: LocalizedStringKey? = nil, display: @escaping (Double) -> String)
  ```
  plus eine Variante für umgerechnete Einheiten (`scale:`), z. B. Wasser: gespeichert ml, eingegeben Liter (`scale: 1000`).
- **Aussehen ohne Design-Entscheid:** `LabeledContent(title)` mit rechts: Wert als Knopf (Akzentfarbe, wie ein tippbarer Wert in Einstellungen) → bei Tippen wird er zum `TextField` (gleiche Stelle, `.multilineTextAlignment(.trailing)`, Tastatur je Art, `keyboardDoneButton(focus:)`), daneben − und + (`.buttonStyle(.borderless)`, `.buttonRepeatBehavior(.enabled)`, Grenzen deaktivieren den Knopf). Hinweis als `.footnote` unter der Zeile.
- **Bedienungshilfen:** ganze Zeile `.accessibilityElement(children: .ignore)`, `.accessibilityLabel(title)`, `.accessibilityValue(display(value))`, `.accessibilityAdjustableAction` (Schritt), `.accessibilityAction(named: "Wert eingeben")` → Fokus. Während des Tippens wird das Textfeld zugänglich (Bedingung über `isEditing`).
- [ ] Tests `ValueEntryModelTests`: `commit_validValue_isNormalized`, `commit_unreadable_keepsOldValueAndShowsHint`, `commit_outOfRange_clampsAndShowsAdjustedHint`, `commit_liters_scaledToMilliliters`, `begin_showsEditingTextWithoutUnit`.
- [ ] Neue Texte (de/en): „Wert eingeben“ / „Enter value“; „Bitte eine Zahl eingeben.“ / „Please enter a number.“; „Angepasst auf %@“ / „Adjusted to %@“.
- [ ] Commit `feat: add a stepper whose value can be typed`

## Task 3: Einstellungen umstellen (Fundstellen 1–12)

Je Datei ein Commit, nur die `Stepper`-Aufrufe ersetzen, Anzeige-Funktionen (`IntakeFormat.grouped`, `IntakeFormat.liters`, `workoutGoalText`, `stepGoalText`, `CapacityText.duration`) als `display:` übergeben.

- [ ] `CaptureSettingsView.swift` (1–5; Wasser mit `kind: .decimal(fractionDigits: 2)`, `scale: 1000`) → `refactor: type the capture goals`
- [ ] `SettingsView.swift` (6, 7) → `refactor: type lunch and buffer durations`
- [ ] `PlanningSettingsSection.swift` (8) → `refactor: type the default task duration`
- [ ] `FocusSettingsView.swift` (9–12) → `refactor: type the focus timer values`

## Task 4: Erfassen (Fundstellen 13–16)

- [ ] `WorkoutSheet.swift` (13)
- [ ] `MealSheet.swift` (14; `kind: .decimal(fractionDigits: 2)`, Bereich/Schritt aus `MealItem`; Zeile liegt in einer `ForEach`-Liste, Fokus je Posten über `id`)
- [ ] `DrinkSheet.swift` (15, 16)
- [ ] je ein Commit `refactor: type … in capture sheets`

## Task 5: Planen (Fundstellen 17–18)

- [ ] `TravelOverrideView.swift` (17)
- [ ] `SuggestionViews.swift` (18)
- [ ] Commits je Datei

## Task 6: Editor und Routinen (Fundstellen 19–24)

- [ ] `PlannedSection.swift` (19, 20)
- [ ] `RecurrenceEditorView.swift` (21, 22; Intervall-Text bleibt der Satz „Alle 2 Wochen“ als `display:`)
- [ ] `HabitSheet.swift` (23)
- [ ] `RoutineSettingsView.swift` (24; „30 min vorher“ als `display:`)
- [ ] Commits je Datei

## Task 7: Erinnerungen (Fundstellen 25–26)

- [ ] `ReminderOffsetPicker.swift` (25, 26)
- [ ] Commit

## Task 8: Datum und Uhrzeit prüfen

- [ ] `grep -rn "Stepper(" app/Tagwerk` ist leer (außer G1-Portionen, falls schon gemergt → Folgepunkt).
- [ ] Alle `DatePicker` bleiben im Kompakt- bzw. `.graphical`-Stil; kein Datum/keine Uhrzeit wird über − / + gesteuert. Ergebnis im Abschnitt „Stand der Umsetzung“ festhalten.

## Task 9: Abschluss

- [ ] `app/test-all.sh` grün, Kataloge ohne Befund.
- [ ] „Stand der Umsetzung“ in die Plan-Kopie: Abweichungen, eigene Entscheidungen, offene Gerätetests.
- [ ] Simulator und Derived Data der Arbeitskopie löschen.

## Folgepunkte (nicht in G4)

- **Portionen aus G1** („Rezept für“, „Ich koche für“) auf `ValueStepper` umstellen, sobald G1 auf `main` ist.
- `EstimateField` könnte später `NumberEntry` für das Lesen nutzen (heute eigene, getestete Logik; kein Umbau ohne Not).

## Designpunkte für #188

- **Erkennbarkeit:** Woran erkennt man, dass die Zahl tippbar ist (Akzentfarbe, Unterstreichung, Kapsel wie beim Aufwand)? Einheitlich mit `EstimateField`?
- **Inline oder Blatt:** Eingabe direkt in der Zeile (Plan-Vorgabe) oder kleines Eingabeblatt mit großer Zahl?
- **Schrittweite bei Eingabe:** Sollen getippte Werte auf die Schrittweite gerundet werden (Plan: ja) oder dürfen sie frei sein (z. B. Puffer 7 min)?
- **Einheit bei Dauern:** Eingabe in Minuten oder in Stunden (z. B. Standarddauer „1,5“ = Stunden?) – Plan: Minuten, mit „h“ und „1:30“ als Alternativen.
- **Hinweis bei Anpassung:** Wortlaut und Dauer von „Angepasst auf …“.

## Gerätetests

1. Jede der 26 Fundstellen: − und + wie vorher, Tippen auf die Zahl öffnet die Eingabe mit passender Tastatur, „Fertig“ übernimmt.
2. Deutsch: „1,5“ im Mahlzeit-Faktor, „2,25“ beim Wasserziel, „2.300“ bei Kalorien. Englisch: „1.5“, „2,300“.
3. Grenzen: Puffer „99“ → 60, „7“ → 5 mit Hinweis; leeres Feld → alter Wert mit Hinweis.
4. Dauer-Eingaben „1:30“, „1,5 h“, „90“ ergeben dieselbe Dauer (Standarddauer, Zeitblock).
5. VoiceOver: Wischen hoch/runter ändert, Rotor-Aktion „Wert eingeben“ öffnet die Eingabe.
6. Größte Schrift (AX5): Zeilen brechen um, nichts abgeschnitten, Knöpfe erreichbar.
7. Datum/Uhrzeit-Stichprobe: Fälligkeit (Kalender), Ruhezeiten/Schlafzeit (Rad) unverändert.

## Stand der Umsetzung

Umgesetzt am 20.11.2026 auf Branch `feat/g4-number-input` (statt `feat/number-input`, der Branch war vorgegeben).

**Fertig:** Task 1 bis 7 (alle 26 Fundstellen auf `ValueStepper`), Task 8 geprüft, Task 9 (Tests, Kataloge).

**Test:** `app/test-all.sh` grün: TagwerkCore 1120 Tests, App 1699 Tests, Kataloge ohne Befund (`check-strings.py --require-english`, `sync-strings.sh --check`). Neu: `NumberEntryTests` (12) und `ValueEntryModelTests` (7).

**Abweichungen und eigene Entscheidungen**

- **Plandatei:** `2026-11-20-g4-number-input.md` statt `2026-11-19-…` (Datum der Umsetzung, wie bei G2).
- **Bereich im Modell:** `ValueEntryModel` bekommt Bereich und Schritt vor jeder Nutzung neu übergeben (`update`), weil der Intervall-Bereich der Wiederholung von der Häufigkeit abhängt.

- **Tastatur bei Dauern:** `.numbersAndPunctuation` statt `.decimalPad`. Auf dem Dezimalblock lassen sich „1:30“ und „1 h 30“ nicht tippen; ohne sie wären die geplanten Dauer-Formate unerreichbar. Ganzzahlen: `.numberPad`, Dezimalzahlen: `.decimalPad`.
- **Live übernehmen:** Jeder lesbare Tastenanschlag setzt den (begrenzten, gerundeten) Wert sofort, wie bei `EstimateField`; so geht beim Sichern eines Blatts mit offener Tastatur nichts verloren. Beim Schließen (Fertig, Verlassen des Felds) wird der Text neu geschrieben und der Hinweis gezeigt. Ist der Text dann leer oder nicht lesbar, kehrt der Wert von vor der Eingabe zurück. Ausnahme: `SuggestionViews` (Dauer im Vorschlag) übernimmt erst beim Schließen (`appliesWhileTyping: false`), weil jede Änderung neu plant.
- **Titel statt Wert im Titel:** Die Zeilen heißen jetzt „Dauer“, „Puffer“ usw.; der Wert steht rechts als antippbarer Akzentwert (vorher „Dauer: 45 min“ als Titel). Neue Titel/Einheiten haben deutsche und englische Texte.
- **Wiederholung:** Titel „Intervall“ / „Anzahl“; der Satz „Alle 2 Wochen“ bleibt als Anzeige des Werts.
- **Hinweis:** verschwindet nach 3 s und wird per VoiceOver angesagt.
- **Mahlzeit-Menge:** `.font(.subheadline)` auf der Zeile; die graue Titelfarbe von vorher entfällt.
- **Katalogformat:** Kataloge nicht neu formatiert; neue Schlüssel im bestehenden JSON-Format ergänzt.

**Nachtrag nach dem Merge von G1 (Rebase auf `origin/main` mit #223):** `app/test-all.sh` grün: TagwerkCore 1173 Tests, App 1746 Tests, Kataloge ohne Befund. Eine UI-Teststufe gibt es in diesem Stand von `main` noch nicht (G3 nicht gemerged). Keine neuen Texte, die Kataloge sind unverändert.

- **Portionen:** Die zwei Zeilen „Rezept für“ / „Ich koche für“ (`RecipeSheets.swift`) und „Portionen“ (`RecipeNoteSaveSheet.swift`) sind jetzt `ValueStepper`. Neu in `ValueStepper`: ein Initialisierer für einen noch nicht gesetzten Wert (`Binding<Int?>`, `start:`). Solange der Wert `nil` ist, zeigt die Zeile „–“, der erste Tipp auf − oder + setzt `start` (4, wie vorher), das Feld öffnet leer, und eine nicht lesbare Eingabe lässt den Wert `nil`. `ValueEntryModel.begin(value:startsEmpty:)` und `hasReadableText` sind neu (Test `begin_startsEmpty_forAValueThatIsNotSetYet`). Die Hilfsfunktion `RecipeResultView.stepped` und ihr Test entfallen, weil die Regel jetzt in der Komponente liegt.
- **Mittagspause je Tag** (`Planning/EntrySheet.swift`, `lunchContent`): „Beginn“ ist ein `DatePicker` (`.hourAndMinute`, wie die übrigen Uhrzeitfelder), „Dauer“ ein `ValueStepper` (15 min Schritt, Minimum 15 wie vorher, Maximum bis Tagesende). Das Modell rundet weiter auf 15 min (`setLunch`). Die Dauer übernimmt erst beim Schließen des Felds (`appliesWhileTyping: false`), weil jede Änderung neu lädt.
- **Bewusst nicht umgestellt:** `stepRow` bleibt für „Beginn“ und „Dauer“ von Terminen und Tagwerk-Blöcken im selben Blatt. Jede Änderung schreibt dort in den Kalender (EventKit), und bei Serien öffnet sie die Frage „Nur diesen / alle folgenden“. Ein Rad-`DatePicker` würde je Raststellung schreiben bzw. fragen; das braucht einen eigenen Entwurf (Übernehmen-Knopf) und ist hier nicht „straightforward“. Offener Punkt für #188.
- **Optik der Portionen:** Der Wert „–“ ist nicht mehr rot (vorher bei fehlender Portionszahl in „Rezept für“); der rote Hinweis im Abschnittsfuß bleibt.
- **Weitere −/+-Steuerungen:** keine gefunden (Suche nach `minus`/`plus`-Symbolen, „−“/„+“-Knöpfen, `Slider`, `accessibilityAdjustableAction`, `onIncrement`). Übrig sind nur `EstimateField` (bewusst unverändert) und die Termin-Zeilen aus `stepRow`.

**Task 8:** `grep "Stepper"` ohne `ValueStepper` ist leer (auch ohne Klammer, also inklusive der `Stepper { … }`-Form aus G1). Die Mittagspause ist jetzt ein `DatePicker`; über −/+ bedient werden nur noch Beginn und Dauer von Terminen (`stepRow`, siehe oben).

**Offene Gerätetests:** alle Punkte aus „Gerätetests“. Layout und Tastatur sind nur durch Unit-Tests der Regeln abgedeckt, nicht visuell geprüft (ein Snapshot im Test-Host blieb leer). Insbesondere zu prüfen: Fokus beim Antippen des Werts in einer `Form`-Zeile, Zeilenumbruch bei AX5, Aktion „Wert eingeben“, Identifier-Weitergabe für G3 (die Zeile ist jetzt ein einstellbares Element statt eines `Stepper`).
