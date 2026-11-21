# Ernährung, Gewicht und Ziele – Implementation Plan (Entwurf)

> **For agentic workers:** Dieser Plan ist ein **Entwurf vor den Entscheidungen des Nutzers**. Kein Task wird begonnen, bevor die Entscheidungen im Abschnitt „Entscheidungen des Nutzers“ getroffen und hier eingetragen sind. Jeder Task nennt unter „Hängt ab von“ die Kürzel, gegen deren Empfehlung er geschrieben ist; fällt eine Entscheidung anders aus, wird der Task vor der Umsetzung überarbeitet. Danach gilt: Task für Task, jeweils mit TDD, Schritte als Checkbox (`- [ ]`).

> **Status:** Stand 21.11.2026. Grundlage ist der Branch `chore/fable-open-items` auf `f3f723b` (zweigt von `main` bei `95f28be` ab). Mockups: `docs/superpowers/mockups/2026-11-21-ernaehrung-gewicht-ziele-mockups.html` (32 Entscheidungen, Kürzel BU, NU, LM, KG, ZI, PV, OR). Nichts davon ist gebaut, nichts am Gerät geprüft. Es gibt noch kein Issue zu diesem Vorhaben.

**Goal:**
- **Tagesbudget:** Der Tageskopf in „Erfassen“ rechnet „Ziel + angerechnete Aktivität − Gegessen = Noch“. Die Aktivitätsenergie kommt als Tagessumme aus Health; in Tagwerk eingetragene Trainings zählen genau einmal.
- **Nährwerte:** Neben Kalorien, Eiweiß, Kohlenhydraten und Fett führt Tagwerk Ballaststoffe und Zucker, zuschaltbar gesättigte Fettsäuren und Salz, mit Zielen, Tagesübersicht und Spiegelung nach Health. Fehlende Angaben bleiben „unbekannt“.
- **Lebensmittel:** Eine eigene Liste „Meine Lebensmittel“ mit Werten je 100 g, je 100 ml oder je Stück; Anlegen durch Tippen, Etikett-Foto oder Übernahme aus einer Schätzung. Strichcode als zweite Ausbaustufe.
- **Gewicht:** Erfassen in „Erfassen“ und im Tagesstart, Spiegelung nach Health, fremde Messungen aus Health, Verlauf mit 7-Tage-Mittel, Ziellinie und Trend.
- **Ziele:** Zielstände mit „gültig ab“ ersetzen die Einzelwerte in den Einstellungen. Ein eigener Chat „Ziele planen“ schlägt Ernährungs- und getrennt Aktivitätsziele als Karten vor; Tagwerk rechnet gegen und warnt. Gesundheitsdaten gehen nur mit eigener Einwilligung, nur als Durchschnitte und nur nach sichtbarer Auswahl an ChatGPT.

**Architecture:**
- **Reine Regeln in `TagwerkCore`:**
  - `NutrientValues` (optionale Werte je Nährwert, Summen mit Abdeckung) und die Erweiterung von `MealItem`, `MealValue`, `DayIntake`.
  - `GoalPlan` (ein Zielstand) und `GoalTimeline` (welcher Stand gilt an welchem Tag).
  - `EnergyBudget` (Budget, angerechnete Aktivität, Makro-Skalierung).
  - `FoodValue` und `FoodPortion` (eigenes Lebensmittel, Menge → Posten).
  - `WeightValue`, `WeightTrend` (Tageswert, 7-Tage-Mittel, Trend, Fortschreibung).
  - `GoalGuard` (Gegenrechnung und Warnungen) und `GoalDataSummary` (das Datenpaket für ChatGPT).
- **`HealthBridge`:** eigene Berechtigungsgruppen neben der bestehenden (`HealthAccessGroup`), Schreiben weiterer Nährwerte, Lesen der Aktivitätsenergie als Tagessumme, Gewicht lesen und schreiben. `HealthShareKind` bleibt unverändert.
- **`AIKit`:** keine Änderung. Die gekürzte Speicherform des Verlaufs und die Einzelbestätigung kommen aus `2026-11-20-decisions-173.md` (Tasks 2 und 4).
- **App:** `GoalStore`, `FoodStore`, `WeightStore` (SwiftData), Erweiterung von `IntakeStore`, `HealthMirror`, `CaptureModel`, `DaySummary`, `MealSheet`, `MealEstimator`; neue Seite `TrendView` („Verlauf und Ziele“) mit Swift Charts; `GoalChatTools` (`ToolHandler` um `AppTools`), `AssistantModel.Context.goals`, `GoalConsentSheet`, `GoalDataSheet`.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, HealthKit, Swift Charts (Systemframework, bisher nicht benutzt), VisionKit nur in Strang E Stufe 2, Swift Testing, XcodeGen. Keine neue Paketabhängigkeit.

**Issues:** noch keines. **Branches (Vorschlag):** je Strang einer, z. B. `feat/nutrition-goal-plans`, `feat/energy-budget`, `feat/nutrients`, `feat/own-foods`, `feat/weight`, `feat/goal-planning`.

## Global Constraints

- **Strings:** Deutsch ist Quellsprache. Jeder neue Text steht deutsch und englisch im Katalog (`Tagwerk/Localizable.xcstrings`, für Pakete im jeweiligen `Resources/Localizable.xcstrings`) und in `scripts/translations/en.json`. Prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs und Testnamen englisch. Anweisungen an ChatGPT für eine Einzelanfrage wie in `MealEstimator`, Anweisungen des Assistenten deutsch (wie `AssistantModel.instructions`).
- **Schätzungen sehen nie exakt aus:** „~“ oder Spanne bleiben (`IntakeFormat`). Ein Budget mit geschätzten Mahlzeiten trägt „~“. Aktivitätsenergie ist immer ein Schätzwert der Geräte; der Text der Aufschlüsselung sagt das.
- **Unbekannt ist nicht 0:** Ein fehlender Nährwert wird nie als 0 gespeichert, angezeigt oder nach Health geschrieben.
- **Health:**
  - Die bestehende Berechtigungsgruppe (`HealthKitStore.shareTypes`, `coreReadTypes`) bleibt unverändert; `HealthShareKind` bekommt keine neuen Fälle. Jede neue Typgruppe hat eigenen Status und eigene Anfrage nach dem Muster der Schritte.
  - Tagessummen kommen aus Statistik-Abfragen, nie aus addierten Einzelwerten.
  - Ohne lesbaren Wert steht „–“, nie 0. Logs enthalten Fehlercodes, nie Werte.
- **Datenschutz:**
  - Gesundheitsdaten (Gewicht, Körperdaten, Ernährungs- und Aktivitätswerte, Ziele) gehen ausschließlich im Chat „Ziele planen“ an ChatGPT, nur mit `goalPlanningConsent`, nur als das in `GoalDataSheet` gezeigte Paket. Der allgemeine Assistent, der Aufgaben-Chat und der Notiz-Chat bekommen keine dieser Funktionen.
  - Die Zusagen in `MealConsentSheet` und `NoteConsentSheet` („Nicht gesendet werden Daten aus Health, deine Ziele …“) bleiben wörtlich wahr.
  - Das Datenpaket steht in keinem Log, keiner Diagnose und nicht im gespeicherten Chatverlauf.
  - Tagwerk gibt keine medizinische Beratung; Einwilligungsblatt und Vorschlagskarte sagen das.
- **SwiftData:** Neue Attribute sind optional oder haben einen Standardwert. Jedes neue Modell steht in `ModelContainerFactory.schema` und hat entweder einen `BackupEntity`-Wert oder einen Eintrag mit Begründung in `BackupCoverage.excluded`. Neue Felder in `BackupDTOs` sind optional.
- **SwiftUI-Falle:** Nie `.sheet`, `.confirmationDialog` oder `.alert` an eine `Section` oder Zeile in `Form`/`List` hängen.
- **Mitteilungen:** Dieser Plan belegt keinen Platz im Mitteilungskontingent.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** `app/test-all.sh` nach jedem Task (`TAGWERK_SKIP_UI_TESTS=1` für Zwischenstände, voller Lauf vor dem letzten Commit jedes Strangs).

## Ausgangslage (Befunde aus dem Quelltext)

Pfade unter `app/`, sofern nicht anders genannt.

