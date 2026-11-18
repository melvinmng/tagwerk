# Phase 4: Widget, Siri-Kurzbefehle und Wochenrückblick – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Die App liefert:
- Widgets „Als Nächstes“ und „Heute“, die einen Snapshot aus dem App-Group-Container lesen.
- Vier App Intents mit deutschen Siri-Phrasen.
- Einen Wochenrückblick als Unterseite von „Erfassen“.
- Die Kalorien-/Wasser-Zeile im Kopf von „Planen“.
- Ein Install-Skript, das App und Extension signiert und bei Fehlern auf den letzten guten Commit zurückfällt.

**Architecture:**
- **Reine Logik in `TagwerkCore`:**
  - `WidgetSnapshot.swift`: Snapshot, Builder, `upcoming(at:)`, Timeline-Zeitpunkte, Veraltung.
  - `AppRoute.swift`: Deeplinks.
  - `WeekReview.swift`: Wochenrückblick.
  - `IntakeFormat.planHeaderLine`: Kopfzeile in „Planen“.
- **App:**
  - `TodaySummary`: Tagessummen heute.
  - `WidgetSnapshotWriter`: Verzeichnis und Reload injizierbar, schreibt nur bei Änderung.
  - `AppRouter`: Routen aus Benachrichtigung und Deeplink.
  - `IntentServices` und die Intents unter `Tagwerk/Intents/`.
  - `WeekReviewModel` und `WeekReviewView` unter `Tagwerk/Capture/`.
- **Neues Target `TagwerkWidget`** (app-extension, WidgetKit): linkt nur `TagwerkCore`.
- **`RemindersKit`:** erledigte Erinnerungen eines Zeitraums.
- **`LocalTask.completedAt`**.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), WidgetKit, AppIntents, SwiftData, EventKit, Swift Testing, zsh.

**Spec:** `docs/superpowers/specs/2026-11-18-phase-4-design.md`. Mockup `docs/superpowers/mockups/2026-11-18-phase-4-comfort-mockups.html` (vorläufig).

**Nicht in diesem Plan:** siehe Spec §2 (Nicht-Ziele).

## Global Constraints

- Alle Constraints aus 2b-1 bis Phase 3 gelten weiter.
  - **§8.4:** kein KI-Aufruf ohne Nutzeraktion. Widget-Provider, Intents und Deeplinks lösen nie eine Schätzung oder einen Netzabruf aus.
  - **Keine Gesundheitsdaten in Logs.** Der Snapshot-Schreiber loggt höchstens Fehlercodes.
- **Kein Store-Umzug.** `ModelContainerFactory.make` bleibt unverändert. Pro Prozess gibt es genau einen `ModelContainer`. Intents nutzen den Container der App.
- **Gruppen-ID** nur aus dem Info.plist-Schlüssel `TagwerkAppGroup`. Fehlt der Container, wird still übersprungen.
- **Neue SwiftData-Attribute** bekommen einen Standardwert oder sind optional.
- Accessory-Widgets zeigen nie Ernährung. Titel sind im Widget `.privacySensitive()`.
- `supportedModes` statt `openAppWhenRun`. Jede Phrase enthält `\(.applicationName)`.
- Neue Swift-Dateien → `xcodegen` in `app/`. Vorher prüfen, dass Xcode das Projekt nicht geöffnet hat.
- Code-Kommentare und Logs auf Englisch, UI-Texte auf Deutsch (Mockup).

## Review Focus

1. Kein Pfad (Widget, Intent, Deeplink) schätzt, ruft das Netz oder liest Health ohne bisherige Anfrage.
2. Der Snapshot enthält bei `widgetShowsNutrition = false` keine Ernährungswerte. Accessory-Widgets zeigen nie Ernährung.
3. Das Skript erneuert die Profile von App und Extension und nimmt das früheste Ablaufdatum. Der Rückfall baut nur einen tatsächlich installierten Commit.
4. Der Intent-Hintergrundstart öffnet keinen zweiten Container.
5. Ein Tageswechsel ohne App-Start zeigt im Widget keine kcal von gestern.

---

### Task 1: Snapshot, Routen und Rückblick-Regeln in `TagwerkCore`

