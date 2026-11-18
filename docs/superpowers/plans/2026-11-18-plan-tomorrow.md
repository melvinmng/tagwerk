# Morgen planen (MP2) und Scrollen über Terminen (SR1) – Implementation Plan

> **Status:** Entwurf, freigegeben 18.11.2026. Nichts ist umgesetzt, gebaut oder am Gerät geprüft.

**Goal:**

1. In der Tagesansicht von „Planen“ lässt sich der nächste Tag (und jeder künftige Tag) so planen wie der heutige: von Hand und durch die KI.
2. Das Stundenraster scrollt auch, wenn der Finger auf einem Termin oder Zeitblock beginnt. Tipp (öffnen) und 0,3 s Halten mit Ziehen (verschieben) bleiben.

**Mockup:** `docs/superpowers/mockups/2026-11-18-plan-tomorrow-mockups.html` (MP0 Ist-Zustand, MP2 Empfehlung (vorläufig, freigegeben 18.11.2026), MP1 kleinere Lösung, MP3 spätere Ausbaustufe, SR1 Gestenablauf).

**Tech Stack:** Swift 6, SwiftUI (iOS 27), Swift Testing.

**Nicht in diesem Plan:** geführtes Blatt (MP3), Mitteilung am Abend, Vorschläge im Raster ziehen (VM1), Änderungen am Wochen- und Monatsplan der KI außer Schritt 6.

**Belegstand:** Der Befund stammt aus dem Quelltext des Zweigs `feature/recurrence-editor` (Zeilenangaben von dort). Die Ursache des Scroll-Problems ist eine Annahme über das Vorrangverhalten von SwiftUI-Gesten; Schritt 8 prüft sie vor dem Umbau. Wie gut die KI einen ganzen künftigen Tag plant, ist ungeprüft.

## Ausgangslage (Befund)

Es gibt keine eigene „Heute“-Seite; „Heute“ ist die Tagesansicht mit `anchor == today`. Am künftigen Tag gehen bereits: Kapazitätskarte mit „✦ Tag planen“ (`DayView.swift:185–188`, `AIPlanBar.swift:153–156`), Vorschläge im Raster, Panel „Ohne Uhrzeit“ mit Ziehen, Deadline-Karte. Eine „Jetzt“-Linie gibt es im Raster nicht.

| Nr. | Stelle | Ist |
|---|---|---|
| F1 | `PlanningModel.swift:1181–1187` | „Am Tag fällig, nicht zugeordnet“ (`openToday`) wird nur für heute gebildet. An künftigen Tagen fehlen diese Aufgaben in Panel, Liste und Last. |
| F2 | `DayGridScreen.swift:136–138`, `DayView.swift:271` | „Überfällig“ nur am heutigen Tag. |
| F3 | `DayGridScreen.swift:248`, `DayView.swift:307`; Texte `DayGridScreen.swift:156`, `389`, `DayView.swift:257`, `266` | Knopf „Heute“ legt immer auf `model.today`; Texte nennen fest „heute“. |
| F4 | `AIPlanner.swift:642` | Aufwand wiederkehrender Erinnerungen kommt von `planning.today`, nicht vom geplanten Tag. |
| F5 | `AIPlanning.swift:229–236`, `257–258`, `302` | Auswahlfenster, Tagesanteil und Reihenfolge rechnen ab heute. |
| F6 | `AIPlanning.swift:730`, `814–823` | Ein Block morgen für eine heute fällige Aufgabe wird bis Mitternacht als „nach der Fälligkeit“ abgelehnt. |
| F7 | `AIPlanner.swift:83–85`, `611–619`; `PlanSuggestion.swift:140–149` | Nur Stapel desselben Tages werden berücksichtigt. Eine Aufgabe mit offenem Vorschlag für heute kann morgen erneut vorgeschlagen werden. |
| F8 | `TaskContextMenu.swift:76–77` | „Mit KI planen“ springt immer auf heute. |
| F9 | `AIPlanner.swift:238`, `302`; `AIPlanBar.swift:15–18` | Nebenbefund: „Alle übernehmen“ und „Verwerfen“ wirken auf alle Stapel des gezeigten Bereichs, also in der Tagesansicht auch auf einen offenen Wochen- oder Monatsplan; gezählt werden nur Tagesvorschläge. Nicht nachgestellt. |
| F10 | `DayView.swift:214–216` | Nebenbefund: „nach dem Übernehmen … frei“ zieht die Vorschlagsminuten von der freien Zeit ab, auch wenn die Aufgabe schon als Last gezählt ist (doppelt). Wird mit F1 an künftigen Tagen sichtbarer. |
| F11 | `TimelineCanvas.swift:202`, `230–248` | Bewegliche Einträge tragen `.gesture(LongPressGesture(0,3 s).sequenced(before: DragGesture(minimumDistance: 0)))`. Leere Fläche (`68–70`), gesperrte Termine und Einträge im Modus „Auswählen“ tragen sie nicht; Vorschlagsblöcke haben Tipp und Halten-Menü (`SuggestionViews.swift:115–118`). |
| F12 | `TimelineCanvas.swift:128`, `240–242` | Das Scrollen wird erst mit der ersten Ziehbewegung nach dem Halten gesperrt (`isDragging` folgt `session`). |
| F13 | `docs/superpowers/specs/2026-11-17-phase-2b-design.md:232` | Entwurf G1 verlangt: „Wischen scrollt“, erst Halten greift. Das Ist weicht ab. |