1. **Ein Posten kennt vier Nährwerte.** `MealItem` hat `kcalMin`, `kcal`, `kcalMax`, `protein`, `carbs`, `fat` und einen Faktor von 0,5 bis 3 (`Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift:35–99`). Posten liegen als JSON in `MealRecord.itemsData` (`Tagwerk/Capture/IntakeRecords.swift:17`); neue Felder sind über `decodeIfPresent` rückwärtsverträglich (so schon bei `id`, `factor`, `isEstimated`).
2. **Die Tagessumme zählt nur eigene Einträge.** `IntakeRules.dayIntake` summiert Mahlzeiten und Getränke aus Tagwerks Datenbank (`Intake.swift:264–273`); aus Health werden Trainings und Schritte gelesen, keine Ernährung.
3. **Das Kalorienziel ist eine feste Zahl.** `AppSettings.goalKilocalories` (2.300), `goalWaterMilliliters`, `goalProteinGrams` mit `proteinGoalEnabled`, `goalStepsPerDay`, `goalWorkoutMinutesPerWeek` (`Tagwerk/Persistence/AppSettings.swift:55–68`); der Kommentar nennt sie Platzhalter. Eine Geschichte der Ziele gibt es nicht. `goalWorkoutsPerWeek` ist abgelöst und wird nur noch migriert.
4. **Der Tageskopf rechnet „gegessen / Ziel“.** `DaySummary` (`Tagwerk/Capture/CaptureView.swift:343–452`) nutzt `IntakeFormat.remaining` (`IntakeFormat.swift:63`); dieselbe Rechnung steht im Kopf von „Planen“ (`IntakeFormat.planHeaderLine`, `WeekReview.swift:133`), im Widget (`SnapshotIntake`, `WidgetSnapshot.swift:30`) und im Wochenrückblick (`WeekReview.swift`).
5. **Eigene Trainings werden mit Kalorien nach Health geschrieben.** `HealthKitStore.save(_ workout:)` hängt ein `activeEnergyBurned`-Sample mit Tagwerk-Marke an das Training (`Packages/HealthBridge/Sources/HealthBridge/HealthKitStore.swift:108–132`). Wer die Aktivitätsenergie aus Health liest und eigene Trainings addiert, zählt sie doppelt.
6. **Aktivitätsenergie wird nicht gelesen.** Lesen kann `HealthKitStore` nur fremde Trainings (`foreignWorkouts`, `:154`) und Schritte als Tagessumme über `HKStatisticsCollectionQueryDescriptor` (`dailySteps`, `:183`).
7. **Ein neuer Typ in der bestehenden Berechtigungsgruppe hält die Spiegelung an.** `access()` fragt den Status für `shareTypes` (alle Fälle von `HealthShareKind`) und `coreReadTypes` ab (`HealthKitStore.swift:32–35, 48–53`); der Kommentar in Zeile 33–34 warnt davor. `HealthMirror.runOnce` schreibt nichts, solange `access.wasAsked` falsch ist (`Tagwerk/Capture/HealthMirror.swift:60–67`). Schritte haben deshalb eine eigene Gruppe (`stepsAccess`, `requestStepsAuthorization`).
8. **`HealthMapping.nutrientPlan` schreibt Werte über 0 und entfernt den Rest** (`HealthMapping.swift:59–72`). „Unbekannt“ muss dort wie „entfernen“ behandelt werden, darf in Tagwerk aber nicht zu 0 werden.
9. **Die Schätzung hat ein strenges Antwortformat** mit acht Pflichtfeldern je Posten (`Tagwerk/Capture/MealEstimator.swift`, `schema`; `MealEstimateOutput` in `Intake.swift:325`). Gesendet werden nur Text und Foto der Mahlzeit.
10. **Bestehende Einwilligungen schließen Health und Ziele aus.** `MealConsentSheet.swift:14` und `NoteConsentSheet.swift` sagen das wörtlich. Die Felder heißen `mealEstimationConsent`, `noteSuggestionConsent` (`AppSettings.swift:74, 109`).
11. **Der Assistent kennt keine Ernährung.** `AppTools` hat Funktionen für Aufgaben, Termine, Einkauf und Planung (`Tagwerk/AI/AppTools+Definitions.swift`); lesende stehen in `readTools` (`AppTools.swift:13–14`), alle anderen brauchen eine bestätigte Karte. Kontexte: `planning`, `tasks`, `settings`, `capture`, `task` (`AssistantModel.swift:12–19`).
12. **Der Chatverlauf wird vollständig gespeichert**, einschließlich Funktionsergebnissen (`ChatStore.save`, `ChatStore.swift:44`), und ist bewusst nicht in der Sicherung (`Tagwerk/Backup/BackupCoverage.swift:7–14`). `storedForm`, `storableHistory` und `singleConfirmationTools` aus `2026-11-20-decisions-173.md` gibt es im Quelltext dieses Stands nicht.
13. **Mitteilungskontingent:** im Quelltext 50 / 6 / 1 / 7 (`NotificationBudget.swift`), nach `2026-11-20-g2-notizen-routinen.md` künftig 44 / 17 / 1 / 2.
14. **Diagramme:** Im Projekt wird `Charts` nicht importiert; der Wochenrückblick arbeitet mit Balken aus `ProgressView`.
15. **Rezept-Notizen haben keine Nährwerte** (`RecipeNote.swift`, `IngredientLine.swift`).

## Rechenregeln (verbindlich, vorbehaltlich der Entscheidungen)

- **Aktiv des Tages** = Tagessumme der Aktivitätsenergie aus Health + Kalorien eigener Trainings dieses Tages, die noch nicht in Health stehen (`healthSynced == false`) oder deren Kalorien Health nicht annehmen durfte. Ohne lesbare Health-Summe: nur die eigenen Trainings, Anzeige „Aktiv“ mit dem Zusatz, dass Health keine Werte liefert.
- **Angerechnet** = Anteil × Aktiv, auf 10 kcal gerundet; Anteil ∈ {0, 0,5, 0,75, 1}, Voreinstellung 1.
- **Budget** = Grundziel des Tages + Angerechnet. **Noch** = Budget − Gegessen.
- **Makros (BU3c):** Eiweiß und Ballaststoffe bleiben in Gramm. Mit Grundzielen KH₀ und F₀ (Gramm) gilt: Kohlenhydrat-Ziel = KH₀ + Angerechnet × (4 × KH₀) / (4 × KH₀ + 9 × F₀) / 4; Fett-Ziel = F₀ + Angerechnet × (9 × F₀) / (4 × KH₀ + 9 × F₀) / 9. Beispiel: 250 g, 78 g, 520 kcal → 326 g und 102 g.
- **Grundziel** gilt für einen Tag ohne angerechnete Aktivität. Das steht im Einstellungs- und Kartentext.
- **Gewicht des Tages** = früheste Messung des Tages (eigene und fremde). **7-Tage-Mittel** = Mittel der Tageswerte der letzten sieben Tage, ab drei Werten. **Trend** = Differenz der 7-Tage-Mittel im Abstand von 28 Tagen, geteilt durch 4, in kg je Woche; ohne ausreichende Werte „–“.
- **Gegenrechnung (Festlegungen dieses Entwurfs, vom Nutzer zu bestätigen):** Ruheumsatz nach Mifflin und St Jeor (1990): 10 × Gewicht in kg + 6,25 × Größe in cm − 5 × Alter + 5 (männlich) bzw. − 161 (weiblich). Bedarf ohne Training = Ruheumsatz × 1,2. Tagesdefizit für ein Tempo = Tempo in kg je Woche × 7.700 kcal / 7. Warnungen: Grundziel unter dem Ruheumsatz; Tempo über 1 % des Gewichts je Woche; Summe aus 4 × Eiweiß + 4 × Kohlenhydrate + 9 × Fett weicht um mehr als 10 % vom Grundziel ab. Die Formel ist vor dem Bau an der Originalquelle zu prüfen; Faktor 1,2, 7.700 kcal je kg und die Schwellen sind Rechenhilfen, keine medizinischen Grenzwerte.

## Review Focus

