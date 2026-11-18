# Schritte und Trainingszeit in „Erfassen“ (ST1) – Implementation Plan

> **Status:** Entwurf. ST1 ist die Empfehlung (vorläufig, freigegeben 18.11.2026). Vor der Umsetzung sind die offenen Entscheidungen am Ende zu klären.

**Goal:** „Erfassen“ zeigt die Schritte des gezeigten Tages aus Health. Statt der Zahl der Trainings der Woche steht die Trainingszeit: in der Tagesübersicht die Minuten der Woche gegen ein Wochenziel in Minuten, im Abschnittskopf „Training“ die Minuten des Tages. Wochenrückblick und Einstellungen ziehen mit.

**Mockup:** `docs/superpowers/mockups/2026-11-18-steps-training-time-mockups.html` (ST0 Ist-Zustand, ST1 Empfehlung, ST2 und ST3 Alternativen).

**Baut auf:** `docs/superpowers/specs/2026-11-18-phase-3-design.md` (§4.2 Health, §5 Regeln, §8), `docs/superpowers/specs/2026-11-18-phase-4-design.md` (Anti-Ziele, §5.6 Wochenrückblick, Entscheidung 14).

**Tech Stack:** Swift 6, SwiftUI (iOS 27), HealthKit, SwiftData, Swift Testing.

**Nicht in diesem Plan:** Schritte im Widget, im Kopf von „Planen“ oder in Siri; Schritte von Hand eintragen; Distanz, Etagen, aktive Energie; Schritte oder Trainingszeit für den Assistenten.

**Belegstand:** Die Aussagen zum Ist-Zustand stammen aus dem Quelltext. Die Aussagen zum Verhalten von HealthKit (erneute Anfrage bei neuem Lesetyp, Zusammenführen von iPhone und Apple Watch in der Statistik, nicht erkennbare Leseablehnung) stammen aus API-Kenntnis und sind am Gerät nicht geprüft. Breiten und Höhen im Mockup sind Rechnungen.

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `app/Tagwerk/Capture/CaptureView.swift:326–329` | Kachel „Training“: `model.weekCount` gegen `settings.goalWorkoutsPerWeek`; bei Ziel 0 ausgeblendet. |
| `app/Tagwerk/Capture/CaptureModel.swift:44`, `117–119` | `weekCount` = Trainings ab 10 min in der Woche des gezeigten Tages, eigene und fremde. |
| `app/Tagwerk/Capture/CaptureModel.swift:92–99` | Fremde Trainings werden nur gelesen, wenn `access.wasAsked`; Minuten = Ende − Beginn (einschließlich Pausen). |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift:240`, `264–268` | `minimumWorkoutMinutes = 10`, `workoutsThisWeek`. |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/WeekReview.swift:72`, `81–82` | `workoutCount` und `workoutMinutes`, beide nur für Trainings ab 10 min. |
| `app/Tagwerk/Capture/WeekReviewView.swift:111–117` | Text „3 / 3 · 127 min“: Zahl gegen Ziel, Minuten als Zusatz. |
| `app/Tagwerk/Persistence/AppSettings.swift:58–59` | `goalWorkoutsPerWeek: Int = 3`, 0 blendet aus. SwiftData-Regel der Datei: neue Attribute brauchen einen Standardwert. |
| `app/Tagwerk/Settings/CaptureSettingsView.swift:16`, `24` | Stepper „Trainings pro Woche“ und Fußtext mit der 10-min-Regel. |
| `app/Tagwerk/Settings/SettingsView.swift:65–67`, `IntakeFormat.swift:90–93` | Zeilenwert „2.300 kcal · 2,0 l · 3×“. |
| `app/Packages/HealthBridge/Sources/HealthBridge/HealthKitStore.swift:33` | `readTypes = [workoutType()]`. Schritte werden nicht gelesen. |
| `app/Packages/HealthBridge/Sources/HealthBridge/HealthKitStore.swift:41–46` | `access()` leitet „noch nicht gefragt“ aus `statusForAuthorizationRequest(toShare:read:)` über **alle** Typen ab. |
| `app/Tagwerk/Capture/HealthMirror.swift:60–65`, `WeekReviewModel.swift:69` | Ohne `wasAsked` wird nichts gespiegelt und nichts gelesen. |
| `app/project.yml:53`, `app/Tagwerk/Info.plist:45`, `InfoPlist.xcstrings:52` | Lesebegründung nennt nur Trainings. |
| `app/Tagwerk/App/AppEnvironment.swift:350–357`, `TagwerkIntents.swift:76` | Widget-Snapshot und „Heute“ in Siri enthalten keine Trainings. Dort ändert sich nichts. |

