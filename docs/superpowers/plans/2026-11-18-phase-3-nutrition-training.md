# Phase 3: Ernährung, Trinken und Training – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ein Tab „Erfassen“, in dem Essen (Text/Foto → ChatGPT-Schätzung mit Spannen, oder manuell), Wasser (ein Tipp) und Trainings (manuell, plus Health-Trainings anderer Quellen) erfasst und gegen Tagesziele angezeigt werden. Eigene Einträge liegen in SwiftData und werden nach Apple Health gespiegelt.

**Architecture:**
- Reine Regeln in `TagwerkCore` (`Intake.swift`, `IntakeFormat.swift`): Mahlzeitentyp, Summen, Spannen, Darstellung, Wochenzähler, Überschneidung, Wiederholvorschläge, Prüfung der KI-Antwort.
- Neues Paket `HealthBridge`: Wertetypen, reines Mapping (Sync-Kennungen, Metadaten), Protokoll `HealthStoring` und die HealthKit-Implementierung `HealthKitStore`.
- App: SwiftData-Modelle und `IntakeStore`; `HealthMirror` (spiegelt, holt nach, Lösch-Warteschlange); `MealEstimator` (ChatGPT, json_schema, Einwilligung); `CaptureModel` (Tab-Zustand); Views unter `Tagwerk/Capture/`.
- AIKit: Eingabefall für Bilder (`input_image`, data-URL, Format aus dem Spike).

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, HealthKit, PhotosUI, AIKit (ChatGPT Responses), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-11-18-phase-3-design.md`; Mockup `docs/superpowers/mockups/2026-11-18-phase-3-nutrition-training-mockups.html` (E1a–E8a, vorläufig). Hauptdesign §2, §6, §7, §9.

**Nicht in diesem Plan:** Fortschritt/Wochenrückblick, Zeile im Kopf von „Planen“, Widget, Siri/Assistent-Erfassen (Phase 4); Getränkearten; Nahrungsdaten anderer Apps; Apples lokales Modell.

## Global Constraints

- Alle Global Constraints aus 2b-1 bis 2b-3 gelten weiter (u. a. §8.4: kein KI-Aufruf ohne Nutzeraktion; Hintergrund-Refresh ruft weder KI noch Erfassen auf).
- **Keine Gesundheitsdaten in Logs:** keine Titel, Mengen, kcal, Trainingsarten in `Logger`/`print`.
- **Health nur auf Tippen:** `requestAuthorization` nur aus der Health-Karte oder der Zugriffszeile. Beim Start wird Health nur gelesen, wenn schon gefragt wurde.
- **Lokal zuerst:** Speichern, Bearbeiten und Löschen gelingen lokal immer; Health-Fehler setzen nur `healthSynced = false` bzw. füllen die Lösch-Warteschlange.
- **Tests ohne echtes HealthKit:** App-Tests nutzen `FakeHealthStore`; `AppEnvironment` bekommt den Store injiziert (`health:`), Standard ist `HealthKitStore`.
- **Bilder:** vor dem Senden auf lange Kante ≤ 1.024 px und JPEG (Qualität 0,7) neu kodiert; nie gespeichert; nie in Chat-Verläufen.
- Neue SwiftData-Attribute mit Standardwert; neue Modelle in `ModelContainerFactory.schema`.
- Tab-Wert „Erfassen“ = 3 (bestehende Werte 0/1/2 bleiben).
- Code-Kommentare und Logs auf Englisch; UI-Texte aus dem Mockup (Abschnitt „Texte“).

## Review Focus

1. Ein Health-Fehler verliert nie einen lokalen Eintrag; Löschen offline landet in der Warteschlange und wird nachgeholt.
2. Eigene Samples zählen beim Lesen nie doppelt (Metadaten `TagwerkEntry` und eigene Quelle).
3. Ohne Einwilligung bzw. mit ausgeschaltetem Schalter geht kein Aufruf an ChatGPT; gesendet werden nur Text und Bild.
4. Schätzungen erscheinen nie ohne „~“ bzw. Spanne; manuelle Werte ohne „~“.
5. Bearbeiten erhöht die Sync-Version und ersetzt das Health-Sample, statt ein zweites anzulegen.

---

### Task 1: Regeln in `TagwerkCore` (`Intake.swift`, `IntakeFormat.swift`)

**Files:** Create `app/Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift`, `IntakeFormat.swift`; Test `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/IntakeTests.swift`.

Typen: `MealKind` (breakfast, lunch, dinner, snack; `germanName`; `static func forTime(_ date:, calendar:)`), `MealItem` (name, amount, factor, kcalMin, kcal, kcalMax, protein, carbs, fat; skaliert mit `factor`), `MealOrigin` (estimated, manual), `MealEntryValue` (id, date, kind, title, items, origin), `DrinkEntryValue`, `WorkoutActivity` (strength, running, cycling, walking, hiking, swimming, yoga, hiit, other; `germanName`), `WorkoutValue` (id, activity, start, minutes, kilocalories, sourceName?, isOwn), `DayIntake` (kcal, kcalMin, kcalMax, protein, carbs, fat, waterMilliliters, hasEstimate), `IntakeRules` (`dayIntake(meals:drinks:)`, `workoutsCountingThisWeek(_:now:calendar:)`, `overlaps(_:with:)`, `repeatSuggestions(meals:hidden:filter:now:calendar:limit:)`), `MealEstimateOutput` (Decodable aus JSON der KI; `normalized()` nach Spec §5.5), `IntakeFormat` (Texte Spec §5.3).

- [ ] **Step 1: Tests schreiben (rot)**
  - `mealKind_byTime` (05:00 Frühstück, 10:29 Frühstück, 10:30 Snack, 12:00 Mittagessen, 18:00 Abendessen, 22:00 Snack, 04:59 Snack)
  - `item_factorScalesValues` (×1,5)
  - `dayIntake_sumsMealsAndWater_rangeFromMinMax`, `dayIntake_manualOnly_hasNoEstimate`
  - `weekCount_mondayToSunday_minimum10Minutes` (Sonntag zählt, nächster Montag nicht, 9 min nicht)
  - `overlap_detected_adjacentNot`
  - `repeatSuggestions_rankByCountThenRecency_hiddenExcluded_filterByTitle_limit8_last30Days`
  - `estimate_decode_normalizes` (min > mittel getauscht/geklemmt, negative → 0, > 5.000 verworfen, > 20 Posten gekürzt), `estimate_emptyItems_isNothingRecognized`
  - `format_estimate_tilde_range` („~520 kcal“, „wahrscheinlich zwischen 410 und 550 kcal“, „410–550“), `format_manual_noTilde`, `format_remaining` („noch ~990“, „120 über Ziel“, manuell „noch 990“), `format_liters` („1,2 l“), `format_rounding10`
- [ ] **Step 2: Tests laufen lassen, Fehlschlag prüfen** (`cd app/Packages/TagwerkCore && xcodebuild test -scheme TagwerkCore -destination 'platform=iOS Simulator,name=iPhone 18 Pro'`)
- [ ] **Step 3: Implementieren**
- [ ] **Step 4: Tests grün**
- [ ] **Step 5: Commit** `feat: add intake rules for meals, water and workouts`

### Task 2: Bild-Eingabe in AIKit

**Files:** Modify `app/Packages/AIKit/Sources/AIKit/ResponseItem.swift`; Test `ChatGPTClientTests.swift` (oder neue Datei `InputItemTests.swift`).

`InputItem.userImage(text: String, jpeg: Data)` → `{"role":"user","content":[{"type":"input_text","text":…},{"type":"input_image","image_url":"data:image/jpeg;base64,…"}]}` (Text weggelassen, wenn leer).

- [ ] **Step 1:** Test `userImage_requestJSON_hasInputImageDataURL`, `userImage_emptyText_onlyImage`, `existingCases_decodeUnchanged` (gespeicherter JSON-Verlauf von `.user` bleibt dekodierbar).
- [ ] **Step 2:** rot · **Step 3:** implementieren · **Step 4:** grün
- [ ] **Step 5: Commit** `feat: send images to ChatGPT`

### Task 3: Paket `HealthBridge`

**Files:** Create `app/Packages/HealthBridge/Package.swift`, `Sources/HealthBridge/HealthEntries.swift`, `HealthMapping.swift`, `HealthStoring.swift`, `HealthKitStore.swift`; Tests `Tests/HealthBridgeTests/HealthMappingTests.swift`; `app/project.yml` (Paket, Abhängigkeit).

- `HealthMeal` (id, date, version, kcal, protein, carbs, fat, estimated), `HealthDrink` (id, date, version, milliliters), `HealthWorkout` (id, version, activity: String, start, end, kilocalories?), `ForeignWorkout` (uuid, activity, start, end, kilocalories?, sourceName).
- `HealthMapping`: `syncIdentifier(kind:id:nutrient:)` → `tagwerk.meal.<UUID>.energy` usw.; `metadata(id:version:estimated:)` mit `HKMetadataKeySyncIdentifier`, `HKMetadataKeySyncVersion`, `TagwerkEntry`, `TagwerkEstimated`; `quantities(for: HealthMeal)` → nur Werte > 0; `workoutActivityType(_:)` Zuordnung; `isOwn(metadata:)`.
- `HealthStoring` (Sendable, async): `isAvailable`, `writeStatus() -> HealthWriteStatus` (`.notDetermined`, `.authorized`, `.partial([String])`, `.denied`, `.unavailable`), `requestAuthorization()`, `save(_ meal)`, `save(_ drink)`, `save(_ workout)`, `deleteEntry(kind:id:)`, `foreignWorkouts(in: DateInterval)`.
- `HealthKitStore`: echte Umsetzung; Workouts über `HKWorkoutBuilder` (Bearbeiten = alte per Sync-Kennung löschen, neu anlegen); Lesen per `HKSampleQueryDescriptor`, eigene per `isOwn` und `HKSource.default()` gefiltert; `errorNoData` = leer.

- [ ] **Step 1:** Tests `syncIdentifier_format`, `metadata_containsSyncKeysAndMarker`, `quantities_skipZero`, `activityMapping_allCases`, `isOwn_byMarker`
- [ ] **Step 2:** rot · **Step 3:** implementieren (inkl. `HealthKitStore`, nur kompiliert, nicht unit-getestet) · **Step 4:** grün
- [ ] **Step 5:** `project.yml`: Paket `HealthBridge`, Entitlements `app/Tagwerk/Tagwerk.entitlements` (`com.apple.developer.healthkit: true`), `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, `NSCameraUsageDescription` (Texte aus dem Mockup). `xcodegen`, Build.
- [ ] **Step 6: Commit** `feat: add HealthBridge for Apple Health`

