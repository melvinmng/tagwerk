# Tageskapazität richtig rechnen – Implementation Plan (Entwurf)


> **Stand 21.11.2026 (Nutzer):** KA6a gewählt. Ursache der 3 h 10 bestätigt: Arbeitszeit am Dienstag ist die normale; wiederkehrende Aufgabe „Karteikarten“ mit 4 h reserviertem Aufwand (7 h 40 − 4 h 30 = 3 h 10). **KA3 entschieden:** Reservierter Aufwand wiederkehrender Aufgaben verringert die freie Zeit gar nicht mehr; Zeit wird erst abgezogen, wenn Zeitblöcke gebucht sind (strenger als KA3a: auch kein Abzug als „eingeplant“). KA1, KA2, KA4, KA5 noch offen. Task 0 entfällt.

> **For agentic workers:** Dieser Plan ist ein **Entwurf vor den Entscheidungen des Nutzers**. Kein Task wird begonnen, bevor die Entscheidungen im Abschnitt „Entscheidungen des Nutzers“ getroffen und hier eingetragen sind. Jeder Task nennt unter „Hängt ab von“ die Kürzel, gegen deren Empfehlung er geschrieben ist; fällt eine Entscheidung anders aus, wird der Task vor der Umsetzung überarbeitet. Danach gilt: Task für Task, jeweils mit TDD, Schritte als Checkbox (`- [ ]`).

> **Status:** Stand 21.11.2026, Code-Grundlage `origin/main` bei `85c982b` (enthält PR #257). Mockups: `docs/superpowers/mockups/2026-11-21-kapazitaet-mockups.html` (Kürzel KA, nur KA6 hat ein Bild). Nichts davon ist gebaut, nichts am Gerät geprüft, kein Test wurde für diesen Plan ausgeführt. Es gibt noch kein Issue zu diesem Vorhaben.

**Anlass (Wortlaut des Nutzers):** „Ich glaube die Zeitberechnung ist bisher falsch. … Eigentlich müsste der ganze Tag außer die eine Stunde Mittagspause als frei gezählt werden. Überschneidende Termine dürfen nicht doppelt zählen.“

**Gemeldeter Tag (zwei Bildschirmfotos, englische Oberfläche, Di. 24. Nov., „in 3 days“):** Karte „3 h 10 free of 3 h 10“. Ganztägig „Away“ und „Oma Bärbel's 66th Birthday“. „Selbststudium“ 8:00–18:00 gestrichelt mit „Fr…“ (frei). „Away“ 12:00–13:00 (blau, belegt). „Lunch break“ 12:00–13:00 (grau). „RT Young Generation“ 18:30–22:00 „Free“ mit Schloss (gestrichelt).

**Goal:**
- Jede Minute der Arbeitszeit zählt höchstens einmal: als blockiert (Pause, Fahrzeit, Termin samt Puffer), als Zeitblock oder als frei.
- Der gemeldete Tag ergibt bei Arbeitszeit 9:00–18:00 „8 h frei von 8 h“, wenn nichts reserviert oder eingeplant ist.
- Die Karte sagt, was abgezogen wurde. Eine Zahl wie „3 h 10“ ist ablesbar erklärt.
- Tag, Woche, Monat, Aufgabenliste, Abendzeile, Routinen-Überblick, Assistent und KI-Planung rechnen mit derselben Funktion.

**Architecture:**
- **`TagwerkCore`, `Capacity.swift`:** `capacity(_:)` bleibt der einzige Einstieg. `CapacityInput` bekommt die Zeitblöcke als Intervalle (`blockIntervals`) und die Last ohne Uhrzeit getrennt (`untimedPlannedMinutes`); `DayCapacity` bekommt eine Aufschlüsselung (`CapacityBreakdown`). Neue reine Funktion `freedMinutes(_:removing:)` für „Frei gibt … frei“.
- **`TagwerkCore`, `AIPlanning.swift`:** `PlanInputDay` baut seine `CapacityInput` an einer Stelle; `freeGaps` nutzt dieselbe Liste blockierter Intervalle wie `capacity(_:)`.
- **App:** `PlanningModel.dayPlan` übergibt Intervalle statt Summen. `CapacityText` bekommt `explanation(_:hours:)`. Kein neues SwiftData-Modell, keine neue Einstellung.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), Swift Testing, XcodeGen. Keine neue Paketabhängigkeit.

**Issues:** noch keines. **Branch (Vorschlag):** `fix/day-capacity`, ein Pull Request.

## Global Constraints