**Folgerung für die Berechtigung:** Käme der Schritt-Typ nur in `readTypes`, meldete `access()` bei bestehenden Nutzern wieder `.notDetermined`. Die Spiegelung hielte an, Watch-Trainings fielen aus Tag und Woche, und wer die Health-Karte weggeklickt hat (`healthCardDismissed`), bekäme keinen Hinweis. Der Schritt-Typ wird deshalb getrennt abgefragt.

## Entwurf (ST1)

1. **Schritte, Quelle:** `HKQuantityType(.stepCount)`, Tagessummen über `HKStatisticsCollectionQueryDescriptor` mit `.cumulativeSum`, Intervall ein Tag, Anker Tagesbeginn im Tagwerk-Kalender. Die Statistik führt überlappende Quellen (iPhone, Apple Watch) nach der Quellenreihenfolge in Health zusammen; Tagwerk summiert keine Einzel-Samples. Von Hand in Health eingetragene Schritte zählen mit (Verhalten von Health).
2. **Schritte, Berechtigung:** eigener Zustand `StepsAccess` (`unavailable`, `notAsked`, `asked`). `notAsked`, solange `statusForAuthorizationRequest(toShare: [], read: [stepCount])` `.shouldRequest` meldet. `requestStepsAuthorization()` zeigt das Systemblatt nur nach Tippen auf „In Health erlauben“ in der Kachel oder in Einstellungen › Zugriff › Health. `access()` bleibt auf die bisherigen Typen beschränkt. Die Health-Karte fragt bei Neuverbindung beide Gruppen zusammen an (`requestAuthorization()` nimmt den Schritt-Typ in die Lesemenge auf; nur `access()` nicht).
3. **Schritte, Anzeige:** Kachel „Schritte“ in einer zweiten Zeile der Tagesübersicht: „6.412 / 8.000“ mit Balken; ohne Ziel (0) nur die Zahl. Ohne Daten „–“, nie 0, weil iOS eine abgelehnte Leseerlaubnis nicht von „keine Daten“ unterscheidet. Vergangene Tage zeigen ihren eigenen Wert; der heutige Wert trägt keinen Zusatz.
4. **Schritte, Haltung:** nur im Speicher von `CaptureModel` und `WeekReviewModel`. Kein SwiftData, kein Snapshot, kein Log.
5. **Trainingszeit, Tag:** Abschnittskopf „Training“ rechts mit der Summe des Tages („45 min“, ab 60 min „1 h 17 min“), wie die Kalorien im Kopf von „Essen“ (`CaptureView.swift:175–179`).
6. **Trainingszeit, Woche:** Kachel „Training · Woche“: „127 / 150 min“ gegen `goalWorkoutMinutesPerWeek`; Ziel 0 blendet die Kachel aus.
7. **Ziel:** neues Attribut `goalWorkoutMinutesPerWeek: Int = 150`, neues Attribut `goalStepsPerDay: Int = 8000`. Beide sind Platzhalter wie die übrigen Ziele. 150 min ist an die Untergrenze der WHO-Empfehlung für mäßig anstrengende Ausdaueraktivität (150 bis 300 min pro Woche) angelehnt; Tagwerk misst Dauer, nicht Intensität, und behauptet keine Übereinstimmung. `goalWorkoutsPerWeek` bleibt im Schema (kein Löschen eines Attributs), wird aber nicht mehr angezeigt. Einmalige Übernahme: War das alte Ziel 0, wird das Minutenziel 0 (Merker `workoutGoalMigrated: Bool = false`).
8. **Zählregel:** Zur Trainingszeit zählen alle Trainings, auch unter 10 min; die Liste des Tages und die Summe im Abschnittskopf stimmen so überein. Die 10-min-Schwelle gilt nur noch für die Zahl im Wochenrückblick.
9. **Wochenrückblick:** Training „127 / 150 min · 3 Trainings“ mit Balken; neuer Abschnitt „Schritte“: „Ø 6.801 pro Tag · Ziel an 1 von 3 Tagen“ und sieben Balken mit Ziellinie; Tage ohne Wert gestrichelt, künftige leer (wie die Kalorienbalken).
10. **Einstellungen:** „Training pro Woche: 150 min“ (0…1200, Schritt 15), „Schritte pro Tag: 8.000“ (0…30000, Schritt 500), Fußtext angepasst; Zeilenwert „2.300 kcal · 2,0 l · 150 min“.

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `app/Packages/HealthBridge/Sources/HealthBridge/HealthStoring.swift` | `stepsAccess()`, `requestStepsAuthorization()`, `dailySteps(in:calendar:)`. |
| `app/Packages/HealthBridge/Sources/HealthBridge/HealthEntries.swift` | `StepsAccess`, `DailySteps` (Tagesbeginn, Anzahl). |
| `app/Packages/HealthBridge/Sources/HealthBridge/HealthKitStore.swift` | Schritt-Typ getrennt von `readTypes`; Statistikabfrage; `requestAuthorization()` fragt den Schritt-Typ mit an. |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift` | `IntakeRules.workoutMinutes(_:in:)` (Tag und Woche, ohne Schwelle). |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/IntakeFormat.swift` | `duration(minutes:)`, `steps(_:)`, `goalSummary` mit Minuten. |
| `app/Packages/TagwerkCore/Sources/TagwerkCore/WeekReview.swift` | `Goals.workoutMinutesPerWeek`, `Goals.stepsPerDay`; `Day.steps`; `averageSteps`, `stepGoalDays`, `daysWithSteps`; `workoutMinutes` ohne Schwelle; `isEmpty` berücksichtigt Schritte nicht. |
| `app/Tagwerk/Persistence/AppSettings.swift` | Zwei Ziele, Merker, Übernahme. |
| `app/Tagwerk/Capture/CaptureModel.swift` | `weekMinutes`, `dayMinutes`, `steps: Int?`, `stepsAccess`, `connectSteps()`; `weekCount` entfällt. |
| `app/Tagwerk/Capture/CaptureView.swift` | `DaySummary` mit zweiter Zeile; Abschnittskopf „Training“; Text der Health-Karte nennt Schritte. |
| `app/Tagwerk/Capture/WeekReviewModel.swift`, `WeekReviewView.swift` | Schritte laden, Abschnitt „Schritte“, Trainingstext, Balken. |
| `app/Tagwerk/Settings/CaptureSettingsView.swift`, `SettingsView.swift` | Stepper, Fußtext, Zeilenwert, Health-Zeile mit „Schritte erlauben“. |
| `app/Tagwerk/Capture/DemoHealthStore.swift`, `app/TagwerkTests/Fakes/FakeHealthStore.swift` | Schritte für Demo und Tests. |
| `app/project.yml`, `app/Tagwerk/Info.plist`, `app/Tagwerk/InfoPlist.xcstrings` | `NSHealthShareUsageDescription`: „Tagwerk zeigt deine Trainings und Schritte aus Health im Tab „Erfassen“.“ |
| `app/Tagwerk/Localizable.xcstrings`, Katalog in `TagwerkCore` | Neue und geänderte Texte, deutsch und englisch. |
| `docs/superpowers/specs/2026-11-18-phase-3-design.md` | Nachtrag: Schritte als Lesetyp, Minutenziel. |

