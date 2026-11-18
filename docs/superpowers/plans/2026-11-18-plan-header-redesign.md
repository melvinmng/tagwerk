# Kopf von „Planen“ überarbeiten (PK2) – Implementation Plan

> **Status:** Umgesetzt und am Gerät abgenommen (PR #131, 18.11.2026). PK2 ist freigegeben; Titel links, rund 19 pt, „Heute“ in der Bedienzeile, ＋ bleibt „Neuer Termin“. Geräte mit 375 pt Breite werden nicht unterstützt. „Erfassen“ bleibt vorerst unverändert (Angleichen der Einzelteile später).

**Goal:** Der KI-Button (✦, „Assistent“) und ＋ sitzen in „Planen“ mit denselben Leisten-Bausteinen wie in „Aufgaben“ und „Erfassen“. Der Kopf von „Planen“ besteht aus zwei festen Zeilen:

1. System-Navigationsleiste: links der Datumstitel mit ▾ (Monatswähler) und der Kennzeile („Heute · KW 47“), rechts ＋ und ✦.
2. Bedienzeile: Umschalter Tag / Woche / Monat, „Heute“ (nur wenn ein anderer Zeitraum gezeigt wird), Pfeile zurück und vor.

Der Datumskopf im Inhalt (`DayHeader`) entfällt.

**Mockup:** `docs/superpowers/mockups/2026-11-18-plan-header-mockups.html` (PK0 Ist-Zustand, PK2 Empfehlung, PK1 Rückfalllösung).

**Vorgänger:** `docs/superpowers/mockups/2026-11-18-assistant-button-mockups.html` (AK2). Gebaut ist dort Weg b (eigene Kopfzeile); dieser Plan stellt auf Weg a um (System-Leiste).

**Tech Stack:** Swift 6, SwiftUI (iOS 27), Swift Testing.

**Nicht in diesem Plan:** Umbau der Tagesnavigation in „Erfassen“, ein Menü hinter ＋, Änderungen an `AssistantButton` selbst, Änderungen am Assistenten.

**Belegstand:** Alle Aussagen zum Verhalten von Leisten-Elementen (Titel-Knopf links, Popover-Anker, Breiten) stammen aus API-Kenntnis und Rechnung. Am Gerät oder im Simulator ist nichts davon geprüft. Task 1 ist deshalb ein Probeaufbau mit Abbruchkriterium.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `app/Tagwerk/Planning/PlanView.swift:90` | `.toolbar(.hidden, for: .navigationBar)` blendet die System-Leiste aus. |
| `app/Tagwerk/Planning/PlanView.swift:84`, `124–141` | Eigene Kopfzeile in `.safeAreaInset(edge: .top)` auf `.background(.bar)`. |
| `app/Tagwerk/Planning/PlanView.swift:131–134` | ＋ als `.bordered`-Kreis mit 22-pt-Symbolrahmen (kein Glas, unter 44 pt). |
| `app/Tagwerk/Planning/PlanView.swift:135` | `AssistantButton` als nackte Ansicht, ohne `ToolbarSpacer`. |
| `app/Tagwerk/AI/AssistantButton.swift:28–35` | Leisten-Baustein `AssistantToolbarItems`, den die anderen Tabs benutzen (`CaptureView.swift:72`, `TaskListView.swift:108`, `SettingsView.swift:107`). |
| `app/Tagwerk/Planning/DayHeader.swift:5–64` | Datumskopf im Inhalt: Kennzeile, „Heute“, Titel mit Popover, zwei kleine Pfeil-Kreise (`40–48`, unter 44 pt), Kalorien-/Wasser-Zeile. |
| `DayView.swift:59`, `WeekView.swift:18`, `MonthView.swift:18` | Einbau von `DayHeader` in den drei Ansichten. |

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `app/Tagwerk/Planning/PlanHeaderText.swift` (neu) | Reine Textlogik: Titel, Kennzeile, „laufender Zeitraum“, Bezeichnungen der Pfeile, VoiceOver-Text. Aus `DayHeader` herausgelöst. |
| `app/Tagwerk/Planning/PlanView.swift` | Leiste einblenden, Leisten-Elemente (Titel-Knopf, ＋, `AssistantToolbarItems`), Bedienzeile im `safeAreaInset`. |
| `app/Tagwerk/Planning/DayHeader.swift` | `DayHeader` entfällt. `DatePickerPopover` bleibt. Die Kalorien-/Wasser-Zeile wird zu einer kleinen eigenen Ansicht `PlanIntakeLine`. Datei danach sinnvoll umbenennen (z. B. `PlanHeader.swift`). |
| `app/Tagwerk/Planning/DayView.swift` | `DayHeader` (Zeile 59) durch `PlanIntakeLine` ersetzen. |
| `app/Tagwerk/Planning/WeekView.swift` | Abschnitt mit `DayHeader` (ab Zeile 18) entfernen. |
| `app/Tagwerk/Planning/MonthView.swift` | `DayHeader` (Zeile 18) entfernen, Abstände prüfen. |
| `app/Tagwerk/Localizable.xcstrings` | Neue Texte nur, falls nötig (VoiceOver-Wert des Titels). Bestehende Schlüssel („Heute“, „Vorheriger Tag“ usw.) bleiben. Englische Übersetzung mitpflegen. |
| `app/TagwerkTests/PlanHeaderTextTests.swift` (neu) | Swift-Testing-Tests für `PlanHeaderText`. |
| `docs/superpowers/specs/2026-11-17-phase-2b-design.md` | Hinweis zu AK2 (Zeile 250) um den Verweis auf PK2 ergänzen, nach Freigabe. |

## Tasks

### Task 1: Probeaufbau der Leiste (Abbruchkriterium)

- [ ] In einem Wegwerf-Zweig `PlanView.swift:90` entfernen und `.toolbarTitleDisplayMode(.inline)` setzen.
- [ ] Trailing: `ToolbarItem(placement: .topBarTrailing)` mit ＋ (`Label("Neuer Termin", systemImage: "plus")`), danach `AssistantToolbarItems { .planning(scope:anchor:) }`. Reihenfolge wie in `TaskListView.swift:105–108`.
- [ ] Titel-Knopf prüfen, zwei Bauweisen:
  - (i) `ToolbarItem(placement: .topBarLeading)` mit eigenem Knopf (zwei Textzeilen), `.sharedBackgroundVisibility(.hidden)`; der Systemtitel muss dafür unsichtbar sein (leeres `principal`-Element oder leerer Titel; welche Lösung trägt, ist offen).
  - (ii) dasselbe in `ToolbarItem(placement: .principal)` (mittig, kürzerer Titel „Mi., 18. Nov.“).
- [ ] `DatePickerPopover` am Titel-Knopf verankern und prüfen, ob `.presentationCompactAdaptation(.popover)` aus der Leiste heraus trägt.
- [ ] Am Gerät und im Simulator ansehen: Standardbreite, schmalstes unterstütztes Gerät, hell und dunkel, größte Schriftstufe, Englisch.
- [ ] **Entscheidung festhalten:** Trägt (i) oder (ii)? Trägt keines (Titel wird abgeschnitten, Popover verankert falsch, Leiste zeigt ungewollt eine Glas-Kapsel), dann **PK1** bauen: Umschalter in `principal`, `DayHeader` bleibt im Inhalt, nur Pfeile und ＋ werden auf 44 pt gebracht. Die Tasks 2 und 6 gelten dann unverändert, 3 bis 5 entfallen bis auf die Leisten-Elemente.

### Task 2: Textlogik herauslösen (TDD)

- [ ] Tests zuerst schreiben (`PlanHeaderTextTests.swift`), dann `PlanHeaderText` anlegen. Schnittstelle als Vorschlag:

  ```swift
  enum PlanHeaderText {
      static func title(scope: PlanScope, anchor: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar, locale: Locale) -> String
      static func caption(scope: PlanScope, anchor: PlanDay, today: PlanDay, range: ClosedRange<PlanDay>, calendar: Calendar) -> String
      static func isCurrent(scope: PlanScope, anchor: PlanDay, today: PlanDay, range: ClosedRange<PlanDay>) -> Bool
      static func stepLabel(scope: PlanScope, direction: Int) -> String
  }
  ```

- [ ] Die Logik unverändert aus `DayHeader.swift:72–133` übernehmen (Titel, Kennzeile, Tagesabstand, „laufender Zeitraum“, Bezeichnungen). Einzige Änderung: `locale` wird hereingereicht, damit die Tests nicht von der Geräteeinstellung abhängen.
- [ ] `DayHeader` vorübergehend auf `PlanHeaderText` umstellen, damit der Zwischenstand baut und sich nichts sichtbar ändert.

### Task 3: Leiste in `PlanView`

- [ ] `.toolbar(.hidden, for: .navigationBar)` entfernen, Anzeigeart `.inline`.
- [ ] Titel-Knopf nach dem Ergebnis von Task 1. Inhalt: Kennzeile (`.caption2`, halbfett, Akzentfarbe nur bei laufendem Zeitraum), Titel (`.headline` oder `.title3`, eine Zeile, `minimumScaleFactor(0.8)`), Symbol `chevron.down`.
- [ ] `@State picking` und das Popover aus `DayHeader` nach `PlanView` ziehen. „Monatsansicht ›“ setzt weiter `model.scope = .month` und entfällt in der Monatsansicht.
- [ ] ＋ und `AssistantToolbarItems` wie in Task 1. Der eigene `AssistantButton`-Aufruf (`PlanView.swift:135`) entfällt.

### Task 4: Bedienzeile

- [ ] `header` in `PlanView` neu: `Picker` (`.segmented`), „Heute“ (nur wenn `!isCurrent`), Pfeile als eine Glas-Kapsel mit zwei Knöpfen von je 44 × 44 pt.
- [ ] Hintergrund der Zeile prüfen: `.background(.bar)` weglassen oder behalten, sodass die Zeile optisch zur Leiste gehört und beim Scrollen kein Bruch entsteht (am Gerät entscheiden).
- [ ] Platzmangel: `ViewThatFits` mit zwei Fassungen (mit und ohne „Heute“). „Heute“ bleibt im Monatswähler erreichbar (`DayHeader.swift:147`).
- [ ] Bezeichnungen der Pfeile aus `PlanHeaderText.stepLabel`.

### Task 5: Inhalt bereinigen

- [ ] `PlanIntakeLine` aus `DayHeader.swift:50–62` und `66–70` herauslösen; Einbau nur in `DayView` an der Stelle des bisherigen Kopfes.
- [ ] `DayHeader` aus `WeekView` und `MonthView` entfernen, Abstände und Listeneinzüge angleichen.
- [ ] `DayHeader` löschen, wenn es keinen Aufrufer mehr gibt.
- [ ] Prüfen, ob Wischen zwischen Tagen und Wochen (`HorizontalSwipe.swift`) unverändert arbeitet.

### Task 6: Bedienungshilfen und Abnahme

- [ ] VoiceOver: Titel-Knopf als ein Element mit Wert aus Datum und Kennzeile, Hinweis „Datum wählen“, Merkmal Überschrift. Reihenfolge: Titel, ＋, Assistent, Umschalter, Heute, zurück, vor.
- [ ] Große Schrift: `.accessibilityShowsLargeContentViewer()` für „Heute“ und die Pfeile; Leisten-Knöpfe bringen die vergrößerte Ansicht selbst mit (Annahme, prüfen).
- [ ] Sichtprüfung der drei Tabs nebeneinander: ✦ an derselben Stelle, gleiche Größe, gleicher Abstand zu ＋ wie in „Aufgaben“. Screenshots hell und dunkel ablegen.
- [ ] `app/test-all.sh` ausführen.

## Tests (Swift Testing)

`app/TagwerkTests/PlanHeaderTextTests.swift`, mit festem gregorianischem Kalender (Wochenbeginn Montag), fester Zeitzone und `Locale(identifier: "de_DE")`; ein Durchlauf zusätzlich mit `en_US`.

- **Titel:** Tag „Mittwoch, 18. Nov.“; Woche innerhalb eines Monats; Woche über die Monatsgrenze (30. Nov. bis 6. Dez.); Woche über den Jahreswechsel; Monat „November“. Geprüft wird gegen die Formatierung mit derselben `locale`, nicht gegen fest verdrahtete Zeichenketten, wo das Format vom System abhängt.
- **Kennzeile Tag:** heute, morgen, gestern, in 3 Tagen, vor 3 Tagen; Kalenderwoche am Jahreswechsel (KW 53 und KW 1).
- **Kennzeile Woche und Monat:** laufender und anderer Zeitraum.
- **`isCurrent`:** Tag, Woche und Monat je einmal wahr und falsch; Monat desselben Namens im anderen Jahr ist nicht „laufend“; ein Nachbarmonat, dessen Raster den heutigen Tag mit anzeigt, ebenfalls nicht (dafür steht der Monatsvergleich in `DayHeader.swift:73`).
- **Bezeichnungen:** je Ansicht und Richtung.

Bestehende Tests (`PlanningModelTests`) decken `step`, `range` und den Anker ab und bleiben unverändert. Für das Layout gibt es keine automatischen Tests; es wird in Task 6 von Hand geprüft.

## Risiken

| Risiko | Einschätzung | Gegenmaßnahme |
|---|---|---|
| Titel-Knopf links in der Leiste sieht nicht wie ein Titel aus (Glas-Kapsel, falsche Grundlinie) oder verdrängt den Systemtitel nicht | offen, ungeprüft | Task 1; Rückfall auf mittigen Titel oder PK1 |
| Popover verankert an einem Leisten-Element falsch oder wird zum Blatt | offen, ungeprüft | Task 1; notfalls Blatt mit mittlerer Höhe |
| Enge auf schmalen Geräten: Titel „30. Nov. – 6. Dez. ▾“ neben zwei 44-pt-Knöpfen; Bedienzeile mit „Heute“ | Rechnung: rund 230 pt für den Titel bei 375 pt Breite, nicht gemessen | eine Zeile, Skalierung bis 0,8; `ViewThatFits` in der Bedienzeile |
| Große Schriftstufen: Leisten-Elemente wachsen kaum, Bedienzeile läuft über | mittel | vergrößerte Ansicht beim Halten; „Heute“ fällt zuerst weg; Prüfung mit der größten Stufe |
| VoiceOver liest Kennzeile und Titel getrennt oder in falscher Reihenfolge | klein | ein zusammengefasstes Element mit eigenem Wert |
| Titel wird kleiner als heute (rund 19 statt 28 pt) und wirkt weniger als Orientierung | Geschmacksfrage, offen (Frage 4 im Mockup) | Freigabe abwarten |
| Höhe: zwei feste Zeilen im Tag über dem Stundenraster | Rechnung: netto etwa eine Zeile gewonnen, weil der Kopf im Inhalt entfällt; nicht gemessen | in Task 6 vorher und nachher vergleichen |
| Inhalt scrollt unter der Leiste anders als bisher (`safeAreaInset` plus sichtbare Leiste, Aktualisieren durch Ziehen) | mittel | in allen drei Ansichten prüfen, Hintergrund der Bedienzeile danach festlegen |
| Englische Texte („Wednesday, Nov 18“, „Day / Week / Month“) sind länger | klein | in Task 1 und 6 mitprüfen |
| Zweite Bauweise der Datumsnavigation bleibt in „Erfassen“ bestehen | bekannt, bewusst ausgeklammert | Frage 7 im Mockup |

## Offene Punkte vor Beginn

Siehe „Offene Fragen“ im Mockup. Ohne Antwort auf die Fragen 2 und 3 wird nur Task 2 begonnen (verhaltensneutral).
