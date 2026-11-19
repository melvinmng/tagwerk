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
