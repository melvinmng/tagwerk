# Termine als Deadline markieren und mit Deadlines verbinden (DL2 + DV1) – Implementation Plan

> **Status:** Entwurf, freigegeben 18.11.2026. Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Die Empfehlung DL2 + DV1 ist vorläufig; die offenen Entscheidungen am Ende bestimmen den Umfang.

**Goal:**

1. Ein einzelner Termin aus einem beliebigen gelesenen Kalender lässt sich als Deadline markieren (Beispiel: „Klausur Statistik“ steht nur im abonnierten Stundenplan). Er erscheint wie eine Deadline aus einem Deadline-Kalender, mit der Marke „markiert“.
2. Zu einer Deadline, die ein Termin ist (aus einem Deadline-Kalender oder markiert), lassen sich andere Kalendereinträge als „Vorbereitung“ zuordnen. Tagwerk zeigt sie zusammen, summiert ihre Zeit und springt in beide Richtungen.

**Mockup:** `docs/superpowers/mockups/2026-11-18-deadline-marking-mockups.html` (DL0 Ist-Zustand, DL1–DL3 Markieren, DV1–DV3 Lesarten von „verbinden“).

**Bezug:** `docs/superpowers/specs/2026-11-17-phase-2b-design.md` §6.2 (wichtige Deadlines), §6.4 (Verknüpfung), §11.4, §11.7, §11.13, §13.15 F1 („Frei“ als lokale Markierung).

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, EventKit, Swift Testing.

**Nicht in diesem Plan:** Vorschlagskarte nach Stichwort (DL3), „derselbe Termin“ (DV2), Zuordnen an P1-Aufgaben und Epics, KI-Funktion zum Markieren (`mark_event_as_deadline`), Abgleich zwischen Geräten.

**Belegstand:** Der Ist-Zustand stammt aus dem Quelltext. Die Aussagen zu EventKit-Kennungen stammen aus der Apple-Dokumentation (`eventIdentifier`: ändert sich meist beim Kalenderwechsel; `calendarItemExternalIdentifier`: für alle Vorkommen einer Serie gleich, kann bei Abos in mehreren Konten doppelt vorkommen, bei Exchange je Plattform verschieden). Wie sich der konkrete Stundenplan-Feed verhält (stabile Kennungen oder nicht), ist ungeprüft; Task 1 klärt das.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `app/Packages/TagwerkCore/Sources/TagwerkCore/ImportantDeadline.swift:21–23, 39–76` | Drei Arten: `.priorityOne`, `.epic`, `.deadlineCalendar`. Ein Termin ist Deadline nur über `deadlineCalendarIDs`. |
| `app/Tagwerk/Persistence/AppSettings.swift:16, 33` | `deadlineCalendarNotifications`, `deadlineCalendarIDs`. |
| `app/Tagwerk/Planning/PlanningModel.swift:228–230, 306–307, 1294–1296` | `importantDeadlines(...)` für Ansicht, Widget-Eingabe und Deadline-Karte (14 Tage). Zeile 1295 liest nur Deadline-Kalender; ohne Deadline-Kalender liest sie nichts. |
| `PlanningModel.swift:606–609` | Ganztägige Termine aus Deadline-Kalendern fehlen in „Ganztägig“. |
| `app/Tagwerk/Planning/DeadlineCard.swift:16–29` | Zeilen ohne Tipp und ohne Menü. Ganztägige Deadline-Termine haben damit kein Blatt. |
| `app/Tagwerk/Planning/DayView.swift:135–139`, `TimelineCanvas.swift:412` | Termine mit Uhrzeit sind im Ablauf blau, auch aus Deadline-Kalendern. |
| `app/Tagwerk/Planning/TimelineCanvas.swift:202, 231–232` | Gedrückthalten im Stundenraster = Verschieben. |
| `app/Tagwerk/Planning/WeekView.swift:30–56` | Woche zeigt Aufgaben und Deadline-Zeilen, keine Termine. |
| `app/Tagwerk/Planning/EntrySheet.swift:66–149` | Termin-Blatt: Kopf, Zeit, „Zählt als“, „Aufgabe“, Aktionen. |
| `app/Tagwerk/Planning/EventMarks.swift:23–37, 114–138` | Vorbild: `EventAvailabilityMark` liegt nur in SwiftData, Schlüssel ist die Termin-ID, Serien über `seriesFrom`. |
| `app/Tagwerk/Planning/EventTaskLink.swift:9` | `eventKey` eindeutig: ein Termin, eine Aufgabe. Schlüssel ist `CalendarEvent.id`, nicht die Server-Kennung (anders als im Entwurf 2b §5). |
| `app/Packages/RemindersKit/Sources/RemindersKit/EventKitGateway.swift:401–408, 420` | `id` = `eventIdentifier`, bei Serien, abgelösten Vorkommen und Abos mit Zeitpunkt; `externalID` wird gelesen; `isEditable` aus `allowsContentModifications`. |
| `app/Tagwerk/Notifications/NotificationScheduler.swift:157–161`, `app/Tagwerk/App/AppEnvironment.swift:150–152, 313–315` | Benachrichtigungen lesen nur Deadline-Kalender; ohne Deadline-Kalender gibt es keine Termin-Benachrichtigung. |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/WidgetSnapshot.swift:115, 139–142` | Zähler und Deadline-Zeile folgen `ImportantDeadline.eventID`; keine Änderung am Widget nötig. |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/AIPlanning.swift:84, 891–893`, `app/Tagwerk/AI/AIPlanner.swift:661–671` | KI-Kennzeichen `deadline` aus `deadlineCalendarIDs`; Anker nur für `.deadlineCalendar`. |
| `PlanningModel.swift:765–766` | Deadline-Kalender nehmen am Zusammenfassen nicht teil. |
| `PlanningModel.swift:1174, 1189–1192, 1267` | Bestehender Mangel: Ein mit einer Aufgabe verknüpfter Deadline-Termin mit Uhrzeit zählt als geplante Arbeit an der Aufgabe und erscheint als Block. |

