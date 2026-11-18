# Phase 2b-3: Benachrichtigungen & Hintergrund – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tagwerk erinnert vor Fälligkeiten von GitHub- und lokalen Aufgaben und vor wichtigen Deadlines aus Deadline-Kalendern, auch wenn die App länger nicht geöffnet war:
- Lokale Benachrichtigungen (höchstens 50, die nächsten zuerst), neu geplant beim Start, nach jeder Änderung und im Hintergrund-Refresh.
- Einrichtungsschritt „Benachrichtigungen“ und eine Zugriffszeile in den Einstellungen.
- Ein Tipp auf die Benachrichtigung öffnet die Aufgabe bzw. den Tag des Termins.
- `BGAppRefreshTask` lädt GitHub neu (falls Token und Netz verfügbar) und plant neu. Keine KI im Hintergrund (§8.4).

**Architecture:**
- Reine Regeln in `TagwerkCore` (`NotificationPlan.swift`): aus Aufgaben, Deadline-Terminen, Vorlauf, Schalter und `now` entsteht eine sortierte, auf 50 begrenzte Liste `PlannedNotification` mit stabilen Kennungen und fertigen deutschen Texten.
- In der App ein `NotificationScheduler` gegen das Protokoll `NotificationCenterClient` (Fake in Tests, `UNUserNotificationCenter` im Betrieb). Er gleicht nur eigene Kennungen ab (Präfix `tagwerk.`) und lässt die Benachrichtigungen einer Quelle stehen, die gerade nicht geladen ist.
- `BackgroundRefresh` kapselt den Lauf im Hintergrund (idempotente Startfolge, GitHub neu laden, neu planen, nächsten Lauf einreichen). Die App registriert ihn per SwiftUI `.backgroundTask(.appRefresh(…))`.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), UserNotifications, BackgroundTasks, EventKit (über `CalendarStore`), SwiftData, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-17-phase-2b-design.md` §8.4, §9, §10 (Zeile 2b-3), §11.13; Phase-2-Design `2026-11-17-phase-2-design.md` §8, §9 (Einrichtung, Punkt 4) und §12.8; Hauptdesign §3 (keine Time-Sensitive-Berechtigung, nur lokale Benachrichtigungen). Vorläufige Entscheidungen dieses Plans: Spec §13.17.

**Nicht in diesem Plan:** Benachrichtigungen für Erinnerungen (Reminders erinnern selbst), nicht zugewiesene Epics (Phase 2 §8 nennt nur Aufgaben), Push (kein bezahlter Account), Time-Sensitive, KI im Hintergrund.

## Änderungen nach dem Fable-Review (2026-11-18) – gehen den Tasks unten vor

Mockup: `docs/superpowers/mockups/2026-11-18-phase-2b3-notifications-mockups.html`, Empfehlungen N1a, N2a, N3a (vorläufig, Freigabe offen).

1. **Freiwillige Abmeldung** (`deactivateGitHub`): Zustand ist danach `nil`, nicht `.signedOut`; die Anfragen `tagwerk.task.github:` werden dort ausdrücklich entfernt. Test `githubVoluntarySignOut_removesGitHubNotifications`.
2. **`submitNext()` am Anfang von `run()`**, damit ein von iOS abgebrochener Lauf die Kette nicht reißt.
3. **Zeitbudget:** Laden im Hintergrund auf ~20 s begrenzen, danach aus dem vorhandenen Stand planen. Bekanntes Restrisiko: ein in der Suspendierung unterbrochener Token-Refresh kann das einmalige Refresh-Token verbrauchen.
4. **Kein doppeltes Laden:** Im Hintergrund GitHub nur registrieren (ohne Katalog) und genau einmal laden.
5. **EventKit:** `gateway.changes` hat genau einen Verbraucher. In `startObservingChanges()` nach `planning.reload()` `scheduler.scheduleSoon()` aufrufen; `Observations` nur für `taskList.items`, `sourceStates` und Einstellungen.
6. **Weitere Auslöser:** nach erteilter Berechtigung (Einrichtung, Einstellungen) sofort; bei `.active` Status neu lesen und planen; bei `.background` `reschedule()` direkt (nicht entprellt).
7. **Vergangene Auslösezeitpunkte:** geplant wird nur, wenn der Auslösezeitpunkt mindestens 60 s nach `now` liegt. Ausstehende eigene Anfragen mit vergangenem Zeitpunkt werden entfernt. Tests `fireDateWithinMargin_skipped`, `overduePendingRequest_removed`.
8. **Trigger:** `DateComponents` Jahr bis Sekunde mit gesetzter `timeZone`.
9. **Delegate unter Swift 6:** Methoden `nonisolated`, aus der Antwort nur Kennung und `userInfo`-Strings entnehmen, dann auf den MainActor. Termintag als ISO-Datum in `userInfo`.
10. **Tippen bei gefilterter Liste:** Router setzt den Filter auf „Alle“; existiert die Aufgabe nicht mehr, nur den Tab zeigen.
11. **Berechtigung:** `.provisional`/`.ephemeral` gelten als erlaubt; angefragt werden `.alert` und `.sound`; „Einstellungen öffnen“ über `UIApplication.openNotificationSettingsURLString`.
12. **Schlüsselbund-Fehler:** fester Offline-Grund „Anmeldung derzeit nicht lesbar.“ statt roher Fehlermeldung; gilt auch für die zweite Prüfung nach dem Abruf. Auslöser neben gesperrtem Gerät: Prewarming vor dem ersten Entsperren.
13. **`.backgroundTask`:** `environment` als `let` im `App`-Struct statt `@State`.
14. **Texte:** Datum ohne Uhrzeit „Fällig heute · <Container>“ (ohne „um 18:00“); ganztägig „Deadline morgen, ganztägig“; mehrtägige Termine zählen ab dem ersten Tag; `isBusy` filtert nicht. Tests `dateOnlyBody_hasNoTime`, `allDayFreeEvent_included`.
15. **Klein:** Spec §13.17 wird in Task 6 angelegt; `SetupModel` bekommt das Center; bei „Einrichtung erneut starten“ mit erteilter Berechtigung gilt der Schritt als erledigt; Task 5 Step 3 ist ein Gerätetest (der Simulator führt `BGTaskScheduler` nicht aus).
16. **Schaltername** „Deadline-Termine“ (nicht „Deadline-Kalender“, das ist schon die Kalenderauswahl).

**Texte (N1a, N2a, N3a):**
- Einrichtung, Schritt „Benachrichtigungen“: „Tagwerk erinnert dich vor der Fälligkeit an GitHub- und lokale Aufgaben und an Termine aus deinen Deadline-Kalendern. Erinnerungen aus der App „Erinnerungen“ melden sich weiterhin selbst.“
- Einstellungen, Fußnote erlaubt: „So lange vor der Fälligkeit erinnert Tagwerk an GitHub- und lokale Aufgaben und an Termine aus Deadline-Kalendern. Ein Datum ohne Uhrzeit gilt als 18:00. An ganztägige Deadline-Termine erinnert Tagwerk am Vortag um 18:00.“ Nicht gefragt: „Benachrichtigungen sind noch nicht erlaubt. Erlaube sie unten unter „Zugriff“.“ Abgelehnt: „Benachrichtigungen sind in iOS ausgeschaltet. Schalte sie unten unter „Zugriff“ wieder ein.“
- Benachrichtigung: Titel = Aufgaben-/Termintitel („Ohne Titel“ bei leerem Titel). Text: „Fällig heute um 14:30 · Lokal“, „Fällig heute · beispiel/webshop“, „Deadline heute um 10:00“, „Deadline morgen, ganztägig“; Tag relativ zum Auslösetag: „heute“, „morgen“, sonst „am Fr., 20.11.“.

## Vorläufige Entscheidungen (Fable-Empfehlung, Freigabe des Nutzers offen) – Spec §13.17

1. **Datum ohne Uhrzeit** gilt bei GitHub **und** lokalen Aufgaben als 18:00 Ortszeit; Auslösung 18:00 minus Vorlauf.
2. **Vorlauf schon vorbei, Fälligkeit noch in der Zukunft:** keine Benachrichtigung. Grund: Jede Neuplanung würde sie sonst erneut sofort auslösen. Liegt die Fälligkeit in der Zukunft und der Auslösezeitpunkt höchstens 1 min in der Vergangenheit, wird ebenfalls übersprungen.
3. **Ganztägige Deadline-Termine:** am Vortag 18:00, ohne Vorlauf (§11.13). Termine mit Uhrzeit: Beginn minus Vorlauf.
4. **Zeitfenster für Deadline-Termine:** die nächsten 60 Tage.
5. **Inhalt:** Titel = Aufgaben- bzw. Termintitel; Text „Fällig heute um 18:00 · <Container>“, „Fällig morgen um 09:00 · …“, „Deadline heute um 14:00“, „Deadline morgen (ganztägig)“. Tag relativ zum Auslösezeitpunkt (heute/morgen/Wochentag mit Datum). Titel sind auf dem Sperrbildschirm sichtbar; wer das nicht will, stellt in iOS „Vorschauen: Wenn entsperrt“ ein (offen für den Nutzer).
6. **Tippen:** Aufgabe → Tab „Aufgaben“ mit Markierung der Aufgabe (`highlight`); Termin → Tab „Planen“, Tagesansicht des Termintags. Im Vordergrund erscheint ein Banner.
7. **Schalter:** „Deadline-Kalender“ (Standard an) unter „Benachrichtigungen“; der Vorlauf gilt für beide. Kein eigener Hauptschalter: die iOS-Berechtigung ist der Hauptschalter.
8. **Hintergrund-Refresh:** frühestens 2 h nach dem letzten Lauf bzw. dem Wechsel in den Hintergrund. iOS entscheidet den Zeitpunkt selbst.

## Global Constraints

- Alle Global Constraints aus 2b-1, 2b-1b und 2b-2 gelten weiter.
- **§8.4:** Weder Hintergrund-Refresh noch Neuplanung der Benachrichtigungen rufen `AIEnvironment`, `AIPlanner` oder `AssistantModel` auf. Nachweis per Test mit `FakeAITransport` (null Anfragen).
- **Keine echten Benachrichtigungen in Tests:** `AppEnvironment` bekommt das Center injiziert; Tests und `AppSmokeTests` nutzen `FakeNotificationCenter`. Kein Berechtigungsdialog im Testlauf.
- **Kennungen:** Benachrichtigungen `tagwerk.task.<TaskID.key>` und `tagwerk.event.<event.id>`; nur Anfragen mit Präfix `tagwerk.` werden entfernt. Hintergrund-Aufgabe: feste Kennung `tagwerk.refresh` (unabhängig von der lokal konfigurierten Bundle-ID), identisch in `project.yml` und Code, per Test geprüft.
- **Keine Time-Sensitive-Stufe** (Berechtigung fehlt beim kostenlosen Account).
- **Datenhoheit:** Ein Lesefehler im Schlüsselbund (z. B. Gerät gesperrt) ist nie eine Abmeldung. GitHub zeigt dann den Cache.
- Code-Kommentare und Logs auf Englisch; keine Titel, Tokens oder persönlichen Daten in Logs.

## Review Focus

1. **Start im Hintergrund ohne GitHub-Anbieter** (der `.task` des Fensters lief nicht, oder der Schlüsselbund ist gesperrt): Die bestehenden GitHub-Benachrichtigungen bleiben stehen; nur geladene oder aus dem Cache gezeigte Quellen werden ersetzt. Test in Task 3.
2. **Schlüsselbund-Lesefehler:** `TokenManager` und `GitHubTaskProvider` melden nicht ab und leeren den Cache nicht. Test in Task 2.
3. **Neuplanung nach Abhaken, Löschen, Fälligkeit ändern, Vorlauf ändern, Deadline-Kalender ändern:** Die passende Benachrichtigung verschwindet bzw. ändert sich. Test in Task 3.
4. **Mehr als 50 Kandidaten:** genau 50, die frühesten; fremde Anfragen (anderes Präfix) bleiben unberührt. Test in Task 1 und 3.
5. **Tippen auf eine Benachrichtigung bei kaltem Start:** Der Delegate ist vor dem Ende des Starts gesetzt; das Ziel wird gemerkt und nach dem Laden angewendet. Test in Task 4 (Routing), Gerät für den echten Kaltstart.

---

### Task 1: Benachrichtigungsplan in `TagwerkCore`

**Files:**
- Create `app/Packages/TagwerkCore/Sources/TagwerkCore/NotificationPlan.swift`.
- Test `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/NotificationPlanTests.swift`.

**Interfaces:**
```swift
public struct PlannedNotification: Sendable, Hashable, Identifiable {
    public enum Target: Sendable, Hashable { case task(TaskID), event(id: String, day: PlanDay) }
    public let id: String          // "tagwerk.task.<key>" / "tagwerk.event.<id>"
    public let fireDate: Date
    public let title: String
    public let body: String
    public let target: Target
    public let source: TaskSource? // nil for calendar events
}
public struct NotificationRules: Sendable {
    public var leadTimeMinutes: Int
    public var includesDeadlineCalendars: Bool
    public var limit: Int = 50
    public var dateOnlyHour: Int = 18
}
public func notificationPlan(tasks: [TaskItem], deadlineEvents: [CalendarEvent], rules: NotificationRules,
                             now: Date, calendar: Calendar) -> [PlannedNotification]