## Zielregeln

- **Geplanter Tag:** Ein Tagesplan rechnet Fenster, Tagesanteil und Reihenfolge ab dem geplanten Tag. „Überfällig“ bleibt am echten Heute gemessen.
- **Heute ist vorbei:** wahr, wenn heute frei ist oder die Uhrzeit das heutige Arbeitsende erreicht hat. Nur dann: Einstieg „☾ Morgen planen“, Abschnitt „Von heute übrig“, und die KI darf heute Fälliges und heute Geplantes auf den geplanten Tag legen.
- **Von heute übrig:** offen, heute geplant oder heute fällig (ohne spätere Zuordnung), ohne künftigen Zeitblock. Nichts wird still verschoben.
- **Kein Doppel:** Aufgaben mit offenem Block- oder Verschiebe-Vorschlag eines anderen Tages nimmt ein neuer Tagesplan nicht auf.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `app/Packages/TagwerkCore/Sources/TagwerkCore/AIPlanning.swift` | `PlanInput.earliestWorkDay` (Standard: `today`); `makePlanInput` rechnet für `.day` ab dem geplanten Tag; Aufgaben mit Zuordnung vor `earliestWorkDay` gelten als liegen geblieben; `isLate` ignoriert Grenzen vor `earliestWorkDay`. |
| `app/Tagwerk/Planning/PlanningModel.swift` | `openToday` zu „am Tag fällig, nicht zugeordnet“ für jeden Tag ab heute; `isTodayOver`; `leftFromToday`; `nextPlanDay` (nächster Arbeitstag innerhalb von fünf Tagen). |
| `app/Tagwerk/Planning/DayPanelText.swift` (neu) | Reine Texte: Knopftitel („Heute“ / „Morgen“ / „Einplanen“), Abschnittstitel, Pausenzeile, Titel des Planen-Knopfs. |
| `app/Tagwerk/Planning/DayGridScreen.swift` | Abschnitte „Von heute übrig“ und „Überfällig“ nach Regel; Knopf legt auf `plan.day`; „Alle auf morgen“. |
| `app/Tagwerk/Planning/DayView.swift` | `TaskSections` wie das Panel; Abend-Zeile in `CapacityCard`; Rechnung F10. |
| `app/Tagwerk/Planning/AIPlanBar.swift` | Titel „Morgen planen“ am Tag nach heute; „Alle übernehmen“ und „Verwerfen“ mit Bereich. |
| `app/Tagwerk/AI/AIPlanner.swift` | Aufwand des geplanten Tages (F4); `earliestWorkDay` setzen; Ausschluss F7; `acceptAll(scope:)`, `dismissAll(scope:)` (F9). |
| `app/Tagwerk/Tasks/TaskContextMenu.swift` | „Mit KI planen“ nutzt den gezeigten Tag, wenn die Tagesansicht einen Tag ab heute zeigt. |
| `app/Tagwerk/Planning/HoldMoveState.swift` (neu) | Reiner Zustand der Halten-und-Ziehen-Geste. |
| `app/Tagwerk/Planning/TimelineCanvas.swift` | Geste nach Weg A; bei Bedarf Weg B. |
| `app/Tagwerk/Localizable.xcstrings`, Katalog von TagwerkCore | Neue Texte, Deutsch und Englisch. |
| `docs/superpowers/specs/2026-11-17-phase-2b-design.md` | §13.9 und §13.15 nach Freigabe ergänzen. |
| Tests | `AIPlanningTests.swift`, `PlanningModelTests.swift`, `AIPlannerTests.swift`, neu `DayPanelTextTests.swift`, `HoldMoveStateTests.swift`. |