## Speichermodell

Nur SwiftData, nichts im Kalender. Gründe: Abonnierte Kalender und Einladungen sind nicht beschreibbar; Notizen oder URL in geteilten Kalendern wären für andere sichtbar; das URL-Feld bedeutet in Tagwerk schon „Zeitblock zu Aufgabe“ (`LinkResolver.swift:36–38`). Schemaregel wie bisher: neue Attribute optional oder mit Standardwert.

```swift
/// A calendar event the user marked as a deadline; lives in Tagwerk only.
@Model final class EventDeadlineMark {
    @Attribute(.unique) var eventKey: String   // CalendarEvent.id when marked (occurrence ID for series)
    var externalID: String?                    // calendarItemExternalIdentifier
    var calendarID: String = ""
    var title: String = ""
    var start: Date = Date.distantPast
    var isAllDay: Bool = false
    var createdAt: Date = Date.now
}

/// A calendar event that belongs to the preparation of a deadline event.
@Model final class DeadlineEventLink {
    @Attribute(.unique) var key: String        // "<deadlineKey>|<eventKey>"
    var deadlineKey: String                    // CalendarEvent.id of the deadline event
    var eventKey: String                       // occurrence ID, or the series identifier when isSeries
    var isSeries: Bool = false                 // all occurrences from createdAt until the deadline
    var externalID: String?
    var calendarID: String = ""
    var title: String = ""
    var start: Date = Date.distantPast
    var createdAt: Date = Date.now
}
```

Wiederfinden (reine Funktion in TagwerkCore, `EventReference` → `EventReferenceMatch`):

1. gleiche `id` → `exact`.
2. gleiche `externalID`, gleicher Kalender, gleicher Beginn → `exact` (Kennung hat sich geändert), `eventKey` nachziehen.
3. gleiche `externalID`, gleicher Kalender, genau ein Treffer, keine Serie → `moved`, still übernehmen, Beginn nachziehen.
4. gleicher normalisierter Titel, gleicher Kalender, ±14 Tage, genau ein Treffer → `candidate`, nur als Vorschlag.
5. sonst `missing`, aber nur, wenn der Kalender gelesen wurde und das Fenster den gemerkten Beginn enthält; sonst `unknown` (nichts ändern).

