# Aufgaben ohne Uhrzeit ziehen keine freie Zeit mehr ab – Implementation Plan

> **Stand 28.11.2026**, Code-Grundlage `origin/main` bei `063a4bbf`, Branch `fix/free-time-task-counting`. Plan von Fable, Zeilennummern am Checkout nachgelesen.

> **Entscheidungen:** Nutzer: Aufgaben ohne Zeitblock verringern die freie Zeit nirgends mehr; die Karte nennt sie als Hinweis mit Aufwand und sagt, ob sie passen (Option „Als Hinweis nennen“). Offene Punkte O1–O6: es gelten die Vorgaben unten (am 28.11. so übernommen).

> **For agentic workers:** Task für Task, jeweils mit TDD, Schritte als Checkbox (`- [ ]`).

**Anlass (Wortlaut des Nutzers):** „Die noch nicht in den Kalender gezogenen To-Dos werden trotzdem schon von meiner freien Zeit abgezogen. Das sollte eigentlich nicht so sein.“

**Gemeldeter Tag (englische Oberfläche, Sa. 28. Nov., 13:24):** Karte „50 min still free / from now · 13:24 to 18:00 · whole day 3 h 40 free of 6 h 40 / 9:00–18:00 · 1 h break · 1 h 20 events · 3 h scheduled / 6 tasks without effort counted at the default duration“. Im Raster nur ein Termin 12:00–14:00 und die Pause, keine Zeitblöcke.

**Goal:**
- Der gemeldete Tag zeigt um 13:24 „3 h 50 noch frei“ und „ganzer Tag 6 h 40 frei von 6 h 40“.
- Darunter steht „6 Aufgaben ohne Uhrzeit · 3 h – passen in die noch freie Zeit“.
- Karte, Woche, Monat, Aufgabenliste, Abendzeile, Routinen-Überblick und Assistent nennen dieselbe freie Zeit.
- Die KI-Planung behält ihre Lastprüfung (O1).

**Architecture:**
- **`TagwerkCore`, `Capacity.swift`:** `capacity(_:)` bleibt der einzige Einstieg. `untimedPlannedMinutes` wird Information statt Abzug. `DayCapacity` bekommt `untimedMinutes`, `untimedCount` und `untimedOverflowMinutes`.
- **`TagwerkCore`, `AIPlanning.swift`:** `PlanInputDay` trennt freie Zeit (`freeMinutes`, neu) von Last (`plannedMinutes`, unverändert Blöcke plus Aufgaben ohne Uhrzeit).
- **App:** `CapacityText` bekommt `untimedHint`, `estimateNote`, `untimedCompact`, `summaryWithUntimed`. Kein neues SwiftData-Modell, keine neue Einstellung.

## Global Constraints

- **Strings:** Deutsch ist Quellsprache. Jeder neue Text steht im Katalog `app/Tagwerk/Localizable.xcstrings` und in `scripts/translations/en.json`. Prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs und Testnamen englisch.
- **Eine Rechnung:** Keine Ansicht rechnet freie Zeit selbst.
- **Quellverträglich:** Neue Parameter von `CapacityInput.init` haben Vorgabewerte.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** nach jedem Task `TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh`; am Ende `app/test-all.sh` ganz.

## Befunde (Pfade unter `app/`)

### Wo der Abzug entsteht

- `Tagwerk/Planning/PlanningModel.swift:1916–1926`: Die Schleife über `assignedSorted + openToday` summiert `untimedPlanned` (Aufwand, sonst `settings.defaultTaskMinutes`), zählt `estimated` und füllt `counted`. Wiederkehrende Aufgaben werden übersprungen (KA3). Die Werte gehen in `CapacityInput` (`:1935`) und `PlanInputDay` (`:1941`).
- `Packages/TagwerkCore/Sources/TagwerkCore/Capacity.swift:62`: `CapacityBreakdown.plannedMinutes = blockMinutes + untimedMinutes`.
- `Capacity.swift:100` (freier Tag), `:116` (`untimedMinutes:`), `:118–120` (`freeMinutes = available − planned`, `isOverbooked`), `:128` (`remainingMinutes … − input.untimedPlannedMinutes`).

**Nachrechnung des gemeldeten Tags** (Fenster 540..<1080, Pause 720..<780, Puffer 10, Termin 720..<840, jetzt 804):