## Tasks

Jeder Schritt: erst die Tests schreiben und scheitern sehen, dann umsetzen. Uhr und Kalender kommen über die vorhandenen Einspritzpunkte (`now`, `calendar`).

### Teil A · Morgen planen

**1. Kern: geplanter Tag und `earliestWorkDay`** (`AIPlanningTests`)

- [ ] `dayPlanForTomorrow_usesWindowFromPlannedDay`
- [ ] `dayPlanForTomorrow_sessionShareCountsDaysFromPlannedDay`
- [ ] `dayPlanForTomorrow_skipsTasksAssignedToToday_whileTodayHasWorkTime`
- [ ] `dayPlanForTomorrow_includesTodaysLeftovers_whenTodayIsOver`
- [ ] `validate_blockTomorrowForTaskDueToday_rejectedWhileTodayHasWorkTime`
- [ ] `validate_blockTomorrowForTaskDueToday_acceptedWhenTodayIsOver`
- [ ] `validate_blockTomorrowBeforeCurrentClockTime_accepted` (sichert das heutige Verhalten)
- [ ] Bestehende Tests für heute bleiben unverändert grün.

**2. Modell: künftige Tage** (`PlanningModelTests`)

- [ ] `futureDay_listsTasksDueThatDay_andCountsTheirLoad`
- [ ] `futureDay_dueTaskAssignedToAnotherFutureDay_notListedTwice`
- [ ] `isTodayOver_afterWorkEnd_andOnDayOff`
- [ ] `leftFromToday_onlyWhenTodayIsOver_withoutFutureBlocks`
- [ ] `nextPlanDay_skipsDaysOff_withinFiveDays`
- [ ] Wirkung auf Woche und Monat prüfen: Kapazitäten künftiger Tage sinken um am Tag Fälliges (offene Entscheidung 11).

**3. Texte** (`DayPanelTextTests`)

- [ ] `commitTitle_today_tomorrow_later`
- [ ] `dueSectionTitle_today_tomorrow_later`
- [ ] `lunchLine_namesTheShownDay`
- [ ] `planTitle_tomorrowSaysMorgenPlanen`

**4. Ansichten**

- [ ] `DayGridScreen` und `TaskSections`: Abschnitte nach Zielregeln, Knopf legt auf `plan.day`, „Alle auf morgen“ nutzt `moveTask` (Blöcke gehen mit, „Widerrufen“ bleibt).
- [ ] `CapacityCard`: Zeile „☾ Morgen planen“, wenn `isTodayOver` und `nextPlanDay` vorhanden; Tipp setzt nur `anchor`.
- [ ] `PlanningModelTests`: `assignFromPanel_usesShownDay`.

**5. KI für den geplanten Tag** (`AIPlannerTests`)