- **Strings:** Deutsch ist Quellsprache. Jeder neue Text steht deutsch und englisch im Katalog und in `scripts/translations/en.json`; prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs und Testnamen englisch.
- **Eine Rechnung:** Keine Ansicht rechnet freie Zeit selbst. Jede Zahl kommt aus `capacity(_:)` oder `freedMinutes(_:removing:)`.
- **Quellverträglich:** Neue Felder von `CapacityInput` haben Vorgabewerte im `init`, damit Strang V (`TravelCapacityTests`, Rückweg) und #256 ohne Änderung weiter übersetzen.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** `app/test-all.sh` nach jedem Task mit `TAGWERK_SKIP_UI_TESTS=1`; voller Lauf am Ende des Strangs und vor dem Merge.

## Ausgangslage (Befunde aus dem Quelltext, `origin/main` `85c982b`)

Pfade unter `app/`, sofern nicht anders genannt.

### Wie „frei von“ heute entsteht

1. **Tagesfenster.** `workHours(on:schedule:overrides:calendar:)` nimmt die Abweichung für das Datum, sonst den Wochentag; ohne Eintrag ist der Tag frei (`Packages/TagwerkCore/Sources/TagwerkCore/WorkSchedule.swift:37–44`). Vorgabe ist Montag bis Freitag 9:00–18:00 (`:24–27`; `AppSettings.weekSchedule`, `Tagwerk/Persistence/AppSettings.swift:244–247`). Heute und künftige Tage nutzen dasselbe Fenster; „in 3 Tagen“ ändert nichts an der Rechnung.
2. **Blockierte Zeit.** `capacity(_:)` weitet jeden belegten Termin um den Puffer auf beiden Seiten (`Capacity.swift:57`, Vorgabe 10 min, `AppSettings.swift:13`), fügt die Pause (`:58–60`, Vorgabe 12:00–13:00, `AppSettings.swift:11–12`; je Tag überschreibbar, `PlanningModel.swift:836–839`) und die Fahrzeit ohne Puffer (`:61`) hinzu, schneidet alles auf die Arbeitszeit zu und nimmt die **Länge der Vereinigung** (`:62–63`, `mergedLength`, `:99–111`). Überschneidende Termine zählen hier also schon einmal.
3. **Gesamtzahl.** `availableMinutes = Arbeitszeit − blockiert − recurringMinutes` (`Capacity.swift:64`). Der reservierte Aufwand wiederkehrender Aufgaben kürzt damit die Zahl hinter „von“, ohne dass die Karte ihn nennt.
4. **Frei.** `freeMinutes = availableMinutes − plannedMinutes` (`:65–67`).
5. **Heute.** Mit `nowMinutes` zählt für „noch frei“ nur das Fenster ab jetzt; der reservierte Aufwand wird trotzdem ganz abgezogen (`:68–74`).
6. **Welche Termine belegt sind.** `busyIntervals` nimmt nur Termine mit Uhrzeit, mit `isBusy` und ohne Verknüpfung zu einer Aufgabe, zugeschnitten auf den Kalendertag (`Capacity.swift:79–92`). Termine über Mitternacht zählen an jedem Tag mit ihrem Teil.
7. **`isBusy`.** `event.availability != .free && !declined` (`Packages/RemindersKit/Sources/RemindersKit/EventKitGateway.swift:519, 534`): „frei“ und abgesagte Einladungen zählen nicht; „belegt“, „mit Vorbehalt“, „abwesend“ und „nicht unterstützt“ zählen. Die Marke „Frei/Belegt“ in Tagwerk gewinnt über den Kalender (`PlanningModel.swift:981–986`).
8. **Ganztägige Termine** zählen nie (`Capacity.swift:85`), auch nicht „Away“ mit Verfügbarkeit „abwesend“.
9. **Private oder gesperrte Termine.** `busyIntervals` liest kein Privat- oder Sperrmerkmal; das Schloss im Bild hat auf die Rechnung keine Wirkung. Was das Schloss genau anzeigt, wurde nicht nachgelesen.
10. **Mehrere Kalender.** Als Duplikat zusammengefasste Kopien werden vor der Rechnung entfernt (`PlanningModel.swift:1004–1008`); nicht zusammengefasste Kopien fallen durch die Vereinigung zusammen.
11. **Eingeplantes.** `planned` ist die **Summe** der Dauern aller Zeitblöcke des Kalendertags (`PlanningModel.swift:1766–1769`) plus Aufwand der Aufgaben ohne Block, ohne Aufwand mit Standarddauer 30 min (`:1772–1779`).
12. **Reservierter Aufwand.** `efforts.reservedMinutes` summiert den Aufwand aller wiederkehrenden Aufgaben, die an dem Tag vorkommen und nicht erledigt sind (`Tagwerk/Planning/RecurringEffortStore.swift:142–148`); abgezogen wird, was Blöcke derselben Aufgabe schon decken (`PlanningModel.swift:1790–1794`). Die Quelle sind Erinnerungen mit Wiederholung aus **allen** Listen und wiederkehrende lokale Aufgaben (`:1727–1736`).
13. **Fahrzeit** (bereits auf `main`): Segmente vor belegten Terminen mit Ort, als `travelIntervals` (`PlanningModel.swift:1795, 1802`; `TravelRules.swift:186–246`).
14. **Anzeige.** `CapacityText.summary`: „X frei von Y“, „… zu viel“, „kein Arbeitstag“ (`Tagwerk/Planning/CapacityBar.swift:27–31`); heute `remaining` (`:34–39`). Die Karte im Tag: `DayView.swift:341–369`.