**Files:**
- Create `app/Packages/TagwerkCore/Sources/TagwerkCore/WidgetSnapshot.swift`, `AppRoute.swift`, `WeekReview.swift`.
- Modify `IntakeFormat.swift`.
- Tests `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/WidgetSnapshotTests.swift`, `AppRouteTests.swift`, `WeekReviewTests.swift`.

- [ ] **Step 1: Tests schreiben (rot)**

  **Snapshot**
  - `snapshot_roundTripsJSON`
  - `snapshot_unknownVersion_decodesAsStale`
  - `builder_ordersAllDayFirst_limits12`
  - `builder_withoutNutrition_hasNoIntake`
  - `builder_intakeOnlyToday`
  - `upcoming_includesRunning_skipsEnded`
  - `upcoming_emptyToday_returnsTomorrowFirst`
  - `upcoming_ignoresAllDay`
  - `timelineDates_startsEndsAndMidnight_max30`
  - `isStale_after3Days`
  - `todayIntake_afterMidnight_isNil` (kein kcal von gestern)

  **Routen**
  - `route_parsesKnownPaths`
  - `route_rejectsUnknownSchemeHostAndPath`
  - `route_ignoresQueryParameters`

  **Rückblick**
  - `review_daysWithoutMeals_areNil`
  - `review_averageOnlyDaysWithMeals`
  - `review_waterGoalDays`
  - `review_workoutsCount10MinMinimum_sumsMinutes`
  - `review_currentWeek_futureDays`
  - `review_completedCount_inWeekOnly`
  - `review_proteinOnlyWhenGoalEnabled`

  **Kopfzeile in „Planen“**
  - `planHeaderLine_estimatedTilde`
  - `planHeaderLine_manualNoTilde`
  - `planHeaderLine_nilWhenNoEntries`
- [ ] **Step 2:** Tests laufen lassen (`app/test-all.sh` oder Paket allein), Fehlschlag prüfen.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** Tests grün.
- [ ] **Step 5:** Commit `feat: add widget snapshot, deep link routes and week review rules`.

### Task 2: Kopfzeile in „Planen“ und Einstellungen

**Files:**
- Create `app/Tagwerk/Capture/TodaySummary.swift`, `app/Tagwerk/Planning/IntakeHeaderLine.swift`.
- Modify `AppSettings.swift` (`showsIntakeInPlan`, `widgetShowsNutrition`), `DayHeader.swift` (bzw. `PlanView`), `CaptureSettingsView.swift`.
- Test `app/TagwerkTests/TodaySummaryTests.swift`.

`TodaySummary` (`@MainActor`) liest die Tagessumme von heute aus `IntakeStore` und `IntakeRules`, unabhängig vom angezeigten Tag in `CaptureModel`. Nach dem Erfassen wird sie neu berechnet.

- [ ] **Step 1:** Tests (rot):
  - `summary_countsTodayOnly_notDisplayedDay`
  - `summary_updatesAfterAddWater`
  - `headerLine_hiddenWhenSettingOff`
  - `headerLine_hiddenWhenNoEntriesToday`
- [ ] **Step 2–4:** rot → implementieren → grün. Tippen auf die Zeile setzt `requestedTab = 3`. Die Schalter stehen unter Einstellungen › Erfassen.
- [ ] **Step 5:** Commit `feat: show today's calories and water in the plan header`.

### Task 3: Snapshot-Schreiber und Auslöser

**Files:**
- Create `app/Tagwerk/Widget/WidgetSnapshotWriter.swift`, `app/Tagwerk/Widget/AppGroup.swift`.
- Modify `AppEnvironment.swift` (Verdrahtung, Entprellung), `TagwerkApp.swift` (Hintergrund), `BackgroundRefresh.swift` (am Ende schreiben).
- Test `app/TagwerkTests/WidgetSnapshotWriterTests.swift`.

`WidgetSnapshotWriter(directory: URL?, reload: @Sendable () -> Void, now:)`:
- `write(_ snapshot)` schreibt atomar mit `.completeUntilFirstUserAuthentication`.
- Den Reload ruft er nur, wenn sich der Inhalt ohne `createdAt` geändert hat.
- Bei `directory == nil` tut er nichts.

`AppEnvironment.makeSnapshot()` baut aus `planning` (heute + 2 Tage über `PlanStore` bzw. Planungsdaten), `TodaySummary` und den Einstellungen.