1. **Keine Doppelzählung:** Ein in Tagwerk eingetragenes Training zählt vor und nach dem Spiegeln genau einmal. Tests in B3 und C1; Gerätetest mit und ohne Uhr.
2. **Spiegelung läuft weiter:** Nach dem Update fragt `access()` bei bestehenden Nutzern nicht erneut; Mahlzeiten, Wasser und Trainings werden ohne neue Zustimmung gespiegelt. Test in B1.
3. **Unbekannt bleibt unbekannt:** Alte Mahlzeiten haben nach dem Update keine Ballaststoff-Null; Summen nennen die Abdeckung; Health bekommt kein 0-Sample. Tests in A1, B2, D3.
4. **Ein Budget an allen Orten:** Tageskopf, Kopf von „Planen“, Widget und Wochenrückblick zeigen dieselbe Zahl für denselben Tag. Tests in C1–C4.
5. **Vergangene Tage rechnen mit ihrem Zielstand.** Tests in A2 und C4.
6. **Gesundheitsdaten nur im Zielchat:** Ohne `goalPlanningConsent` liefert keine Funktion Werte; der allgemeine Assistent hat die Funktionen nicht; das Paket enthält nur eingeschaltete Gruppen. Tests in G4 und G5.
7. **Gespeicherter Verlauf ohne Datenpaket.** Test in G7.
8. **Karten:** Zielkarten werden einzeln bestätigt; eine Karte mit Warnung verlangt eine zweite Bestätigung; nach „Übernehmen“ existiert genau ein neuer Zielstand. Tests in G6.

---

## Strang A: Grundlagen (Regeln und Datenmodell)

### Task A1: `NutrientValues` und erweiterte Posten

**Hängt ab von:** NU1b, NU4b.

**Files:**
- Create: `Packages/TagwerkCore/Sources/TagwerkCore/NutrientValues.swift`, Tests `NutrientValuesTests.swift`
- Modify: `Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift` (`MealItem`, `MealValue`, `DayIntake`, `IntakeRules.dayIntake`, `MealEstimateOutput`), `IntakeFormat.swift`

- [ ] **Step 1: Tests.** `mealItem_decodesOldJSONWithoutNewFields`, `sum_ignoresUnknownAndCountsCoverage`, `sum_allUnknown_isNil`, `scaled_keepsUnknown`, `format_minimumWithCoverage` („mind. 14 g · 2 von 3 Mahlzeiten“), `salt_fromSodium`.
- [ ] **Step 2:** `enum Nutrient { fiber, sugar, saturatedFat, salt }` mit `displayName`, Einheit und der Angabe, ob Ziel oder Obergrenze. `MealItem` bekommt `fiber`, `sugar`, `saturatedFat`, `salt` als `Double?` (`decodeIfPresent`), dazu `total…`-Werte mit Faktor.
- [ ] **Step 3:** `DayIntake` bekommt je Nährwert `NutrientSum(value: Double?, known: Int, total: Int)`; `IntakeRules.dayIntake` füllt sie. Bestehende Initialisierer bleiben mit Standardwerten nutzbar.
- [ ] **Step 4:** `IntakeFormat.nutrient(_:goal:)` für Zeilenwerte samt Abdeckungstext; Katalogeinträge.
- [ ] **Step 5:** Commit `feat: add optional fibre, sugar, saturated fat and salt to meal items`.

### Task A2: Zielstände `GoalPlan` und `GoalTimeline`

**Hängt ab von:** ZI5b, ZI4b, BU1b.

**Files:**
- Create: `Packages/TagwerkCore/Sources/TagwerkCore/GoalPlan.swift`, Tests; `Tagwerk/Capture/GoalRecords.swift` (`GoalPlanRecord`), `Tagwerk/Capture/GoalStore.swift`, Tests
- Modify: `Tagwerk/Persistence/ModelContainerFactory.swift`, `Tagwerk/Persistence/AppSettings.swift` (neues Feld `goalPlansMigrated`, `activityCreditPercent` = 100), `Tagwerk/App/AppEnvironment.swift`

- [ ] **Step 1: Tests.** `timeline_planForDay_picksLatestNotAfter`, `timeline_beforeFirstPlan_usesFirst`, `migration_createsOnePlanFromSettings` (Eiweiß nur bei `proteinGoalEnabled`), `migration_runsOnce`, `store_adopt_sameDayReplaces`.
- [ ] **Step 2:** `GoalPlan`: `validFrom: PlanDay`, `kcal`, `proteinGrams?`, `carbsGrams?`, `fatGrams?`, `fiberGrams?`, `sugarLimitGrams?`, `waterMilliliters`, `stepsPerDay`, `workoutMinutesPerWeek`, `activeKcalPerDay` (0 = aus), `targetWeightKg?`, `paceKgPerWeek?`, `origin` (`manual`, `assistant`), `note`.
- [ ] **Step 3:** `GoalPlanRecord` (SwiftData, alle Felder mit Standardwert) und `GoalStore` (`plans()`, `current(on:)`, `adopt(_:)`, `delete(_:)`). Einmalige Übernahme der heutigen Einstellungen als erster Zielstand mit `validFrom` = Tag der ältesten Mahlzeit oder heute.
- [ ] **Step 4:** Die bisherigen Felder in `AppSettings` bleiben im Schema (Attribute werden nie entfernt) und werden bei jeder Übernahme mitgeschrieben, bis alle Leser umgestellt sind (C1–C4); danach liest niemand mehr direkt.
- [ ] **Step 5:** Commit `feat: store goals as dated goal plans`.

### Task A3: `EnergyBudget`