### Task 4: Persistenz, `IntakeStore` und `HealthMirror`

**Files:** Create `app/Tagwerk/Capture/IntakeRecords.swift` (`MealRecord`, `DrinkRecord`, `WorkoutRecord`, `HiddenMealSuggestion`, `PendingHealthDeletion`), `IntakeStore.swift`, `HealthMirror.swift`; Modify `AppSettings.swift` (Ziele, Einwilligung, Schalter, Karte), `ModelContainerFactory.swift`; Test `TagwerkTests/IntakeStoreTests.swift`, `HealthMirrorTests.swift`, Fake `TagwerkTests/Fakes/FakeHealthStore.swift`.

- `IntakeStore` (MainActor, ModelContext): `meals(on:)`, `drinks(on:)`, `workouts(on:)`, `workouts(in:)`, `recentMeals(days:)`, `add…`, `update…` (erhöht `healthVersion`, setzt `healthSynced = false`), `delete…` (gibt Wert für „Widerrufen“ zurück), `restore…`, `hide(title:)`.
- `HealthMirror`: `sync(_ id)` nach jeder Änderung; `syncPending()` (alle `healthSynced == false` + Warteschlange) bei Tab-Öffnen, nach Verbinden, im Vordergrund; nur wenn `writeStatus` nicht `.notDetermined`/`.unavailable`. Löschen: Health-Löschung versuchen, bei Fehler `PendingHealthDeletion`.

