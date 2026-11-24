# Ernährung, Gewicht und Ziele – Implementation Plan

> **For agentic workers:** Die Entscheidungen des Nutzers vom 21.11.2026 sind eingetragen (Abschnitt „Entscheidungen des Nutzers“); jeder Task folgt der gewählten Variante, nicht gewählte Varianten sind entfernt. Umsetzung Task für Task, jeweils mit TDD, Schritte als Checkbox (`- [ ]`). Die Recherche ist eingetragen (Rechenregeln, Open Food Facts); offen sind nur noch Gerätetests (HealthKit).

> **Status:** Stand 21.11.2026, Code-Grundlage `origin/main` bei `8326a3c` (enthält PR #240–#252, darunter #242 mit `storedForm`, `storableHistory`, `singleConfirmationTools` und dem Nachrichtentyp `.activity`). Mockups: `docs/superpowers/mockups/2026-11-21-ernaehrung-gewicht-ziele-mockups.html` (32 Entscheidungen, gewählte Varianten tragen die Marke „Gewählt“). Nichts davon ist gebaut, nichts am Gerät geprüft. Es gibt noch kein Issue zu diesem Vorhaben. Die Vorschlagskarten der Zielplanung teilen sich ihre Bauteile mit dem Plan `2026-11-21-ki-vorschlaege-anpassen.md` („Anpassen“ für alle KI-Vorschläge).

**Goal:**
- **Tagesbudget:** Der Tageskopf in „Erfassen“ rechnet „Ziel + angerechnete Aktivität − Gegessen = Noch“. Die Aktivitätsenergie kommt als Tagessumme aus Health; in Tagwerk eingetragene Trainings zählen genau einmal. Der angerechnete Anteil ist einstellbar (Voreinstellung 50 %).
- **Nährwerte:** Neben Kalorien, Eiweiß, Kohlenhydraten und Fett führt Tagwerk Ballaststoffe und Zucker, zuschaltbar gesättigte Fettsäuren und Salz, mit Zielen, Tagesübersicht und Spiegelung nach Health. Fehlende Angaben bleiben „unbekannt“. Ernährungseinträge anderer Apps aus Health zählen mit, wenn der Nutzer das einschaltet.
- **Lebensmittel:** Eine eigene Liste „Meine Lebensmittel“ mit Werten je 100 g, je 100 ml oder je Stück; Anlegen durch Tippen, Etikett-Foto, Übernahme aus einer Schätzung oder aus der Online-Suche in Open Food Facts (Text). Strichcode als zweite Ausbaustufe hinter demselben Schalter.
- **Gewicht:** Erfassen in „Erfassen“ und im Tagesstart, Spiegelung nach Health, fremde Messungen aus Health, Verlauf mit 7-Tage-Mittel, Ziellinie und Trend; Körperfett zuschaltbar.
- **Ziele:** Zielstände mit „gültig ab“ ersetzen die Einzelwerte in den Einstellungen. Ein eigener Chat „Ziele planen“ schlägt Ernährungs- und getrennt Aktivitätsziele als Karten vor; Tagwerk rechnet gegen und warnt. Gesundheitsdaten gehen nur mit eigener Einwilligung, nur als Durchschnitte und nur nach sichtbarer Auswahl an ChatGPT. Größe, Geburtsdatum und biologisches Geschlecht kommen aus Health, mit Eingabefeldern als Ersatz.

**Architecture:**
- **Reine Regeln in `TagwerkCore`:**
  - `NutrientValues` (optionale Werte je Nährwert, Summen mit Abdeckung) und die Erweiterung von `MealItem`, `MealValue`, `DayIntake`; `ForeignIntake` (Tagessummen anderer Apps) und `IntakeTotals` (eigene + fremde Einträge).
  - `GoalPlan` (ein Zielstand) und `GoalTimeline` (welcher Stand gilt an welchem Tag).
  - `EnergyBudget` (Budget, angerechnete Aktivität, Makro-Skalierung).
  - `FoodValue` und `FoodPortion` (eigenes Lebensmittel, Menge → Posten); `ProductSearchRules` (Abfragegrenze, Zuordnung fremder Produktdaten).
  - `WeightValue`, `WeightTrend` (Tageswert, 7-Tage-Mittel, Trend, Fortschreibung).
  - `GoalGuard` mit `GoalGuardConstants` (Gegenrechnung und Warnungen), `BodyProfile` (Körperdaten mit Quelle) und `GoalDataSummary` (das Datenpaket für ChatGPT).
- **`HealthBridge`:** eigene Berechtigungsgruppen neben der bestehenden (`HealthAccessGroup`: `moreNutrients`, `activeEnergy`, `body`, `foreignNutrition`, `bodyProfile`), Schreiben weiterer Nährwerte, Lesen der Aktivitätsenergie als Tagessumme, Gewicht lesen und schreiben, Tagessummen fremder Ernährungseinträge, Körper-Stammdaten lesen. `HealthShareKind` bleibt unverändert.
- **`AIKit`:** `Conversation` bekommt das Bestätigen mit geänderten Argumenten (Plan `2026-11-21-ki-vorschlaege-anpassen.md`, Task A1); sonst keine Änderung. `storedForm`, `storableHistory`, `reduceToStoredForm` und `.activity` sind vorhanden (`Packages/AIKit/Sources/AIKit/Conversation.swift:41–52, 70, 185, 211`).
- **App:** `GoalStore`, `FoodStore`, `WeightStore`, `DayHealthStore` (SwiftData), Erweiterung von `IntakeStore`, `HealthMirror`, `CaptureModel`, `DaySummary`, `MealSheet`, `MealEstimator`; neue Seite `TrendView` („Verlauf und Ziele“) mit Swift Charts; `ProductLookup` (Open Food Facts); `GoalChatTools` (eigener `ToolHandler`, ohne die Funktionen von `AppTools`), `AssistantModel.Context.goals`, `GoalConsentSheet`, `GoalDataSheet`, `GoalProposalCard`.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, HealthKit, Swift Charts (Systemframework, bisher nicht benutzt), VisionKit nur in Task E6, Swift Testing, XcodeGen. Keine neue Paketabhängigkeit.

**Issues:** noch keines. **Branches (Vorschlag):** je Strang einer, z. B. `feat/nutrition-goal-plans`, `feat/energy-budget`, `feat/nutrients`, `feat/own-foods`, `feat/food-search`, `feat/weight`, `feat/goal-planning`.

## Global Constraints

- **Strings:** Deutsch ist Quellsprache. Jeder neue Text steht deutsch und englisch im Katalog (`Tagwerk/Localizable.xcstrings`, für Pakete im jeweiligen `Resources/Localizable.xcstrings`) und in `scripts/translations/en.json`. Prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs und Testnamen englisch. Anweisungen an ChatGPT für eine Einzelanfrage wie in `MealEstimator`, Anweisungen des Assistenten deutsch (wie `AssistantModel.instructions`).
- **Schätzungen sehen nie exakt aus:** „~“ oder Spanne bleiben (`IntakeFormat`). Ein Budget mit geschätzten Mahlzeiten trägt „~“. Aktivitätsenergie ist immer ein Schätzwert der Geräte; der Text der Aufschlüsselung sagt das.
- **Unbekannt ist nicht 0:** Ein fehlender Nährwert wird nie als 0 gespeichert, angezeigt oder nach Health geschrieben.
- **Health:**
  - Die bestehende Berechtigungsgruppe (`HealthKitStore.shareTypes`, `coreReadTypes`, `HealthKitStore.swift:32–35`) bleibt unverändert; `HealthShareKind` bekommt keine neuen Fälle. Jede neue Typgruppe hat eigenen Status und eigene Anfrage nach dem Muster der Schritte (`stepsAccess`, `requestStepsAuthorization`, `:60–66`).
  - Tagessummen kommen aus Statistik-Abfragen, nie aus addierten Einzelwerten.
  - Ohne lesbaren Wert steht „–“, nie 0. Logs enthalten Fehlercodes, nie Werte.
  - iOS meldet ein verweigertes Lesen nicht. Jede Lesefunktion dieses Plans hat deshalb einen Zustand „keine Daten“, der beide Fälle abdeckt, und einen Ersatzweg in Tagwerk.
- **Datenschutz:**
  - Gesundheitsdaten (Gewicht, Körperdaten, Ernährungs- und Aktivitätswerte, Ziele) gehen ausschließlich im Chat „Ziele planen“ an ChatGPT, nur mit `goalPlanningConsent`, nur als das in `GoalDataSheet` gezeigte Paket. Der allgemeine Assistent, der Aufgaben-Chat und die Notiz-Funktionen bekommen keine dieser Funktionen.
  - Die Zusagen in `MealConsentSheet` und `NoteConsentSheet` („Nicht gesendet werden Daten aus Health, deine Ziele …“) bleiben wörtlich wahr.
  - Das Datenpaket steht in keinem Log, keiner Diagnose und nicht im gespeicherten Chatverlauf.
  - Die Online-Suche (Open Food Facts) sendet Suchwort oder Strichcode an einen Dritten. Sie läuft nur mit `foodLookupConsent`, nur auf ausdrückliches Tippen, ohne Konto und ohne weitere Angaben über den Nutzer.
  - Tagwerk gibt keine medizinische Beratung; Einwilligungsblatt und Vorschlagskarte sagen das.
- **SwiftData:** Neue Attribute sind optional oder haben einen Standardwert. Jedes neue Modell steht in `ModelContainerFactory.schema` und hat entweder einen `BackupEntity`-Wert oder einen Eintrag mit Begründung in `BackupCoverage.excluded`. Neue Felder in `BackupDTOs` sind optional.
- **SwiftUI-Falle:** Nie `.sheet`, `.confirmationDialog` oder `.alert` an eine `Section` oder Zeile in `Form`/`List` hängen.
- **Mitteilungen:** Dieser Plan belegt keinen Platz im Mitteilungskontingent (KG5a, ZI6b).
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** `app/test-all.sh` nach jedem Task (`TAGWERK_SKIP_UI_TESTS=1` für Zwischenstände, voller Lauf vor dem letzten Commit jedes Strangs).

## Ausgangslage (Befunde aus dem Quelltext, `origin/main` `8326a3c`)

Pfade unter `app/`, sofern nicht anders genannt.

1. **Ein Posten kennt vier Nährwerte.** `MealItem` hat `kcalMin`, `kcal`, `kcalMax`, `protein`, `carbs`, `fat` und einen Faktor von 0,5 bis 3 (`Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift:35–99`). Posten liegen als JSON in `MealRecord.itemsData` (`Tagwerk/Capture/IntakeRecords.swift:17`); neue Felder sind über `decodeIfPresent` rückwärtsverträglich.
2. **Die Tagessumme zählt nur eigene Einträge.** `IntakeRules.dayIntake` summiert Mahlzeiten und Getränke aus Tagwerks Datenbank (`Intake.swift:264–273`); aus Health werden Trainings und Schritte gelesen, keine Ernährung.
3. **Das Kalorienziel ist eine feste Zahl.** `AppSettings.goalKilocalories` (2.300), `goalWaterMilliliters`, `goalProteinGrams` mit `proteinGoalEnabled`, `goalStepsPerDay`, `goalWorkoutMinutesPerWeek` (`Tagwerk/Persistence/AppSettings.swift`); der Kommentar nennt sie Platzhalter. Eine Geschichte der Ziele gibt es nicht.
4. **Der Tageskopf rechnet „gegessen / Ziel“.** `DaySummary` (`Tagwerk/Capture/CaptureView.swift`) nutzt `IntakeFormat.remaining`; dieselbe Rechnung steht im Kopf von „Planen“ (`IntakeFormat.planHeaderLine`), im Widget (`SnapshotIntake`, `WidgetSnapshot.swift`) und im Wochenrückblick (`WeekReview.swift`, `WeekReviewModel.swift`). `CaptureView.swift` und `WeekReviewModel.swift` haben sich seit dem Entwurf geändert (PR #240–#252: +9 und +42 Zeilen); Zeilenangaben sind vor der Umsetzung neu zu bestimmen.
5. **Eigene Trainings werden mit Kalorien nach Health geschrieben.** `HealthKitStore.save(_ workout:)` hängt ein `activeEnergyBurned`-Sample mit Tagwerk-Marke an das Training (`Packages/HealthBridge/Sources/HealthBridge/HealthKitStore.swift:108–132`). Wer die Aktivitätsenergie aus Health liest und eigene Trainings addiert, zählt sie doppelt.
6. **Aktivitätsenergie wird nicht gelesen.** Lesen kann `HealthKitStore` nur fremde Trainings (`foreignWorkouts`, `:154`) und Schritte als Tagessumme über `HKStatisticsCollectionQueryDescriptor` (`dailySteps`, `:183`).
7. **Ein neuer Typ in der bestehenden Berechtigungsgruppe hält die Spiegelung an.** `access()` fragt den Status für `shareTypes` und `coreReadTypes` ab (`HealthKitStore.swift:48–53`). `HealthMirror.runOnce` schreibt nichts, solange `access.wasAsked` falsch ist (`Tagwerk/Capture/HealthMirror.swift`). Schritte haben deshalb eine eigene Gruppe.
8. **Eigene Samples sind doppelt gekennzeichnet.** Jedes von Tagwerk geschriebene Sample trägt Metadaten mit Marke, Sync-Kennung, Eintrags-ID und Version (`HealthMapping.metadata`); `HealthMapping.isOwn` erkennt eigene Samples zuerst an der Quelle (Bundle-ID), ersatzweise an der Marke (`HealthMapping.swift:123–127`). Gelöscht wird über ein Metadaten-Prädikat (`HealthKitStore.swift:143–146`). Darauf baut der Ausschluss eigener Einträge in NU5b.
9. **`HealthMapping.nutrientPlan` schreibt Werte über 0 und entfernt den Rest.** „Unbekannt“ muss dort wie „entfernen“ behandelt werden, darf in Tagwerk aber nicht zu 0 werden.
10. **Die Schätzung hat ein strenges Antwortformat** mit Pflichtfeldern je Posten (`Tagwerk/Capture/MealEstimator.swift:52–53`, Schema `meal_estimate`; `MealEstimateOutput` in `Intake.swift`). Gesendet werden nur Text und Foto der Mahlzeit.
11. **Bestehende Einwilligungen schließen Health und Ziele aus.** `MealConsentSheet.swift` und `NoteConsentSheet.swift` sagen das wörtlich. Einwilligungsfelder: `mealEstimationConsent`, `shoppingSortConsent` mit `shoppingSortConsentVersion` (Muster für eine Einwilligung mit Textversion, `AppSettings.swift:82–87, 295–303`), `shoppingRecipeConsent`, `mailSummaryConsent`, `noteAssistantConsent`, `noteSuggestionConsent`.
12. **Der Assistent kennt keine Ernährung.** `AppTools` hat Funktionen für Aufgaben, Termine, Einkauf, Suche, Notizen und Planung; lesende stehen in `readTools` (`Tagwerk/AI/AppTools.swift:14–15`), alle anderen brauchen eine bestätigte Karte. Kontexte: `planning`, `tasks`, `settings`, `capture`, `task` (`AssistantModel.swift:12–19`).
13. **Die Bausteine aus #173 sind auf `main` (PR #242):**
    - `ToolHandler.storedForm(of:output:)` und `showsActivity(_:)` (`Conversation.swift:41–52`); `AppTools` kürzt damit `search` und `read_note` (`AppTools.swift:72–83`), `TaskChatTools` reicht beides an seine Basis durch (`TaskChat.swift:79–83`).
    - `Conversation.storableHistory` und `reduceToStoredForm()` (`Conversation.swift:185, 211`); `AssistantModel.persist()` speichert nur die Kurzform (`AssistantModel.swift:463`). Im Arbeitsspeicher der Sitzung bleibt der volle Verlauf, bis der Chat gewechselt (`switchThread`, `:119–131`) oder die Sitzung beendet wird (`endNoteSession`, `:405–410`).
    - `ChatMessage.Content.activity` (`Conversation.swift:70`) und die Zeile „Gelesen: …“ in `ChatView.swift:212–217`; den Text liefert `AssistantModel.activityText` (`:445–451`), bisher nur für `read_note`.
    - `AssistantModel.singleConfirmationTools` (`:206`, bisher `["assign_task"]`), `needsSingleConfirmation`, `batchConfirmable` und der Hinweis „Zuweisungen bestätigst du einzeln.“ (`:210–224`); `confirmAll` lässt geschützte Karten offen (`:353–364`).
    - `ActionCard.warning`, `confirmTitle`, `isDestructive` (`:575–585`); `ActionCardView` zeigt die Warnung rot (`ChatView.swift:300–302`). Eine **zweite Bestätigung** bei einer Warnung gibt es nicht; sie ist in G6 neu.
    - Die Einwilligung für Notizen wird beobachtet und beendet bei Widerruf die Sitzung (`watchNoteConsent`, `syncNoteConsent`, `:414–441`). Dasselbe Muster braucht die Zielplanung.
14. **Karten kennen kein „Anpassen“.** `ActionCardView` hat „Verwerfen“ und „Bestätigen“ (`ChatView.swift:285–330`); `Conversation.confirm` führt die Argumente des Modells unverändert aus (`Conversation.swift:140–148`). Das Mockup ZI3b setzt „Anpassen“ voraus; die Grundlage dafür entsteht im Plan `2026-11-21-ki-vorschlaege-anpassen.md`.
15. **Mitteilungskontingent:** im Quelltext 50 / 6 / 1 / 7 (`NotificationBudget.swift`), nach `2026-11-20-g2-notizen-routinen.md` künftig 44 / 17 / 1 / 2.
16. **Diagramme:** Im Projekt wird `Charts` nicht importiert; der Wochenrückblick arbeitet mit Balken aus `ProgressView`.
17. **Rezept-Notizen haben keine Nährwerte** (`RecipeNote.swift`, `IngredientLine.swift`).

## Rechenregeln (verbindlich)

- **Aktiv des Tages** = Tagessumme der Aktivitätsenergie aus Health + Kalorien eigener Trainings dieses Tages, die noch nicht in Health stehen (`healthSynced == false`) oder deren Kalorien Health nicht annehmen durfte. Ohne lesbare Health-Summe: nur die eigenen Trainings, Anzeige „Aktiv“ mit dem Zusatz, dass Health keine Werte liefert. Es gibt **keine Abzugsregel** für Trainings, die zugleich die Uhr aufgezeichnet hat (BU2a; Anmerkung des Nutzers: „Wenn es von der Uhr eingetragen wurde, schreibe ich es eh nicht nochmal in Tagwerk.“). Der Gerätetest dazu bleibt.
- **Angerechnet** = Anteil × Aktiv, auf 10 kcal gerundet; Anteil ∈ {0, 0,5, 0,75, 1}, Voreinstellung 0,5 (BU1b; Festlegung des Nutzers vom 21.11.2026 nach der Faktenprüfung, abweichend von den 100 % im Mockup).
- **Gegessen** = eigene Einträge aus Tagwerks Datenbank + Tagessumme fremder Einträge aus Health (nur bei eingeschaltetem „Einträge anderer Apps mitzählen“). Eigene Einträge kommen nie aus Health, fremde nie aus der Datenbank; so zählt nichts doppelt.
- **Budget** = Grundziel des Tages + Angerechnet. **Noch** = Budget − Gegessen.
- **Makros (BU3c):** Eiweiß und Ballaststoffe bleiben in Gramm. Mit Grundzielen KH₀ und F₀ (Gramm) gilt: Kohlenhydrat-Ziel = KH₀ + Angerechnet × (4 × KH₀) / (4 × KH₀ + 9 × F₀) / 4; Fett-Ziel = F₀ + Angerechnet × (9 × F₀) / (4 × KH₀ + 9 × F₀) / 9. Beispiel bei voller Anrechnung: 250 g, 78 g, 520 kcal → 326 g und 102 g.
- **Grundziel** gilt für einen Tag ohne angerechnete Aktivität. Das steht im Einstellungs- und Kartentext.
- **Gewicht des Tages** = früheste Messung des Tages (eigene und fremde). **7-Tage-Mittel** = Mittel der Tageswerte der letzten sieben Tage, ab drei Werten. **Trend** = Differenz der 7-Tage-Mittel im Abstand von 28 Tagen, geteilt durch 4, in kg je Woche; ohne ausreichende Werte „–“.
- **Gegenrechnung (ZI2b), alle Zahlen als benannte Konstanten in `GoalGuardConstants` – geprüft am 21.11.2026** (Quelle: `docs/superpowers/research/2026-11-21-ernaehrung-faktenpruefung.md`):

  | Konstante | Wert | Bedeutung | Stand |
  |---|---|---|---|
  | `mifflinWeightFactor`, `mifflinHeightFactor`, `mifflinAgeFactor`, `mifflinMaleOffset`, `mifflinFemaleOffset` | 10 · 6,25 · 5 · +5 · −161 | Ruheumsatz = 10 × kg + 6,25 × cm − 5 × Alter + 5 bzw. − 161 (Mifflin et al. 1990, doi:10.1093/ajcn/51.2.241). Text: „Schätzwert, Einzelfehler von ±10 % und mehr möglich“ | bestätigt |
  | `baseNeedFactor` | 1,2 | **Grundbedarf ohne Bewegung** = Ruheumsatz × 1,2; Grundlage des Tagesbudgets, zu dem die angerechnete Aktivenergie kommt (Modell wie Apple Health: Ruhe- plus Aktivenergie). Nie als „Bedarf“ beschriften | bestätigt in dieser Rolle (als Gesamtbedarf zu niedrig, FAO/WHO/UNU 2004, DGE, EFSA) |
  | `fallbackActivityFactor` | 1,4 | Gesamtumsatz für die Defizitwarnung, wenn keine Aktivenergie aus Health vorliegt (PAL „sitzend“, DGE/EFSA/FAO) | neu |
  | `activityAverageDays` | 14 | Gesamtumsatz für die Defizitwarnung = Grundbedarf + mittlere Aktivenergie (voll, nicht der angerechnete Anteil) der letzten 14 Tage | neu, Festlegung der Hauptsitzung |
  | `kcalPerKilogramBodyMass` | 7.700 | Nur kurzfristige Näherung (4–8 Wochen) für Tempo ↔ Tagesdefizit; Text: „grobe Schätzung, der tatsächliche Verlauf flacht ab“; Verweis auf den NIDDK Body Weight Planner. Hauptprüfung über das tägliche Defizit | bestätigt mit Einschränkung (Hall et al. 2011) |
  | `maxWeeklyChangeShare`, `maxWeeklyChangeKilograms` | 0,01 · 1,0 | Warnung, wenn das Tempo `min(1 % Körpergewicht, 1 kg)` je Woche übersteigt; als Regel der App formulieren, nicht als Leitlinie (CDC: 0,45–0,9 kg/Woche) | angepasst |
  | `softMinimumKcalFemale`, `softMinimumKcalMale` | 1.200 · 1.500 | Warnung bei Grundziel darunter (AHA/ACC/TOS 2013, sekundär) | neu |
  | `hardMinimumKcal` | 1.000 | Ziel darunter lässt sich nicht übernehmen (NIDDK Body Weight Planner) | neu |
  | `minimumProteinPerKilogram`, `minimumProteinPerKilogramFrom65` | 0,8 · 1,0 | Warnung darunter, bezogen auf das Referenzgewicht (bei BMI über 25: Gewicht bei BMI 22) (DGE) | neu |
  | `fibreHint`, `fibreHintPer1000Kcal` | 30 g · 14,6 g | Nur Hinweis, keine Warnung (DGE) | neu |
  | `drinkHintLitres` | 1,5 | Nur Hinweis zur Trinkmenge (DGE: Getränke etwa 1,2–1,5 l) | neu |
  | `activityCreditShareDefault` | 0,5 | Voreinstellung des Anrechnungsanteils (BU1b, Nutzer 21.11.2026); Handgelenk-Geräte schätzen ungenau, Apple eher zu hoch (Fuller et al. 2020) | entschieden |
  | `macroEnergyTolerance` | 0,10 | Warnung, wenn 4 × Eiweiß + 4 × Kohlenhydrate + 9 × Fett um mehr als 10 % vom Grundziel abweicht | Festlegung dieses Plans |

  Weitere Warnung ohne eigene Konstante: Grundziel unter dem geschätzten Ruheumsatz. Kein anderer Ort im Quelltext nennt diese Zahlen; Texte auf der Karte lesen sie aus den Konstanten, jede Konstante trägt ihren Quellenkommentar aus dem Prüfbericht. Sie sind Rechenhilfen, keine medizinischen Grenzwerte.

## Review Focus

1. **Keine Doppelzählung der Aktivität:** Ein in Tagwerk eingetragenes Training zählt vor und nach dem Spiegeln genau einmal. Tests in B3 und C1; Gerätetest mit und ohne Uhr.
2. **Keine Doppelzählung des Essens:** Eine in Tagwerk erfasste Mahlzeit erscheint nach dem Spiegeln nicht zusätzlich als fremder Eintrag. Tests in B5; Gerätetest.
3. **Spiegelung läuft weiter:** Nach dem Update fragt `access()` bei bestehenden Nutzern nicht erneut; Mahlzeiten, Wasser und Trainings werden ohne neue Zustimmung gespiegelt. Test in B1.
4. **Unbekannt bleibt unbekannt:** Alte Mahlzeiten haben nach dem Update keine Ballaststoff-Null; Summen nennen die Abdeckung; Health bekommt kein 0-Sample. Tests in A1, B2, D3.
5. **Ein Budget an allen Orten:** Tageskopf, Kopf von „Planen“, Widget und Wochenrückblick zeigen dieselbe Zahl für denselben Tag. Tests in C1–C4.
6. **Vergangene Tage rechnen mit ihrem Zielstand und ihren festgehaltenen Health-Werten.** Tests in A2 und C4.
7. **Gesundheitsdaten nur im Zielchat:** Ohne `goalPlanningConsent` liefert keine Funktion Werte; der allgemeine Assistent und die Notiz-Vorschläge haben die Funktionen nicht; das Paket enthält nur eingeschaltete Gruppen. Tests in G4 und G5.
8. **Gespeicherter Verlauf ohne Datenpaket.** Test in G7.
9. **Karten:** Zielkarten werden einzeln bestätigt; eine Karte mit Warnung verlangt eine zweite Bestätigung; nach „Übernehmen“ existiert genau ein neuer Zielstand; eine von Hand angepasste Karte wird neu gegengerechnet. Tests in G6.
10. **Online-Suche:** Ohne Einwilligung, ohne Netz und ohne Tippen geht keine Anfrage hinaus; die Abfragegrenze hält. Tests in E4.

---

## Strang A: Grundlagen (Regeln und Datenmodell)

### Task A1: `NutrientValues` und erweiterte Posten

**Entscheidungen:** NU1b, NU4b.

**Files:**
- Create: `Packages/TagwerkCore/Sources/TagwerkCore/NutrientValues.swift`, Tests `NutrientValuesTests.swift`
- Modify: `Packages/TagwerkCore/Sources/TagwerkCore/Intake.swift` (`MealItem`, `MealValue`, `DayIntake`, `IntakeRules.dayIntake`, `MealEstimateOutput`), `IntakeFormat.swift`

- [ ] **Step 1: Tests.** `mealItem_decodesOldJSONWithoutNewFields`, `sum_ignoresUnknownAndCountsCoverage`, `sum_allUnknown_isNil`, `scaled_keepsUnknown`, `format_minimumWithCoverage` („mind. 14 g · 2 von 3 Mahlzeiten“), `salt_fromSodium`.
- [ ] **Step 2:** `enum Nutrient { fiber, sugar, saturatedFat, salt }` mit `displayName`, Einheit und der Angabe, ob Ziel oder Obergrenze. `MealItem` bekommt `fiber`, `sugar`, `saturatedFat`, `salt` als `Double?` (`decodeIfPresent`), dazu `total…`-Werte mit Faktor.
- [ ] **Step 3:** `DayIntake` bekommt je Nährwert `NutrientSum(value: Double?, known: Int, total: Int)`; `IntakeRules.dayIntake` füllt sie. Bestehende Initialisierer bleiben mit Standardwerten nutzbar.
- [ ] **Step 4:** `IntakeFormat.nutrient(_:goal:)` für Zeilenwerte samt Abdeckungstext; Katalogeinträge.
- [ ] **Step 5:** Commit `feat: add optional fibre, sugar, saturated fat and salt to meal items`.

### Task A2: Zielstände `GoalPlan` und `GoalTimeline`

**Entscheidungen:** ZI5b, ZI4b, BU1b.

**Files:**
- Create: `Packages/TagwerkCore/Sources/TagwerkCore/GoalPlan.swift`, Tests; `Tagwerk/Capture/GoalRecords.swift` (`GoalPlanRecord`), `Tagwerk/Capture/GoalStore.swift`, Tests
- Modify: `Tagwerk/Persistence/ModelContainerFactory.swift`, `Tagwerk/Persistence/AppSettings.swift` (`goalPlansMigrated`, `activityCreditPercent` = 50), `Tagwerk/App/AppEnvironment.swift`

- [ ] **Step 1: Tests.** `timeline_planForDay_picksLatestNotAfter`, `timeline_beforeFirstPlan_usesFirst`, `migration_createsOnePlanFromSettings` (Eiweiß nur bei `proteinGoalEnabled`), `migration_runsOnce`, `store_adopt_sameDayReplaces`.
- [ ] **Step 2:** `GoalPlan`: `validFrom: PlanDay`, `kcal`, `proteinGrams?`, `carbsGrams?`, `fatGrams?`, `fiberGrams?`, `sugarLimitGrams?`, `waterMilliliters`, `stepsPerDay`, `workoutMinutesPerWeek`, `activeKcalPerDay` (0 = aus), `targetWeightKg?`, `paceKgPerWeek?`, `origin` (`manual`, `assistant`), `note`.
- [ ] **Step 3:** `GoalPlanRecord` (SwiftData, alle Felder mit Standardwert) und `GoalStore` (`plans()`, `current(on:)`, `adopt(_:)`, `delete(_:)`). Einmalige Übernahme der heutigen Einstellungen als erster Zielstand mit `validFrom` = Tag der ältesten Mahlzeit oder heute. Ein übernommener Zielstand gilt ab heute, nie rückwirkend.
- [ ] **Step 4:** Die bisherigen Felder in `AppSettings` bleiben im Schema (Attribute werden nie entfernt) und werden bei jeder Übernahme mitgeschrieben, bis alle Leser umgestellt sind (C1–C4); danach liest niemand mehr direkt.
- [ ] **Step 5:** Commit `feat: store goals as dated goal plans`.

### Task A3: `EnergyBudget`

**Entscheidungen:** BU1b, BU3c.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/EnergyBudget.swift`, Tests.

- [ ] **Step 1: Tests.** `credited_roundsToTens`, `credited_shareZero_isZero`, `credited_share75` (520 → 390), `credited_defaultShareIsHalf` (520 → 260), `budget_exampleDay_fullCredit` (2.300, 520, 1.340 → 2.820, 1.480), `budget_exampleDay_defaultCredit` (→ 2.560, 1.220), `macros_proteinFixed_restScales` (250/78/520 → 326/102), `macros_withoutCarbOrFatGoal_staysNil`, `remaining_over_isNegativeAndMarked`, `activeUnknown_usesOwnWorkoutsOnly`, `eaten_includesForeignIntake`.
- [ ] **Step 2:** `struct ActiveEnergy { healthKcal: Double?; unsyncedOwnKcal: Double }`, `EnergyBudget.make(plan:active:creditPercent:eatenKcal:)` mit `base`, `credited`, `budget`, `remaining`, `scaledCarbs`, `scaledFat`, `isEstimated`.
- [ ] **Step 3:** `IntakeFormat.budgetRemaining` („noch ~1.480“, „~120 über Budget“) und `planHeaderLine` mit Budget (alte Signatur bleibt bis C4).
- [ ] **Step 4:** Commit `feat: add the daily energy budget rules`.

### Task A4: Festgehaltene Health-Werte des Tages und Sicherung

**Entscheidungen:** OR4b, NU5b (vergangene Tage dürfen nicht davon abhängen, dass Health später dieselben Werte liefert).

**Files:** Create `Tagwerk/Capture/DayHealthRecord.swift`, `DayHealthStore.swift`, Tests; Modify `Tagwerk/Backup/BackupDTOs.swift`, `BackupService.swift`, `BackupCoverage.swift`, Schema; Tests der Sicherung.

- [ ] **Step 1: Tests.** `record_upsertsPerDay`, `record_keepsLastKnownWhenHealthUnreadable` (ein späteres „keine Daten“ überschreibt keinen gespeicherten Wert), `backup_roundTripsGoalPlansAndDayHealth`, `backup_oldFileWithoutNewLists_decodes`, Vollständigkeitstest bleibt grün.
- [ ] **Step 2:** `DayHealthRecord`: Tag, `activeKcal: Double?`, `creditPercent: Int`, `foreignKcal: Double?`, fremde Nährwerte je Größe (`Double?`), `foreignWaterMilliliters: Double?`, `foreignSources: [String]`, `updatedAt`. Geschrieben beim Laden eines Tages und beim Tageswechsel; der heutige Tag wird bei jedem Laden überschrieben, vergangene Tage nur, wenn Health einen Wert liefert.
- [ ] **Step 3:** `GoalPlanBackup`, `DayHealthBackup`; neue Einstellungsfelder optional. `FoodRecord` und `WeightRecord` kommen in E1 und F1 dazu.
- [ ] **Step 4:** Commit `feat: keep the day's Health totals and include goal plans in the backup`.

---

## Strang B: HealthBridge

### Task B1: Berechtigungsgruppen

**Entscheidungen:** NU1b, BU2a, KG2a, KG4b, NU5b, PV4b.

**Files:** Modify `HealthEntries.swift`, `HealthStoring.swift`, `HealthKitStore.swift`, `HealthMapping.swift`; `Tagwerk/Capture/DemoHealthStore.swift`, Test-Fakes; `app/project.yml`, `Tagwerk/Info.plist`, `Tagwerk/InfoPlist.xcstrings`.

Gruppen (jede mit eigenem Status und eigener Anfrage, nie zusammen mit der bestehenden Gruppe):

| Gruppe | Typen | Richtung | Anfrage ausgelöst durch |
|---|---|---|---|
| `moreNutrients` | `dietaryFiber`, `dietarySugar`, `dietaryFatSaturated`, `dietarySodium` | schreiben | Kachel in den Einstellungen „Weitere Nährwerte nach Health“ |
| `activeEnergy` | `activeEnergyBurned` | lesen | Kachel „In Health erlauben“ im Tageskopf |
| `body` | `bodyMass`, `bodyFatPercentage` | lesen und schreiben | erstes Sichern eines Gewichts oder Schalter in den Einstellungen |
| `foreignNutrition` | `dietaryEnergyConsumed`, `dietaryProtein`, `dietaryCarbohydrates`, `dietaryFatTotal`, `dietaryFiber`, `dietarySugar`, `dietaryFatSaturated`, `dietarySodium`, `dietaryWater` | lesen | Schalter „Einträge anderer Apps mitzählen“ |
| `bodyProfile` | `height` (Messwert), `dateOfBirth`, `biologicalSex` (Stammdaten) | lesen | Knopf „Aus Health lesen“ im Abschnitt „Körper“ |

- [ ] **Step 1: Tests.** `coreTypes_unchanged` (Menge der Typen in `shareTypes` und `coreReadTypes` ist exakt die heutige), `group_status_notAskedThenAsked`, `writeGroups_disjointFromCoreShareTypes`, `foreignNutrition_readOnly_doesNotChangeShareStatus`.
- [ ] **Step 2:** `enum HealthAccessGroup` mit den fünf Typmengen, `groupAccess(_:)` und `requestAuthorization(for:)` nach dem Muster von `stepsAccess`. Schreibstatus je Typ über `authorizationStatus(for:)`. Lesegruppen kennen nur „noch nicht gefragt“ und „gefragt“; „gefragt“ sagt nichts darüber, ob gelesen werden darf.
- [ ] **Step 3:** Texte der Systemabfrage ergänzen (Gewicht, Aktivitätsenergie, weitere Nährwerte, Ernährungseinträge anderer Apps, Größe, Geburtsdatum, Geschlecht), deutsch und englisch.
- [ ] **Step 4:** Commit `feat: add separate Health permission groups`.

### Task B2: Weitere Nährwerte schreiben

**Hängt ab von:** B1, A1.

**Files:** Modify `HealthEntries.swift` (`HealthMeal` mit optionalen Werten), `HealthMapping.swift` (`Nutrient`, `nutrientPlan`), `HealthKitStore.swift` (`save(_ meal:)`, `deleteEntry`), `Tagwerk/Capture/IntakeStore.swift` (`healthValue`).

- [ ] **Step 1: Tests.** `nutrientPlan_unknown_isRemovedNotWritten`, `nutrientPlan_zeroKnown_isRemoved`, `save_skipsGroupNotAsked_andStillCountsAsMirrored`, `salt_writtenAsSodium`.
- [ ] **Step 2:** Die neuen Nährwerte werden nur geschrieben, wenn ihre Gruppe erlaubt ist; ein später erteilter Zugriff setzt `healthSynced` der Mahlzeiten mit solchen Werten zurück (einmaliger Nachlauf über `HealthMirror`).
- [ ] **Step 3:** Commit `feat: mirror fibre, sugar, saturated fat and sodium to Health`.

### Task B3: Aktivitätsenergie als Tagessumme

**Entscheidungen:** BU2a. **Hängt ab von:** B1.

**Files:** Modify `HealthEntries.swift` (`DailyActiveEnergy`), `HealthStoring.swift`, `HealthKitStore.swift` (Abfrage wie `dailySteps`), `HealthMapping.swift`, Fakes.

- [ ] **Step 1: Tests.** `dailyActiveEnergy_dropsDaysWithoutStatistics`, `dailyActiveEnergy_emptyWhenNotAuthorized`, Fake-Test `ownWorkoutEnergy_countedOnce` (gespiegelt: nur Health-Summe; ungespiegelt: Health-Summe + eigenes Training).
- [ ] **Step 2:** `dailyActiveEnergy(in:calendar:)` mit `cumulativeSum`; keine Quellenfilter, keine Abzugsregel.
- [ ] **Step 3:** Commit `feat: read daily active energy from Health`.

### Task B4: Gewicht lesen und schreiben

**Entscheidungen:** KG2a, KG4b. **Hängt ab von:** B1.

**Files:** Modify `HealthEntries.swift` (`HealthWeight`, `ForeignWeight`, `HealthEntryKind.weight` ohne Rückgriff auf `HealthShareKind`), `HealthStoring.swift`, `HealthKitStore.swift`, `HealthMapping.swift`.

- [ ] **Step 1: Tests.** `syncIdentifier_weight`, `foreignWeights_filtersOwn`, `save_weight_deniedReturnsFalse`, `deleteEntry_weight_onlyBodyTypes`.
- [ ] **Step 2:** Schreiben mit Sync-Kennung und Version wie bei Getränken; Körperfett als zweites Sample desselben Eintrags; Lesen fremder Messungen im Zeitraum, eigene über `HealthMapping.isOwn` ausgeschlossen.
- [ ] **Step 3:** Commit `feat: read and write body weight in Health`.

### Task B5: Ernährungseinträge anderer Apps als Tagessummen

**Entscheidungen:** NU5b (machbar, Begründung im Abschnitt „NU5: Entscheidung über die Machbarkeit“). **Hängt ab von:** B1.

**Files:** Modify `HealthEntries.swift` (`DailyForeignNutrition`), `HealthStoring.swift`, `HealthKitStore.swift`, `HealthMapping.swift` (`foreignPredicate`), Fakes.

- [ ] **Step 1: Tests.** `foreignPredicate_excludesMarkerAndOwnSource`, `dailyForeignNutrition_perNutrientNilWhenNoSamples` (kein Sample ≠ 0), `dailyForeignNutrition_sodiumToSalt`, `dailyForeignNutrition_namesSources`, `dailyForeignNutrition_emptyWhenGroupNotAsked`, Fake-Test `ownMeal_mirrored_notCountedAsForeign`.
- [ ] **Step 2:** Je Typ eine Statistik-Abfrage über den Zeitraum mit Tagesintervallen und einem Prädikat, das eigene Samples ausschließt: **nicht** mit Tagwerks Marke in den Metadaten (`HealthMapping.markerKey`) **und nicht** aus der eigenen Quelle. Statistik-Abfragen lassen kein nachträgliches Filtern zu; deshalb liegt der Ausschluss im Prädikat. Quellenname über `separateBySource` bzw. die Quellen der Statistik.
- [ ] **Step 3:** Ergebnis je Tag und Nährwert `Double?`: `nil`, wenn Health für den Tag keine fremde Statistik liefert. `nil` bedeutet „keine fremden Einträge **oder** Lesen nicht erlaubt“; die Schnittstelle unterscheidet das nicht und dokumentiert es.
- [ ] **Step 4:** Commit `feat: read daily nutrition totals of other apps from Health`.

### Task B6: Körper-Stammdaten lesen

**Entscheidungen:** PV4b. **Hängt ab von:** B1.

**Files:** Modify `HealthEntries.swift` (`HealthBodyProfile`), `HealthStoring.swift`, `HealthKitStore.swift`, Fakes.

- [ ] **Step 1: Tests.** `bodyProfile_mapsLatestHeight`, `bodyProfile_sexNotSetOrOther_isNil`, `bodyProfile_throwingCharacteristic_isNil` (ein Fehler je Feld macht nur dieses Feld leer), `bodyProfile_allNilWhenNotAsked`.
- [ ] **Step 2:** `bodyProfile() async -> HealthBodyProfile` mit `heightCm: Double?` (jüngster Messwert), `birthYear: Int?` (aus dem Geburtsdatum nur das Jahr), `sex: FormulaSex?` (`female`, `male`; `other` und `notSet` → `nil`). Jedes Feld einzeln, jeder Fehler wird zu `nil`.
- [ ] **Step 3:** Commit `feat: read height, birth year and sex from Health`.

---

## Strang C: Tagesbudget in der Oberfläche

### Task C1: `CaptureModel` rechnet mit Zielstand, Budget und fremden Einträgen

**Entscheidungen:** BU1b, BU2a, NU5b. **Hängt ab von:** A2, A3, A4, B3, B5.

**Files:** Modify `Tagwerk/Capture/CaptureModel.swift` (`CaptureDay`, `HealthCache`, `reload`, `page(for:)`, `planHeaderLine`), `IntakeStore.swift` (`unsyncedWorkoutKcal(on:)`), Tests.

- [ ] **Step 1: Tests.** `budget_usesPlanOfShownDay`, `budget_healthSumPlusUnsyncedOwn`, `budget_withoutHealth_ownWorkoutsOnly`, `eaten_ownPlusForeign_whenSwitchedOn`, `eaten_ownOnly_whenSwitchedOff`, `pastDay_usesStoredDayHealthWhenHealthSilent`, `neighbourPage_usesCachedHealthTotals`, `reload_keepsBudgetWhileHealthAnswers`.
- [ ] **Step 2:** `CaptureDay` bekommt `plan: GoalPlan`, `active: ActiveEnergy`, `foreign: ForeignIntake?`, `budget: EnergyBudget`; der Health-Cache nimmt Aktivitätsenergie und fremde Ernährung der Woche auf (je eine Abfrage wie bei den Schritten) und schreibt `DayHealthRecord`.
- [ ] **Step 3:** Commit `feat: compute the day's energy budget in the capture model`.

### Task C2: Tageskopf mit Rechenzeile und Aufschlüsselung

**Entscheidungen:** BU4b. **Hängt ab von:** C1.

**Files:** Modify `Tagwerk/Capture/CaptureView.swift` (`DaySummary`), Create `Tagwerk/Capture/BudgetBreakdownSheet.swift`; UI-Test, Katalog.

- [ ] **Step 1: Tests.** UI-Test `captureHead_showsBudgetEquation`; Barrierefreiheit: die Rechenzeile ist ein Element mit gesprochenem Satz („Noch etwa 1.480 Kilokalorien: Ziel 2.300, plus 520 aktiv, minus etwa 1.340 gegessen“).
- [ ] **Step 2:** Rechenzeile, Budgetbalken (Gegessen, Strich am Grundziel, Zugewinn), Kachel „In Health erlauben“ für die Aktivitätsenergie nach dem Muster der Schritte-Kachel.
- [ ] **Step 3:** Blatt „Aktiv heute“: Trainings (eigene, fremde), Alltag als Rest, Anteil, Hinweis auf Schätzwerte.
- [ ] **Step 4:** Commit `feat: show the energy budget in the capture head`.

### Task C3: Einstellungen

**Entscheidungen:** BU1b, ZI4b, ZI5b, NU5b. **Hängt ab von:** A2.

**Files:** Modify `Tagwerk/Settings/CaptureSettingsView.swift`, `AppSettings.swift` (`countsForeignNutrition` = false, `saturatedFatEnabled`, `saltEnabled`, `bodyFatEnabled`); Create `Tagwerk/Settings/GoalPlanView.swift` (aktueller Zielstand bearbeiten, frühere Stände).

- [ ] **Step 1: Tests.** `editingGoal_createsNewPlanFromToday`, `editingSameDayTwice_replaces`, `foreignSwitch_on_requestsGroupOnce`, `foreignSwitch_off_hidesForeignRowsAndSums`.
- [ ] **Step 2:** „Aktivität anrechnen“ (aus, 50 %, 75 %, 100 %; Voreinstellung 50 %) mit Fußtext zum Grundziel; Ziele aus `GoalStore` statt aus Einzelfeldern; Schalter für gesättigte Fettsäuren, Salz und Körperfett.
- [ ] **Step 3:** Schalter „Einträge anderer Apps mitzählen“ mit Fußtext: „Tagwerk liest dafür Ernährungseinträge aus Health, die nicht von Tagwerk stammen. iOS teilt Tagwerk nicht mit, ob du das Lesen erlaubt hast; ohne Erlaubnis sieht es so aus, als gäbe es keine fremden Einträge. Prüfen kannst du es in Health › Teilen › Apps › Tagwerk.“
- [ ] **Step 4:** Commit `feat: edit goal plans, the activity credit and foreign entries in the settings`.

### Task C4: Kopf von „Planen“, Widget, Wochenrückblick

**Entscheidungen:** OR2b, OR3a, OR4b. **Hängt ab von:** C1.

**Files:** Modify `WeekReview.swift`, `WidgetSnapshot.swift` (`SnapshotIntake.creditedKcal: Int?`, `foreignKcal: Int?`), `Tagwerk/Capture/WeekReviewModel.swift`, `WeekReviewView.swift`, `TagwerkWidget/WidgetViews.swift`, `Tagwerk/Planning/PlanHeader.swift`.

- [ ] **Step 1: Tests.** `planHeaderLine_showsRemainingBudget`, `snapshot_oldFileWithoutCredit_decodes`, `weekReview_dayWithinBudget_usesPlanAndStoredHealthOfThatDay`, `weekReview_unknownActivity_fallsBackToBaseGoal`.
- [ ] **Step 2:** Umstellung der drei Orte auf `EnergyBudget`; vergangene Tage lesen `DayHealthRecord`. Der Wochenrückblick bekommt Tagesmittel der Nährwerte und den Gewichtstrend (nach F3).
- [ ] **Step 3:** Commit `feat: use the energy budget in the plan header, widget and week review`.

---

## Strang D: Nährwerte in der Oberfläche

### Task D1: Schätzung liefert weitere Nährwerte

**Entscheidungen:** NU1b. **Hängt ab von:** A1.

**Files:** Modify `Tagwerk/Capture/MealEstimator.swift` (Anweisung, `schema`), `Intake.swift` (`MealEstimateOutput.Item`, `normalized`), Tests, `Tagwerk/AI/DemoAITransport.swift`.

- [ ] **Step 1: Tests.** `schema_newFieldsRequiredAndNullable`, `normalized_nullStaysUnknown`, `normalized_negativeClampedToZero`, `decode_answerWithoutNewFields_fails` (strenges Format).
- [ ] **Step 2:** Felder `fiber_g`, `sugar_g`, `saturated_fat_g`, `salt_g` als Pflichtfelder mit erlaubtem `null`; Anweisung: lieber `null` als raten.
- [ ] **Step 3:** Commit `feat: estimate fibre, sugar, saturated fat and salt`.

### Task D2: Mahlzeitenblatt

**Entscheidungen:** NU3b. **Hängt ab von:** A1.

**Files:** Modify `Tagwerk/Capture/MealSheet.swift`; UI-Test.

- [ ] **Step 1: Tests.** `mealSheet_moreNutrients_expandAndSave`, `emptyField_savesUnknown`.
- [ ] **Step 2:** Zeile „Weitere Nährwerte“ mit Zähler; Felder mit `ValueStepper`/`NumberEntry`; leeres Feld = unbekannt.
- [ ] **Step 3:** Commit `feat: edit further nutrients in the meal sheet`.

### Task D3: Karte „Nährwerte“ und Zeile „Aus Health“

**Entscheidungen:** NU2b, BU3c, NU5b. **Hängt ab von:** A1, C1.

**Files:** Create `Tagwerk/Capture/NutrientCard.swift`, `ForeignIntakeRow.swift`; Modify `CaptureView.swift`, `CaptureModel.swift` (`summaryRows` ohne Eiweiß-Kachel).

- [ ] **Step 1: Tests.** `card_rows_followGoalPlanAndSwitches`, `sugar_overLimit_isMarked`, `row_showsCoverageWhenIncomplete`, `macroGoals_scaleWithBudget`, `foreignRow_hiddenWithoutForeignValues`, `foreignRow_namesSources`, `nutrientSum_addsForeignWithoutChangingCoverageOfOwnMeals`.
- [ ] **Step 2:** Karte mit Balkenzeilen, aufklappbar (Zustand je Gerät in `AppSettings`), VoiceOver je Zeile.
- [ ] **Step 3:** In der Liste „Essen“ eine Zeile „Aus Health · andere Apps“ mit Kalorien und den Quellennamen („Yazio, Lose It“); sie ist nicht bearbeitbar und nicht löschbar, Tippen zeigt die Werte je Nährwert und den Satz aus C3 Step 3. Fremde Werte tragen kein „~“ (Tagwerk weiß nicht, ob sie geschätzt sind), aber den Quellennamen. Die Abdeckung („2 von 3 Mahlzeiten“) bezieht sich weiter nur auf eigene Mahlzeiten.
- [ ] **Step 4:** Commit `feat: add the nutrients card and the row for entries of other apps`.

---

## Strang E: Lebensmittel

### Task E1: `FoodRecord` und `FoodStore`

**Entscheidungen:** LM1b, LM4b. **Hängt ab von:** A1, A4.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/FoodValue.swift`, Tests; `Tagwerk/Capture/FoodRecords.swift`, `FoodStore.swift`; Modify Schema und Sicherung.

- [ ] **Step 1: Tests.** `portion_gramsToItem` (250 g bei Werten je 100 g), `portion_pieces`, `item_fromFood_isExact`, `search_matchesWordsCaseInsensitive`, `backup_roundTripsFoods`.
- [ ] **Step 2:** `FoodValue`: Name, Bezug (`per100g`, `per100ml`, `perPiece(grams?)`), Kalorien und `NutrientValues`, `origin` (`typed`, `label`, `estimate`, `openFoodFacts`), optional Strichcode, optional `sourceNote` (Quelle und Abrufdatum bei fremden Daten).
- [ ] **Step 3:** Commit `feat: add own foods with reference values`.

### Task E2: Auswahl und Mengeneingabe

**Hängt ab von:** E1.

**Files:** Modify `MealSheet.swift` (Segment „Zuletzt / Meine Lebensmittel / Mahlzeiten“), Create `FoodPickerView.swift`, `FoodEditSheet.swift`.

- [ ] **Step 1: Tests.** UI-Test `addOwnFood_withGrams_addsExactItem`; `estimatedItem_saveAsFood_keepsValues`.
- [ ] **Step 2:** Auswahl mit Mengenfeld; „Als Lebensmittel sichern“ an einem Posten.
- [ ] **Step 3:** Commit `feat: pick own foods with an amount in the meal sheet`.

### Task E3: Etikett fotografieren

**Entscheidungen:** LM3b. **Hängt ab von:** E1.

**Files:** Create `Tagwerk/Capture/LabelReader.swift` (eine Anfrage nach dem Muster von `MealEstimator`), Tests; Modify `MealConsentSheet.swift` (ein Satz), `FoodEditSheet.swift`.

- [ ] **Step 1: Tests.** `labelReader_requiresMealConsent`, `labelReader_nullFieldsStayUnknown`, `labelReader_noTable_reportsNothingRecognized`.
- [ ] **Step 2:** Antwortformat `nutrition_label` (Bezug, Werte je Bezug, Stückgewicht); Vorschau füllt `FoodEditSheet`, gespeichert wird erst nach Bestätigung. Das Blatt ist zugleich die Handanpassung dieses Vorschlags (Plan „Anpassen“, Ort 14).
- [ ] **Step 3:** Commit `feat: read nutrition labels into own foods`.

### Task E4: Einwilligung und Client für Open Food Facts

**Entscheidungen:** LM1d, LM2b. **Hängt ab von:** E1. **Vor dem Bau:** Ergebnisse der Recherche (Tabelle unten) eintragen.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/ProductSearchRules.swift` (Abfragegrenze, Zuordnung der Antwort), Tests; `Tagwerk/Capture/ProductLookup.swift` (Protokoll `ProductLookingUp`, Transport austauschbar), `FoodLookupConsentSheet.swift`; Modify `AppSettings.swift` (`foodLookupConsent`, `foodLookupContact: String?`), `BackupDTOs.swift`, `CaptureSettingsView.swift`, `Tagwerk/AI/DemoAITransport.swift` bzw. ein eigener Demo-Transport.

**Fakten über Open Food Facts – geprüft am 21.11.2026** (Quelle: `docs/superpowers/research/2026-11-21-ernaehrung-faktenpruefung.md`, API-Doku, Terms, Privacy):

| Punkt | Festlegung | Stand |
|---|---|---|
| Textsuche | Search-a-licious (`search.openfoodfacts.org`) als empfohlener Weg, Ersatz `/cgi/search.pl`; v2/v3 haben keine Volltextsuche. Suche nur auf „Suchen“-Tippen, kein Suchen beim Tippen | geprüft; Bedingungen von Search-a-licious nicht gefunden → vor E4 Ersatzweg über `/cgi/search.pl` als Standard, Search-a-licious nur, wenn Bedingungen auffindbar |
| Abfrage per Strichcode | `/api/v2/product/<code>` mit `fields=` auf die benötigten Felder | geprüft |
| Abfragegrenzen | `ProductSearchRules.searchLimit` = 10 je Minute, `productLimit` = 15 je Minute (gelten pro Nutzer) | geprüft |
| Anfragekopf | `User-Agent: Tagwerk/<Version> (<Kontaktadresse des Nutzers>)`; Adresse fragt die App ab, ohne Adresse keine Anfrage | geprüft + entschieden |
| Konto/Schlüssel | Lesen ohne Konto | geprüft |
| Lizenz | Datenbank ODbL, Inhalte DbCL; Namensnennung mit Verweis auf Open Food Facts. Übernommene Produkte werden als eigener Eintrag in „Meine Lebensmittel“ mit Quellenangabe „Open Food Facts“ gespeichert; OFF-Daten nie mit eigenen Werten in einem Datensatz vermischen | geprüft |
| Bilder | CC BY-SA 3.0; werden nicht geladen | geprüft |
| Zwischenspeicher | Kein dauerhafter Zwischenspeicher für Treffer (Doku rät für nutzergetriebene Apps davon ab) | geprüft |
| Datenschutz | OFF speichert IP und Logs 3 Jahre; das steht im Einwilligungstext | geprüft |


- [ ] **Step 1: Tests.** `lookup_withoutConsent_sendsNothing`, `lookup_withoutContactAddress_sendsNothing`, `contactAddress_neverPrefilled`, `contactAddress_invalid_notAccepted`, `contactAddress_cleared_switchesLookupOff`, `lookup_offline_sendsNothingAndReportsOffline`, `limiter_blocksAboveLimit_andReportsWaitTime`, `limiter_sameQueryWithinSession_servedFromMemory`, `map_missingFieldsStayUnknown`, `map_kJOnly_convertsToKcal`, `map_saltOrSodium`, `map_perServingOnly_marksReference`, `request_hasNoCookiesNoAccountNoDeviceIdentifiers`.
- [ ] **Step 2:** Einwilligungsblatt „Online-Suche in Open Food Facts“ nach dem Aufbau von `ShoppingSortConsentSheet`:
  - Gesendet wird: das Suchwort oder der Strichcode, technisch unvermeidbar die IP-Adresse, dazu die App-Kennung und die Kontaktadresse, die der Nutzer im Blatt einträgt.
  - Feld „Kontaktadresse für Open Food Facts“: leer vorbelegt, vom Nutzer auszufüllen; Tagwerk schlägt keine Adresse vor und übernimmt keine aus dem Gerät oder aus einem Konto. „Einverstanden“ ist erst mit einer gültigen Adresse aktiv. Der Fußtext sagt, dass der Betreiber die Adresse mit jeder Anfrage sieht und wofür er sie verlangt (Wortlaut nach der Prüfung).
  - Nicht gesendet wird: Mengen, Mahlzeiten, Ziele, Gewicht, Daten aus Health, ein Konto.
  - Hinweis: Wer sucht, verrät dem Betreiber, was er isst oder kaufen will. Die Daten stammen von Freiwilligen und können fehlen oder falsch sein.
  - Schalter „Online-Suche in Open Food Facts“ unter Einstellungen › Erfassen (Widerruf), darunter die Kontaktadresse zum Ändern. Wird sie geleert, schaltet sich die Online-Suche aus. Derselbe Schalter gilt für Textsuche und Strichcode. Die Adresse steht in der Sicherung, in keinem Log.
- [ ] **Step 3:** `ProductLookup`: eine Anfrage je ausdrücklichem Tippen; Abfragegrenze lokal (`ProductSearchRules.searchLimit` = 10/min, `productLimit` = 15/min); bei Überschreitung keine Anfrage, sondern der Text „Bitte kurz warten“ mit Restzeit. Keine Cookies, keine gespeicherten Kennungen, Zeitlimit, kein Wiederholen ohne Tippen.
- [ ] **Step 4:** Zwischenspeicher: Treffer und Produkte liegen nur im Arbeitsspeicher des offenen Blatts (gleiche Anfrage in derselben Sitzung wird nicht erneut gesendet). Dauerhaft gespeichert wird nur ein Produkt, das der Nutzer als Lebensmittel übernimmt, mit `origin = openFoodFacts`, Strichcode und `sourceNote` („Open Food Facts, abgerufen am …“). Keine Protokollierung von Suchwörtern.
- [ ] **Step 5:** Namensnennung: Fußzeile unter jeder Trefferliste und Produktvorschau („Daten: Open Food Facts, Lizenz ODbL“ mit Verweis) und ein Eintrag unter Einstellungen › Über. Wortlaut „Daten: Open Food Facts (ODbL)“, Verweis auf openfoodfacts.org.
- [ ] **Step 6:** Commit `feat: add the consent and client for Open Food Facts`.

### Task E5: Online-Textsuche im Mahlzeitenblatt

**Entscheidungen:** LM1d. **Hängt ab von:** E2, E4.

**Files:** Modify `FoodPickerView.swift`; Create `ProductSearchView.swift`, `ProductPreviewSheet.swift`; UI-Test.

- [ ] **Step 1: Tests.** `search_startsOnlyOnTap_notWhileTyping`, `search_minimumThreeCharacters`, `search_noNetwork_buttonDisabledWithHint`, `preview_saveCreatesOwnFoodWithSource`, `preview_incompleteValues_offerLabelPhoto`, UI-Test `onlineSearch_consentFirst_thenResults`.
- [ ] **Step 2:** Im Segment „Meine Lebensmittel“ unter den eigenen Treffern die Zeile „Online suchen: ‚…‘“. Sie sendet erst auf Tippen (nie beim Tippen im Suchfeld), nur mit Einwilligung, nur mit Netz (sonst ausgegraut mit „Keine Verbindung“). Ohne Einwilligung öffnet sie das Blatt aus E4.
- [ ] **Step 3:** Trefferliste (Name, Marke, Menge, Kalorien je 100 g, „Angaben unvollständig“ wo Werte fehlen), höchstens eine Seite; „Weitere laden“ ist ein eigenes Tippen und zählt gegen die Grenze.
- [ ] **Step 4:** Vorschau eines Treffers mit allen Werten, fehlende als „keine Angabe“, Hinweis „Bitte mit der Verpackung vergleichen“, dann „Als Lebensmittel speichern“ (öffnet `FoodEditSheet` vorausgefüllt). Ein Treffer wird nie ohne diesen Schritt zu einem Posten.
- [ ] **Step 5:** Commit `feat: search packaged foods online by name`.

### Task E6 (zweite Ausbaustufe): Strichcode

**Entscheidungen:** LM2b. **Hängt ab von:** E4, E5 (Vorschau). Beginnt erst, wenn E1–E5 am Gerät geprüft sind.

**Files:** Create `Tagwerk/Capture/BarcodeScannerView.swift`, Tests.

- [ ] **Step 1: Tests.** `lookup_mapsProductToFood_missingFieldsUnknown`, `lookup_notFound_offersLabelPhoto`, `lookup_disabled_sendsNothing`.
- [ ] **Step 2:** Scan auf dem Gerät (VisionKit), Abfrage nur bei eingeschaltetem Schalter, dieselbe Vorschau wie in E5.
- [ ] **Step 3:** Commit `feat: look up packaged foods by barcode`.

---

## Strang F: Gewicht

### Task F1: `WeightRecord`, Store und Spiegelung

**Entscheidungen:** KG2a, KG4b. **Hängt ab von:** B4, A4.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/Weight.swift`, Tests; `Tagwerk/Capture/WeightRecords.swift`, `WeightStore.swift`; Modify `IntakeStore.swift`/`HealthMirror.swift` (weitere Eintragsart, Löschwarteschlange), Schema, Sicherung.

- [ ] **Step 1: Tests.** `mirror_writesUnsyncedWeight`, `delete_withinUndoWindow_neverReachesHealth`, `dayValue_earliestOfDay`, `merge_ownAndForeign_noDuplicates`.
- [ ] **Step 2:** Modell mit `healthVersion`, `healthSynced` wie bei Getränken; Grenzen 20–400 kg, Schritt 0,1.
- [ ] **Step 3:** Commit `feat: record body weight and mirror it to Health`.

### Task F2: Erfassen

**Entscheidungen:** KG1c, KG5a. **Hängt ab von:** F1.

**Files:** Create `Tagwerk/Capture/WeightSheet.swift`; Modify `CaptureView.swift` (`quickEntry`), `Tagwerk/Routines/MorningSheet.swift`, `RoutineSettingsView.swift`.

- [ ] **Step 1: Tests.** UI-Test `quickEntry_weight_savesAndOffersUndo`; `morningRow_hiddenWhenSwitchedOff`; Layouttest der vier Knöpfe bei großer Schrift (Umbruch in zwei Zeilen).
- [ ] **Step 2:** Blatt mit vorbelegtem letzten Wert, Zeitpunkt, optional Körperfett; Zeile im Tagesstart, abschaltbar. Keine eigene Mitteilung.
- [ ] **Step 3:** Commit `feat: enter body weight from the capture tab and the morning sheet`.

### Task F3: `WeightTrend`

**Entscheidungen:** KG3a. **Hängt ab von:** F1.

**Files:** Modify `Weight.swift`, Tests.

- [ ] **Step 1: Tests.** `movingAverage_needsThreeValues`, `trend_perWeekOver28Days`, `trend_insufficientData_isNil`, `projection_linear_nilWhenMovingAway`, `gaps_doNotBreakAverage`.
- [ ] **Step 2:** Regeln aus „Rechenregeln“.
- [ ] **Step 3:** Commit `feat: add weight trend rules`.

### Task F4: Seite „Verlauf und Ziele“

**Entscheidungen:** OR1a, KG3a. **Hängt ab von:** F3, C1, A2.

**Files:** Create `Tagwerk/Capture/TrendModel.swift`, `TrendView.swift`, `WeightChart.swift`, `IntakeChart.swift`; Modify `CaptureView.swift` (Zeile), `Tagwerk/App/AppRouter.swift`.

- [ ] **Step 1: Tests.** `trendModel_week_month_year_buckets`, `goalLine_stepsAtPlanChange`, `chart_accessibilitySummary`, `intakeChart_usesStoredDayHealth`.
- [ ] **Step 2:** Zeiträume Woche, Monat, Jahr (Gewicht zusätzlich 3 Monate); Diagramme mit Swift Charts, jeweils mit Textzusammenfassung für VoiceOver; Messpunkte, 7-Tage-Mittel als Linie, Ziellinie; Kennzahlen unter dem Gewichtsdiagramm; Liste der Messungen mit Quelle.
- [ ] **Step 3:** Commit `feat: add the trends page for intake and weight`.

---

## Strang G: Zielplanung mit ChatGPT

Die Bausteine aus #173 sind vorhanden (Ausgangslage Nr. 13). G6 braucht zusätzlich die Tasks A1 und A2 des Plans `2026-11-21-ki-vorschlaege-anpassen.md` (Bestätigen mit geänderten Argumenten, Knopf „Anpassen“ auf der Karte).

### Task G1: Körperdaten aus Health mit Eingabefeldern als Ersatz

**Entscheidungen:** PV4b. **Hängt ab von:** B6.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/BodyProfile.swift`, Tests; `Tagwerk/Capture/BodyProfileStore.swift`; Modify `AppSettings.swift` (`bodyHeightCm: Int?`, `birthYear: Int?`, `formulaSexRaw: String?` als eigene Eingaben; `healthBodyHeightCm: Int?`, `healthBirthYear: Int?`, `healthFormulaSexRaw: String?`, `healthBodyProfileReadAt: Date?` als letzter gelesener Stand), `CaptureSettingsView.swift`, `BackupDTOs.swift`.

- [ ] **Step 1: Tests.** `resolved_prefersHealthValuePerField`, `resolved_fallsBackToTypedPerField`, `resolved_missingField_reportsWhichOneIsMissing`, `refresh_healthSilent_keepsLastReadValue`, `refresh_notAsked_readsNothing`, `sexOtherOrUnset_requiresTypedChoice`, `age_fromBirthYear`, `backup_oldFileWithoutBodyData_decodes`.
- [ ] **Step 2:** `BodyProfile.resolved(health:typed:)` liefert je Feld Wert und Quelle (`health`, `typed`, `missing`). Aus Health gilt, was zuletzt gelesen wurde; Tagwerk speichert davon nur Größe in ganzen Zentimetern, Geburtsjahr und das Geschlecht für die Formel, nie das Geburtsdatum.
- [ ] **Step 3:** Abschnitt „Körper“ unter Einstellungen › Erfassen: Knopf „Aus Health lesen“ (fragt die Gruppe `bodyProfile` an und liest), darunter je Feld der Wert mit Quelle („180 cm · aus Health“). Für jedes Feld ohne Health-Wert steht ein Eingabefeld. Nach einer Anfrage ohne Ergebnis steht der Satz: „Health hat nichts geliefert. Entweder fehlt die Angabe in Health oder das Lesen ist nicht erlaubt; iOS teilt Tagwerk das nicht mit. Trage die Werte hier ein oder erlaube das Lesen in Health › Teilen › Apps › Tagwerk.“ Neu gelesen wird beim Öffnen des Abschnitts und vor dem Auswahlblatt der Zielplanung (G4), nie im Hintergrund.
- [ ] **Step 4:** Commit `feat: read body data from Health with typed fields as fallback`.

### Task G2: `GoalGuard`

**Entscheidungen:** ZI2b. **Vor dem Bau:** Ergebnis der Quellenprüfung in die Tabelle „Gegenrechnung“ eintragen.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/GoalGuard.swift` (enthält `GoalGuardConstants`), Tests.

- [ ] **Step 1: Tests.** `restingEnergy_example` (82,1 kg, 180 cm, 34, männlich → ~1.780), `warning_belowRestingEnergy`, `warning_paceAboveShareOfBodyWeight`, `warning_paceAboveOneKilogram`, `warning_belowSoftMinimum`, `block_belowHardMinimum`, `warning_proteinBelowReferenceWeight`, `deficitCheck_usesAverageActivity_orFallbackFactor`, `warning_macrosDoNotAddUp`, `noBodyData_noCheckButNotice`, `check_text_alwaysSaysEstimate`, `constants_areTheOnlySourceOfNumbers` (die Texte der Prüfung enthalten die Werte aus `GoalGuardConstants`, nicht eigene Literale).
- [ ] **Step 2:** `enum GoalGuardConstants` mit den Werten aus „Rechenregeln“, jeder mit Quellenkommentar; die Kommentare nennen die Quelle aus dem Prüfbericht.
- [ ] **Step 3:** `GoalGuard.check(proposal:body:weight:) -> GoalCheck` (Vergleichswerte, Warnungen, Text).
- [ ] **Step 4:** Commit `feat: add the local cross-check for goal proposals`.

### Task G3: Einwilligung

**Entscheidungen:** PV1b.

**Files:** Create `Tagwerk/Capture/GoalConsentSheet.swift`; Modify `AppSettings.swift` (`goalPlanningConsent`), `BackupDTOs.swift`, `CaptureSettingsView.swift`, Datenschutzhinweis unter Einstellungen › KI.

- [ ] **Step 1: Tests.** `consent_defaultOff`, `consent_notRestoredAsOnFromOldBackup`.
- [ ] **Step 2:** Blatt nach dem Aufbau von `MealConsentSheet` mit dem Text aus dem Mockup PV1b, ergänzt um den Satz: „Durchschnittswerte enthalten auch Einträge anderer Apps aus Health, wenn du sie mitzählen lässt.“ Schalter „Ziele mit ChatGPT planen“.
- [ ] **Step 3:** Commit `feat: add the consent for goal planning with ChatGPT`.

### Task G4: Datenpaket und Auswahlblatt

**Entscheidungen:** PV2a. **Hängt ab von:** A2, C1, F3, G1.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/GoalDataSummary.swift`, Tests; `Tagwerk/Capture/GoalDataBuilder.swift`, `GoalDataSheet.swift`.

- [ ] **Step 1: Tests.** `summary_averagesOver28Days_withCoverage`, `summary_excludesSwitchedOffGroups`, `summary_noMealTitlesNoDatesNoSourceNames`, `json_matchesWhatSheetShows` (derselbe Wert erzeugt Anzeige und Sendeform), `daysWithoutEntries_notCountedAsZero`, `summary_bodyGroup_usesResolvedProfile`.
- [ ] **Step 2:** Gruppen: Körperdaten, Gewicht und Trend, Ernährung, Aktivität, Wasser, geltende Ziele. Zeitraum 28 Tage; für „Fortschritt besprechen“ der Zeitraum seit dem geltenden Zielstand, höchstens 12 Wochen. Die Auswahl gilt für eine Sitzung; die Schalterstellung wird gemerkt.
- [ ] **Step 3:** Commit `feat: build and preview the data package for goal planning`.

### Task G5: `GoalChatTools` und Kontext

**Entscheidungen:** ZI1b, ZI3b. **Hängt ab von:** G2–G4.

**Files:** Create `Tagwerk/AI/GoalChatTools.swift`, Tests; Modify `AssistantModel.swift` (`Context.goals`, `openGoals(prefill:)`, Anweisungen, `activityText`, `singleConfirmationTools`, `singleConfirmationNotice`), `ChatStore.swift` (Schlüssel `goals`), `ChatView.swift`.

Werkzeuge (nur in diesem Kontext registriert):

| Name | Art | Inhalt |
|---|---|---|
| `get_goal_data` | lesen, als Zeile sichtbar | liefert das in der Sitzung freigegebene Paket; ohne Einwilligung oder Auswahl ein Fehler ohne Werte |
| `propose_nutrition_goals` | schreiben (Karte) | `kcal`, `protein_g`, `carbs_g`, `fat_g`, `fiber_g`, `sugar_limit_g`, `water_ml`, `target_weight_kg`, `pace_kg_per_week`, `reason`; alle nullable |
| `propose_activity_goals` | schreiben (Karte) | `steps_per_day`, `workout_minutes_per_week`, `active_kcal_per_day`, `reason`; alle nullable |

- [ ] **Step 1: Tests.** `goalTools_haveNoAppFunctions` (`definitions` enthält genau die drei Werkzeuge), `appTools_haveNoGoalFunctions`, `noteSuggestions_neverOfferGoalFunctions` (`NoteSuggestionRules.definitions` bekommt sie nie), `getGoalData_withoutConsent_returnsErrorWithoutValues`, `getGoalData_returnsOnlySelectedGroups`, `proposal_outOfRange_isRejectedWithMessage`, `instructions_stateBaseGoalWithoutActivity`, `goalCards_areSingleConfirmation`, `openGoals_whileOtherChatBusy_waits`.
- [ ] **Step 2:** `GoalChatTools: ToolHandler` als **eigener** Handler ohne Basis `AppTools` (anders als `TaskChatTools`, das `base.definitions` durchreicht, `TaskChat.swift:71–73`). Damit hat der Zielchat weder `search` noch `read_note` noch Schreibfunktionen für Aufgaben und Termine, und kein anderer Chat hat die Zielfunktionen. `kind(of:)`: `get_goal_data` lesend, die beiden Vorschläge schreibend.
- [ ] **Step 3:** `AssistantModel`: neuer Fall `Context.goals`; `openGoals(prefill:)` nach dem Muster von `open(task:)` (`:100–111`) mit `isHoldingOtherChat("goals")` und `switchThread(to: "goals", tools: goalTools)`. Der Sprachmodus wird in diesem Kontext nicht angeboten (`offersVoiceMode` in `ChatView`).
- [ ] **Step 4:** `singleConfirmationTools` (`:206`) um beide Vorschlagsfunktionen erweitern. Der Hinweistext „Zuweisungen bestätigst du einzeln.“ (`:222–224`) wird nach Werkzeug gewählt: für Zielkarten „Ziele bestätigst du einzeln.“ Die Sprachzählung `OpenCards.guarded` (`:197–202`) erfasst sie damit ebenfalls.
- [ ] **Step 5:** `showsActivity("get_goal_data")` = `true`; `AssistantModel.activityText` (`:445–451`) bekommt den Fall `get_goal_data` und baut die Zeile aus der **Kurzform** des Ergebnisses („Gelesen: Gewicht und Ernährung der letzten 28 Tage (Durchschnitte)“), damit sie mit vollem und mit gespeichertem Ergebnis gleich lautet.
- [ ] **Step 6:** Anweisungen (deutsch): Rolle, Pflicht zu `get_goal_data` vor einem Vorschlag, Grundziel ohne Aktivität, keine Diagnosen, Hinweis auf ärztlichen Rat bei genannten Erkrankungen, Vorschläge nur über die Funktionen, bei einer Rückmeldung „angepasst“ oder „Rückfrage“ mit dem genannten Stand weiterarbeiten.
- [ ] **Step 7:** Commit `feat: add the goal planning chat with its tools`.

### Task G6: Vorschlagskarten, zweite Bestätigung und „Anpassen“

**Entscheidungen:** ZI2b, ZI3b. **Hängt ab von:** G5; Plan „Anpassen“ Tasks A1, A2.

**Files:** Create `Tagwerk/AI/GoalProposalCard.swift`, `GoalAdjustSheet.swift`; Modify `Tagwerk/AI/ActionCardDescriber.swift`, `ChatView.swift`.

- [ ] **Step 1: Tests.** `card_showsOldAndNewValues`, `card_showsCrossCheck`, `card_withWarning_needsSecondConfirmation`, `confirmAll_skipsGoalCards`, `adopt_createsOnePlanFromToday`, `adjust_thenAdopt_usesEditedValues`, `adjust_recomputesCrossCheckAndWarning`, `adjust_outputTellsModelWhatWasAdopted`, `nullFields_keepCurrentValues`, `spokenDescription_existsForGoalCards`.
- [ ] **Step 2:** `ChatView.messageView` (`:209–212`) zeigt für die beiden Zielfunktionen `GoalProposalCard` statt `ActionCardView`: Zeilen alt → neu, darunter die Gegenrechnung aus `GoalGuard.check`. `ActionCardDescriber.describe` liefert dieselben Angaben als Text (für VoiceOver und für Orte, die nur `ActionCard` kennen); eine Warnung der Gegenrechnung steht in `ActionCard.warning` (`AssistantModel.swift:580`).
- [ ] **Step 3:** Zweite Bestätigung: Hat die Karte eine Warnung, öffnet „Übernehmen“ einen Bestätigungsdialog mit dem Warntext und „Trotzdem übernehmen“. Der Dialog hängt an der Chat-Ansicht, nicht an der Karte in der Liste (SwiftUI-Falle). Ohne Warnung führt „Übernehmen“ direkt aus.
- [ ] **Step 4:** „Anpassen“ öffnet `GoalAdjustSheet` mit den Zahlenfeldern (`ValueStepper`, `NumberEntry`) der Karte; „Fertig“ schreibt die Werte in die offene Karte zurück, die Karte trägt „von dir angepasst“ und wird neu gegengerechnet. Übernommen wird über `Conversation.confirm(_:arguments:)` (Plan „Anpassen“, Task A1); das Funktionsergebnis nennt dem Modell die übernommenen Werte und dass sie vom Nutzer geändert wurden.
- [ ] **Step 5:** „Übernehmen“ ruft `GoalStore.adopt` mit `origin = assistant` und der Begründung; genau ein neuer Zielstand ab heute.
- [ ] **Step 6:** Commit `feat: confirm goal proposals as cards`.

### Task G7: Gespeicherte Kurzform und Ende der Sitzung

**Entscheidungen:** PV3b. **Hängt ab von:** G5.

**Files:** Modify `GoalChatTools.swift` (`storedForm`), `AssistantModel.swift` (Beobachtung der Einwilligung), Tests.

- [ ] **Step 1: Tests.** `storedForm_getGoalData_keepsGroupsAndPeriodOnly`, `storedHistory_containsNoValuesFromGoalData` (über `Conversation.storableHistory`), `activityLine_sameForFullAndStoredOutput`, `sessionMemory_keepsPackageUntilChatIsLeft`, `leavingChat_reloadsStoredForm`, `revokeConsent_reducesHistoryAndEndsSelection`, `revokeConsent_whileTurnRuns_reducesAfterTurn`, `storedForm_proposals_keepArguments` (Karten bleiben im Verlauf lesbar).
- [ ] **Step 2:** `GoalChatTools.storedForm(of:output:)`: Für `get_goal_data` bleibt vom Ergebnis nur `{"ok":true,"groups":[…],"days":28}`; Argumente und Ergebnisse der Vorschlagsfunktionen bleiben unverändert (sie enthalten Zielzahlen, keine Messwerte, und der Nutzer hat sie gesehen). Gespeichert wird wie bei allen Chats nur `storableHistory` (`AssistantModel.persist`, `:459–465`); im Arbeitsspeicher behält die laufende Sitzung das volle Paket, bis der Chat verlassen wird (`switchThread` lädt die Kurzform, `:119–131`).
- [ ] **Step 3:** Widerruf: `watchGoalConsent` nach dem Muster von `watchNoteConsent`/`syncNoteConsent` (`:414–441`). Beim Wechsel auf „aus“ wird die Auswahl der Sitzung verworfen und der Verlauf über `reduceToStoredForm()` gekürzt; läuft gerade ein Zug, folgt die Kürzung nach dessen Ende (dieselbe Mechanik wie `pendingNoteSessionEnd`, `applyNoteSessionEnd`, `:453–457`; die beiden Fälle teilen sich eine Methode).
- [ ] **Step 4:** Commit `feat: keep goal data out of the stored chat history`.

### Task G8: Einstiege und „Fortschritt besprechen“

**Entscheidungen:** ZI6b, OR4b. **Hängt ab von:** G5, F4.

**Files:** Modify `TrendView.swift`, `WeekReviewView.swift`, `GoalPlanView.swift`, `AppRouter.swift`.

- [ ] **Step 1: Tests.** `entry_withoutSignIn_showsSignInHint`, `entry_withoutConsent_showsConsentFirst`, `review_prefillsFirstMessage_withoutSending`.
- [ ] **Step 2:** „Ziele planen“ (Verlaufsseite, Einstellungen) und „Fortschritt besprechen“ (Verlaufsseite und Abschnitt im Wochenrückblick) öffnen Einwilligung (falls nötig), Auswahlblatt, dann den Chat; die erste Nachricht ist vorbereitet, gesendet wird erst auf Tippen.
- [ ] **Step 3:** Commit `feat: add entries to goal planning and the progress review`.

---

## NU5: Entscheidung über die Machbarkeit

**Ergebnis: NU5b wird umgesetzt (Tasks B1, B5, C1, C3, D3).** NU5a bleibt der Zustand bei ausgeschaltetem Schalter und damit die Voreinstellung.

Begründung, getrennt nach dem, was gezeigt, angenommen und offen ist:

| Frage | Befund | Stand |
|---|---|---|
| Lassen sich eigene Einträge sicher ausschließen? | Ja. Jedes eigene Sample trägt Tagwerks Marke in den Metadaten und stammt aus der eigenen Quelle (`HealthMapping.metadata`, `isOwn`, Ausgangslage Nr. 8). Gelöscht wird schon heute über ein Metadaten-Prädikat. Eigene Einträge kommen in der Tagessumme ausschließlich aus Tagwerks Datenbank, fremde ausschließlich aus Health; es gibt keinen Pfad, auf dem ein Eintrag in beiden Summen landet. | im Quelltext belegt |
| Funktioniert der Ausschluss in einer Statistik-Abfrage? | Angenommen: Ein verneintes Metadaten-/Quellen-Prädikat ist in `HKStatisticsCollectionQueryDescriptor` zulässig. | am Gerät zu prüfen (Gerätetest „Fremde Einträge“). Schlägt es fehl: Ersatzweg `separateBySource` und Summe über alle Quellen außer der eigenen. |
| Was passiert bei verweigertem Lesen? | iOS meldet es nicht; die Abfrage liefert dasselbe wie „keine fremden Einträge“. Die Folge ist harmlos: Die Summe entspricht dann dem heutigen Verhalten (nur eigene Einträge). Der Fall ist also nicht erkennbar, führt aber zu keinem falschen Zusatzwert. | belegt (Verhalten von HealthKit wie bei den Schritten, Regel „–, nie 0“) |
| Wie geht die Oberfläche damit um? | Kein Fehlertext, sondern: Zeile „Aus Health · andere Apps“ erscheint nur, wenn es Werte gibt; der Schalter in den Einstellungen und das Detailblatt erklären, dass Tagwerk die Erlaubnis nicht sehen kann, und nennen den Ort in Health. | Entwurf (C3, D3) |
| Sind die Summen ohne Health wiederherstellbar? | Fremde Werte gehören Health. Tagwerk hält die Tagessummen in `DayHealthRecord` fest (A4), damit vergangene Tage, Wochenrückblick und Diagramme stabil bleiben und in der Sicherung stehen. Für den laufenden Tag wird bei jedem Laden neu aus Health gerechnet; ein späteres „keine Daten“ überschreibt einen gespeicherten Wert nicht. | Entwurf |
| Doppelte Einträge zweier fremder Apps | Schreiben zwei fremde Apps dieselbe Mahlzeit, führt Health sie bei Mengenwerten nach seiner Quellen-Reihenfolge zusammen; ob das für Ernährungswerte ohne Zeitüberlappung greift, ist offen. | nicht verifiziert; in „Risiken“ |
| Gesperrtes Gerät | Health ist nicht lesbar; Widget und Hintergrund nutzen die letzte Momentaufnahme. | wie bei Schritten |

Gegenüber dem Entwurf entfällt damit der Einwand „Summen ohne Health nicht wiederherstellbar“ durch A4; es bleibt der Einwand, dass ein verweigertes Lesen unsichtbar ist. Er wiegt hier leicht, weil der unsichtbare Fall mit dem heutigen Verhalten identisch ist.

---

## Gerätetests

| Bereich | Prüfung |
|---|---|
| Berechtigungen | Nach dem Update ohne neue Zustimmung: Mahlzeit, Wasser und Training erscheinen weiter in Health. Jede der fünf neuen Gruppen fragt einzeln und nur nach einem Tipp. |
| Doppelzählung Aktivität | (a) iPhone ohne Uhr: Lauf in Tagwerk eintragen, „Aktiv“ vor und nach dem Spiegeln vergleichen. (b) Mit Uhr: Training auf der Uhr aufzeichnen und denselben Zeitraum in Tagwerk eintragen; festhalten, was Health als Summe zeigt (keine Abzugsregel, nur Befund). (c) Kalorien-Schreiben in Health verweigern: Training zählt über den Lückenfüller. |
| Verweigertes Lesen | Aktivitätsenergie verweigern: „Aktiv –“, Budget = Grundziel + eigene Trainings, nie 0. |
| Fremde Einträge | (a) Mahlzeit in einer anderen App eintragen: erscheint als „Aus Health“ mit Quellenname, Summe steigt. (b) Mahlzeit in Tagwerk eintragen und spiegeln: Summe steigt nur einmal. (c) Lesen verweigern: keine Zeile, kein Fehler, Summe = eigene Einträge. (d) Schalter aus: keine Abfrage (Diagnose). (e) Fremden Eintrag in der anderen App löschen: Summe sinkt beim nächsten Laden. |
| Körperdaten | „Aus Health lesen“ mit allen drei Angaben, mit fehlender Größe, mit Geschlecht „nicht festgelegt“, mit verweigertem Lesen: jeweils richtige Quelle je Feld und der Hinweistext. |
| Gesperrtes Gerät | Widget nach Hintergrundaktualisierung bei gesperrtem iPhone: zeigt den letzten Stand, keinen Fehler. |
| Tageswechsel | Um Mitternacht und bei Zeitzonenwechsel: Aktivität, fremde Einträge und Budget gehören zum richtigen Tag. |
| Nährwerte | Alte Mahlzeit ohne Ballaststoffe: Zeile nennt die Abdeckung; in Health kein 0-Eintrag. |
| Online-Suche | Ohne Einwilligung, im Flugmodus und beim Tippen im Suchfeld kein Netzverkehr (Diagnose). Schnelles mehrfaches Tippen löst die Wartemeldung aus. Übernommenes Produkt trägt den Quellenhinweis; nach Neustart sind keine Treffer gespeichert. |
| Gewicht | Eintrag, Widerrufen innerhalb von 4 s, Eintrag aus einer anderen App erscheint mit Quellenname; Diagramm bei 1, 2 und 100 Messungen. |
| Schrift | Vier Knöpfe der Schnellerfassung und die Rechenzeile bei größter Schriftstufe. |
| Zielchat | Ohne Einwilligung kein Netzverkehr (Diagnose). Auswahl abgeschaltet → Antwort des Assistenten nennt die Werte nicht. Karte mit Warnung verlangt zweite Bestätigung. „Alle bestätigen“ lässt Zielkarten offen. Nach „Anpassen“ zeigt die Karte die neue Gegenrechnung. Nach Neustart steht im Verlauf nur „Gelesen: …“. Widerruf während einer laufenden Antwort. |
| Sicherung | Sichern und Wiederherstellen mit Zielständen, Lebensmitteln, Gewicht und Tageswerten; alte Sicherung ohne diese Listen öffnet. |

## Reihenfolge und Abhängigkeiten

1. **A1 → A2 → A3 → A4** (reine Regeln und Modelle; keine sichtbare Änderung außer der Übernahme der Ziele).
2. **B1 → B3 → B5**, dann **C1 → C2 → C3 → C4**: Das Tagesbudget ist der erste sichtbare Schritt.
3. **B2, D1 → D2 → D3** (Nährwerte) parallel zu Schritt 2 möglich; D3 braucht C1.
4. **E1 → E2 → E3**, danach **E4 → E5**; E6 erst nach eigener Freigabe. E4 beginnt erst, wenn die Tabelle „Fakten über Open Food Facts“ ausgefüllt ist.
5. **B4 → F1 → F2 → F3 → F4**; F4 braucht C1 für die Kaloriendiagramme.
6. **B6 → G1 → G2 → G3 → G4 → G5 → G6 → G7 → G8**; G2 wartet auf die Quellenprüfung der Konstanten, G4 auf F3 und C1, G6 auf die Tasks A1 und A2 des Plans „Anpassen“.

Höchstens drei Umsetzungs-Agenten parallel; sinnvolle Dreiergruppen: {C, D, E1–E3} nach A und B1/B3/B5, danach {F, G1–G4, E4–E5}, zuletzt G5–G8.

**Fremde Abhängigkeiten:**
- `2026-11-21-ki-vorschlaege-anpassen.md`, Tasks A1 und A2 (für G6). Umgekehrt nutzt jener Plan `GoalProposalCard` als einen seiner Orte.
- `MorningSheet.swift` wird auch von den Routinen-Plänen (`2026-11-20-g2-routinen-persoenliches.md`) geändert; F2 nach deren Umsetzung einplanen.
- Das Mitteilungskontingent wird nicht berührt.

## Nicht im Umfang

- Vitamine und Mineralstoffe, eine mitgelieferte Lebensmittelliste, ein eigenes Ernährungs-Widget.
- Rezepte als Mahlzeit mit Nährwerten.
- Einzelne fremde Ernährungseinträge als eigene Zeilen (gelesen werden Tagessummen), Bearbeiten oder Löschen fremder Einträge.
- Produktbilder aus Open Food Facts, Beitragen zu Open Food Facts.
- Eigene Mitteilungen (Wiegen, Besprechung).
- Selbsttätige Anfragen an ChatGPT; Gesundheitsdaten im allgemeinen Assistenten oder im Sprachmodus.
- Apple-Watch-App, Schlaf, Puls.

## Entscheidungen des Nutzers (21.11.2026)

Wortlaut: „BU1b, BU2a, BU3c, BU4b, NU1b, NU2b, NU3b, NU4b, NU5b (falls umsetzbar, sonst NU5a), LM1b & LM1d, LM2b, LM3b, LM4b, KG1c, KG2a, KG3a, KG4b, KG5a, ZI1b, ZI2b, ZI3b, ZI4b, ZI5b, ZI6b, PV1b, PV2a, PV3b, PV4b, OR1a, OR2b, OR3a, OR4b“.

Drei Entscheidungen weichen von der Empfehlung des Entwurfs ab (NU5, LM1, PV4); sie sind markiert.

| Kürzel | Frage | Gewählt | Folge im Plan |
|---|---|---|---|
| BU1 | Wie viel der verbrannten Energie wird angerechnet? | **BU1b** Anteil einstellbar; Voreinstellung **50 %** (Nutzer, 21.11.2026, nach der Faktenprüfung; das Mockup zeigt noch 100 %) | A2, A3, C3 |
| BU2 | Woher kommt „Aktiv“, und wie wird Doppelzählung vermieden? | **BU2a** Tagessumme aus Health, eigene Trainings nur als Lückenfüller | B3, C1; keine Abzugsregel, Gerätetest bleibt |
| BU3 | Wie verändern sich die Makro-Ziele mit dem Budget? | **BU3c** Eiweiß und Ballaststoffe fest, Rest wächst | A3, D3 |
| BU4 | Tageskopf in „Erfassen“ | **BU4b** Rechenzeile mit Budgetbalken | C2 |
| NU1 | Welche Nährwerte führt Tagwerk? | **NU1b** Dazu Ballaststoffe und Zucker; gesättigte Fettsäuren und Salz zuschaltbar | A1, B2, D1 |
| NU2 | Nährwerte in der Tagesübersicht | **NU2b** Eigene Karte „Nährwerte“ mit Balkenzeilen | D3 |
| NU3 | Mahlzeitenblatt | **NU3b** Kalorien und Makros sichtbar, weitere aufklappbar | D2 |
| NU4 | Fehlende Werte | **NU4b** Fehlend ist unbekannt, die Summe nennt die Abdeckung | A1, B2 |
| NU5 | Ernährungsdaten anderer Apps aus Health lesen? | **NU5b** Ja, fremde Einträge mitzählen *(abweichend von der Empfehlung; als machbar bewertet)* | B1, B5, A4, C1, C3, D3; Abschnitt „NU5“ |
| LM1 | Quellen für Nährwerte | **LM1b und LM1d** „Meine Lebensmittel“ und Online-Textsuche in Open Food Facts *(LM1d abweichend von der Empfehlung)* | E1, E2, E4, E5 |
| LM2 | Strichcode-Scan | **LM2b** Zweite Ausbaustufe, hinter einem Schalter | E6, derselbe Schalter wie E4 |
| LM3 | Etikett fotografieren | **LM3b** Ja, über ChatGPT mit Prüf-Vorschau | E3 |
| LM4 | Mengeneingabe | **LM4b** Gramm oder Stück bei eigenen Lebensmitteln, Faktor bei Schätzungen | E1, E2 |
| KG1 | Wo wird das Gewicht eingetragen? | **KG1c** Knopf und abschaltbare Zeile im Tagesstart | F2 |
| KG2 | Wer führt das Gewicht? | **KG2a** Tagwerk führt eigene Einträge, liest fremde Messungen dazu | B4, F1 |
| KG3 | Gewichtsverlauf | **KG3a** Messpunkte, 7-Tage-Mittel als Linie, Ziellinie | F3, F4 |
| KG4 | Körperfettanteil | **KG4b** Zuschaltbar, im Standard aus | B1, B4, C3, F2 |
| KG5 | Erinnerung ans Wiegen | **KG5a** Keine eigene Mitteilung | F2 |
| ZI1 | Form der Zielplanung | **ZI1b** Geführtes Gespräch im eigenen Chat „Ziele planen“ | G5 |
| ZI2 | Wer rechnet die Zahlen? | **ZI2b** ChatGPT schlägt vor, Tagwerk rechnet gegen und warnt | G2, G6; Konstanten geprüft |
| ZI3 | Vorschlagskarte | **ZI3b** Getrennte Karten für Ernährung und Aktivität | G5, G6 |
| ZI4 | Umfang der Aktivitätsziele | **ZI4b** Dazu Aktivitätsenergie pro Tag | A2, G5 |
| ZI5 | Ziele mit Geschichte | **ZI5b** Zielstände mit „gültig ab“ | A2, C3 |
| ZI6 | Fortschritt besprechen | **ZI6b** Dazu ein Abschnitt im Wochenrückblick | G8 |
| PV1 | Einwilligung für die Zielplanung | **PV1b** Eigenes Blatt und eigener Schalter | G3 |
| PV2 | Welche Daten gehen an ChatGPT? | **PV2a** Durchschnitte und Trend, je Gespräch auswählbar | G4 |
| PV3 | Was bleibt gespeichert? | **PV3b** Datenpaket nur in der Sitzung, Chattext gespeichert | G7 |
| PV4 | Größe, Alter und Geschlecht | **PV4b** Aus Health lesen, Eingabefelder als Ersatz *(abweichend von der Empfehlung)* | B1, B6, G1 |
| OR1 | Wo wohnen Verlauf und Ziele? | **OR1a** In „Erfassen“: Tageskopf plus Seite „Verlauf und Ziele“ | F4 |
| OR2 | Kalorien-Zeile im Kopf von „Planen“ | **OR2b** Rest des Budgets | C4 |
| OR3 | Widget | **OR3a** Widget „Heute“ rechnet mit dem Budget | C4 |
| OR4 | Wochenrückblick | **OR4b** Budget und Zielstände, dazu Nährwerte und Gewichtstrend | C4, G8 |

### Aus den Entscheidungen abgeleitete Festlegungen (ohne eigene Rückfrage in den Plan übernommen)

| Nr. | Festlegung | Grund |
|---|---|---|
| 1 | Tageswerte aus Health (Aktivität, fremde Ernährung) werden in `DayHealthRecord` festgehalten und gesichert (A4). | Frühere offene Frage 1; mit NU5b und OR4b zwingend, sonst ändern sich vergangene Tage. |
| 2 | Zeitraum des Datenpakets: 28 Tage fest; für „Fortschritt besprechen“ seit dem geltenden Zielstand, höchstens 12 Wochen. | Frühere offene Frage 3, Empfehlung übernommen. |
| 3 | Ein Zielstand gilt ab heute, nie rückwirkend. | Frühere offene Frage 4, Empfehlung übernommen. |
| 4 | Der Zielchat hat keinen Sprachmodus. | Frühere offene Frage 5; Karten mit Zahlen und Warnungen brauchen den Bildschirm. |
| 5 | Fremde Ernährung umfasst auch Wasser. | Trink-Apps sind die wahrscheinlichste fremde Quelle; ein Schalter für alles. |
| 6 | Ein Schalter für Textsuche und Strichcode. | Derselbe Dienst, dieselbe Art von Angabe (was der Nutzer isst oder kauft). |

Nach der Faktenprüfung (`docs/superpowers/research/2026-11-21-ernaehrung-faktenpruefung.md`) hat der Nutzer am 21.11.2026 zwei weitere Punkte festgelegt, die oben eingearbeitet sind: die Voreinstellung des Anrechnungsanteils (50 %) und die Abfrage der Kontaktadresse für Open Food Facts in der App. Die übrigen Ergebnisse der Faktenprüfung sind am 21.11.2026 von der Hauptsitzung eingetragen (Rechenregeln, Open Food Facts). HealthKit-Fragen bleiben Gerätetests.

### Weitere offene Fragen

| Nr. | Frage | Empfehlung |
|---|---|---|
| 1 | **Werte der Gegenrechnung** (Tabelle in „Rechenregeln“): nach der Quellenprüfung übernehmen oder ändern? | Geprüfte Werte übernehmen; Abweichungen der Recherche in die Tabelle eintragen. Schwellen nicht einstellbar machen. |
| 2 | **Kontaktangabe im Anfragekopf an Open Food Facts** – entschieden (Nutzer, 21.11.2026): Die App fragt die Adresse beim Einschalten der Online-Suche ab; ohne Adresse keine Anfrage; nie selbsttätig eine Adresse eintragen. | In E4 eingeplant. Format: `Tagwerk/<Version> (<Adresse>)`. |
| 3 | **Fremde Einträge im Datenpaket für ChatGPT:** mitrechnen oder nur eigene? | Mitrechnen, sonst passen Durchschnitt und Gewichtstrend nicht zusammen; Einwilligungstext sagt es (G3). |
| 4 | **Körperdaten: Vorrang.** Soll ein in Tagwerk getippter Wert einen Health-Wert überstimmen können? | Nein. Health gilt, wo es liefert; die Felder sind Ersatz. Wer abweichen will, ändert den Wert in Health. |
| 5 | **Issue-Schnitt:** ein Issue je Strang (A–G) oder ein Sammel-Issue? | Je Strang eines; E4–E5 (Online-Suche) und E6 (Strichcode) je ein eigenes. |

## Risiken

1. **Quellen-Reihenfolge in Health bei der Aktivitätsenergie.** Ob Health ein von Tagwerk geschriebenes Energie-Sample und eine gleichzeitige Messung der Uhr nur einmal zählt, ist aus der Dokumentation abgeleitet, nicht am Gerät belegt. Der Nutzer trägt Uhr-Trainings nicht zusätzlich ein; es gibt bewusst keine Abzugsregel. Der Gerätetest hält den Befund fest.
2. **Berechtigungsgruppen.** Ein Fehler in B1 hält die Spiegelung für alle bestehenden Einträge an, ohne Fehlermeldung. Der Test `coreTypes_unchanged` ist die Absicherung; zusätzlich Gerätetest nach einem Update über einen bestehenden Stand. Mit fünf neuen Gruppen steigt die Zahl der Systemabfragen; jede kommt nur nach einem Tipp.
3. **Ausschluss eigener Einträge (NU5b).** Trägt der Ausschluss per Prädikat in einer Statistik-Abfrage nicht, zählt jede gespiegelte Mahlzeit doppelt. Absicherung: Gerätetest (b) vor jeder Freigabe; Ersatzweg über `separateBySource`.
4. **Fremde Werte sind nicht prüfbar.** Tagwerk kennt weder Qualität noch Vollständigkeit fremder Einträge und zeigt sie ohne „~“. Zwei fremde Apps mit denselben Mahlzeiten können doppelt zählen. Gegenmaßnahme: Quellenname in der Zeile, Schalter im Standard aus.
5. **Unsichtbares Lesen.** Bei Aktivität, fremder Ernährung und Körperdaten kann Tagwerk ein Verbot nicht erkennen. Die Texte erklären das; ob Nutzer sie lesen, ist offen.
6. **Open Food Facts.** Nutzungsbedingungen, Abfragegrenzen und Lizenzfolgen sind ungeprüft (Tabelle in E4). Fällt die Prüfung ungünstig aus (z. B. Suche für Apps nicht erlaubt oder eng begrenzt), entfällt E5 und LM1d wird auf die Strichcode-Abfrage reduziert. Datenqualität schwankt; die Vorschau mit Prüfhinweis ist die einzige Absicherung.
7. **Genauigkeit der Aktivitätsenergie.** Die Anrechnung kann das Budget systematisch zu hoch ansetzen. Gegenmaßnahme ist die Voreinstellung von 50 %, der einstellbare Anteil und der Abgleich mit dem Gewichtstrend im Rückblick; belegt ist die Wirksamkeit damit nicht.
8. **Gesundheitsbezogene Vorschläge eines Sprachmodells.** Ein unpassendes Ziel kann schaden. Gegenmaßnahmen: Gegenrechnung mit Warnung, zweite Bestätigung, Hinweis auf ärztlichen Rat, keine selbsttätige Übernahme. Die Schwellen werden noch geprüft; auch geprüft bleiben sie Rechenhilfen.
9. **Datenschutz.** Die Nachrichten des Zielchats bleiben auf dem Gerät gespeichert und können Zahlen enthalten, die der Assistent genannt hat (PV3b). Was OpenAI mit den gesendeten Daten tut, liegt außerhalb der App. Mit NU5b können Durchschnitte Werte anderer Apps enthalten.
10. **Datenmigration der Ziele.** Der erste Zielstand entsteht aus Platzhaltern; eine falsche `validFrom`-Wahl verfälscht den Wochenrückblick.
11. **Umfang.** Sieben Stränge mit 35 Tasks. Ohne Schnitt in getrennte Issues und ohne die Reihenfolge „Budget zuerst“ droht ein langer Branch.
12. **Schätzqualität kleiner Nährwerte.** Ballaststoff- und Zuckerangaben aus Text oder Foto sind unsicher; die Tagessumme kann eine Genauigkeit vortäuschen. Gegenmaßnahme: „~“, Abdeckung, `null` statt Raten.
13. **Platz bei großer Schrift.** Vier Schnellknöpfe und eine Rechenzeile mit vier Zahlen sind eng; Umbruchregeln sind Teil von C2 und F2.

## Nicht verifiziert

- Verhalten von Health bei überlappenden Quellen für `activeEnergyBurned` und die Einreihung von Tagwerk in die Quellen-Reihenfolge.
- Ob das iPhone ohne Uhr Aktivitätsenergie nach Health schreibt.
- Ob ein verneintes Metadaten- oder Quellen-Prädikat in `HKStatisticsCollectionQueryDescriptor` trägt, und wie Health Ernährungswerte zweier fremder Quellen zusammenführt.
- Verhalten der Stammdaten-Abfragen (`dateOfBirth`, `biologicalSex`) bei verweigertem Lesen im Vergleich zu einer fehlenden Angabe; der Plan behandelt beide gleich.
- Nutzungsbedingungen, Schnittstellen, Abfragegrenzen und Lizenzdetails von Open Food Facts (Recherche läuft).
- Die Formel nach Mifflin und St Jeor, der Faktor 1,2, 7.700 kcal je kg und die 1-%-Schwelle (Recherche läuft); der Literaturstand zur Genauigkeit der Energieschätzung von Handgelenk-Geräten wurde nicht nachgeschlagen.
- `MealSheet.swift`, `WeekReviewView.swift`, `WeekReviewModel.swift`, `WidgetSnapshot.swift` und `BackupDTOs.swift` wurden nur in Ausschnitten gelesen; die genannten Dateien und Stellen in den Tasks C4, D2 und E2 sind vor der Umsetzung zu bestätigen. Zeilenangaben zu `AssistantModel.swift`, `Conversation.swift`, `ChatView.swift`, `TaskChat.swift` und `HealthKitStore.swift` stammen von `origin/main` `8326a3c`.
- Ob `ViewThatFits` oder ein fester Umbruch für die vier Schnellknöpfe trägt, ist am Gerät zu prüfen.
- Kein Build, kein Testlauf, kein Simulator in dieser Runde.
