# Designgruppe 1 „Planen, Fokus, Erinnerungen, Ruhezeiten“ (#188, #173 Punkt 7) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Stand 20.11.2026, nach den Entscheidungen des Nutzers (Kommentar „Entscheidungen zur Designgruppe 1“ in #188 und die Klarstellung zu FO13a). Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Code-Stand der Befunde: `052eda4`. Alle Kontrastwerte in diesem Plan sind gerechnet (WCAG-Formel auf die sRGB-Werte), nicht gemessen; P1 und V2 messen zuerst. API-Namen von iOS 26/27 (Zubehörleiste der Tab-Leiste, Karten-Startoptionen) sind aus dem Gedächtnis genannt und vor der Umsetzung gegen das SDK zu prüfen.

**Goal:** Die entschiedenen Varianten der Gruppe 1 umsetzen: Uhrzeit-Linie als Kapsel, laufender Eintrag, Ausrichtung auf „jetzt“, Datumsübergang beim Ziehen, mitziehbarer Monat, Datumstitel nach Platz, Sammelblock bei großer Schrift (PL1–PL7, PL16, BF1); Fahrzeit als Aufsatz mit Abfahrtszeit, Betrag der Überschneidung, Menü, Adresssuche, Verkehrsmittel und Start je Termin, Rückweg (PL8–PL15); Fokus-Timer mit Ring, „Erledigt“ während der Phase, Startblatt, Bausteine, Leiste über den Tabs, Live Activity, Wochenrückblick (FO1–FO15); Erinnerungen als eine Zeile mit Auswahlseite, benannte Abschnitte bei Deadlines, Standards als Übersicht (ER1–ER9); Ruhezeiten-Seite mit Zeitbalken, neuer Wortlaut, Fokus-Filter mit 4-Stunden-Rückfall (RH1–RH6).

**Architecture:** Fünf Stränge auf eigenen Branches. Regeln liegen als reine Funktionen in `TagwerkCore` (`NowMarker`, `TimeGrid`, `TravelRules`, `FocusReward`, `FocusStart`, `ReminderText`, `FocusQuiet`, `NotificationPlan`), Views bleiben dünn. Neue gespeicherte Werte sind zusätzliche Attribute mit Standardwert (`AppSettings`, `EventTravelOverride`); gespeicherte Rohwerte (`FocusOutcome`) bleiben unverändert, nur ihre Deutung und Darstellung ändern sich. Farben für die Uhrzeit-Kapsel und die Kapsel „zu früh“ sind benannte Farbsets im Katalog `app/Design/Colors.xcassets`, den Strang K der Gruppe 3 später erweitert.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, Swift Testing, XCUITest (`performAccessibilityAudit`), ActivityKit/WidgetKit, MapKit (`MKLocalSearchCompleter`), App Intents, String Catalogs (Deutsch als Quellsprache, Englisch).

**Grundlagen:** Issue #188 samt Kommentaren; Mockups `docs/superpowers/mockups/2026-11-20-g1-planen-fokus-erinnerungen-mockups.html` (gewählte Varianten, Abschnitt „Randbedingungen und Abgrenzung“); Pläne `2026-11-19-p2-plan-view.md`, `-p3-focus-effort.md`, `-p4-reminders.md`, `-quiet-hours.md`; `2026-11-20-decisions-173.md` (Strang E), `2026-11-20-g3-system-anbindungen.md` (Strang K, T, G, U).

