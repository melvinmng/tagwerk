# P3 Fokus und Aufwand (#161, #162) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026 auf dem Stand `origin/main` 70a2b9c. Ohne Mockups gebaut, nach den Mustern der App; Aussehen und Wortlaut gehen danach in die Designrunde #188. Nichts davon ist gebaut oder am Gerät geprüft.

**Goal:**
- **#161:** Ein Fokus-Timer, gestartet aus einem Zeitblock, aus einer Aufgabe oder frei.
  - Pomodoro mit Runden und langer Pause.
  - Live Activity auf dem Sperrbildschirm und in der Dynamic Island, am Ende „Erledigt / Weiter / Verschieben“.
  - Eine eigene Sammlung als Belohnung.
  - App-Sperre nur, wenn der Spike sie mit dem Personal Team erlaubt.
- **#162:** Tagwerk misst den Ist-Aufwand aus Fokus-Zeiten, Zeitblöcken und dem Zeitpunkt des Abhakens.
  - Ein Block, der zu früh endet, wird gekürzt.
  - Der Wochenrückblick zeigt Schätzung gegen Ist je Quelle und Label.
  - Die KI-Planung bekommt einen erwarteten Aufwand je Aufgabe.

**Architecture:**
- **Reine Regeln in `TagwerkCore`:** `FocusTimerRules` (Phasen, Zustand aus Zeitstempeln), `FocusReward` (Wachstumsstufe), `EffortRules` (Ist-Aufwand und Kürzungsentscheidung), `EffortStats` (Korrekturfaktor). Alle ohne App testbar.
- **App:** neuer Ordner `app/Tagwerk/Focus/` mit SwiftData-Typen, `FocusStore`, `FocusTimerModel`, `FocusActivityController`, `FocusNotificationScheduler`, `EffortTracker` und den Ansichten.
- **Live Activity:** läuft im vorhandenen Target `TagwerkWidget`. Attribute und Intents liegen in geteilten Dateien, die `project.yml` wie `Color+Hex.swift` zusätzlich ins Widget einbindet.
- **Eingriffe in fremde Dateien:** jeweils höchstens ein Aufruf oder eine Zeile (siehe „Konfliktregeln“).

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI (iOS 27), SwiftData, EventKit, ActivityKit, App Intents, UserNotifications, optional FamilyControls/ManagedSettings, Swift Testing. Das Projekt kommt aus XcodeGen (`app/project.yml`), Quellordner werden als Ganzes eingelesen.

**Issues:** #161, #162. Sie werden nicht geschlossen; der Status kommt nach der Prüfung auf „In review“.

## Global Constraints

- **Namen:** „Fokus“ ist im Code schon belegt, `FocusMark`/`FocusRules` (Tagesfokus) und `FocusQuiet` (Fokus-Filter von iOS). Neue Typen heißen deshalb `FocusTimer…`, `FocusSession…`, `FocusReward…`, `Effort…`. In der Oberfläche heißt die Funktion „Fokus-Timer“.
- **Speicher:** Es bleibt ein SwiftData-Store, lokal, nicht im Group-Container (`ModelContainerFactory.swift`).
  - Neue Typen kommen in `ModelContainerFactory.schema`.
  - Jedes neue Attribut, auch in `AppSettings`, hat einen Standardwert. `ModelStoreLocationTests` bleibt grün.
- **Datenschutz:** Fokus-Zeiten, Sammlung und Stichproben bleiben auf dem iPhone.
  - An ChatGPT geht nur je Aufgabe die Zahl `expectedMinutes`. Keine Labels, keine Statistik, keine Verlaufsdaten.
  - Abschaltbar über „Erfahrungswerte in der Planung nutzen“ (Standard an), im Datenschutzhinweis genannt.
  - Nichts davon steht in Logs.
- **Mitteilungen:**
  - `NotificationScheduler` wird nicht angefasst, P4 baut ihn parallel um.
  - Der Fokus-Timer plant über einen eigenen `FocusNotificationScheduler` höchstens **eine** Mitteilung (Ende der laufenden Phase), mit dem Bezeichner-Präfix `focus.`.
  - Budget: 50 (Hauptplan) + 5 (Routinen) + 1 (Fokus) = 56 < 64. Diese Rechnung im PR-Text für P4 nennen.
  - Ruhezeiten gelten für diese Mitteilung nicht, weil der Timer bewusst gestartet wurde. Das ist ein Designpunkt.
- **Zeitblöcke:** Tagwerk ändert nur Blöcke im Plan-Kalender, die eine Aufgaben-URL tragen (`TaskLinkURL`). Kürzen läuft über das vorhandene `CalendarStore.moveBlock(id:to:end:expectedVersion:)`.
- **Texte:** Deutsch ist Quellsprache, jeder neue Text steht deutsch und englisch im String Catalog (`Localizable.xcstrings`, Widget-Texte in `TagwerkWidget/Localizable.xcstrings`). Danach `scripts/sync-strings.sh` und `scripts/check-strings.py`. Code, Kommentare, Log- und Testmeldungen auf Englisch.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI, ohne `Co-Authored-By`. Branch `feat/focus-timer-effort`.
- **Tests:** vor jedem Commit ab Task 5 `app/test-all.sh`. Die Tasks 1–4 reichen mit `swift test` im Paket `TagwerkCore`.

