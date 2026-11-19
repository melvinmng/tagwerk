# P4: Flexible und mehrfache Erinnerungen (#151) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026, ohne Mockups (Design folgt in #188). Nichts gebaut. Annahmen A1–A10 sind vom Nutzer im Vorschlag bestätigt bzw. von der Hauptsitzung gesetzt; Abweichungen nur nach Rückfrage.

**Goal:** Aufgaben (alle Quellen), Deadlines und Kalendertermine bekommen beliebig viele Erinnerungen mit frei wählbaren Zeitpunkten (relativ oder „n Tage vorher um hh:mm“). Standard-Erinnerungen je Art stehen in den Einstellungen und lassen sich je Eintrag überschreiben. Bei Serien fragt Tagwerk „Nur dieser“ / „Alle folgenden“.

**Architecture:** Reine Regeln in `TagwerkCore` (`ReminderOffset`, `ReminderDefaults`, `ReminderOverrideResolution`, Erweiterung von `notificationPlan`, `NotificationBudget`). Speicherorte: EventKit-Alarme für normale Kalendertermine und Apple-Erinnerungen (`RemindersKit`), Tagwerk-Mitteilungen über den vorhandenen `NotificationScheduler` für GitHub-Issues, lokale Aufgaben und Deadlines. Eintragsbezogene Abweichungen liegen in einem neuen SwiftData-Typ `ReminderOverrideRecord`. Die UI besteht aus einem wiederverwendbaren `ReminderListEditor`, eingebaut in Aufgaben-Editor, `EventEditSheet`, Deadline-Abschnitt des `EntrySheet` und eine neue Einstellungsseite.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, EventKit (`EKAlarm`), UserNotifications, Swift Testing, XcodeGen.

**Issue:** GitHub #151. Branch: `feat/flexible-reminders`.

## Annahmen (verbindlich für diesen Plan)

- **A1 Speicherorte:** Normale Kalendertermine → `EKAlarm` am `EKEvent`. Apple-Erinnerungen → `EKAlarm` am `EKReminder`. GitHub-Issues, lokale Aufgaben und Deadlines (Deadline-Kalender und markierte Termine) → Tagwerk-Mitteilungen. EventKit-Alarme sind in Apples Apps sichtbar und unbegrenzt.
- **A2 Standard vs. eigene Liste:** Ein Eintrag ohne `ReminderOverrideRecord` folgt dem Standard seiner Art. Für Aufgaben aller Quellen (auch Apple-Erinnerungen) und für Deadlines bedeutet „Standard“: Tagwerk-Mitteilungen wie heute. Wer bei einer Apple-Erinnerung eine eigene Liste speichert, bekommt sie als `EKAlarm`s geschrieben; ein Override-Datensatz mit `storage = eventKit` markiert sie, und Tagwerk plant für sie keine eigenen Mitteilungen mehr. „Standard verwenden“ entfernt die von Tagwerk geschriebenen Alarme wieder (nur die, deren Zeitpunkte im Override gespeichert sind) und löscht den Datensatz.
- **A3 Normale Termine:** Standard für Termine ist leer (heute keine Mitteilungen). Ist ein Standard für Termine gesetzt, schreibt Tagwerk ihn **nur beim Anlegen** eines Termins in Tagwerk als `EKAlarm`s. Bestehende Termine bleiben unberührt. Tagwerk plant für normale Termine nie eigene Mitteilungen.
- **A4 Zeitpunkte:** `ReminderOffset` kennt `.before(amount, unit)` mit Einheiten Minuten/Stunden/Tage/Wochen (amount 0 = „Zum Zeitpunkt“), `.at(daysBefore, hour, minute)` („1 Tag vorher um 18:00“, daysBefore 0 = „Am selben Tag um …“) und `.absolute(Date)` (nur gelesen aus EventKit, bleibt erhalten und ist löschbar, wird in Tagwerk nicht neu angelegt). Keine feste Obergrenze je Eintrag; doppelte Einträge werden beim Speichern entfernt.
- **A5 Ohne Uhrzeit / ganztägig:** Für Aufgaben ohne Uhrzeit und ganztägige Termine/Deadlines ist der Anker 00:00 des Tages; `.before` mit Minuten/Stunden ist dort nicht wählbar (Picker bietet nur Tage/Wochen und `.at`). Jede Standardliste hat zwei Varianten: „mit Uhrzeit“ und „ohne Uhrzeit / ganztägig“.
- **A6 Migration:** `reminderDefaultsData == nil` ergibt die Standards aus den bisherigen Feldern, verhaltensgleich zu heute: Aufgaben mit Uhrzeit `[.before(leadTimeMinutes, .minutes)]` (als größte glatte Einheit dargestellt), Aufgaben ohne Uhrzeit `[.at(0, 9, 0)]`, Deadlines mit Uhrzeit `[.before(leadTime)]`, ganztägige Deadlines `[.at(1, 18, 0)]`, Termine `[]` / `[]`. Die Schalter je Quelle und „Deadline-Termine“ bleiben unverändert. `leadTimeMinutes` bleibt im Schema (Attribute werden nie entfernt), wird aber nicht mehr angezeigt.
- **A7 Rollierendes Planen:** Das Budget bleibt 50 (`NotificationScheduler.limit`). Der Plan nimmt wie heute die frühesten 50; neu ist, dass ein Eintrag mehrere Mitteilungen hat. Nachgefüllt wird bei jedem Lauf (Änderungen, Vordergrund, Hintergrund-Refresh). Liegt mehr im Plan als ins Budget passt, setzt der Hintergrund-Refresh sein `earliestBeginDate` spätestens auf den Zeitpunkt der 50. Mitteilung minus 1 h.
- **A8 Serien:** Termine (EventKit): vorhandene Abfrage „Nur diesen Termin“ / „Diesen und alle folgenden“ im `EventEditSheet` gilt auch für Alarme (`EKSpan`). Deadlines in Serien: eigene Abfrage im Deadline-Blatt; Override gilt für das Vorkommen oder ab diesem Tag für die Serie. Wiederholende lokale Aufgaben: „Nur diese“ bindet den Override an das aktuelle Fälligkeitsdatum, „Alle folgenden“ gilt dauerhaft. Wiederholende Apple-Erinnerungen und GitHub-Issues: keine Abfrage (EventKit kennt bei Erinnerungen nur das eine Objekt; GitHub hat keine Serien); Fußtext sagt „gilt für alle Wiederholungen“.
- **A9 Ruhezeiten:** Tagwerk-Mitteilungen laufen weiter durch `NotificationRules.deliveryDate` (Ruhezeiten, Fokus-Filter). Fallen mehrere Erinnerungen eines Eintrags durch das Verschieben auf dieselbe Minute, bleibt eine. EventKit-Alarme meldet iOS selbst; Ruhezeiten gelten dafür nicht (Fußtext im Editor).
- **A10 Neue Aufgabe:** `NewTaskSheet` bekommt keinen Erinnerungs-Abschnitt; neue Aufgaben folgen dem Standard, Anpassung im Editor danach.