### Wer die Zahl noch nutzt

| Ort | Stelle | Rechnung |
|---|---|---|
| Tag, Karte | `Planning/DayView.swift:345, 351, 372–381` | `plan.capacity` |
| Woche, Monat, Seitenvorschau | `WeekView.swift:88`, `MonthView.swift:118, 137`, `DayPagePreview.swift:49` | `CapacityText.summary` |
| Aufgabenliste, Auswahl | `Tasks/TaskListView.swift:281–287` | `remainingMinutes` von heute |
| Abendzeile „Morgen planen“ | `PlanningModel.swift:1495` | `input.availableMinutes − input.plannedMinutes` aus `PlanInputDay` |
| Routinen-Überblick | `Routines/RoutinesModel.swift:252–256` | wie Abendzeile |
| Assistent, Kontextzeile | `AI/AssistantModel.swift:576–579` | `freeMinutes`, `availableMinutes` |
| KI-Planung | `AIPlanning.swift:73–77, 114–118, 929, 944–945, 1042–1058` | eigene `CapacityInput`, `freeGaps` |
| „Frei gibt … frei“ | `PlanningModel.swift:883–885`, `DayGridScreen.swift:460` | **Summe** der Termindauern |
| Widget | `TagwerkWidget/` | nutzt keine Kapazität (Suche nach `capacity`, `freeMinutes` ohne Treffer) |

## Ursache

**Die Kernrechnung summiert nicht.** `capacity(_:)` vereinigt Pause, Termine und Fahrzeit. „Away“ 12:00–13:00 und die Pause 12:00–13:00 zählen dort einmal. Die Vermutung „doppelt gezählt“ trifft auf diese Stelle nicht zu.

**Was der Code für den gemeldeten Tag rechnet (Vorgaben: Di. 9:00–18:00, Pause 12:00–13:00, Puffer 10 min):**

| Schritt | Wert |
|---|---|
| Arbeitszeit | 540 min |
| belegt: nur „Away“ 12:00–13:00 (Selbststudium und RT sind frei, ganztägige zählen nie) | mit Puffer 11:50–13:10 |
| Vereinigung mit der Pause | 80 min |
| verfügbar ohne reservierten Aufwand | 460 min = **7 h 40** |
| angezeigt | 190 min = 3 h 10 |
| Differenz | **270 min = 4 h 30** |

**Die Differenz von 4 h 30 kommt nicht aus den sichtbaren Terminen.** Der Code kennt dafür drei Wege; welcher zutrifft, lässt sich ohne die Daten des Geräts nicht entscheiden:
1. **Reservierter Aufwand wiederkehrender Aufgaben von zusammen 4 h 30** (Befund 3 und 12). Das passt zur Anzeige „frei von 3 h 10“, weil dieser Abzug die Gesamtzahl kürzt und nirgends auf der Karte steht. Er gilt unabhängig davon, ob die Aufgabe in die Arbeitszeit fällt. **Wahrscheinlichste Erklärung, nicht belegt.**
2. **Kürzere Arbeitszeit an diesem Dienstag** (Wochenplan oder Abweichung für das Datum). Beispiel: 9:00–13:30 ergibt 270 − 80 = 190 min.
3. **Fahrzeit.** Unwahrscheinlich: Im Bild ist kein Fahrzeitblock zu sehen.