**Hängt ab von:** BU1b, BU3c.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/EnergyBudget.swift`, Tests.

- [ ] **Step 1: Tests.** `credited_roundsToTens`, `credited_shareZero_isZero`, `budget_exampleDay` (2.300, 520, 1.340 → 2.820, 1.480), `macros_proteinFixed_restScales` (250/78/520 → 326/102), `macros_withoutCarbOrFatGoal_staysNil`, `remaining_over_isNegativeAndMarked`, `activeUnknown_usesOwnWorkoutsOnly`.
- [ ] **Step 2:** `struct ActiveEnergy { healthKcal: Double?; unsyncedOwnKcal: Double }`, `EnergyBudget.make(plan:active:creditPercent:intake:)` mit `base`, `credited`, `budget`, `remaining`, `scaledCarbs`, `scaledFat`, `isEstimated`.
- [ ] **Step 3:** `IntakeFormat.budgetRemaining` („noch ~1.480“, „~120 über Budget“) und `planHeaderLine` mit Budget (alte Signatur bleibt bis C4).
- [ ] **Step 4:** Commit `feat: add the daily energy budget rules`.

### Task A4: Sicherung

**Hängt ab von:** A2; wird in E1 und F1 je Modell ergänzt.

**Files:** Modify `Tagwerk/Backup/BackupDTOs.swift`, `BackupService.swift`, `BackupCoverage.swift`; Tests der Sicherung.

- [ ] **Step 1: Tests.** `backup_roundTripsGoalPlans`, `backup_oldFileWithoutGoalPlans_decodes`, Vollständigkeitstest bleibt grün.
- [ ] **Step 2:** `GoalPlanBackup`; neue Einstellungsfelder optional.
- [ ] **Step 3:** Commit `feat: include goal plans in the backup`.

---

## Strang B: HealthBridge

### Task B1: Berechtigungsgruppen

**Hängt ab von:** NU1b, BU2a, KG2a, KG4b.

**Files:** Modify `HealthEntries.swift`, `HealthStoring.swift`, `HealthKitStore.swift`, `HealthMapping.swift`; `Tagwerk/Capture/DemoHealthStore.swift`, Test-Fakes; `app/project.yml`, `Tagwerk/Info.plist`, `Tagwerk/InfoPlist.xcstrings`.

- [ ] **Step 1: Tests.** `coreTypes_unchanged` (Menge der Typen in `shareTypes` und `coreReadTypes` ist exakt die heutige), `group_status_notAskedThenAsked`, `groupTypes_disjointFromCore`.
- [ ] **Step 2:** `enum HealthAccessGroup { moreNutrients, activeEnergy, body }` mit eigenen Typmengen (`moreNutrients`: Ballaststoffe, Zucker, gesättigte Fettsäuren, Natrium, schreiben; `activeEnergy`: `activeEnergyBurned` lesen; `body`: `bodyMass`, `bodyFatPercentage` lesen und schreiben). `groupAccess(_:)` und `requestAuthorization(for:)` nach dem Muster von `stepsAccess`. Schreibstatus je Typ über `authorizationStatus(for:)`.
- [ ] **Step 3:** Texte der Systemabfrage ergänzen (Gewicht, Aktivitätsenergie, weitere Nährwerte), deutsch und englisch.
- [ ] **Step 4:** Commit `feat: add separate Health permission groups for nutrients, active energy and body data`.

### Task B2: Weitere Nährwerte schreiben

**Hängt ab von:** B1, A1.

**Files:** Modify `HealthEntries.swift` (`HealthMeal` mit optionalen Werten), `HealthMapping.swift` (`Nutrient`, `nutrientPlan`), `HealthKitStore.swift` (`save(_ meal:)`, `deleteEntry`), `Tagwerk/Capture/IntakeStore.swift` (`healthValue`).

- [ ] **Step 1: Tests.** `nutrientPlan_unknown_isRemovedNotWritten`, `nutrientPlan_zeroKnown_isRemoved`, `save_skipsGroupNotAsked_andStillCountsAsMirrored`, `salt_writtenAsSodium`.
- [ ] **Step 2:** Die neuen Nährwerte werden nur geschrieben, wenn ihre Gruppe erlaubt ist; ein später erteilter Zugriff setzt `healthSynced` der Mahlzeiten mit solchen Werten zurück (einmaliger Nachlauf über `HealthMirror`).
- [ ] **Step 3:** Commit `feat: mirror fibre, sugar, saturated fat and sodium to Health`.

### Task B3: Aktivitätsenergie als Tagessumme

**Hängt ab von:** BU2a, B1.

**Files:** Modify `HealthEntries.swift` (`DailyActiveEnergy`), `HealthStoring.swift`, `HealthKitStore.swift` (Abfrage wie `dailySteps`), `HealthMapping.swift`, Fakes.

- [ ] **Step 1: Tests.** `dailyActiveEnergy_dropsDaysWithoutStatistics`, `dailyActiveEnergy_emptyWhenNotAuthorized`, Fake-Test `ownWorkoutEnergy_countedOnce` (gespiegelt: nur Health-Summe; ungespiegelt: Health-Summe + eigenes Training).
- [ ] **Step 2:** `dailyActiveEnergy(in:calendar:)` mit `cumulativeSum`; keine Quellenfilter.
- [ ] **Step 3:** Commit `feat: read daily active energy from Health`.

### Task B4: Gewicht lesen und schreiben

**Hängt ab von:** KG2a, KG4b, B1.

**Files:** Modify `HealthEntries.swift` (`HealthWeight`, `ForeignWeight`, `HealthEntryKind.weight` ohne Rückgriff auf `HealthShareKind`), `HealthStoring.swift`, `HealthKitStore.swift`, `HealthMapping.swift`.

- [ ] **Step 1: Tests.** `syncIdentifier_weight`, `foreignWeights_filtersOwn`, `save_weight_deniedReturnsFalse`, `deleteEntry_weight_onlyBodyTypes`.
- [ ] **Step 2:** Schreiben mit Sync-Kennung und Version wie bei Getränken; Körperfett als zweites Sample desselben Eintrags; Lesen fremder Messungen im Zeitraum.
- [ ] **Step 3:** Commit `feat: read and write body weight in Health`.

---

## Strang C: Tagesbudget in der Oberfläche

### Task C1: `CaptureModel` rechnet mit Zielstand und Budget

**Hängt ab von:** A2, A3, B3; BU1b, BU2a.

**Files:** Modify `Tagwerk/Capture/CaptureModel.swift` (`CaptureDay`, `HealthCache`, `reload`, `page(for:)`, `planHeaderLine`), `IntakeStore.swift` (`unsyncedWorkoutKcal(on:)`), Tests.

- [ ] **Step 1: Tests.** `budget_usesPlanOfShownDay`, `budget_healthSumPlusUnsyncedOwn`, `budget_withoutHealth_ownWorkoutsOnly`, `neighbourPage_usesCachedActiveEnergy`, `reload_keepsBudgetWhileHealthAnswers`.
- [ ] **Step 2:** `CaptureDay` bekommt `plan: GoalPlan`, `active: ActiveEnergy`, `budget: EnergyBudget`; der Health-Cache nimmt die Aktivitätsenergie der Woche auf (eine Abfrage wie bei den Schritten).
- [ ] **Step 3:** Commit `feat: compute the day's energy budget in the capture model`.

### Task C2: Tageskopf mit Rechenzeile und Aufschlüsselung

**Hängt ab von:** C1; BU4b.

**Files:** Modify `Tagwerk/Capture/CaptureView.swift` (`DaySummary`), Create `Tagwerk/Capture/BudgetBreakdownSheet.swift`; UI-Test, Katalog.

- [ ] **Step 1: Tests.** UI-Test `captureHead_showsBudgetEquation`; Barrierefreiheit: die Rechenzeile ist ein Element mit gesprochenem Satz („Noch etwa 1.480 Kilokalorien: Ziel 2.300, plus 520 aktiv, minus etwa 1.340 gegessen“).
- [ ] **Step 2:** Rechenzeile, Budgetbalken (Gegessen, Strich am Grundziel, Zugewinn), Kachel „In Health erlauben“ für die Aktivitätsenergie nach dem Muster der Schritte-Kachel.
- [ ] **Step 3:** Blatt „Aktiv heute“: Trainings (eigene, fremde), Alltag als Rest, Anteil, Hinweis auf Schätzwerte.
- [ ] **Step 4:** Commit `feat: show the energy budget in the capture head`.

### Task C3: Einstellungen

**Hängt ab von:** A2; BU1b, ZI4b, ZI5b.

**Files:** Modify `Tagwerk/Settings/CaptureSettingsView.swift`; Create `Tagwerk/Settings/GoalPlanView.swift` (aktueller Zielstand bearbeiten, frühere Stände).

- [ ] **Step 1: Tests.** `editingGoal_createsNewPlanFromToday`, `editingSameDayTwice_replaces`.
- [ ] **Step 2:** „Aktivität anrechnen“ (aus, 50 %, 75 %, 100 %) mit Fußtext zum Grundziel; Ziele aus `GoalStore` statt aus Einzelfeldern; Schalter für gesättigte Fettsäuren, Salz und Körperfett.
- [ ] **Step 3:** Commit `feat: edit goal plans and the activity credit in the settings`.

### Task C4: Kopf von „Planen“, Widget, Wochenrückblick

**Hängt ab von:** C1; OR2b, OR3a, OR4b.

**Files:** Modify `WeekReview.swift`, `WidgetSnapshot.swift` (`SnapshotIntake.creditedKcal: Int?`), `Tagwerk/Capture/WeekReviewModel.swift`, `WeekReviewView.swift`, `TagwerkWidget/WidgetViews.swift`, `Tagwerk/Planning/PlanHeader.swift`; Create `Tagwerk/Capture/DayActivityRecord.swift` (siehe offene Frage 1).

- [ ] **Step 1: Tests.** `planHeaderLine_showsRemainingBudget`, `snapshot_oldFileWithoutCredit_decodes`, `weekReview_dayWithinBudget_usesPlanAndActivityOfThatDay`, `weekReview_unknownActivity_fallsBackToBaseGoal`.
- [ ] **Step 2:** Umstellung der drei Orte auf `EnergyBudget`; der Wochenrückblick bekommt Tagesmittel der Nährwerte und den Gewichtstrend (nach F3).
- [ ] **Step 3:** Commit `feat: use the energy budget in the plan header, widget and week review`.

---

## Strang D: Nährwerte in der Oberfläche

### Task D1: Schätzung liefert weitere Nährwerte

**Hängt ab von:** A1; NU1b.

**Files:** Modify `Tagwerk/Capture/MealEstimator.swift` (Anweisung, `schema`), `Intake.swift` (`MealEstimateOutput.Item`, `normalized`), Tests, `Tagwerk/AI/DemoAITransport.swift`.

- [ ] **Step 1: Tests.** `schema_newFieldsRequiredAndNullable`, `normalized_nullStaysUnknown`, `normalized_negativeClampedToZero`, `decode_answerWithoutNewFields_fails` (strenges Format).
- [ ] **Step 2:** Felder `fiber_g`, `sugar_g`, `saturated_fat_g`, `salt_g` als Pflichtfelder mit erlaubtem `null`; Anweisung: lieber `null` als raten.
- [ ] **Step 3:** Commit `feat: estimate fibre, sugar, saturated fat and salt`.

### Task D2: Mahlzeitenblatt

**Hängt ab von:** A1; NU3b.

**Files:** Modify `Tagwerk/Capture/MealSheet.swift`; UI-Test.

- [ ] **Step 1: Tests.** `mealSheet_moreNutrients_expandAndSave`, `emptyField_savesUnknown`.
- [ ] **Step 2:** Zeile „Weitere Nährwerte“ mit Zähler; Felder mit `ValueStepper`/`NumberEntry`; leeres Feld = unbekannt.
- [ ] **Step 3:** Commit `feat: edit further nutrients in the meal sheet`.