## Schritte (TDD, je Task erst der Test)

### Task 1: Regeln und Formate (`TagwerkCore`)
- Tests in `IntakeTests.swift`:
  - `workoutMinutes_sumsAllWorkoutsOfInterval_includingShortOnes`
  - `workoutMinutes_excludesWorkoutsOutsideInterval_endExclusive`
  - `duration_below60_showsMinutes_from60_showsHoursAndMinutes` („45 min“, „1 h 17 min“, „2 h“)
  - `steps_groupsDigitsByLocale` („6.412“, englisch „6,412“)
  - `goalSummary_showsMinutes_andOmitsTrainingWhenGoalIsZero`
- Umsetzung in `Intake.swift`, `IntakeFormat.swift`. Bestehende Tests `weekCount_mondayToSunday_minimum10Minutes` und `goalSummary` anpassen.

### Task 2: Wochenrückblick-Wert (`TagwerkCore`)
- Tests in `WeekReviewTests.swift`:
  - `workoutMinutes_countAllWorkouts_workoutCountKeepsThreshold`
  - `steps_averageOverDaysWithValue_futureDaysExcluded`
  - `steps_goalDays_countDaysAtOrAboveGoal_zeroGoalGivesNone`
  - `steps_missingDay_isNil_notZero`
  - `isEmpty_ignoresSteps` (eine Woche nur mit Schritten gilt weiter als „nichts erfasst“)