**Vier Fehler, die unabhängig von der Erklärung bestehen:**
- **F1, unsichtbare Abzüge.** Die Gesamtzahl ist um reservierten Aufwand gekürzt (`Capacity.swift:64`). Die Karte nennt weder Arbeitszeit noch Abzüge. Der Nutzer kann 3 h 10 nicht nachvollziehen.
- **F2, Puffer um einen Termin in der Pause.** „Away“ liegt ganz in der Pause und kostet trotzdem 20 min (11:50–12:00, 13:00–13:10). Erwartet sind 8 h, gerechnet werden 7 h 40.
- **F3, Summen beim Eingeplanten.** Überschneidende Zeitblöcke zählen doppelt, Blöcke außerhalb der Arbeitszeit verbrauchen freie Arbeitszeit, ein Block in der Pause zählt als blockiert **und** als eingeplant (`PlanningModel.swift:1766–1769`).
- **F4, Summe bei „Frei gibt … frei“.** `busyMinutes(of:)` addiert Dauern (`PlanningModel.swift:883–885`); bei überschneidenden Terminen, Terminen außerhalb der Arbeitszeit oder in der Pause verspricht der Text mehr, als die Karte danach zeigt.

**Dazu eine Abweichung zwischen Karte und KI:** `freeGaps` weitet auch die Fahrzeit um den Puffer (`AIPlanning.swift:72, 1047`), `capacity(_:)` nicht (`Capacity.swift:61`). Für einen einzelnen Tag nennt die KI-Eingabe deshalb weniger freie Minuten als die Karte (`AIPlanning.swift:944`).

**Richtiger Wert für den gemeldeten Tag** nach den Regeln unten (Empfehlungen), Arbeitszeit 9:00–18:00:
- nichts reserviert, nichts eingeplant: **„8 h frei von 8 h“**;
- falls Erklärung 1 zutrifft (4 h 30 reserviert): **„3 h 30 frei von 8 h“** mit der Zeile „9:00–18:00 · 1 h Pause · 4 h 30 wiederkehrend“.
- Ist die Arbeitszeit des Nutzers 8:00–18:00, sind es 9 h statt 8 h.

## Regeln (Vorschlag)

Bezeichnungen: **Fenster** = Arbeitszeit des Tages. **Blockiert** = Pause, Fahrzeit, belegte Termine samt Puffer. Alle Angaben in Minuten seit Mitternacht des Kalendertags.

1. **Fenster.** Abweichung für das Datum, sonst Wochentag; ohne Eintrag „kein Arbeitstag“. Unverändert.
2. **Jede Minute einmal.** Jede Minute des Fensters gehört zu genau einer Klasse, in dieser Rangfolge: blockiert, Zeitblock, frei. Blockierte Zeit ist die Vereinigung der Intervalle, zugeschnitten auf das Fenster. Nichts wird addiert.
3. **Belegte Termine.** Belegt sind Termine mit Uhrzeit, deren Verfügbarkeit nicht „frei“ ist und die nicht abgesagt sind; „mit Vorbehalt“ und „abwesend“ zählen als belegt. Die Marke „Frei/Belegt“ in Tagwerk gewinnt. Unverändert.
4. **Puffer.** Jeder belegte Termin wird um den Puffer geweitet. Ein Termin, der ganz in der Pause oder ganz in einer Fahrzeit liegt, bekommt keinen Puffer. **(KA1)**
5. **Pause und Fahrzeit** blockieren ohne Puffer. Hin- und Rückweg (Strang V) gehen als Intervalle in dieselbe Vereinigung.
6. **Ganztägige Termine** kürzen den Tag nicht. **(KA4)**
7. **Außerhalb des Fensters** zählt nichts: Termine vor oder nach der Arbeitszeit ändern die Kapazität nicht; Termine über den Rand zählen mit dem Teil im Fenster.
8. **Über Mitternacht.** Ein Termin zählt an jedem Kalendertag mit seinem Teil dieses Tages. Fahrzeit wird an Mitternacht abgeschnitten. Unverändert.
9. **Mehrere Kalender, Duplikate.** Gleiche oder überschneidende Termine zählen einmal, ob zusammengefasst oder nicht.
10. **Gesamtzahl („von“).** Fenster minus blockierte Zeit. **(KA2)**
11. **Eingeplantes** setzt sich aus drei Teilen zusammen:
    - Zeitblöcke: Länge der Vereinigung der Blöcke im Fenster, ohne den Teil, der schon blockiert ist. Blöcke außerhalb des Fensters verbrauchen keine freie Arbeitszeit. **(KA5)**
    - Aufgaben ohne Uhrzeit: ihr Aufwand, ohne Angabe die Standarddauer. Unverändert.
    - Reservierter Aufwand wiederkehrender Aufgaben, soweit kein Block derselben Aufgabe ihn deckt. **(KA3)**