Aufräumen: Markierungen und Zuordnungen, deren gemerkter Beginn mehr als 30 Tage zurückliegt, löscht `reload()`.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `TagwerkCore/ImportantDeadline.swift` | `DeadlineKind.markedEvent`; Parameter `markedEventIDs: Set<String> = []`; ein Termin aus Deadline-Kalender und markiert erscheint einmal als `.deadlineCalendar`. |
| `TagwerkCore/EventReference.swift` (neu) | `EventReference`, `EventReferenceMatch`, `resolveEventReference`, `preparationMinutes`. |
| `TagwerkCore/AIPlanning.swift` | `PlanInputDay` bekommt `deadlineEventIDs`; `deadline` = Kalender oder markiert. |
| `TagwerkCore/EventMerging.swift` | Markierte Termine werden nie als Platzhalter ausgeblendet (`excludingEventIDs`). |
| `app/Tagwerk/Planning/DeadlineMarks.swift` (neu) | Beide `@Model`-Klassen und `DeadlineMarkStore` (markieren, entfernen, zuordnen, lösen, nachziehen, aufräumen). |
| `app/Tagwerk/Persistence/ModelContainerFactory.swift` | Schema um beide Klassen ergänzen. |
| `app/Tagwerk/Planning/PlanningModel.swift` | Store einhängen; `markDeadline`, `unmarkDeadline`, `linkPreparation`, `unlinkPreparation`, `preparation(for:)`, `deadline(forEvent:)`; Marken an alle `importantDeadlines`-Aufrufe; `allDayEvents` ohne markierte; `loadUpcomingDeadlines` liest zusätzlich die Kalender der Marken; verwaiste Marken als eigene Liste. |
| `app/Tagwerk/Planning/DeadlineCard.swift` | Zeilen antippbar, Menü, Marke „markiert“, Kalendername, Zeile „Vorbereitung“, verwaiste Zeile mit „Übernehmen / Zuordnen / Entfernen“. |
| `app/Tagwerk/Planning/EntrySheet.swift` | Abschnitte „Deadline“ und „Vorbereitung“; `EventLinkPicker`; „Zu Deadline zuordnen …“. |
| `app/Tagwerk/Planning/DayView.swift`, `TimelineCanvas.swift` | Rote Darstellung für Deadline-Termine; Menü im Listenmodus und an „Ganztägig“; Marke „→ Deadline“ an zugeordneten Terminen. |
| `app/Tagwerk/Planning/WeekView.swift`, `MonthView.swift` | Deadline-Zeilen mit Marke, Tipp und Menü. |
| `app/Tagwerk/Notifications/NotificationScheduler.swift`, `app/Tagwerk/App/AppEnvironment.swift` | Deadline-Termine = Deadline-Kalender plus markierte; neu planen nach Markieren und Entfernen. |
| `app/Tagwerk/AI/AIPlanner.swift`, `AppTools.swift` | Anker auch für `.markedEvent`; `list_events` nennt `deadline`. |
| `app/Tagwerk/Settings/SettingsView.swift`, `PlanningSettingsSection.swift` | Fußtexte: „Deadline-Termine“ gilt auch für markierte Termine. |
| `app/Tagwerk/Localizable.xcstrings`, `TagwerkCore/Resources` | Neue Texte deutsch und englisch. |
| `docs/superpowers/specs/2026-11-17-phase-2b-design.md` | Nachtrag zu §6.2 und §11.7 nach Freigabe. |

## Tasks

Jeder Task beginnt mit den Tests (rot), dann die Umsetzung (grün). Kein Task ändert einen Kalender.

### Task 1: Kennungen am echten Stundenplan prüfen (Abbruchkriterium für Stufe 3 des Wiederfindens)

- [ ] In der Kalender-Diagnose (Debug) für den Stundenplan `id` und `externalID` von fünf Terminen ausgeben, Abo neu laden, erneut ausgeben.
- [ ] **Entscheidung festhalten:** Bleibt `externalID` gleich, gelten Stufen 2 und 3. Wechselt sie, entfallen sie für Abos und nur Stufe 4 (Vorschlag) bleibt.

### Task 2: Wiederfinden als reine Funktion (TagwerkCore)