### Konfliktregeln (parallel laufen P1, P2, P4, P5)

| Datei | Andere Pakete | Erlaubter Eingriff in P3 |
|---|---|---|
| `Planning/PlanView.swift`, `TimelineCanvas.swift`, `DayView.swift` | P1, P2 | **keiner**; gekürzte Blöcke erscheinen über das normale Neuladen |
| `Planning/EntrySheet.swift` | P2, P4 | eine Zeile im letzten Abschnitt von `eventContent` (`FocusStartButton(block:)`), nur für Blöcke mit Aufgabe |
| `Notifications/NotificationScheduler.swift` | P4 | **keiner** |
| `Capture/WeekReviewView.swift` | P1 | eine Zeile `EffortReviewSection(model: …)` vor `WeekReflectionSections` |
| `Capture/CaptureView.swift` | P2 (#134 Blättern) | ein Abschnitt-Aufruf `FocusCaptureSection()` am Ende der Liste |
| `Settings/SettingsView.swift` | P2, P4 | ein `NavigationLink` „Fokus-Timer“ |
| `App/AppEnvironment.swift` | alle | neue Eigenschaften `focus`, `effort` und eine Zeile im vorhandenen `onCompletionChanged`-Block |
| `Tasks/TaskListModel.swift` | P1 (#163) | ein zusätzlicher Hook `onCompletedItem`, sonst nichts |
| `App/EntrySheets.swift` (`AppTaskEditorSheet`) | P4 | ein Knopf „Fokus starten“ in der Toolbar oder im Menü |
| `Localizable.xcstrings` | alle | nur neue Schlüssel; beim Rebase per `scripts/sync-strings.sh` neu erzeugen statt von Hand mischen |

Wer einen dieser Eingriffe größer machen muss, hält an und beschreibt es im Bericht.

## Review Focus

1. **Timer im Hintergrund:** Start um 10:00 (25/5), App sofort geschlossen, um 10:31 geöffnet. Erwartet: Die Arbeitsphase ist mit 25 min Fokus gebucht, die Pause läuft mit noch 4 min, die Live Activity zeigt die Pause. Der Zustand kommt nur aus Zeitstempeln, nicht aus einem laufenden `Timer`. Test: `FocusTimerRulesTests.state_afterBackgroundGap_isDerivedFromTimestamps`.
2. **Neustart der App während einer Sitzung** (vom System beendet): Erwartet: Die laufende Sitzung wird aus dem Store wiederhergestellt, die Live Activity wird übernommen statt verdoppelt. Ist sie über 12 Stunden alt, wird sie als abgebrochen beendet. Test: `FocusTimerModelTests.relaunch_restoresTheRunningSession`, `relaunch_endsAStaleSession`.
3. **Früh abgehakt:**
   - Ablauf: Block 14:00–15:00, um 14:20 abgehakt.
   - Erwartet: Der Block endet um 14:20, die Stichprobe zählt 20 min, „Rückgängig“ setzt das Blockende wieder auf 15:00 und löscht die Stichprobe.
   - Nach einer Änderung im Kalender meldet die Versionsprüfung einen Konflikt. Dann wird nichts gekürzt, die Stichprobe zählt trotzdem.
   - Tests: `EffortTrackerTests.earlyCompletion_trimsTheBlockAndRecordsTheElapsedTime`, `undo_restoresTheBlockEnd`, `trimConflict_keepsTheBlockButRecordsTheSample`.
4. **Spät oder ohne Block abgehakt:**
   - Ein Block 9–10 Uhr, um 17:00 abgehakt: Erwartet sind 60 min und keine Änderung am Block.
   - Ohne Block und ohne Fokus-Zeit: Es entsteht keine Stichprobe.
   - Mit Fokus-Zeit zählt nur die Fokus-Zeit, Blöcke dann nicht zusätzlich.
   - Tests in `EffortRulesTests`.
5. **App-Sperre bleibt hängen:** Ist sie nach einem Absturz noch aktiv, hebt der nächste Start sie auf, wenn keine Sitzung läuft. Test: `FocusShieldPolicyTests.launchWithoutSession_clearsTheShield` (nur wenn Task 0 positiv ist).

---

## Task 0: Spike App-Sperre (Family Controls mit Personal Team)

**Ziel:** Klären, ob sich `com.apple.developer.family-controls` mit dem Personal Team (ohne bezahltes Developer Program) signieren lässt. Ein iPhone ist dafür nicht nötig.

- [ ] Auf einem Wegwerf-Branch `spike/family-controls` in `app/project.yml` unter `targets.Tagwerk.entitlements.properties` den Eintrag `com.apple.developer.family-controls: true` ergänzen.
- [ ] Mit den Werten aus `~/Library/Application Support/Tagwerk/config` (wird von `scripts/install-config.zsh` gelesen) bauen. Team-ID und Geräte-ID nie ausgeben oder ins Repo schreiben:
  ```zsh
  source scripts/install-config.zsh
  (cd app && xcodegen --quiet)
  xcodebuild -project app/Tagwerk.xcodeproj -scheme Tagwerk -destination 'generic/platform=iOS' \
    -derivedDataPath "$HOME/Library/Developer/Tagwerk/DerivedData-spike-fc" -allowProvisioningUpdates \
    "${BUILD_SETTINGS[@]}" build 2>&1 | tail -n 40
  ```
- [ ] Ergebnis prüfen:
  - Bricht der Bau mit einem Signierfehler ab (z. B. „Personal development teams … do not support the Family Controls capability“ oder „Provisioning profile … doesn't include the com.apple.developer.family-controls entitlement“), ist der Spike **negativ**.
  - Läuft er durch, ist er **positiv, aber vorläufig**. Ob `AuthorizationCenter.requestAuthorization(for: .individual)` auf dem iPhone durchgeht, zeigt erst der Gerätetest.
- [ ] Branch löschen, DerivedData-Ordner `DerivedData-spike-fc` löschen.
- [ ] Ergebnis mit Fehlertext ohne IDs in `docs/superpowers/spikes/2026-11-19-family-controls.md` festhalten und committen (`docs: record the family controls signing spike`).
- [ ] Bei **negativ**: Task 12 entfällt. In den Einstellungen erscheint nichts zur App-Sperre. Im Bericht und im PR-Text steht „App-Sperre nicht gebaut: Family Controls mit Personal Team nicht signierbar“.

## Task 1: `FocusTimerRules` (TagwerkCore)

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/FocusTimerRules.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/FocusTimerRulesTests.swift`

Typen:
- `FocusTimerSettings`: `workMinutes` 25, `shortBreakMinutes` 5, `longBreakMinutes` 15, `rounds` 4, `isPomodoro` Bool; Grenzen 5–120 / 1–30 / 5–60 / 1–8.
- `FocusPhase`: `.work(round)`, `.shortBreak(round)`, `.longBreak`, `.finished`.
- `FocusTimerState`: `start`, `pauses: [DateInterval]`, `skips: [Date]` (übersprungene Pausen), `settings`, `endedAt`.
- `FocusTimerRules.snapshot(of:at:) -> FocusTimerSnapshot`: aktuelle Phase, Phasenende, restliche Sekunden, `focusedSeconds` (nur Arbeitsphasen, ohne Pausen), erledigte Runden.

Regeln:
- Ohne Pomodoro gibt es genau eine Arbeitsphase mit `workMinutes`, danach `.finished`.
- Pomodoro: Arbeit, kurze Pause, Arbeit … Nach der letzten Runde kommt die lange Pause, dann `.finished`.
- Pausieren hält die Uhr an; ein übersprungener Pausenabschnitt endet sofort.
- Alles wird aus `start`, `pauses` und `skips` berechnet, nie aus einem laufenden Zähler.

- [ ] Tests zuerst:
  - `single_endsAfterWorkMinutes`
  - `pomodoro_sequenceOfFourRounds_endsWithLongBreak`
  - `pause_stopsTheClock`
  - `skipBreak_startsTheNextRoundImmediately`
  - `focusedSeconds_countOnlyWorkPhases`
  - `state_afterBackgroundGap_isDerivedFromTimestamps`
  - `settings_areClampedToTheirBounds`
- [ ] Umsetzen, `swift test --filter FocusTimerRulesTests` grün, Commit `feat: add focus timer phase rules`.

## Task 2: `FocusReward` (TagwerkCore)

**Files:** Create `FocusReward.swift`, Test `FocusRewardTests.swift`.

- Pro beendeter Sitzung entsteht ein Stück der Sammlung.
- `FocusReward.stage(focusedMinutes:outcome:) -> FocusRewardStage`. Stufen 1–5 ab 1, 10, 25, 50, 90 Fokus-Minuten.
- Outcome `.completed` wächst, `.aborted` ergibt `.wilted(stage)`.
- `.discarded` (Abbruch in den ersten 60 s) erzeugt kein Stück.
- Die Darstellung ist bewusst neutral (`FocusRewardStage` mit `rawValue`), damit die Gestaltung in #188 frei bleibt. Kein Baum, kein Wald, keine Anlehnung an Forest.
- [ ] Tests:
  - `stage_thresholds`
  - `abortedSession_wilts`
  - `abortWithinAMinute_isDiscarded`
  - `collectionSummary_countsGrownAndWilted`
- [ ] Commit `feat: add focus reward stages`.

## Task 3: `EffortRules` (TagwerkCore)

**Files:** Create `EffortRules.swift`, Test `EffortRulesTests.swift`.

Eingaben:
- Abhakzeitpunkt `completedAt`.
- Blöcke der Aufgabe als `[DateInterval]` mit ID, aus dem Plan-Kalender und auf `completedAt`'s Tag plus vorherige Tage im Fenster.
- `focusedSeconds` aus Fokus-Sitzungen dieser Aufgabe seit dem letzten Abhaken.
- `estimateMinutes`.

Ausgabe `EffortOutcome`: `actualMinutes: Int?`, `method: .focus | .blocks | .partialBlock`, `trim: BlockTrim?` (Block-ID, neues Ende, altes Ende).

Regeln:
1. Gibt es Fokus-Zeit (≥ 1 min), zählt nur sie (`.focus`). Läuft dabei gerade ein Block, wird er zusätzlich gekürzt (Regel 2b).
2. Liegt `completedAt` in einem Block:
   - a) Ist-Aufwand = vergangene Blöcke vollständig + `completedAt − start` des laufenden Blocks (`.partialBlock`).
   - b) Der laufende Block endet neu bei `completedAt`, auf 5 min abgerundet. Sind seit Blockstart weniger als 5 min vergangen, gibt es keine Kürzung (der Block bleibt) und einen Hinweis im Ergebnis (`trim == nil`, `tooShortToTrim == true`).
3. `completedAt` liegt nach allen Blöcken, egal wie lange: Die Summe der Blöcke zählt, keine Änderung (`.blocks`). Blöcke nach `completedAt` zählen nicht und bleiben unverändert. Deren Löschung ist nicht Teil von #162 und wird im Bericht als offene Frage genannt.
4. Kein Block, keine Fokus-Zeit: `actualMinutes == nil`, es entsteht keine Stichprobe.
5. Wiederkehrende Aufgaben: nur Blöcke und Fokus-Zeit seit dem vorigen Abhaken desselben Vorkommens.

- [ ] Tests:
  - `focusTime_winsOverBlocks`
  - `completionInsideBlock_trimsToCompletionRoundedDown`
  - `completionInsideBlock_withinFiveMinutes_doesNotTrim`
  - `completionAfterBlockEnd_countsTheFullBlock`
  - `completionHoursLater_countsTheFullBlockAndChangesNothing`
  - `noBlockNoFocus_givesNoSample`
  - `severalBlocks_pastOnesCountFully`
  - `recurringTask_onlyCountsSinceThePreviousCompletion`
- [ ] Commit `feat: add actual effort rules`.

## Task 4: `EffortStats` (TagwerkCore)

**Files:** Create `EffortStats.swift`, Test `EffortStatsTests.swift`.

- `EffortSample`: `source`, `labels`, `estimateMinutes`, `actualMinutes`, `completedAt`.
- `EffortStats.groups(samples, window: 56 Tage, now:)` liefert je Quelle und je Label: Anzahl, Median des Verhältnisses Ist/Schätzung, Abweichung in Prozent.
- **Mindestens 3 Stichproben** je Gruppe, sonst keine Aussage.
- `EffortStats.factor(for task:)`: zuerst das Label mit den meisten Stichproben, sonst die Quelle, sonst 1. Begrenzt auf 0,5–2,0.
- `expectedMinutes(estimate:factor:)` wird auf 5 min gerundet.
- Stichproben ohne Schätzung zählen nur in der Anzeige „gemessen ohne Schätzung“, nicht im Faktor.
- [ ] Tests:
  - `groupNeedsThreeSamples`
  - `medianRatio_ignoresOutliers`
  - `factor_prefersLabelOverSource`
  - `factor_isClamped`
  - `samplesOutsideWindow_areIgnored`
  - `expectedMinutes_roundToFive`
- [ ] Commit `feat: add effort statistics`.

## Task 5: Speicher und Einstellungen

**Files:**
- Create: `app/Tagwerk/Focus/FocusRecords.swift`
  - `FocusSessionRecord`: `id`, `taskKey?`, `blockEventID?`, `title` (nur lokal), `start`, `pausesJSON`, `skipsJSON`, `settingsJSON`, `endedAt?`, `outcomeRaw`, `focusedSeconds`, `activityID?`.
  - `EffortSampleRecord`: `id`, `taskKey`, `sourceRaw`, `labelsJSON`, `estimateMinutes?`, `actualMinutes`, `methodRaw`, `completedAt`, `trimmedEventID?`, `trimmedOriginalEnd?`.
- Create: `app/Tagwerk/Focus/FocusStore.swift`: Lesen, Schreiben, `runningSession()`, `sessions(for taskKey:since:)`, `samples(in:)`, `deleteSample(for taskKey:completedAt:)`. Lesen legt nie etwas an.
- Modify: `ModelContainerFactory.schema` um beide Typen ergänzen.
- Modify: `AppSettings`: `focusWorkMinutes` 25, `focusShortBreakMinutes` 5, `focusLongBreakMinutes` 15, `focusRounds` 4, `focusUsesPomodoro` true, `focusAppLockEnabled` false, `effortHistoryInPlanning` true.
- Test: `app/TagwerkTests/FocusStoreTests.swift`
  - `runningSession_isNilWithoutRecords`
  - `reading_neverInserts`
  - `samples_inRange`
  - `deleteSample_removesOnlyThatCompletion`
- `ModelStoreLocationTests` muss weiter grün sein.
- [ ] `app/test-all.sh` grün, Commit `feat: store focus sessions and effort samples`.

## Task 6: `FocusTimerModel` und Mitteilung

**Files:**
- Create: `app/Tagwerk/Focus/FocusTimerModel.swift` (`@Observable @MainActor`). Eingaben über Protokolle, damit Tests mit Fakes laufen: Uhr `now`, `FocusStore`, `FocusActivityControlling`, `FocusNotificationScheduling`, `FocusShielding?`.
  - `start(task: TaskItem?, block: CalendarEvent?)`: nimmt die Einstellungen; ein Block ohne Pomodoro setzt `workMinutes` auf die Restlänge des Blocks (mindestens 5).
  - `pause()`, `resume()`, `skipBreak()`, `stop()` (Abbruch), `finish(_ action: FocusEndAction)` mit `.complete` (Aufgabe erledigen über `TaskListModel.complete`), `.continue` (neue Arbeitsphase), `.postpone` (Aufgabe auf morgen über `PlanningModel.assign`).
  - `restore()` beim App-Start: Eine laufende Sitzung wird übernommen; ist sie über 12 h alt, wird sie als `.aborted` beendet.
  - Eine Aktualisierung pro Sekunde nur, solange die Ansicht sichtbar ist (`TimelineView(.periodic)` in der Ansicht, nicht im Modell).
- Create: `app/Tagwerk/Focus/FocusNotificationScheduler.swift`. Plant genau eine Mitteilung `focus.phaseEnd` zum Phasenende und entfernt sie bei Pause, Stop oder Ende. Text: „Pause vorbei“ / „Fokuszeit vorbei“ mit dem Aufgabentitel, nur wenn die Sperrbildschirm-Vorschau es erlaubt (wie bei vorhandenen Aufgaben-Mitteilungen). Nutzt `NotificationCenterClient`.
- Modify: `AppEnvironment`: `let focus: FocusTimerModel` und `restore()` in der vorhandenen Startsequenz.
- Test: `app/TagwerkTests/FocusTimerModelTests.swift`
  - `startFromBlock_usesTheRemainingBlockLength`
  - `pause_removesThePendingNotification`
  - `finishComplete_completesTheTaskOnce`
  - `finishPostpone_assignsTomorrow`
  - `stopWithinAMinute_discardsTheSession`
  - `relaunch_restoresTheRunningSession`
  - `relaunch_endsAStaleSession`
  - `onlyOneSessionRuns`
- [ ] Commit `feat: add the focus timer model`.

## Task 7: Live Activity

**Files:**
- Create: `app/Tagwerk/Focus/Shared/FocusActivityAttributes.swift` (`ActivityAttributes`):
  - Feste Daten: Titel, ob Pomodoro.
  - `ContentState`: Phase, `phaseEnd: Date`, `pausedRemaining: Int?`, Runde von Runden.
  - Nur was angezeigt wird, kein Notiztext.
- Create: `app/Tagwerk/Focus/Shared/FocusActivityIntents.swift`:
  - `LiveActivityIntent`s `FocusCompleteIntent`, `FocusContinueIntent`, `FocusPostponeIntent`, `FocusPauseIntent`.
  - `perform()` ruft `FocusActionBridge.handler?(action)`. `FocusActionBridge` ist ein `@MainActor enum` mit statischem Handler, den nur die App setzt.
  - Live-Activity-Intents laufen im App-Prozess, im Widget bleibt der Handler `nil`.
- Create: `app/TagwerkWidget/FocusLiveActivity.swift`:
  - `ActivityConfiguration` mit Sperrbildschirm-Ansicht, Dynamic Island (compact, minimal, expanded).
  - Countdown über `Text(timerInterval:countsDown:)`.
  - Knöpfe: „Pause“ während der Arbeit; am Phasenende „Erledigt / Weiter / Verschieben“.
- Create: `app/Tagwerk/Focus/FocusActivityController.swift` (`FocusActivityControlling`): `start`, `update`, `end`; übernimmt bei `restore()` eine vorhandene Activity über `Activity<FocusActivityAttributes>.activities` statt eine zweite zu starten.
- Modify `app/project.yml`:
  - Unter `TagwerkWidget.sources` die Pfade `Tagwerk/Focus/Shared/FocusActivityAttributes.swift` und `Tagwerk/Focus/Shared/FocusActivityIntents.swift` ergänzen.
  - Unter `Tagwerk.info.properties` den Eintrag `NSSupportsLiveActivities: true` ergänzen.
- Modify `TagwerkWidgetBundle.swift`: `FocusLiveActivity()` ergänzen.
- **Grenze ohne Push-Server:** Endet eine Phase, während die App im Hintergrund ist, zeigt der Countdown 0:00, und die Activity bekommt `staleDate = phaseEnd`. Die Ansicht wechselt dann auf „Phase vorbei“ mit den Knöpfen. Der nächste Phasenwechsel passiert beim Tippen auf einen Knopf (Intent im App-Prozess) oder beim Öffnen der App. Das steht im PR-Text.
- Test: `app/TagwerkTests/FocusActivityTests.swift` mit Fake-Controller:
  - `start_startsOneActivity`
  - `restore_adoptsTheExistingActivity`
  - `phaseChange_updatesTheContentState`
  - `end_endsTheActivityImmediately`
  - `intentHandler_routesToTheModel`
- [ ] `xcodegen`, Build und Tests grün, Commit `feat: show the focus timer as a live activity`.

## Task 8: Oberfläche

**Files:**
- Create: `app/Tagwerk/Focus/FocusTimerView.swift`. Blatt mit großer Restzeit, Phase, Runde, Aufgabe und den Knöpfen Pause/Weiter, Pause überspringen und Beenden. Beenden fragt nach: „Fokus abbrechen? Das Stück der Sammlung welkt.“ Am Ende stehen „Erledigt / Weiter / Verschieben“.
- Create: `app/Tagwerk/Focus/FocusStartButton.swift`. Knopf „Fokus starten“ für ein `CalendarEvent` mit Aufgabe oder für ein `TaskItem`; läuft schon eine Sitzung, öffnet er sie.
- Create: `app/Tagwerk/Focus/FocusCaptureSection.swift`. Abschnitt „Fokus-Timer“ in „Erfassen“ mit „Frei starten“, der laufenden Sitzung und „Sammlung“ (Anzahl gewachsen und gewelkt).
- Create: `app/Tagwerk/Focus/FocusCollectionView.swift`. Raster der Stücke nach Woche, Platzhalter-Symbole je Stufe (SF Symbols, neutral). Die Gestaltung folgt in #188.
- Create: `app/Tagwerk/Settings/FocusSettingsView.swift`. Arbeitszeit, Pausen, Runden, Pomodoro an/aus, „Erfahrungswerte in der Planung nutzen“ und App-Sperre (nur bei positivem Spike).
- Modify (je eine Zeile, siehe Konfliktregeln): `EntrySheet.swift` (letzter Abschnitt von `eventContent`, nur `isBlock` mit Aufgabe), `EntrySheets.swift` (`AppTaskEditorSheet`), `CaptureView.swift`, `SettingsView.swift`.
- Präsentation: Das Fokus-Blatt hängt am `RootView` (`.sheet(isPresented:)` über `environment.focus.isPresented`). In der vorhandenen `onChange(of: assistant.isPresented)`-Kette wird es geschlossen wie die anderen Blätter.
- [ ] Sichtprüfung im eigenen Simulator mit `-TagwerkDemoData`: Blatt in hell und dunkel, große Schrift (AX3), Start aus einem Block. Danach den Simulator **löschen** (siehe Abschluss).
- [ ] Commit `feat: add the focus timer screens`.

## Task 9: `EffortTracker` (Ist-Aufwand beim Abhaken)

**Files:**
- Create: `app/Tagwerk/Focus/EffortTracker.swift` (`@MainActor`).
  - `didComplete(_ item: TaskItem, at:)`: liest die Blöcke der Aufgabe für das Fenster `[completedAt − 14 Tage, completedAt + 1 Tag]` und `FocusStore.sessions` seit dem letzten Abhaken. Danach ruft es `EffortRules.outcome` auf, kürzt den Block gegebenenfalls über `CalendarStore.moveBlock(id:to:end:expectedVersion:)` und speichert die Stichprobe mit altem Ende.
  - `didReopen(_ id: TaskID)`: Die letzte Stichprobe dieser Aufgabe (≤ 24 h) wird gelöscht; war ein Block gekürzt und ist er unverändert, bekommt er sein altes Ende zurück.
- Modify `BlockPlanner.swift`: neue Methode `blocks(for taskID: TaskID, in interval: DateInterval) -> [CalendarEvent]`, gleiche Filterung wie `futureBlocks`. Keine Änderung an bestehenden Methoden.
- Modify `TaskListModel.swift`: Hook `var onCompletedItem: ((TaskItem, Date) async -> Void)?`, aufgerufen an genau den Stellen, an denen heute `onCompletionChanged?(id, true)` aufgerufen wird und ein `TaskItem` vorliegt: `complete(_:)`, `setStatus`, `didSave`, `complete(_ ids:)` (dort je Item vor dem Entfernen merken). Wiederkehrende lokale Aufgaben, die offen bleiben, zählen auch (`updated` mit neuem Fälligkeitsdatum).
- Modify `AppEnvironment.swift`: `taskList.onCompletedItem = { item, date in await effort.didComplete(item, at: date) }`. Im vorhandenen `onCompletionChanged`-Block bei `isCompleted == false` `await effort.didReopen(id)` aufrufen. Danach `planning.reload()` wie bisher.
- Test: `app/TagwerkTests/EffortTrackerTests.swift` mit `FakeCalendarStore` aus `TagwerkTests/Fakes`:
  - `earlyCompletion_trimsTheBlockAndRecordsTheElapsedTime`
  - `undo_restoresTheBlockEnd`
  - `undo_afterTheBlockChanged_leavesItAlone`
  - `trimConflict_keepsTheBlockButRecordsTheSample`
  - `completionWithoutBlockOrFocus_recordsNothing`
  - `bulkComplete_recordsEachTask`
  - `focusSession_isUsedInsteadOfBlocks`
- [ ] Commit `feat: measure actual effort when a task is completed`.

## Task 10: Wochenrückblick „Schätzung und Ist“

**Files:**
- Create: `app/Tagwerk/Focus/EffortReviewSection.swift`
  - Abschnitt mit Fußtext: „Gemessen über Fokus-Timer und Zeitblöcke, letzte 8 Wochen.“
  - Je Gruppe eine Zeile, z. B. „Erinnerungen: dauern im Schnitt 40 % länger als geschätzt (7 Aufgaben)“.
  - Labels darunter („Schreiben: +40 %“).
  - Fokus-Zeit dieser Woche und Anzahl der Stichproben dieser Woche.
  - Gruppen mit weniger als drei Stichproben: „Noch zu wenige Messungen.“
- Create: `app/Tagwerk/Focus/EffortReviewText.swift`: reine Textbausteine, testbar.
- Modify `WeekReviewView.swift`: eine Zeile vor `WeekReflectionSections`. Die Daten kommen aus `environment.effort`, `WeekReviewModel` bleibt unverändert (P1 ändert ihn).
- Test: `app/TagwerkTests/EffortReviewTextTests.swift`
  - `longerThanEstimated_german`
  - `shorterThanEstimated_german`
  - `english_texts`
  - `tooFewSamples`
  - `withinFivePercent_saysAsEstimated`
- [ ] Commit `feat: show estimate against actual effort in the week review`.

## Task 11: Korrekturfaktor für die KI-Planung

**Files:**
- Modify `TagwerkCore/AIPlanning.swift`:
  - `PlanInputTask.expectedMinutes: Int?` (Standard `nil`), im `modelJSON()`-`Task` als optionales Feld `expectedMinutes` (nur gesetzt, wenn ≠ `minutes`).
  - Im Eingabe-Bau (`tasks.map`, Zeile ~251) aus einem übergebenen `[String: Int]` (Aufgaben-Key → erwartete Minuten) füllen. Die Schnittstelle bekommt einen Parameter mit Standardwert `[:]`, damit bestehende Aufrufer und Tests unverändert bleiben.
- Modify `Tagwerk/AI/AIPlanner.swift`:
  - In `instructions(...)` einen Satz ergänzen, nur wenn mindestens eine Aufgabe `expectedMinutes` hat: „expectedMinutes: erwarteter Aufwand aus bisherigen Messungen der Person; plane Blöcke mit diesem Wert statt minutes.“
  - Die Map kommt von `EffortTracker.expectedMinutes(for:)`, aber nur bei `settings.effortHistoryInPlanning`.
- Modify Datenschutztext (`ChatGPTSignInModel.privacyNotice` bzw. `AIPrivacyView`): ein Satz, dass je Aufgabe ein erwarteter Aufwand in Minuten mitgeht, abschaltbar unter „Fokus-Timer“.
- Tests:
  - `AIPlanningTests.modelJSON_includesExpectedMinutesOnlyWhenDifferent`
  - `AIPlanningTests.input_withoutHistory_isUnchanged`
  - `AIPlannerTests.instructions_mentionExpectedMinutesOnlyWhenPresent`
  - `AIPlannerTests.historySwitchOff_sendsNoExpectedMinutes`
- [ ] Commit `feat: pass expected effort to AI planning`.

## Task 12: App-Sperre (nur bei positivem Spike)

**Files:**
- Modify `app/project.yml`: Entitlement `com.apple.developer.family-controls: true` für `Tagwerk`.
- Create: `app/Tagwerk/Focus/FocusShield.swift` (`FocusShielding`):
  - `requestAuthorization()` über `AuthorizationCenter.shared.requestAuthorization(for: .individual)`.
  - `apply(exceptions: FamilyActivitySelection)` mit `ManagedSettingsStore(named: .tagwerkFocus)`: `shield.applicationCategories = .all(except: exceptions.applicationTokens)`.
  - `clear()`.
  - Die Auswahl wird als `Data` (Codable) in `AppSettings.focusAppLockExceptions` gespeichert (neues Attribut, Standard leer).
- Create: `TagwerkCore/FocusShieldPolicy.swift`, rein: Sperre nur während Arbeitsphasen, nie in Pausen, und beim Start ohne laufende Sitzung immer aufheben.
- UI in `FocusSettingsView`: Schalter „Apps während Fokus sperren“, `FamilyActivityPicker` für Ausnahmen, Hinweis „Telefon und Notrufe bleiben immer erreichbar“.
- Tests:
  - `FocusShieldPolicyTests.shieldOnlyDuringWork`
  - `FocusShieldPolicyTests.launchWithoutSession_clearsTheShield`
  - `FocusTimerModelTests.stop_clearsTheShield` (Fake)
- [ ] Commit `feat: block distracting apps during focus`.

## Task 13: Abschluss

- [ ] `scripts/sync-strings.sh`, `python3 scripts/check-strings.py`, `app/test-all.sh` grün.
- [ ] Ein Abschnitt „P3 Fokus und Aufwand“ in `docs/superpowers/2026-11-19-overnight-log.md` im Format der vorhandenen Abschnitte:
  - umgesetzte Tasks
  - eigene Entscheidungen mit Optionen und Risiko
  - offene Gerätetests
  - Ergebnis des Spikes
- [ ] **Simulator und DerivedData dieser Arbeitskopie löschen:**
  ```zsh
  source scripts/test-env.sh
  xcrun simctl delete "Tagwerk Tests $TAGWERK_CHECKOUT_KEY" 2>/dev/null
  rm -rf "$TAGWERK_TEST_DERIVED"
  ```
- [ ] Commit `docs: record the focus timer and effort work`. Kein PR, kein Merge, kein Board. Das macht die Hauptsitzung nach der Prüfung.

---

## Offene Fragen, die der Plan bewusst nicht entscheidet

- Werden zukünftige Blöcke einer erledigten Aufgabe (an späteren Tagen) gelöscht? Heute bleiben sie, und #162 ändert das nicht.
- Kürzen auf 5 min abgerundet oder minutengenau?

## Designpunkte für #188

- **Fokus-Timer-Blatt:** Aufbau (große Restzeit, Ring oder Balken), Platz von Aufgabe und Runde, Knöpfe Pause, Überspringen und Beenden, Wortlaut der Abbruch-Rückfrage.
- **Einstieg:** Wo „Fokus starten“ sitzt (Blockblatt, Aufgabeneditor, Kontextmenü im Ablauf, „Erfassen“) und ob die laufende Sitzung als Leiste über den Tabs sichtbar bleibt.
- **Live Activity:** Sperrbildschirm-Layout, Dynamic Island compact/minimal/expanded, Zustand „Phase vorbei“ mit „Erledigt / Weiter / Verschieben“.
- **Belohnung:** Motiv der Sammlung (eigene Gestaltung, keine Anlehnung an Forest), fünf Wachstumsstufen, Aussehen eines gewelkten Stücks, Ansicht der Sammlung (Woche, Monat, gesamt).
- **Einstellungen „Fokus-Timer“:** Aufteilung von Pomodoro-Werten, App-Sperre und Ausnahmen.
- **Mitteilung zum Phasenende:** Wortlaut und ob sie in Ruhezeiten kommt.
- **Wochenrückblick „Schätzung und Ist“:** Darstellung (Text, Balken, Pfeile), Gruppierung nach Quelle oder Label, Umgang mit zu wenigen Messungen.
- **Gekürzter Block:** ob im Ablauf sichtbar ist, dass er früher beendet wurde (z. B. Häkchen, Marke).

## Gerätetests

1. **Live Activity:**
   - Start aus einem Block, App schließen.
   - Countdown auf Sperrbildschirm und Dynamic Island.
   - Nach Phasenende Zustand „Phase vorbei“, Knöpfe „Erledigt / Weiter / Verschieben“ ohne App-Öffnen.
   - Aufgabe danach erledigt bzw. auf morgen.
2. **Pomodoro 25/5 × 4 im Hintergrund:** Mitteilung zu jedem Phasenende, korrekte Phase beim Öffnen, Fokus-Zeit = 100 min.
3. **App vom System beendet** (in den App-Umschalter wischen) während einer Sitzung: Beim Öffnen läuft sie weiter, keine zweite Live Activity.
4. **Abbruch nach 10 min:** Stück welkt. Abbruch nach 30 s: kein Stück.
5. **Früh abgehakt:**
   - Ablauf: Block 60 min, nach 20 min abgehakt.
   - Erwartet: Block in „Planen“ und in Apple Kalender bis zum Abhakzeitpunkt, Kapazität wieder frei. „Rückgängig“ stellt den Block wieder her.
6. **Spät abgehakt:** Block am Vormittag, Abhaken am Abend: Block unverändert, Stichprobe 60 min.
7. **Wochenrückblick:** Nach mindestens drei Messungen in einer Quelle erscheint die Abweichung, mit zwei Messungen „Noch zu wenige Messungen“.
8. **KI-Planung:** Planungs-Diagnose (`PlanningDiagnostics`) zeigt `expectedMinutes` nur bei vorhandenen Messungen. Nach dem Ausschalten des Schalters fehlt das Feld.
9. **Nur bei positivem Spike: App-Sperre**
   - Freigabe-Dialog erscheint, Ausnahmen-Auswahl wird gespeichert.
   - Während der Arbeitsphase sind andere Apps gesperrt, in der Pause frei.
   - Nach Abbruch oder Ende ist nichts mehr gesperrt.
   - Nach erzwungenem Beenden ist beim nächsten Start nichts mehr gesperrt.
10. **Drüberinstallieren über den Stand vor P3:** Store öffnet, Einstellungen haben die Standardwerte.