12. **Frei.** Gesamtzahl minus Eingeplantes. Negativ heißt „zu viel“.
13. **Heute, „noch frei“.** Dieselbe Rechnung im Fenster ab jetzt: blockierte Zeit ab jetzt, Blöcke ab jetzt, Aufgaben ohne Uhrzeit und reservierter Aufwand ganz. Unverändert bis auf Regel 11.
14. **„Frei gibt … frei“.** Der Wert ist die Differenz der Gesamtzahl mit und ohne die gewählten Termine, nicht die Summe ihrer Dauern.
15. **KI-Planung.** Freie Lücken und freie Minuten entstehen aus derselben Liste blockierter Intervalle; die Fahrzeit bekommt auch dort keinen Puffer. Die Lücken halten weiter Abstand (Puffer) zu vorhandenen Zeitblöcken.
16. **Erklärung.** Die Karte im Tag nennt Arbeitszeit und jeden Abzug, der an dem Tag vorkommt. **(KA6)**

## Entscheidungen des Nutzers

Noch offen. Empfehlung jeweils zuerst.

- **KA1 · Puffer um einen Termin, der ganz in Pause oder Fahrzeit liegt**
  - **KA1c (Empfehlung):** kein Puffer für solche Termine. Der gemeldete Tag ergibt 8 h. Der Puffer bleibt für alle anderen Termine.
  - KA1a: wie bisher, Puffer immer. Der gemeldete Tag ergibt 7 h 40.
  - KA1b: Puffer zählt in der Kapazität gar nicht, nur als Abstand bei der KI-Planung. Einfacher, aber volle Tage wirken freier, als sie planbar sind.
- **KA2 · Gesamtzahl „von …“**
  - **KA2a (Empfehlung):** Fenster minus blockierte Zeit („Zeit für Aufgaben“). Entspricht der bisherigen Bedeutung ohne den reservierten Aufwand; „zu viel“ und der Balken bleiben verständlich.
  - KA2b: Fenster minus Pause, fest je Tag („von 8 h“); Termine erscheinen als Verbrauch. Dann bedeutet „frei von“ etwas anderes als in Woche, Monat und KI-Eingabe; mehr Umbau.
- **KA3 · Reservierter Aufwand wiederkehrender Aufgaben**
  - **KA3a (Empfehlung):** zählt als Eingeplantes. „Frei“ bleibt gleich, die Gesamtzahl wird ehrlich, der Balken zeigt die Reservierung als Last.
  - KA3b: kürzt weiter die Gesamtzahl, steht aber in der Erklärzeile.
  - Folge von KA3a: Ein Tag, dessen Reservierung die Arbeitszeit übersteigt, zeigt „… zu viel“ statt „0 min frei von 0 min“.
- **KA4 · Ganztägige Termine**
  - **KA4a (Empfehlung):** kürzen den Tag nie. „Kein Arbeitstag“ bleibt die Handeinstellung über die Karte. Entspricht der Erwartung im gemeldeten Tag (ganztägig „Away“, trotzdem ganzer Tag frei).
  - KA4b: Ganztägige Termine mit Verfügbarkeit „belegt“ oder „abwesend“ machen den Tag zum freien Tag. Trifft Urlaub richtig, den gemeldeten Tag aber falsch.
- **KA5 · Zeitblöcke außerhalb der Arbeitszeit**
  - **KA5a (Empfehlung):** verbrauchen keine freie Arbeitszeit; die Aufgabe gilt trotzdem als eingeplant.
  - KA5b: zählen wie bisher voll. Ein Block um 19:00 senkt dann die freie Zeit von 9:00–18:00.
- **KA6 · Erklärung auf der Karte** (Mockup)
  - **KA6a (Empfehlung):** eine Zeile unter dem Balken, nur mit vorkommenden Teilen.
  - KA6b: geteilter Balken mit Legende.

## Tasks

### Task 0: Erklärung des gemeldeten Tags am Gerät klären

**Hängt ab von:** nichts. Kein Code.

- [ ] Am Gerät für Di. 24. Nov. ablesen: Arbeitszeit des Tages (Karte antippen), Wochenplan Dienstag (Einstellungen), Liste „↻ … reserviert“ im Tag, Puffer, Pause.
- [ ] Ergebnis hier eintragen. Trifft keine der drei Erklärungen zu, vor Task 1 die Rechnung mit den abgelesenen Werten als Test nachstellen.