Tests `EventReferenceTests`:
- [ ] `exactIDMatches`
- [ ] `changedIdentifierMatchesByExternalIDCalendarAndStart`
- [ ] `movedEventFollowsUniqueExternalID`
- [ ] `seriesOccurrencesNeverMatchByExternalIDAlone`
- [ ] `sameExternalIDInOtherCalendarIsIgnored`
- [ ] `uniqueTitleWithinFourteenDaysIsOnlyACandidate`
- [ ] `twoTitleCandidatesAreMissing`
- [ ] `unreadCalendarOrWindowOutsideStartIsUnknown`

### Task 3: `importantDeadlines` mit markierten Terminen (TagwerkCore)

Tests in `ImportantDeadlineTests`:
- [ ] `markedEventBecomesDeadline` (Art `.markedEvent`, `eventID`, Uhrzeit, ganztägig ohne Uhrzeit)
- [ ] `markedEventInDeadlineCalendarAppearsOnce`
- [ ] `markedOccurrenceOfSeriesMarksOnlyThatOccurrence`
- [ ] `unmarkedEventsStayOrdinary`

### Task 4: Store und Schema

Tests `DeadlineMarkStoreTests` (In-Memory-Container):
- [ ] `markStoresSnapshot`, `markTwiceKeepsOneRecord`, `unmarkDeletesMarkAndItsLinks`
- [ ] `linkAndUnlinkPreparation`, `seriesLinkCoversOccurrencesUntilDeadline`
- [ ] `followUpdatesKeyAndStart`, `pruneRemovesMarksOlderThanThirtyDays`
- [ ] `ModelStoreLocationTests` bleibt grün (Schema öffnet den bestehenden Store).

### Task 5: PlanningModel

Tests in `PlanningModelTests` (mit dem vorhandenen Kalender-Fake):
- [ ] `markedTimetableEventShowsInDaysAndUpcomingDeadlines` (auch ohne jeden Deadline-Kalender)
- [ ] `markedAllDayEventLeavesAllDayRow`
- [ ] `markedTimedEventStillCountsAsBusy`
- [ ] `markOnReadOnlyCalendarWritesNothingToTheCalendar`
- [ ] `movedMarkedEventIsFollowed`, `deletedMarkedEventIsReportedNotDropped`, `withoutCalendarAccessMarksStayUntouched`
- [ ] `preparationSumsLinkedEventsBeforeDeadline`
- [ ] `markedEventIsNeverHiddenByMerge`

### Task 6: Deadline-Karte, Woche, Monat

- [ ] Zeilen öffnen das Termin-Blatt (für Aufgaben-Deadlines die Aufgabe), Menü „Öffnen / Zum Tag springen / Termin zuordnen … / Markierung entfernen“.
- [ ] Marke, Kalendername, „Vorbereitung x h · n Termine“, verwaiste Zeile.
- [ ] Test `DeadlineCardTextTests`: `kindTextNamesCalendarAndMark`, `preparationLineOnlyWithLinks`, VoiceOver-Text.

### Task 7: Termin-Blatt, Ablauf, Menü

- [ ] Abschnitt „Deadline“: Schalter; bei Deadline-Kalendern nur Hinweis; Rückfrage beim Entfernen mit Zuordnungen.
- [ ] Abschnitt „Vorbereitung“ mit `EventLinkPicker` (Termine von heute bis zur Deadline, Suche, Rückfrage bei Serien).
- [ ] Rote Darstellung im Stundenraster und in der Liste; Menü im Listenmodus und an „Ganztägig“. Stundenraster: kein Menü.
- [ ] Sichtprüfung am Gerät: dunkel, hell, größte Schriftstufe, Englisch, VoiceOver.

### Task 8: Benachrichtigungen

Tests in `NotificationSchedulerTests`:
- [ ] `markedEventGetsNotificationWithoutAnyDeadlineCalendar`
- [ ] `switchOffRemovesMarkedEventNotifications`
- [ ] `unmarkRemovesPendingNotification`
- [ ] `eventInDeadlineCalendarAndMarkedNotifiesOnce`

### Task 9: Widget und KI-Kontext

