# Ruhezeiten für Benachrichtigungen (#169)

**Ziel:** In einer festgelegten Ruhezeit kommen keine Tagwerk-Mitteilungen zu Aufgaben und Deadline-Terminen. Mitteilungen, die in die Ruhezeit fallen, werden auf das Ende der Ruhezeit verschoben, nicht verworfen. Der Beginn kann an die Zielschlafzeit aus Phase 7 gekoppelt werden.

**Rahmen:** Rein technische Umsetzung ohne Mockups. Die Oberfläche folgt den vorhandenen Einstellungen. Keine Änderungen an `TODO.md`, kein `t3gh`.

## Bestand

- Reine Planung: `notificationPlan(tasks:deadlineEvents:rules:now:calendar:locale:)` in `app/Packages/TagwerkCore/Sources/TagwerkCore/NotificationPlan.swift:68`, mit `NotificationRules` (Zeilen 35-63). Feuerzeit für Aufgaben in Zeilen 80-82, für Events in Zeile 104. Sortierung und `prefix(limit)` in Zeile 112. Die Texte richten sich über `dayText(day, fire:)` (Zeilen 150-157) nach der Feuerzeit.
- `NotificationScheduler.performReschedule` (`app/Tagwerk/Notifications/NotificationScheduler.swift:99-158`) baut die Regeln in Zeile 127 und gleicht Feuerzeiten mit ausstehenden Anfragen ab.
- Routine-Erinnerungen (Abend-Checkliste relativ zur Schlafzeit, Tagesstart) sind wiederholende Stunde/Minute-Trigger in `RoutineSchedule.swift:128-152`, geplant über `RoutineNotificationScheduler`.
- Einstellungen: SwiftData-Modell `AppSettings` (`app/Tagwerk/Persistence/AppSettings.swift`). Neue Attribute brauchen einen Standardwert. Zielschlafzeit ist `bedtimeMinutes` (Zeile 88, Standard 1380 = 23:00). Der Abschnitt „Benachrichtigungen“ in `SettingsView.swift:86-98`, der Footer in `notificationFooter` (~155). Beobachtungs-Hash für Neuplanung in `AppEnvironment.startNotificationUpdates` (~558-582).

## Entscheidungen (technische Vorgaben, ins Design-Sammelissue übernommen)

1. **Fenster:** `quietHoursEnabled` (Standard `false`), `quietHoursStartsAtBedtime` (Standard `true`), `quietStartMinutes` (Standard 1380, nur genutzt, wenn nicht an Schlafzeit gekoppelt), `quietEndMinutes` (Standard 420 = 07:00). Das Fenster darf über Mitternacht gehen. Beginn gleich Ende bedeutet „kein Fenster“.
2. **Verschieben:** Eine Feuerzeit im Fenster wird auf das nächste Fensterende gesetzt. Gilt für Aufgaben- und Deadline-Mitteilungen. Mehrere verschobene Mitteilungen behalten ihre Reihenfolge (stabile Sortierung wie bisher nach `(fireDate, id)`). Bei identischer Zeit bleibt die Sortierung nach `id`.
3. **Fällige Zeitpunkte:** Wird eine Mitteilung über den Fälligkeitszeitpunkt hinaus verschoben, nennt der Text das. Zum Beispiel „war fällig um 23:30“ statt „in 2 Std.“. Die Texte entstehen aus der verschobenen Zeit, damit „heute/morgen“ stimmt.
4. **Routine-Erinnerungen** (Abend-Checkliste, Tagesstart) sind ausgenommen. Es sind vom Nutzer bewusst gesetzte Uhrzeiten, und eine Abend-Erinnerung am Morgen wäre sinnlos. Liegt eine davon im Fenster, zeigt die Routine-Einstellung einen Hinweis.
5. **Fokus von iOS:** #169 verlangt die Kopplung an Fokus-Modi. Umsetzung als Fokus-Filter (`SetFocusFilterIntent`, App Intents) im App-Target: In den Fokus-Einstellungen von iOS lässt sich für Tagwerk „Tagwerk-Mitteilungen ruhen lassen“ wählen. `perform()` setzt einen Laufzeitzustand `focusQuietActive` (persistiert, z. B. in `AppSettings`) und plant neu. Solange er aktiv ist, verschiebt `notificationPlan` alle Aufgaben- und Deadline-Mitteilungen bis zum Ende der Ruhezeit oder, ohne Ruhezeit, bis zum Fokus-Ende. Endet der Fokus, ruft iOS `perform()` mit dem Standardwert auf, und Tagwerk plant mit den Originalzeiten neu. **Vorab prüfen:** ob der Fokus-Filter mit Personal Team ohne zusätzliche Berechtigung im App-Target funktioniert (Build, Metadaten im Bundle, Doku). Wenn nicht, den Fokus-Teil weglassen, die Begründung im Plan festhalten und im Footer auf die Fokus-Einstellungen von iOS verweisen.