| Schritt | heute | neu |
|---|---|---|
| Termin mit Puffer | 710..<850 | gleich |
| blockiert (Vereinigung mit Pause) | 140 = 60 Pause + 80 Termine | gleich |
| verfügbar | 400 = 6 h 40 | gleich |
| Aufgaben ohne Uhrzeit | 6 × 30 = 180, abgezogen | 180, nur Hinweis |
| ganzer Tag frei | 220 = 3 h 40 | **400 = 6 h 40** |
| ab jetzt: 804..<1080 = 276, blockiert 804..<850 = 46 | 230 − 180 = 50 | **230 = 3 h 50** |
| Hinweis | – | 180 ≤ 230: passt |

### Verbraucher und neues Verhalten

| Ort | Stelle | heute | neu |
|---|---|---|---|
| Kernrechnung | `Capacity.swift:100–128` | Aufgaben ohne Uhrzeit sind Last | nur Blöcke sind Last; Aufgaben ohne Uhrzeit sind Information |
| Tag, Überschrift | `Planning/DayView.swift:340`, `CapacityBar.swift:48–53` | `remainingMinutes` mit Abzug | ohne Abzug |
| Tag, „ganzer Tag …“ | `DayView.swift:344–346, 371–381` | `summary` mit Abzug | ohne Abzug |
| Tag, Balken | `CapacityBar.swift:10–17` | Blöcke plus Aufgaben | nur Blöcke (O5) |
| Tag, Erklärzeile | `CapacityBar.swift:43` „… eingeplant“ | Blöcke plus Aufgaben | nur Zeitblöcke; Text bleibt |
| Tag, Standarddauer-Zeile | `DayView.swift:351–354` | eigene Zeile | entfällt; ersetzt durch Hinweis plus Zusatzzeile |
| Tag, „nach dem Übernehmen … frei“ | `DayView.swift:355–361`, `PlanningModel.swift:1606–1611` | rechnet `counted` wieder drauf | `free − added` |
| Tag, „Unerledigtes verschieben“ | `DayView.swift:272`, `PlanningModel.swift:1513` | `isOverbooked` | `untimedMinutes > freeMinutes` |
| Woche | `Planning/WeekView.swift:106–108` | `summary`, rot bei `isOverbooked` | `summaryWithUntimed`, rot bei Überhang |
| Seitenvorschau | `Planning/DayPagePreview.swift:49–50` | wie Woche | wie Woche |
| Monat | `Planning/MonthView.swift:140, 159` | `summary` | Kurzhinweis im VoiceOver-Wert und im Tageskopf |
| Aufgabenliste, Auswahl | `Tasks/TaskListView.swift:285–292` | `remainingMinutes` mit Abzug | neue Zahl automatisch |
| Abendzeile | `PlanningModel.swift:1639` | `available − planned` | `input.freeMinutes` |
| „Alles auf morgen“, Vorschau | `PlanningModel.swift:1544–1548`, `Routines/LeftoverSheet.swift:154–158, 232–240` | `available − planned` | `input.freeMinutes` (O2) |
| Routinen-Überblick | `Routines/RoutinesModel.swift:258` | `available − planned` | `input.freeMinutes` |
| Assistent, Kontextzeile | `AI/AssistantModel.swift:868–872` | „X frei von Y, überbucht“ | neue Zahlen; Zusatz zu Aufgaben ohne Uhrzeit |
| „Frei gibt … frei“ | `DayGridScreen.swift:530`, `Capacity.swift:138–146` | `availableMinutes` | unverändert |
| Ablage „Ohne Uhrzeit“ | `DayGridScreen.swift:318–341` | nur `plan.assigned` | unverändert (O3) |

### KI-Planung

- `freeGaps` (`AIPlanning.swift:1045–1063`), `freeSlots`/`freeMinutes` der Tageseingabe (`:940–949`) und `validateBlocks` (`:778–783`) ziehen Aufgaben ohne Uhrzeit nicht ab. Kein Fehler.
- Weiche Lastprüfung `loadAfter()` (`:794–801`), `overbookedBy` (`:947, 954`), Auswahl verschiebbarer Aufgaben (`:296, :325`), `:633`, Woche/Monat `freeMinutes = available − planned` (`:931, 953`), `periodFreeMinutes` (`:395`), `validateAssignments` (`:824–845`), `validateChanges` (`:724–731`) hängen an der Last samt Aufgaben ohne Uhrzeit. In Woche und Monat ordnet die KI Aufgaben ohne Uhrzeit Tagen zu; die Last begrenzt, wie viele auf einen Tag kommen. Diese Zahlen bleiben unverändert (O1).

### Strings

