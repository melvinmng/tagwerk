# Siri-Kurzbefehle reparieren (#178)

**Ziel:** Ursache finden, warum Siri auf dem iPhone keinen Tagwerk-Kurzbefehl erkennt, sondern eine Websuche startet, und sie beheben. Belegen, was am Build überprüfbar ist. Für Melvin eine kurze Checkliste für den Gerätetest erstellen. Siri lässt sich im Simulator nicht prüfen.

**Rahmen:** Keine Änderungen an `TODO.md`, kein `t3gh`. Keine Installation auf dem iPhone. Die macht Melvin.

## Bestand

- `TagwerkShortcuts: AppShortcutsProvider` in `app/Tagwerk/Intents/TagwerkIntents.swift:258-302`: 8 Kurzbefehle mit 24 Sätzen, alle mit `\(.applicationName)`.
- Katalog `app/Tagwerk/AppShortcuts.xcstrings` (Quellsprache de, 24 Schlüssel mit `${applicationName}` usw., alle mit `en`).
- Parameter über `ShoppingArticleEntity` (id = Name), `HabitEntity` und `WorkoutActivityOption`. `updateAppShortcutParameters()` in `TagwerkApp.swift:30` und `AppEnvironment.swift:687/690`.
- Kein `INAlternativeAppNames`, keine Siri-Einträge in `project.yml` oder `Info.plist`. Für App Intents nicht nötig.
- Protokoll und API-Grenzen: `docs/superpowers/2026-11-19-overnight-log.md`, Abschnitt „Siri Einkaufsliste“ (ab Zeile 280).
- Auf dem Gerät betrifft der Fehler mindestens alle Einkaufslisten-Sätze. Ob die Sätze aus Phase 4 („Wasser in Tagwerk erfassen“) funktionieren, ist unbekannt.

## Vorgehen

1. Plan nach `docs/superpowers/plans/2026-11-19-siri-shortcuts-fix.md` legen und committen.
2. **Build-Belege sammeln.** Gerätebuild ohne Installation wie in `scripts/install-dev.sh`, aber mit `-destination 'generic/platform=iOS'` und ohne Signierung (`CODE_SIGNING_ALLOWED=NO`), dazu ein Simulator-Build. Im erzeugten `Tagwerk.app` prüfen:
   - Gibt es `Metadata.appintents/` mit `extract.actionsdata`, und sind dort alle 8 Kurzbefehle mit ihren Sätzen enthalten?
   - Liegen die Sätze lokalisiert vor (`de.lproj/AppShortcuts.strings` oder das kompilierte Gegenstück aus dem `.xcstrings`)? Ist `AppShortcuts.xcstrings` überhaupt Ressource des App-Targets (`app/project.yml`)?
   - Meldet das Build-Log Warnungen von `appintentsmetadataprocessor` (z. B. ungültige Sätze, fehlende Übersetzung, zu viele Sätze, Satz ohne Parameter-Werte)?
   - Ergebnis jeweils mit Pfad und Auszug im Plan festhalten.
3. **Sätze prüfen und bereinigen.** Doppeldeutige oder sich überdeckende Sätze entfernen (z. B. „Einkaufsliste in Tagwerk“ neben „Einkaufsliste in Tagwerk zeigen“) und Sätze vermeiden, die Siri als allgemeine Anfrage deutet. Eher wenige, eindeutige Sätze je Kurzbefehl. Die Zahl der Sätze je Kurzbefehl begründen. Katalog und `CaptureSettingsView.swift:49-64` (angezeigte Satzliste) synchron halten.
4. **App-Name.** `INAlternativeAppNames` in den Info-Einstellungen über `project.yml` ergänzen (z. B. „Tag Werk“), mit Aussprache-Hinweis, falls sinnvoll. Vorher an Apples Dokumentation prüfen, ob App Shortcuts diese Namen nutzen, und das Ergebnis im Plan festhalten.
5. **Prüfhilfe in der App.** In „Siri & Kurzbefehle“ (`CaptureSettingsView`) einen `ShortcutsLink()` ergänzen, der die Tagwerk-Kurzbefehle in der App „Kurzbefehle“ öffnet. Optional einen `SiriTipView` für den wichtigsten Satz. So sieht Melvin sofort, ob die Kurzbefehle registriert sind.
6. **Weitere Ursachen, die nur am Gerät klärbar sind**, als Checkliste im Plan:
   - Erscheinen die Tagwerk-Kurzbefehle in der App „Kurzbefehle“, und laufen sie dort per Tipp?
   - Funktionieren die Sätze aus Phase 4 per Siri?
   - Einstellungen → Siri → Apps → Tagwerk: „Von dieser App lernen“ und „Bei Siri verwenden“ aktiv?
   - Siri-Sprache Deutsch, iPhone-Sprache Deutsch?
   - Nach einer Neuinstallation über `install-dev.sh` einmal die App öffnen, dann 1–2 Minuten warten.
   - Gilt die Einschränkung auch nach einem Neustart des iPhones?
7. Tests: Wo sinnvoll, Unit-Tests für die Satzliste. Zum Beispiel muss jeder Satz `${applicationName}` enthalten, und jeder Satz im Code muss einen Katalogschlüssel mit `en` haben. Ein solcher Test existiert eventuell schon in `scripts/check-strings.py`, dann nicht doppeln.
8. `app/test-all.sh` grün.

## Abnahme

- Belegte Diagnose im Plan. Entweder eine gefundene Ursache im Build mit Behebung, oder der Nachweis, dass der Build korrekt ist, sodass die Ursache am Gerät oder in der Siri-Konfiguration liegt.
- Bereinigte Sätze, `ShortcutsLink` in den Einstellungen, Gerätetest-Checkliste.
- Ehrlich kennzeichnen, was nur am Gerät bestätigt werden kann.

## Für das Design-Sammelissue

- Platzierung und Aussehen von `ShortcutsLink` und `SiriTipView`.