## Aufgaben

1. Plan nach `docs/superpowers/plans/2026-11-19-quiet-hours.md` legen und committen.
2. **TagwerkCore:** `public struct QuietHours: Equatable, Sendable { startMinutes, endMinutes }` mit
   - `func contains(_ date: Date, calendar: Calendar) -> Bool`
   - `func shifted(_ date: Date, calendar: Calendar) -> Date` (nächstes Fensterende, über Mitternacht korrekt, Sommerzeit-Wechsel über `Calendar` statt Sekunden-Arithmetik).
   - Tests in `NotificationPlanTests.swift` oder einer neuen `QuietHoursTests.swift` (Swift Testing): Fenster am selben Tag, über Mitternacht, Grenzen (Beginn inklusive, Ende exklusive), Sommerzeit-Umstellung (Europe/Berlin, letzter Sonntag im März und Oktober), leeres Fenster.
3. `NotificationRules.quietHours: QuietHours?` mit Standardwert `nil`, damit bestehende Aufrufe weiter kompilieren. Anwenden in `notificationPlan` nach dem Guard `fire >= earliest`, bei Aufgaben und Events, vor der Textbildung. Tests: verschobene Feuerzeit, Text mit „war fällig um“, Reihenfolge und Limit nach dem Verschieben.
4. **App:** Attribute in `AppSettings` mit Standardwerten. Regeln in `NotificationScheduler.performReschedule` füllen, Beginn aus `bedtimeMinutes`, wenn gekoppelt. Felder in den Beobachtungs-Hash aufnehmen (auch `bedtimeMinutes`, falls dort noch nicht enthalten). Scheduler-Test in `app/TagwerkTests/NotificationSchedulerTests.swift` mit `FakeNotificationCenter`.
4b. **Fokus-Filter** nach Entscheidung 5, mit Tests für die Regel (reine Funktion: Fokus aktiv → Verschiebeziel).
5. **Einstellungen:** Im Abschnitt „Benachrichtigungen“ ein Unterpunkt „Ruhezeiten“ (NavigationLink mit Wert „Aus“ oder „23:00–07:00“). Dahinter ein `Form` mit Schalter, „Beginn bei Zielschlafzeit“ (Schalter), sonst `DatePicker` für den Beginn, `DatePicker` für das Ende. Footer: Verschieben statt Verwerfen und der Satz zum Fokus. Das Muster für Minuten↔`Date` ist `RoutineSettingsView.time(_:)` (Zeile 140). Wiederverwenden statt duplizieren.
6. **Hinweis in `RoutineSettingsView`:** Liegt eine Routine-Erinnerung im Ruhefenster, einen Fußtext anzeigen. Das ist eine reine Funktion in TagwerkCore mit Test.
7. Demo-Daten nur ergänzen, wenn `DemoData.swift` Einstellungen setzt.
8. Strings deutsch als Schlüssel mit englischer Übersetzung. Für Texte aus TagwerkCore der Paket-Katalog `app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/Localizable.xcstrings`.
9. `app/test-all.sh` grün.

## Abnahme

- Mit eingeschalteten Ruhezeiten fällt keine Aufgaben- oder Deadline-Mitteilung ins Fenster. Verschobene Mitteilungen erscheinen am Fensterende mit korrektem Text.
- Ausgeschaltet: Verhalten unverändert (bestehende Tests unverändert grün).
- Budget von 50 und Abgleich der ausstehenden Anfragen funktionieren mit verschobenen Zeiten.

## Für das Design-Sammelissue

- Aussehen der Einstellung „Ruhezeiten“ und Wortlaut der verschobenen Mitteilungen.
- Ob Routine-Erinnerungen ausgenommen bleiben.
- Fokus-Filter: Wortlaut und Verhalten (verschieben bis Ruhezeit-Ende oder bis Fokus-Ende).
- Zusammenspiel mit #151 (flexible Erinnerungen), sobald es gebaut wird.

## Stand

Umgesetzt auf dem Branch `feature/quiet-hours` (Stand: 2026-11-19).

### Was gebaut wurde