- `"%lld Aufgabe(n) ohne Aufwand mit Standarddauer gerechnet"` entfällt (Katalog, `en.json:253–256`, `TagwerkUITests/AuditAllowlist.swift:74, 280`).
- `"%@ eingeplant"`, `"%@ zu viel"`, `"%@ noch frei"`, `"%@ frei von %@"`, `"heute noch %@ frei"`, `"kein Arbeitstag"`: bleiben.

## Regeln (ersetzen Regel 11–13 aus `2026-11-21-kapazitaet.md`)

11. **Eingeplantes** sind nur Zeitblöcke: Länge der Vereinigung der Blöcke im Fenster, ohne den schon blockierten Teil. Aufgaben ohne Zeitblock und reservierter Aufwand wiederkehrender Aufgaben verbrauchen keine freie Zeit.
11a. **Aufgaben ohne Uhrzeit** sind die dem Tag zugeordneten oder an ihm fälligen offenen Aufgaben ohne Zeitblock, ohne wiederkehrende. Ihr Aufwand ist die Summe der Aufwände, ohne Angabe die Standarddauer. Die Summe ist ein Hinweis.
11b. **Passt oder übersteigt.** Verglichen wird mit der freien Zeit des Tages, heute mit „noch frei ab jetzt“. Überhang = Summe − freie Zeit, mindestens 0.
12. **Frei.** Gesamtzahl minus Eingeplantes. „Zu viel“ gibt es an Arbeitstagen nur noch durch Zeitblöcke, sonst an einem freien Tag mit Zeitblöcken.
13. **Heute, „noch frei“.** Dieselbe Rechnung im Fenster ab jetzt. Aufgaben ohne Uhrzeit werden nicht abgezogen.

## Texte

**Hinweis auf der Tageskarte** (eine Zeile unter der Erklärzeile; fehlt ohne Aufgaben ohne Uhrzeit und an vergangenen Tagen):

| Fall | Deutsch (Plural über Katalog) | Englisch (one / other) |
|---|---|---|
| künftiger Tag, passt | „1 Aufgabe ohne Uhrzeit · 30 min – passt in die freie Zeit“ / „6 Aufgaben ohne Uhrzeit · 3 h – passen in die freie Zeit“ | „%lld task without a time · %@ – fits into the free time“ / „%lld tasks without a time · %@ – fit into the free time“ |
| künftiger Tag, übersteigt | „6 Aufgaben ohne Uhrzeit · 3 h – 1 h mehr als frei“ | „… – %@ more than free“ |
| heute, passt | „… – passt/passen in die noch freie Zeit“ | „… – fits/fit into the time still free“ |
| heute, übersteigt | „… – 1 h mehr als noch frei“ | „… – %@ more than still free“ |
| freier Tag (O4) | „6 Aufgaben ohne Uhrzeit · 3 h“ | „%lld task(s) without a time · %@“ |

**Zusatzzeile** (nur wenn `estimatedCount > 0`): „6 davon ohne Aufwand mit Standarddauer gerechnet“ / „%lld of them without effort counted at the default duration“.

**Woche, Seitenvorschau, Tageskopf im Monat** (an `summary` mit „ · “ angehängt):
- passt: „6 h 40 frei von 6 h 40 · 3 h ohne Uhrzeit“ / „%@ without a time“.
- übersteigt: „… · 7 h 30 ohne Uhrzeit (50 min zu viel)“ in `redText` / „%1$@ without a time (%2$@ over)“.
- Monatszelle: nur im VoiceOver-Wert.

**Assistent, Kontextzeile** (deutscher Prompttext): „- 2026-11-28: 6 h 40 frei von 6 h 40, 6 Aufgaben ohne Uhrzeit (3 h), 0 Zeitblöcke“; bei Überhang „(3 h, 1 h mehr als frei)“. „, überbucht“ nur bei `isOverbooked`.

## Datenmodell (`Capacity.swift`)

- **`CapacityInput`:** `untimedPlannedMinutes` und `estimatedCount` bleiben. Neu `untimedCount: Int = 0` als letzter Parameter mit Vorgabewert. Kommentar: „Information only: tasks of the day without a time block; they use no free time“.
- **`DayCapacity`:** neu `untimedMinutes`, `untimedCount`, berechnet `untimedOverflowMinutes = max(0, untimedMinutes - max(0, remainingMinutes ?? freeMinutes))`. `plannedMinutes` ist nur noch die Blocklänge.
- **`CapacityBreakdown`:** `untimedMinutes` und das berechnete `plannedMinutes` entfallen; Pause + Fahrzeit + Termine + Blöcke + frei = Fenster.
- **`PlanInputDay`:** neu `blockMinutes`, berechnet `freeMinutes = availableMinutes - blockMinutes`. `plannedMinutes` bleibt Last: `dayCapacity.plannedMinutes + untimedPlannedMinutes`. `withHours` setzt auch `blockMinutes`.