```

- [ ] **Step 1: Failing tests:**
  - `remindersAndCompletedTasks_excluded`
  - `githubDateOnly_firesAt18MinusLeadTime`, `localDateOnly_firesAt18MinusLeadTime`
  - `timedTask_firesAtDueMinusLeadTime`
  - `fireDateInPast_skipped` (auch wenn die Fälligkeit noch kommt)
  - `timedDeadlineEvent_firesAtStartMinusLeadTime`, `allDayDeadlineEvent_firesPreviousDayAt18`
  - `deadlineCalendarsSwitchOff_excludesEvents`
  - `limit_keepsEarliestFifty`
  - `identifiers_areStable` (gleiche Eingabe → gleiche Kennungen; Kennung hängt nicht vom Titel ab)
  - `body_usesRelativeDayOfFireDate` (heute/morgen/„Fr., 21.11.“, mit Container bei Aufgaben)
  - `dstChange_keepsWallClockTime` (Fälligkeit 18:00 am Tag nach der Zeitumstellung)
- [ ] **Step 2: Implementierung** als reine Funktion; Wochentag/Datum mit `de_DE`.
- [ ] **Step 3:** Paket-Tests grün (`app/test-all.sh` oder Paket-Stufe).
- [ ] **Step 4: Commit** `feat: compute deadline notifications from tasks and deadline calendars`

### Task 2: Schlüsselbund-Lesefehler ist keine Abmeldung (`GitHubKit`)

**Files:**
- Modify `app/Packages/GitHubKit/Sources/GitHubKit/TokenManager.swift` (neu `public func hasCredentials() async throws -> Bool`; `isSignedIn` bleibt für die UI).
- Modify `app/Packages/GitHubKit/Sources/GitHubKit/GitHubTaskProvider.swift` (`openTasks` prüft mit `hasCredentials()` innerhalb des `do`; ein Lesefehler wird `.failed` und zeigt den Cache).
- Tests in `TokenManagerTests.swift`, `GitHubTaskProviderReadTests.swift`.

- [ ] **Step 1: Failing tests:**
  - `hasCredentials_storeThrows_rethrows` (kein `false`, kein Löschen)
  - `openTasks_keychainUnreadable_showsCacheAndKeepsSignIn` (kein `TaskWriteError.signedOut`, Cache nicht geleert, `offlineSince` gesetzt)
  - `openTasks_noCredentials_stillSignsOut` (Regression)
- [ ] **Step 2: Implementierung.**
- [ ] **Step 3: Commit** `fix: treat an unreadable keychain as offline instead of signed out`

### Task 3: `NotificationScheduler` in der App

**Files:**
- Create `app/Tagwerk/Notifications/NotificationCenterClient.swift` (Protokoll + `SystemNotificationCenter` über `UNUserNotificationCenter`), `app/Tagwerk/Notifications/NotificationScheduler.swift`.
- Create `app/TagwerkTests/Fakes/FakeNotificationCenter.swift`, Test `app/TagwerkTests/NotificationSchedulerTests.swift`.
- Modify `AppSettings.swift` (`deadlineCalendarNotifications: Bool = true`), `AppEnvironment.swift` (Center injizierbar, Scheduler erzeugen, Neuplanung auslösen), `TagwerkApp.swift`, `AppSmokeTests.swift` (Fake-Center).
- `xcodegen` in `app/` (neuer Ordner).

**Interfaces:**
```swift
protocol NotificationCenterClient: Sendable {
    func authorizationStatus() async -> NotificationAuthorization   // .notDetermined, .denied, .authorized
    func requestAuthorization() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func add(_ notification: PlannedNotification) async throws
    func removePending(_ identifiers: [String]) async
}
@MainActor final class NotificationScheduler {
    init(center: any NotificationCenterClient, taskList: TaskListModel, calendarStore: any CalendarStore,
         settings: AppSettings, now: @escaping () -> Date, calendar: Calendar)
    func reschedule() async            // no-op without authorization
    func scheduleSoon()                // debounced (1 s) for change bursts
}
```

Regeln:
- Ohne Berechtigung (`notDetermined`/`denied`) nichts planen, nichts entfernen.
- Quellen, deren Zustand nicht `.loaded` oder `.offline` ist (fehlend, `.failed`, `.noAccess`), behalten ihre bestehenden Benachrichtigungen (Präfix + Quelle in der Kennung). Abgemeldete Quellen (`.signedOut`) verlieren sie.
- Deadline-Termine nur bei vollem Kalenderzugriff; sonst bleiben bestehende Termin-Benachrichtigungen stehen.
- Abgleich: entfernen, was nicht mehr gewünscht ist; hinzufügen bzw. ersetzen, was gewünscht ist (gleiche Kennung ersetzt). Die 50er-Grenze gilt für die Summe einschließlich behaltener Anfragen.
- Auslöser: App-Start (nach dem ersten Laden), jede Änderung von `taskList.items` und `sourceStates`, Änderung von Vorlauf, Schalter, Deadline-Kalendern, EventKit-Änderungen, `scenePhase == .background`, Hintergrund-Refresh. Umsetzung über `Observations` mit Entprellung.

- [ ] **Step 1: Failing tests:**
  - `noAuthorization_schedulesNothing`
  - `schedulesGitHubAndLocal_notReminders`
  - `completedTask_removesItsNotification`, `dueChanged_replacesNotification`
  - `leadTimeChanged_reschedulesAll`, `deadlineSwitchOff_removesEventNotifications`
  - `githubNotLoaded_keepsExistingGitHubNotifications` (Review Focus 1)
  - `githubSignedOut_removesGitHubNotifications`
  - `foreignPendingRequests_untouched`
  - `limit_countsKeptRequests`
  - `noAIRequests_duringReschedule` (FakeAITransport)
- [ ] **Step 2: Implementierung**, `SystemNotificationCenter` (`UNCalendarNotificationTrigger` aus den Datumsteilen des Auslösezeitpunkts, `threadIdentifier` je Quelle, `userInfo` mit Ziel, Standard-Ton, Stufe `.active`).
- [ ] **Step 3: Commit** `feat: schedule deadline notifications and keep them current`

### Task 4: Einrichtung, Einstellungen und Tippen auf die Benachrichtigung

**Files:**
- Modify `app/Tagwerk/Setup/SetupModel.swift` (Schritt `.notifications` nach `.chatGPT`; Kommentar „added by a later plan“ entfernen), `SetupView.swift`, `SetupModelTests.swift`.
- Modify `SettingsView.swift`: Abschnitt „Benachrichtigungen“ mit Vorlauf, Schalter „Deadline-Kalender“, Footer; Zeile „Benachrichtigungen“ unter „Zugriff“ (Erlauben / erlaubt / Einstellungen öffnen).
- Create `app/Tagwerk/Notifications/NotificationRouter.swift` (Delegate: Banner im Vordergrund; Tipp → Ziel merken), Test `NotificationRouterTests.swift`.
- Modify `TagwerkApp.swift` (Delegate im `init` setzen), `RootView.swift`/`AppEnvironment.swift` (gemerktes Ziel nach dem ersten Laden anwenden: Tab + `highlight` bzw. Planen/Tag).

- [ ] **Step 1: Failing tests:**
  - `setup_notificationsStep_requestsAuthorization_andRecordsResult`, `setup_skipNotifications_finishes`
  - `router_taskTarget_selectsTasksTabAndHighlights`, `router_eventTarget_opensDayView`
  - `router_targetBeforeLoad_appliedAfterLoad`
- [ ] **Step 2: UI** nach Mockup `docs/superpowers/mockups/2026-11-18-phase-2b3-notifications-mockups.html` (vorläufig, Freigabe offen).
- [ ] **Step 3: Simulator:** Einrichtung erneut starten, Schritt prüfen; Einstellungen prüfen.
- [ ] **Step 4: Commit** `feat: ask for notification permission in setup and settings and open the task on tap`

### Task 5: Hintergrund-Refresh

**Files:**
- Modify `app/project.yml`: `UIBackgroundModes: [fetch]`, `BGTaskSchedulerPermittedIdentifiers: [tagwerk.refresh]`.
- Create `app/Tagwerk/Notifications/BackgroundRefresh.swift` (Kennung, `run()`, `submitNext()`), Test `BackgroundRefreshTests.swift`.
- Modify `TagwerkApp.swift` (`.backgroundTask(.appRefresh(BackgroundRefresh.identifier))`, Einreichen bei `.background`), `AppEnvironment.swift` (idempotente Startfolge `prepareForBackgroundWork()`: Änderungen beobachten, GitHub aktivieren, falls angemeldet).

Ablauf von `run()`: Startfolge → `taskList.reload()` (GitHub über Netz oder Cache, Reminders und lokal) → `scheduler.reschedule()` → `submitNext()` (frühestens in 2 h). Fehler von `submit` nur loggen (Simulator).

- [ ] **Step 1: Failing tests:**
  - `infoPlist_containsRefreshIdentifier_andFetchMode` (liest das gebaute `Info.plist` des App-Bundles)
  - `run_reloadsAndReschedules`
  - `run_withoutGitHubProvider_keepsGitHubNotifications`
  - `run_sendsNoAIRequests` (FakeAITransport, null Anfragen)
  - `run_submitsNextRequest`
- [ ] **Step 2: Implementierung.**
- [ ] **Step 3: Simulator:** App in den Hintergrund; Lauf per LLDB `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"tagwerk.refresh"]` auslösen, wenn verfügbar; sonst als Gerätetest offen lassen.
- [ ] **Step 4: Commit** `feat: refresh tasks and notifications in the background`

### Task 6: Abschluss

- [ ] `app/test-all.sh` und `zsh scripts/tests/refresh-decisions.zsh` grün.
- [ ] Spec §13.17 um Abweichungen ergänzen.
- [ ] Simulator mit Demo-Daten: Benachrichtigung mit kurzem Vorlauf auslösen lassen (Demo-Aufgabe in 20 min fällig, Vorlauf 15 min), Banner und Tipp prüfen.
- [ ] Fable-Review des Branches, Befunde beheben.
- [ ] Commit `docs: record the 2b-3 decisions and deviations`