- [ ] **Step 1:** Tests: `addMeal_thenDay_returnsIt`, `update_bumpsVersion_marksUnsynced`, `delete_restore_roundTrip`, `recentMeals_last30Days`; Mirror: `save_success_marksSynced`, `save_failure_keepsLocal_unsynced`, `syncPending_retries`, `delete_failure_queues_thenRetried`, `notDetermined_sendsNothing`, `update_sendsHigherVersion`
- [ ] **Step 2:** rot · **Step 3:** implementieren · **Step 4:** grün (`app/test-all.sh`)
- [ ] **Step 5: Commit** `feat: store meals, water and workouts and mirror them to Health`

### Task 5: `MealEstimator`

**Files:** Create `app/Tagwerk/Capture/MealEstimator.swift`, `ImageDownscaler.swift`; Test `TagwerkTests/MealEstimatorTests.swift`.

- `estimate(text:image:) async throws -> MealEstimateOutput` über `ResponseStreaming` mit `json_schema` „meal_estimate“, Modell über `AIEnvironment.selectedModel()`.
- Gate: wirft `.consentMissing` ohne Einwilligung, `.disabled` bei ausgeschaltetem Schalter – **vor** jedem Aufruf (Test: null Anfragen).
- Eingabe: nur `.user(text)` bzw. `.userImage(text, jpeg)`; Anweisung fordert deutsche Posten, Spanne, keine Erfindung bei Unklarheit.
- Fehler → Texte: `.network`, Zeitüberschreitung/Server/`incomplete`, `.notSignedIn`/`.invalidUser` („Anmeldung abgelaufen“), `.usageLimit`, `refusal`/leer („nichts erkannt“).
- `ImageDownscaler.jpeg(from: UIImage, maxEdge: 1024)`.