- **TagwerkCore**
  - `QuietHours` (`QuietHours.swift`): `contains`, `shifted`, `nextEnd(after:)`, `resolved(...)` aus den Einstellungen. Minutenauflösung, Beginn inklusive, Ende exklusiv, Beginn gleich Ende bedeutet kein Fenster. Das Fensterende kommt über `Calendar.nextDate(after:matching:matchingPolicy:.nextTime,repeatedTimePolicy:.first)`, nicht über Sekunden-Arithmetik.
  - `NotificationRules` hat drei neue Felder mit Standardwert `nil` (`quietHours`, `focusHold`, `focusCatchUp`). `notificationPlan` bleibt eine reine Funktion. Die Verschiebung steckt in `NotificationRules.deliveryDate(for:calendar:)`.
  - Texte: „War fällig gestern um 23:30 · Liste“ bzw. „Deadline war heute um 02:00“, wenn die verschobene Feuerzeit hinter dem Fälligkeitsmoment liegt (Aufgaben und Termine mit Uhrzeit: nach der Uhrzeit; ohne Uhrzeit oder ganztägig: ab dem Folgetag). Neu in `dayText`: „gestern“.
  - `FocusQuiet`, `FocusHold`, `FocusCatchUp`: reine Regeln für den Fokus-Filter (Zustandsübergänge, Verschiebeziel, Nachholen).
  - `RoutineSchedule.quietHoursConflict(...)`: reine Funktion für den Hinweis in den Routine-Einstellungen.
- **App**
  - `AppSettings`: `quietHoursEnabled` (aus), `quietHoursStartsAtBedtime` (an), `quietStartMinutes` (1380), `quietEndMinutes` (420) sowie der Laufzeitzustand des Fokus-Filters `focusQuietSince`, `focusQuietCatchUpFrom`, `focusQuietCatchUpAt`.
  - `NotificationScheduler.performReschedule` füllt die Regeln. Der Beobachtungs-Hash in `AppEnvironment.startNotificationUpdates` enthält die Ruhezeit-Felder, `bedtimeMinutes` (stand dort vorher nicht) und `focusQuietSince`.
  - `QuietFocusFilter` (`SetFocusFilterIntent`) und `IntentServices.setFocusQuiet(active:)`.
  - Einstellungen: Zeile „Ruhezeiten“ im Abschnitt „Benachrichtigungen“, Unterseite `QuietHoursSettingsView`, Fußtext in `RoutineSettingsView`. Das Muster Minuten↔`Date` ist als `Binding<Int>.asTime()` in `MinutesBinding.swift` ausgelagert und ersetzt die private Kopie in `RoutineSettingsView`. Die zwei weiteren Kopien in `SettingsView` und `PlanningSettingsSection` bleiben unangetastet (außerhalb des Auftrags).
  - Strings: neue Schlüssel mit englischer Übersetzung in beiden Katalogen.
- **Tests:** `QuietHoursTests` (Fenster, Grenzen, Mitternacht, leeres Fenster, beide Sommerzeit-Umstellungen 29.03. und 25.10.2026 in Europe/Berlin mit Prüfung der verstrichenen Sekunden, Fensterende in der übersprungenen und in der doppelten Stunde, Rasterprüfung über das Jahr 2026), `NotificationPlanQuietHoursTests`, `FocusQuietTests`, `QuietHoursRoutineTests`, `NotificationSchedulerQuietHoursTests` (mit `FakeNotificationCenter`) sowie ein Test in `IntentServicesTests`. Bestehende Tests sind unverändert und grün.

### Abweichungen vom Plan