## Tasks

### Task 1: Kernrechnung ohne Abzug

Dateien: `Capacity.swift`, `AIPlanning.swift` (nur `init`), `CapacityRulesTests.swift`, `PlanDayTests.swift`, `PlanningModel.swift:1916–1936` (nur `untimedCount`), `PlanningModelTests.swift`, `CapacityTextTests.swift`.

Neue Tests in `CapacityRulesTests` (Fenster 540..<1080, Pause 720..<780, Puffer 10):

| Test | Eingabe | Erwartung |
|---|---|---|
| `reportedDay_untimedTasksUseNoFreeTime` | belegt `[720..<840]`, untimed 180, count 6, estimated 6, now 804 | verfügbar 400, eingeplant 0, frei 400, `remainingMinutes` 230, `untimedMinutes` 180, `untimedCount` 6, Überhang 0, nicht überbucht, `eventMinutes` 80, `lunchMinutes` 60 |
| `untimedTasks_exceedTheTimeStillFree` | wie oben, now 960 | `remainingMinutes` 120, Überhang 60 |
| `untimedTasks_futureDay_compareWithTheWholeDay` | belegt `[720..<840]`, untimed 450 | frei 400, Überhang 50 |
| `untimedTasks_afterWork_exceedCompletely` | untimed 90, now 1140 | `remainingMinutes` 0, Überhang 90 |
| `dayOff_untimedTasksAreNoOverbooking` | `hours: nil`, untimed 30 | frei 0, nicht überbucht, `untimedMinutes` 30 |
| `dayOff_blocksStillCountAsTooMuch` | `hours: nil`, Block `[600..<660]` | eingeplant 60, frei −60, überbucht |

Geänderte Erwartungen (Werte am Code prüfen):
- `PlanDayTests.capacity_untimedAndBlocksAreLoad` → `capacity_onlyBlocksAreLoad`.
- `PlanDayTests.capacity_overbooked` → `capacity_untimedBeyondTheDay_isNoOverbooking`.
- `PlanDayTests.capacity_withNow_subtractsUntimedInFullAndBlocksAhead` → `capacity_withNow_countsBlocksAheadOnly`.
- `PlanDayTests.capacity_dayOff`: `!isOverbooked`.
- `CapacityRulesTests.blocksAndTasksWithoutTime_addUp` → `tasksWithoutTime_addNothingToTheBlocks`.
- `CapacityRulesTests.blocksBeyondTheDay_areOverbooked` → an neue Regel anpassen.
- `CapacityRulesTests.breakdown_partsAddUpToWindow`: ohne `untimedMinutes`.
- `planInput_loadCountsBlocksOnceAndTasksWithoutTime`, `planInput_withHours_countsBlocksInTheNewHours`: bleiben unverändert (KI-Last).
- `PlanningModelTests` an `:123–125, 153, 194, 242, 253, 255, 264, 272`: `capacity.plannedMinutes` nur Blöcke, `capacity.untimedMinutes` trägt die Aufgaben; Testnamen „…AsLoad“ → „…AsUntimedEffort“.
- `CapacityTextTests.explanation_*` entsprechend.

- [ ] Tests schreiben, Fehlschlag ansehen.
- [ ] `capacity(_:)` umbauen, `PlanInputDay.init` Last erhalten, `PlanningModel.dayPlan` `untimedCount` übergeben.
- [ ] `swift test` im Paket, dann `TAGWERK_SKIP_UI_TESTS=1 app/test-all.sh`.
- [ ] Commit `fix: stop subtracting tasks without a time block from free time`.

### Task 2: Freie Zeit aus `PlanInputDay` für Abendzeile, Routinen und Vorschau

- [ ] Tests: `planInput_freeMinutes_ignoreTasksWithoutTime`, `planInput_withHours_…` ergänzt, `PlanningModelTests` Abendzeile (`freeMinutes == 480`), `freeAfterAccepting_subtractsTheSuggestedBlocks`, `leftoverTargetCapacity_ignoresTasksWithoutTime`, `RoutinesModelTests.overview_…`.
- [ ] `PlanInputDay.blockMinutes`/`freeMinutes`; Abendzeile, `leftoverTargetCapacity`, `RoutinesModel.overview` nutzen `input.freeMinutes`; `freeAfterAccepting` ohne `counted`.
- [ ] Tests, Commit `fix: show free time without untimed tasks in evening line, routines and move preview`.

