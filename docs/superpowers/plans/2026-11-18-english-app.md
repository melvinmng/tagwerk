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

Fables Review vom 2026-11-18 (Urteil „überarbeiten“) ist eingearbeitet; die Nummern verweisen darauf.

1. **String Catalogs, Deutsch bleibt Quellsprache.**
   - Je Ziel ein `Localizable.xcstrings`: App, Widget, und je Paket mit Nutzertexten (TagwerkCore, AIKit, RemindersKit, GitHubKit, HealthBridge) als Paket-Ressource mit `defaultLocalization: "de"` und `Bundle.module`.
   - Schlüssel ist der deutsche Text. Reine SwiftUI-Literale (`Text("…")`, `Button("…")`, `Label("…", systemImage:)`, `Toggle`, `Picker`, `Section`-Header, `.navigationTitle`) sind schon `LocalizedStringKey`.
   - **Codeänderungen sind trotzdem nötig** (Fable 6):
     - `Text(variable)` mit `String` (138 Stellen).
     - `String`-Parameter von Hilfs-Views (`SourceSelectionView(title:)`, `quickButton(title:)`, `Row`, `ActionCard`) werden `LocalizedStringResource`.
     - 84 Interpolationen, darunter aus Fragmenten gebaute Sätze (`"\(actionName(scope)) planen"`, `"zuletzt \(…)"`, `germanName`), werden ganze Sätze je Fall.
     - Handgebaute Plural-Zweige (`WidgetSnapshot.overviewText`, `WeekReviewView`) werden Catalog-Plurale.
2. **Texte als `String`** (Rückgabewerte, Fehlermeldungen, Modelltexte, Benachrichtigungen) werden zu `String(localized: "…", bundle: …, comment: …)`. Bei Interpolation ersetzt Xcode die Werte durch Platzhalter; Plural über die Catalog-Varianten statt eigener `count == 1`-Zweige, wo es solche gibt.
3. **Sprache und Formate über `Locale.current`.** Das trägt die App-Sprache schon (Fable 11).
   - Feste `de_DE`-Formate werden zu `Locale.current`.
   - In Paketen wird die Locale injiziert (Parameter mit Vorgabe `.current`), nicht aus `Bundle.main` gelesen.
   - Für die KI und das Vorlesen gibt es `VoiceLanguage.app` (die App-Sprache als de/en, Vorgabe de).
4. **Was deutsch bleibt:**
   - Anweisungen an ChatGPT und Funktionsbeschreibungen: modellseitig, nicht sichtbar. Ausnahme: Die Antwortsprache wird gesetzt.
     - Planen (`AIPlanner`): Begründungen in der App-Sprache.
     - Chat: Sprache der letzten Nachricht wie bisher; ohne Nachricht die App-Sprache.
   - Fehlertexte der App-Funktionen an das Modell (`{"error":…}`) gehen an das Modell. Die Karten zeigen sie aber an (`ActionCardView.error`), deshalb werden sie lokalisiert.
5. **Sprach-Ansagen** (`ActionAnnouncement`, `SpokenText`, Sprechmodus) richten sich nach der gesprochenen Sprache. Damit keine gemischten Sätze entstehen, bekommt `AssistantModel.describe` einen Sprachparameter (Fable 7):
   - Karten auf dem Bildschirm: App-Sprache.
   - Ansage: Sprache der Antwort.
   - Die `fallback: .german` in `AssistantModel` werden `VoiceLanguage.app`.
6. **Siri/Kurzbefehle:**
   - Titel und Parameter über den App-Catalog (`LocalizedStringResource`).
   - Phrasen über `AppShortcuts.xcstrings` mit englischen Phrasen. Jede Phrase enthält `\(.applicationName)`.
7. **Info.plist:** Usage-Descriptions über `InfoPlist.xcstrings` (App und Widget). Die deutschen Texte bleiben im `project.yml` als Quelle.
8. **Geschriebene Daten** (Titel von Zeitblöcken, Mittagspause, Plan-Kalender „Tagwerk“, Benachrichtigungen) entstehen in der App-Sprache zum Zeitpunkt des Schreibens. Bestehende Einträge werden nicht umbenannt.
   - **Benachrichtigungen:** Die App merkt sich die Sprache, in der zuletzt geplant wurde. Weicht sie beim Start ab, werden alle Benachrichtigungen neu geplant, auch die nicht geladener Quellen (`kept`) (Fable 10).
   - **Sichtbare und gespeicherte KI-Daten** (Titel und Mengen aus `MealEstimator`, Begründungen aus `AIPlanner`) entstehen in der App-Sprache (Fable 8).