- [ ] `WidgetSnapshotTests.markedEventCountsAndShowsAsDeadlineRow`
- [ ] `AIPlanningTests.markedEventIsFlaggedAsDeadline`
- [ ] `AIPlannerTests.taskLinkedToMarkedDeadlineGetsAnchor`
- [ ] `AppToolsTests.listEventsNamesDeadline`

### Task 10 (nach Entscheidung 5): Deadline-Termin ist für die Aufgabe nur Anker

- [ ] `PlanningModelTests.deadlineEventLinkedToTaskIsNotABlock`: zählt als belegt, nicht als geplante Arbeit, bleibt Termin.
- [ ] Umsetzung in `dayPlan` (`PlanningModel.swift:1174`).

### Task 11: Texte, Entwurf, Abschluss

- [ ] `Localizable.xcstrings` deutsch und englisch; `LocalizedTests` grün.
- [ ] Nachtrag im Entwurf 2b; `app/test-all.sh` grün.

## Risiken

| Risiko | Folge | Gegenmaßnahme |
|---|---|---|
| Der Stundenplan-Feed vergibt Kennungen neu | Marken verwaisen nach jedem Abruf | Task 1 zuerst; Stufe 4 als Vorschlag; nie still löschen |
| Markierter Termin wird vom Zusammenfassen ausgeblendet | Deadline verschwindet | Markierte IDs ausschließen (Task 5) |
| Kalender wird später abgewählt | Marke wirkt „gelöscht“ | Zustand `unknown`; Deadline-Lesen schließt die Kalender der Marken ein |
| Zwei Bedeutungen von „verknüpft“ (Arbeit an der Aufgabe, Anker) | falsche „eingeplant“-Summen | Task 10 |
| Budget von 50 Benachrichtigungen | markierte Termine verdrängen Aufgaben | unverändert früheste zuerst; im Plan vermerkt |
| Gedrückthalten im Stundenraster | Menü fehlt dort | bewusst; Tipp öffnet das Blatt |
| Schemaänderung | Store öffnet nicht | nur neue Klassen mit Standardwerten; `ModelStoreLocationTests` |
| Daten nur auf dem Gerät | nach Neuinstallation weg | im Fußtext nennen; kein Abgleich geplant |

## Offene Entscheidungen (Vorschlag in Klammern)

1. „Verbinden“ = Vorbereitung (DV1) oder derselbe Termin (DV2)? (DV1)
2. Stundenraster ohne Menü, Markieren dort über das Blatt? (ja)
3. Serientermin markieren: nur das einzelne Vorkommen, ohne Rückfrage? (ja)
4. Zählt alles Zugeordnete zur Summe „Vorbereitung“, auch Vorlesungen? (ja)
5. Deadline-Termin mit verknüpfter Aufgabe nur als Anker, nicht als Arbeitszeit? (ja, Task 10)
6. Ein Schalter „Deadline-Termine“ für beide Arten von Benachrichtigungen? (ja)
7. Zuordnen nur an Deadline-Termine, nicht an P1-Aufgaben und Epics? (ja)
8. Vorschlagskarte DL3 zurückstellen? (ja)

## Entscheidungen (18.11.2026, freigegeben)

1. DL2 + DV1 (Vorbereitung).
2. Kein Menü im Stundenraster; Markieren dort nur über das Terminblatt.
3. Serientermine: beim Markieren fragen „Nur diesen Termin / Alle Termine der Serie“ (Abweichung vom Vorschlag).
4. Alles Zugeordnete zählt zur Vorbereitung, auch Vorlesungen; bei Serien „Nur diesen / Alle bis zur Deadline“.
5. Ein verknüpfter Deadline-Termin zählt nicht mehr als Arbeitszeit der Aufgabe.
6. Der vorhandene Schalter „Deadline-Termine“ gilt auch für markierte Termine.
7. Zuordnen von Vorbereitung auch an P1-Aufgaben und Epics, nicht nur an Deadline-Terminen (Abweichung vom Vorschlag).
8. Vorschläge nach Stichwort (DL3) direkt mit einbauen (Abweichung vom Vorschlag).
9. Verwaiste Markierungen 30 Tage nach ihrem Datum aufräumen, vorher nie still löschen.