1. **Verschieben vor dem Guard, nicht danach** (Aufgabe 3). Der Plan nennt „nach dem Guard `fire >= earliest`“. Das würde eine Mitteilung verlieren, die ursprünglich um 23:30 geplant war, wenn um 02:00 neu geplant wird: Die Originalzeit liegt in der Vergangenheit, die Mitteilung fiele aus `wanted`, und `performReschedule` löschte die ausstehende Anfrage für 07:00. Jetzt wird zuerst verschoben, dann gegen `earliest` geprüft. Ohne Ruhezeit ändert das nichts. Abgedeckt durch einen Plan-Test und einen Scheduler-Test (`rescheduleDuringTheNight_keepsTheMovedRequest`).
2. **Fokus-Filter: Halten und Nachholen statt „bis Fokus-Ende“.** iOS meldet nur Beginn und Ende eines Fokus, nie das Ende im Voraus. Deshalb gilt:
   - Solange der Filter aktiv ist, werden Mitteilungen, die ab dem Fokus-Beginn fällig würden, auf das **Ende der laufenden bzw. nächsten Ruhezeit** verschoben (`FocusQuiet.hold`). Ohne Ruhezeit gilt ein **Höchstmaß von 8 Stunden** ab Fokus-Beginn (`openEndedHold`, eine Annahme von mir, nicht aus #169).
   - Mit Ruhezeit und Fokus gleichzeitig werden nur Mitteilungen verschoben, die vor dem Zielende feuern würden. Spätere bleiben unverändert (mit der normalen Ruhezeit-Verschiebung).
   - Endet der Fokus, plant Tagwerk mit den Originalzeiten neu. Was seit dem Fokus-Beginn fällig wurde, feuert **einmal** eine Minute nach dem ersten Lauf (`FocusQuiet.scheduling`, Zeitpunkt wird in `focusQuietCatchUpAt` festgehalten, damit wiederholte Läufe nichts doppelt auslösen). Ohne dieses Nachholen gingen genau diese Mitteilungen verloren, weil ihre Originalzeit dann in der Vergangenheit liegt.
   - Ein Fokus-Beginn, der älter als 24 Stunden ist (Ende nie angekommen), wird verworfen, damit ein verpasster Ende-Aufruf die App nicht dauerhaft stumm schaltet.
3. **`perform()` lädt zuerst die Quellen** (`AppEnvironment.loadTasksInBackground()`), bevor es neu plant. Bei einem Kaltstart im Hintergrund wären sonst alle Quellen nicht geladen und behielten über `kept` ihre unverschobenen Anfragen.
4. Der Fokus-Filter hat keinen eigenen Zustand `focusQuietActive: Bool`, sondern `focusQuietSince: Date?` (aus dem oben genannten Grund).

### Entscheidung 5: Machbarkeit des Fokus-Filters mit Personal Team

- Ergebnis: **eingebaut**. `SetFocusFilterIntent` ist ein gewöhnlicher App Intent im App-Target. Es ist kein Entitlement und keine Capability nötig; `Tagwerk.entitlements` blieb unverändert (nur HealthKit und App Group wie zuvor).
- Geprüft: Das App-Target baut für den Simulator fehlerfrei. Im gebauten Bundle (`Tagwerk.app/Metadata.appintents/extract.actionsdata`) steht `QuietFocusFilter` neben den vorhandenen Intents (`LogWaterIntent` usw., die mit Personal Team bereits laufen).
- **Nicht geprüft** (nur auf dem Gerät möglich): ob der Filter in iOS unter Einstellungen › Fokus › Fokus-Filter › Tagwerk erscheint, ob iOS `perform()` bei Fokus-Beginn und -Ende wirklich aufruft und ob das mit einem Personal-Team-Build klappt. Siehe unten.

### Offen

- Mitteilungen von Quellen, die beim Nachholen nicht geladen waren (z. B. GitHub offline ohne Cache), werden nicht nachgeholt. Ihre bestehenden Anfragen bleiben, wie überall im Scheduler, unverändert.
- Routine-Erinnerungen bleiben ausgenommen (Entscheidung 4). Liegt die Erinnerung „Schlafzeit“ (Abstand 0) bei gekoppeltem Beginn exakt auf dem Fensterbeginn, zeigt die Routine-Einstellung den Hinweis. Das ist beabsichtigt, weil der Beginn inklusive ist.
- Tastaturabbau (`feature/keyboard-dismissal`): zum Zeitpunkt des Merges von `origin/main` war der Branch nicht gemergt (`origin/main` hatte seit dem Fork keine neuen Commits). Die neue Seite „Ruhezeiten“ enthält nur Schalter und `DatePicker`, kein Texteingabefeld; es waren daher keine Modifier anzuwenden.
- Zusammenspiel mit #151 (flexible Erinnerungen) bleibt offen.

### Nur auf dem Gerät prüfbar (Melvin)

1. Einstellungen › Benachrichtigungen › Ruhezeiten: Schalter, Beginn bei Zielschlafzeit, Ende. Wert in der Liste („Aus“ bzw. „23:00–07:00“).
2. Eine Aufgabe mit Fälligkeit um 23:30 anlegen, Ruhezeit 23:00–07:00 einschalten: Mitteilung kommt um 07:00 mit „War fällig gestern um 23:30 …“.
3. Fokus-Filter: In iOS unter Fokus einen Fokus (z. B. „Arbeit“) öffnen, Fokus-Filter › Tagwerk hinzufügen, „Tagwerk-Mitteilungen ruhen lassen“ einschalten. Beim Aktivieren darf keine Mitteilung vor dem Ende der Ruhezeit (bzw. 8 Stunden) kommen; nach dem Beenden kommen die inzwischen fälligen Mitteilungen nach etwa einer Minute.
4. Der Hinweis in Einstellungen › Routinen, wenn eine Routine-Erinnerung in der Ruhezeit liegt.

### Für das Design-Sammelissue

- Wortlaut „War fällig gestern um 23:30“ und „Deadline war …“ für verschobene Mitteilungen.
- Fokus-Filter: Wortlaut, Höchstdauer von 8 Stunden ohne Ruhezeit und das Nachholen nach dem Fokus.