### Task 1: Aufschlüsselung und Regeln in `capacity(_:)`

**Hängt ab von:** KA1c, KA2a, KA3a, KA5a.
**Dateien:** `Packages/TagwerkCore/Sources/TagwerkCore/Capacity.swift`, `Packages/TagwerkCore/Tests/TagwerkCoreTests/PlanDayTests.swift`, neu `…/CapacityRulesTests.swift`.

Schnittstelle:
- `CapacityInput`: neu `blockIntervals: [Range<Int>] = []`, `untimedPlannedMinutes: Int? = nil`. Ist `untimedPlannedMinutes` gesetzt, ersetzt es `plannedMinutes` als Last ohne Uhrzeit; sonst gilt `plannedMinutes` wie bisher (für bestehende Aufrufer und Tests).
- `CapacityBreakdown`: `windowMinutes`, `lunchMinutes`, `travelMinutes`, `eventMinutes` (mit Puffer), `blockMinutes`, `outsideBlockMinutes`, `untimedMinutes`, `reservedMinutes`. Die Teile sind disjunkt zugeordnet in der Rangfolge Pause, Fahrzeit, Termine; ihre Summe ist die Länge der Vereinigung.
- `DayCapacity`: neu `breakdown`. `availableMinutes = window − blockiert`, `plannedMinutes = block + untimed + reserved`.
- `remainingMinutes` rechnet die Blöcke ab jetzt selbst aus `blockIntervals`; `remainingPlannedMinutes` bleibt als Vorrang für alte Aufrufer.

Testfälle (Fenster 540..<1080, Pause 720..<780, Puffer 10, sofern nicht anders genannt):

| Test | Eingabe | Erwartung |
|---|---|---|
| `reportedDay_onlyLunchIsBlocked` | belegt `[720..<780]` | verfügbar 480, frei 480, `eventMinutes` 0, `lunchMinutes` 60 |
| `eventPartlyInLunch_keepsBuffer` | belegt `[690..<750]` | verfügbar 440 |
| `overlappingEvents_countOnce` | belegt `[600..<660, 630..<690]` | verfügbar 370 |
| `sameEventInTwoCalendars_countsOnce` | belegt `[600..<660, 600..<660]` | verfügbar 400 |
| `eventOutsideWindow_changesNothing` | belegt `[1110..<1320]` | verfügbar 480 |
| `eventAcrossWindowEnd_countsInsidePart` | belegt `[1050..<1140]` | verfügbar 440 |
| `eventInsideTravel_getsNoBuffer` | Fahrzeit `[600..<660]`, belegt `[610..<650]` | verfügbar 420 |
| `reservedEffort_isPlannedLoad` | belegt `[720..<780]`, reserviert 270 | verfügbar 480, eingeplant 270, frei 210 |
| `reservedBeyondWindow_isOverbooked` | reserviert 600 | frei −120, überbucht |
| `overlappingBlocks_countOnce` | Blöcke `[600..<660, 630..<690]` | `blockMinutes` 90 |
| `blockOutsideWindow_usesNoFreeTime` | Block `[1140..<1200]` | `blockMinutes` 0, `outsideBlockMinutes` 60, frei 480 |
| `blockInLunch_countsOnlyOutsidePart` | Block `[750..<810]` | `blockMinutes` 30, frei 450 |
| `breakdown_partsAddUpToWindow` | gemischte Eingabe | Pause + Fahrzeit + Termine + Blöcke + freie Minuten = 540 |
| `today_countsBlocksAheadOnly` | jetzt 840, Blöcke `[600..<660, 900..<960]` | `remainingMinutes` 180 |

Dazu `busyIntervals_reportedDay`: die sechs Einträge des gemeldeten Tags als `CalendarEvent` (zwei ganztägige, davon „Away“ belegt; „Selbststudium“ 8:00–18:00 frei; „Away“ 12:00–13:00 belegt; „RT Young Generation“ 18:30–22:00 frei) ergeben `[720..<780]`; und `busyIntervals_eventAcrossMidnight_isSplit` (23:00 Vortag bis 1:00 ergibt `[0..<60]`).

- [ ] Tests schreiben, Fehlschlag ansehen.
- [ ] `capacity(_:)` umbauen; `capacity_recurringAndPlanned` in `PlanDayTests` auf die neue Bedeutung anpassen (verfügbar 480, eingeplant 540, frei −60).
- [ ] `swift test` im Paket `TagwerkCore`; `TravelCapacityTests` unverändert grün.
- [ ] Commit `fix: count every minute of the working day once`.