- [ ] **Step 1:** Tests `noConsent_sendsNothing`, `disabled_sendsNothing`, `textOnly_sendsUserText_withSchema`, `image_sendsUserImage`, `decodes_and_normalizes`, `emptyItems_nothingRecognized`, `errors_mapToTexts`, `downscale_longEdge1024`
- [ ] **Step 2:** rot · **Step 3:** implementieren · **Step 4:** grün
- [ ] **Step 5: Commit** `feat: estimate meals with ChatGPT`

### Task 6: `CaptureModel`

**Files:** Create `app/Tagwerk/Capture/CaptureModel.swift`; Test `TagwerkTests/CaptureModelTests.swift`.

- Zustand: `day`, `canGoForward` (nur bis heute), `intake: DayIntake`, `meals`, `water`, `workouts` (eigene + fremde, sortiert), `weekCount`, `goals`, `healthStatus`, `showsHealthCard`, `undo` (Text + Aktion, 4 s).
- Aktionen: `addWater(ml)`, `saveMeal(_)`, `repeatMeal(_)` (jetzt, Typ nach Uhrzeit), `saveWorkout(_)`, `delete(_)`, `undoLast()`, `connectHealth()`, `dismissHealthCard()`, `reload()` (liest fremde Workouts nur bei Status ≠ notDetermined/unavailable), `overlapWarning(for:)`, `lastWorkoutDefaults`.
- [ ] **Step 1:** Tests `addWater_updatesTotal_andUndo`, `repeatMeal_usesNow_andKindByTime`, `delete_thenUndo_restores`, `foreignWorkouts_merged_ownFiltered`, `weekCount_includesForeign`, `cannotGoPastToday`, `healthCard_hiddenWhenConnectedOrDismissed`, `reload_notDetermined_readsNothing`
- [ ] **Step 2:** rot · **Step 3:** implementieren · **Step 4:** grün
- [ ] **Step 5: Commit** `feat: add capture model for the Erfassen tab`

### Task 7: Tab „Erfassen“ und Blätter

**Files:** Create `app/Tagwerk/Capture/CaptureView.swift`, `MealSheet.swift`, `DrinkSheet.swift`, `WorkoutSheet.swift`, `MealConsentSheet.swift`, `HealthCard.swift`, `CameraPicker.swift`; Modify `RootView.swift` (Tab „Erfassen“, Wert 3, vor „Einstellungen“), `AppEnvironment.swift` (`health:`, `intake`, `healthMirror`, `capture`, `mealEstimator`), `TagwerkApp.swift` (`syncPending` bei `.active`).

- Nach Mockup E1a, E2a, E3a, E4a, E5a, E8a und den Texten. Foto: `PhotosPicker` + Kamera (`UIImagePickerController`, nur wenn `isSourceTypeAvailable(.camera)`).
- [ ] **Step 1:** Test `rootTabs_captureValueIs3` ist nicht sinnvoll testbar; stattdessen UI-freie Logik liegt in Task 6. Hier Build + Simulator-Sichtprüfung (Demo-Daten).
- [ ] **Step 2:** implementieren · **Step 3:** `app/test-all.sh` grün
- [ ] **Step 4: Commit** `feat: add the Erfassen tab`

### Task 8: Einstellungen, Demo-Daten, Abschluss

**Files:** Create `app/Tagwerk/Settings/CaptureSettingsView.swift`; Modify `SettingsView.swift` (Zeile „Erfassen“, Zeile „Health“ unter „Zugriff“), `DemoData.swift` (Mahlzeiten, Wasser, Training; Fake-Health mit Watch-Training im Simulator bei `-TagwerkDemoData`), `DemoAITransport.swift` (Antwort für `meal_estimate`); Spec Nachtrag §11 „Abweichungen“.

- [ ] **Step 1:** Test `demoTransport_answersMealEstimate` (Schema-Name → gültige Schätzung), Settings-Zusammenfassung `captureSummary` („2.300 kcal · 2,0 l · 3×“) in `IntakeFormat` testen.
- [ ] **Step 2:** rot · **Step 3:** implementieren · **Step 4:** `app/test-all.sh` grün
- [ ] **Step 5:** Simulator-Prüfung mit `-TagwerkDemoData -TagwerkDemoAI` (falls Simulator frei)
- [ ] **Step 6: Commit** `feat: add capture settings and demo data`