- Umsetzung: `make(…, steps: [PlanDay: Int], …)`.

### Task 3: HealthBridge
- Tests in `HealthMappingTests.swift` (reine Abbildung, kein HealthKit):
  - `stepsAccess_shouldRequest_isNotAsked_otherwiseAsked`
  - `access_ignoresStepType` (die Kernabbildung bekommt den Schritt-Status nicht)
  - `dailySteps_roundsSumsToInt_dropsDaysWithoutStatistics`
- Umsetzung in `HealthKitStore`: Abfrage, Fehler `errorNoData` und `errorAuthorizationNotDetermined` ergeben eine leere Liste. `FakeHealthStore` und `DemoHealthStore` ergänzen (Demo: 6.412 heute, zwei Vortage).
- Gerät: siehe Checkliste.

### Task 4: Einstellungen und Übernahme
- Tests in `CaptureSettingsTests.swift`:
  - `defaults_minutesGoal150_stepsGoal8000`
  - `migration_oldGoalZero_setsMinutesGoalZero_once`
  - `migration_oldGoalNonZero_keepsDefault_andDoesNotRunTwice`
- Umsetzung in `AppSettings`, Aufruf beim Start neben den bestehenden Einstellungs-Initialisierungen; `CaptureSettingsView`, `SettingsView`.

### Task 5: `CaptureModel`
- Tests in `CaptureModelTests.swift`:
  - `weekMinutes_includeOwnAndForeignWorkouts` (ersetzt `foreignWorkouts_merged_weekCountIncludesThem`)
  - `dayMinutes_followDisplayedDay`
  - `steps_loadedForDisplayedDay_whenStepsAccessAsked`
  - `steps_notRead_whenStepsNotAsked` (kein Aufruf am Fake)
  - `steps_staleResultOfEarlierDay_isDiscarded` (wie der Wochen-Schutz in `CaptureModel.swift:102`)
  - `connectSteps_requestsOnlySteps_andReloads`
  - `coreAccess_unchanged_whenStepsNotAsked` (Spiegelung läuft weiter)
- Umsetzung: Schritte im selben `reload()` nach den Trainings; `show(_:)` setzt `steps` auf `nil`, bis das Laden fertig ist.

### Task 6: Ansichten „Erfassen“
- `DaySummary`: erste Zeile Wasser und Eiweiß, zweite Zeile Schritte und „Training · Woche“; fehlt eine Kachel der zweiten Zeile (Ziel 0, Health nicht verfügbar), rückt die andere in die erste Zeile, wenn dort Platz ist (Regel als reine Funktion mit Test `summaryRows_layout`).
- Abschnittskopf „Training“ mit Tagessumme. VoiceOver: „Schritte, 6.412 von 8.000“, „Training diese Woche, 127 von 150 Minuten“.
- Kachel im Zustand `notAsked`: Knopf „In Health erlauben“ (eigener Knopf außerhalb des kombinierten VoiceOver-Elements).

### Task 7: Wochenrückblick
- Tests in `WeekReviewModelTests.swift`: `steps_readOnlyWhenAsked`, `review_usesMinuteGoalFromSettings`.
- `WeekReviewView`: Trainingstext, Abschnitt „Schritte“ mit Balken (Balken-Ansicht aus `CalorieBars` verallgemeinern statt kopieren).

### Task 8: Texte, Begründung, Doku
- Kataloge, `NSHealthShareUsageDescription`, Health-Karte, Nachtrag im Phase-3-Design. Prüfen, dass kein Katalogeintrag verwaist.

### Task 9: Prüfung
- `swift test` für `TagwerkCore` und `HealthBridge`, App-Tests, danach Geräte-Checkliste.

## Geräte-Checkliste (offen)