10. **Ausgenommen von der Übersetzung:** Diagnose- und Spike-Seiten (`VoiceDiagnostics`, `RecognitionSpikeView`, `ConversationSpikeView`, `PlanningDiagnostics`) bleiben deutsch. Sie sind Entwickler-Werkzeuge; der Catalog markiert ihre Texte mit `shouldTranslate: false`.
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

### Task 0: Spike (zuerst, Fable 1, 3, 12)
Klärt am Gerüst mit einem einzigen Text je Ziel:
- `xcrun xcstringstool sync <catalog> --stringsdata <…>` aus den `.stringsdata` eines `xcodebuild`-Laufs. `xcstringstool` ist in Xcode 27.2 vorhanden (geprüft); `-exportLocalizations` bleibt Rückfall.
- XcodeGen: `en` in `knownRegions`, Kataloge als Ressource der App und des Widgets, Pakete mit `resources: [.process("Resources")]` und `defaultLocalization: "de"`.
- Englischer Stichprobentest mit injizierter Sprache: `String(localized: LocalizedStringResource(key, locale: Locale(identifier: "en"), bundle: …))` oder über das `en.lproj`-Bundle; das Ergebnis legt die Testhilfe `localized(_:in:)` fest.

Ergebnis kommt in diesen Plan, bevor Task 1 beginnt.

### Task 1: Gerüst, Testsprache, Sync-Skript, Prüfung der Abdeckung
- **Kataloge anlegen:**
  - App: `Localizable.xcstrings`, `InfoPlist.xcstrings`, `AppShortcuts.xcstrings`.
  - Widget: `Localizable.xcstrings`, `InfoPlist.xcstrings`.
  - Pakete mit Nutzertexten: `Resources/Localizable.xcstrings`.
- **Testsprache für alle Stufen** (Fable 4): `run_tests` in `test-all.sh` bekommt `-testLanguage de -testRegion DE`. Das XcodeGen-App-Schema bekommt zusätzlich `language: de`, `region: DE`.
- **`scripts/sync-strings.sh`:**
  - Baut einmal mit `SWIFT_EMIT_LOC_STRINGS=YES` und synchronisiert jeden Catalog mit den `.stringsdata` seines Ziels.
  - `--check`: synchronisiert auf eine Kopie und scheitert, wenn sie vom eingecheckten Catalog abweicht. So bleiben keine nie extrahierten Texte unsichtbar (Fable 2).
- **`scripts/check-strings.py`** (Host-Skript, nicht im Simulator), aufgerufen von `test-all.sh` als eigene Stufe:
  - Jeder Schlüssel mit `shouldTranslate != false` hat einen englischen Wert im Zustand `translated`.
  - Platzhalter in beiden Sprachen gleich.
  - Englisch ≠ Deutsch nur prüfen, nachdem die Platzhalter entfernt sind, und nur für Texte mit Buchstaben. Gleich lautende Wörter („Yoga“, „HIIT“, „Deadline“) werden im Catalog als `translated` mit gleichem Wert geführt, nicht über eine Allowlist.
  - `InfoPlist.xcstrings` hat Plist-Schlüssel und eine eigene Regel: jeder Usage-Key braucht de und en.
  - `AppShortcuts.xcstrings`: Jede Phrase enthält `${applicationName}`.
- Danach läuft `sync-strings.sh --check` als Stufe in `test-all.sh`.

### Task 2: Sprachparameter und `VoiceLanguage.app` (Fable 3, 7, 11)
- `VoiceLanguage.app` aus `Locale.current`.
- `AssistantModel.describe(_:language:)`, Ansagen mit Kartentext in der Sprache der Antwort.
- Pakete: Locale-Parameter statt fester `de_DE`.
- **Tests:** deutsch und englisch, englisch über die Testhilfe aus Task 0.