- [ ] **Step 1:** Tests (rot):
  - `writer_writesFile_reloadsOnce`
  - `writer_sameContent_noSecondReload`
  - `writer_nilDirectory_noop`
  - `makeSnapshot_withoutNutritionSetting_noIntake`
  - `backgroundRefresh_writesSnapshot`
- [ ] **Step 2–4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit `feat: write the widget snapshot after changes and in the background`.

### Task 4: Deeplinks und gemeinsame Routen

**Files:**
- Create `app/Tagwerk/App/AppRouter.swift`.
- Modify `RootView.swift` (`onOpenURL`, Puffer bis Einrichtung und Daten bereit), `CaptureView.swift` (Blatt per Route öffnen, vorausgefüllter Text bzw. vorausgefülltes Training), `project.yml` (`CFBundleURLTypes` mit Schema `tagwerk`).
- Test `app/TagwerkTests/AppRouterTests.swift`.

`AppRouter` (`@MainActor @Observable`) puffert eine `AppRoute` und optionale Vorbelegung (Mahlzeit-Text, Trainingsart, Dauer). `RootView` schließt offene Blätter und den Chat, wechselt den Tab und reicht die Vorbelegung an `CaptureView` weiter. `NotificationNavigator` bleibt für Aufgaben-Ziele zuständig. Beide lösen dieselbe Aufräum-Logik aus.

- [ ] **Step 1:** Tests (rot):
  - `router_buffersUntilSetupCompleted`
  - `router_mealPrefill_consumedOnce`
  - `router_unknownURL_ignored`
- [ ] **Step 2–4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit `feat: open plan, capture and review from tagwerk:// links`.

### Task 5: App Intents und Siri-Phrasen

**Files:**
- Create `app/Tagwerk/Intents/IntentServices.swift`, `LogWaterIntent.swift`, `LogMealIntent.swift`, `LogWorkoutIntent.swift`, `TodayOverviewIntent.swift`, `TagwerkShortcuts.swift`.
- Modify `TagwerkApp.swift` (`AppDependencyManager.shared.add { services }`).
- Test `app/TagwerkTests/IntentServicesTests.swift`.

`IntentServices` (`@MainActor final class`):
- `logWater(ml:)` legt das Wasser über `IntakeStore` an, stößt die Health-Spiegelung an und schreibt den Snapshot. Es gibt den Antworttext zurück.
- `todayOverview()` liest den Snapshot (Text und die nächsten drei Einträge).
- `openMeal(text:)` und `openWorkout(activity:minutes:)` setzen die Route im `AppRouter`.

Die Intents rufen nur diesen Dienst. Die Logik ist über den Dienst getestet, nicht über `perform()`.

- [ ] **Step 1:** Tests (rot):
  - `logWater_savesDrink_mirrorsAndWritesSnapshot`
  - `logWater_clampsAmount`
  - `logWater_replyHasNoDailyTotal`
  - `todayOverview_fromSnapshot_noNutrition`
  - `todayOverview_staleSnapshot_asksToOpenApp`
  - `openMeal_setsRouteWithText_noEstimatorCall` (der Fake-Responder zählt 0 Aufrufe)
  - `openWorkout_setsRoute`
- [ ] **Step 2–4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit `feat: add Siri shortcuts for water, meals, workouts and today's plan`.

### Task 6: Widget-Extension

**Files:**
- Create `app/TagwerkWidget/TagwerkWidgetBundle.swift`, `SnapshotProvider.swift`, `NextUpWidget.swift`, `TodayWidget.swift`, `WidgetViews.swift`.
- Modify `project.yml`:
  - Target `TagwerkWidget` vom Typ `app-extension`, `NSExtensionPointIdentifier = com.apple.widgetkit-extension`, Bundle-ID `$(TAGWERK_BUNDLE_ID).widget`.
  - Entitlements App Group, Info `TagwerkAppGroup`, in die App eingebettet.
  - App-Entitlements um `com.apple.security.application-groups: [group.$(TAGWERK_BUNDLE_ID)]` ergänzen.
  - Info `TagwerkAppGroup` auch in der App.

Der Provider liest die Datei über `WidgetSnapshot.load(from:)` aus Task 1, ohne Netz, Health oder EventKit. Die Timeline kommt aus `timelineDates`.
- Familien:
  - „Als Nächstes“: `.systemSmall`, `.accessoryRectangular`, `.accessoryInline`.
  - „Heute“: `.systemMedium`.