### Task 2: `freedMinutes(_:removing:)`

**Hängt ab von:** Task 1.
**Dateien:** `Capacity.swift`, `CapacityRulesTests.swift`, `Tagwerk/Planning/PlanningModel.swift:883–885`, `Tagwerk/Planning/DayGridScreen.swift:460`.

- [ ] Tests: zwei überschneidende Termine `[600..<660, 630..<690]` geben 110 frei (nicht 120); ein Termin in der Pause gibt 0 frei; ein Termin außerhalb des Fensters gibt 0 frei.
- [ ] Funktion: `capacity(input).availableMinutes` ohne die gewählten Intervalle minus mit ihnen.
- [ ] `busyMinutes(of:)` ruft sie mit der Eingabe des Tages auf; Test in `PlanningModelTests`.
- [ ] Commit `fix: show the time a free mark really gives back`.

### Task 3: `PlanningModel.dayPlan` übergibt Intervalle

**Hängt ab von:** Task 1.
**Dateien:** `Tagwerk/Planning/PlanningModel.swift:1766–1803, 1825–1832`, `TagwerkTests/PlanningModelTests.swift`.

- [ ] Tests im Modell: der gemeldete Tag mit dem Kalender-Double ergibt „8 h frei von 8 h“; zwei überschneidende Blöcke derselben Stunde zählen 60 min; ein Block um 19:00 senkt die freie Zeit nicht; eine wiederkehrende Erinnerung mit 4 h 30 ergibt „3 h 30 frei von 8 h“.
- [ ] `blockIntervals` aus `linkedEvents`, `untimedPlannedMinutes` aus der Schleife über Aufgaben; die eigene Rechnung für `remainingPlannedMinutes` entfällt.
- [ ] `countedTaskMinutes` und `planInput` behalten ihre Werte (Test `AIPlanningTests` unverändert grün, siehe Task 4).
- [ ] Commit `fix: pass time blocks to the capacity as intervals`.

### Task 4: KI-Planung auf dieselbe Rechnung

**Hängt ab von:** Task 1, KA3a.
**Dateien:** `Packages/TagwerkCore/Sources/TagwerkCore/AIPlanning.swift:68–77, 112–120, 929, 944–945, 1042–1058`, `AIPlanningTests.swift`, `Tagwerk/Planning/PlanningModel.swift:1495`, `Tagwerk/Routines/RoutinesModel.swift:252–256`.

- [ ] `PlanInputDay` bekommt `freeMinutes` (verfügbar minus eingeplant, reservierter Aufwand eingeschlossen) als einzige Quelle; Abendzeile, Routinen-Überblick und `free(day)` nutzen sie.
- [ ] `freeGaps`: Fahrzeit ohne Puffer, Termin ganz in Pause oder Fahrzeit ohne Puffer (dieselbe Hilfsfunktion wie in `capacity(_:)`).
- [ ] Tests: Tag mit Fahrzeit `[600..<630]` nennt in der KI-Eingabe dieselben freien Minuten wie `capacity(_:)`; bestehende Erwartungen in `AIPlanningTests` bleiben, wo sie sich nicht auf den Fahrzeit-Puffer stützen (jede geänderte Erwartung im Commit begründen).
- [ ] Commit `fix: derive AI free time from the same blocked intervals`.

### Task 5: Erklärzeile auf der Karte

**Hängt ab von:** Task 1 und 3, KA6a.
**Dateien:** `Tagwerk/Planning/CapacityBar.swift`, `Tagwerk/Planning/DayView.swift:341–381`, `Tagwerk/AI/AssistantModel.swift:576–579`, Katalog, `scripts/translations/en.json`, neu `TagwerkTests/CapacityTextTests.swift`.

- [ ] Tests für `CapacityText.explanation(_:hours:)`: „9:00–18:00 · 1 h Pause“; „… · 2 h 20 Termine · 30 min Fahrzeit · 3 h 50 eingeplant“; „… · 4 h 30 wiederkehrend“; Teile mit 0 fehlen; freier Tag liefert keine Zeile.
- [ ] Karte: Zeile unter dem Balken, an künftigen Tagen und heute (heute ersetzt sie den Teil „ganzer Tag …“ nicht, sondern folgt ihm). VoiceOver liest sie als Teil der Karte.
- [ ] Assistent: Kontextzeile nennt reservierten Aufwand getrennt („davon 4 h 30 wiederkehrend“), damit die Aussagen im Chat zur Karte passen.
- [ ] Woche und Monat bleiben bei `summary` ohne Zeile.
- [ ] Strings deutsch und englisch; beide Prüfskripte.
- [ ] Commit `feat: explain what the day capacity counts`.