- [ ] `planTomorrow_usesRecurringEffortOfPlannedDay`
- [ ] `planTomorrow_keepsTodaysBatch`
- [ ] `planTomorrow_excludesTasksWithOpenSuggestionForToday`
- [ ] `planTomorrow_carriesTodaysLeftovers_onlyWhenTodayIsOver`
- [ ] `contextMenuPlanAnchor_usesShownFutureDay` (reine Funktion)
- [ ] Anweisungstext um einen Satz zum geplanten Tag ergänzen; Wirkung nur mit echter KI prüfbar.

**6. Nebenbefunde F9 und F10**

- [ ] F9 erst als Test nachstellen: `acceptAll_dayScope_leavesWeekBatchUntouched`, `dismissAll_dayScope_leavesWeekBatchUntouched`. Bestätigt der Test den Befund nicht, entfällt der Schritt.
- [ ] F10: `freeAfterAccepting_doesNotCountReplacedLoadTwice`.

**7. Texte und Entwurf**

- [ ] Kataloge pflegen (Deutsch, Englisch), `LocalizedTests` grün.
- [ ] Entwurf §13.9 und §13.15 ergänzen.

### Teil B · Scrollen über Terminen

**8. Prüfung am Gerät ohne Codeänderung (Abbruchkriterium)**

- [ ] Wischen ab beweglichem Termin, Zeitblock, Mittagspause: scrollt nicht (erwartet).
- [ ] Wischen ab gesperrtem Termin (🔒) und im Modus „Auswählen“ ab jedem Termin: scrollt (erwartet).
- [ ] Wischen ab Vorschlagsblock: Ergebnis festhalten.
- [ ] Stimmt das Muster nicht, ist die Annahme widerlegt: Ursache neu suchen (`onTapGesture`, Seitenwisch `DayGridScreen.swift:61`), Schritte 9 bis 11 anpassen.

**9. Reiner Gestenzustand** (`HoldMoveStateTests`)

- [ ] `idle_doesNotBlockScroll`
- [ ] `held_blocksScroll_beforeAnyMovement`
- [ ] `moving_accumulatesDelta`
- [ ] `ended_orCancelled_returnsToIdle`

**10. Weg A in `TimelineCanvas`**

- [ ] `.simultaneousGesture(moveGesture)` statt `.gesture(…)` (`TimelineCanvas.swift:202`).
- [ ] „Gehalten“ als `@GestureState` (setzt sich bei Abbruch selbst zurück); `isDragging` meldet `gehalten || session != nil`, damit `scrollDisabled` (`DayGridScreen.swift:60`) schon nach 0,3 s greift.
- [ ] Tipp-Logik (`tap`, `selectedAt`) und Griffe bleiben.

**11. Abnahme am Gerät; Weg B bei Bedarf**

- [ ] Wischen ab Termin, Block, Pause, Vorschlag, leerer Fläche scrollt; Tipp öffnet; Halten und Ziehen verschiebt ohne Mitscrollen; Griffe; Rand-Scrollen beim Ziehen aus dem Panel; waagerechter Tageswechsel ab einem Termin; Listenmodus; VoiceOver.
- [ ] Scrollt das Raster beim Verschieben mit oder wird das Halten nicht erkannt: Weg B. Halten als `UILongPressGestureRecognizer` (0,3 s, 10 pt) über `UIGestureRecognizerRepresentable`; `.began` greift, `.changed` liefert die Verschiebung, `.ended` und `.cancelled` schließen ab. Der Zustand aus Schritt 9 bleibt.

## Risiken