### Task 3: Texte als `String` und Hilfs-Views umstellen (mit Fable 6)
- `String(localized:comment:)` (in Paketen `bundle: .module`).
- `LocalizedStringResource`-Parameter in Hilfs-Views. `Text(variable)` geht über `Text(LocalizedStringResource)` oder bleibt bewusst unübersetzt (Nutzerdaten wie Aufgabentitel).
- Fragment-Sätze werden ganze Sätze, Plural-Zweige werden Catalog-Plurale.
- **Fundliste:**
  - grep auf deutsche Literale, nicht nur mit Umlaut: alle `"…"` mit einem Großbuchstaben am Wortanfang außerhalb von Bezeichnern.
  - Plus `sync-strings.sh`: was im Catalog fehlt, fällt in den englischen Screenshots auf.
- Betroffen u. a.:
  - `userMessage` in AIKit, `TaskListModel.message`.
  - `VoiceNoticeRow.text`, `LanguagePackState.label`, `CapacityText`.
  - `AssistantModel.describe`, `ActionCardView`-Fehler, Fehler der App-Funktionen.
  - Benachrichtigungen, Widget-Texte, `SnapshotProvider`-Platzhalter.
  - Intents: `IntentDialog` aus `LocalizedStringResource` statt `stringLiteral` (Fable 9).
  - `DemoData` vergleicht `title == "Einkaufen"` (Fable 13).

### Task 4: Formate (mit Fable 5)
- `de_DE` ersetzen.
- **Handgebaute Formate:**
  - Wochentags-Arrays (`NotificationTexts`, `WeekReviewView`, `MonthView`, `PlanningSettingsSection`) werden zu `Calendar.shortWeekdaySymbols`/`.formatted`.
  - „heute/morgen“ und `%02d.%02d.` (`DueText`, `SuggestionFacts`, `CaptureText`, `DayHeader`) werden lokalisierte Texte und Datumsformate.
  - „Uhr“/„um“ werden lokalisierte Sätze.
- `EstimateHours`/`IntakeFormat`: Dezimaltrennzeichen nach Locale, Eingabe nimmt Komma und Punkt an (`MealSheet`).
- **Tests:** deutsche und englische Formate.

### Task 5: Übersetzen
- `sync-strings.sh`, dann englische Werte nach Glossar per Skript in die Kataloge, mit Durchsicht.
- Plurale.
- `AppShortcuts.xcstrings` von Hand: Schlüssel exakt mit `${applicationName}`/`${activity}`, englische `caseDisplayRepresentations` für den Parameter (Fable 9).
- **Abnahme:** `check-strings.py` grün, keine Warnungen des App-Intents-Prozessors.

### Task 6: KI-Sprache und geschriebene Daten (mit Fable 8, 10)
- **KI:**
  - `AIPlanner`: „auf Deutsch“ wird App-Sprache.
  - `MealEstimator`: Titel und Mengen in App-Sprache.
  - Chat ohne Nutzernachricht: App-Sprache.
- **Geschriebene Daten:** Titel geschriebener Einträge in App-Sprache.
- **Benachrichtigungen:** neu planen bei Sprachwechsel.
- **Tests:** Anweisungen enthalten die Sprache; ein Sprachwechsel plant neu.

### Task 7: Prüfung
- `test-all.sh` (inkl. Sync-Check und Catalog-Prüfung).
- **Simulator Englisch** (`-AppleLanguages (en) -AppleLocale en_US`) über die Geräte-Tools: Screenshots aller Tabs, Einstellungen, Chat, Sprechmodus-Blatt, Widget, Benachrichtigungstext.
- **Simulator Deutsch:** Stichprobe.
- Danach Fable-Review des Diffs, iPhone, PR.

Reihenfolge: 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7.

## Risiken
- **Vergessene `String`-Texte bleiben deutsch.** Abhilfe: die grep-Liste aus Task 2 und eine Durchsicht der englischen Screenshots.
- **Englische Texte sind oft kürzer, Plural ist anders.** Abhilfe: Varianten im Catalog.
- **Catalog-Sync ohne IDE:** wird in Task 0 geklärt.
- **Tests mit deutschen Erwartungen** (32 Testdateien) brechen ohne feste Testsprache. Deshalb steht `-testLanguage de` in Task 1 vor jeder Übersetzung.
