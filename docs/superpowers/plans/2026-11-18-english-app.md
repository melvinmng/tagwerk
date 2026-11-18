# Tagwerk auf Englisch – Plan

**Ziel:** Die App erscheint auf Englisch, wenn das iPhone auf Englisch steht, sonst auf Deutsch. Das ist die Entscheidung des Nutzers vom 2026-11-18 (eigener PR, Sprache folgt dem iPhone). Die Sprache der KI-Antworten folgt weiter der Sprache, in der der Nutzer schreibt oder spricht (Plan voice-chat, Entscheidung 4).

**Ausgangslage (Bestand, 2026-11-18):**
- `developmentLanguage: de`; keine `.xcstrings`/`.lproj`.
- Etwa 480 deutsche Literale mit Umlaut, insgesamt geschätzt 1 200–1 500 Texte:
  - App: 422 mit Umlaut, rund 210 `Text("…")`, 190 `Button("…")`, 80 `Label("…")`.
  - Widget: 9. TagwerkCore: 41. Kleinere Pakete: 12.
- Feste deutsche Formate: `Locale(identifier: "de_DE")` in `CaptureView`, `TaskListModel`, `EstimateHours`, `WeekReview`, `IntakeFormat` (3×), `SnapshotProvider`, `WidgetViews`.
- App Intents mit `LocalizedStringResource`-Titeln und Siri-Phrasen auf Deutsch.
- Benachrichtigungstexte als `String`.
- Usage-Descriptions im `project.yml`.

## Entscheidungen

1. **String Catalogs, Deutsch bleibt Quellsprache.**
   - Je Ziel ein `Localizable.xcstrings`: App, Widget, und je Paket mit Nutzertexten (TagwerkCore, AIKit, RemindersKit, GitHubKit, HealthBridge) als Paket-Ressource mit `defaultLocalization: "de"` und `Bundle.module`.
   - Schlüssel ist der deutsche Text. SwiftUI-Literale (`Text("…")`, `Button("…")`, `Label("…", systemImage:)`, `Toggle`, `Picker`, `Section`-Header, `.navigationTitle`) sind schon `LocalizedStringKey` und brauchen keine Codeänderung.
2. **Texte als `String`** (Rückgabewerte, Fehlermeldungen, Modelltexte, Benachrichtigungen) werden zu `String(localized: "…", bundle: …, comment: …)`. Bei Interpolation ersetzt Xcode die Werte durch Platzhalter; Plural über die Catalog-Varianten statt eigener `count == 1`-Zweige, wo es solche gibt.
3. **Sprache = Sprache der App** (`Bundle.main.preferredLocalizations.first`), nicht `Locale.current`.
   - Feste `de_DE`-Formate werden zu `Locale.autoupdatingCurrent`, mit der App-Sprache als Sprachteil.
   - Wo Tests ein festes Format brauchen, wird die Locale injiziert.
4. **Was deutsch bleibt:**
   - Anweisungen an ChatGPT und Funktionsbeschreibungen: modellseitig, nicht sichtbar. Ausnahme: Die Antwortsprache wird gesetzt.
     - Planen (`AIPlanner`): Begründungen in der App-Sprache.
     - Chat: Sprache der letzten Nachricht wie bisher; ohne Nachricht die App-Sprache.
   - Fehlertexte der App-Funktionen an das Modell (`{"error":…}`) gehen an das Modell. Die Karten zeigen sie aber an (`ActionCardView.error`), deshalb werden sie lokalisiert.
5. **Sprach-Ansagen** (`ActionAnnouncement`, `SpokenText`, Sprechmodus): richten sich schon nach der gesprochenen Sprache und bleiben so.
6. **Siri/Kurzbefehle:**
   - Titel und Parameter über den App-Catalog (`LocalizedStringResource`).
   - Phrasen über `AppShortcuts.xcstrings` mit englischen Phrasen. Jede Phrase enthält `\(.applicationName)`.
7. **Info.plist:** Usage-Descriptions über `InfoPlist.xcstrings` (App und Widget). Die deutschen Texte bleiben im `project.yml` als Quelle.
8. **Geschriebene Daten** (Titel von Zeitblöcken, Mittagspause, Plan-Kalender „Tagwerk“, Benachrichtigungen) entstehen in der App-Sprache zum Zeitpunkt des Schreibens. Bestehende Einträge werden nicht umbenannt.
9. **Begriffe (Glossar)** für eine einheitliche Übersetzung:

   | Deutsch | Englisch |
   |---|---|
   | Planen | Plan |
   | Aufgaben | Tasks |
   | Erfassen | Log |
   | Einstellungen | Settings |
   | Zeitblock | Time block |
   | Fälligkeit / fällig | Due date / due |
   | Aufwand | Effort |
   | Vorschlag | Suggestion |
   | Aktionskarte | Action card |
   | Bestätigen / Verwerfen | Confirm / Discard |
   | Sprechmodus | Voice mode |
   | Vorlesen | Read aloud |
   | Diktat | Dictation |
   | Wochenrückblick | Weekly review |
   | Arbeitszeit | Working hours |
   | Mittagspause | Lunch break |
   | Ungeplant | Unplanned |
   | Erledigt | Done |

   Die Anrede bleibt informell: „du“ wird zu „you“.