### Task D3: Karte „Nährwerte“

**Hängt ab von:** A1, C1; NU2b, BU3c.

**Files:** Create `Tagwerk/Capture/NutrientCard.swift`; Modify `CaptureView.swift`, `CaptureModel.swift` (`summaryRows` ohne Eiweiß-Kachel).

- [ ] **Step 1: Tests.** `card_rows_followGoalPlanAndSwitches`, `sugar_overLimit_isMarked`, `row_showsCoverageWhenIncomplete`, `macroGoals_scaleWithBudget`.
- [ ] **Step 2:** Karte mit Balkenzeilen, aufklappbar (Zustand je Gerät in `AppSettings`), VoiceOver je Zeile.
- [ ] **Step 3:** Commit `feat: add the nutrients card to the capture tab`.

---

## Strang E: Meine Lebensmittel

### Task E1: `FoodRecord` und `FoodStore`

**Hängt ab von:** LM1b, LM4b; A1, A4.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/FoodValue.swift`, Tests; `Tagwerk/Capture/FoodRecords.swift`, `FoodStore.swift`; Modify Schema und Sicherung.

- [ ] **Step 1: Tests.** `portion_gramsToItem` (250 g bei Werten je 100 g), `portion_pieces`, `item_fromFood_isExact`, `search_matchesWordsCaseInsensitive`, `backup_roundTripsFoods`.
- [ ] **Step 2:** `FoodValue`: Name, Bezug (`per100g`, `per100ml`, `perPiece(grams?)`), Kalorien und `NutrientValues`, `origin` (`typed`, `label`, `estimate`, `barcode`), optional Strichcode.
- [ ] **Step 3:** Commit `feat: add own foods with reference values`.

### Task E2: Auswahl und Mengeneingabe

**Hängt ab von:** E1.

**Files:** Modify `MealSheet.swift` (Segment „Zuletzt / Meine Lebensmittel / Mahlzeiten“), Create `FoodPickerView.swift`, `FoodEditSheet.swift`.

- [ ] **Step 1: Tests.** UI-Test `addOwnFood_withGrams_addsExactItem`; `estimatedItem_saveAsFood_keepsValues`.
- [ ] **Step 2:** Auswahl mit Mengenfeld; „Als Lebensmittel sichern“ an einem Posten.
- [ ] **Step 3:** Commit `feat: pick own foods with an amount in the meal sheet`.

### Task E3: Etikett fotografieren

**Hängt ab von:** E1; LM3b.

**Files:** Create `Tagwerk/Capture/LabelReader.swift` (eine Anfrage nach dem Muster von `MealEstimator`), Tests; Modify `MealConsentSheet.swift` (ein Satz), `FoodEditSheet.swift`.

- [ ] **Step 1: Tests.** `labelReader_requiresMealConsent`, `labelReader_nullFieldsStayUnknown`, `labelReader_noTable_reportsNothingRecognized`.
- [ ] **Step 2:** Antwortformat `nutrition_label` (Bezug, Werte je Bezug, Stückgewicht); Vorschau füllt `FoodEditSheet`, gespeichert wird erst nach Bestätigung.
- [ ] **Step 3:** Commit `feat: read nutrition labels into own foods`.

### Task E4 (zweite Ausbaustufe): Strichcode

**Hängt ab von:** LM2b; E1. **Vor dem Bau:** Nutzungsbedingungen und Abfragegrenzen von Open Food Facts prüfen und hier eintragen.

**Files:** Create `Tagwerk/Capture/BarcodeScannerView.swift`, `ProductLookup.swift` (Protokoll, Transport austauschbar), Tests; Schalter in `CaptureSettingsView.swift`.

- [ ] **Step 1: Tests.** `lookup_mapsProductToFood_missingFieldsUnknown`, `lookup_notFound`, `lookup_disabled_sendsNothing`.
- [ ] **Step 2:** Scan auf dem Gerät, Abfrage nur bei eingeschaltetem Schalter, Vorschau mit Quellenhinweis.
- [ ] **Step 3:** Commit `feat: look up packaged foods by barcode`.

---

## Strang F: Gewicht

### Task F1: `WeightRecord`, Store und Spiegelung

**Hängt ab von:** KG2a, KG4b; B4, A4.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/Weight.swift`, Tests; `Tagwerk/Capture/WeightRecords.swift`, `WeightStore.swift`; Modify `IntakeStore.swift`/`HealthMirror.swift` (weitere Eintragsart, Löschwarteschlange), Schema, Sicherung.

- [ ] **Step 1: Tests.** `mirror_writesUnsyncedWeight`, `delete_withinUndoWindow_neverReachesHealth`, `dayValue_earliestOfDay`, `merge_ownAndForeign_noDuplicates`.
- [ ] **Step 2:** Modell mit `healthVersion`, `healthSynced` wie bei Getränken; Grenzen 20–400 kg, Schritt 0,1.
- [ ] **Step 3:** Commit `feat: record body weight and mirror it to Health`.

### Task F2: Erfassen

**Hängt ab von:** F1; KG1c, KG5a.

**Files:** Create `Tagwerk/Capture/WeightSheet.swift`; Modify `CaptureView.swift` (`quickEntry`), `Tagwerk/Routines/MorningSheet.swift`, `RoutineSettingsView.swift`.

- [ ] **Step 1: Tests.** UI-Test `quickEntry_weight_savesAndOffersUndo`; `morningRow_hiddenWhenSwitchedOff`; Layouttest der vier Knöpfe bei großer Schrift (Umbruch in zwei Zeilen).
- [ ] **Step 2:** Blatt mit vorbelegtem letzten Wert, Zeitpunkt, optional Körperfett; Zeile im Tagesstart, abschaltbar.
- [ ] **Step 3:** Commit `feat: enter body weight from the capture tab and the morning sheet`.

### Task F3: `WeightTrend`

**Hängt ab von:** F1; KG3a.

**Files:** Modify `Weight.swift`, Tests.

- [ ] **Step 1: Tests.** `movingAverage_needsThreeValues`, `trend_perWeekOver28Days`, `trend_insufficientData_isNil`, `projection_linear_nilWhenMovingAway`, `gaps_doNotBreakAverage`.
- [ ] **Step 2:** Regeln aus „Rechenregeln“.
- [ ] **Step 3:** Commit `feat: add weight trend rules`.

### Task F4: Seite „Verlauf und Ziele“

**Hängt ab von:** F3, C1, A2; OR1a, KG3a.

**Files:** Create `Tagwerk/Capture/TrendModel.swift`, `TrendView.swift`, `WeightChart.swift`, `IntakeChart.swift`; Modify `CaptureView.swift` (Zeile), `Tagwerk/App/AppRouter.swift`.

- [ ] **Step 1: Tests.** `trendModel_week_month_year_buckets`, `goalLine_stepsAtPlanChange`, `chart_accessibilitySummary`.
- [ ] **Step 2:** Zeiträume Woche, Monat, Jahr (Gewicht zusätzlich 3 Monate); Diagramme mit Swift Charts, jeweils mit Textzusammenfassung für VoiceOver; Kennzahlen unter dem Gewichtsdiagramm; Liste der Messungen mit Quelle.
- [ ] **Step 3:** Commit `feat: add the trends page for intake and weight`.

---

## Strang G: Zielplanung mit ChatGPT

Voraussetzung für G5–G7: `2026-11-20-decisions-173.md`, Task 2 (Einzelbestätigung, `ActionCard.warning`) und Task 4 (`storedForm`, `storableHistory`, Nachrichtentyp `.activity`) sind auf `main`.

### Task G1: Körperdaten

**Hängt ab von:** PV4a.

**Files:** Modify `AppSettings.swift` (`bodyHeightCm: Int?`, `birthYear: Int?`, `formulaSexRaw: String?`), `CaptureSettingsView.swift`, `BackupDTOs.swift`.

- [ ] **Step 1: Tests.** `backup_oldFileWithoutBodyData_decodes`, `age_fromBirthYear`.
- [ ] **Step 2:** Abschnitt „Körper“ mit drei Feldern und Erklärung, wofür sie dienen.
- [ ] **Step 3:** Commit `feat: add body data for goal calculations`.

### Task G2: `GoalGuard`