## Global Constraints

- Ein SwiftData-Store; neuer Typ `ReminderOverrideRecord` in `ModelContainerFactory.schema`; neue Attribute optional oder mit Standardwert; `ModelStoreLocationTests` bleibt grün.
- **Erweiterbarkeit des Schedulers (wegen P1 und P3):** Der `NotificationScheduler` fasst nur noch Kennungen mit Präfix `tagwerk.task.` oder `tagwerk.event.` an (`PlannedNotification.isBudgeted(_:)`), statt „alles mit `tagwerk.` außer Routine“. Andere Pakete legen eigene Präfixe an (z. B. `tagwerk.routine.` für die Wochenplanung in P1, `tagwerk.focus.` für den Fokus-Timer in P3) und bleiben unberührt. Neues `NotificationBudget` in `TagwerkCore` hält die Platzaufteilung zentral (`system = 64`, `tasksAndDeadlines = 50`, `routines = 5`, `reserve = 9`); ein Test prüft, dass die Summe ≤ 64 ist. P1/P3 ergänzen dort ihre Plätze aus `reserve`. Keine weiteren Änderungen an `RoutineNotificationScheduler`.
- **Konfliktarm bauen:** `EntrySheet` nur minimal ändern (eine Zeile im Deadline-Abschnitt, ein `.sheet` im vorhandenen Helfer `eventPresentations`). **Keine** `.sheet`/`.confirmationDialog` an `Section`s in einer `Form` hängen (Lehre aus PR #202: Modifier an einer Section werden an jede Zeile weitergereicht und stapeln Blätter). `PlanView` nicht anfassen. Neue UI in eigene Dateien unter `app/Tagwerk/Reminders/`.
- Kennungen mehrerer Mitteilungen je Eintrag: `tagwerk.task.<task key>#<n>` bzw. `tagwerk.event.<event id>#<n>` mit `n` = Index in der sortierten Liste. Alte Kennungen ohne `#` werden beim ersten Lauf als veraltet entfernt und neu angelegt. `NotificationNavigator` liest `userInfo`, nicht die Kennung (unverändert).
- Deutsch ist Quellsprache; jeder neue Text deutsch und englisch in `Localizable.xcstrings` bzw. dem Katalog von `TagwerkCore`/`RemindersKit` (`scripts/sync-strings.sh`, `scripts/check-strings.py`). Plurale über Katalog-Varianten. Code, Kommentare, Logs, Testnamen englisch.
- Kein KI-Aufruf. Kein Text einer Erinnerung geht an ChatGPT. Der Assistent bekommt keine neuen Werkzeuge.
- Sicherung: `AppSettingsBackup` bekommt `reminderDefaultsData: Data?` (optional, alte Sicherungen bleiben lesbar); `ReminderOverrideRecord` kommt als eigene optionale Liste in die Sicherung.
- Commits: Conventional Commits auf Englisch, ohne Hinweis auf KI, ohne `Co-Authored-By`. Vor jedem Commit ab Task 7: `app/test-all.sh`.

## Review Focus

1. **Migration verhaltensgleich:** Ohne Eingriff des Nutzers plant der neue Scheduler exakt dieselben Zeitpunkte wie vorher (Test `migratedDefaults_planSameFireDatesAsLegacyRules`).
2. **Doppelte Meldungen:** Apple-Erinnerung mit eigener Liste → nur EventKit-Alarme, keine Tagwerk-Mitteilung. Override entfernt → Tagwerk-Mitteilungen wieder da, die von Tagwerk geschriebenen Alarme weg, fremde Alarme (aus der Erinnerungen-App) unverändert.
3. **Budget:** 30 Aufgaben × 3 Erinnerungen → genau 50 geplant, die frühesten; nach Ablauf der ersten werden die nächsten nachgefüllt. Routinen- und andere Präfixe bleiben unangetastet.
4. **Serien:** „Nur dieser“ auf Vorkommen 2 einer Deadline-Serie ändert Vorkommen 1 und 3 nicht; „Alle folgenden“ ab Vorkommen 2 ändert 2 und 3, nicht 1.
5. **Zeitumstellung:** `.at(1, 18, 0)` vor einem Termin am Tag nach der Umstellung feuert um 18:00 Ortszeit (Kalenderarithmetik, nicht Sekunden). Für `EKAlarm.relativeOffset` wird der Abstand je Vorkommen berechnet; bei Serien über die Umstellung hinweg ist eine Stunde Versatz möglich (bekannte Grenze, im Plan-Nachtrag vermerken).

---

## Task 1: `ReminderOffset` und Texte (TagwerkCore)

**Files:** Create `app/Packages/TagwerkCore/Sources/TagwerkCore/ReminderOffset.swift`, `.../ReminderText.swift`; Test `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/ReminderOffsetTests.swift`, `ReminderTextTests.swift`.

- [ ] Typen: `public enum ReminderUnit: String, Codable, CaseIterable { case minutes, hours, days, weeks }`; `public enum ReminderOffset: Codable, Hashable, Sendable { case before(amount: Int, unit: ReminderUnit); case at(daysBefore: Int, hour: Int, minute: Int); case absolute(Date) }`.
- [ ] `func fireDate(anchor: Date, isAllDay: Bool, calendar: Calendar) -> Date?`: `.before` über `calendar.date(byAdding:)`; `.at` = Tag des Ankers minus `daysBefore` Tage, dann Uhrzeit setzen; `.absolute` unverändert. Bei `isAllDay` ist der Anker der Tagesbeginn.
- [ ] `static func normalized(_ list: [ReminderOffset], isAllDay: Bool) -> [ReminderOffset]`: entfernt Duplikate (auch gleichwertige wie 60 min = 1 h), verwirft `.before` mit Minuten/Stunden bei `isAllDay`, sortiert vom frühesten zum spätesten Zeitpunkt (relativ zum Anker), Werte begrenzt (amount 0…999, daysBefore 0…365, Uhrzeit gültig).
- [ ] `static func largestUnit(minutes: Int) -> ReminderOffset` (120 → 2 Stunden, 2880 → 2 Tage, 10080 → 1 Woche).
- [ ] `ReminderText.describe(_:locale:)`: „Zum Zeitpunkt“, „15 Minuten vorher“, „2 Stunden vorher“, „1 Tag vorher“, „2 Wochen vorher“, „Am selben Tag um 9:00“, „1 Tag vorher um 18:00“, absolute Daten mit `DateText`. Englisch: „At time of event“, „15 minutes before“, „1 day before at 6:00 PM“. `ReminderText.summary(_ list:)`: „Keine“, ein Eintrag wörtlich, sonst „2 Wochen vorher + 2 weitere“.
- [ ] Tests: `fireDate_before_subtractsCalendarUnits`, `fireDate_atDaysBefore_setsLocalTime`, `fireDate_at_acrossDaylightSavingChange_keepsWallClock`, `fireDate_allDay_anchorsAtStartOfDay`, `normalized_removesEquivalentDuplicates`, `normalized_dropsHourOffsetsForAllDay`, `normalized_sortsEarliestFirst`, `largestUnit_picksWholeUnits`, `describe_german`, `describe_english`, `summary_countsTheRest`.
- [ ] Commit `feat: add reminder offsets and their texts`.

## Task 2: `ReminderDefaults` und Migration (TagwerkCore)

**Files:** Create `.../ReminderDefaults.swift`; Test `ReminderDefaultsTests.swift`.

- [ ] `public enum ReminderKind: String, Codable, CaseIterable { case task, deadline, event }`; `public struct ReminderDefaults: Codable, Hashable, Sendable { var timed: [ReminderKind: [ReminderOffset]]; var allDay: [ReminderKind: [ReminderOffset]] }` mit `func offsets(for: ReminderKind, isAllDay: Bool) -> [ReminderOffset]` (normalisiert).
- [ ] `static func legacy(leadTimeMinutes: Int, dateOnlyHour: Int = 9, allDayEventHour: Int = 18) -> ReminderDefaults` gemäß A6.
- [ ] `static func decode(_ data: Data?, leadTimeMinutes: Int) -> ReminderDefaults`: `nil` oder defekt → `legacy`. `func encoded() -> Data`.
- [ ] Tests: `legacy_matchesTodaysRules`, `decode_nil_fallsBackToLegacy`, `decode_corrupt_fallsBackToLegacy`, `roundTrip_keepsAllKinds`, `offsets_areNormalized`.
- [ ] Commit `feat: add reminder defaults with migration from the lead time`.

## Task 3: Abweichungen je Eintrag und Serienregel (TagwerkCore)

**Files:** Create `.../ReminderOverride.swift`; Test `ReminderOverrideTests.swift`.

- [ ] `public struct ReminderOverride: Hashable, Sendable { enum Scope { case always; case onlyDue(DueDate); case occurrence(String); case seriesFrom(PlanDay) }; enum Storage { case tagwerk, eventKit }; var itemKey: String; var scope: Scope; var storage: Storage; var offsets: [ReminderOffset] }`.
- [ ] Schlüssel: `ReminderOverride.key(task: TaskID)` = `"task:" + key`; `key(deadlineSeries:)` = `"deadline:" + Basis-ID` (über `CalendarBlockRules.parseOccurrenceID` wird die Vorkommens-ID zerlegt; die Basis-ID wird in der App ermittelt und als String übergeben, Core bleibt EventKit-frei).
- [ ] `ReminderOverrideResolution.offsets(for itemKey:, occurrenceID:, day:, due:, overrides:, defaults:) -> (offsets, storage)`: Vorrang `occurrence` > `onlyDue` (nur wenn `due` gleich) > `seriesFrom` mit dem spätesten Tag ≤ `day` > `always` > Standard.
- [ ] Tests: `noOverride_usesDefaults`, `onlyDue_appliesWhileDueUnchanged_thenFallsBack`, `occurrence_beatsSeries`, `seriesFrom_appliesFromItsDayOn_notBefore`, `laterSeriesFrom_winsOverEarlier`, `eventKitStorage_isReported`.
- [ ] Commit `feat: resolve per-entry reminder overrides including series`.

## Task 4: Mehrere Mitteilungen im `notificationPlan` + Budget (TagwerkCore)

**Files:** Modify `.../NotificationPlan.swift`; Create `.../NotificationBudget.swift`; Tests `NotificationPlanTests.swift`, `NotificationPlanQuietHoursTests.swift`, new `NotificationPlanMultipleTests.swift`, `NotificationBudgetTests.swift`.

- [ ] `NotificationRules` bekommt `reminders: (ReminderPlanItem) -> [ReminderOffset]` **nicht** als Closure (Sendable/Hashable), sondern `defaults: ReminderDefaults` + `overrides: [String: [ReminderOverride]]` (nach `itemKey`) + `seriesKey: [String: String]` (Vorkommens-ID → Serien-Basis). Der alte Initialisierer mit `leadTimeMinutes` bleibt als Bequemlichkeit und baut `ReminderDefaults.legacy` (damit bestehende Tests unverändert laufen).
- [ ] Aufgaben: Override mit `storage == .eventKit` → keine Tagwerk-Mitteilung. Sonst je Offset eine `PlannedNotification` mit Kennung `identifier(for:index:)` = `tagwerk.task.<key>#<n>`; Deadlines analog `tagwerk.event.<id>#<n>`. Bodies und `isOverdue` wie bisher.
- [ ] Je Eintrag: nach `deliveryDate` gleiche Minute → nur die erste behalten.
- [ ] `PlannedNotification.isBudgeted(_ id:)` = Präfix `tagwerk.task.` oder `tagwerk.event.`.
- [ ] `NotificationBudget` mit `system`, `tasksAndDeadlines`, `routines`, `reserve` und statischer Prüfung.
- [ ] Tests: `migratedDefaults_planSameFireDatesAsLegacyRules` (bestehende Fälle über beide Initialisierer vergleichen), `threeOffsets_yieldThreeNotificationsWithIndexedIDs`, `eventKitOverride_suppressesTagwerkNotifications`, `limit_keepsEarliestAcrossEntries`, `quietHours_collapseSameMinuteOfOneEntry`, `pastOffsets_areSkipped_laterOnesKept`, `deadlineSeries_onlyThisOccurrenceOverride`, `isBudgeted_ignoresRoutineAndOtherPrefixes`, `budget_sumStaysWithinSystemLimit`.
- [ ] Commit `feat: plan several notifications per task and deadline`.

## Task 5: EventKit-Alarme lesen und schreiben (RemindersKit)

**Files:** Modify `ReminderRecord.swift`, `EventKitGateway.swift`, `CalendarStore.swift` (`EventDraft`), `ReminderStore.swift` (Protokoll), `FakeReminderStore.swift`; Create `AlarmMapping.swift`; Tests `AlarmMappingTests.swift`, Ergänzung `RemindersTaskProviderTests.swift`.

- [ ] `AlarmMapping.offset(relativeOffset:isAllDay:calendar:)` → `ReminderOffset` (ganze Wochen/Tage/Stunden/Minuten vorher; bei ganztägig negative Offsets mit Uhrzeit → `.at(daysBefore, h, m)`; positive Offsets bei ganztägig, z. B. +9 h = „Am selben Tag um 9:00“ → `.at(0, 9, 0)`).
- [ ] `AlarmMapping.relativeOffset(for:anchor:isAllDay:calendar:)` → `TimeInterval?` (für `.at` die Differenz zum Anker dieses Vorkommens; `.absolute` → `nil`, wird als `EKAlarm(absoluteDate:)` geschrieben).
- [ ] `ReminderRecord.alarms: [ReminderOffset]` gelesen aus `EKReminder.alarms` (Anker: Fälligkeit; ohne Fälligkeit nur `.absolute`). `ReminderStore.setAlarms(_:forReminder:)` und `removeAlarms(_:forReminder:)` (entfernt nur Alarme mit gleichem Zeitpunkt).
- [ ] `EventDraft.alarms: [ReminderOffset]?` (`nil` = unverändert, damit bestehende Aufrufer und `AppTools` nichts ändern); `apply(_:to:)` ersetzt die Alarme nur bei nicht-`nil`. `CalendarStore.alarms(ofEvent id:) -> [ReminderOffset]` für den Editor.
- [ ] `create(...)` für Erinnerungen: der bisherige Alarm zur Fälligkeit bleibt (Apples Verhalten).
- [ ] Tests: `relativeOffset_roundTripsWholeUnits`, `allDay_eveningBefore_mapsToAtDaysBefore`, `allDay_positiveOffset_mapsToSameDay`, `absolute_staysAbsolute`, `draftWithoutAlarms_leavesEventAlarmsUntouched`, `removeAlarms_keepsForeignAlarms` (Fake).
- [ ] Commit `feat: read and write EventKit alarms for events and reminders`.

## Task 6: Speicher für Abweichungen und Einstellungen (App)

**Files:** Create `app/Tagwerk/Reminders/ReminderOverrideRecord.swift`, `ReminderOverrideStore.swift`; Modify `AppSettings.swift` (`reminderDefaultsData: Data? = nil`, berechnete Eigenschaft `reminderDefaults`), `ModelContainerFactory.swift`, `BackupDTOs.swift` und Sicherungslogik; Tests `ReminderOverrideStoreTests.swift`, `BackupTests.swift` (Ergänzung), `ModelStoreLocationTests` grün.

- [ ] `@Model ReminderOverrideRecord`: `itemKey: String`, `scopeRaw: String`, `scopeValue: String?` (Fälligkeit als `DueDate`-JSON, Vorkommens-ID oder `PlanDay`-Schlüssel), `storageRaw: String`, `offsetsData: Data`, `updatedAt: Date`.
- [ ] `ReminderOverrideStore`: `overrides() -> [String: [ReminderOverride]]`, `save(_:)`, `remove(itemKey:scope:)`, `removeAll(itemKey:)`; Lesen fügt nie ein. Aufräumen: Overrides gelöschter lokaler Aufgaben mitlöschen (Hook im `LocalTaskProvider`-Löschpfad), `onlyDue`-Overrides mit vergangener Fälligkeit beim Start entfernen.
- [ ] Tests: `save_thenRead_roundTrips`, `reading_neverInserts`, `staleOnlyDueOverrides_areRemoved`, `deletingLocalTask_removesItsOverride`, Backup `backup_roundTripsReminderDefaultsAndOverrides`, `oldBackupWithoutReminderFields_restores`.
- [ ] Commit `feat: store reminder defaults and per-entry overrides`.

## Task 7: Scheduler umstellen (App)

**Files:** Modify `app/Tagwerk/Notifications/NotificationScheduler.swift`, `BackgroundRefresh.swift`, `AppEnvironment.swift` (Hash der Einstellungen um `reminderDefaultsData` und Override-Revision ergänzen, Zeile ~632; Override-Store injizieren), `TagwerkApp.swift` (bei `scenePhase == .active` `notifications.scheduleSoon()`, falls noch nicht vorhanden); Tests `NotificationSchedulerTests.swift`, `NotificationSchedulerQuietHoursTests.swift`, `BackgroundRefreshTests.swift`.

- [ ] `ours` filtert mit `PlannedNotification.isBudgeted`. Limit aus `NotificationBudget.tasksAndDeadlines`.
- [ ] Regeln aus `settings.reminderDefaults` und `overrideStore.overrides()`; Serienschlüssel der Deadline-Termine in der App über `CalendarBlockRules.parseOccurrenceID` ermitteln.
- [ ] Nach dem Lauf: Gibt es mehr gewünschte Mitteilungen als Plätze, meldet der Scheduler `nextRefill: Date?` (Zeitpunkt der letzten geplanten minus 1 h); `BackgroundRefresh` nimmt das Minimum aus seinem bisherigen `earliestBeginDate` und `nextRefill`.
- [ ] Tests: `reschedule_replacesLegacyIDsWithIndexedOnes`, `reschedule_keepsRoutineAndForeignPrefixes`, `reschedule_overflow_reportsRefillDate`, `reschedule_afterFirstFired_refillsNext`, `appleReminderWithEventKitOverride_getsNoTagwerkNotification`, `quietHours_stillApplyToEveryOffset`, `backgroundRefresh_usesEarlierRefillDate`.
- [ ] Commit `feat: schedule several reminders per entry with rolling refill`.

## Task 8: `ReminderListEditor` (App, wiederverwendbar)

**Files:** Create `app/Tagwerk/Reminders/ReminderListEditor.swift`, `ReminderOffsetPicker.swift`, `ReminderListModel.swift`; Test `ReminderListModelTests.swift`.

- [ ] `ReminderListModel` (`@Observable`): `offsets`, `isUsingDefault`, `defaultOffsets`, `isAllDay`; `add`, `remove(at:)`, `useDefault()`, `customize()` (übernimmt die Standardliste als Startpunkt); `result -> ReminderListResult { case useDefault; case custom([ReminderOffset]) }`.
- [ ] `ReminderListEditor`: liefert **Zeilen** (kein eigenes `Section`-Modifier-Blatt); Zeilen „2 Wochen vorher“ mit Wischen zum Löschen, Zeile „Erinnerung hinzufügen“ öffnet `ReminderOffsetPicker`, Schalter bzw. Zeile „Standard verwenden“ (Standardliste grau). Das Blatt für den Picker hängt der Aufrufer an die `Form`/den Helfer, nicht an die Section (Lehre aus #202); der Editor gibt dafür ein `Binding<Bool>` heraus oder nutzt `.navigationDestination` in einer `NavigationStack`.
- [ ] `ReminderOffsetPicker`: Segment „Vorher“ (Stepper Menge + Picker Einheit; bei ganztägig nur Tage/Wochen) / „Zu einer Uhrzeit“ (Stepper „Tage vorher“ 0…365 + Uhrzeit). Vorschau-Zeile mit `ReminderText.describe`. Schnellauswahl: „Zum Zeitpunkt“, „1 Stunde vorher“, „1 Tag vorher“, „1 Woche vorher“.
- [ ] Tests: `customize_startsFromDefaults`, `add_duplicate_isIgnored`, `useDefault_returnsUseDefault`, `allDay_hidesHourUnits`.
- [ ] Commit `feat: add a reusable reminder list editor`.

## Task 9: Aufgaben-Editor (App)

**Files:** Modify `app/Tagwerk/Editor/TaskEditorModel.swift`, `TaskEditorView.swift`; Test `TaskEditorModelTests.swift`.

- [ ] Abschnitt „Erinnerungen“ direkt nach dem Fälligkeits-/Planungsbereich, nur sichtbar mit Fälligkeit. Ohne Fälligkeit Hinweiszeile „Erinnerungen brauchen ein Fälligkeitsdatum.“
- [ ] Speichern: GitHub/lokal → `ReminderOverrideStore` (`storage = tagwerk`); Apple-Erinnerung → `ReminderStore.setAlarms` + Override `storage = eventKit` mit den geschriebenen Zeitpunkten; „Standard verwenden“ → `removeAlarms` (nur die eigenen) + Override löschen. Wiederholende lokale Aufgabe → `confirmationDialog` „Nur diese“ / „Alle folgenden“ (an der `Form`, nicht an der Section). Wiederholende Apple-Erinnerung → Fußtext „Gilt für alle Wiederholungen.“
- [ ] Erinnerungen werden mit dem Rest der Aufgabe gespeichert; schlägt das Schreiben der Alarme fehl, bleibt die Aufgabe gespeichert und der Fehlertext erscheint wie bei anderen Schreibfehlern.
- [ ] Nach dem Speichern `notifications.scheduleSoon()`.
- [ ] Tests: `save_githubTask_storesTagwerkOverride`, `save_reminder_writesAlarmsAndMarksEventKit`, `useDefault_onReminder_removesOnlyOwnAlarms`, `recurringLocal_onlyThis_bindsToCurrentDue`, `noDue_hidesReminders`.
- [ ] Commit `feat: edit reminders of a task`.

## Task 10: Termine und Deadlines (App)

**Files:** Modify `app/Tagwerk/Planning/EventEditSheet.swift`, `PlanningModel.swift` (Durchreichen von `alarms`), `EntrySheet.swift` (minimal); Create `app/Tagwerk/Reminders/DeadlineReminderSheet.swift`; Tests `PlanningModelTests.swift` (Ergänzung), `DeadlineReminderTests.swift`.

- [ ] `EventEditSheet`: Abschnitt „Erinnerungen“ vor „Weitere Optionen …“. Bestehender Termin: Liste aus `CalendarStore.alarms(ofEvent:)`; neuer Termin: Standard „Termine“ vorbelegt (A3). Speichern setzt `draft.alarms`; die vorhandene Serienabfrage gilt mit. Fußtext: „iOS meldet diese Erinnerungen selbst, auch in Apple Kalender. Ruhezeiten gelten dafür nicht.“
- [ ] `EntrySheet`, Deadline-Abschnitt (`deadlineSection`): eine Zeile „Erinnerungen“ mit `ReminderText.summary` und Chevron; das Blatt `DeadlineReminderSheet` wird im Helfer `eventPresentations` an die `Form` gehängt (keine Section-Modifier). Nichts anderes im `EntrySheet` ändern.
- [ ] `DeadlineReminderSheet`: `ReminderListEditor` mit Standard „Deadlines“; bei `event.isRecurring` beim Sichern Abfrage „Nur diese Deadline“ / „Diese und alle folgenden“ → Override `occurrence` bzw. `seriesFrom(day)`.
- [ ] Tests: `newEvent_prefillsEventDefaults`, `updateEvent_passesAlarmsWithSpan`, `deadlineOverride_onlyThis_storesOccurrenceScope`, `deadlineOverride_allFollowing_storesSeriesFromDay`.
- [ ] Commit `feat: edit reminders of events and deadlines`.

## Task 11: Einstellungen „Standard-Erinnerungen“ (App)

**Files:** Modify `app/Tagwerk/Settings/SettingsView.swift`; Create `app/Tagwerk/Settings/ReminderDefaultsView.swift`; Test `ReminderDefaultsViewModelTests.swift` (falls ein Modell nötig ist).

- [ ] Im Abschnitt „Benachrichtigungen“ ersetzt eine Zeile „Standard-Erinnerungen ›“ (Wert: Kurzform für Aufgaben) den Stepper „Vorlauf“. Schalter je Quelle, „Deadline-Termine“ und „Ruhezeiten“ bleiben.
- [ ] `ReminderDefaultsView`: Abschnitte „Aufgaben“, „Deadlines“, „Termine“, je mit „Mit Uhrzeit“ und „Ohne Uhrzeit“ bzw. „Ganztägig“ (je ein `ReminderListEditor`). Fußtexte: Aufgaben „Gilt für alle Aufgaben ohne eigene Erinnerungen.“; Termine „Wird beim Anlegen eines Termins in Tagwerk übernommen. Bestehende Termine bleiben unverändert.“
- [ ] Schreiben in `settings.reminderDefaultsData`; erster Aufruf zeigt die migrierten Werte (A6).
- [ ] Footer des Abschnitts „Benachrichtigungen“ (`notificationFooter`) anpassen, falls er den Vorlauf nennt.
- [ ] Commit `feat: add default reminder settings`.

## Task 12: Texte, Gesamttest, Sichtprüfung, Doku

- [ ] `scripts/sync-strings.sh`, englische Übersetzungen ergänzen, `scripts/check-strings.py` und `scripts/find-unlocalized.py` ohne Befund.
- [ ] `app/test-all.sh` grün (eigener Simulator der Arbeitskopie über `scripts/test-env.sh`).
- [ ] Sichtprüfung im Simulator mit `-TagwerkDemoData`: Aufgaben-Editor (GitHub-, lokale, Apple-Erinnerung), Termin bearbeiten, Deadline-Blatt, Einstellungen; Screenshots für die Prüfung beilegen. Ausstehende Mitteilungen über einen Debug-Log (nur Kennung und Zeit, kein Titel) prüfen.
- [ ] Status-Nachtrag in diesem Plan (was gebaut, was ungeprüft, bekannte Grenzen: EventKit-Alarme ohne Ruhezeiten, Zeitumstellung bei Serien-Alarmen, keine Einzel-Abweichung bei wiederholenden Apple-Erinnerungen).
- [ ] Commit `docs: record the state of flexible reminders`.

---

## Designpunkte für #188

- Aufbau des Abschnitts „Erinnerungen“ im Aufgaben-Editor: Lage (nach Fälligkeit oder eigener Bereich), Darstellung „Standard“ vs. „eigene Liste“ (Schalter, graue Liste, Marke).
- Picker für einen Zeitpunkt: Segment „Vorher“ / „Zu einer Uhrzeit“ vs. Rad-Picker wie in Apple Kalender; welche Schnellauswahl-Werte.
- Kurzform in Zeilen und Übersicht („2 Wochen vorher + 2 weitere“ vs. Glocken-Symbol mit Zahl); soll die Aufgabenzeile in der Liste ein Erinnerungs-Symbol zeigen?
- Deadline-Termine: Erinnerungen als Zeile im Deadline-Abschnitt oder eigener Abschnitt; Unterscheidung „Tagwerk-Erinnerung“ (Deadline) vs. „Apple-Hinweis“ (Termin-Alarm), wenn beides an einem Termin hängt.
- Hinweis, dass Ruhezeiten für Termin- und Erinnerungs-Alarme von iOS nicht gelten: Wortlaut und Ort.
- Einstellungsseite „Standard-Erinnerungen“: Gliederung nach Art × mit/ohne Uhrzeit; ob der Vorlauf-Stepper als Kurzweg erhalten bleibt.
- Serienabfrage bei Deadlines und lokalen Aufgaben: Wortlaut („Nur diese Deadline“ / „Diese und alle folgenden“).
- Ob neue Aufgaben im Blatt „Neue Aufgabe“ schon Erinnerungen wählen können (heute bewusst nicht, A10).

## Gerätetests

1. Migration: Installation über den Stand vor P4; ohne Änderung kommen Aufgaben- und Deadline-Mitteilungen zu denselben Zeiten wie vorher; alte Kennungen sind ersetzt (keine Doppelmeldung).
2. GitHub-Issue mit drei Erinnerungen (1 Woche, 1 Tag, 1 Stunde vorher): alle drei kommen; Tippen öffnet die Aufgabe.
3. Apple-Erinnerung: eigene Liste speichern → Alarme in der Erinnerungen-App sichtbar, keine zusätzliche Tagwerk-Mitteilung; „Standard verwenden“ → Tagwerk-Alarme weg, selbst in der Erinnerungen-App angelegte bleiben.
4. Kalendertermin: Erinnerung „1 Tag vorher um 18:00“ → in Apple Kalender sichtbar und meldet sich; Serie mit „Nur diesen Termin“ und „Diesen und alle folgenden“.
5. Ganztägige Deadline mit „2 Tage vorher um 18:00“ und Serien-Deadline mit „Nur diese“.
6. Ruhezeiten aktiv: Tagwerk-Erinnerung in der Ruhezeit kommt am Ende („war fällig …“), mehrere davon nur einmal je Eintrag; Termin-Alarm kommt trotzdem (bekannte Grenze).
7. Budget: > 50 Mitteilungen (Demo mit vielen Aufgaben × 3 Erinnerungen); nach einigen Stunden/Tagen werden spätere nachgefüllt (Hintergrund-Refresh und Öffnen der App). Routine-Mitteilungen bleiben vollständig.
8. Zeitumstellung (Simulator-Zeitzone oder echtes Datum Ende März/Oktober): `.at`-Erinnerung zur richtigen Ortszeit.
9. Sicherung und Wiederherstellung enthalten Standards und Abweichungen.