## Tasks

### Task 1: Gerüst und Tests
- **Kataloge anlegen:**
  - App: `Localizable.xcstrings`, `InfoPlist.xcstrings`, `AppShortcuts.xcstrings`.
  - Widget: `Localizable.xcstrings`, `InfoPlist.xcstrings`.
  - Pakete: `Resources/Localizable.xcstrings`, `defaultLocalization: "de"`.
- **Build-Einstellungen:**
  - `project.yml`: Bekannte Regionen de und en. `SWIFT_EMIT_LOC_STRINGS: YES` und `LOCALIZATION_PREFERS_STRING_CATALOGS: YES`, damit der Build die Schlüssel in den Catalog schreibt.
- **Test-Schema:**
  - Tests laufen fest mit `language: de` und `region: DE`, damit bestehende deutsche Erwartungen gelten.
  - Neue englische Tests setzen die Locale ausdrücklich.
- **Test `LocalizationCoverageTests`:**
  - Liest alle `.xcstrings` und prüft: jeder Schlüssel hat einen englischen Wert, kein englischer Wert ist leer oder gleich dem deutschen Schlüssel.
  - Ausnahmen: Eigennamen und Zeichenfolgen ohne Buchstaben, in einer Allowlist.
  - Prüft außerdem, dass Platzhalter (`%@`, `%lld`) in beiden Sprachen übereinstimmen.

### Task 2: Texte als `String` umstellen
- Fundstellen per `grep` auf deutsche Literale außerhalb von SwiftUI-Initialisierern; Liste im PR.
- Umstellen auf `String(localized:)` mit `comment`, in Paketen mit `bundle: .module`.
- Betroffen u. a.:
  - `userMessage` in AIKit.
  - `TaskListModel.message`.
  - Notice-Texte (`VoiceNoticeRow.text`), Labels (`LanguagePackState.label`, Picker-Titel), `CapacityText`.
  - Karten-Texte (`AssistantModel.describe`), `ActionCardView`-Fehler.
  - Benachrichtigungen.
  - Widget-Texte.
  - Fehler der App-Funktionen.
- **Tests:** Für jede umgestellte Datei läuft der bestehende Test weiter, weil das Testschema deutsch ist. Dazu je Bereich ein englischer Stichprobentest mit `Locale(identifier: "en")`, der eine übersetzte Zeichenfolge erwartet.

### Task 3: Formate
- `de_DE` ersetzen, Datums- und Zahlenformate über `.formatted` mit App-Locale.
- `EstimateHours` und `IntakeFormat`: Dezimaltrennzeichen nach Locale. Eingabe-Parsing nimmt Komma und Punkt an.
- **Tests:** deutsche und englische Formate.

### Task 4: Übersetzen
- Build schreibt alle Schlüssel in die Kataloge.
- Englische Werte nach dem Glossar eintragen, per Skript in die JSON-Kataloge, mit Durchsicht.
- Plural- und Gerätevarianten, wo nötig.
- `LocalizationCoverageTests` muss grün sein.

### Task 5: Antwortsprache der KI und geschriebene Daten
- `AIPlanner`: Antwortsprache = App-Sprache.
- `AssistantModel.instructions`: ohne Nutzernachricht in der App-Sprache antworten.
- Titel geschriebener Einträge in der App-Sprache.
- **Tests:** Anweisungen enthalten die Sprache.

### Task 6: Prüfung
- `test-all.sh`.
- Simulator in Englisch (Launch-Argumente `-AppleLanguages (en) -AppleLocale en_US`) über die Geräte-Tools:
  - Screenshots aller Tabs, der Einstellungen, des Chats und des Sprechmodus-Blatts.
  - Abgeschnittene Texte prüfen.
- Simulator in Deutsch: Stichprobe, dass sich nichts geändert hat.
- Danach Fable-Review des Diffs, iPhone-Installation, PR.

## Risiken
- **Vergessene `String`-Texte bleiben deutsch.** Abhilfe: die grep-Liste aus Task 2 und eine Durchsicht der englischen Screenshots.
- **Englische Texte sind oft kürzer, Plural ist anders.** Abhilfe: Varianten im Catalog.
- **`xcodebuild` und Catalog-Sync:** Schreibt der Build ohne Xcode-IDE die Schlüssel nicht, werden sie mit `xcodebuild -exportLocalizations` gesammelt (am Anfang von Task 4 prüfen).
- **Tests mit deutschen Erwartungen** brechen ohne festes Testschema. Deshalb kommt die Sprache des Schemas in Task 1 zuerst.