**Hängt ab von:** ZI2b; Bestätigung der Festlegungen in „Rechenregeln“.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/GoalGuard.swift`, Tests.

- [ ] **Step 1: Tests.** `restingEnergy_example` (82,1 kg, 180 cm, 34, männlich → ~1.780), `warning_belowRestingEnergy`, `warning_paceAboveOnePercent`, `warning_macrosDoNotAddUp`, `noBodyData_noCheckButNotice`, `check_text_alwaysSaysEstimate`.
- [ ] **Step 2:** `GoalGuard.check(proposal:body:weight:) -> GoalCheck` (Vergleichswerte, Warnungen, Text).
- [ ] **Step 3:** Commit `feat: add the local cross-check for goal proposals`.

### Task G3: Einwilligung

**Hängt ab von:** PV1b.

**Files:** Create `Tagwerk/Capture/GoalConsentSheet.swift`; Modify `AppSettings.swift` (`goalPlanningConsent`), `BackupDTOs.swift`, `Settings/ChatGPTCaptureSection.swift`, Datenschutzhinweis unter Einstellungen › KI.

- [ ] **Step 1: Tests.** `consent_defaultOff`, `revoke_endsRunningGoalSession`.
- [ ] **Step 2:** Blatt nach dem Aufbau von `MealConsentSheet` mit dem Text aus dem Mockup PV1b; Schalter „Ziele mit ChatGPT planen“.
- [ ] **Step 3:** Commit `feat: add the consent for goal planning with ChatGPT`.

### Task G4: Datenpaket und Auswahlblatt

**Hängt ab von:** PV2a; A2, C1, F3.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/GoalDataSummary.swift`, Tests; `Tagwerk/Capture/GoalDataBuilder.swift`, `GoalDataSheet.swift`.

- [ ] **Step 1: Tests.** `summary_averagesOver28Days_withCoverage`, `summary_excludesSwitchedOffGroups`, `summary_noMealTitlesNoDates`, `json_matchesWhatSheetShows` (derselbe Wert erzeugt Anzeige und Sendeform), `daysWithoutEntries_notCountedAsZero`.
- [ ] **Step 2:** Gruppen: Körperdaten, Gewicht und Trend, Ernährung, Aktivität, Wasser, geltende Ziele. Die Auswahl gilt für eine Sitzung; die Schalterstellung wird gemerkt.
- [ ] **Step 3:** Commit `feat: build and preview the data package for goal planning`.

### Task G5: `GoalChatTools` und Kontext

**Hängt ab von:** ZI1b, ZI3b; G2–G4.

**Files:** Create `Tagwerk/AI/GoalChatTools.swift` (nach dem Muster von `TaskChat.swift`), Tests; Modify `AssistantModel.swift` (`Context.goals`, Anweisungen, eigener Chat-Schlüssel `goals`), `ChatView.swift`.

Werkzeuge (nur in diesem Kontext registriert):

| Name | Art | Inhalt |
|---|---|---|
| `get_goal_data` | lesen | liefert das in der Sitzung freigegebene Paket; ohne Einwilligung oder Auswahl ein Fehler ohne Werte |
| `propose_nutrition_goals` | schreiben (Karte) | `kcal`, `protein_g`, `carbs_g`, `fat_g`, `fiber_g`, `sugar_limit_g`, `water_ml`, `target_weight_kg`, `pace_kg_per_week`, `reason`; alle nullable |
| `propose_activity_goals` | schreiben (Karte) | `steps_per_day`, `workout_minutes_per_week`, `active_kcal_per_day`, `reason`; alle nullable |

- [ ] **Step 1: Tests.** `tools_notRegisteredInGeneralAssistant`, `getGoalData_withoutConsent_returnsErrorWithoutValues`, `getGoalData_returnsOnlySelectedGroups`, `proposal_outOfRange_isRejectedWithMessage`, `instructions_stateBaseGoalWithoutActivity`.
- [ ] **Step 2:** Anweisungen (deutsch): Rolle, Pflicht zu `get_goal_data` vor einem Vorschlag, Grundziel ohne Aktivität, keine Diagnosen, Hinweis auf ärztlichen Rat bei genannten Erkrankungen, Vorschläge nur über die Funktionen.
- [ ] **Step 3:** Commit `feat: add the goal planning chat with its tools`.

### Task G6: Vorschlagskarten und „Anpassen“

**Hängt ab von:** G5; ZI2b, ZI3b; #173 Task 2.

**Files:** Modify `Tagwerk/AI/ActionCardDescriber.swift`, `ChatView.swift`; Create `Tagwerk/AI/GoalProposalCard.swift`, `GoalAdjustSheet.swift`.

- [ ] **Step 1: Tests.** `card_showsOldAndNewValues`, `card_showsCrossCheck`, `card_withWarning_needsSecondConfirmation`, `confirmAll_skipsGoalCards`, `adopt_createsOnePlanFromToday`, `adjust_thenAdopt_usesEditedValues`, `nullFields_keepCurrentValues`.
- [ ] **Step 2:** Karte mit Gegenrechnung; „Übernehmen“ ruft `GoalStore.adopt` mit `origin = assistant` und der Begründung; das Funktionsergebnis nennt dem Modell, was übernommen wurde.
- [ ] **Step 3:** Commit `feat: confirm goal proposals as cards`.

### Task G7: Gespeicherte Kurzform

**Hängt ab von:** G5; PV3b; #173 Task 4.

**Files:** Modify `GoalChatTools.swift` (`storedForm`, `showsActivity`), Tests.

- [ ] **Step 1: Tests.** `storedHistory_containsNoValuesFromGoalData`, `activityLine_namesGroupsAndPeriod`, `sessionMemory_keepsPackageUntilSessionEnds`.
- [ ] **Step 2:** Gespeichert wird „Gelesen: … (Durchschnitte)“; das Paket bleibt nur im Arbeitsspeicher der Sitzung.
- [ ] **Step 3:** Commit `feat: keep goal data out of the stored chat history`.

### Task G8: Einstiege und „Fortschritt besprechen“

**Hängt ab von:** G5, F4; ZI6b, OR4b.

**Files:** Modify `TrendView.swift`, `WeekReviewView.swift`, `GoalPlanView.swift`, `AppRouter.swift`.

- [ ] **Step 1: Tests.** `entry_withoutSignIn_showsSignInHint`, `entry_withoutConsent_showsConsentFirst`, `review_prefillsFirstMessage_withoutSending`.
- [ ] **Step 2:** „Ziele planen“ und „Fortschritt besprechen“ öffnen Einwilligung (falls nötig), Auswahlblatt, dann den Chat; die erste Nachricht ist vorbereitet, gesendet wird erst auf Tippen.
- [ ] **Step 3:** Commit `feat: add entries to goal planning and the progress review`.

---

## Gerätetests

| Bereich | Prüfung |
|---|---|
| Berechtigungen | Nach dem Update ohne neue Zustimmung: Mahlzeit, Wasser und Training erscheinen weiter in Health. Jede neue Gruppe fragt einzeln und nur nach einem Tipp. |
| Doppelzählung | (a) iPhone ohne Uhr: Lauf in Tagwerk eintragen, „Aktiv“ vor und nach dem Spiegeln vergleichen. (b) Mit Uhr: Training auf der Uhr aufzeichnen und denselben Zeitraum in Tagwerk eintragen; die Health-Summe darf den Zeitraum nur einmal enthalten. (c) Kalorien-Schreiben in Health verweigern: Training zählt über den Lückenfüller. |
| Verweigertes Lesen | Aktivitätsenergie verweigern: „Aktiv –“, Budget = Grundziel + eigene Trainings, nie 0. |
| Gesperrtes Gerät | Widget nach Hintergrundaktualisierung bei gesperrtem iPhone: zeigt den letzten Stand, keinen Fehler. |
| Tageswechsel | Um Mitternacht und bei Zeitzonenwechsel: Aktivität und Budget gehören zum richtigen Tag. |
| Nährwerte | Alte Mahlzeit ohne Ballaststoffe: Zeile nennt die Abdeckung; in Health kein 0-Eintrag. |
| Gewicht | Eintrag, Widerrufen innerhalb von 4 s, Eintrag aus einer anderen App erscheint mit Quellenname; Diagramm bei 1, 2 und 100 Messungen. |
| Schrift | Vier Knöpfe der Schnellerfassung und die Rechenzeile bei größter Schriftstufe. |
| Zielchat | Ohne Einwilligung kein Netzverkehr (Diagnose). Auswahl abgeschaltet → Antwort des Assistenten nennt die Werte nicht. Karte mit Warnung verlangt zweite Bestätigung. Nach Neustart steht im Verlauf nur „Gelesen: …“. |
| Sicherung | Sichern und Wiederherstellen mit Zielständen, Lebensmitteln und Gewicht; alte Sicherung ohne diese Listen öffnet. |