**Nicht in diesem Plan:**
- FO13a: Die Mitteilung zum Phasenende kommt wie heute mit Ton; „Ruhemodus“ ist der Stumm-Schalter des iPhones. Nichts zu bauen, kein Code, kein Test.
- RH3a: Routine-Erinnerungen bleiben ausgenommen (Ist-Zustand). PL5a: volle Nachbarseite (Ist-Zustand).
- „Jetzt losfahren“ als Mitteilung (in #188 als „später“ markiert), App-Sperre (#236), RH1c (Ruhezeiten je Wochentag).
- Kontrast in der Breite (Gruppe 3, Strang K), Abend-Erinnerungen je Tag (#173, Strang E), Bible-Study-Erinnerungen (Gruppe 2).

## Entscheidungen (aus #188, 20.11.2026)

| Bereich | Entschieden | Folge für die Umsetzung |
|---|---|---|
| Planen, Linie und Seiten | PL1b, PL2b, PL3c, PL4b, PL5a, PL6b, PL7b, PL16b | Zeit-Kapsel und 2-pt-Linie in dunklerem Rot (4,5:1 Pflicht); laufender Eintrag mit Rahmen und „läuft · noch 28 min“, „Jetzt“-Zeile bleibt; „Heute“ und Rückkehr nach 30 min richten neu aus; Titel wechselt ab halber Breite; Monat waagrecht mitziehbar mit vereinfachter Nachbarseite; volle Titelform, wenn sie passt. |
| Planen, Fahrzeit | PL8b, PL9b, PL10b (mit Bedingung), PL11b, PL12b, PL13b, PL14c, PL15c | Aufsatz am Termin „Los 15:05 · 25 min“; Zeile „Losfahren · 25 min ab Zuhause“; Kapsel „10 min zu früh“ nur bei gemessenen 4,5:1 hell und dunkel, sonst PL10a; Menü mit drei Einträgen; Adresssuche mit Vorschlägen; Verkehrsmittel und Start je Termin; Rückweg hinter Schalter (Vorgabe aus). |
| Barrierefreiheit | BF1c | Sammelblock in voller Breite, sobald eine Spalte schmaler als etwa sechs Zeichen wird. |
| Fokus | FO1b, FO2b, FO3b, FO4b, FO5b, FO6b, FO7b, FO8c, FO9b, FO10b, FO11b, FO12b, FO13a, FO14b, FO15b | Ring, drei Knöpfe, „Erledigt“ während der Phase zählt als abgeschlossen; Rückfrage „Fokus beenden?“; „Fokus starten“ als erster Menüabschnitt; Knopf am laufenden Block; Leiste über den Tabs; Abschnitt „Danach“; Startblatt; Bausteine je Wochentag, vorzeitig beendete gestrichelt in erreichter Stufe; neue Live Activity und Dynamic Island; Einstellungszeile mit Wert und Vorlagen; Balken im Wochenrückblick; Text im gekürzten Block. |
| Erinnerungen | ER1b, ER2b, ER3a, ER4b, ER5b, ER6b, ER7b, ER8b, ER9b | Eine Zeile unter „Fällig“, Auswahlseite mit Häkchen und „Eigene …“; Kurzform als Text mit „Standard ·“; Glocke nur bei Abweichung; Deadline-Seite mit zwei benannten Abschnitten und Dopplungshinweis; Wortlaut je Art; Standards als fünf Zeilen mit Unterseiten; Serienfrage mit Datum; Zeile im Blatt „Neue Aufgabe“ ab gesetzter Fälligkeit. |
| Ruhezeiten | RH1b, RH2b, RH3a, RH4b, RH5b, RH6c | Seite mit Zeitbalken und Listen; „Seit … fällig“, „Deadline seit … abgelaufen“; Fokus-Filter hält bis zum gemeldeten Ende, sonst höchstens 4 h (ohne Ruhezeit 8 h); Wortlaut „zurückhalten“; Hinweis „kommt 07:00“ in der Erinnerungsliste. |

## Global Constraints

- **Texte:** Deutsch im Quelltext, Englisch im Katalog. Jeder Task trägt seine neuen und geänderten Zeichenketten selbst ein (`scripts/sync-strings.sh`, Englisch in `scripts/translations/en.json`, `scripts/apply-translations.py`), sonst wird `app/test-all.sh` in der Stufe „string catalogs“ rot. Ändert ein Task einen deutschen Text, entfällt der alte Schlüssel in `en.json`. Texte in `TagwerkCore` stehen im Paket-Katalog, Texte der Live Activity im Katalog des Widget-Targets.
- **Mitteilungskontingent:** Dieser Plan plant keine neue Mitteilung. Die Aufteilung aus `2026-11-20-decisions-173.md`, Strang E, gilt unverändert: Aufgaben/Deadlines 46, Routinen 14, Fokus 1, Reserve 3, Summe 64 (`NotificationBudgetTests`). RH6c und RH4b ändern nur Zustellzeiten vorhandener Mitteilungen. **Hinweis für Gruppe 2:** Die Bible-Study-Erinnerungen (BE1c–BE3b) brauchen Plätze. `2026-11-20-g2-notizen-routinen.md` schlägt dafür 44/17/1/2 vor (Aufgaben/Deadlines 44, Routinen 17, Fokus 1, Reserve 2; dort noch als Frage geführt). Dieser Plan ist mit beiden Aufteilungen verträglich: Er belegt weder die Reserve noch einen Routine-Platz, und kein Test dieses Plans nennt die Zahl 46.
- **Farben:** Neue Schrift- und Flächenfarben mit Kontrastpflicht (PL1b, PL10b) sind Farbsets in `app/Design/Colors.xcassets` und werden nur über `MarkerColors.swift` angesprochen. Strang K (Gruppe 3) legt denselben Katalog in K2 an: Wer zuerst merged, legt ihn an, der andere ergänzt. Übrige Texte nutzen bis Strang K die heutigen Farben (`.secondary`, `.orange`); Strang K ersetzt sie mit.
- **Datenschutz:** An Apple Karten gehen wie heute Ort und Heimadresse; neu gehen beim Tippen die Teil-Eingaben der Adresssuche an Apple (V4, steht auf der Seite „Mehr dazu“). Tagwerk nutzt weiterhin keinen Standort. An ChatGPT geht durch diesen Plan nichts Neues.
- **SwiftData:** Neue Attribute haben einen Standardwert oder sind optional. Neue Felder in `BackupDTOs.swift` sind optional, damit ältere Sicherungen lesbar bleiben. Gespeicherte Rohwerte werden nicht umbenannt.
- **Navigation:** Auswahlseiten öffnen als Seite im Navigationsstapel, nie als Blatt an einer Zeile oder einem Abschnitt (Regel aus PR #202). Dialoge hängen am Formular. Kein Blatt über einem Blatt: erst schließen, dann nach 400 ms öffnen (Muster `FocusStartButton.swift:22–28`).
- **App Shortcuts:** kein neuer Kurzbefehl, keine geänderten Sätze. Der Fokus-Filter behält Typ- und Parameternamen (`QuietFocusFilter`, `silencesNotifications`); nur die sichtbaren Texte ändern sich.
- Code-Bezeichner, Kommentare, Log- und Testmeldungen englisch. Commits im Stil `feat: …`/`fix: …`, ohne Hinweis auf KI, ohne Co-Authored-By. Branches ohne Präfix `claude/`.
- Neue Parameter haben Standardwerte; bestehende Aufrufer und Tests bleiben gültig. Einzige Ausnahme: `ReminderText.describe(_:subject:…)` (E1) verlangt die Art ausdrücklich, damit kein Aufrufer still „Zur Fälligkeit“ für einen Termin schreibt.
- Höchstens drei Umsetzer gleichzeitig; Simulatoren nach dem Lauf löschen.

**Testbefehle** (wie in `2026-11-20-g3-system-anbindungen.md`):

- `PKG <Paket> <Suite>` = `cd app/Packages/<Paket> && xcodebuild test -testLanguage de -testRegion DE -scheme <Paket> -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:<Paket>Tests/<Suite>`
- `APP <Suite>` = `cd app && xcodegen --quiet && xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkTests/<Suite>`
- `UI <Klasse>` = wie `APP`, mit `-scheme TagwerkUITests -only-testing:TagwerkUITests/<Klasse>`
- `ALL` = `app/test-all.sh`, erwartet `ALL TESTS PASSED`.

## Abgrenzung zu laufenden Arbeiten

| Laufende Arbeit | Dateien dort | Berührung hier | Regel |
|---|---|---|---|
| `2026-11-20-decisions-173.md`, Strang E (Abend-Erinnerungen je Tag) | `TagwerkCore/RoutineSchedule.swift`, `NotificationBudget.swift`, `RoutineNotificationScheduler.swift`, `NotificationScheduler.swift` (nur Budget) | R1 ändert `NotificationScheduler.swift:138–140` (Aufruf von `FocusQuiet`), R3 nennt Routinen in einer Liste | Dieser Plan fasst `NotificationBudget.swift` und `RoutineSchedule.swift` nicht an. R1 rebased auf den Stand nach Strang E; die Tests zur Grenze 46 bleiben grün. |
| Gruppe 2 (`2026-11-20-g2-notizen-routinen.md`), Bible-Study-Erinnerungen | `NotificationBudget.swift`, `RoutineNotificationScheduler.swift`, `AppSettings.swift`, `BackupDTOs.swift` | Mitteilungskontingent; neue Felder in `AppSettings`/`BackupDTOs` (V1, F4) | Kontingent siehe Global Constraints. Felder am Blockende anfügen; Konflikte sind Nachbarzeilen. |
| Gruppe 3, Strang K (Kontrast, läuft zuletzt) | `Design/Colors.xcassets`, `project.yml`, `Common/TextTones.swift`, alle Views mit Schriftfarben, `AuditAllowlist.swift` | P1 legt den Katalog an (falls K2 noch nicht gemerged ist) und `Common/MarkerColors.swift`; neue Views nutzen bis K `.secondary` | Katalogpfad und Aufbau wie in K2. `MarkerColors.swift` ist eine eigene Datei, damit `TextTones.swift` konfliktfrei bleibt. Der WCAG-Testhelfer aus P1 (`TagwerkTests/Support/ContrastMath.swift`) ist der, den K2 für `TextTonesTests` braucht: K2 nutzt ihn, statt einen zweiten zu schreiben. Der Rückfall PL10a nutzt `.orangeText`, sobald es das gibt, sonst `.orange`. |
| Gruppe 3, Strang T | `Settings/SettingsView.swift:~98` (Zeile „Siri & Kurzbefehle“ nach „Fokus-Timer“) | F4 ändert die Zeile „Fokus-Timer“ (`SettingsView.swift:97`) | Nachbarzeilen; zweiter Merge löst von Hand. |
| Gruppe 3, Strang G | `Tasks/TaskRow.swift:29–44, 94–108` (Status in der Unterzeile), `Tasks/NewTaskSheet.swift:119–123, 280–285` | E5 (Glocke in der Unterzeile, `TaskRow.swift:30–45`), E6 (Zeile im Abschnitt „Fällig“, `NewTaskSheet.swift:156–166`) | `TaskRow`: dieselbe Unterzeile. Reihenfolge der Elemente: Wiederholung, Fälligkeit, Status (G2), Farbpunkt, Containername, Glocke (E5) am Zeilenende. Wer zuletzt merged, übernimmt beide. |
| Gruppe 3, Strang U | `Search/SearchTaskMenu.swift` ruft „Fokus starten“ | F4 ändert `FocusStartButton` (Titel mit Dauer, Startblatt) | U nutzt `FocusStartButton(task:)` unverändert weiter; das Startblatt erscheint auch dort (Suchblatt schließt zuerst, wie heute). |

## Review Focus

1. **Regel „früh fertig“ (FO1b, FO9b):** „Erledigt“ während einer Fokus- oder Pausenphase beendet die Sitzung als `completed`; der Baustein hat die erreichte Stufe und ist nicht gestrichelt. „Beenden“ ab einer Minute ergibt `aborted` mit erreichter Stufe, gestrichelt. Unter einer Minute bleibt nichts, auch bei „Erledigt“. Gespeicherte Sitzungen und Sicherungen mit `aborted` lesen sich unverändert. → F1.
2. **Kontrast gemessen, nicht gerechnet (PL1b, PL10b):** Für beide Kapseln liegt je ein Messwert hell und dunkel aus dem gerenderten Bild vor (≥ 4,5:1), dazu ein Audit-Lauf ohne Ausnahme. Fehlt für PL10b einer der vier Nachweise, ist PL10a gebaut. Kein neuer Eintrag in `AuditAllowlist.swift` ohne schriftlichen Grund im Pull Request. → P1, P2, V2.
3. **Keine doppelte Zustellung nach dem Fokus-Rückfall (RH4b):** Hat der Rückfall (4 h, ohne Ruhezeit 8 h) die zurückgehaltenen Mitteilungen schon zugestellt und meldet iOS das Fokus-Ende danach, kommt nichts ein zweites Mal. → R1 (`focusEndsAfterTheFallback_deliversNothingTwice`).
4. **Erinnerungen bleiben, wo sie waren:** Der Umbau der Auswahl (ER2b) ändert keine gespeicherte Liste: Öffnen und Schließen ohne Tipp schreibt nichts; ein Tipp auf eine Zeile, solange der Standard gilt, beginnt eine eigene Liste **aus** dem Standard. Apple-Erinnerungen schreiben weiter Alarme, keine Tagwerk-Mitteilungen. → E2.
5. **Wortlaut je Art (ER6b):** Kein Aufrufer zeigt „Zum Zeitpunkt“; Aufgabe „Zur Fälligkeit“, Termin „Zum Beginn“, Deadline „Zur Deadline“, ohne Uhrzeit „Am Tag selbst“. → E1.
6. **Fahrzeit je Termin:** Verkehrsmittel und Start je Termin wirken auf Dauer, Cache-Schlüssel, Symbol und „knapp“; ohne Wahl ändert sich für bestehende Termine nichts. Der Rückweg zählt zur belegten Zeit wie die Hinfahrt und erscheint nur bei eingeschaltetem Schalter. → V1.
7. **Sammelblock (BF1c):** Bei Standardschrift und bis zu drei Spalten auf dem iPhone bleibt das Raster wie heute; der Sammelblock ersetzt nie einen einzelnen Eintrag; im Auswahlmodus „Frei“ wird nicht zusammengefasst. → P8.
8. **Ausrichten ohne Wegziehen (PL4b):** Eigenes Scrollen beendet die Ausrichtung wie bisher; ein Seitenwechsel durch Ziehen scrollt nie. → P4.
9. **Startblatt nur mit Oberfläche (FO7b):** Siri, Kontrollzentrum und Kurzbefehl starten ohne Blatt mit den Einstellungen; der Knopf am Block (FO4b) startet mit einem Tipp „bis Blockende“. → F4, F8.
10. **Gerätetests mit Rückfall:** PL16b, FO5b, FO4b, FO10b, FO11b, RH4 haben je einen beschriebenen Prüfablauf und einen gebauten oder benannten Rückfall; das Ergebnis steht im Pull Request. → P7, F5, F7, F8, R1, Z1.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `Planning/NowLine.swift:37–48, 61–76` | 1-pt-Linie, 7-pt-Punkt, Uhrzeit als roter Text (`.red`) in der Stundenspalte; `NowRow` „Jetzt · 14:32“ rot. Element trägt `.isStaticText` (wird vom Audit gemessen). |
| `TagwerkCore/NowMarker.swift:20–28` | `alignsOnOpening` nur für den zuerst gezeigten Tag, wenn er heute ist; `insertionIndex` setzt die Zeile vor den ersten Eintrag, der nach jetzt beginnt. Einen Zustand „läuft“ gibt es nicht. |
| `Planning/DayGridScreen.swift:136–156`, `NowLine.swift:100–131` | Ausrichtung beim Öffnen (Raster über `scrollPosition`, Liste über `scrollTo("now-row")`); `userScrolled` beendet sie. Kein Auslöser für „Heute“ oder Rückkehr. |
| `App/PagedContainer.swift:88–92` | `dragOffset` ist privat; der Kopf erfährt nichts vom Ziehfortschritt. |
| `Planning/MonthView.swift:24–42` | Raster mit `.simultaneousGesture(pageSwipeGesture …)` (Monat) und ein zweiter Wischbereich über dem Tagesdetail (Tag). Kein `PagedContainer`. `PlanningModel+Neighbours.swift:19` lädt für den Monat nichts vor. |
| `Planning/PlanHeader.swift:50–55, 118` | `displayedTitle` wählt fest (Tag: mittlere Form), `.fixedSize()`; `titleCandidates` liefert drei Formen. |
| `Planning/TimelineCanvas.swift:71–98, 194–236, 374–377`, `TagwerkCore/TimeGrid.swift:37–51` | Gleich breite Spalten je Überlappung; Titel `.caption`, zwei Zeilen; Fahrzeit liegt hinter den Einträgen mit `.allowsHitTesting(false)`. Halten-und-Ziehen über `HoldToMoveRecognizer`, Tippen über `.onTapGesture`. |
| `Planning/TravelSegmentView.swift`, `TravelText.swift:51–69` | Grau schraffierter Block „25 min“, „· knapp“ in `.orange`; Listenzeile „Fahrzeit 25 min · ab Zuhause“ ohne Aktion. |
| `TagwerkCore/TravelRules.swift:97, 128–159, 192–201` | `homeGapMinutes = 180`; `isTight` ist ein Wahrheitswert (`previous.end > from`); kein Rückweg; ein Verkehrsmittel für alle Fahrten (`settings.travelTransport`). |
| `TagwerkCore/TravelOverride.swift`, `Planning/TravelOverrides.swift:9–31`, `TravelOverrideView.swift` | Je Termin nur Modus (automatisch, keine, feste Dauer); Modell `EventTravelOverride` mit `modeName`, `minutes`; Sicherung `EventTravelOverrideBackup` (`BackupDTOs.swift:338`). |
| `Settings/TravelSettingsView.swift:18–41` | Freitext-Adresse, Prüfung beim Absenden, Fußtext mit sieben Sätzen. |
| `Focus/FocusTimerModel.swift:126–151`, `TagwerkCore/FocusReward.swift:62–76` | `stop()` vor Phasenende ergibt `aborted` und ein gewelktes Stück der erreichten Stufe. `finish(.complete)` beendet **schon heute** in jeder Phase als `completed`; nur die Oberfläche bietet „Erledigt“ erst nach Ablauf (`FocusTimerView.swift:80–86`). |
| `Focus/FocusTimerView.swift:30–35, 39–117` | Ziffern, Balken, Titel an dritter Stelle; Rückfrage „Fokus abbrechen?“ mit „Abbrechen“. |
| `Focus/FocusTimerModel.swift:77–98` | `start(task:block:)` ohne Dauer; Block ohne Pomodoro setzt die Restlänge. `Focus/FocusStartButton.swift:19–31` startet sofort. |
| `Tasks/TaskContextMenu.swift:86–88` | „Fokus starten“ nach Einplanen, Fälligkeit, Status, Fokus-Markierung. |
| `Focus/FocusCollectionView.swift`, `FocusTimerText.swift:44–47` | Nummerierte Kreise je Woche; „12 gewachsen · 3 gewelkt“. |
| `TagwerkWidget/FocusLiveActivity.swift`, `Focus/Shared/FocusActivityAttributes.swift` | Phase oben, Titel klein; nach `isStale` „Phase vorbei“ mit drei Knöpfen; Insel mit Uhrsymbol und weißer Zeit. `FocusTimerModel+Intents.swift:9–14`: nach einem Knopf wird die Anzeige nicht in jedem Fall neu geschrieben. |
| `App/RootView.swift:49–76, 91–93`, `Planning/PlanView.swift:29–117` | `TabView` mit `Tab`; Timer als Blatt; sieben Rückgängig-Kapseln mit `.padding(.bottom, 60)`. Keine Leiste. |
| `Settings/SettingsView.swift:97`, `FocusSettingsView.swift` | Zeile „Fokus-Timer“ ohne Wert; Seite mit Schalter und Zählern. |
| `Focus/EffortReviewSection.swift:16–22`, `EffortReviewText.swift` | Zwei Textzeilen je Gruppe; Gruppen unter drei Messungen: „Noch zu wenige Messungen.“ |
| `Focus/FocusRecords.swift:83–86` | `trimmedEventID`, `trimmedOriginalEnd`, `trimmedNewEnd` gespeichert, im Plan nicht gezeigt. |
| `TagwerkCore/ReminderText.swift:11, 21` | Abstand 0 heißt immer „Zum Zeitpunkt“; `describe` kennt die Art nicht. |
| `Reminders/ReminderListEditor.swift`, `ReminderOffsetPicker.swift:51–55, 84–88` | Zeilen mit Schalter, Wischen zum Löschen, „Erinnerung hinzufügen“ öffnet Seite mit Segment, Zähler, Vorschau; Schnellauswahl füllt nur die Felder. |
| `Editor/TaskEditorView.swift:299–312, 219–241` | Eigener Abschnitt „Erinnerungen“; Serienfrage mit festem Text. |
| `Reminders/DeadlineReminderSheet.swift:23–29, 44–47`, `Planning/EventEditSheet.swift:67–71` | Zwei Orte mit dem Namen „Erinnerungen“; Frage „Diese Deadline wiederholt sich“. |
| `Settings/ReminderDefaultsView.swift:13–21` | Zehn Abschnitte auf einer Seite. |
| `Tasks/TaskRow.swift:30–45`, `Tasks/NewTaskSheet.swift:156–166` | Keine Marke für Erinnerungen; das Blatt legt immer mit dem Standard an. |
| `Settings/QuietHoursSettingsView.swift:20–41` | Schalter, zwei lange Fließtexte. |
| `TagwerkCore/NotificationPlan.swift:138–149, 216–228` | Mehrere Erinnerungen eines Eintrags in derselben Zustellminute ergeben schon heute **eine** Mitteilung (`NotificationPlanMultipleTests.quietHours_collapseSameMinuteOfOneEntry`); RH6b ist damit Ist-Zustand. Wortlaut „War fällig …“, „Deadline war …“. |
| `TagwerkCore/FocusQuiet.swift:32, 55–65, 92–96` | Halten bis zum nächsten Ende der Ruhezeit, ohne Ruhezeit 8 h ab Beginn. `applying(active: false)` setzt den Nachhol-Beginn immer auf den Fokusbeginn, auch wenn das Ziel schon erreicht war. Aus dem Lesen abgeleitet, nicht ausgeführt: Ohne Ruhezeit und bei einem Fokus über 8 h würde nach dem gemeldeten Ende ein zweites Mal zugestellt. |
| `Intents/QuietFocusFilter.swift:7–17` | Titel „Mitteilungen ruhen lassen“. |

## Stränge, Branches und Dateien

| Strang | Branch | Tasks | Dateien (ändern; **neu** fett) |
|---|---|---|---|
| **P** Planen: Linie, Seiten, Raster | `feat/g1-plan-grid` | P1–P8 | **`Design/Colors.xcassets`**, `project.yml`, **`Common/MarkerColors.swift`**, **`TagwerkTests/Support/ContrastMath.swift`**, `Planning/NowLine.swift`, `TagwerkCore/NowMarker.swift`, `TagwerkCore/TimeGrid.swift`, `Planning/TimelineCanvas.swift`, **`Planning/CollapsedGroupBlock.swift`**, `Planning/DayView.swift`, `DayGridScreen.swift`, `PlanHeader.swift`, `PlanView.swift`, `MonthView.swift`, **`Planning/MonthPagePreview.swift`**, `PlanningModel.swift`, `App/PagedContainer.swift`, `App/PageDrag.swift`, `App/RootView.swift` (Tab sichtbar), `App/DemoData.swift`, UI-Tests |
| **V** Fahrzeit | `feat/g1-travel` | V1–V5 | `TagwerkCore/TravelRules.swift`, `TravelOverride.swift`, `Planning/TravelOverrides.swift`, `Backup/BackupDTOs.swift`, `Persistence/AppSettings.swift`, `Planning/PlanningModel+Travel.swift`, `TravelTimeService.swift`, `TravelSegmentView.swift`, `TravelText.swift`, `TimelineCanvas.swift` (Fahrzeit-Ebene, Zeilen 80–89), `DayView.swift` (Fall `.travel`, Blatt), `TravelOverrideView.swift`, `Settings/TravelSettingsView.swift`, **`Planning/HomeAddressModel.swift`**, **`Settings/TravelInfoView.swift`**, `DemoTravelEstimator.swift`, `App/DemoData.swift` |
| **F** Fokus | `feat/g1-focus` (F1–F7), `feat/g1-focus-in-plan` (F8) | F1–F8 | `TagwerkCore/FocusReward.swift`, **`TagwerkCore/FocusCollection.swift`**, **`TagwerkCore/FocusStart.swift`**, `Focus/FocusTimerModel.swift`, `FocusTimerModel+Intents.swift`, `FocusTimerView.swift`, `FocusTimerText.swift`, `FocusCollectionView.swift`, `FocusCaptureSection.swift`, `FocusStartButton.swift`, **`Focus/FocusStartSheet.swift`**, **`Focus/FocusUpNext.swift`**, **`Focus/FocusAccessoryBar.swift`**, `Focus/FocusProtocols.swift`, `Focus/Shared/FocusActivityAttributes.swift`, `FocusActivityIntents.swift`, `FocusActivityController.swift`, `TagwerkWidget/FocusLiveActivity.swift`, `Focus/EffortReviewSection.swift`, `EffortReviewText.swift`, `Settings/FocusSettingsView.swift`, `SettingsView.swift:97`, `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift`, `Tasks/TaskContextMenu.swift`, `App/RootView.swift`, `Planning/PlanView.swift`; F8: `TimelineCanvas.swift` (`entryView`), `DayView.swift` (Fall `.block`), `DayPageExtras.swift`, `Focus/EffortTracker.swift` |
| **E** Erinnerungen | `feat/g1-reminders` | E1–E6 | `TagwerkCore/ReminderText.swift`, **`TagwerkCore/ReminderChoices.swift`**, `Reminders/ReminderListModel.swift`, `ReminderListEditor.swift` (wird **`ReminderSelection.swift`**), `ReminderOffsetPicker.swift`, `DeadlineReminderSheet.swift`, `DeadlineReminderModel.swift`, `Editor/TaskEditorView.swift`, `Planning/EntrySheet.swift:237–246`, `EventEditSheet.swift:67–71`, `Settings/ReminderDefaultsView.swift`, `SettingsView.swift:104–106`, `Tasks/TaskRow.swift`, `TaskListModel.swift`, `NewTaskSheet.swift` |
| **R** Ruhezeiten | `feat/g1-quiet-hours` | R1–R4 | `TagwerkCore/FocusQuiet.swift`, `NotificationPlan.swift`, **`TagwerkCore/ReminderQuietHint.swift`**, `Notifications/NotificationScheduler.swift:138–140`, `Intents/IntentServices.swift:51–53`, `Intents/QuietFocusFilter.swift`, `Settings/QuietHoursSettingsView.swift`, **`Settings/FocusFilterGuideView.swift`**, `Reminders/ReminderSelection.swift` (R4) |

**Gemeinsam berührte Dateien:**

| Datei | Stränge | Art |
|---|---|---|
| `Planning/TimelineCanvas.swift` | P (Linie, laufender Eintrag, Sammelblock), V (Fahrzeit-Ebene), F8 (Knopf und Text im Block) | **V und F8 beginnen erst, wenn P auf `main` ist.** V ändert nur die Fahrzeit-Ebene, F8 nur `entryView`; beide können danach parallel laufen, V merged zuerst. |
| `Planning/DayView.swift` | P (laufender Eintrag in der Liste), V (Fall `.travel`, Blatt „Fahrzeit“), F8 (Fall `.block`) | wie oben, verschiedene Fälle derselben `switch`-Anweisung |
| `App/DemoData.swift` | P (drei überlappende Termine), V (knappe Fahrt) | je ein eigener Startparameter; verschiedene Funktionen |
| `Persistence/AppSettings.swift`, `Backup/BackupDTOs.swift` | V (`travelShowsReturn`, Felder des Overrides), F (`focusAsksDurationAtStart`, `focusLastStartMinutes`), Gruppe 3, #173 | Anfügen am Blockende |
| `App/RootView.swift` | P (Rückkehr in den Tab), F (Startblatt, Leiste) | verschiedene Stellen |
| `Planning/PlanView.swift` | P (Fensterbreite für den Titel), F7 (Abstand der Kapseln) | verschiedene Stellen |
| `Settings/SettingsView.swift` | F (Zeile 97), E (Zeilen 104–106), Gruppe 3 T/L | Nachbarzeilen |
| `Reminders/ReminderSelection.swift` | E (legt an), R4 (Hinweis „kommt 07:00“) | **R4 beginnt erst, wenn E2 auf `main` ist** |
| `Tasks/TaskContextMenu.swift` | F4 (Abschnitt nach oben), Gruppe 3 U (liest Bausteine) | F4 verschiebt nur den Abschnitt |
| Kataloge, `scripts/translations/en.json` | alle | nach jedem Rebase `sync-strings.sh` neu laufen lassen, nie von Hand zusammenführen |

## Reihenfolge und Abhängigkeiten

```
Welle 1 (drei Umsetzer):
P Planen:        P1 ─► P2 ─► P3 ─► P4 ─► P5 ─► P6 ─► P7 (Spike am Gerät) ─► P8
F Fokus:         F1 ─► F2 ─► F3 ─► F4 ─► F5 ─► F6 ─► F7
E Erinnerungen:  E1 ─► E2 ─► E3 ─► E4 ─► E5 ─► E6

Welle 2 (drei Umsetzer, nach Merge von P und E):
V Fahrzeit:      V1 ─► V2 (Messung, sonst PL10a) ─► V3 ─► V4 ─► V5
R Ruhezeiten:    R1 ─► R2 ─► R3 ─► R4 (braucht E2)
F8 Fokus im Plan (braucht P3 und F4)

Abschluss:       Z1 (Geräteprüfung aller Stränge)
```

- **Merge-Reihenfolge:** E, P, F (F1–F7); dann R, V, F8. Jeder Strang ist ein Pull Request, F8 ein eigener kleiner.
- R1–R3 hängen an nichts aus Welle 1 und können vorgezogen werden, sobald ein Umsetzer frei ist; R4 wartet auf E2.
- Innerhalb eines Strangs bauen die Tasks aufeinander auf, außer F6 (eigenständig) und P7 (eigenständig, hängt am Gerätetest).

---

## Strang P: Planen (Linie, Seiten, Raster)

### Task P1: Farbsets und Kontrastrechnung (Grundlage für PL1b und PL10b)

**Files:**
- Create: `app/Design/Colors.xcassets` (vier Farbsets), `app/Tagwerk/Common/MarkerColors.swift`, `app/TagwerkTests/Support/ContrastMath.swift`, `app/TagwerkTests/MarkerColorsTests.swift`
- Modify: `app/project.yml` (Katalog in das Target `Tagwerk`; existiert er schon durch K2, nur die Farbsets ergänzen)

Farbsets (Startwerte, gerechnet):

| Asset | Hell | Dunkel | Verwendung | Gerechnet |
|---|---|---|---|---|
| `NowMarkerFill` | #D70015 | #D70015 | Fläche der Uhrzeit-Kapsel und Linie | Weiß darauf 5,38:1 (Systemrot: 3,55 hell, 3,41 dunkel) |
| `OnNowMarker` | #FFFFFF | #FFFFFF | Schrift in der Kapsel | |
| `TravelWarningFill` | #FF9500 | #FF9F0A | Fläche der Kapsel „zu früh“ | Schwarz darauf 9,55 / 10,22:1 |
| `OnTravelWarning` | #000000 | #000000 | Schrift in der Kapsel | |

**Interfaces (Produces):**

```swift
// MarkerColors.swift
/// Colours of markers that carry text on a filled shape and must keep 4.5:1 in both appearances (PL1b, PL10b).
extension ShapeStyle where Self == Color {
    static var nowMarkerFill: Color { get }
    static var onNowMarker: Color { get }
    static var travelWarningFill: Color { get }
    static var onTravelWarning: Color { get }
}

// TagwerkTests/Support/ContrastMath.swift
enum ContrastMath {
    /// WCAG 2 contrast ratio of two opaque sRGB colours, 1...21.
    static func ratio(_ first: UIColor, _ second: UIColor) -> Double
    /// A named colour resolved for one appearance.
    static func color(named name: String, style: UIUserInterfaceStyle) -> UIColor?
    /// Contrast between the fill at the centre-left edge and the darkest or lightest glyph pixel of a rendered view.
    @MainActor static func renderedRatio(of view: some View, colorScheme: ColorScheme, scale: CGFloat = 3) -> Double?
}
```

`renderedRatio` rendert mit `ImageRenderer`, liest als Flächenfarbe den häufigsten Pixel und als Schriftfarbe den Pixel mit dem größten Abstand zur Fläche (der Kern einer fetten Glyphe bei dreifacher Auflösung ist deckend). Das ist die **Messung am gerenderten Bild**; sie ersetzt nicht den Audit, sondern steht daneben.

- [ ] **Step 1: Tests** (`MarkerColorsTests`): `allAssets_resolveInBothAppearances`; `nowMarker_whiteOnFill_isAtLeast4_5` (hell, dunkel); `travelWarning_textOnFill_isAtLeast4_5` (hell, dunkel); `contrastMath_knownPairs` (Schwarz/Weiß 21, #767676 auf Weiß 4,54).
- [ ] **Step 2:** `APP MarkerColorsTests` → rot (Assets fehlen).
- [ ] **Step 3:** Katalog, Erweiterung und Helfer anlegen.
- [ ] **Step 4:** `ALL`. Commit `feat: add colour assets for the now marker and the travel warning`.

### Task P2: Uhrzeit-Linie als Kapsel (PL1b)

**Files:**
- Modify: `app/Tagwerk/Planning/NowLine.swift:32–76`, `TimelineCanvas.swift:344–355` (Einrast-Anzeige bleibt, nutzt aber dieselbe Füllfarbe)
- Test: `app/TagwerkTests/NowLineTextTests.swift`, neu `app/TagwerkTests/MarkerRenderContrastTests.swift`, `app/TagwerkUITests/AccessibilityAuditUITests.swift`, `AccessibilityAuditLargeTextUITests.swift`

**Interfaces (Produces):**

```swift
/// The time of the "now" marker: white on `nowMarkerFill`, bold caption2 with monospaced digits.
struct NowTimeCapsule: View { let time: String }
```

Raster: `NowTimeCapsule` in der Stundenspalte (deckt die Stundenbeschriftung wie heute), daneben eine 2-pt-Linie in `.nowMarkerFill`, kein Punkt. Liste: dieselbe Kapsel mit „Jetzt · 14:32“, daneben die 2-pt-Linie. VoiceOver-Label und `.isStaticText` bleiben.

**Messung (verbindlich):**
1. `MarkerRenderContrastTests.nowCapsule_renderedContrast_light`, `…_dark`: `ContrastMath.renderedRatio(of: NowTimeCapsule(time: "14:32"), …) >= 4.5`.
2. Audit: `UI AccessibilityAuditUITests` (hell, „Planen (Tag)“) und `UI AccessibilityAuditLargeTextUITests` (AX5/dunkel) im Sammelmodus (`TEST_RUNNER_AUDIT_COLLECT_FILE=…`): kein Kontrastbefund, dessen Element „Jetzt“ enthält.
3. Liegt ein Wert unter 4,5:1: zuerst `NowMarkerFill` abdunkeln (#C81E1E: 5,74; #B91C1C: 6,47) und neu messen. Ein Eintrag in `AuditAllowlist.swift` ist nur zulässig, wenn die gerenderte Messung ≥ 4,5:1 zeigt und der Audit trotzdem meldet (Messfehler des Audits, etwa durch die Linie hinter der Kapsel); der Grund nennt beide Messwerte.

- [ ] **Step 1:** Tests wie oben; `NowLineTextTests` unverändert grün.
- [ ] **Step 2:** `APP MarkerRenderContrastTests` → rot.
- [ ] **Step 3:** Umsetzen.
- [ ] **Step 4:** Messung 1–3, Werte in die Beschreibung des Pull Requests. `ALL`.
- [ ] **Step 5:** Commit `feat: show the current time as a capsule on a stronger line`.

### Task P3: Laufender Eintrag (PL2b, PL3c)

**Files:**
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/NowMarker.swift`, `app/Tagwerk/Planning/TimelineCanvas.swift:194–236`, `DayView.swift:196–223, 506–525` (`TimelineLine`), `NowLine.swift` (Texte)
- Test: `TagwerkCoreTests/NowMarkerTests.swift`, `app/TagwerkTests/NowLineTextTests.swift`

**Interfaces (Produces):**

```swift
// NowMarker
/// Whether an entry is running: `nowMinutes` lies in its range (start inclusive, end exclusive). `nil` is another day.
public static func isRunning(range: Range<Int>, nowMinutes: Int?) -> Bool
/// Minutes left of a running entry, rounded up to at least 1.
public static func remainingMinutes(range: Range<Int>, nowMinutes: Int) -> Int

// NowText
/// "läuft · noch 28 min" (EN "running · 28 min left").
static func runningDetail(remainingMinutes: Int) -> String
/// "läuft, noch 28 Minuten" for VoiceOver.
static func runningAccessibility(remainingMinutes: Int) -> String
```

Raster: Der laufende Eintrag (Termin, Zeitblock, Mittagspause; nicht ganztägig, nicht Fahrzeit) bekommt einen 2-pt-Rahmen in seiner Farbe (die Auswahl-Markierung hat Vorrang), die Zeitzeile zeigt `runningDetail` statt „14:00–15:00“; der Zusatz (`style.suffix`) bleibt. Die Einträge stehen dafür in einem `TimelineView(.everyMinute)`. Liste: Die Detailzeile des laufenden Eintrags zeigt `runningDetail`, der Farbbalken ist 6 pt breit; die „Jetzt“-Zeile bleibt, wo sie ist (`insertionIndex` unverändert). Der Zustand ist der Anker für FO4b (F8).

- [ ] **Step 1: Tests.** `isRunning_startInclusive_endExclusive`, `isRunning_otherDay_isFalse`, `remainingMinutes_roundsUp`; `NowLineTextTests.runningDetail_inBothLanguages`.
- [ ] **Step 2:** `PKG TagwerkCore NowMarkerTests` → rot. **Step 3:** umsetzen.
- [ ] **Step 4:** `ALL` (Audit „Planen (Tag)“: Die Uhrzeit der Audits ist fest auf den Vormittag gesetzt, ein Demo-Eintrag läuft dann; neue Befunde beheben, nicht ausnehmen).
- [ ] **Step 5:** Commit `feat: mark the running entry in the grid and the list`.

### Task P4: Ausrichten auf „jetzt“ (PL4b)

**Files:**
- Modify: `TagwerkCore/NowMarker.swift`, `app/Tagwerk/Planning/PlanningModel.swift`, `PlanHeader.swift:127–132, 148`, `DayGridScreen.swift:100–156`, `NowLine.swift:100–131`, `app/Tagwerk/App/RootView.swift` (Tab-Wechsel, `scenePhase`)
- Test: `TagwerkCoreTests/NowMarkerTests.swift`, `app/TagwerkTests/PlanningModelTests.swift`

**Interfaces (Produces):**

```swift
// NowMarker
public static let realignAfter: TimeInterval = 30 * 60
/// Returning to the day view of today aligns to "now" again when it was not visible for at least `realignAfter`.
public static func realignsOnReturn(hiddenSince: Date?, now: Date) -> Bool
/// Where a day that is not today starts when it is opened by a jump: the first entry, else the work start.
public static func openingMinutes(firstEntryStart: Int?, workStart: Int?) -> Int?

// PlanningModel
/// Bumped by "Heute" and by a return after `realignAfter`; the day views align to "now" when it changes.
private(set) var nowAlignmentToken = 0
/// Bumped when a day is opened by a jump (date picker, month, "Zeigen"), never by paging.
private(set) var dayOpeningToken = 0
func showToday()                    // anchor = today, bumps nowAlignmentToken
func jump(to day: PlanDay)          // anchor = day, bumps dayOpeningToken (today: nowAlignmentToken)
func planBecameHidden(at: Date)
func planBecameVisible(at: Date)    // bumps nowAlignmentToken when realignsOnReturn
```

- „Heute“ in `PlanControlRow` und im Datums-Popover ruft `showToday()`. Alle Stellen, die `anchor` direkt setzen, um einen Tag zu öffnen (Popover, Monat → Tag, `RootView.showDay`, Suche), rufen `jump(to:)`; `step(_:)` (Seitenwechsel) bleibt ohne Token.
- `DayGridScreen` und `NowListBehavior` setzen bei geändertem `nowAlignmentToken` ihre Merker zurück (`nowAlignedDay`, `userScrolled`, `scrolledFor`) und richten wie beim Öffnen aus. Eigenes Scrollen beendet die Ausrichtung wie bisher.
- Bei geändertem `dayOpeningToken` und einem anderen Tag als heute scrollt das Raster auf `openingMinutes` (ein Drittel der sichtbaren Höhe wie bei „jetzt“); die Liste auf die erste Zeile der Zeitleiste.
- `RootView`: Tab 0 verlassen oder App in den Hintergrund → `planBecameHidden`; zurück → `planBecameVisible`.

- [ ] **Step 1: Tests.** `realignsOnReturn_after30Minutes`, `…_before30Minutes_isFalse`, `…_neverHidden_isFalse`; `openingMinutes_prefersFirstEntry`; `PlanningModelTests.showToday_bumpsTheToken`, `step_neverBumpsATokens`, `planBecameVisible_after31Minutes_bumps`.
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL`. Im Simulator: Tag öffnen, weit scrollen, „Heute“ → Ausschnitt springt auf „jetzt“; Seite ziehen → kein Scrollen.
- [ ] **Step 5:** Commit `feat: realign the day view to now on "Heute" and after a longer absence`.

### Task P5: Datumstitel wechselt ab halber Breite (PL6b)

**Files:**
- Modify: `app/Tagwerk/App/PageDrag.swift`, `PagedContainer.swift:22–37, 88–116`, `app/Tagwerk/Planning/PlanningModel.swift`, `PlanHeader.swift:104–125`, `DayView.swift:34–37`, `WeekView.swift:17–18`
- Test: `app/TagwerkTests/PageDragTests.swift`, `PlanHeaderTextTests.swift`

**Interfaces (Produces):**

```swift
// PageDrag
/// The neighbour that covers more than half of the width during a drag; nil while the shown page prevails.
static func prevailingPage(offset: CGFloat, width: CGFloat, canGoBack: Bool, canGoForward: Bool) -> PageSwipe?

// PagedContainer
/// Called when the prevailing page changes during a drag, and with nil when the drag ends or is cancelled.
var onPrevailingPage: (PageSwipe?) -> Void = { _ in }

// PlanningModel
/// Set while a neighbour prevails during a drag: the header shows that period. Never stored.
var titlePreviewStep: Int?
/// Anchor and range the header shows: the neighbour while `titlePreviewStep` is set.
var titleAnchor: PlanDay { get }
var titleRange: ClosedRange<PlanDay> { get }
```

`PlanTitleButton` liest `titleAnchor`/`titleRange` für Oberzeile und Titel, blendet mit `.contentTransition(.opacity)` über und gibt eine leichte Haptik (`.sensoryFeedback(.selection, trigger: model.titlePreviewStep)`). Mit „Bewegung reduzieren“ folgt die Seite dem Finger nicht; der Titel wechselt dann wie heute nach dem Loslassen.

- [ ] **Step 1: Tests.** `prevailingPage_belowHalf_isNil`, `…_aboveHalf_isTheNeighbour`, `…_atBlockedEdge_isNil`; `PlanHeaderTextTests.titleAnchor_followsThePreviewStep_inDayWeekAndMonth`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: switch the plan title once the neighbour page prevails while dragging`.

### Task P6: Monat waagrecht mitziehbar (PL7b)

**Files:**
- Create: `app/Tagwerk/Planning/MonthPagePreview.swift`
- Modify: `app/Tagwerk/Planning/MonthView.swift:24–42`, `PlanningModel.swift` (Tage des Monatsrasters als statische Funktion)
- Test: `app/TagwerkTests/PlanningModelTests.swift`, `app/TagwerkUITests/PlanUITests.swift`

**Interfaces (Produces):**

```swift
// PlanningModel
/// The days of the month grid for `anchor` (whole weeks around the month), the same range the month scope loads.
static func monthGridDays(anchor: PlanDay, calendar: Calendar) -> [PlanDay]

/// The neighbouring month while the page is dragged: weekday header and day numbers, no load bars and no marks.
struct MonthPagePreview: View { let model: PlanningModel; let anchor: PlanDay }
```

Der `PagedContainer` umschließt **nur** das Raster (Wochentagszeile und `LazyVGrid`), nicht die ganze Seite: So bleibt die senkrechte `ScrollView` die eine Scroll-Ansicht der Navigationsleiste, und der zweite Wischbereich über dem Tagesdetail (`stepSelectedDay`) bleibt erhalten. `contentID: { model.days.first?.day }`, `onPage: { model.step($0.step) }`, `onPrevailingPage` wie in P5. Die bisherige `.simultaneousGesture(pageSwipeGesture …)` am Raster entfällt. Es wird nichts vorgeladen; die Nachbarseite braucht nur das Datum.

- [ ] **Step 1: Tests.** `monthGridDays_coversWholeWeeks`, `monthGridDays_matchesTheLoadedRange`; `PlanUITests.testMonthPagesBySwiping` (Monat öffnen, waagrecht wischen, Titel zeigt den nächsten Monat).
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL`. Im Simulator prüfen: Tippen auf einen Tag, Kontextmenü und Ablegen einer Aufgabe auf einen Tag funktionieren weiter; senkrechtes Scrollen beginnt keinen Seitenwechsel; Monate mit fünf und sechs Wochen.
- [ ] **Step 5:** Commit `feat: page the month view by dragging, with a plain neighbour page`.

### Task P7: Datumstitel nach Platz (PL16b), mit Gerätetest

**Files:**
- Modify: `app/Tagwerk/Planning/PlanHeader.swift:47–55, 104–119`, `PlanView.swift` (Fensterbreite)
- Test: `app/TagwerkTests/PlanHeaderTextTests.swift`

**Interfaces (Produces):**

```swift
// PlanHeaderText
/// The longest candidate that is not wider than `availableWidth`; the shortest when none fits.
static func fittingTitle(_ candidates: [String], availableWidth: CGFloat, width: (String) -> CGFloat) -> String
/// `availableWidth == nil` keeps the fixed choice of today (fallback PL16a).
static func displayedTitle(scope:anchor:range:calendar:largeText:availableWidth: CGFloat? = nil,
                           width: (String) -> CGFloat = PlanHeaderMetrics.titleWidth) -> String

enum PlanHeaderMetrics {
    /// Width the three trailing bar buttons, the chevron, the gaps and the margins take. Start value, set by the spike.
    static let trailingReserve: CGFloat = 196
    /// `nil` switches the measurement off (fallback PL16a).
    static func availableTitleWidth(windowWidth: CGFloat) -> CGFloat?
    /// Width of a title in the header font (bold title3 at the current content size), measured with UIKit.
    static func titleWidth(_ text: String) -> CGFloat
}
```

Statt `ViewThatFits` (bekommt in einem Leisten-Eintrag keine nutzbare Breite) wird gerechnet: `PlanView` liest die Fensterbreite (`onGeometryChange`) und reicht sie an `PlanTitleButton`; die Breite jedes Kandidaten kommt aus `NSAttributedString.size` mit der Schrift des Titels. `.fixedSize()` bleibt. Bei Bedienungshilfen-Größen gilt dieselbe Rechnung (die gemessene Schrift wächst mit).

**Spike am Gerät (vor dem Commit, Pflicht):**

| Prüfung | Geräte und Lagen | Erwartung |
|---|---|---|
| Reserve stimmt | kleinstes unterstütztes iPhone, 6,3″, Pro Max; Deutsch und Englisch; Schriftgrößen Standard, XXXL, AX1 | Der Titel ist nie abgeschnitten und stößt nie an die Knöpfe; die volle Form erscheint, wo sichtbar Platz ist („Freitag, 20. Nov.“ auf 6,3″ in Standardgröße). |
| Lange Fälle | „Donnerstag, 24. Dez.“, „Mittwoch, 30. Sept.“, englisch „Wednesday, Sep 30“; Woche und Monat | Rückfall auf die mittlere bzw. kurze Form statt Kürzung. |
| Leiste | mit und ohne Suchknopf-Zustände, nach Drehen der Schriftgröße bei laufender App | Auswahl folgt der neuen Breite. |

Vorgehen: Reserve am Gerät ausmessen (vorübergehend einen Rahmen um den Titel und die berechnete Breite einblenden, nicht committen), Wert in `trailingReserve` eintragen. **Rückfall:** Lässt sich für die drei Geräte kein gemeinsamer Wert finden oder überlappt der Titel in einer der Lagen, gibt `availableTitleWidth` `nil` zurück (PL16a bleibt), und die Hauptsitzung kommentiert das Ergebnis in #188.

- [ ] **Step 1: Tests.** `fittingTitle_takesTheLongestThatFits`, `fittingTitle_nothingFits_takesTheShortest`, `displayedTitle_withoutWidth_keepsTheFixedForm`.
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** Spike, `ALL` (Audits „Planen“ in Standardgröße und AX5 ohne neue Befunde „Text abgeschnitten“).
- [ ] **Step 5:** Commit `feat: show the full date title in the plan header when it fits`.

### Task P8: Sammelblock bei schmalen Spalten (BF1c)

**Files:**
- Create: `app/Tagwerk/Planning/CollapsedGroupBlock.swift` (Block und Liste)
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/TimeGrid.swift`, `app/Tagwerk/Planning/TimelineCanvas.swift:67–98, 374–377`, `app/Tagwerk/App/DemoData.swift` (Startparameter `-TagwerkDemoOverlap`: drei gleichzeitige Termine)
- Test: `TagwerkCoreTests/TimeGridTests.swift`, `app/TagwerkUITests/PlanUITests.swift`, `AccessibilityAuditLargeTextUITests.swift`

**Interfaces (Produces):**

```swift
// TimeGrid.swift
/// Indices grouped by overlap, directly or through others, each group in start order; single entries are groups of one.
public func overlapGroups(for intervals: [Range<Int>]) -> [[Int]]

public enum GridCollapse {
    /// A group becomes one block when it needs more than one column and a column would be narrower than the minimum.
    public static func collapses(columnCount: Int, availableWidth: Double, minimumColumnWidth: Double) -> Bool
}

// CollapsedGroupBlock.swift
/// "3 Termine · 10:00–11:00" and the titles, over the full width; a tap opens the entries as a list.
struct CollapsedGroupBlock: View { let entries: [DayEntry]; let range: Range<Int>; … }
struct CollapsedGroupList: View { … }   // rows open the entry sheet through the canvas' onTap
```

Regeln:
- Mindestbreite: `@ScaledMetric(relativeTo: .caption) var minimumColumnWidth: CGFloat = 44` (etwa sechs Zeichen der Titelschrift; wächst mit der Schriftgröße).
- Der Block reicht über die Zeitspanne der Gruppe und zeigt Anzahl, Zeitraum und so viele Titel, wie in die Höhe passen (jeder einzeilig), sonst „+2 weitere“. Farbe neutral grau, roter Balken links, wenn eine Deadline dabei ist; läuft ein Mitglied, trägt der Block den Rahmen aus P3.
- Tippen öffnet `CollapsedGroupList` als Blatt (Uhrzeit, Titel, Zusatz je Zeile); eine Zeile schließt das Blatt und öffnet nach 400 ms das Blatt des Eintrags.
- In der Gruppe gibt es kein Halten-und-Ziehen; verschoben wird über das Blatt des Eintrags. Fußtext der Liste: „Zum Verschieben den Eintrag öffnen.“
- Im Auswahlmodus „Frei“ (`selectingIDs != nil`) wird nicht zusammengefasst.
- Fahrzeit-Blöcke von Terminen einer zusammengefassten Gruppe liegen in voller Breite hinter dem Block.
- VoiceOver: ein Knopf „3 Termine, 10:00 bis 11:00: Projektbesprechung, Zahnarzt Kontrolle, Anruf Steuerberater“.

- [ ] **Step 1: Tests.** `overlapGroups_joinsTransitiveOverlaps`, `overlapGroups_keepsSingleEntries`, `collapses_onlyBelowTheMinimum`, `collapses_neverForOneColumn`; `PlanUITests.testOverlappingEntriesCollapseAtLargeText` (AX5, `-TagwerkDemoOverlap`: Knopf „3 Termine“ vorhanden, Tipp zeigt drei Zeilen; in Standardgröße drei einzelne Blöcke).
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL`; Audit AX5/dunkel „Planen“: Der Sammelblock darf keinen Befund „Text abgeschnitten“ auslösen.
- [ ] **Step 5:** Commit `feat: collapse overlapping entries into one block when columns get too narrow`.

---

## Strang V: Fahrzeit (beginnt nach dem Merge von P)

### Task V1: Regeln: Betrag der Überschneidung, Verkehrsmittel und Start je Termin, Rückweg (PL10b, PL13b, PL14c, PL15c)

**Files:**
- Modify: `TagwerkCore/TravelRules.swift`, `TravelOverride.swift`, `app/Tagwerk/Planning/TravelOverrides.swift`, `PlanningModel+Travel.swift`, `TravelTimeService.swift`, `DemoTravelEstimator.swift`, `app/Tagwerk/Persistence/AppSettings.swift`, `app/Tagwerk/Backup/BackupDTOs.swift:338–356` und Einstellungs-DTO
- Test: `TagwerkCoreTests/TravelRulesTests.swift`, `TravelOverrideTests.swift`, `app/TagwerkTests/TravelTimeServiceTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
public enum TravelStart: String, Sendable, Codable { case home, previousEvent }

public struct TravelLeg {
    public enum Direction: Sendable, Hashable { case toEvent, returnHome }
    public var direction: Direction = .toEvent
    /// Transport chosen for this event; nil uses the setting.
    public var transport: TravelTransport?
    /// `toEvent`: the start of the event. `returnHome`: the end of the event, when the trip starts.
    public var arrival: Date
}

public struct TravelSegment {
    public var direction: TravelLeg.Direction = .toEvent
    public var transport: TravelTransport?
    /// Minutes the trip starts before the previous event ends; 0 when it does not. `isTight` is `overlapMinutes > 0`.
    public var overlapMinutes: Int = 0
    public var id: String { direction == .toEvent ? eventID : eventID + "#return" }
}

/// What the user chose for one event: mode, and for the automatic mode optionally transport and start.
public struct TravelChoice: Hashable, Sendable {
    public var mode: TravelOverrideMode = .automatic
    public var transport: TravelTransport?
    public var start: TravelStart?
    public var isDefault: Bool { get }
}
public struct TravelOverride { …; public var transport: TravelTransport? = nil; public var start: TravelStart? = nil }

public enum TravelOverrideRules {
    public static func choice(eventID:seriesID:start:overrides:) -> TravelChoice
    /// Like `updated(…mode…)`; an entry stays as long as the choice is not the default.
    public static func updated(_:eventID:seriesID:start:choice:series:) -> [TravelOverride]
}

public enum TravelRules {
    public static func legs(events:on:home:calendar:, choices: [String: TravelChoice] = [:],
                            includesReturn: Bool = false) -> [TravelLeg]
}

// TravelTimeEstimating
/// Trip that starts at `departure`; the default implementation asks with `arrival: departure`.
func minutes(from:to:transport:departure: Date) async throws -> Int

// AppSettings
/// "Rückweg anzeigen" (PL15c).
var travelShowsReturn: Bool = false
// EventTravelOverride (SwiftData), EventTravelOverrideBackup: `transportRaw: String? = nil`, `startRaw: String? = nil`
```

Regeln:
- **Start je Termin:** `.home` erzwingt Zuhause (ohne Heimadresse keine Fahrt), `.previousEvent` den letzten zuvor beendeten Termin mit Ort unabhängig von der Lücke (gibt es keinen, gilt die Automatik). Ohne Wahl bleibt die 3-Stunden-Regel.
- **Verkehrsmittel je Termin:** geht in Anfrage und Cache-Schlüssel (`TravelTimeCache.tripKey` enthält das Verkehrsmittel schon); `resolvedTimes` und `fetchMissing` nutzen `leg.transport ?? transport`.
- **Rückweg:** nur mit `includesReturn` und Heimadresse; nach dem letzten Termin des Tages mit Ort, und nach jedem Termin mit Ort, auf den erst nach mehr als `homeGapMinutes` der nächste folgt. Der Block reicht vom Terminende um die Fahrzeit nach vorn, an Mitternacht abgeschnitten. Modus „Keine“ am Termin: weder Hin- noch Rückfahrt. Feste Dauer: Der Rückweg nutzt dieselbe Dauer (`source: .manual`).
- **Überschneidung:** `overlapMinutes = max(0, Ende des Vortermins − Abfahrt)`.
- Der Rückweg zählt zur belegten Zeit auf demselben Weg wie die Hinfahrt (`TravelCapacityTests` deckt die Hinfahrt ab; ein Test `returnTrip_countsAsBusyTime` kommt dazu).

- [ ] **Step 1: Tests.** `overlapMinutes_isTheTimeBeforeThePreviousEnds`, `startHome_ignoresANearPreviousEvent`, `startPrevious_ignoresTheGap`, `startPrevious_withoutOne_fallsBackToTheRule`, `transportPerEvent_reachesTheLeg`, `returnLeg_afterTheLastPlacedEvent`, `returnLeg_beforeAGapOverThreeHours`, `returnLeg_offByDefault`, `returnLeg_noneMode_hasNeitherTrip`, `returnLeg_isCutAtMidnight`; `choice_seriesThenOccurrence`, `updated_defaultChoice_leavesNoEntry`; `TravelTimeServiceTests.perLegTransport_usesItsOwnCacheKey`; `BackupTests.travelOverride_withoutNewFields_restoresAsBefore`, `…_withTransportAndStart_roundTrips`.
- [ ] **Step 2–3:** rot, umsetzen. Bestehende Aufrufer (`travelOverrideMode`, `setTravelOverride`) bleiben als dünne Hüllen um `choice`.
- [ ] **Step 4:** `ALL`. Commit `feat: add per-event transport and start, the return trip and the overlap amount to the travel rules`.

### Task V2: Aufsatz am Termin, Zeile „Losfahren“, Kapsel „zu früh“ (PL8b, PL9b, PL10b mit Messung und Rückfall)

**Files:**
- Modify: `app/Tagwerk/Planning/TravelSegmentView.swift`, `TravelText.swift:43–82`, `TimelineCanvas.swift:80–89`, `DayView.swift:221–223`, `app/Tagwerk/App/DemoData.swift` (unter `-TagwerkDemoTravel` ein Terminpaar mit Orten, dessen Fahrt 10 min vor dem Ende des Vortermins beginnt)
- Test: `app/TagwerkTests/TravelTextTests.swift`, `MarkerRenderContrastTests.swift`, neu `app/TagwerkUITests/TravelContrastUITests.swift`

**Interfaces (Produces):**

```swift
// TravelText
/// Grid: "Los 15:05 · 25 min", "Los 15:05 · ~30 min" (estimate), return: "25 min nach Hause".
static func gridText(_ segment: TravelSegment, departure: String) -> String
/// Short forms for narrow columns, longest first.
static func gridCandidates(_ segment: TravelSegment, departure: String) -> [String]
/// List: "Losfahren · 25 min ab Zuhause", "… ab vorherigem Termin", "… · manuell", "… · geschätzt"; return: "Nach Hause · 25 min".
static func rowText(_ segment: TravelSegment) -> String
/// "10 min zu früh" (EN "10 min early"); VoiceOver: "10 Minuten vor dem Ende des vorherigen Termins".
static func overlapText(minutes: Int) -> String
static func overlapAccessibility(minutes: Int) -> String

/// Black on `travelWarningFill`, bold caption2, own static-text element for VoiceOver and the audit.
struct TravelWarningCapsule: View { let minutes: Int }
```

Darstellung: Der Block wird zum Aufsatz in der Farbe des Zieltermins (Fläche 12 %, ohne Schraffur), bündig über dem Termin (Rückweg: bündig darunter), Text aus `gridCandidates` über `ViewThatFits`. Die Kapsel sitzt rechts im Aufsatz; reicht die Breite nicht, steht nur die Kapsel. In der Liste steht die Kapsel hinter „Losfahren“. „· knapp“ entfällt. Symbol und Text nutzen `segment.transport ?? settings.travelTransport`.

**Messung PL10b (verbindlich, vier Nachweise):**

| Nr. | Nachweis | Befehl | Schwelle |
|---|---|---|---|
| 1 | gerendert, hell | `APP MarkerRenderContrastTests` (`travelCapsule_renderedContrast_light`) | ≥ 4,5:1 |
| 2 | gerendert, dunkel | `…_dark` | ≥ 4,5:1 |
| 3 | Audit, hell | `UI TravelContrastUITests` (`testTightTripInLight`: `-TagwerkDemoTravel`, Tagesansicht in Raster und Liste, `performAccessibilityAudit(for: .contrast)`, **ohne** `AuditAllowlist`) | kein Befund an einem Element mit „zu früh“ |
| 4 | Audit, dunkel | `testTightTripInDark` (`-TagwerkUITestDark`) | wie 3 |

Dazu die Sichtprüfung am Gerät (Z1): Standardgröße, zwei Spalten, Aufsatz von 15 Minuten Höhe, hell und dunkel, im Freien bei voller Helligkeit.

**Rückfall PL10a (ausdrücklich):** Erreicht einer der vier Nachweise die Schwelle nicht, werden zuerst höchstens zwei Farbkorrekturen versucht (Fläche dunkler mit weißer Schrift, z. B. #A84400 mit 6,01:1; größere Schrift `.caption`). Bleibt ein Nachweis rot oder fällt die Sichtprüfung durch, wird **PL10a** gebaut: keine Kapsel; der Text lautet „Los 15:05 · 25 min · knapp“ (Liste: „Losfahren · 25 min ab Zuhause · knapp“) in `.orangeText` (bis Strang K: `.orange`). Der Betrag bleibt im VoiceOver-Text und als Kopfzeile des Menüs aus V3 („Abfahrt 10 min vor dem Ende von „Team-Call““). `TravelWarningCapsule` und die Tests 1–4 werden dann entfernt, `TravelWarningFill`/`OnTravelWarning` ebenfalls. Die Entscheidung steht mit den Messwerten im Pull Request; die Hauptsitzung kommentiert sie in #188.

- [ ] **Step 1: Tests.** `TravelTextTests`: `gridText_namesTheDeparture`, `gridText_estimateKeepsTheTilde`, `rowText_saysLosfahren`, `rowText_return`, `overlapText_inBothLanguages`, `gridCandidates_shortenInOrder`; Nachweise 1–4.
- [ ] **Step 2:** rot. **Step 3:** umsetzen.
- [ ] **Step 4:** Messung, bei Bedarf Rückfall. `ALL`.
- [ ] **Step 5:** Commit `feat: show travel time as an attachment with the departure time and the overlap amount` (bei Rückfall: `… and keep the text mark for tight trips`).

### Task V3: Menü an der Fahrzeit (PL11b)

**Files:**
- Modify: `app/Tagwerk/Planning/TravelSegmentView.swift`, `TimelineCanvas.swift:80–89`, `DayView.swift` (Blatt „Fahrzeit“, Fall `.travel`)
- Create: `app/Tagwerk/Planning/TravelRoute.swift`
- Test: neu `app/TagwerkTests/TravelRouteTests.swift`

**Interfaces (Produces):**

```swift
/// Opens the trip in Apple Maps: from the origin of the segment (home or the previous event) to the event's place.
enum TravelRoute {
    /// The Maps direction mode for a transport; transports Maps cannot open directly use the default mode.
    static func directionsMode(for transport: TravelTransport) -> String
    @MainActor static func open(from: TravelPlace, to: TravelPlace, transport: TravelTransport)
}
struct TravelMenu: View { let segment: TravelSegment; let event: CalendarEvent; let model: PlanningModel; let onEdit: () -> Void }
```

Aufsatz und Listenzeile werden zu einem `Menu` mit drei Einträgen: „Route in Karten“, „Fahrzeit ändern …“ (öffnet `TravelOverrideView` als Blatt mit eigenem Navigationsstapel, gehängt an `DayView`), „Keine Fahrzeit für diesen Termin“ (setzt den Modus „Keine“ für dieses Vorkommen, ohne Serienfrage; rückgängig über das Terminblatt). Die Route hat Start und Ziel ausdrücklich, damit Karten nicht den aktuellen Standort nimmt und die gezeigte Zeit zur Route passt. Die Fahrzeit-Ebene verliert `.allowsHitTesting(false)`; die Trefferfläche ist mindestens 28 pt hoch und wächst nur nach oben (Rückweg: nach unten), nie über den Termin. VoiceOver: Knopf mit dem bisherigen Label, Hinweis „Öffnet Aktionen zur Fahrzeit“.

- [ ] **Step 1: Tests.** `directionsMode_mapsEveryTransport`; `PlanUITests.testTravelMenuOffersThreeActions` (`-TagwerkDemoTravel`).
- [ ] **Step 2–3:** rot, umsetzen (Startoptionen von Karten gegen das SDK prüfen; ein fehlender Fahrrad-Modus fällt auf den Standard von Karten zurück).
- [ ] **Step 4:** `ALL`. Im Simulator: Tipp auf den Aufsatz öffnet das Menü, Tipp auf den Termin weiter das Terminblatt, Halten-und-Ziehen des Termins unverändert.
- [ ] **Step 5:** Commit `feat: open route, travel settings of the event and "no travel time" from the travel block`.

### Task V4: Einstellung „Fahrzeit“ mit Adresssuche und Rückweg-Schalter (PL12b, PL15c)

**Files:**
- Create: `app/Tagwerk/Planning/HomeAddressModel.swift`, `app/Tagwerk/Settings/TravelInfoView.swift`
- Modify: `app/Tagwerk/Settings/TravelSettingsView.swift`, `app/Tagwerk/App/AppEnvironment.swift` (Vorschlagsdienst), `DemoTravelEstimator.swift`
- Test: neu `app/TagwerkTests/HomeAddressModelTests.swift`, `AccessibilityAuditRecipesUITests.swift` (falls die Seite dort geprüft wird; sonst kein neuer Audit)

**Interfaces (Produces):**

```swift
struct AddressSuggestion: Identifiable, Hashable, Sendable { let id: String; let title: String; let subtitle: String }

/// Address completion while typing; MapKit in the app, a fixed list in the simulator demo and in tests.
protocol AddressSuggesting: Sendable {
    func suggestions(for query: String) async -> [AddressSuggestion]
    func resolve(_ suggestion: AddressSuggestion) async throws -> PlaceLookup
}

@MainActor @Observable
final class HomeAddressModel {
    enum Status: Equatable { case idle, searching, noSuggestions, saved(String), failed }
    var query: String
    private(set) var suggestions: [AddressSuggestion]
    private(set) var status: Status
    func queryChanged() async            // debounced by 300 ms, at least 3 characters
    func choose(_ suggestion: AddressSuggestion) async
    func checkTypedAddress() async       // the path of today, offered when there are no suggestions
    func clear() async
}
```

Seite: Schalter „Fahrzeit berücksichtigen“ mit Fußtext „Berechnet von Apple Karten. Tagwerk nutzt deinen Standort nicht.“ und dem Verweis „Mehr dazu“ (öffnet `TravelInfoView` mit den übrigen Sätzen von heute und dem neuen Satz „Beim Tippen der Adresse gehen deine Eingaben an Apple Karten.“); Abschnitt „Zuhause“ mit Suchfeld, Löschknopf und Vorschlägen als Zeilen (Titel, darunter PLZ und Ort); nach der Wahl „Gesichert: …“; ohne Vorschläge die Zeile „Adresse trotzdem prüfen“ (heutiger Weg); „Verkehrsmittel“; Schalter „Rückweg anzeigen“; Fußtext „Verkehrsmittel und Start lassen sich je Termin ändern.“ Der Platz in Einstellungen › Planung bleibt.

- [ ] **Step 1: Tests** (mit `FakeAddressSuggester`): `typing_showsSuggestions_afterTheDebounce`, `shortQuery_asksNothing`, `choose_storesAddressAndCoordinates_andReloadsThePlan`, `clear_removesTheHome`, `noSuggestions_offersTheTypedCheck`, `staleAnswer_isDropped` (eine spätere Eingabe gewinnt).
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: find the home address with suggestions and add the return-trip switch`.

### Task V5: Verkehrsmittel und Start auf der Seite des Termins (PL13b, PL14c)

**Files:**
- Modify: `app/Tagwerk/Planning/TravelOverrideView.swift`, `TravelText.swift:86–98` (`overrideSummary`), `PlanningModel+Travel.swift` (`setTravelChoice`)
- Test: `app/TagwerkTests/TravelTextTests.swift`, `PlanningModelTests.swift`

Seite: Abschnitt 1 „Automatisch“ (mit dem geltenden Wert, „✓ 25 min“), „Feste Dauer“ (mit Zähler), „Keine“. Nur im Modus „Automatisch“ folgen „Verkehrsmittel“ („Wie eingestellt (Auto)“ und die vier Verkehrsmittel) und „Start“ („Automatisch (Zuhause)“ bzw. „Automatisch (Vorheriger Termin)“ je nach geltender Regel, „Zuhause“, „Vorheriger Termin“; die letzte Zeile ist ohne früheren Termin mit Ort ausgegraut). „Sichern“ fragt bei Serien wie heute nach der Reichweite.

- [ ] **Step 1: Tests.** `overrideSummary_namesTheEventsTransport`, `setTravelChoice_reloadsAndChangesTheSegment`, `setTravelChoice_default_removesTheEntry`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: choose transport and start of the travel time per event`.

---

## Strang F: Fokus

### Task F1: Regel „früh fertig“ und Baustein statt Welken (FO9b, Regelteil von FO1b)

**Files:**
- Modify: `TagwerkCore/FocusReward.swift:33–80`, `app/Tagwerk/Focus/FocusTimerModel.swift:125–151` (Kommentare, Tests), `FocusRecords.swift:62–66`, `FocusTimerText.swift:43–47`, `FocusCollectionView.swift` (nur Umbenennung, Aussehen folgt in F2), `FocusCaptureSection.swift:40–42`
- Test: `TagwerkCoreTests/FocusRewardTests.swift`, `app/TagwerkTests/FocusTimerModelTests.swift`, `FocusCompletionTests.swift`, `FocusTimerTextTests.swift`, `BackupTests.swift:543`

**Interfaces (Produces):**

```swift
/// One piece of the collection: a brick of the stage reached. `endedEarly` marks a session that was stopped
/// before its phase ended; it keeps its stage (FO9b).
public enum FocusRewardPiece: Sendable, Equatable {
    case completed(FocusRewardStage)
    case endedEarly(FocusRewardStage)
    public var stage: FocusRewardStage { get }
    public var isEndedEarly: Bool { get }
}
public struct FocusCollectionSummary { public let completed: Int; public let endedEarly: Int; public var total: Int }
// FocusOutcome keeps its raw values "completed", "aborted", "discarded": stored sessions and backups stay readable.
// `aborted` now reads as "ended early".
```

Regel (das ist die Änderung, nicht nur das Aussehen):

| Handlung | Ergebnis (`FocusOutcome`) | Baustein |
|---|---|---|
| Timer läuft bis zum Ende | `completed` | erreichte Stufe |
| „Erledigt“ während einer Fokus- oder Pausenphase (Blatt, Live Activity, Aufgabe anderswo abgehakt) | `completed` | **erreichte** Stufe, nicht gestrichelt |
| „Beenden“ vor Phasenende, ab 1 min Fokuszeit | `aborted` | erreichte Stufe, gestrichelt („vorzeitig beendet“) |
| „Beenden“ oder „Erledigt“ unter 1 min Fokuszeit | `discarded` bzw. `completed` ohne Stufe | keiner |
| „Verschieben“ während der Fokusphase | `aborted` (wie heute) | erreichte Stufe, gestrichelt |

Im Modell ist die zweite Zeile schon so (`finish(.complete)` → `end(.completed)`); F1 schreibt sie als Tests fest, F3 bietet den Knopf an. Die Wörter „welken“, „gewelkt“, „gewachsen“ entfallen in allen Texten und in `en.json`.

- [ ] **Step 1: Tests.** `FocusRewardTests`: `piece_aborted_keepsTheReachedStage_asEndedEarly`, `piece_completedEarly_hasTheReachedStage`, `summary_countsEndedEarly`. `FocusTimerModelTests`: `completeDuringTheWorkPhase_isCompleted_withTheReachedStage` (18 von 25 min → `.completed(.two)`), `completeDuringABreak_isCompleted`, `completeWithinTheFirstMinute_leavesNoPiece`, `stopDuringThePhase_leavesAnEarlyPiece`, `storedAbortedSession_readsAsEndedEarly`. `FocusTimerTextTests.collectionSummary`: „7 Bausteine“, „7 Bausteine · 2 vorzeitig beendet“, „Noch leer“.
- [ ] **Step 2:** `PKG TagwerkCore FocusRewardTests`, `APP FocusTimerModelTests` → rot.
- [ ] **Step 3:** Umsetzen; `FocusTimerModelTests.swift:147` (`.wilted(.two)`) auf `.endedEarly(.two)`.
- [ ] **Step 4:** `ALL`. Commit `feat: count a task finished early as completed and keep the reached stage for sessions ended early`.

### Task F2: Sammlung als Bausteine je Wochentag (FO8c)

**Files:**
- Create: `TagwerkCore/FocusCollection.swift`
- Modify: `app/Tagwerk/Focus/FocusCollectionView.swift`
- Test: neu `TagwerkCoreTests/FocusCollectionTests.swift`

**Interfaces (Produces):**

```swift
public struct FocusBrick: Sendable, Equatable { public let piece: FocusRewardPiece; public let focusedMinutes: Int }
public struct FocusCollectionWeek: Sendable, Equatable, Identifiable {
    public let start: Date
    /// Seven days in the order of the calendar's week, each with its bricks in the order the sessions ended.
    public let days: [[FocusBrick]]
    public let focusedMinutes: Int
    public let summary: FocusCollectionSummary
}
public enum FocusCollection {
    public static func weeks(sessions: [(endedAt: Date, piece: FocusRewardPiece, focusedSeconds: Int)],
                             calendar: Calendar) -> [FocusCollectionWeek]   // newest week first
    /// Height of a brick in points for a column of `available` points that holds `bricks`; stages 1...5 map to
    /// 8, 14, 22, 32, 44 and shrink together when the column would overflow.
    public static func heights(of bricks: [FocusBrick], available: Double) -> [Double]
}
```

Ansicht: je Woche ein Abschnitt „Woche ab 16. Nov. · 4 h 35 min Fokus“, sieben Spalten mit Wochentagskürzel, je Sitzung ein Baustein (abgerundetes Rechteck in Akzentfarbe, vorzeitig beendet: gestrichelter Rand ohne Füllung), von unten gestapelt. Fußtext „7 Bausteine · Höhe nach Dauer (1, 10, 25, 50, 90 min) · gestrichelt: vorzeitig beendet“. VoiceOver je Wochentag ein Element: „Montag: 2 Bausteine, 50 Minuten Fokus, 1 vorzeitig beendet“. Leerer Zustand: „Jede Fokus-Sitzung ab einer Minute ergibt einen Baustein.“ Keine Grafikdateien.

- [ ] **Step 1: Tests.** `weeks_groupByWeekAndWeekday`, `weeks_newestFirst`, `weeks_sumFocusMinutes`, `heights_followTheStage`, `heights_shrinkWhenTheColumnOverflows`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL` (Audit „Erfassen“ unverändert; die Sammlung ist eine Unterseite).
- [ ] **Step 5:** Commit `feat: show the focus collection as bricks per weekday`.

### Task F3: Timer-Blatt mit Ring, drei Knöpfen, Rückfrage und „Danach“ (FO1b, FO2b, FO6b)

**Files:**
- Create: `app/Tagwerk/Focus/FocusUpNext.swift`
- Modify: `app/Tagwerk/Focus/FocusTimerView.swift`, `FocusTimerText.swift`
- Test: neu `app/TagwerkTests/FocusUpNextTests.swift`, `FocusTimerTextTests.swift`, `app/TagwerkUITests/` (Fokus-Start im vorhandenen Ablauf, falls es einen gibt; sonst `TaskFlowUITests.testFocusSheetOffersDoneWhileRunning`)

**Interfaces (Produces):**

```swift
// FocusTimerText
/// "bis 14:51" (EN "until 2:51 PM"); nil while paused.
static func endsAt(_ phaseEnd: Date?, calendar: Calendar, locale: Locale = .current) -> String?
/// "Fokus · Runde 1 von 4", "Fokus" without Pomodoro.
static func phaseLine(phase: FocusPhase, settings: FocusTimerSettings) -> String
/// "18 min bleiben als Fokuszeit für „Bericht schreiben“ gespeichert." / "… als Fokuszeit gespeichert." without a task.
static func stopMessage(focusedSeconds: Int, title: String) -> String

// FocusUpNext.swift
struct FocusUpNextRow: Identifiable, Equatable {
    enum Kind: Equatable { case blockEnd(title: String), departure(minutes: Int), entry(title: String, endMinutes: Int) }
    let startMinutes: Int
    let kind: Kind
}
enum FocusUpNext {
    /// The next rows of today after `nowMinutes`: the end of the session's block first, then entries and departures
    /// in time order; gaps are left out. At most `limit` rows.
    static func rows(timeline: [TimelineRow], blockEventID: String?, nowMinutes: Int, dayStart: Date, limit: Int = 3) -> [FocusUpNextRow]
}
```

Aufbau: Titel der Aufgabe oben (bei freier Sitzung „Fokus“), darunter `phaseLine`, Ring mit Restzeit und `endsAt` (pausiert: „Pausiert“), darunter drei runde Knöpfe mit Beschriftung: „Beenden“, „Pausieren“/„Fortsetzen“, „Erledigt“. „Erledigt“ erscheint nur, wenn die Sitzung eine Aufgabe hat (offene Frage 1). In einer Pause zusätzlich der Textknopf „Pause überspringen“. Nach Ablauf bleiben die vier Wahlmöglichkeiten von heute (Erledigt, Weiter, Verschieben, Beenden) unter dem Titel. Zahnrad oben rechts öffnet `FocusSettingsView` im Stapel des Blatts. Rückfrage: Titel „Fokus beenden?“, Text `stopMessage`, Knöpfe „Beenden“ (destruktiv) und „Weitermachen“; unter einer Minute weiter ohne Rückfrage. Abschnitt „Danach“: bis zu drei Zeilen aus `FocusUpNext` (Daten über `planning.dayPage(planning.today)` und `timelineWithGaps`), nur lesbar; fehlt der Tagesplan, entfällt der Abschnitt.

- [ ] **Step 1: Tests.** `rows_startWithTheBlockEnd`, `rows_includeDepartures`, `rows_skipGapsAndPastEntries`, `rows_respectTheLimit`; `endsAt_inBothLanguages`, `stopMessage_withAndWithoutTitle`; UI-Test: Fokus für eine Aufgabe starten, „Erledigt“ ist sichtbar, „Beenden“ zeigt „Fokus beenden?“ mit „Weitermachen“.
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL`; das Blatt bei AX5 im Simulator ansehen (Ring schrumpft, Knöpfe umbrechen in zwei Zeilen, nichts abgeschnitten).
- [ ] **Step 5:** Commit `feat: redesign the focus sheet with a ring, "Erledigt" while running and what comes next`.

### Task F4: Startblatt, Menüplatz und Einstellungen (FO7b, FO3b, FO12b)

**Files:**
- Create: `TagwerkCore/FocusStart.swift`, `app/Tagwerk/Focus/FocusStartSheet.swift`
- Modify: `app/Tagwerk/Focus/FocusTimerModel.swift:73–98`, `FocusStartButton.swift`, `FocusCaptureSection.swift:26–28`, `FocusTimerText.swift`, `app/Tagwerk/Tasks/TaskContextMenu.swift:47–88`, `app/Tagwerk/App/RootView.swift:37–41, 91–93`, `app/Tagwerk/Settings/FocusSettingsView.swift`, `SettingsView.swift:97`, `app/Tagwerk/Persistence/AppSettings.swift`, `app/Tagwerk/Backup/BackupDTOs.swift`
- Test: neu `TagwerkCoreTests/FocusStartTests.swift`, `app/TagwerkTests/FocusTimerModelTests.swift`, `FocusTimerTextTests.swift`, `BackupTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore/FocusStart.swift
public enum FocusStartChoice: Equatable, Sendable { case minutes(Int), untilBlockEnd, pomodoro }
public enum FocusStart {
    public static let presets = [15, 25, 45, 60]
    /// The settings of a session. `nil` keeps the behaviour of today (a block without Pomodoro runs to its end).
    public static func settings(base: FocusTimerSettings, choice: FocusStartChoice?, blockRemainingMinutes: Int?) -> FocusTimerSettings
    /// What the start sheet preselects: "bis Blockende" for a block, else the last choice, else the settings.
    public static func preselected(base: FocusTimerSettings, lastMinutes: Int?, hasBlock: Bool) -> FocusStartChoice
    /// The minutes a start without a sheet would run, for the menu title.
    public static func plannedMinutes(base: FocusTimerSettings, lastMinutes: Int?) -> Int
}
public enum FocusPreset: Equatable, Sendable { case classic, long, custom      // 25/5, 50/10, own values
    public static func matching(_ settings: FocusTimerSettings) -> FocusPreset
    public func applied(to settings: FocusTimerSettings) -> FocusTimerSettings }

// FocusTimerModel
struct StartRequest: Identifiable, Equatable { let id = UUID(); let task: TaskItem?; let block: CalendarEvent? }
/// The start sheet is shown for this request.
var pendingStart: StartRequest?
/// Shows the start sheet, or starts at once when "Dauer beim Start fragen" is off. Opens the running session instead.
func requestStart(task: TaskItem?, block: CalendarEvent?) async
func start(task: TaskItem?, block: CalendarEvent?, choice: FocusStartChoice? = nil) async

// AppSettings
var focusAsksDurationAtStart: Bool = true
/// Minutes of the last choice in the start sheet; nil before the first one.
var focusLastStartMinutes: Int? = nil
```

- **Startblatt** (halbhoch, über den Tabs wie das Timer-Blatt; `RootView.hasOpenSheet` kennt es): Titel der Aufgabe, bei einem Zeitblock „Zeitblock 14:00–15:00“; Kapseln 15, 25, 45, 60, bei einem Block „Bis Blockende · 28 min“, „Andere …“ (Zähler 5–120); Schalter „Pomodoro (4 × 25 / 5)“ (an: Kapseln ausgegraut); „Starten“; Verweis „Fokus-Einstellungen“ (Seite im Stapel des Blatts). Die Wahl in Minuten wird gemerkt.
- **Ohne Blatt:** Siri, Kontrollzentrum, Kurzbefehl (`setRunning`) und der Knopf am Block (F8) rufen `start` direkt.
- **Menü (FO3b):** `FocusStartButton` steht als erster Abschnitt des Kontextmenüs; Titel „Fokus starten · 25 min“ (`plannedMinutes`), bei laufender Sitzung „Fokus öffnen“.
- **Einstellungen (FO12b):** Zeile `LabeledContent("Fokus-Timer", value: …)` mit „25 min · Pomodoro aus“ bzw. „4 × 25 / 5“; Seite: Vorlagen als Segment („25 / 5“, „50 / 10“, „Eigene“), Schalter „Pomodoro (Runden mit Pausen)“, Zähler wie heute, Schalter „Dauer beim Start fragen“, Abschnitt „Sammlung“ mit „Sammlung ansehen“ und der Zahl der Bausteine, Abschnitt „Planung“ mit dem bestehenden Schalter.

- [ ] **Step 1: Tests.** `settings_minutes_switchPomodoroOff`, `settings_untilBlockEnd_usesTheRest_atLeastFive`, `settings_nil_behavesAsToday`, `preselected_blockPrefersItsEnd`, `preselected_lastChoiceBeforeSettings`, `preset_matching`, `preset_appliedKeepsRounds`; `FocusTimerModelTests`: `requestStart_showsTheSheet`, `requestStart_switchOff_startsAtOnce`, `requestStart_whileRunning_opensTheSession`, `start_withMinutes_storesTheSessionSettings`, `setRunning_neverShowsTheSheet`; `FocusTimerTextTests.startTitle`, `settingsSummary`; `BackupTests.focusStartSettings_roundTrip`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: choose the focus duration at the start and make the timer settings easier to find`.

### Task F5: Live Activity und Dynamic Island (FO10b, FO11b), mit Gerätetest

**Files:**
- Modify: `app/TagwerkWidget/FocusLiveActivity.swift`, `app/Tagwerk/Focus/Shared/FocusActivityAttributes.swift`, `FocusActivityIntents.swift`, `app/Tagwerk/Focus/FocusProtocols.swift:5–43`, `FocusActivityController.swift`, `FocusTimerModel+Intents.swift:5–15`, Katalog des Widget-Targets
- Test: `app/TagwerkTests/FocusActivityTests.swift`, `FocusTimerModelTests.swift`

**Interfaces (Produces):**

```swift
// FocusActivityContent and FocusActivityAttributes.ContentState (new fields optional, so a running activity decodes)
var phaseSeconds: Int?          // planned length of the running phase, for the bar and the ring
var nextKind: Kind?             // the phase that follows; nil when the session ends
var nextPhaseMinutes: Int?

// FocusIntentAction
case showCurrent                // brings the activity in line with the phase that runs now ("Pause starten")
// FocusTimerModel.handle(_:) ends with `await refresh()` for every action.
```

- **Sperrbildschirm, läuft:** Titel der Aufgabe groß; darunter „Fokus · Runde 1 von 4 · bis 14:51“ und rechts die Restzeit; Balken `ProgressView(timerInterval:)` (pausiert: fester Wert); ein Knopf „Pausieren“/„Fortsetzen“.
- **Phase vorbei (`isStale` oder `finished`):** Titel; „25 min Fokus geschafft ✓“ bzw. „Pause vorbei“; zwei Knöpfe: „Erledigt“ und, je nach `nextKind`, „Pause starten · 5 min“ (`showCurrent`) oder „Weiter“ (`keepGoing`). „Verschieben“ bleibt in der App.
- **Dynamic Island:** kompakt links ein Ring (`ProgressView(timerInterval:)` im Kreisstil), rechts die Restzeit, beides in der Phasenfarbe (Fokus Akzentblau, Pause Grün); minimal der Ring; farbiger Rand über `keylineTint`; ausgeklappt Titel groß, „Fokus · bis 14:51“, Restzeit, „Pausieren“ und „Erledigt“.

**Gerätetest (Pflicht, Ergebnis in den Pull Request):**

| Prüfpunkt | Ablauf | In Ordnung, wenn | Rückfall |
|---|---|---|---|
| L1 Umschalten am Phasenende | Fokus 5 min ohne Pomodoro, Gerät gesperrt; fünf Läufe, Verzögerung bis „Phase vorbei“ notieren; dasselbe entsperrt mit App im Hintergrund | in allen Läufen innerhalb von 10 s | Die laufende Ansicht zeigt „Erledigt“ **immer** neben „Pausieren“; der Zustand „Phase vorbei“ ist dann nur Zierde. Text der Fußzeile „Tippen für die nächste Phase“. |
| L2 Knöpfe vom Sperrbildschirm | „Erledigt“, „Pause starten“, „Weiter“ bei beendeter App | Aktion wirkt, Anzeige zeigt danach die richtige Phase | `showCurrent` öffnet die App (Intent mit `openAppWhenRun`). |
| L3 Zwei Knöpfe bei großer Schrift | Schriftgröße XXXL und AX3 | nichts abgeschnitten | Knöpfe untereinander ab Bedienungshilfen-Größen. |
| D1 Ring in der Insel | kompakt, minimal (zweite Aktivität: Timer der Uhr-App), ausgeklappt | Ring füllt sich sichtbar, Farbe unterscheidet Tagwerk vom System-Timer | Füllt sich der Ring kompakt nicht: Symbol `timer` in der Phasenfarbe (FO11a mit Farbe). |
| D2 Rand und Farben | hell, dunkel, Always-On | Rand und Ziffern lesbar | Rand weglassen, Ziffern weiß, Ring farbig. |

- [ ] **Step 1: Tests.** `content_carriesPhaseSecondsAndTheNextPhase`, `content_lastRound_hasNoNextPhase`, `decode_withoutNewFields_works`; `handle_showCurrent_updatesTheActivity`, `handle_everyAction_refreshes`.
- [ ] **Step 2–3:** rot, umsetzen (Widget-Texte Deutsch und Englisch).
- [ ] **Step 4:** `ALL`; Gerätetest L1–L3, D1–D2; Rückfälle nach Befund umsetzen.
- [ ] **Step 5:** Commit `feat: put the task first in the focus Live Activity and make the Dynamic Island recognisable`.

### Task F6: Wochenrückblick mit Balken (FO14b)

**Files:**
- Modify: `app/Tagwerk/Focus/EffortReviewSection.swift:10–33`, `EffortReviewText.swift`
- Test: `app/TagwerkTests/EffortReviewTextTests.swift`

**Interfaces (Produces):**

```swift
// EffortReviewText
/// Scale of the bars: −50 % … +100 %, with "wie geschätzt" at a third of the width.
static let scale = -50...100
/// Position of a deviation on the scale, 0...1, clamped; 1/3 is "as estimated".
static func position(deviationPercent: Int) -> Double
/// "+40 %", "±0 %" (within the tolerance), "−15 %".
static func deviationLabel(_ percent: Int, language: VoiceLanguage = .app) -> String
/// "2 von 3 Messungen" for a group below the minimum.
static func pendingLabel(count: Int, language: VoiceLanguage = .app) -> String
```

Abschnitt „Schätzung und Ist · letzte 8 Wochen“: Skalenzeile („−50 %“, „wie geschätzt“, „+100 %“), je Gruppe eine Zeile mit Name, Balken von der Mitte (rechts orange: länger, links blau: kürzer; über die Skala hinaus mit Pfeilspitze), Wert und darunter „7 Aufgaben“. Quellen zuerst, Labels mit „↳“ eingerückt darunter. Gruppen unter drei Messungen grau mit `pendingLabel`, ohne Balken. VoiceOver liest je Zeile den heutigen Satz (`detail(of:)`). Die Kennzahl bleibt das mittlere Verhältnis; keine neue Auswertung. Die Zeilen „Fokus in dieser Woche“ und „Messungen in dieser Woche“ bleiben.

- [ ] **Step 1: Tests.** `position_centreIsAThird`, `position_clampsAtBothEnds`, `deviationLabel_signsAndTolerance`, `pendingLabel_inBothLanguages`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: show estimate against actual as bars around "as estimated"`.

### Task F7: Leiste über den Tabs (FO5b), mit Gerätetest

**Files:**
- Create: `app/Tagwerk/Focus/FocusAccessoryBar.swift`
- Modify: `app/Tagwerk/App/RootView.swift:49–76`, `app/Tagwerk/Planning/PlanView.swift:29–117` und jede weitere Stelle mit einer Rückgängig-Kapsel über dem unteren Rand (`UndoCapsule(`, `HandedOverCapsule(`), `app/Tagwerk/Tasks/UndoCapsule.swift`
- Test: `app/TagwerkTests/FocusTimerTextTests.swift`, `app/TagwerkUITests/TaskFlowUITests.swift`

**Interfaces (Produces):**

```swift
/// One line above the tab bar while a focus session runs: progress ring, title, remaining time, pause button.
/// A tap opens the timer sheet. Green with "Pause" during a break.
struct FocusAccessoryBar: View
enum UndoCapsuleMetrics {
    /// Distance of an undo capsule from the bottom edge; larger while the focus bar is shown.
    static func bottomInset(focusBarVisible: Bool) -> CGFloat     // 60, or 60 plus the height of the bar
}
// FocusTimerText
/// "Bericht schreiben, noch 18 Minuten 42 Sekunden, Fokus" for VoiceOver.
static func barAccessibility(title: String, remainingSeconds: Int, phase: FocusPhase) -> String
```

Umsetzung als Zubehörleiste der Tab-Leiste (`tabViewBottomAccessory`), nur solange `focus.session != nil` (bedingte Form der API gegen das SDK prüfen). Eine Aktualisierung je Sekunde über `TimelineView`, nur für die Leiste. In verkleinerter Lage der Leiste (falls das System sie verkleinert): nur Ring und Restzeit. Alle Kapseln lesen ihren Abstand aus `UndoCapsuleMetrics`. Die Zeile am Ende von „Erfassen“ bleibt.

**Gerätetest (Pflicht):**

| Prüfpunkt | Ablauf | In Ordnung, wenn |
|---|---|---|
| A1 Sichtbarkeit | Fokus starten, Blatt schließen, alle vier Tabs | Leiste überall, Tipp öffnet das Blatt, Pausieren wirkt ohne Blatt |
| A2 Kapseln | in „Planen“ eine Aufgabe abhaken, einen Block duplizieren, Vorschläge verwerfen; in „Aufgaben“ abhaken | Kapsel liegt vollständig über der Leiste, „Rückgängig“ ist tippbar |
| A3 Tastatur und Blätter | Suche öffnen, Notiz schreiben, Terminblatt öffnen | Leiste verdeckt kein Eingabefeld und liegt nicht über Blättern |
| A4 Scrollen | lange Listen in allen Tabs | Inhalt endet nicht unter der Leiste; verkleinerte Lage zeigt Ring und Zeit |
| A5 Bedienungshilfen | VoiceOver, AX3 | ein Element mit `barAccessibility`, Pausieren als Aktion; Text nicht abgeschnitten |

**Rückfall:** Erfüllt die Zubehörleiste A2, A3 oder A4 nicht oder lässt sie sich nicht an die laufende Sitzung binden, wird dieselbe `FocusAccessoryBar` über `.safeAreaInset(edge: .bottom)` an der Wurzel der vier Tab-Inhalte eingesetzt (vier Stellen in `RootView`); die Kapseln behalten dann den Abstand 60, weil die Sicherheitszone wächst. Scheitert auch das an A3, bleibt FO5a (keine Leiste), und die Hauptsitzung kommentiert in #188.

- [ ] **Step 1: Tests.** `barAccessibility_inBothLanguages`; `UndoCapsuleMetrics` (zwei Werte); UI-Test `testFocusBarReturnsToTheSheet` (Fokus starten, schließen, Tab „Aufgaben“, Leiste tippen, Blatt ist offen).
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL` (die Audits laufen ohne Fokus-Sitzung und dürfen sich nicht ändern); Gerätetest A1–A5.
- [ ] **Step 5:** Commit `feat: show the running focus session in a bar above the tabs`.

### Task F8: Fokus im Plan: Knopf am Block und Text im gekürzten Block (FO4b, FO15b), nach P3 und F4, mit Gerätetest

**Branch:** `feat/g1-focus-in-plan`

**Files:**
- Modify: `TagwerkCore/NowMarker.swift`, `app/Tagwerk/Planning/TimelineCanvas.swift:194–236`, `DayView.swift:205–212, 506–525`, `DayPageExtras.swift`, `PlanningModel.swift` (Extras füllen), `app/Tagwerk/Focus/EffortTracker.swift`, `FocusTimerText.swift`
- Test: `TagwerkCoreTests/NowMarkerTests.swift`, `app/TagwerkTests/EffortTrackerTests.swift`, `FocusTimerTextTests.swift`, `app/TagwerkUITests/PlanUITests.swift`

**Interfaces (Produces):**

```swift
// NowMarker
/// The block that carries the focus button today: the running one, else the next that starts after now; nil otherwise.
public static func focusBlockIndex(blockRanges: [Range<Int>], nowMinutes: Int?) -> Int?

// DayPageExtras
/// Blocks that were cut when their task was completed, by event ID (FO15b).
var trimmedBlocks: [String: TrimmedBlock] = [:]
struct TrimmedBlock: Equatable { let plannedMinutes: Int; let actualMinutes: Int }

// EffortTracker
/// Cut blocks among `events`: a sample names the event and its stored new end still equals the event's end.
func trimmedBlocks(among events: [CalendarEvent]) -> [String: TrimmedBlock]

// FocusTimerText
/// "35 von 60 min · 25 min früher fertig"; short form "35 von 60 min".
static func trimDetail(_ block: TrimmedBlock, short: Bool = false) -> String
```

- **FO4b:** Der Zeitblock mit verknüpfter Aufgabe aus `focusBlockIndex` trägt im Raster und in der Liste „▶ Fokus“ (schmale Spalte: nur das Symbol). Ein Tipp ruft `focus.start(task:block:choice: .untilBlockEnd)` ohne Startblatt. Läuft schon eine Sitzung, zeigt der Block statt des Knopfs ein Uhrsymbol (Sitzung dieses Blocks) oder nichts.
- **FO15b:** Ein gekürzter Block zeigt „✓ “ vor dem Titel und `trimDetail` statt der Zeitzeile; in der Liste dieselbe Unterzeile. Wurde das Ende danach von Hand geändert (`trimmedNewEnd` ≠ Ende), entfällt die Marke.

**Gerätetest FO4b (Pflicht):**

| Prüfpunkt | Ablauf | In Ordnung, wenn |
|---|---|---|
| B1 Tipp | Knopf im laufenden Block tippen | Fokus startet, das Blockblatt öffnet sich **nicht** |
| B2 Halten | auf dem Knopf 0,5 s halten und ziehen | kein Fokus-Start; der Block lässt sich verschieben oder nichts geschieht |
| B3 Seitenwechsel | waagrecht über den Knopf wischen | Seite wechselt, kein Fokus-Start |
| B4 Kurzer Block | 15-Minuten-Block, zwei Spalten | Knopf mindestens 44 pt breit und 28 pt hoch tippbar, Titel bleibt lesbar |
| B5 Griffe | Block auswählen (Griffe sichtbar), Knopf tippen | Fokus startet, Griffe lösen kein Ziehen aus |

**Rückfall:** Scheitert B1, B2 oder B3 auch mit `highPriorityGesture` am Knopf, entfällt der Knopf im Raster (FO4a: Start über das Blockblatt) und bleibt in der Liste, wo Knöpfe in Zeilen zuverlässig Vorrang haben; der laufende Block im Raster zeigt dann nur das Symbol „▶“ als Hinweis ohne eigene Trefferfläche.

- [ ] **Step 1: Tests.** `focusBlockIndex_prefersTheRunningBlock`, `…_elseTheNext`, `…_otherDay_isNil`; `trimmedBlocks_onlyWhileTheEndIsUnchanged`; `trimDetail_longAndShort`; `PlanUITests.testFocusButtonOnTheRunningBlockStartsFocus` (feste Uhrzeit der UI-Tests so, dass ein Demo-Block läuft).
- [ ] **Step 2–3:** rot, umsetzen.
- [ ] **Step 4:** `ALL`; Gerätetest B1–B5.
- [ ] **Step 5:** Commit `feat: start focus from the running time block and mark blocks that ended early`.

---

## Strang E: Erinnerungen

### Task E1: Wortlaut je Art (ER6b)

**Files:**
- Modify: `TagwerkCore/ReminderText.swift`, Paket-Katalog, alle Aufrufer von `describe`/`summary` (`Reminders/ReminderListEditor.swift:18`, `ReminderOffsetPicker.swift:53, 82`, `Planning/EntrySheet.swift:244`, `Settings/SettingsView.swift:105`)
- Test: `TagwerkCoreTests/ReminderTextTests.swift`

**Interfaces (Produces):**

```swift
/// What a reminder counts from; decides the wording of the distance 0.
public enum ReminderSubject: Sendable { case task, event, deadline }

public enum ReminderText {
    /// Distance 0: "Zur Fälligkeit" (task), "Zum Beginn" (event), "Zur Deadline" (deadline); for an entry without a
    /// time of day "Am Tag selbst". `subject` has no default on purpose.
    public static func describe(_ offset: ReminderOffset, subject: ReminderSubject, isAllDay: Bool = false,
                                locale: Locale = .current, calendar: Calendar = .current) -> String
    public static func summary(_ list: [ReminderOffset], subject: ReminderSubject, isAllDay: Bool = false, …) -> String
    /// The row in a form: "Standard · 1 Tag vorher um 18:00 + 1 weitere", without the prefix for an own list, "Keine".
    public static func rowSummary(_ list: [ReminderOffset], isDefault: Bool, subject: ReminderSubject, isAllDay: Bool = false, …) -> String
}
```

„Am selben Tag um 9:00“ wird zu „Am Tag selbst um 9:00“ (Mockup ER7b). Englisch: „At due time“, „At start“, „At the deadline“, „On the day“, „On the day at 9:00 AM“. Der Schlüssel „Zum Zeitpunkt“ entfällt in Katalog und `en.json`.

- [ ] **Step 1: Tests.** `describe_zero_perSubject` (drei Arten, mit und ohne Uhrzeit, Deutsch und Englisch), `describe_sameDayAtTime`, `rowSummary_prefixesTheDefault`, `rowSummary_emptyOwnList_isKeine`; die bestehenden Erwartungen mit „Zum Zeitpunkt“ anpassen.
- [ ] **Step 2:** `PKG TagwerkCore ReminderTextTests` → rot. **Step 3:** umsetzen, Aufrufer mit der richtigen Art versorgen (Editor: `.task`; Terminblatt einer Deadline: `.deadline`; „Termin bearbeiten“: `.event`; Einstellungszeile: `.task`).
- [ ] **Step 4:** `ALL`. Commit `fix: name what a reminder at the time itself refers to`.

### Task E2: Auswahlseite mit Häkchen und eine Zeile im Editor (ER2b, ER1b, ER3a)

**Files:**
- Create: `TagwerkCore/ReminderChoices.swift`, `app/Tagwerk/Reminders/ReminderSelection.swift` (ersetzt `ReminderListEditor.swift`)
- Modify: `app/Tagwerk/Reminders/ReminderListModel.swift`, `ReminderOffsetPicker.swift:48–56, 84–95`, `app/Tagwerk/Editor/TaskEditorView.swift:297–322`
- Test: neu `TagwerkCoreTests/ReminderChoicesTests.swift`, `app/TagwerkTests/ReminderListModelTests.swift`, `TaskReminderTests.swift`

**Interfaces (Produces):**

```swift
// TagwerkCore
public enum ReminderChoices {
    /// The usual distances: with a time 0, 15 min, 1 h, 1 day, 1 week; without a time 0 days, 1 day, 1 week.
    public static func common(isAllDay: Bool) -> [ReminderOffset]
    /// The rows of the selection page: the common distances and every reminder that is set, without duplicates,
    /// in the order of `ReminderOffset.normalized`.
    public static func rows(selected: [ReminderOffset], isAllDay: Bool) -> [ReminderOffset]
}

// ReminderListModel
/// Sets the reminder when it is missing, removes it when it is there. While the default applies, the own list
/// starts from the default first.
func toggle(_ offset: ReminderOffset)
func isSelected(_ offset: ReminderOffset) -> Bool

// ReminderSelection.swift
/// Rows for a `Section`: the default switch, the choices with checkmarks, "Eigene …".
struct ReminderSelectionRows: View {
    @Bindable var model: ReminderListModel
    let subject: ReminderSubject
    var defaultSwitchTitle: LocalizedStringKey? = "Standard verwenden"
    var calendar: Calendar = .tagwerk
}
/// The same as a page with the title "Erinnerungen" and an optional footer.
struct ReminderSelectionPage: View { … var footer: String? }
```

- Seite: Schalter „Standard verwenden“; Zeilen aus `ReminderChoices.rows` mit Häkchen (solange der Standard gilt, grau mit den Häkchen des Standards); ein Tipp setzt oder entfernt; „Eigene …“ öffnet `ReminderOffsetPicker` (Segment, Zähler, Uhrzeit, Vorschau; der Abschnitt „Schnellauswahl“ entfällt dort). Fußtext „Antippen setzt oder entfernt eine Erinnerung.“ Feste Zeitpunkte aus dem Kalender (`.absolute`) erscheinen als gesetzte Zeilen und lassen sich nur entfernen.
- Editor (ER1b, ER3a): Der Abschnitt „Erinnerungen“ wird eine Zeile direkt unter „Fällig“: `NavigationLink` mit `LabeledContent("Erinnerungen", value: rowSummary(…))`; ohne Fälligkeit ausgegraut mit „Braucht eine Fälligkeit“. Der Fußtext für Apple-Erinnerungen wandert auf die Seite.
- `ReminderListEditor` entfällt; `DeadlineReminderSheet`, `ReminderDefaultsView` und `EventEditSheet` nutzen bis E3/E4 `ReminderSelectionRows` an derselben Stelle.

- [ ] **Step 1: Tests.** `rows_containCommonAndSelected_once`, `rows_allDay_haveNoHourDistances`, `rows_keepAbsoluteAlarms`; `toggle_setsAndRemoves`, `toggle_whileDefault_startsFromTheDefault`, `toggle_equivalentDistance_countsAsSelected` (60 min und 1 h); `TaskReminderTests.openingAndClosing_writesNothing`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL` (Audit des Editors: die Zeile darf bei AX5 umbrechen, nicht abschneiden).
- [ ] **Step 5:** Commit `feat: pick reminders from a list with checkmarks and show them as one row in the editor`.

### Task E3: Standard-Erinnerungen als Übersicht (ER7b)

**Files:**
- Modify: `app/Tagwerk/Settings/ReminderDefaultsView.swift`, `app/Tagwerk/Reminders/ReminderDefaultsModel.swift` (Namen der Arten)
- Test: `app/TagwerkTests/ReminderDefaultsModelTests.swift`

Seite: fünf Zeilen (Kalendertermine, Apple Erinnerungen, GitHub-Issues, Lokale Aufgaben, Deadline-Termine) mit der Kurzform der Liste „mit Uhrzeit“; Fußtext „Gilt für alles ohne eigene Erinnerungen. Für Kalendertermine nur beim Anlegen in Tagwerk.“ Jede Zeile öffnet eine Unterseite mit „Mit Uhrzeit“ und „Ohne Uhrzeit“ (Kalender- und Deadline-Termine: „Ganztägig“), je mit Kurzform; dahinter `ReminderSelectionPage` ohne Standard-Schalter. Die zehn Listen und ihre Speicherung bleiben.

- [ ] **Step 1: Tests.** `ReminderDefaultsModelTests`: `kindTitle_forEveryKind`, `rowSummary_usesTheSubjectOfTheKind` (Termine „Zum Beginn“, Deadlines „Zur Deadline“), `changingOneList_keepsTheOtherNine`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: turn the default reminders into an overview with a page per kind`.

### Task E4: Deadline-Termine: zwei benannte Abschnitte und Serienfrage (ER5b, ER8b)

**Files:**
- Modify: `app/Tagwerk/Reminders/DeadlineReminderSheet.swift`, `DeadlineReminderModel.swift`, `app/Tagwerk/Planning/EventEditSheet.swift:67–71`, `app/Tagwerk/Editor/TaskEditorView.swift:219–241, 376`
- Create: `TagwerkCore/ReminderDuplicates.swift`
- Test: neu `TagwerkCoreTests/ReminderDuplicatesTests.swift`, `app/TagwerkTests/DeadlineReminderTests.swift`

**Interfaces (Produces):**

```swift
public enum ReminderDuplicates {
    /// Reminders of both lists that fire in the same minute for this entry.
    public static func find(tagwerk: [ReminderOffset], calendarAlarms: [ReminderOffset], anchor: Date, isAllDay: Bool,
                            calendar: Calendar) -> [(offset: ReminderOffset, fire: Date)]
}
public enum ReminderReachText {
    /// "Erinnerungen für welche Termine ändern?" / "… welche Fälligkeiten ändern?"
    public static func title(_ subject: ReminderSubject, locale: Locale = .current) -> String
    /// "Nur am 27. Nov." and "Ab 27. Nov. für alle folgenden".
    public static func onlyThis(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String
    public static func fromThis(_ day: PlanDay, calendar: Calendar, locale: Locale = .current) -> String
}

// DeadlineReminderModel
/// The alarms of the calendar event; nil when the event cannot be edited (then the section is read-only).
let calendarAlarms: ReminderListModel?
```

- Seite (Titel des Termins): Abschnitt „Tagwerk-Mitteilungen“ (Glocke) mit `ReminderSelectionRows(subject: .deadline)` und Fußtext „Kommen als Mitteilung von Tagwerk. Ruhezeiten und Fokus-Filter gelten.“; Abschnitt „Hinweise im Kalender (Apple)“ (Wecker) mit den Alarmen des Termins, „Hinweis hinzufügen“ und Fußtext „Gehören zum Kalendertermin und erscheinen auf allen Geräten. Ruhezeiten gelten dafür nicht.“; gelber Kasten bei Dopplung: „Doppelt: „1 Tag vorher“ – Tagwerk und Kalender erinnern beide am So., 22. Nov.“
- „Sichern“ schreibt beide Listen; die Alarme über denselben Weg wie `EventEditSheet` (bei Serien mit der Reichweite aus der Frage: „nur dieser“ bzw. „dieser und alle folgenden“). Nicht bearbeitbare Termine und Einladungen: Abschnitt nur lesbar mit dem Grund.
- `EventEditSheet`: Der Abschnitt heißt „Hinweise im Kalender“, der Knopf „Hinweis hinzufügen“ (offene Frage 4).
- ER8b: Frage „Erinnerungen für welche Termine ändern?“ mit „Nur am 27. Nov.“, „Ab 27. Nov. für alle folgenden“, „Abbrechen“; dieselbe Form im Aufgaben-Editor („… welche Fälligkeiten ändern?“).

- [ ] **Step 1: Tests.** `find_sameMinute_isADuplicate`, `find_differentTimes_isEmpty`, `find_allDay_usesTheDayStart`; `reachText_namesTheDay_inBothLanguages`; `DeadlineReminderTests`: `save_writesBothLists`, `save_readOnlyEvent_writesOnlyTagwerk`, `duplicates_areReported`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: show Tagwerk notifications and calendar alerts of a deadline on one page`.

### Task E5: Glocke in der Aufgabenzeile nur bei Abweichung (ER4b)

**Files:**
- Modify: `TagwerkCore/ReminderOverride.swift` (Ergänzung), `app/Tagwerk/Tasks/TaskRow.swift:30–45, 94–108`, `TaskListModel.swift`, Aufrufer von `TaskRow` (`TaskListView`, `Search/SearchRows.swift:87`)
- Test: `TagwerkCoreTests/ReminderOverrideTests.swift`, `app/TagwerkTests/TaskRowTextTests.swift`, `TaskListModelTests.swift`

**Interfaces (Produces):**

```swift
/// What a task row says about reminders: nothing while the default applies.
public enum ReminderMark: Equatable, Sendable {
    case custom(count: Int)     // bell with the number
    case none                   // crossed-out bell: an own, empty list
    public static func of(task: TaskItem, overrides: [String: [ReminderOverride]]) -> ReminderMark?
}
// TaskRow
var reminderMark: ReminderMark? = nil
// TaskListModel
/// Marks by task key, rebuilt on reload and after the editor saved reminders.
private(set) var reminderMarks: [String: ReminderMark]
```

Die Marke steht am Ende der Unterzeile: „🔔 3“ (`bell.fill` mit Zahl) oder `bell.slash`; nur bei Aufgaben mit Fälligkeit. VoiceOver ergänzt „3 eigene Erinnerungen“ bzw. „keine Erinnerungen“. Reihenfolge der Unterzeile mit Gruppe 3 (Status) siehe „Abgrenzung“.

- [ ] **Step 1: Tests.** `mark_default_isNil`, `mark_ownList_countsIt`, `mark_emptyOwnList_isNone`, `mark_withoutDue_isNil`, `mark_appleReminderWithOwnAlarms_counts`; `TaskRowTextTests.accessibilityLabel_namesOwnReminders`; `TaskListModelTests.reminderMarks_refreshAfterSaving`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: mark tasks whose reminders differ from the default`.

### Task E6: Erinnerungen im Blatt „Neue Aufgabe“ (ER9b)

**Files:**
- Modify: `app/Tagwerk/Tasks/NewTaskSheet.swift:156–166` und `save()`
- Test: `app/TagwerkTests/TaskReminderTests.swift`, `app/TagwerkUITests/TaskFlowUITests.swift`

Sobald „Fällig“ eingeschaltet ist, erscheint im selben Abschnitt die Zeile „Erinnerungen“ mit „Standard“ (das Blatt ist ein Formular; die Kapsel des schematischen Mockups wird zur Zeile). Sie öffnet `ReminderSelectionPage`; ohne Tipp bleibt der Standard. Das Blatt hält dafür ein `ReminderListModel` mit dem Standard der gewählten Quelle und passt es an, wenn Quelle oder „Uhrzeit“ wechseln (`configure`). Nach dem Anlegen schreibt `TaskReminderModel(item: created, …).save(…)` eine eigene Liste (Apple-Erinnerungen: als Alarme; wiederkehrende lokale Aufgaben: für alle folgenden). Schlägt nur das Schreiben der Erinnerungen fehl, bleibt die Aufgabe angelegt und das Blatt meldet den Fehler wie der Editor.

- [ ] **Step 1: Tests.** `newTask_untouched_writesNoOverride`, `newTask_ownList_isStoredForTheCreatedTask`, `newTask_sourceChange_resetsToThatDefault`; UI-Test `testNewTaskOffersRemindersOnceDueIsSet`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: set reminders while creating a task once it has a due date`.

---

## Strang R: Ruhezeiten

### Task R1: Fokus-Filter mit 4-Stunden-Rückfall (RH4b), mit Gerätetest

**Files:**
- Modify: `TagwerkCore/FocusQuiet.swift:27–96`, `app/Tagwerk/Notifications/NotificationScheduler.swift:138–140`, `app/Tagwerk/Intents/IntentServices.swift:51–53`
- Test: `TagwerkCoreTests/FocusQuietTests.swift`, `app/TagwerkTests/NotificationSchedulerQuietHoursTests.swift:95–139`

**Interfaces (Produces):**

```swift
public enum FocusQuiet {
    /// With quiet hours set up: held notifications wait this long after the start when iOS never reports the end.
    public static let unreportedEndHold: TimeInterval = 4 * 3600
    /// Without quiet hours (unchanged): 8 hours, so a sleep Focus does not end in the middle of the night.
    public static let openEndedHold: TimeInterval = 8 * 3600

    /// Where held notifications go when the end is never reported: 4 hours after the start, moved to the end of the
    /// quiet hours when that moment lies inside them; 8 hours after the start without quiet hours.
    public static func fallbackTarget(since: Date, quietHours: QuietHours?, calendar: Calendar) -> Date
    /// Uses `fallbackTarget`; nil when inactive, stale or when the target has passed.
    public static func hold(since: Date?, now: Date, quietHours: QuietHours?, calendar: Calendar) -> FocusHold?
    /// The end of the filter starts a catch-up only while the fallback target has not passed: what was held has
    /// been delivered otherwise, and what came due after the target was never held.
    public static func applying(active: Bool, now: Date, to state: State, quietHours: QuietHours? = nil,
                                calendar: Calendar = .current) -> State
}
```

Beispiele (Ruhezeit 23–7 Uhr): Fokus ab 14:00, fällig 15:00, Ende gemeldet 17:00 → Zustellung 17:01. Ende nie gemeldet → 18:00. Fokus ab 21:30 → 01:30 liegt in der Ruhezeit → 07:00. Fokus ab 09:00, Ende gemeldet 17:00 → fällig 10:00 kam um 13:00, fällig 15:00 kam um 15:00; um 17:00 kommt **nichts** erneut.

**Gerätetest RH4 (Pflicht, Zuverlässigkeit der Meldung):**

| Prüfpunkt | Ablauf | Notieren |
|---|---|---|
| Q1 Ende von Hand | Fokus „Arbeiten“ mit Filter ein, Aufgabe fällig in 5 min, nach 10 min Fokus aus; App im Hintergrund und einmal beendet | kommt die Mitteilung binnen 2 min nach dem Ende? |
| Q2 Ende nach Zeitplan | Fokus mit Zeitplan (15 min) | wie Q1 |
| Q3 Ende auf anderem Gerät | Fokus auf dem iPad oder Mac beenden (geteilter Fokus) | wird das Ende gemeldet? |
| Q4 Gerät gesperrt über Nacht | Schlaf-Fokus mit Filter | Zustellung am Ende der Ruhezeit, nichts doppelt |
| Q5 Rückfall | App beenden, Fokus 4 h 10 min laufen lassen (Uhrzeit des Geräts nicht verstellen) | Zustellung 4 h nach Beginn |

**Rückfall:** Wird das Ende in Q1 oder Q2 nicht zuverlässig gemeldet (mehr als einer von fünf Läufen ohne Meldung), bleibt die Regel wie gebaut (der 4-Stunden-Rückfall ist genau dafür da); der Text der Anleitung (R3) nennt dann „spätestens nach 4 Stunden“ an erster Stelle, und die Hauptsitzung kommentiert in #188, ob der Wert gesenkt werden soll. Kein weiterer Code.

- [ ] **Step 1: Tests.** `fallbackTarget_fourHoursAfterTheStart`, `fallbackTarget_insideQuietHours_movesToTheirEnd`, `fallbackTarget_withoutQuietHours_isEightHours`, `hold_endsAtTheFallbackTarget`, `applying_endBeforeTheTarget_startsTheCatchUp`, `applying_endAfterTheTarget_startsNoCatchUp`; Scheduler: `focusActive_withQuietHours_holdsForFourHours` (ersetzt `…holdsUntilTheirEnd`), `focusActive_fallbackInsideQuietHours_movesToTheirEnd`, `focusEndsAfterTheFallback_deliversNothingTwice`, `focusActive_holdsNotificationsBack_untilEightHoursAfterTheStart` bleibt grün.
- [ ] **Step 2:** `PKG TagwerkCore FocusQuietTests`, `APP NotificationSchedulerQuietHoursTests` → rot.
- [ ] **Step 3:** Umsetzen; `IntentServices.setFocusQuiet` und der Planer reichen Ruhezeit und Kalender durch.
- [ ] **Step 4:** `ALL`; Gerätetest Q1–Q5.
- [ ] **Step 5:** Commit `fix: release notifications four hours after a Focus started when its end is never reported`.

### Task R2: Wortlaut verschobener Mitteilungen und des Fokus-Filters (RH2b, RH5b)

**Files:**
- Modify: `TagwerkCore/NotificationPlan.swift:209–246`, Paket-Katalog, `app/Tagwerk/Intents/QuietFocusFilter.swift:7–18`, Katalog der App Intents
- Test: `TagwerkCoreTests/NotificationPlanTests.swift` (Suite mit den Texten), `app/TagwerkTests/NotificationSchedulerQuietHoursTests.swift:52`

Neue Texte:

| Fall | Deutsch | Englisch |
|---|---|---|
| Aufgabe mit Uhrzeit, verschoben | „Seit gestern, 23:30 fällig · Privat“ | “Due since yesterday, 11:30 PM · Private” |
| Aufgabe ohne Uhrzeit, verschoben | „Seit gestern fällig · Privat“ | “Due since yesterday · Private” |
| Deadline mit Uhrzeit, verschoben | „Deadline seit gestern, 23:30 abgelaufen“ | “Deadline passed yesterday, 11:30 PM” |
| Deadline ganztägig, verschoben | „Deadline seit gestern abgelaufen“ | “Deadline passed yesterday” |
| älterer Tag | „Seit Mo., 23.11., 23:30 fällig · Privat“ (ohne „am“) | “Due since Mon, 11/23, 11:30 PM · Private” |
| Fokus-Filter, Titel | „Mitteilungen zurückhalten“ | “Hold Notifications” |
| Fokus-Filter, Schalter | „Aufgaben und Deadlines zurückhalten“ | “Hold tasks and deadlines” |
| Fokus-Filter, Beschreibung | „Tagwerk meldet sich nach dem Fokus, spätestens nach 4 Stunden. Nichts entfällt.“ | “Tagwerk notifies you after the Focus, after 4 hours at the latest. Nothing is dropped.” |
| Fokus-Filter, Anzeige | „Mitteilungen nach dem Fokus“ / „Mitteilungen wie gewohnt“ | “Notifications after the Focus” / “Notifications as usual” |

Die Beschreibung weicht vom Mockup ab („Tagwerk meldet sich erst nach dem Fokus.“), weil sie sonst der Regel aus R1 widerspräche (offene Frage 6). Typ- und Parameternamen des Filters bleiben; ein eingerichteter Filter gilt weiter (Prüfung in Z1).

- [ ] **Step 1: Tests.** Erwartungen der überfälligen Texte in beiden Sprachen, je ein Fall der Tabelle; nicht verschobene Texte („Fällig heute um …“) unverändert.
- [ ] **Step 2–4:** rot, umsetzen, `ALL` (`check-strings.py` prüft den Katalog der Intents).
- [ ] **Step 5:** Commit `fix: say that a held notification is still due and name the Focus filter "zurückhalten"`.

### Task R3: Seite „Ruhezeiten“ mit Zeitbalken und Listen (RH1b)

**Files:**
- Create: `app/Tagwerk/Settings/FocusFilterGuideView.swift`
- Modify: `app/Tagwerk/Settings/QuietHoursSettingsView.swift`, `TagwerkCore/QuietHours.swift` (Ergänzung)
- Test: `TagwerkCoreTests/QuietHoursTests.swift`, Audit der Einstellungen (falls die Seite dort geprüft wird)

**Interfaces (Produces):**

```swift
// QuietHours
/// The window as fractions of the day for a 24-hour bar: one part, or two when it crosses midnight.
public var dayFractions: [ClosedRange<Double>] { get }

/// 24-hour bar with ticks at 0, 6, 12, 18 and 24 and the quiet window filled.
struct QuietHoursBar: View { let window: QuietHours }
```

Seite: Schalter „Ruhezeiten“; Zeile „Beginn“ als Auswahl („Zielschlafzeit · 23:00“ oder „Eigene Uhrzeit“ mit Zeitwähler; speichert weiter `quietHoursStartsAtBedtime`); „Ende“; der Balken; Satz „In dieser Zeit hält Tagwerk Mitteilungen zurück. Sie kommen um 07:00, nichts entfällt.“ Abschnitt „Wird zurückgehalten“: „Aufgaben und Deadline-Termine“. Abschnitt „Kommt immer“: „Routinen (Tagesstart, Abend-Checkliste)“, „Fokus-Timer: Phasenende“, „Hinweise aus Kalender und Erinnerungen“ mit der Marke „Apple“. Abschnitt „Fokus-Filter“: Zeile „Bei iOS-Fokus zurückhalten“ mit „Aktiv“ (solange `focusQuietSince` gesetzt ist) oder „Einrichten“, Fußtext „Hält Mitteilungen auch während eines iOS-Fokus zurück, zum Beispiel „Arbeiten“.“ Die Zeile öffnet `FocusFilterGuideView`: nummerierte Schritte (Einstellungen › Fokus › Fokus wählen › Fokusfilter › Tagwerk › „Aufgaben und Deadlines zurückhalten“) und der Satz zur Regel aus R1. Kein Sprung in die Systemeinstellungen (dafür gibt es keine öffentliche Adresse). Der Balken ist ein VoiceOver-Element „Ruhezeit von 23:00 bis 07:00“. Das Datenmodell bleibt.

- [ ] **Step 1: Tests.** `dayFractions_insideOneDay`, `dayFractions_acrossMidnight_hasTwoParts`, `dayFractions_emptyWindow_isEmpty`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: explain quiet hours with a time bar and lists instead of long text`.

### Task R4: Hinweis „kommt 07:00“ in der Erinnerungsliste (RH6c), nach E2

**Files:**
- Create: `TagwerkCore/ReminderQuietHint.swift`
- Modify: `app/Tagwerk/Reminders/ReminderSelection.swift`, Aufrufer mit Bezugszeitpunkt (`TaskEditorView`, `DeadlineReminderSheet`, `NewTaskSheet`)
- Test: neu `TagwerkCoreTests/ReminderQuietHintTests.swift`, `TagwerkCoreTests/NotificationPlanMultipleTests.swift`

**Interfaces (Produces):**

```swift
public enum ReminderQuietHint {
    /// When a reminder is delivered instead of its own moment because it falls into the quiet hours; nil when it
    /// fires as set.
    public static func delivery(of offset: ReminderOffset, anchor: Date, isAllDay: Bool, quietHours: QuietHours?,
                                calendar: Calendar) -> Date?
}
// ReminderSelectionRows
/// The moment the reminders count from and the quiet hours; without them no hint is shown (default settings).
var quietContext: (anchor: Date, quietHours: QuietHours?)? = nil
```

Betroffene Zeilen zeigen rechts „kommt 07:00“; unter der Liste steht dann „Fällt in die Ruhezeit (23:00–07:00) und wird bis zu deren Ende zurückgehalten.“ Nur für Tagwerk-Mitteilungen, nicht für Alarme in Kalender und Erinnerungen und nicht auf den Seiten der Standards. RH6b (eine Mitteilung je Aufgabe und Zustellminute) ist der Ist-Zustand; R4 sichert ihn zusätzlich für den Fokus-Filter ab.

- [ ] **Step 1: Tests.** `delivery_insideQuietHours_isTheirEnd`, `delivery_outside_isNil`, `delivery_withoutQuietHours_isNil`, `delivery_allDayAtTime`; `NotificationPlanMultipleTests.focusHold_collapsesSameMinuteOfOneEntry`.
- [ ] **Step 2–4:** rot, umsetzen, `ALL`.
- [ ] **Step 5:** Commit `feat: show in the reminder list when quiet hours hold a reminder back`.

---

## Task Z1: Geräteprüfung (nach allen Strängen)

Die mit „Gerätetest nötig“ markierten Punkte haben ihre Prüfabläufe und Rückfälle in den Tasks; Z1 wiederholt sie auf dem fertigen Stand und ergänzt die Sichtprüfung.

| Bereich | Prüfung am Gerät |
|---|---|
| PL16b | Tabelle aus P7 auf drei Gerätegrößen, Deutsch und Englisch, drei Schriftgrößen. |
| PL1b, PL10b | Kapseln hell und dunkel, im Freien bei voller Helligkeit, „Kontrast erhöhen“ ein; Kapsel „zu früh“ im schmalen Aufsatz (zwei Spalten, 15 min); bei Rückfall PL10a: Text „· knapp“ lesbar. |
| Planen | Laufender Eintrag wechselt zur vollen Minute; „Heute“ richtet aus; nach 30 min im Hintergrund richtet die Rückkehr aus; Titel wechselt ab halber Breite mit Haptik; Monat ziehen, Tag antippen, Aufgabe auf einen Tag ziehen; Sammelblock bei AX3–AX5 mit drei parallelen Terminen, Liste öffnet die Einträge. |
| Fahrzeit | Adresse suchen (mehrere gleichnamige Straßen), wählen, löschen; Termin mit Bahn statt Auto; Start „Zuhause“ trotz Vortermin; Rückweg an und aus; Menü: Route öffnet Karten mit Start und Ziel und dem Verkehrsmittel; ohne Netz geschätzte Werte mit „~“. |
| FO5b | A1–A5 aus F7. |
| FO4b | B1–B5 aus F8. |
| FO10b, FO11b | L1–L3, D1–D2 aus F5. |
| Fokus sonst | Startblatt merkt die letzte Wahl; Start über Siri und Kontrollzentrum ohne Blatt; „Erledigt“ nach 18 von 25 min: Aufgabe erledigt, Baustein der Stufe 2 nicht gestrichelt; „Beenden“ nach 12 min: gestrichelt, Stufe 2; Mitteilung zum Phasenende mit Ton, im Stumm-Modus mit Vibration (FO13a, nur Beobachtung). |
| Erinnerungen | Eigene Liste setzen und zurück auf Standard; Glocke in der Liste; Deadline mit Tagwerk-Mitteilung und Kalender-Hinweis zur selben Zeit: Kasten „Doppelt“, beide treffen ein; Serienfrage nennt das Datum; neue Aufgabe mit eigener Erinnerung. |
| RH4 | Q1–Q5 aus R1. |
| Ruhezeiten sonst | Bereits eingerichteter Fokus-Filter gilt nach dem Update weiter und zeigt den neuen Wortlaut; verschobene Mitteilung am Morgen mit „Seit gestern, 23:30 fällig“; Hinweis „kommt 07:00“ bei einer Erinnerung um 23:30. |

## Offene Fragen (mit Empfehlung)

1. **„Erledigt“ bei freier Sitzung (FO1b).** Ohne Aufgabe gibt es nichts abzuhaken. **Empfehlung (so geplant):** Der Knopf erscheint nur mit Aufgabe; eine freie Sitzung, die vor Phasenende beendet wird, ist „vorzeitig beendet“. Alternative: „Erledigt“ auch frei, dann ist dort jede früh beendete Sitzung „abgeschlossen“ und die Marke sagt nichts mehr.
2. **„Pause starten · 5 min“ auf dem Sperrbildschirm (FO10b).** Der Timer rechnet aus Zeitstempeln: Die Pause beginnt am Phasenende, nicht beim Tipp. Wer zwei Minuten später tippt, sieht drei Minuten Rest. **Empfehlung (so geplant):** Regel lassen, Knopf zeigt nur die laufende Phase (`showCurrent`); nach dem Gerätetest entscheiden, ob „Zur Pause“ der ehrlichere Text ist. Eine Pause, die erst beim Tipp beginnt, wäre eine neue Timer-Regel und ist nicht entschieden.
3. **Andere Tage beim Öffnen (PL4b).** Das Mockup sagt „Andere Tage beginnen beim ersten Eintrag, sonst beim Arbeitsbeginn“; beim Seitenwechsel durch Ziehen übernimmt die Nachbarseite heute bewusst die Scrollhöhe (#134). **Empfehlung (so geplant):** nur beim Sprung (Datumswahl, Monat → Tag, „Zeigen“), nicht beim Ziehen und nicht bei den Pfeilen.
4. **„Hinweise im Kalender“ für alle Termine (ER5b).** ER5b betrifft Deadline-Termine; „Termin bearbeiten“ zeigt denselben Mechanismus aber bei jedem Termin unter „Erinnerungen“. **Empfehlung (so geplant):** überall „Hinweise im Kalender“/„Hinweis hinzufügen“, damit ein Mechanismus einen Namen hat.
5. **BF1b als Ergänzung.** Entschieden ist BF1c; der Empfehlungstext nannte BF1b (Zeitzeile entfällt, Titel nutzt die Blockhöhe) als billige Ergänzung für den Normalfall. **Empfehlung:** nicht in P8 mitbauen; erst wenn die Geräteprüfung zeigt, dass zwei Spalten knapp über der Schwelle schlecht lesbar sind, als kleiner Folge-Commit.
6. **Beschreibung des Fokus-Filters (RH5b).** Der Mockup-Text „erst nach dem Fokus“ passt nicht zum 4-Stunden-Rückfall. **Empfehlung (so geplant):** „… nach dem Fokus, spätestens nach 4 Stunden. Nichts entfällt.“
7. **Rückweg bei fester Dauer (PL15c).** **Empfehlung (so geplant):** Der Rückweg nutzt dieselbe feste Dauer; „Keine“ entfernt beide Fahrten. Alternative: Rückweg immer automatisch.
8. **„Keine Fahrzeit für diesen Termin“ bei Serien (PL11b).** **Empfehlung (so geplant):** gilt für dieses Vorkommen ohne Rückfrage; die Serie ändert man auf der Seite „Fahrzeit“ des Termins.
9. **Sammelblock und Ziehen (BF1c).** In der Gruppe lässt sich nichts ziehen (Preis laut Mockup). **Empfehlung (so geplant):** hinnehmen, Verschieben über das Blatt; kein Umschalter „Einzeln zeigen“.
10. **„Am Tag selbst um 9:00“ statt „Am selben Tag um 9:00“ (ER6b/ER7b).** Folgt dem Bild von ER7b und ändert einen bestehenden Text. **Empfehlung (so geplant):** ändern, weil „Am Tag selbst“ sonst neben „Am selben Tag um …“ stünde.
11. **Dunkler Wert von `NowMarkerFill`.** Gerechnet reicht #D70015 in beiden Erscheinungsbildern (5,38:1); auf schwarzem Grund ist die Linie dann dunkler als das heutige Systemrot. **Empfehlung:** erst messen und am Gerät ansehen; wirkt die Linie im Dunkeln zu schwach, nur die Linie auf Systemrot lassen und die Kapsel dunkel füllen.

## Risiken

- **Zubehörleiste (FO5b):** Verhalten, bedingte Anzeige und Wirkung auf die Sicherheitszone sind nicht geprüft; der Rückfall über `safeAreaInset` steht in F7. Die Namen der API sind gegen das SDK zu prüfen.
- **Knopf im Block (FO4b):** `HoldToMoveRecognizer` und der Seitenwechsel sind UIKit-Gesten; ob ein SwiftUI-Knopf darin zuverlässig Vorrang hat, zeigt erst das Gerät. Rückfall in F8.
- **Live Activity ohne Push (FO10b):** Der Zustand „Phase vorbei“ hängt am Verfallsdatum; wie pünktlich iOS umschaltet, ist nicht belegt. Der Rückfall macht die Knöpfe davon unabhängig. Die neuen Felder des Zustands sind optional, damit eine beim Update laufende Aktivität lesbar bleibt.
- **Audit als Messung:** Ob `performAccessibilityAudit` den Kontrast einer kleinen Kapsel überhaupt bewertet, ist nicht belegt; ein Lauf ohne Befund beweist dann nichts. Deshalb zusätzlich die Messung am gerenderten Bild (P1) und die Sichtprüfung. `ImageRenderer` zeichnet Systemfarben und Schrift wie die App, aber ohne den Hintergrund des Rasters; die Kapseln sind deckend, der Hintergrund geht in den Wert nicht ein.
- **Adresssuche:** `MKLocalSearchCompleter` liefert im Simulator unzuverlässig; die Tests laufen gegen `FakeAddressSuggester`, die echte Suche ist nur am Gerät geprüft. Beim Tippen gehen Teil-Adressen an Apple; das steht auf „Mehr dazu“.
- **Rückweg und Kapazität:** Der Rückweg belegt Zeit nach dem letzten Auswärtstermin; bei eingeschaltetem Schalter sinkt die freie Zeit sichtbar. Vorgabe aus.
- **Fahrzeit-Ebene wird tippbar:** Der Aufsatz liegt dicht am Termin; eine zu große Trefferfläche fängt Tipps auf den Termin ab. Die Fläche wächst deshalb nur vom Termin weg (V3).
- **Monat im `PagedContainer`:** Der Container umschließt hier erstmals nur einen Teil einer Scroll-Ansicht. Zeichnen der Nachbarseite außerhalb des Bildschirms ohne Clip, Kontextmenüs und Ablegen von Aufgaben sind im Simulator zu prüfen (P6).
- **Doppelte Zustellung (RH4b):** Der Befund zum Nachholen nach einem abgelaufenen Ziel ist aus dem Lesen von `FocusQuiet.applying` abgeleitet, nicht ausgeführt. R1 schreibt zuerst den Test; ist er auf dem heutigen Stand schon grün, entfällt nur die Ergänzung in `applying`, nicht der Test.
- **Umbenennung der Fokus-Texte:** `FocusRewardPiece` wird nur berechnet, nie gespeichert; die Umbenennung ist gefahrlos, solange `FocusOutcome` seine Rohwerte behält (Test `storedAbortedSession_readsAsEndedEarly`, `BackupTests.swift:543`).
- **Kataloge:** Fünf Stränge ändern dieselben Katalogdateien. Konflikte nie von Hand lösen: Quelltext zusammenführen, `sync-strings.sh` und `apply-translations.py` neu laufen lassen.
- **Umfang:** Strang F und Strang V sind groß (acht und fünf Tasks). Ein Pull Request je Strang bleibt prüfbar nur, wenn jeder Task ein eigener Commit ist; die Hauptsitzung prüft Task für Task entlang des Review Focus.