- **Last an künftigen Tagen:** F1 ändert Kapazitäten in Woche und Monat und die Eingabe des Wochenplans der KI. Abweichung von §13.9; braucht die Freigabe aus Entscheidung 11.
- **KI-Qualität:** Regeln und Prüfungen sind testbar, die Güte der Vorschläge für einen ganzen freien Tag nicht. Nach Schritt 5 mit echten Daten ansehen.
- **`earliestWorkDay`:** falsch gesetzt, erlaubt es Blöcke nach der Fälligkeit. Deshalb nur für Tagespläne künftiger Tage und nur bei `isTodayOver`; Wochen- und Monatsplan bleiben unberührt.
- **Sitzungsfortschritt:** „Noch einzuplanen“ rechnet das Fenster wiederkehrender Erinnerungen für heute (`PlanningModel.swift:884–902`); am morgigen Tag kann die Restzeit einer täglichen Erinnerung abweichen. Beobachten, nicht in diesem Plan.
- **Panelhöhe:** vier Abschnitte können das Panel füllen; es scrollt bereits (`DayGridScreen.swift:152–163`), die Bedienbarkeit ist am Gerät zu prüfen.
- **Gesten:** Vorrang zwischen SwiftUI-Gesten und Scrollen ist nicht dokumentiert belegt und unter iOS 27 ungeprüft. Weg A kann Scrollen und Verschieben gleichzeitig auslösen; Weg B ist der vorbereitete Rückfall.
- **Mitternacht:** „heute“ wechselt, während die Ansicht offen ist; Abschnitte und Titel hängen an `model.today` und müssen beim nächsten `reload()` stimmen (Test mit gestellter Uhr in Schritt 2).

## Offene Entscheidungen (Vorschlag in Klammern)

1. Variante (MP2).
2. Gleichstellung nur für morgen oder für jeden künftigen Tag? (jeder künftige Tag; Abend-Einstieg und „Von heute übrig“ nur für den Tag nach heute)
3. „Überfällig“ an künftigen Tagen? (heute und morgen ja, später nein)
4. Auslöser für „☾ Morgen planen“? (heute keine Arbeitszeit mehr oder heute frei; keine feste Uhrzeit, keine Mitteilung)
5. Ziel, wenn morgen frei ist? (nächster Arbeitstag innerhalb von fünf Tagen)
6. Darf die KI heute Fälliges und heute Geplantes auf morgen legen? (ja, sobald heute vorbei ist; vorher nicht)
7. Aufgaben mit offenem Vorschlag für heute? (auslassen)
8. Titel: „✦ Morgen planen“, Zeilenknopf „Morgen“, später „Einplanen“? (ja)
9. Scroll-Korrektur: erst Weg A, bei Konflikten Weg B? (ja)
10. F9 und F10 in diesem Plan beheben? (ja, F9 nur nach bestätigendem Test)
11. Zählt am Tag Fälliges an künftigen Tagen als Last, auch in Woche und Monat? (ja)

## Entscheidungen (18.11.2026, freigegeben)

1. Variante MP2.
2. Jeder künftige Tag wird gleichgestellt; Abend-Einstieg und „Von heute übrig“ nur für den Tag nach heute.
3. „Überfällig“ heute und morgen, später nicht.
4. „☾ Morgen planen“ erscheint, sobald heute keine Arbeitszeit mehr bleibt oder heute frei ist; keine feste Uhrzeit, keine Mitteilung.
5. Ist morgen frei, führt der Einstieg zum nächsten Arbeitstag innerhalb von fünf Tagen.
6. Die KI darf heute Fälliges und heute Geplantes auf morgen legen, sobald die heutige Arbeitszeit vorbei ist; nichts wird still verschoben.
7. Aufgaben mit offenem Vorschlag für heute werden beim Planen von morgen einbezogen (Abweichung vom Vorschlag).
8. Beschriftung „✦ Morgen planen“, Zeilenknopf „Morgen“, an späteren Tagen „Einplanen“.
9. Scrollen über Terminen direkt mit dem UIKit-Erkenner (Weg B), nicht erst Weg A (Abweichung vom Vorschlag).
10. Beide Nebenbefunde mitbeheben („Alle übernehmen“/„Verwerfen“ nur nach bestätigendem Test).
11. Am Tag Fälliges zählt an künftigen Tagen als Last, auch in Woche und Monat (Vorschlag).