## Reihenfolge und Abhängigkeiten

1. **A1 → A2 → A3 → A4** (reine Regeln und Modelle; keine sichtbare Änderung außer der Übernahme der Ziele).
2. **B1 → B3**, dann **C1 → C2 → C3 → C4**: Das Tagesbudget ist der erste sichtbare Schritt und unabhängig von den übrigen Strängen.
3. **B2, D1 → D2 → D3** (Nährwerte) parallel zu Schritt 2 möglich; D3 braucht C1.
4. **E1 → E2 → E3**; E4 erst nach eigener Freigabe.
5. **B4 → F1 → F2 → F3 → F4**; F4 braucht C1 für die Kaloriendiagramme.
6. **G1 → G2 → G3 → G4 → G5 → G6 → G7 → G8**; G5–G7 warten auf #173 Tasks 2 und 4, G4 auf F3 und C1.

Höchstens drei Umsetzungs-Agenten parallel; sinnvolle Dreiergruppen: {C, D, E} nach A und B1/B3, danach {F, G1–G4}, zuletzt G5–G8.

**Fremde Abhängigkeiten:** `2026-11-20-decisions-173.md` Tasks 2 und 4 (für G5–G7). Das Mitteilungskontingent wird nicht berührt. `MorningSheet.swift` wird auch von den Routinen-Plänen (`2026-11-20-g2-routinen-persoenliches.md`) geändert; F2 nach deren Umsetzung einplanen.

## Nicht im Umfang

- Vitamine und Mineralstoffe, eine mitgelieferte Lebensmittelliste, Textsuche in einer Online-Datenbank, ein eigenes Ernährungs-Widget.
- Rezepte als Mahlzeit mit Nährwerten.
- Lesen von Ernährungsdaten anderer Apps aus Health.
- Eigene Mitteilungen (Wiegen, Besprechung).
- Selbsttätige Anfragen an ChatGPT; Gesundheitsdaten im allgemeinen Assistenten oder im Sprachmodus.
- Apple-Watch-App, Schlaf, Puls.

## Entscheidungen des Nutzers (jeweils mit Empfehlung)

Alle Tasks sind gegen die Empfehlungen geschrieben. Bilder und Varianten stehen im Mockup unter dem jeweiligen Kürzel.

| Kürzel | Frage | Empfehlung | Begründung |
|---|---|---|---|
| BU1 | Wie viel der verbrannten Energie wird angerechnet? | **BU1b** Anteil einstellbar, Voreinstellung 100 % | Erfüllt den Wunsch am ersten Tag und bleibt korrigierbar, wenn die Schätzung der Aktivitätsenergie zu großzügig ausfällt. |
| BU2 | Woher kommt „Aktiv“, und wie wird Doppelzählung vermieden? | **BU2a** Tagessumme aus Health, eigene Trainings nur als Lückenfüller | Eine Quelle der Wahrheit für die Summe; Health führt Quellen bereits zusammen, Tagwerk muss nur die Lücke vor dem Spiegeln schließen. |
| BU3 | Wie verändern sich die Makro-Ziele mit dem Budget? | **BU3c** Eiweiß und Ballaststoffe fest, Rest wächst | Das Eiweißziel bleibt eine feste, vom Körpergewicht abgeleitete Größe; nur die Energieträger folgen der Aktivität. |
| BU4 | Tageskopf in „Erfassen“: Darstellung des Budgets | **BU4b** Rechenzeile mit Budgetbalken | Die Rechnung ist ohne Erklärung nachvollziehbar, und der Balken zeigt, wie viel des Spielraums aus Aktivität stammt. |
| NU1 | Welche Nährwerte führt Tagwerk? | **NU1b** Dazu Ballaststoffe und Zucker; gesättigte Fettsäuren und Salz zuschaltbar | Deckt den Wunsch und die Pflichtangaben der Verpackung, ohne Werte zu führen, für die es keine verlässliche Quelle gibt. |
| NU2 | Nährwerte in der Tagesübersicht | **NU2b** Eigene Karte „Nährwerte“ mit Balkenzeilen | Trennt Budget und Nährwerte lesbar und wächst mit zuschaltbaren Größen, ohne den Kopf zu überladen. |
| NU3 | Mahlzeitenblatt: Wie viele Wertfelder sind sichtbar? | **NU3b** Kalorien und Makros sichtbar, weitere aufklappbar | Der schnelle Fall bleibt so kurz wie heute; Vollständigkeit kostet einen Tipp. |
| NU4 | Fehlende Werte: 0 oder unbekannt? | **NU4b** Fehlend ist unbekannt, die Summe nennt die Abdeckung | Verhindert, dass Lücken in alten und getippten Einträgen als gemessene Null erscheinen. |
| NU5 | Ernährungsdaten anderer Apps aus Health lesen? | **NU5a** Nein, nur eigene Einträge | Hält die Summen vollständig prüfbar; ein Parallelbetrieb mit einer zweiten Ernährungs-App ist nicht das Ziel des Wunsches. |
| LM1 | Quellen für Nährwerte | **LM1b** Dazu „Meine Lebensmittel“ mit Werten je 100 g oder je Stück | Liefert exakte Werte für das, was wirklich wiederkehrt, ohne Lizenz- und Qualitätsfragen einer fremden Datenbank. |
| LM2 | Strichcode-Scan | **LM2b** Als zweite Ausbaustufe, hinter einem Schalter | Der Nutzen ist real, hängt aber an einem fremden Dienst; die eigene Liste muss zuerst stehen und bleibt der Speicherort. |
| LM3 | Etikett fotografieren | **LM3b** Ja, über ChatGPT mit Prüf-Vorschau | Nutzt den vorhandenen Foto-Weg, liefert exakte statt geschätzter Werte und füllt „Meine Lebensmittel“ am schnellsten. |
| LM4 | Mengeneingabe | **LM4b** Gramm oder Stück bei eigenen Lebensmitteln, Faktor bei Schätzungen | Werte je 100 g sind ohne Grammangabe nicht nutzbar; geschätzte Posten brauchen die Umstellung nicht. |
| KG1 | Wo wird das Gewicht eingetragen? | **KG1c** Beides: Knopf und abschaltbare Zeile im Tagesstart | Ein fester, jederzeit erreichbarer Ort und eine Erinnerung zum üblichen Wiegezeitpunkt, ohne einen Platz im Mitteilungskontingent. |
| KG2 | Wer führt das Gewicht: Tagwerk oder Health? | **KG2a** Tagwerk führt eigene Einträge, liest fremde Messungen dazu | Gleiche Regel wie bei allen anderen Einträgen: Tagwerk bleibt ohne Health vollständig, Health-Daten kommen dazu. |
| KG3 | Gewichtsverlauf: Was zeigt das Diagramm? | **KG3a** Messpunkte, 7-Tage-Mittel als Linie, Ziellinie | Zeigt die Messungen ehrlich und macht zugleich den Trend lesbar, an dem sich Ziel und Tempo bemessen. |
| KG4 | Körperfettanteil | **KG4b** Zuschaltbar, im Standard aus | Kostet wenig, stört im Standard nicht und passt zum Ziel „ohne Muskeln zu verlieren“. |
| KG5 | Erinnerung ans Wiegen | **KG5a** Keine eigene Mitteilung | Die Reserve von zwei Plätzen ist knapp, und der Tagesstart erreicht denselben Zeitpunkt ohne neuen Platz. |
| ZI1 | Form der Zielplanung | **ZI1b** Geführtes Gespräch im eigenen Chat „Ziele planen“ | Erfüllt den Wunsch nach einem Gespräch und begrenzt Gesundheitsdaten auf einen eigenen Chat mit eigenem Zweck. |
| ZI2 | Wer rechnet die Zahlen? | **ZI2b** ChatGPT schlägt vor, Tagwerk rechnet gegen und warnt | Lässt dem Gespräch die Freiheit und stellt jedem Vorschlag eine nachvollziehbare eigene Rechnung mit sichtbarer Warnung gegenüber. |
| ZI3 | Vorschlagskarte: eine oder zwei? | **ZI3b** Getrennte Karten für Ernährung und Aktivität | Aktivitätsziele sind im Wunsch ausdrücklich optional; getrennte Karten machen das ohne Umweg möglich. |
| ZI4 | Umfang der Aktivitätsziele | **ZI4b** Dazu Aktivitätsenergie pro Tag | Nutzt einen Wert, der für das Budget ohnehin gelesen wird, und nimmt die frühere Entscheidung gegen die Trainingsanzahl nicht zurück. |
| ZI5 | Ziele mit Geschichte | **ZI5b** Zielstände mit „gültig ab“ | Ohne Zielstände sind weder Verlauf noch Rückblick verlässlich; das Modell ist klein und Voraussetzung für ZI6. |
| ZI6 | Fortschritt später mit ChatGPT besprechen | **ZI6b** Dazu ein Abschnitt im Wochenrückblick | Bindet die Besprechung an den Wochenrückblick, den es schon gibt, ohne Mitteilung und ohne selbsttätige Anfrage. |
| PV1 | Einwilligung für die Zielplanung | **PV1b** Eigenes Blatt und eigener Schalter „Ziele mit ChatGPT planen“ | Eigener Zweck, eigene Zusage, eigener Widerruf; die bestehenden Zusagen bleiben wörtlich wahr. |
| PV2 | Welche Daten gehen an ChatGPT? | **PV2a** Durchschnitte und Trend, je Gespräch auswählbar | Für den Zweck ausreichend, vor dem Senden vollständig sichtbar und je Gruppe abwählbar. |
| PV3 | Was bleibt vom Gespräch gespeichert? | **PV3b** Datenpaket nur in der Sitzung, Chattext gespeichert | Gleiche Regel wie bei Notizen: Rohdaten nur flüchtig, das Gespräch bleibt anschlussfähig und löschbar. |
| PV4 | Größe, Alter und Geschlecht: tippen oder aus Health lesen? | **PV4a** In Tagwerk eintragen | Drei selten geänderte Werte rechtfertigen keine drei weiteren Berechtigungen mit unsichtbarem Fehlerfall. |
| OR1 | Wo wohnen Verlauf und Ziele? | **OR1a** In „Erfassen“: Tageskopf plus Seite „Verlauf und Ziele“ | Hält Eintragen und Auswerten an einem Ort und lässt die Leiste, wie sie ist. |
| OR2 | Kalorien-Zeile im Kopf von „Planen“ | **OR2b** Rest des Budgets | Die Zeile ist kurz; sie soll die eine Zahl zeigen, die eine Entscheidung auslöst. |
| OR3 | Widget | **OR3a** Widget „Heute“ rechnet mit dem Budget | Kein neues Widget, solange die Zahl darin nur so frisch ist wie der letzte App-Start. |
| OR4 | Wochenrückblick | **OR4b** Rechnet mit Budget und Zielständen, dazu Nährwerte und Gewichtstrend | Tageskopf und Wochenrückblick müssen dieselbe Rechnung zeigen. |