- Zustände aus W4a.

- [ ] **Step 1:** Die Logik ist in Task 1 getestet. Hier kommt ein Build-Test dazu: `test-all.sh` baut das Scheme mit der Extension. Außerdem prüft ein App-Test, dass die Gruppen-ID in `Info.plist` steht und mit `group.` beginnt.
- [ ] **Step 2–4:** implementieren, `xcodegen`, `test-all.sh` grün.
- [ ] **Step 5:** Commit `feat: add Next Up and Today widgets`.

### Task 7: Install-Skript für App und Extension

**Files:**
- Modify `scripts/refresh-install.sh`, `scripts/install-dev.sh` (nur Hinweise, falls nötig), `scripts/tests/refresh-decisions.zsh`, `scripts/README.md`.

Neue reine Funktionen:
- `is_tagwerk_profile <app-id> <team> <bundle>`
- `earliest_expiry <epoch…>`
- `fallback_commit <last-good or empty> <current>`: gibt nichts zurück, wenn kein Rückfall möglich oder nötig ist.

Laufzeitverhalten:
- Profile beider Bundles räumen, frühestes Ablaufdatum aus App und `PlugIns/*.appex` nehmen.
- Signier-Grep auf die Extension erweitern.
- Nach Erfolg `last-good-commit.<bundle>` schreiben.
- Bei Build- oder Signierfehler einmal den gemerkten Commit bauen und installieren (`git checkout --detach <commit>`, danach zurück auf den Branch), dann mit Hinweis benachrichtigen.

- [ ] **Step 1:** Tests (rot) in `refresh-decisions.zsh`:
  - exakte ID und `.widget` passen, fremde Bundle und Präfix-Täuschung (`<bundle>x`) nicht
  - frühestes Ablaufdatum, leere Eingaben ignoriert
  - Rückfall nur mit gemerktem Commit, der vom aktuellen abweicht
- [ ] **Step 2–4:** rot → implementieren → grün (`zsh scripts/tests/refresh-decisions.zsh`).
- [ ] **Step 5:** Commit `fix: renew the widget profile and fall back to the last installed commit`.

### Task 8: Wochenrückblick

**Files:**
- Modify `RemindersKit` (`ReminderStore.completedReminders(in:listIDs:)`, `EventKitGateway`), `LocalTask.swift` (`completedAt`), `LocalTaskProvider.swift` (setzen/löschen), `CaptureView.swift` (Einstieg R3a).
- Create `app/Tagwerk/Capture/WeekReviewModel.swift`, `WeekReviewView.swift`.
- Tests: `RemindersKit` Fake bzw. `app/TagwerkTests/WeekReviewModelTests.swift`, `LocalTaskProviderTests` (`completedAt`).

`WeekReviewModel`:
- Liest Mahlzeiten, Wasser und eigene Trainings der Woche aus `IntakeStore`.
- Fremde Trainings liest es aus Health nur, wenn `access != .notDetermined` (Regel aus Phase 3).
- Erledigte Erinnerungen kommen aus den gewählten Listen, nur bei Vollzugriff.
- Lokale Aufgaben zählen über `completedAt`.
- Das Ergebnis berechnet `WeekReview.make`.

- [ ] **Step 1:** Tests (rot):
  - `localTask_complete_setsCompletedAt_reopenClears`
  - `review_readsHealthOnlyWhenAsked` (der Fake zählt Lesezugriffe)
  - `review_remindersOnlyWithFullAccess`
  - `review_goBack_onlyPast`
- [ ] **Step 2–4:** rot → implementieren → grün.
- [ ] **Step 5:** Commit `feat: add the weekly review to the capture tab`.

### Task 9: Einstellungen „Siri & Kurzbefehle“, Demo-Daten, Doku

**Files:**
- Modify `CaptureSettingsView.swift` (Abschnitt S2a) und `DemoData.swift` (Snapshot nach dem Seed schreiben; Beispiele für erledigte lokale Aufgaben).
- Modify Spec §12 (Abweichungen) und Hauptdesign §9 (Kalender-Export erledigt).
- Create bzw. aktualisieren: Geräte-Checkliste.

- [ ] Commit `docs: record phase 4 decisions and device checklist`.