### Task 6: Abschluss

- [ ] Voller Lauf `app/test-all.sh` mit UI-Tests.
- [ ] Gerätechecks unten.
- [ ] `docs/` und Entwurfsstand dieses Plans aktualisieren.

## Abhängigkeiten zu offenen Pull Requests

- **#256 (`feat/g1-plan-grid`):** ändert `Capacity.swift` und `CapacityBar.swift` nicht (Diff gegen `origin/main` leer), wohl aber `PlanningModel.swift` (+100 Zeilen, keine Zeile mit Kapazität, Puffer, Pause oder Fahrzeit), `WeekView.swift`, `MonthView.swift` und `PlanHeader.swift`. Dieser Plan beginnt **nach dem Merge von #256**; die Zeilennummern oben verschieben sich dann.
- **#253 (`feat/g1-focus`):** berührt die Kapazität nicht. Keine Reihenfolge nötig.
- **G1, Strang V (Fahrzeit, Rückweg):** Der Rückweg geht laut Plan als weiteres Intervall in `travelIntervals` (`2026-11-20-g1-planen-fokus-erinnerungen.md`, Zeile 503, Test `returnTrip_countsAsBusyTime`). Das passt zu Regel 5. Reihenfolge frei, solange der `init` von `CapacityInput` quellverträglich bleibt. Landet V zuerst, kommt ein Test „Termin ganz im Rückweg bekommt keinen Puffer“ in Task 1 dazu.

## Risiken

- **Erklärung des gemeldeten Tags ist nicht belegt.** Trifft eine kürzere Arbeitszeit zu (Erklärung 2), ist die Zahl 3 h 10 nach heutigen Regeln richtig und nur die fehlende Erklärung (F1) der Fehler. Task 0 klärt das vor dem Bau.
- **Bedeutungswechsel von „von“ (KA3a).** An Tagen mit reserviertem Aufwand steigt die Gesamtzahl in Tag, Woche und Monat; „frei“ bleibt gleich. Wer sich die alten Zahlen gemerkt hat, sieht andere.
- **KI-Eingabe.** Task 4 ändert freie Minuten an Tagen mit Fahrzeit (ohne Puffer mehr freie Zeit). Vorschläge können dichter an Fahrzeiten rücken. Ob das stört, zeigt erst der Gebrauch.
- **Höhe der Karte.** Die Zeile kann bei großer Schrift umbrechen; nicht geprüft.
- **Blöcke außerhalb der Arbeitszeit (KA5a).** Ein Abendblock senkt die Last des Tages nicht mehr; ein Tag kann frei wirken, obwohl abends gearbeitet wird. Die Erklärzeile nennt solche Blöcke nicht; bei Bedarf Zusatz „+ 1 h außerhalb“.

## Gerätechecks

1. Di. 24. Nov. wie gemeldet: Karte zeigt die erwartete Zahl und eine Zeile, die sie erklärt.
2. „Away“ 12:00–13:00 auf 12:30–13:30 schieben: die Gesamtzahl sinkt um 40 min (13:00–13:40: Rest des Termins und Puffer danach), die halbe Stunde in der Pause zählt nicht doppelt.
3. Zwei überschneidende belegte Termine: Zahl sinkt um die Vereinigung, nicht um die Summe; „Frei gibt …“ nennt denselben Betrag, um den die Karte danach steigt.
4. Zeitblock um 19:00: freie Zeit bleibt.
5. Wiederkehrende Erinnerung mit Aufwand: erscheint als „wiederkehrend“ in der Zeile, Balken füllt sich.
6. Heute nach 14:00: „noch frei“ stimmt mit der Zeile überein.
7. Woche und Monat: dieselben Zahlen wie im Tag.
8. Englische Oberfläche und VoiceOver lesen die Zeile.

## Offene Punkte

- KA1 bis KA6 (Empfehlungen: KA1c, KA2a, KA3a, KA4a, KA5a, KA6a).
- Task 0: tatsächliche Arbeitszeit und Reservierungen des gemeldeten Tags.
- Bedeutung des Schlosses im Raster nicht nachgelesen; für die Rechnung ohne Belang.
- „Mit Vorbehalt“ zählt weiter als belegt. Wird das anders gewünscht, ist das eine eigene Entscheidung.