### Weitere offene Fragen

| Nr. | Frage | Empfehlung |
|---|---|---|
| 1 | **Aktivität vergangener Tage festhalten?** Ohne eigene Speicherung hängt das Budget vergangener Tage (Wochenrückblick, Diagramme) daran, dass Health später dieselben Werte liefert; in der Sicherung fehlen sie. | Ja: `DayActivityRecord` (Tag, Aktivitätsenergie, angerechneter Anteil), geschrieben beim Laden eines Tages und beim Tageswechsel, Teil der Sicherung. In C4 eingeplant. |
| 2 | **Festlegungen der Gegenrechnung** (Faktor 1,2, 7.700 kcal je kg, Warnschwellen) übernehmen? | Als Rechenhilfe ja, mit dem Satz „Schätzung, keine medizinische Empfehlung“ auf der Karte; Schwellen nicht einstellbar. Vor dem Bau die Formel an der Originalquelle prüfen. |
| 3 | **Zeitraum des Datenpakets:** 28 Tage fest oder wählbar? | 28 Tage fest; für „Fortschritt besprechen“ der Zeitraum seit dem geltenden Zielstand, höchstens 12 Wochen. |
| 4 | **Zielstand rückwirkend?** Gilt ein übernommener Zielstand ab heute oder ab einem wählbaren Datum? | Ab heute; kein rückwirkendes Ändern, damit vergangene Auswertungen stabil bleiben. |
| 5 | **Sprachmodus:** Darf der Zielchat per Sprache geführt werden? | Vorerst nein; Karten mit Zahlen und Warnungen brauchen den Bildschirm. |
| 6 | **Issue-Schnitt:** ein Issue je Strang (A–G) oder ein Sammel-Issue? | Je Strang eines, Strang E Stufe 2 (Strichcode) als eigenes. |

## Risiken

1. **Doppelzählung und Quellen-Reihenfolge in Health.** Ob Health ein von Tagwerk geschriebenes Energie-Sample und eine gleichzeitige Messung der Uhr nur einmal zählt, ist aus der Dokumentation abgeleitet, nicht am Gerät belegt. Fällt der Gerätetest anders aus, braucht BU2a eine Abzugsregel je Trainingszeitraum (Variante BU2b mit Zusatzregel).
2. **Berechtigungsgruppen.** Ein Fehler in B1 hält die Spiegelung für alle bestehenden Einträge an, ohne Fehlermeldung. Der Test `coreTypes_unchanged` ist die Absicherung; zusätzlich Gerätetest nach einem Update über einen bestehenden Stand.
3. **Genauigkeit der Aktivitätsenergie.** Volle Anrechnung kann das Budget systematisch zu hoch ansetzen. Gegenmaßnahme ist der einstellbare Anteil und der Abgleich mit dem Gewichtstrend im Rückblick; belegt ist die Wirksamkeit damit nicht.
4. **Gesundheitsbezogene Vorschläge eines Sprachmodells.** Ein unpassendes Ziel kann schaden. Gegenmaßnahmen: Gegenrechnung mit Warnung, zweite Bestätigung, Hinweis auf ärztlichen Rat, keine selbsttätige Übernahme. Die Schwellen sind nicht fachlich geprüft.
5. **Datenschutz.** Die Nachrichten des Zielchats bleiben auf dem Gerät gespeichert und können Zahlen enthalten, die der Assistent genannt hat (PV3b). Was OpenAI mit den gesendeten Daten tut, liegt außerhalb der App.
6. **Abhängigkeit von #173.** Ohne `storedForm` und Einzelbestätigung sind G5–G7 nicht baubar; die Reihenfolge der Pläne muss das abbilden.
7. **Datenmigration der Ziele.** Der erste Zielstand entsteht aus Platzhaltern; vergangene Tage werden damit so bewertet wie heute, aber eine falsche `validFrom`-Wahl verfälscht den Wochenrückblick.
8. **Umfang.** Sieben Stränge mit über 30 Tasks. Ohne Schnitt in getrennte Issues und ohne die Reihenfolge „Budget zuerst“ droht ein langer Branch.
9. **Schätzqualität kleiner Nährwerte.** Ballaststoff- und Zuckerangaben aus Text oder Foto sind unsicher; die Tagessumme kann eine Genauigkeit vortäuschen. Gegenmaßnahme: „~“, Abdeckung, `null` statt Raten.
10. **Platz bei großer Schrift.** Vier Schnellknöpfe und eine Rechenzeile mit vier Zahlen sind eng; Umbruchregeln sind Teil von C2 und F2.

## Nicht verifiziert

- Verhalten von Health bei überlappenden Quellen für `activeEnergyBurned` und die Einreihung von Tagwerk in die Quellen-Reihenfolge.
- Ob das iPhone ohne Uhr Aktivitätsenergie nach Health schreibt.
- Nutzungsbedingungen, Lizenzdetails und Abfragegrenzen von Open Food Facts; Lizenzlage von Bundeslebensmittelschlüssel, Schweizer Nährwertdatenbank und USDA FoodData Central.
- Die Formel nach Mifflin und St Jeor und der Literaturstand zur Genauigkeit der Energieschätzung von Handgelenk-Geräten wurden aus dem Gedächtnis wiedergegeben und in dieser Runde nicht an Quellen geprüft.
- `MealSheet.swift`, `WeekReviewView.swift`, `WidgetSnapshot.swift` und `BackupDTOs.swift` wurden nur in Ausschnitten gelesen; die genannten Dateien und Stellen in den Tasks C4, D2 und E2 sind vor der Umsetzung zu bestätigen.
- Ob `ViewThatFits` oder ein fester Umbruch für die vier Schnellknöpfe trägt, ist am Gerät zu prüfen.
- Kein Build, kein Testlauf, kein Simulator in dieser Runde.