### Task 3: Hinweis auf der Tageskarte

- [ ] Tests in `CapacityTextTests`: `untimedHint_reportedDay_fitsIntoTheTimeStillFree`, `untimedHint_today_exceeds`, `untimedHint_futureDay_fitsAndExceeds`, `untimedHint_singular`, `untimedHint_withoutTasks_isNil`, `untimedHint_dayOff_namesOnlyTheEffort`, `estimateNote`, `summary_dayOffWithUntimedTasksOnly_isNoWorkday`.
- [ ] `CapacityText.untimedHint(_:)`, `CapacityText.estimateNote(_:)`; `DayView.details` zeigt beide (nicht an vergangenen Tagen), alte Zeile entfällt; bei Überhang `redText`.
- [ ] `DayView:272`: `showsLeftoverLine(overbooked: plan.capacity.untimedMinutes > plan.capacity.freeMinutes)`.
- [ ] Strings in Katalog und `en.json`, alten Schlüssel entfernen, `AuditAllowlist` anpassen, beide Prüfskripte.
- [ ] Tests, Commit `feat: show tasks without a time as a hint on the day card`.

### Task 4: Woche, Monat, Seitenvorschau, Assistent

- [ ] Tests: `untimedCompact_fits`, `untimedCompact_exceeds`, `untimedCompact_withoutTasks_isNil`, `summaryWithUntimed_joinsBoth`, Kontextzeile des Assistenten.
- [ ] `CapacityText.untimedCompact(_:)`, `summaryWithUntimed(_:)`; Woche/Vorschau rot bei `isOverbooked || untimedOverflowMinutes > 0`; Monat Tageskopf und VoiceOver; Assistent nutzt `capacity.untimedCount`.
- [ ] Strings, Prüfskripte, Tests, Commit `feat: name tasks without a time in week, month and assistant context`.

### Task 5: Abschluss

- [ ] `2026-11-21-kapazitaet.md`: Hinweis „Regel 11 bis 13 ersetzt durch `2026-11-28-ungeplante-aufgaben.md`“.
- [ ] Voller Lauf `app/test-all.sh`; `AuditAllowlist` nachziehen.
- [ ] Commit `docs: record the rule for tasks without a time block`.

## Gerätechecks

1. Gemeldeter Tag: „noch frei“ = Fenster ab jetzt minus Termin und Pause; „ganzer Tag 6 h 40 frei von 6 h 40“; Hinweis nennt 6 Aufgaben, 3 h.
2. Eine Aufgabe ins Raster ziehen: freie Zeit sinkt um die Blockdauer, Hinweis nennt 5 Aufgaben.
3. Spät am Tag: Hinweis „… mehr als noch frei“, rot.
4. Woche und Monat: gleiche Zahlen; Kurzhinweis bricht bei großer Schrift nicht ab.
5. Aufgabenliste: „heute noch … frei“ gleich der Karte.
6. Abendzeile und Routinen-Überblick ohne Abzug.
7. „Tag planen“: „nach dem Übernehmen … frei“ gleich der Karte danach.
8. Englisch und VoiceOver.

## Risiken

- „Zu viel“ verschwindet an Arbeitstagen ohne Zeitblöcke; Rot in Woche/Vorschau hängt am Überhang.
- Der Balken zeigt nur Zeitblöcke (O5).
- Die KI kann weiter „zu viel“ melden oder verschieben, während die Karte freie Zeit zeigt (O1).
- Woche für heute: `summary` nennt den ganzen Tag, der Überhang rechnet gegen „noch frei“.
- Karte wird bis zu zwei Zeilen höher.

## Offene Punkte (Vorgaben übernommen)

- **O1 · KI-Last:** unverändert, Aufgaben ohne Uhrzeit bleiben Last für die KI-Prüfungen.
- **O2 · „Alles auf morgen“:** Vorschau nutzt `freeMinutes` ohne vorhandene Aufgaben ohne Uhrzeit.
- **O3 · Ablage:** unverändert; Hinweis zählt ohne wiederkehrende Aufgaben.
- **O4 · Freier Tag:** Hinweis ohne Vergleich, Überschrift bleibt „kein Arbeitstag“.
- **O5 · Balken:** nur Zeitblöcke.
- **O6 · „Unerledigtes verschieben“:** erscheint, wenn die Aufgaben den ganzen Tag übersteigen (oder wie bisher am späten Nachmittag).