1. Bestehende Installation mit erteiltem Zugriff: Nach dem Update läuft die Spiegelung weiter, Watch-Trainings bleiben sichtbar, die Health-Karte erscheint nicht.
2. „In Health erlauben“ zeigt ein Blatt, das nur Schritte nennt.
3. Tagessumme stimmt mit der App „Health“ überein (iPhone und Apple Watch getragen), auch für einen Tag mit Zeitumstellung.
4. Lesen abgelehnt: Kachel zeigt „–“, kein Fehler, kein erneutes Blatt.
5. Breite der zweiten Zeile mit „12.345 / 10.000“ und „1.185 / 1.200 min“, große Schrift (Dynamic Type) eingeschlossen.

## Risiken

- **Berechtigung:** Der getrennte Status beruht darauf, dass `statusForAuthorizationRequest` je Typmenge auswertet. Trifft das am Gerät nicht zu, ist Task 3 neu zu entwerfen, bevor die Ansichten gebaut werden.
- **Leseablehnung nicht erkennbar:** „–“ kann „abgelehnt“ oder „keine Daten“ heißen. Ein Hinweis mit Weg zu Health steht nur in den Einstellungen.
- **Doppelte Trainingszeit:** Ein von Hand erfasstes und ein Watch-Training, die sich überschneiden, zählen doppelt. Die bestehende Warnung (`CaptureModel.swift:300–306`) bleibt der einzige Schutz; mit Minuten wiegt der Fehler schwerer als mit Stückzahl.
- **Dauer fremder Trainings:** Ende − Beginn enthält Pausen (`CaptureModel.swift:96`). Optional auf `HKWorkout.duration` umstellen; nicht Teil dieses Plans, als offener Punkt vermerken.
- **Mehr Health-Abfragen:** eine zusätzliche Statistikabfrage je Tageswechsel. Ergebnis verspäteter Abfragen wird verworfen.
- **Höhe:** Die Übersicht wächst um rund 50 pt (Rechnung).
- **Ziel 150 min:** kann als Gesundheitsempfehlung gelesen werden. Der Fußtext „Platzhalter, keine Empfehlung“ bleibt und nennt die WHO nicht.

## Datenschutz

- Schritte sind Gesundheitsdaten aus fremden Quellen. Sie werden nur gelesen und nur angezeigt.
- Nicht an den Assistenten und nicht an die Mahlzeitenschätzung (`AssistantModel.swift:377–378` bleibt unverändert; kein neues Kontextfeld).
- Nicht in Logs: Fehler der Abfrage nur als Domäne und Code, wie in `HealthMirror.swift:93–96`.
- Nicht im Widget-Snapshot, nicht auf dem Sperrbildschirm, nicht in Siri-Antworten (Phase-4-Design, Anti-Ziele und Entscheidung 14).
- Nicht in SwiftData, nicht in der App-Gruppe, nicht im Netz.
- Die Anfrage erscheint nur nach einem Tippen des Nutzers.

## Offene Entscheidungen (Vorschlag in Klammern)

1. Variante der Übersicht (ST1).
2. Wochenziel in Minuten statt in Trainings (ja, Platzhalter 150 min; altes Ziel 0 bleibt „aus“).
3. Schrittziel (ja, Platzhalter 8.000 pro Tag; 0 = ohne Ziel).
4. Trainings unter 10 min zur Trainingszeit zählen (ja).
5. Schritte im Widget oder im Kopf von „Planen“ (nein).
6. Schreibweise ab 60 min im Abschnittskopf („1 h 17 min“; gegen das Ziel immer Minuten).
7. Zahl der Trainings im Wochenrückblick als Zusatz behalten (ja).

## Entscheidungen (18.11.2026, freigegeben)

1. Variante ST1.
2. Wochenziel in Minuten statt Anzahl Trainings, Platzhalter 150 min.
3. Schrittziel ja, Platzhalter 8.000 pro Tag, 0 = ohne Ziel.
4. Trainings unter 10 min zählen zur Trainingszeit; die 10-min-Schwelle bleibt nur für die Zahl der Trainings.
5. Schritte auch im Widget und im Kopf von „Planen“ (Abweichung vom Vorschlag). Wie Kalorien und Wasser nie auf dem Sperrbildschirm und nur mit dem Schalter für Ernährungswerte im Widget.
6. Ab 60 min überall einheitlich „x h y min“, auch gegen das Ziel (Abweichung vom Vorschlag).
7. Zahl der Trainings bleibt im Wochenrückblick als Zusatz (Vorschlag).
8. Ohne Schrittdaten „–“ statt 0.
