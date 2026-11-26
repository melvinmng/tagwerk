# Council-Plan: #319, #320, #331, #332 (Entwurf)

> **Status:** Stand 25.11.2026, Code-Grundlage `main` bei `c3cecc8d` (Branch `chore/plan-next-steps`). Reiner Planungsentwurf eines Council-Mitglieds: nichts gebaut, nichts übersetzt, kein Test ausgeführt, nichts am Gerät geprüft. Alle Aussagen über den Bestand stammen aus dem Quelltext dieses Standes; was nicht gelesen oder nur aus Dokumentation bekannt ist, ist als **[Annahme]** oder **[zu prüfen]** markiert.

> **For agentic workers:** Kein Task beginnt, bevor die „Fragen an den Owner“ des jeweiligen Issues beantwortet sind. Jeder Task ist gegen die Empfehlung geschrieben; fällt eine Entscheidung anders aus, wird der Task vorher überarbeitet. Danach Task für Task mit TDD, Schritte als Checkbox.

Pfade ohne Präfix liegen unter `app/`.

## Global Constraints (für alle vier Issues)

- **Signing:** Keines der vier Vorhaben braucht nach diesem Plan ein neues Entitlement, eine neue Capability oder ein neues Target. Es ist kein Xcode-Signing-Durchgang nötig. Einzige Änderung an `project.yml`: der Text von `NSCameraUsageDescription` (#319).
- **Strings:** Deutsch ist Quellsprache; jeder neue Text deutsch und englisch (`Localizable.xcstrings`, `scripts/translations/en.json`, für den Kameratext zusätzlich `Tagwerk/InfoPlist.xcstrings`). Prüfen mit `scripts/sync-strings.sh --check` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs, Testnamen englisch. Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** Je Commit `app/test-all.sh` mit `TAGWERK_SKIP_UI_TESTS=1`; voller UI-Lauf am Ende des Strangs und vor dem Merge. Neue Bildschirme kommen in die Audit-Läufe (`AccessibilityAuditUITests`, `AccessibilityAuditLargeTextUITests`): 44 pt Trefferflächen, Dynamic Type bis AX5, Kontrast; keine neuen Einträge in `AuditAllowlist.swift` ohne Beleg.
- **Farben:** nur die vorhandenen Töne (`.secondaryText`, `.orangeText` aus `Common/TextTones.swift`), keine neuen Farbwerte. Bedeutung nie nur über Farbe.
- **SwiftData:** Neue Attribute optional oder mit Standardwert. Neue Modelle in die Sicherung (`Backup/BackupDTOs.swift`) oder begründet in `BackupCoverage.excluded`.
- **Merge-Konflikte:** Alle Stränge ändern `Localizable.xcstrings`, `scripts/translations/en.json` und `Common/AccessibilityID.swift`. Reihenfolge der Merges festlegen, jeder weitere Strang wird vor dem Merge neu auf `main` gesetzt.

---

# Issue #319 – Strichcode-Scan für Lebensmittel (E6)

## Befund im Quelltext

| Baustein | Stand | Stelle |
|---|---|---|
| Abfrage per Strichcode | **gebaut und getestet**, aber von keiner Ansicht aufgerufen | `ProductLookingUp.product(barcode:)`, `ProductLookup.product(barcode:)` (`Tagwerk/Capture/ProductLookup.swift`), Tests in `TagwerkTests/ProductLookupTests.swift` |
| Anfrage und Zuordnung | gebaut: `/api/v2/product/<code>` mit `fields=`, 8–14 Ziffern, `status: 0` → `nil` | `OpenFoodFactsAPI.productRequest`, `readProduct` (`Packages/TagwerkCore/…/OpenFoodFacts.swift`) |
| Abfragegrenze | gebaut: 15 Produktabfragen je Minute | `ProductSearchRules.productLimit`, `RequestLimiter` |
| Einwilligung, Schalter, Kontaktadresse | gebaut; der Text nennt den Strichcode bereits („später auch ein Strichcode“) | `FoodLookupConsentSheet.swift`, `AppSettings.isFoodLookupEnabled`, `CaptureSettingsView.swift:197` |
| Produktvorschau und Übernahme | gebaut, wiederverwendbar | `ProductPreviewView`, `ProductPreviewModel`, `ProductAttribution` (`ProductSearchView.swift`) |
| Strichcode am Lebensmittel | gebaut: Feld, Sicherung | `FoodValue.barcode`, `FoodRecord.barcode`, `BackupDTOs.swift:1340` |
| Suche in „Meine Lebensmittel“ nach Strichcode | **fehlt** (`FoodStore` sucht nur nach Namen) | `FoodStore.swift` |
| Scanner | **fehlt**; die App nutzt die Kamera nur über `UIImagePickerController` (`CameraPicker.swift`) | – |
| Demo-Antwort für Produktabfragen | liefert immer `{"status":0}` | `DemoProductTransport.swift` |
| Kamera-Begründung | nennt nur Mahlzeiten- und Notizfotos | `project.yml` (`NSCameraUsageDescription`), `InfoPlist.xcstrings` |

Folge: #319 ist überwiegend Oberfläche und Ablauf. Der Netzteil ist fertig.

## 1. Umfang

**Drin**
- Knopf „Strichcode scannen“ in `FoodPickerSection` (gilt damit im Mahlzeitenblatt `MealSheet` und in `FoodPickerSheet`).
- Scan auf dem Gerät mit VisionKit (`DataScannerViewController`), Symbologien EAN-13, EAN-8, UPC-E (UPC-A liest Vision als EAN-13 mit führender 0 **[Doku, zu prüfen am Gerät]**).
- Prüfziffer-Kontrolle (GTIN) vor jeder Abfrage, damit Fehllesungen nichts senden.
- **Zuerst lokal:** Ein Lebensmittel aus „Meine Lebensmittel“ mit diesem Strichcode öffnet sofort das Mengenblatt, ohne Netz und ohne Einwilligung.
- Sonst Abfrage bei Open Food Facts (nur mit Einwilligung, sonst zuerst das vorhandene Einwilligungsblatt), dann die vorhandene Produktvorschau.
- Nicht gefunden: „Etikett fotografieren“ (bei ChatGPT-Anmeldung) und „Selbst anlegen“, jeweils mit vorbelegtem Strichcode.
- Handeingabe der Ziffern als Ersatzweg (Kamera verweigert, Simulator, zerknitterte Packung).
- Aktualisierter Kameratext und Einwilligungstext („später auch“ entfällt).

**Ausdrücklich nicht drin**
- Beitragen oder Korrigieren bei Open Food Facts, Produktbilder, Nutri-Score, Zutaten, Allergene.
- Dauerhafter Zwischenspeicher fremder Produkte (bleibt wie in E4 festgelegt: nur im Arbeitsspeicher des Blatts).
- QR-Codes, Kassenbons, Mehrfach-Scan in Serie, Scan aus einem Foto der Mediathek.
- Scan als Einstieg in die Einkaufsliste.
- AVFoundation-Eigenbau; nur als Rückfallweg beschrieben (Risiko 1).

## 2. UX

**Einstieg.** In `FoodPickerSection` zwischen `onlineSearchRow` und „Neues Lebensmittel“: Knopf „Strichcode scannen“ (Symbol `barcode.viewfinder`). Er ist immer sichtbar (Empfehlung zu Frage 1), weil der lokale Treffer ohne Netz und ohne Einwilligung funktioniert.

**Blatt „Strichcode scannen“** (`.sheet` am `FoodSheetsModifier`, `.large`):
- Oben das Kamerabild mit Rahmen, darunter eine Zeile Status, darunter „Nummer eingeben“ (öffnet ein Zahlenfeld mit „Suchen“).
- Der erste gültige Code beendet den Scan (Haptik `.success`), das Kamerabild hält an. Kein zweiter Code wird ohne Tippen verarbeitet („Erneut scannen“).
- Die Kamera läuft nur, solange das Blatt offen und im Zustand „scannt“ ist.

**Zustände und Texte**

| Zustand | Anzeige |
|---|---|
| Kamera noch nicht gefragt | Systemdialog; bis zur Antwort: „Tagwerk braucht die Kamera, um den Strichcode zu lesen.“ |
| Kamera verweigert oder eingeschränkt | „Die Kamera ist für Tagwerk ausgeschaltet.“ · Knopf „Einstellungen öffnen“ · darunter „Nummer eingeben“ |
| Gerät oder Simulator ohne Scanner (`DataScannerViewController.isSupported == false`) | Kein Kamerabild, direkt das Zahlenfeld: „Gib die Nummer unter dem Strichcode ein.“ |
| Scannt | „Halte den Strichcode in den Rahmen.“ |
| Ungültige Nummer (Prüfziffer) | „Das ist kein gültiger Strichcode.“ (vorhandener Text `ProductLookupError.invalidBarcode`) |
| Lokaler Treffer | Blatt schließt, `FoodAmountSheet` des Lebensmittels öffnet |
| Online, lädt | Fortschrittsanzeige · „Suche bei Open Food Facts …“ |
| Ohne Einwilligung, kein lokaler Treffer | `FoodLookupConsentSheet` mit Knopf „Einverstanden und suchen“; bei „Nicht jetzt“ zurück zum Ergebnis „Nicht in ‚Meine Lebensmittel‘“ mit „Selbst anlegen“ |
| Keine Verbindung | „Keine Verbindung“ (vorhanden) · „Selbst anlegen“ |
| Gefunden | `ProductPreviewView` (unverändert: Werte, „Bitte mit der Verpackung vergleichen“, „Als Lebensmittel speichern“, Namensnennung) |
| Nicht gefunden | „Open Food Facts kennt diesen Strichcode nicht.“ · „Etikett fotografieren“ (nur angemeldet) · „Selbst anlegen“ · „Erneut scannen“ |
| Abfragegrenze, 403, 429, 5xx, Fehler | die vorhandenen Texte aus `ProductLookupError.message` · „Erneut versuchen“ |

**Barrierefreiheit.** Alle Knöpfe als Zeilen einer `Form` bzw. mit mindestens 44 pt; Statuszeile als `accessibilityLabel` des Kamerabereichs, Änderungen per `AccessibilityNotification.Announcement` („Strichcode erkannt“). Der Rahmen ist dekorativ (`accessibilityHidden`). Texte umbrechen, keine festen Höhen außer dem Kamerabild (bei AX-Größen scrollt der Inhalt darunter). Die Handeingabe macht die Funktion ohne Sehen des Kamerabilds nutzbar.

## 3. Daten und Architektur

- **`TagwerkCore`, neu `Barcode.swift`:** `Barcode.normalized(_:) -> String?` (nur Ziffern, 8, 12, 13 oder 14 Stellen, GTIN-Prüfziffer), reine Funktion. `OpenFoodFactsAPI.productRequest` bleibt die zweite Schranke.
- **`FoodStore`:** `food(barcode:) -> FoodValue?` (Vergleich über die normalisierte Form; bei mehreren Treffern der zuletzt angelegte). Kein Schemawechsel.
- **`Tagwerk/Capture/BarcodeScanModel.swift`** (`@MainActor @Observable`): Phasen `scanning`, `manualEntry`, `lookingUp`, `found(ProductCandidate)`, `ownFood(FoodValue)`, `notFound(code)`, `needsConsent(code)`, `failed(String)`, `cameraDenied`, `unsupported`. Abhängigkeiten als Closures bzw. Protokolle (`ProductLookingUp`, `foodByBarcode`, `hasConsent`, `isOnline`, `cameraAccess`), damit das Modell ohne Kamera und Netz testbar ist. `handle(code:)` ist der einzige Weg, der eine Abfrage auslöst; er wird vom Scanner und von der Handeingabe gerufen.
- **`Tagwerk/Capture/BarcodeScannerView.swift`:** `UIViewControllerRepresentable` um `DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce])], qualityLevel: .balanced, recognizesMultipleItems: false, isHighlightingEnabled: true)`; Delegate meldet den ersten Code an das Modell und stoppt (`stopScanning()`).
- **Kamerarecht:** `AVCaptureDevice.authorizationStatus(for: .video)` und `requestAccess` hinter einem kleinen Protokoll `CameraAccessProviding`; `DataScannerViewController.isAvailable` als zweite Prüfung **[Doku]**.
- **`FoodPickerCoordinator`:** neues Feld `barcodeScan: BarcodeScanRequest?`; `FoodSheetsModifier` hängt das Blatt an. `FoodEditSheet.Seed` braucht kein neues Feld: der Strichcode steht in `seed.food.barcode`; zu prüfen ist nur, dass `FoodEditSheet` ihn beim Speichern eines neuen, getippten Lebensmittels erhält **[zu prüfen]**.
- **API:** unverändert `GET https://world.openfoodfacts.org/api/v2/product/<code>?fields=…` mit `User-Agent` aus `ProductSearchRules.userAgent`. Keine neue Kennung, kein Cookie, kein Log des Codes (bestehende Regel in `ProductLookup.send`).
- **Datenschutz und Texte:**
  - `NSCameraUsageDescription` (deutsch): „Tagwerk nimmt Fotos von Mahlzeiten auf, um Kalorien und Nährwerte schätzen zu lassen, liest Strichcodes von Lebensmitteln und nimmt Fotos auf, die du an eine Notiz anhängst.“
  - Einwilligungsblatt: „**Gesendet wird:** das Suchwort oder der Strichcode, …“ (statt „später auch ein Strichcode“). Die bestehende Einwilligung deckt den Strichcode bereits wörtlich ab; eine erneute Abfrage ist nach meiner Lesart nicht nötig (Frage 3).
  - Das Kamerabild verlässt das Gerät nicht und wird nicht gespeichert; gesendet wird nur die Ziffernfolge.
- **Demo/Tests:** `DemoProductTransport` liefert für `4000000000001` ein vollständiges Produkt, sonst weiter `{"status":0}`. Im Simulator gibt es keinen Scanner; der UI-Test nutzt die Handeingabe.

## 4. Umsetzungsschritte (ein Commit je Schritt)

- [ ] **1 `feat: validate barcodes and find own foods by barcode`** – `Barcode.swift`, `FoodStore.food(barcode:)`.
  Tests (Core): `normalized_acceptsEAN13EAN8UPCA`, `normalized_rejectsWrongCheckDigit`, `normalized_stripsSpaces`, `normalized_rejectsLettersAndShortCodes`. Tests (App): `foodByBarcode_findsStoredFood`, `foodByBarcode_unknownIsNil`, `foodByBarcode_prefersNewest`.
- [ ] **2 `feat: add the barcode scan model`** – `BarcodeScanModel.swift`, `CameraAccessProviding`.
  Tests: `scan_ownFood_opensAmountWithoutRequest`, `scan_withoutConsent_sendsNothingAndAsksConsent`, `scan_consentGiven_runsLookupOnce`, `scan_unknownProduct_offersLabelPhotoOnlyWhenSignedIn`, `scan_offline_sendsNothing`, `scan_invalidCode_sendsNothing`, `scan_secondCodeIgnoredUntilRescan`, `scan_rateLimited_showsWaitText`, `cameraDenied_offersManualEntry`.
- [ ] **3 `feat: scan a barcode in the food list`** – `BarcodeScannerView.swift`, Blatt, Knopf in `FoodPickerSection`, `AccessibilityID.FoodLookup.scanButton/manualField/manualSubmit`, Demo-Antwort, Kamera- und Einwilligungstext, Übersetzungen.
  UI-Tests (`FoodLookupUITests`): `testBarcode_manualEntry_knownProduct_showsPreviewAndSaves`, `testBarcode_manualEntry_unknownProduct_offersOwnFood`, `testBarcode_ownFood_opensAmountSheet`. Audit: das Blatt im Zustand „Nummer eingeben“ und „Nicht gefunden“ in beide Audit-Läufe.
- [ ] **4 Gerätetest (kein Commit):** echte Packungen (EAN-13, EAN-8, eine US-Packung mit UPC-A), schlechtes Licht, Kamera verweigert, Flugmodus, erste Nutzung ohne Einwilligung. Ergebnis in den Issue-Kommentar.

## 5. Risiken, Fragen, Aufwand

**Risiken**
1. `DataScannerViewController` ist im Simulator nicht verfügbar; das Verhalten der Kamera ist nur am Gerät prüfbar. Rückfallweg bei Problemen: `AVCaptureMetadataOutput` (mehr Code, gleiche Rechte).
2. UPC-A/EAN-13-Normalisierung: Open Food Facts speichert Codes teils mit, teils ohne führende Null **[Annahme]**. Gegenmaßnahme: bei „nicht gefunden“ und 12 bzw. 13 Stellen mit führender 0 eine zweite Abfrage in der anderen Schreibweise – das kostet einen zweiten Platz in der Abfragegrenze; nur einbauen, wenn der Gerätetest es zeigt.
3. Datenqualität: Die Vorschau mit „Bitte mit der Verpackung vergleichen“ bleibt die einzige Absicherung; ein Scan darf nie ohne Vorschau zu einem Posten werden.
4. Der geänderte Kameratext betrifft auch Nutzer, die nie scannen; er muss alle drei Zwecke nennen, sonst droht eine Ablehnung bei einer späteren Verteilung über TestFlight.

**Fragen an den Owner**
1. **Sichtbarkeit des Knopfs.** A: immer sichtbar; lokal ohne Einwilligung, online erst nach Einwilligung (**Empfehlung**: der lokale Treffer ist der häufigste Fall bei wiederkehrenden Produkten). B: nur sichtbar, wenn der Schalter „Online-Suche in Open Food Facts“ an ist (wörtlich LM2b „hinter demselben Schalter“).
2. **Nach „Als Lebensmittel speichern“.** A: zurück in die Liste wie bei der Textsuche (**Empfehlung**, gleiches Verhalten). B: direkt das Mengenblatt des neuen Lebensmittels öffnen (ein Tipp weniger, weicht aber vom Text „Erst dort wählst du eine Menge“ ab).
3. **Einwilligung.** A: bestehende Einwilligung gilt, Text wird nur präzisiert (**Empfehlung**). B: beim ersten Scan einmal erneut zeigen.
4. **Einstieg zusätzlich im „＋“ von „Erfassen“?** A: nein, nur in der Lebensmittelliste (**Empfehlung**, kein neuer Ort). B: zusätzlicher Schnellzugriff „Strichcode“ neben Mahlzeit/Getränk.

**Aufwand:** 9–11 h (Schritt 1: 1,5 h; 2: 3 h; 3: 4 h; Gerätetest und Nacharbeit: 1,5–2,5 h).

---

# Issue #320 – Wochenrückblick: Zahlen zu Gewicht und Ernährung (C4)

## Befund im Quelltext

Der Plan zu #254 verlangt in C4/OR4b/ZI6b: Budget und Zielstände, Tagesmittel der Nährwerte, Gewichtstrend; das Mockup zeigt im Rückblick „Eiweiß ~118 / 140 g · Ballaststoffe ~22 / 30 g · Wasser 1,8 / 2,0 l · ⚖ Gewicht 7-Tage-Mittel 82,1 kg · −0,3 kg/Woche ›“ und „Fortschritt besprechen · Ziele vom 1. Nov. · seit 3 Wochen“.

| Punkt | Stand | Stelle |
|---|---|---|
| Kalorien je Tag gegen das Budget des Tages | **gebaut** (Balken mit Tagesziel) | `WeekReview.Day.goalKcal`, `WeekReviewView.caloriesSection` |
| Zielstand des jeweiligen Tages | **gebaut** | `WeekReviewModel.reload` (`budgets.figures(on:own:)`) |
| Tagesmittel Ballaststoffe, Zucker, ges. Fettsäuren, Salz | **gebaut**, aber ohne Vergleich mit dem Ziel | `nutrientsSection`, `averageNutrients` |
| Eiweiß-Mittel gegen Ziel | **gebaut** | Abschnitt „Eiweiß“ |
| „Fortschritt besprechen“ | **gebaut** | `GoalPlanningEntries(offer: .reviewOnly)` |
| Gewicht | **fehlt vollständig**; `WeekReviewModel` kennt `WeightStore` nicht | – |
| „Im Budget an x von y Tagen“, Ø Budget | **fehlt** (nur „Ø … kcal an n Tagen“) | `caloriesSection` |
| Kohlenhydrate und Fett | **fehlen** (`WeekReview.Day` kennt nur `protein`) | `WeekReview.swift` |
| Ziele für Ballaststoffe und Zuckergrenze | im Zielstand vorhanden, im Rückblick ungenutzt | `GoalPlan.fiberGrams`, `sugarLimitGrams`, `carbsGrams`, `fatGrams` |
| Hinweis „Ziele vom … · seit n Wochen“ | **fehlt** | – |

Die Trendrechnung existiert (`WeightTrend.movingAverage`, `trendPerWeek`, `summary`) und wird von „Verlauf und Ziele“ (`TrendModel`) und vom Datenpaket der Zielplanung (`GoalDataBuilder.weightFigures`) genutzt.

## 1. Umfang

**Drin**
- Abschnitt „Gewicht“: 7-Tage-Mittel am Ende der gezeigten Woche, Veränderung zur Vorwoche, Trend in kg je Woche (28 Tage), Anzahl Messungen der Woche, Abstand zum Zielgewicht; Zeile führt zu „Verlauf und Ziele“.
- Kalorien: „Im Budget an x von y Tagen“ und „Ø gegessen · Ø Budget“.
- Ein gemeinsamer Abschnitt „Nährwerte“ mit Eiweiß, Kohlenhydraten, Fett und den sichtbaren weiteren Nährwerten, jeweils Mittel gegen Ziel, wo der Zielstand eines hat.
- Zeile „Ziele vom … · seit n Wochen“ unter „Fortschritt besprechen“.

**Ausdrücklich nicht drin**
- Neue Diagramme im Rückblick (das Gewichtsdiagramm bleibt auf der Verlaufsseite).
- Körperfett im Rückblick (Frage 3), Prognose „Ziel erreicht am …“ (bleibt auf der Verlaufsseite).
- Änderungen an Widget, Kopf von „Planen“, Tageskopf, Health-Berechtigungen.
- Gewicht oder Nährwerte in der Wochenreflexion, in Mitteilungen oder im Assistenten.
- Bewertungen („gut“/„schlecht“) der Gewichtsveränderung. Die App nennt Zahlen, keine Urteile; die Warnung bei zu schnellem Abnehmen gibt es schon auf der Verlaufsseite (`TrendModel.paceLimit`) und wird hier nur übernommen (Frage 4).

## 2. UX

Ort: `WeekReviewView.reviewList`, Reihenfolge neu: Kalorien → Nährwerte → Gewicht → Wasser → Training → Schritte → Erledigt → „Fortschritt besprechen“ → Aufwand → Reflexion.

**Kalorien** (zusätzlich zu Balken und Fußtext):
- „Im Budget an 4 von 6 Tagen“ – gezählt werden nur Tage mit erfasster Mahlzeit; y ist die Zahl dieser Tage.
- „Ø ~2.140 kcal gegessen · Ø Budget 2.450 kcal“.

**Nährwerte** (ersetzt den heutigen Abschnitt „Nährwerte“ und den Abschnitt „Eiweiß“): je Zeile `LabeledContent`:
- „Eiweiß — Ø ~118 g / 140 g“
- „Kohlenhydrate — Ø ~230 g“ (mit „/ Ziel“ nur, wenn `carbsGrams` gesetzt ist), ebenso „Fett“.
- „Ballaststoffe — Ø 22 g / 30 g · an 5 Tagen“; „Zucker — Ø 61 g / höchstens 50 g“.
- Fußtext wie heute („Tagesmittel aus den Tagen, an denen der Wert bekannt ist …“).

**Gewicht**
- Erste Zeile: „7-Tage-Mittel 82,1 kg“; rechts „−0,4 kg zur Vorwoche“.
- Zweite Zeile (sekundär): „Trend −0,3 kg/Woche · 5 Messungen · noch 4,1 kg bis zum Ziel“. Teile ohne Wert entfallen.
- Die Zeile ist ein `NavigationLink` zu `TrendView` („Verlauf und Ziele“).
- Vorzeichen stehen als Text („−0,4 kg“), nicht als Farbe oder Pfeil allein.

**Zustände**

| Zustand | Anzeige |
|---|---|
| Keine Messung in den 7 Tagen bis Wochenende | „Kein Gewicht erfasst“ (sekundär), Zeile führt trotzdem zum Verlauf |
| 1–2 Messungen im Fenster | „Letzte Messung 82,4 kg (Do.)“ · „Für ein 7-Tage-Mittel fehlen Messungen (mindestens 3).“ |
| Kein Mittel der Vorwoche | Vergleich entfällt |
| Kein Zielgewicht | „bis zum Ziel“ entfällt |
| Laufende Woche | Kopf „bisher“ wie in den anderen Abschnitten; Mittel zum heutigen Tag |
| Health-Gruppe „Körper“ nie gefragt | nur eigene Einträge (so liefert es `WeightStore.measurements`), kein Dialog im Rückblick |
| Lädt | Abschnitt erscheint erst mit dem Ergebnis (keine springende Platzhalterzeile); die übrigen Abschnitte warten nicht darauf |

**Barrierefreiheit.** Jede Zeile ein zusammengefasstes Element mit ausgeschriebenem Label („Gewicht, 7-Tage-Mittel 82,1 Kilogramm, 0,4 Kilogramm weniger als in der Vorwoche“). Bei AX-Größen untereinander statt nebeneinander (`ViewThatFits` bzw. `LabeledContent`-Umbruch), keine `lineLimit(1)`.

## 3. Daten und Architektur

- **`TagwerkCore`, `WeightTrend.swift`:** neue reine Funktion
  `weekFigures(_ days: [PlanDay: DayWeight], weekStart: PlanDay, today: PlanDay, targetKg: Double?, calendar:) -> WeekFigures` mit `referenceDay` (= min(Sonntag der Woche, heute)), `mean`, `previousMean` (Mittel 7 Tage früher), `change`, `trendPerWeek`, `measurementCount`, `latest`, `remainingToTarget`. Sie nutzt `movingAverage` und `trendPerWeek`; keine zweite Rechnung.
- **`TagwerkCore`, `WeekReview.swift`:**
  - `Day` bekommt `carbs: Double?`, `fat: Double?`; `WeekReview` bekommt `averageCarbs`, `averageFat`, `daysWithinBudget`, `averageBudgetKcal`, `nutritionGoals` (Eiweiß, KH, Fett, Ballaststoffe, Zuckergrenze des Zielstands am `goalDay`).
  - `make` bekommt die neuen Parameter mit Vorgabewerten, damit die bestehenden Aufrufer und Tests unverändert übersetzen.
  - `IntakeFormat`: `weekBudgetDays(within:of:)`, `weekWeight(...)`, `nutrientAgainstGoal(...)` für die Texte (Texte im Paket, Bundle `.module`, wie `weekTraining`).
- **`WeekReviewModel`:** neue Abhängigkeit `weights: WeightStore?` (Vorgabe `nil`, damit bestehende Tests laufen); `reload()` liest `weights.dayValues(in:)` für `weekStart − (28 + 7 + 7)` Tage bis Wochenende und setzt `weightFigures`. Der Lesevorgang liegt hinter `review = makeReview(...)`, damit die lokalen Zahlen zuerst erscheinen (gleiches Muster wie GitHub). `makeWeekReviewModel()` in `AppEnvironment.swift:1126` reicht `capture.weights` durch.
- **Zielstand-Hinweis:** `GoalStore` kennt die Zielstände mit `validFrom`; das Modell bekommt `planSince: (validFrom: PlanDay, weeks: Int)?` für den `goalDay`.
- **Health/Datenschutz:** Kein neuer Health-Typ, keine neue Berechtigung, nichts verlässt das Gerät. Fremde Gewichte werden nur gelesen, wenn die Gruppe „Körper“ schon gefragt wurde (bestehende Regel in `WeightStore`). Der Kommentar am Modell („nothing here reaches an AI feature or the network“) bleibt wahr.
- **Vergangene Wochen:** Das Mittel wird für den Sonntag der gezeigten Woche gerechnet und ist damit stabil, solange die Messungen bestehen. Löscht der Nutzer Messungen in Health, ändert sich der Rückblick rückwirkend; das ist gewollt (Health ist die Quelle fremder Werte) und steht nicht im Widerspruch zu `DayHealthRecord`, das nur Energie und Ernährung festhält.

## 4. Umsetzungsschritte

- [ ] **1 `feat: compute the weight figures of a week`** – `WeightTrend.weekFigures`.
  Tests (`WeightTrendTests`): `weekFigures_meanAtWeekEnd_pastWeek`, `weekFigures_currentWeek_usesToday`, `weekFigures_fewerThanThreeValues_meanUnknownButLatestKnown`, `weekFigures_changeNeedsBothMeans`, `weekFigures_countsOnlyMeasurementsOfTheWeek`, `weekFigures_remainingToTarget`.
- [ ] **2 `feat: add budget days and macro means to the week review`** – `WeekReview` (Felder, `make`), `IntakeFormat`-Texte.
  Tests (`WeekReviewTests`): `daysWithinBudget_countsOnlyDaysWithMeals`, `daysWithinBudget_usesBudgetOfEachDay`, `averageBudget_overDaysWithMeals`, `carbsAndFat_meanOverDaysWithMeals`, `nutrientAgainstGoal_withoutGoal_showsMeanOnly`, `oldCallersWithoutNewParameters_unchanged`.
- [ ] **3 `feat: load the weight for the week review`** – `WeekReviewModel` (`weights`, `weightFigures`, `planSince`), `AppEnvironment.makeWeekReviewModel`.
  Tests (`WeekReviewModelTests`): `reload_withoutWeightStore_hasNoWeightSection`, `reload_weightOfTheShownWeek_notOfToday`, `reload_weekChangeDiscardsLateAnswer`, `reload_bodyGroupNotAsked_usesOwnEntriesOnly`, `planSince_namesThePlanOfTheGoalDay`.
- [ ] **4 `feat: show weight and nutrition figures in the week review`** – `WeekReviewView` (Abschnitte, Reihenfolge, Link zu `TrendView`), `WeekReviewPagePreview` anpassen **[zu prüfen: Datei nicht gelesen]**, Übersetzungen, `AccessibilityID`.
  UI-Tests: `CaptureUITests.testWeekReview_showsWeightAndBudgetDays` (Demodaten mit ≥ 3 Gewichten), `testWeekReview_withoutWeight_showsHint`; der Rückblick in beide Audit-Läufe (falls noch nicht enthalten: aufnehmen).
- [ ] **5 Gerätetest:** eine Woche mit echten Health-Gewichten gegen die Verlaufsseite vergleichen (Mittel und Trend müssen übereinstimmen).

## 5. Risiken, Fragen, Aufwand

**Risiken**
1. Zwei Orte mit Gewichtszahlen können auseinanderlaufen. Gegenmaßnahme: dieselben Funktionen in `WeightTrend`; ein Test vergleicht `weekFigures` der laufenden Woche mit `summary` für heute.
2. Die Liste wird lang. Das Zusammenlegen von „Eiweiß“ und „Nährwerte“ spart einen Abschnitt; mehr Kürzung wäre eine Gestaltungsfrage (Frage 2).
3. „Im Budget“ an einem Tag mit unbekannter Aktivität rechnet mit dem Grundziel (so macht es `DayBudgets` bereits). Der Fußtext der Kalorien muss das weiter sagen.
4. Wenige Messungen: Mit einer Messung je Woche gibt es nie ein 7-Tage-Mittel (Mindestzahl 3). Der Hinweis erklärt das; die Regel selbst (KG3a) wird nicht aufgeweicht.

**Fragen an den Owner**
1. **Was ist „Veränderung der Woche“?** A: Differenz der 7-Tage-Mittel (Wochenende gegen Vorwochenende), dazu der 28-Tage-Trend wie auf der Verlaufsseite (**Empfehlung**: glättet Tagesschwankungen, eine Rechnung). B: erste gegen letzte Messung der Woche (anschaulich, aber stark vom Wasserhaushalt einzelner Tage abhängig).
2. **Eiweiß-Abschnitt.** A: in „Nährwerte“ aufgehen lassen (**Empfehlung**). B: eigener Abschnitt bleibt, Kohlenhydrate und Fett kommen in „Nährwerte“.
3. **Körperfett.** A: nicht im Rückblick (**Empfehlung**; Messwerte von Waagen schwanken stark, die Verlaufsseite zeigt sie). B: als weitere Zeile, wenn `bodyFatEnabled` an ist.
4. **Hinweis bei zu schnellem Abnehmen** (Grenze `GoalGuardConstants.weeklyLossLimit`). A: auch im Rückblick als sekundärer Satz (**Empfehlung**, gleiche Regel wie Verlaufsseite). B: nur auf der Verlaufsseite.
5. **Wasser.** A: bleibt wie heute („Ziel an x von y Tagen · Ø …“) (**Empfehlung**). B: zusätzlich „Ø 1,8 l / 2,0 l“ wie im Mockup.

**Aufwand:** 7–9 h (1: 1,5 h; 2: 2 h; 3: 1,5 h; 4: 2,5 h; Gerätetest: 0,5–1,5 h).

---

# Issue #331 – Suche für Einstellungen und Repositories/Projects

Das Issue hat keinen Text. Der Umfang ist aus Titel und Quelltext abgeleitet und damit **eine Auslegung**, keine Anforderung. Die Fragen unten entscheiden, was davon gebaut wird.

## Befund im Quelltext

| Ort | Stand |
|---|---|
| Übergreifende Suche | `Search/SearchSheet.swift`, `SearchModel.swift`, Kern in `TagwerkCore/Search/` (`SearchQuery`, `SearchResults`, `SearchText.fold`). Abschnitte: Termine, Aufgaben, Erledigt, GitHub online, Vergangene Termine, Notizen, Einkaufsliste. Filter: Alle/Termine/Aufgaben. Einstieg: `SearchButton` oben in „Planen“ und „Aufgaben“, **nicht** in „Einstellungen“. `.searchable` für die übergreifende Suche wurde im Suchdesign verworfen (QE2). |
| Einstellungen | `Settings/SettingsView.swift`: eine `Form` mit rund 20 Zeilen und 14 Unterseiten, teils mit weiteren Unterseiten (KI › Stimme, Erfassen › Zielstände, Routinen …). Kein Suchfeld. `SettingsDestination` kennt nur 6 Seiten (`languages`, `ai`, `aiVoice`, `capture`, `shopping`, `siri`); die übrigen hängen an `NavigationLink`s mit festem Ziel und sind nicht programmatisch erreichbar. |
| Repository beim Anlegen eines Issues | `Picker("Repository", …)` als Menü an **drei** Stellen: `Tasks/NewTaskSheet.swift:125`, `Routines/IssueTargetSheet.swift:125`, `AI/TaskProposalEditor.swift:293`. Kein Filter. |
| Projekte beim Anlegen | `ProjectSelectionRow` (`Tasks/ProjectSelection.swift`): `Menu` mit Schaltern, bleibt offen, kein Filter. |
| Projekte in den Einstellungen | `SourceSelectionView` (auch für Kalender und Erinnerungslisten): Liste ohne Filter. |
| Datenbasis | `GitHubCatalog` (`repositories: [String]`, `projects: [ProjectInfo]`). `GitHubAPI.ownedRepositories()` liest **nur eigene** Repositories (`affiliation=owner`), **nur die ersten 100**, nach letztem Push sortiert. `ProjectsQuery.viewerProjects` liest **nur die ersten 20** offenen Projects. |

Zwei Folgerungen:
1. Der vermutete Schmerz „bei der Erstellung von Issues“ sind die langen, ungefilterten Menüs für Repository und Projekte.
2. Eine Suche über eine abgeschnittene Liste täuscht Vollständigkeit vor. Wer mehr als 100 Repositories oder 20 Projects hat oder in Organisationen arbeitet, findet das Gesuchte auch mit Suchfeld nicht. Das gehört in denselben Umfang (Frage 4).

## 1. Umfang (Empfehlung)

**Teil A – Auswahl mit Suche für Repository und Projekte (Kern des Issues)**
- Eine gemeinsame, durchsuchbare Auswahlseite ersetzt das Repository-Menü und das Projekt-Menü an allen drei Stellen.
- Abschnitt „Zuletzt verwendet“ (bis zu 3 Repositories) über der Liste.
- `SourceSelectionView` bekommt dasselbe Suchfeld (Kalender, Erinnerungslisten, Projekte in den Einstellungen).
- Katalog vollständig laden: Repositories seitenweise (bis 500), Projects seitenweise (bis 100); ob auch Repositories aus Organisationen und Mitarbeit dazukommen, entscheidet Frage 4.

**Teil B – Suche in den Einstellungen**
- Suchfeld oben im Tab „Einstellungen“ (`.searchable`), Treffer aus einem gepflegten Verzeichnis aller Einstellungen (Titel, Schlagwörter, Pfad); Tipp öffnet die Seite.
- Dazu werden alle Unterseiten über `SettingsDestination` erreichbar.

**Teil C – Einbindung in die übergreifende Suche (optional, Frage 1)**
- Abschnitt „Einstellungen“ am Ende der Trefferliste (höchstens 5 Zeilen, nur beim Filter „Alle“), Tipp schließt die Suche und öffnet die Seite.
- Abschnitt „Projekte“ erst zusammen mit #332 sinnvoll (Tipp öffnet die Projektseite).

**Ausdrücklich nicht drin**
- Suche in Einstellungs-**Werten** („wo steht 2.300 kcal“), Verlauf „zuletzt gesucht“, Spotlight/Siri-Suche, Deeplinks `tagwerk://settings/…`.
- GitHub-weite Repository-Suche (fremde, nicht verbundene Repositories).
- Ein neuer Tab oder ein Umbau der Einstellungen-Gliederung.
- Suche nach Labels, Meilensteinen, Personen (Zuweisung hat eine eigene Auswahl in `AssigneeSelection.swift`; bei Bedarf eigener Schritt mit derselben Auswahlseite).
- Das Assistenten-Werkzeug `search` bleibt unverändert (keine Einstellungen an ChatGPT).

## 2. UX

**A – Auswahlseite** (Push innerhalb des `NavigationStack` des jeweiligen Blatts; Vorbild `Notes/BibleBookPicker.swift` mit `.searchable(placement: .navigationBarDrawer(displayMode: .always))`):
- Zeile im Formular: „Repository — melvinmng/tagwerk ›“ bzw. „Projekte — Tagwerk, Studium ›“ (statt Menü).
- Seite „Repository“: Suchfeld „Repository suchen“; Abschnitte „Zuletzt verwendet“ und „Alle“; Zeile zweizeilig bei langen Namen (Besitzer sekundär, Name primär), Häkchen am gewählten Eintrag; Tipp wählt und geht zurück.
- Seite „Projekte“ (Mehrfachauswahl): Suchfeld „Projekt suchen“; oben „Kein Projekt“; darunter „Mit dem Repository verknüpft“ und „Weitere“; Tipp schaltet um, „Fertig“ oben rechts. Die Vorbelegung (`ProjectSelection.preselect`) bleibt.
- Abgleich: jedes Suchwort muss in „owner/name“ bzw. im Titel vorkommen, ohne Groß-/Kleinschreibung und Umlautunterschiede (`SearchText.fold`); Treffer am Wortanfang zuerst.

| Zustand | Anzeige |
|---|---|
| Katalog lädt, nichts im Speicher | Fortschrittsanzeige · „Repositories werden geladen …“ |
| Katalog aus dem Speicher, Abruf läuft | Liste sofort, darunter sekundär „Wird aktualisiert …“ |
| Abruf fehlgeschlagen, Speicher vorhanden | Liste · „Stand vom 24.11., 18:02. GitHub ist gerade nicht erreichbar.“ |
| Abruf fehlgeschlagen, nichts im Speicher | „Repositories konnten nicht geladen werden.“ (vorhandener Text) · „Erneut versuchen“ |
| Kein Treffer | `ContentUnavailableView.search(text:)` · bei abgeschnittener Liste zusätzlich „Es werden nur die ersten 500 Repositories geladen.“ |
| Keine Projekte | „Keine Projekte“ (vorhanden) |

**B – Einstellungen:** Suchfeld „Einstellungen durchsuchen“. Mit Text ersetzt eine Trefferliste die Form: je Zeile Titel und darunter der Pfad („Erfassen › Online-Suche in Open Food Facts“). Tipp öffnet die Seite, die Suche wird beendet. Kein Treffer: `ContentUnavailableView.search`. Ohne Text: die Form wie heute.

**C – Übergreifende Suche:** Abschnitt „Einstellungen · 2“ nach „Einkaufsliste“; Zeile wie in B. Tipp: Suchblatt schließt, Tab „Einstellungen“ öffnet mit dem Pfad (`environment.settingsPath`, `requestedTab = 2`, vorhandener Mechanismus aus `UITestScreen.swift`).

**Barrierefreiheit.** Zeilen sind `Button`s in Listen (≥ 44 pt), Auswahlzustand als `accessibilityAddTraits(.isSelected)`, nicht nur als Häkchen. Lange Repository-Namen umbrechen bei AX-Größen (kein `lineLimit(1)`, das heute im Menü abschneidet). Der Wechsel von Menü zu Seite verbessert die Bedienung mit VoiceOver, weil Menüs mit vielen Einträgen kein Suchfeld haben.

## 3. Daten und Architektur

- **`TagwerkCore/Search/ChoiceFilter.swift`** (neu, rein): `ChoiceFilter.matching(_ items: [T], query: String, text: (T) -> [String]) -> [T]` mit `SearchText.fold`, Wortanfang vor Wortmitte, stabile Reihenfolge sonst.
- **`Tagwerk/Common/SearchableChoiceList.swift`** (neu): generische Seite für Einfach- und Mehrfachauswahl (Abschnitte, Sperrnotizen wie `lockedIDs`, Häkchen, leerer Zustand). `SourceSelectionView` wird darauf umgestellt oder nutzt nur `ChoiceFilter` (kleinerer Eingriff; Empfehlung: nur Filter, damit die Einstellungen-Seite unverändert aussieht).
- **`RepositoryChoice`** (neu, `Tasks/`): Zeile + Seite für das Repository; ersetzt die drei `Picker("Repository")`. `ProjectSelectionRow` wird von `Menu` auf `NavigationLink` + Seite umgestellt; die reinen Regeln in `ProjectSelection` bleiben.
- **Zuletzt verwendet:** `AppSettings.recentRepositories: [String]` (optional, höchstens 5, nach erfolgreichem Anlegen eines Issues fortgeschrieben; in die Sicherung, enthält nur Namen eigener Repositories). Kein neues Modell.
- **Katalog:** `GitHubAPI.ownedRepositories()` seitenweise (`page=`), Obergrenze 5 Seiten; `ProjectsQuery.viewerProjects` mit Cursor, Obergrenze 5 Seiten. `GitHubCatalog` bekommt `isTruncated: Bool` (mit `decodeIfPresent`, alte Kataloge lesen sich weiter). Die Affiliation ist ein Parameter (Frage 4). Kein neuer OAuth-Scope: `repo project` deckt beides ab (`DeviceFlowClient.swift:22`); ob `affiliation=organization_member` ohne `read:org` vollständig liefert, ist **[zu prüfen]**.
- **`Settings/SettingsSearchIndex.swift`** (neu): statische Liste `SettingsEntry(title: LocalizedStringResource, keywords: [LocalizedStringResource], path: [SettingsDestination])`. Gesucht wird in der lokalisierten Form (deutsch oder englisch, je nach Oberfläche). `SettingsDestination` wird um alle Seiten erweitert (`calendars`, `reminderLists`, `gitHubProjects`, `routines`, `notes`, `backup`, `focus`, `reminderDefaults`, `quietHours`, `travel`, Unterseiten von „Erfassen“ und „KI“ …); `SettingsView` ersetzt die festen `NavigationLink`s durch `NavigationLink(value:)`. Einträge, die keine eigene Seite sind (z. B. „Puffer“, „Mittagspause“ auf der Hauptseite), führen auf die Hauptseite und scrollen zur Zeile (`ScrollViewReader`, `id`) **[Machbarkeit in `Form` zu prüfen]**; ersatzweise werden nur Seiten indexiert.
- **Übergreifende Suche:** `SearchSectionKind.settings`, `SearchInput.settings: [SettingsSearchItem]`, `SearchSources.settings`-Closure; `SearchResults.make` begrenzt auf 5. Der Kern bleibt in `TagwerkCore` und kennt nur Titel, Pfadtext und eine opake Kennung.
- **Datenschutz:** Die Suche in Einstellungen und Auswahllisten läuft lokal; kein Suchwort verlässt das Gerät (gleiche Regel wie im Suchdesign). Der Katalogabruf sendet wie bisher nur die Anmeldung an GitHub.

## 4. Umsetzungsschritte

Teil A (ein Pull Request):
- [ ] **A1 `feat: filter choice lists by folded words`** – `ChoiceFilter`. Tests: `matching_allWordsMustOccur`, `matching_ignoresCaseAndDiacritics`, `matching_prefixHitsFirst`, `matching_emptyQueryKeepsOrder`, `matching_ownerOrNameOfRepository`.
- [ ] **A2 `feat: load the full GitHub catalog`** – Paging für Repositories und Projects, `isTruncated`. Tests (GitHubKit, vorhandener Fake-Transport): `ownedRepositories_followsPagesUpToLimit`, `viewerProjects_followsCursor`, `catalog_oldPayloadWithoutTruncatedFlag_decodes`, `catalog_marksTruncation`.
- [ ] **A3 `feat: choose the repository on a searchable page`** – `SearchableChoiceList`, `RepositoryChoice`, Einbau in `NewTaskSheet`, `IssueTargetSheet`, `TaskProposalEditor`; `recentRepositories` inkl. Sicherung. Tests: `recentRepositories_keepsFiveNewestFirst`, `recentRepositories_dropsUnknownRepositories`, `backup_roundTripsRecentRepositories`. UI-Test (`TaskFlowUITests`): `testNewIssue_findsRepositoryBySearch`.
- [ ] **A4 `feat: choose projects on a searchable page`** – Umbau `ProjectSelectionRow`. Tests: bestehende `ProjectSelection`-Tests bleiben grün; neu `projectSections_linkedFirst`. UI-Test: `testNewIssue_selectsTwoProjectsBySearch`. Audit: beide Auswahlseiten in beide Audit-Läufe.
- [ ] **A5 `feat: search the source lists in the settings`** – `SourceSelectionView` mit Suchfeld (erst ab 8 Einträgen sichtbar). UI-Test in `SettingsNavigationUITests`.

Teil B (eigener Pull Request):
- [ ] **B1 `refactor: route every settings page through SettingsDestination`** – ohne sichtbare Änderung. Tests: `SettingsNavigationUITests.testSettingsPageOpensFromItsRow` bleibt grün und wird über alle Ziele parametrisiert; `UITestScreen` um die neuen Seiten ergänzt.
- [ ] **B2 `feat: index the settings for search`** – `SettingsSearchIndex`. Tests: `index_everyDestinationHasAnEntry`, `index_everyPathStartsAtARootRow`, `index_findsByKeyword` („Kalorien“ → Erfassen, „Open Food Facts“ → Erfassen, „Stimme“ → KI › Stimme), `index_titlesAreUniquePerPath`.
- [ ] **B3 `feat: search the settings`** – `.searchable` in `SettingsView`, Trefferliste. UI-Tests: `testSettingsSearch_opensNestedPage`, `testSettingsSearch_noHit_showsEmptyState`; Trefferliste in beide Audit-Läufe.

Teil C (optional, nach Entscheidung):
- [ ] **C1 `feat: show settings in the global search`** – `SearchSectionKind.settings`, Quelle, Zeile, Sprung. Tests (`SearchResultsTests`): `settings_onlyWithFilterAll`, `settings_cappedAtFive`, `settings_lastSection`. UI-Test (`SearchUITests`): `testSearchOpensSettingsPage`.

## 5. Risiken, Fragen, Aufwand

**Risiken**
1. **Verzeichnis veraltet.** Ein von Hand gepflegter Index driftet. Gegenmaßnahme: Test `index_everyDestinationHasAnEntry` (über `CaseIterable`) erzwingt einen Eintrag je Seite; einzelne Schalter innerhalb einer Seite bleiben Handarbeit und werden als Schlagwörter der Seite geführt.
2. **Umbau der Navigation (B1)** berührt jede Zeile von `SettingsView` und kann Rücksprünge oder den Zustand der Unterseiten verändern. Deshalb als eigener Commit ohne Funktionsänderung, mit UI-Test über alle Seiten.
3. **Drei Einbaustellen** für die Repository-Auswahl; `TaskProposalEditor` liegt in einem Blatt über dem Chat. Eine Seite statt Menü braucht dort einen `NavigationStack` **[zu prüfen]**.
4. **Paging kostet Abrufe.** 5 Seiten Repositories + 5 Seiten Projects je Katalogabruf im schlechtesten Fall; der Katalog ist zwischengespeichert (`catalog(maxAge:)`), der Abruf läuft im Hintergrund.
5. **Mehr Tipps bei wenigen Einträgen.** Mit 3 Repositories ist das Menü schneller als eine Seite. Siehe Frage 3.
6. **Widerspruch zum Suchdesign:** `.searchable` wurde dort für die übergreifende Suche verworfen (QE2). Hier dient es nur der Seite „Einstellungen“ und den Auswahllisten; das ist ein anderer Zweck, sollte aber bewusst entschieden werden (Frage 1).

**Fragen an den Owner**
1. **Wo sucht man Einstellungen?** A: Suchfeld im Tab „Einstellungen“ **und** Abschnitt in der übergreifenden Suche (Teile B und C) (**Empfehlung**: der Index wird einmal gebaut, C kostet dann wenig). B: nur im Tab „Einstellungen“. C: nur in der übergreifenden Suche (dann braucht „Einstellungen“ eine Lupe).
2. **Was heißt „Repositories/Projects suchen“?** A: beim Auswählen filtern (Anlegen eines Issues, Zielwahl der KI-Vorschläge, Einstellungen) (**Empfehlung**, so lese ich „v. a. bei der Erstellung von Issues“). B: zusätzlich als Treffer in der übergreifenden Suche; dann bitte festlegen, was der Tipp tut: (i) „Neues Issue“ mit vorgewähltem Repository, (ii) Aufgabenliste nach Projekt gefiltert, (iii) Projektseite aus #332, (iv) auf GitHub öffnen.
3. **Menü oder Seite?** A: immer die durchsuchbare Seite (**Empfehlung**: ein Verhalten, besser mit Dynamic Type). B: Menü bis 8 Einträge, darüber Seite (schneller bei wenigen, aber zwei Verhaltensweisen und zwei Testpfade).
4. **Welche Repositories?** A: nur eigene, aber vollständig (Paging) (**Empfehlung** als erster Schritt, kein Rechte-Risiko). B: zusätzlich Repositories aus Organisationen und Mitarbeit (`affiliation=owner,collaborator,organization_member`); längere Liste, Rechtefrage zu prüfen. Wie viele Repositories und Projects hast du ungefähr?
5. **Tiefe der Einstellungssuche.** A: Seiten und wichtige einzelne Schalter als Schlagwörter, Tipp öffnet die Seite (**Empfehlung**). B: jeder Schalter ein eigener Treffer mit Sprung und Hervorhebung der Zeile (deutlich mehr Pflege, Machbarkeit des Scrollens in `Form` offen).
6. **Englische Suchwörter bei deutscher Oberfläche** („backup“, „voice“)? A: nein, nur die Sprache der Oberfläche (**Empfehlung**). B: beide Sprachen durchsuchen.
7. **Auch die Personen-Auswahl („Zuweisen“)** auf die durchsuchbare Seite umstellen? A: nicht in diesem Issue (**Empfehlung**). B: mitnehmen.

**Aufwand:** Teil A 9–11 h (A1 1 h, A2 2,5 h, A3 3 h, A4 2 h, A5 1 h, Rest Gerätetest); Teil B 8–10 h (B1 3 h, B2 2,5 h, B3 3 h); Teil C 3–4 h. Zusammen 20–25 h; ohne C 17–21 h.

---

# Issue #332 – Projektfortschritt: Übersicht und Verlauf/Trend je Projekt

Das größte der vier Vorhaben und das einzige mit einem neuen Bereich. Vor dem Bau braucht es die Entscheidungen unten und Mockups (dieser Plan liefert keine).

## Befund im Quelltext

| Frage | Befund |
|---|---|
| Gibt es „Projekte“ in Tagwerk? | Nur als Gruppierung: `TaskItem.container` (Erinnerungsliste, Repository, „Lokal“) und `subContainers` (GitHub Projects). Keine Projektseite, keine eigene Gruppe. |
| Jira | Im App-Quelltext nicht vorhanden (keine Fundstelle in `Tagwerk/`, `Packages/`). Jira gibt es nur im Werkzeug des Owners (`t3jira`), nicht in der App. |
| GitHub: was wird geladen? | Nur **offene, mir zugewiesene** Issues mit ihren Project-Einträgen (`ProjectsQuery.assignedIssues`), dazu geschlossene Issues eines Zeitraums für den Rückblick (`GitHubAPI.closedIssues`, nur `closedAt`, `stateReason`, Projekt-IDs; höchstens 300). Eine Abfrage aller Einträge eines Projects gibt es nicht. |
| Erinnerungen | Offene je Liste; erledigte über die Suche (`SearchSources.completedTasks`, `CompletedTask.completedAt`). EventKit kennt Anlage- und Abschlussdatum je Erinnerung **[Doku]**; gelöschte Erinnerungen sind weg. |
| Lokale Aufgaben | `LocalTask.createdAt`, `completedAt` (`Persistence/LocalTask.swift`). |
| Zeit | Eingeplant: Zeitblöcke mit Aufgabenbezug (`EventTaskLink.taskKey`, Plan-Kalender, `PlanStore`) und Schätzungen (`TaskItem.estimateMinutes`). Investiert: `FocusSessionRecord.focusedSeconds` je `taskKey`, `EffortSampleRecord.actualMinutes` je `taskKey`. Keines davon kennt das Projekt; die Zuordnung läuft über die Aufgabe. |
| Verlauf von Statuswechseln | Wird nirgends festgehalten. |
| Diagramme | Swift Charts ist im Einsatz (`WeightChart.swift`, `IntakeChart.swift`). |
| Einstiegspunkte | Kopf von „Aufgaben“: `TasksEntrySection` (Einkaufsliste, Notizen, Bible Study) mit `TasksDestination`. |

## Begriffe (Arbeitsdefinitionen, vom Owner zu bestätigen)

- **Projekt:** eine vom Nutzer gewählte Gruppierung von Aufgaben aus genau einer Quelle. Empfehlung für Stufe 1: jedes in den Einstellungen gewählte **GitHub Project**, jede gewählte **Erinnerungsliste** (ohne Einkaufsliste) und **„Lokal“**.
- **Erledigt:** Issue geschlossen mit Grund „completed“ oder ohne Grund (so rechnet `ClosedIssue.isCompleted` schon); Erinnerung bzw. lokale Aufgabe abgehakt. „Nicht geplant“ und „Duplikat“ zählen als **geschlossen**, nicht als erledigt.
- **Offener Bestand** an einem Tag: Aufgaben, die an dem Tag angelegt und noch nicht geschlossen waren. Er lässt sich aus Anlage- und Schlussdatum rückwirkend berechnen; dafür braucht es keine eigenen Momentaufnahmen.
- **Trend** (operationalisiert, Schwellen als benannte Konstanten, Vergleich der letzten 4 Wochen):
  - „abgeschlossen“: offener Bestand 0.
  - „stockt“: Bestand > 0 und in den letzten 21 Tagen weder etwas erledigt noch angelegt.
  - „wächst“: in 4 Wochen mindestens 2 mehr angelegt als erledigt.
  - „geht voran“: in 4 Wochen mindestens so viel erledigt wie angelegt und mindestens 1 erledigt.
  - sonst „gleichbleibend“.
  Diese Schwellen sind Setzungen ohne Datenbasis; sie sind am eigenen Bestand zu prüfen und gehören in eine Datei, damit sie leicht zu ändern sind.
- **Bewegt:** jüngstes Ereignis (angelegt, erledigt, geschlossen, wieder geöffnet, Statuswechsel) des Projekts.

## 1. Umfang

**Stufe 1 – Übersicht und Projektseite mit Zählwerten (erster Pull Request)**
- Seite „Projekte“: alle Projekte mit offen/erledigt, Fortschrittsanteil, Trend als Wort, „zuletzt bewegt“, kleiner Verlauf des offenen Bestands (8 Wochen).
- Projektseite: Zeitraumwahl; „Erledigt und neu je Woche“; „Offener Bestand“; Liste „Offene Punkte“ (überfällig, Frist in 14 Tagen, blockiert, übrige); „Verlauf“ (angelegt, erledigt, geschlossen) in zeitlicher Folge.
- Quellen: GitHub Projects (neue Abfrage aller Einträge), Erinnerungslisten, „Lokal“.

**Stufe 2 – Zeit (zweiter Pull Request)**
- „Eingeplant und investiert je Woche“: Zeitblöcke und Fokus-Sitzungen der Aufgaben des Projekts; Summe „geschätzt offen“.

**Stufe 3 – Statuswechsel (dritter Pull Request, nach einem Spike)**
- „Verschoben“ im Verlauf (z. B. „nach In Progress“), über Momentaufnahmen ab Einbau oder über die Issue-Timeline von GitHub, falls sie die Wechsel liefert **[zu prüfen]**.

**Ausdrücklich nicht drin**
- Jira (nicht in der App), eigene Projektgruppen über Quellen hinweg, Repositories als Projekte (Frage 1).
- Prognosen („fertig am …“), Burndown gegen einen Zieltermin, Geschwindigkeit in Punkten.
- Bearbeiten von Projekten oder Feldern; die Projektseite öffnet Aufgaben im vorhandenen Editor.
- KI-Auswertung, Senden von Projektdaten an ChatGPT, Mitteilungen bei stockenden Projekten, Widget.
- Pull Requests und Draft Issues als eigene Zählgröße (Frage 6).
- Rekonstruktion des Verlaufs vor dem Einbau für Statuswechsel (nur mit der Timeline möglich).

## 2. UX (in Worten; Mockups folgen nach den Entscheidungen)

**Einstieg.** Zeile „Projekte“ in `TasksEntrySection` (Symbol `chart.bar.xaxis`), Untertitel „4 Projekte · 1 stockt“, öffnet `TasksDestination.projects`. Zusätzlich im Kontextmenü einer Aufgabe „Projekt zeigen“ (`TaskContextMenu.swift`) als spätere Ergänzung.

**Seite „Projekte“**
- Abschnitt „Zuletzt bewegt“ (Bewegung in den letzten 14 Tagen), Abschnitt „Länger nicht bewegt“ (älter), jeweils nach jüngster Bewegung sortiert.
- Zeile: Name; Quelle als Symbol mit Label (GitHub, Erinnerungen, Lokal); „12 offen · 34 erledigt“; Fortschrittsbalken (erledigt / alle); Trend als Wort mit Symbol („geht voran“, „wächst“, „stockt seit 3 Wochen“, „gleichbleibend“, „abgeschlossen“); rechts ein kleiner Verlauf des offenen Bestands. Bei AX-Größen steht der Verlauf unter dem Text oder entfällt.
- Ziehen zum Aktualisieren; Fußzeile „Stand: heute, 14:02“.

**Projektseite**
- Kopf: Name, Quelle, „12 offen · 34 erledigt · 3 nicht geplant“, Trendsatz („In 4 Wochen 9 erledigt, 5 neu.“), „Auf GitHub öffnen“ bei GitHub-Projekten.
- Auswahl „4 Wochen · 12 Wochen · 6 Monate“ (Frage 2).
- Diagramm „Erledigt und neu“ (zwei Balken je Woche), Diagramm „Offener Bestand“ (Linie). Unter jedem Diagramm ein Satz mit den Zahlen; die Diagramme tragen `accessibilityChartDescriptor` oder sind verborgen und der Satz trägt die Aussage.
- (Stufe 2) Diagramm „Zeit“: eingeplant gegen investiert je Woche; Zeile „Geschätzt offen: 14 h (5 ohne Schätzung)“.
- „Offene Punkte“: Gruppen „Überfällig“, „Frist in den nächsten 14 Tagen“, „Blockiert“, „Weitere“ (je 5, „Alle zeigen“); Zeile = `TaskRow`, Tipp öffnet den Editor. Aufgaben, die nicht in Tagwerk geladen sind (fremd zugewiesen), erscheinen als schlichte Zeile mit Titel, Person und Link zu GitHub.
- „Verlauf“: nach Tagen gruppiert („Heute“, „Gestern“, Datum), je Zeile Symbol, Text („Erledigt: #319 Strichcode-Scan“), Uhrzeit; 25 je Seite, „Weitere zeigen“.

**Zustände**

| Zustand | Anzeige |
|---|---|
| Keine Quelle verbunden | `ContentUnavailableView`: „Noch keine Projekte“ · „Verbinde GitHub oder erlaube Erinnerungen unter Einstellungen.“ · Knopf „Einstellungen öffnen“ |
| GitHub nicht verbunden, Erinnerungen ja | nur Listen und „Lokal“; Fußzeile „GitHub ist nicht verbunden.“ |
| Erinnerungen verweigert | nur GitHub/„Lokal“; Fußzeile „Tagwerk darf nicht auf Erinnerungen zugreifen.“ |
| Erster Abruf | Zeilen aus lokalen Quellen sofort; GitHub-Zeilen mit Fortschrittsanzeige „Wird geladen …“ |
| Abruf fehlgeschlagen, Speicher vorhanden | Daten aus dem Speicher · „Stand vom 24.11., 18:02. GitHub ist gerade nicht erreichbar.“ |
| Abruf fehlgeschlagen, kein Speicher | Zeile „GitHub ist gerade nicht erreichbar.“ · „Erneut versuchen“ |
| Abfragelimit | „GitHub nimmt gerade keine weiteren Abfragen an. Versuch es in einigen Minuten noch einmal.“ |
| Projekt größer als die Ladegrenze | „Es werden die 500 zuletzt geänderten Einträge ausgewertet.“ |
| Projekt ohne Einträge | „In diesem Projekt gibt es noch nichts.“ |
| Erinnerungslisten | Fußtext „Gelöschte Erinnerungen fehlen im Verlauf; der frühere Bestand kann deshalb höher gewesen sein.“ |
| Zu wenig Verlauf für einen Trend (Projekt jünger als 14 Tage) | Trend „noch kein Trend“ |

**Barrierefreiheit.** Trend immer als Wort; Balken und Linien nie alleinige Träger. Diagrammhöhen fest, Text darunter umbrechend. Zeilen ≥ 44 pt. Farben aus den vorhandenen Tönen; für zwei Balkenreihen zusätzlich unterschiedliche Füllung oder Beschriftung, weil zwei Farben allein die Kontrast- und Farbsehprüfung nicht bestehen.

## 3. Daten und Architektur

**Kern (`TagwerkCore`, neu `ProjectProgress.swift`)** – reine, getestete Logik:
- `ProjectKey` (`kind: .gitHubProject | .reminderList | .local`, `id`).
- `ProjectItemFact` (`id`, `title`, `number?`, `createdAt`, `closedAt?`, `isCompleted`, `due: DueDate?`, `status: String?`, `isBlocked`, `assignees`, `taskKey: String?`, `url?`, `estimateMinutes?`).
- `ProjectProgress.make(facts:now:calendar:weeks:)` → `ProjectSummary` (offen, erledigt, geschlossen ohne Erledigung, `lastActivity`, `trend`, `weeks: [WeekBucket(created, completed, openAtEnd)]`).
- `ProjectTrend` mit den Schwellen als Konstanten; `ProjectEvent` (`created`, `completed`, `closedNotPlanned`, später `statusChanged`) und `ProjectProgress.events(facts:)`.
- `ProjectOpenItems.groups(facts:today:)` (überfällig, bald fällig, blockiert, weitere).
- `ProjectTime.weeks(blocks:sessions:facts:)` (Stufe 2).

**GitHub (`GitHubKit`, neu `ProjectItemsQuery.swift`)**
- GraphQL: `node(id: $project) { ... on ProjectV2 { items(first: 100, after: $cursor, orderBy: {field: POSITION, direction: ASC}) { pageInfo nodes { id createdAt updatedAt isArchived fieldValues(…Status, Due, Estimate…) content { __typename ... on Issue { id number title url state stateReason createdAt closedAt assignees(first: 10) labels(first: 20) } } } } } }`. Ob `ProjectV2ItemConnection` eine Sortierung nach Änderungsdatum anbietet, ist **[zu prüfen]**; ohne sie gilt die Ladegrenze in Board-Reihenfolge und der Hinweistext wird angepasst.
- Obergrenze 5 Seiten (500 Einträge) je Projekt, ein Projekt nach dem anderen, nur beim Öffnen der Seite oder beim Ziehen; Höchstalter des Speichers 1 h. Kosten: GraphQL-Punktebudget 5.000 je Stunde **[Doku]**; 4 Projekte × 5 Seiten sind unkritisch, die genauen Kosten je Abfrage zeigt `rateLimit { cost }` im Spike.
- Rechte: vorhandener Scope `repo project`. Kein neuer Scope, keine neue Anmeldung.
- Blockiert: Label `blocked` (ohne Groß-/Kleinschreibung) **oder** Status-Option, deren Name „blocked“/„blockiert“ enthält (Frage 5).
- Statuswechsel (Stufe 3): Spike, ob `Issue.timelineItems(itemTypes: [PROJECT_V2_ITEM_STATUS_CHANGED_EVENT, ADDED_TO_PROJECT_V2_EVENT, REOPENED_EVENT, CLOSED_EVENT])` verfügbar ist und was es kostet **[zu prüfen, Typnamen aus dem Gedächtnis, nicht nachgeschlagen]**. Rückfallweg: Momentaufnahmen.

**Erinnerungen (`RemindersKit`)**
- `EventKitGateway.reminderFacts(listIDs:since:)`: offene und seit `since` erledigte Erinnerungen mit `creationDate`, `completionDate`, Frist. Baut auf dem Leseweg der Suche für erledigte Erinnerungen auf. Erinnerungen ohne Anlagedatum zählen ab ihrer ältesten bekannten Zeitangabe **[zu prüfen am Gerät, ob `creationDate` für synchronisierte Listen gesetzt ist]**.
- Wiederkehrende Erinnerungen: jede Erledigung erzeugt keine neue Aufgabe im Bestand; sie zählen als eine offene Aufgabe und tauchen im Verlauf nur über Tagwerks eigene Abschlusszeiten auf. Für Stufe 1: wiederkehrende Erinnerungen aus dem Trend ausschließen und das im Fußtext sagen.

**Lokal:** `LocalTaskProvider` liefert `createdAt`/`completedAt`; eine kleine Lesefunktion `localFacts(since:)`.

**Zeit (Stufe 2):** Zuordnung über `taskKey` der Fakten: `FocusStore`-Sitzungen (`focusedSeconds`, `start`) und Zeitblöcke mit `EventTaskLink` bzw. Plan-Einträgen im Zeitraum. Sitzungen und Blöcke zu Aufgaben, die nicht mehr im Projekt sind, fallen heraus; das steht als Hinweis unter dem Diagramm. Kein Schemawechsel.

**App**
- `Tagwerk/Projects/` (neu): `ProjectsModel` (`@Observable`, lädt Speicher zuerst, dann Quellen; Zustände je Projekt), `ProjectsOverviewView`, `ProjectDetailView`, `ProjectDetailModel`, `ProjectCharts.swift`, `ProjectEventRow.swift`, `ProjectSources` (Closures wie `SearchSources`, damit das Modell ohne EventKit und Netz testbar ist).
- `TasksDestination.projects`, `.project(ProjectKey)`; Zeile in `TasksEntrySection`; `AppEnvironment.makeProjectsModel()`.
- **Speicher:** `CachedProjectFacts` (`@Model`: `projectKey`, `payload` JSON, `fetchedAt`), nur für GitHub; wiederherstellbar, daher in `BackupCoverage.excluded` mit Begründung. Stufe 3 (falls Momentaufnahmen): `ProjectStatusSnapshot` (`projectKey`, `itemID`, `status`, `seenAt`) – nicht wiederherstellbar, also **in die Sicherung**.
- **Demo/Tests:** Demo-Quelle mit festen Fakten hinter dem vorhandenen UI-Testmodus (`UITestMode`), damit Übersicht und Projektseite ohne Netz prüfbar sind.

**Datenschutz**
- Nichts Neues verlässt das Gerät außer den GitHub-Abfragen mit der bestehenden Anmeldung. Die Abfrage aller Einträge liest auch Issues **anderer Personen** in den Projekten (Titel, Zuweisung); sie bleiben im lokalen Speicher und in keiner Sicherung. Das ist eine Erweiterung gegenüber heute („nur mir zugewiesene“) und gehört in die Datenschutzhinweise der App, falls es welche zu GitHub gibt **[zu prüfen]**.
- Kein neuer Berechtigungsdialog, kein neuer Text in `Info.plist`.

## 4. Umsetzungsschritte

**Vorab (kein Code in `main`)**
- [ ] **S0 Spike (2–3 h):** GraphQL-Abfrage aller Project-Einträge gegen das eigene Project „Tagwerk“ (Kosten, Sortierung, Dauer); Timeline-Ereignisse für Statuswechsel; `creationDate` von Erinnerungen am Gerät. Ergebnis als Abschnitt in diesem Plan.
- [ ] **S1 Mockups** nach den Entscheidungen (Übersichtszeile, Projektseite, Diagramme bei AX5).

**Stufe 1**
- [ ] **1 `feat: compute project progress from item facts`** – `ProjectProgress.swift`. Tests: `summary_countsOpenCompletedAndNotPlanned`, `weeks_openAtEndReconstructedFromDates`, `weeks_itemCreatedAndClosedInSameWeek`, `trend_stalledAfter21QuietDays`, `trend_growingWhenCreatedExceedsCompleted`, `trend_progressing`, `trend_finishedWhenNothingOpen`, `trend_unknownForYoungProjects`, `events_sortedNewestFirst`, `lastActivity_usesNewestEvent`, `openGroups_overdueSoonBlockedRest`.
- [ ] **2 `feat: read all items of a GitHub project`** – `ProjectItemsQuery.swift`, `GitHubAPI.projectItems(projectID:)`, Zuordnung zu `ProjectItemFact`. Tests (Fake-Transport): `projectItems_followsCursorUpToLimit`, `projectItems_skipsDraftsAndPullRequests`, `projectItems_mapsStateReason`, `projectItems_readsStatusDueEstimate`, `projectItems_partialErrorsKeepReadableNodes`, `blocked_byLabelOrStatusName`.
- [ ] **3 `feat: read reminder and local task facts`** – `EventKitGateway.reminderFacts`, `LocalTaskProvider.localFacts`. Tests: `reminderFacts_openAndCompletedSince`, `reminderFacts_excludesShoppingList`, `reminderFacts_recurringExcludedFromTrend`, `localFacts_createdAndCompleted`.
- [ ] **4 `feat: cache project facts`** – `CachedProjectFacts`, Speicher, `BackupCoverage.excluded`. Tests: `cache_roundTrip`, `cache_staleAfterOneHour`, `backupCoverage_listsEveryModel` (bestehender Test) bleibt grün.
- [ ] **5 `feat: add the projects overview`** – `ProjectsModel`, `ProjectsOverviewView`, Einstieg, Route, Demo-Quelle, Texte. Tests (`ProjectsModelTests`): `load_showsCachedThenFresh`, `load_gitHubFails_keepsCacheAndReportsAge`, `load_withoutGitHub_showsListsAndLocal`, `sections_recentVersusQuiet`, `entrySubtitle_countsStalledProjects`. UI-Tests (`ProjectsUITests`): `testProjectsOverview_opensFromTasks`, `testProjectsOverview_emptyState`; Audit beider Größen.
- [ ] **6 `feat: add the project page with charts, open items and history`** – `ProjectDetailView`, Diagramme, Listen. Tests: `detail_periodChangesBuckets`, `detail_historyPagesBy25`, `detail_foreignItemsShownAsPlainRows`. UI-Tests: `testProjectPage_showsChartsAndOpensTask`, `testProjectPage_largestTextKeepsContentReachable`; Audit beider Größen und dunkel.
- [ ] **7 Gerätetest:** eigenes Project „Tagwerk“ und eine Erinnerungsliste; Zahlen gegen GitHub prüfen.

**Stufe 2**
- [ ] **8 `feat: compute planned and focused time per project`** – `ProjectTime`. Tests: `time_sumsFocusSessionsPerWeek`, `time_sumsLinkedBlocksPerWeek`, `time_ignoresTasksOutsideTheProject`, `time_openEstimateAndCountWithoutEstimate`.
- [ ] **9 `feat: show planned and focused time on the project page`** – Diagramm, Zeile, UI-Test, Audit.

**Stufe 3 (nach S0)**
- [ ] **10 `feat: record status changes of project items`** – Timeline-Abfrage oder Momentaufnahmen inkl. Sicherung; Tests je nach Weg (`snapshotDiff_emitsStatusChange`, `snapshot_firstSightEmitsNothing`, `backup_roundTripsSnapshots`).
- [ ] **11 `feat: show moved items in the project history`**.

## 5. Risiken, Fragen, Aufwand

**Risiken**
1. **Umfang.** Ohne die Abgrenzung oben wird daraus ein eigenes Produkt. Die Stufen sind einzeln lieferbar; Stufe 1 beantwortet bereits beide Ebenen des Issues bis auf „verschoben“ und „Zeit“.
2. **Kein Verlauf für Statuswechsel bei GitHub Projects.** ProjectV2 bietet keine Feldhistorie; ob die Issue-Timeline die Wechsel liefert, ist ungeprüft. Momentaufnahmen zeigen nur Wechsel ab Einbau und nur so genau, wie die App aktualisiert (zwei Wechsel zwischen zwei Abrufen erscheinen als einer).
3. **Große Projekte.** Das Repository steht bei Nummer 335 (Issues und Pull Requests zusammen); wie viele Einträge das eigene Project hat, ist nicht gezählt **[zu prüfen in S0]**. Wächst es über die Grenze von 500, gilt: Dann fehlen alte Einträge und der rückgerechnete Bestand stimmt für frühe Wochen nicht mehr. Abhilfe: Grenze erhöhen (Kosten messen) oder geschlossene Einträge über die Issue-Suche mit Zeitraum nachladen.
4. **Erinnerungen sind eine schwache Quelle.** Gelöschte fehlen, wiederkehrende verzerren, Anlagedaten können nach einem Gerätewechsel fehlen. Der Trend von Listen ist deshalb weniger belastbar als der von GitHub; das muss sichtbar sein.
5. **Trendregeln sind Setzungen.** Sie können an echten Daten unsinnig wirken (ein Projekt mit einer großen offenen Aufgabe „stockt“ nie sichtbar). Vor dem Festschreiben am eigenen Bestand durchrechnen (Teil von S0).
6. **Fremde Issues im lokalen Speicher** (Titel, Zuweisung anderer Personen): bisher nicht der Fall.
7. **Zeit je Projekt ist lückenhaft:** Fokus-Sitzungen ohne Aufgabe und Blöcke ohne Aufgabenbezug fehlen; erledigte Issues, die aus dem Project entfernt wurden, verlieren ihre Zeit.

**Fragen an den Owner**
1. **Was zählt als Projekt?** A: GitHub Projects + Erinnerungslisten + „Lokal“, je Quelle getrennt (**Empfehlung**; entspricht den vorhandenen Gruppierungen und der Auswahl in den Einstellungen). B: zusätzlich Repositories als eigene Projekte (doppelte Zählung derselben Issues in Repository und Project). C: eigene Gruppen in Tagwerk über Quellen hinweg (neues Modell, eigener Entwurf). Jira ist in der App nicht vorhanden und wäre ein eigenes Vorhaben.
2. **Zeiträume.** A: feste Auswahl „4 Wochen · 12 Wochen · 6 Monate“, Wochen als Einheit (**Empfehlung**). B: zusätzlich Monat als Einheit und freier Zeitraum (mehr Oberfläche, mehr Testfälle; freie Zeiträume sind für Trends selten nötig).
3. **Einstieg.** A: Zeile „Projekte“ im Kopf von „Aufgaben“ (**Empfehlung**: Projekte sind Gruppen von Aufgaben; kein neuer Tab). B: Abschnitt in „Planen“ (Woche). C: zusätzlich eine Kurzfassung im Wochenrückblick („3 Projekte bewegt, 1 stockt“) – sinnvoll als spätere Ergänzung zu A.
4. **Wessen Aufgaben zählen bei GitHub?** A: alle Einträge des Projects, mit Zusatz „davon mir zugewiesen: n“ (**Empfehlung**: „Projektfortschritt“ meint das Projekt). B: nur mir zugewiesene (billiger: baut auf den vorhandenen Abfragen auf, aber kein echter Projektstand).
5. **Blocker.** A: Label `blocked` oder eine Status-Stufe mit „Blocked“/„Blockiert“ (**Empfehlung**). B: zusätzlich in Tagwerk von Hand markierbar (neues Feld, auch für Erinnerungen). Welche Stufen und Labels nutzt du dafür heute?
6. **Pull Requests und Draft Issues** in Projects? A: nicht zählen (**Empfehlung**). B: Draft Issues als Aufgaben mitzählen.
7. **Statuswechsel („verschoben“).** A: Stufe 3 nach dem Spike, bis dahin nur angelegt/erledigt/geschlossen (**Empfehlung**). B: Momentaufnahmen sofort in Stufe 1 mitbauen, damit der Verlauf früher beginnt (mehr Umfang im ersten Pull Request, Sicherung betroffen).
8. **Zeit.** A: Stufe 2 wie beschrieben (Zeitblöcke und Fokus-Sitzungen) (**Empfehlung**). B: weglassen, bis genügend Fokus-Daten da sind.
9. **Trendschwellen** (21 Tage ohne Bewegung = „stockt“; 4-Wochen-Vergleich): so übernehmen oder andere Werte?
10. **Erledigte Projekte** (Bestand 0) und geschlossene GitHub Projects: A: am Ende unter „Abgeschlossen“ eingeklappt (**Empfehlung**). B: ausblenden.

**Aufwand:** S0 + Mockups 5–7 h; Stufe 1 24–30 h (1: 4 h, 2: 5 h, 3: 4 h, 4: 2 h, 5: 5 h, 6: 7 h, Gerätetest 2 h); Stufe 2 6–8 h; Stufe 3 6–10 h je nach Weg. Zusammen 41–55 h. Die Spanne ist groß, weil drei Annahmen (Sortierung der Project-Einträge, Timeline, Anlagedaten von Erinnerungen) ungeprüft sind.

---

# 6. Abhängigkeiten und Reihenfolge

**Abhängigkeiten**

| Von | Zu | Art |
|---|---|---|
| #319 | – | unabhängig; baut nur auf Gebautem (E4/E5) |
| #320 | – | unabhängig; baut auf `WeightTrend` (F3) und `DayBudgets` (C1), beide auf `main` |
| #331 A | – | unabhängig |
| #331 B | – | unabhängig von A; berührt `SettingsView` vollständig |
| #331 C | #331 B | braucht den Index |
| #331 C „Projekte als Treffer“ | #332 Stufe 1 | braucht die Projektseite als Ziel |
| #332 | Entscheidungen 1–4, S0, Mockups | blockiert bis dahin |
| #332 Abschnitt 2 | #331 A2 | beide ändern `GitHubKit` (`ProjectsQuery`, `GitHubAPI`); nicht gleichzeitig |

**Gemeinsam berührte Dateien (Konfliktquellen):** `Localizable.xcstrings`, `scripts/translations/en.json`, `Common/AccessibilityID.swift` (alle); `App/AppEnvironment.swift` (#320, #332, evtl. #319); `Capture/`-Ordner (#319 und #320, aber verschiedene Dateien); `Backup/BackupDTOs.swift` (#331 A3, #332 Stufe 3); Audit-Tests (alle).

**Empfohlene Reihenfolge (höchstens 3 Stränge gleichzeitig)**

- **Runde 1 (sofort, parallel):**
  - Strang 1: **#319** – klein, entschieden bis auf vier Detailfragen, höchster Nutzen im Alltag.
  - Strang 2: **#320** – klein, schließt das Epic #254 ab.
  - Strang 3: **#331 Teil A** – nach Antwort auf Fragen 2–4; unabhängig von den Ernährungssträngen.
  - Nebenher (kein Umsetzungsstrang): Entscheidungen zu #332, Spike S0, Mockups.
  - Merge-Reihenfolge: #320 → #319 → #331 A (aufsteigend nach Zahl der berührten gemeinsamen Dateien).
- **Runde 2 (parallel):**
  - Strang 1: **#331 Teil B** (dann C).
  - Strang 2: **#332 Stufe 1, Schritte 1–4** (Kern, Abfragen, Speicher) – erst nach dem Merge von #331 A2 wegen `GitHubKit`.
  - Strang 3 frei für Nacharbeit aus den Gerätetests von Runde 1.
- **Runde 3:** #332 Stufe 1, Schritte 5–6 (Oberfläche), danach Stufe 2 und Stufe 3 nacheinander.

Begründung: #319 und #320 sind die einzigen, deren Anforderungen bereits durch freigegebene Entscheidungen (LM2b, OR4b, ZI6b) gedeckt sind. #331 ist ohne Issue-Text eine Auslegung und braucht eine kurze Bestätigung, ist dann aber gut teilbar. #332 hat die größte Unsicherheit und den größten Umfang; früher Bau ohne Entscheidungen würde mit hoher Wahrscheinlichkeit verworfen.

**Gesamtaufwand (Summe der Spannen):** #319 9–11 h · #320 7–9 h · #331 17–25 h · #332 41–55 h → 74–100 h.

---

# Geprüft, angenommen, offen

**Im Quelltext gelesen (Stand `c3cecc8d`):** `Capture/ProductLookup.swift`, `ProductSearchModel.swift`, `ProductSearchView.swift`, `FoodPickerView.swift`, `FoodStore.swift`, `CameraPicker.swift`, `DemoProductTransport.swift`, `WeekReviewModel.swift`, `WeekReviewView.swift`, `TrendModel.swift`, `WeightStore.swift`, `GoalPlanningEntries.swift`; `TagwerkCore`: `ProductSearchRules.swift`, `WeekReview.swift`, `WeightTrend.swift`, `TaskItem.swift`, `AppRoute.swift`, Auszüge aus `OpenFoodFacts.swift`, `EffortStats.swift`, `GoalPlan.swift`; `Search/SearchModel.swift`; `Settings/SettingsView.swift`, `SettingsDestination.swift`, `GitHubSettingsSection.swift`, `SourceSelectionView.swift`; `Tasks/ProjectSelection.swift`, `TasksDestination.swift`, `TasksEntrySection.swift`; `GitHubKit`: `ProjectsQuery.swift`, `ClosedIssues.swift`, `GitHubCatalog.swift`, Auszug `GitHubAPI.swift`; `Focus/FocusRecords.swift`, `Planning/EventTaskLink.swift`, `Persistence/CachedGitHubIssue.swift`, `App/UITestScreen.swift`, `project.yml`.

**Nur in Ausschnitten oder gar nicht gelesen (vor der Umsetzung bestätigen):** `FoodEditSheet.swift` (Erhalt des Strichcodes beim Speichern), `MealSheet.swift`, `FoodLookupConsentSheet.swift`, `WeekReviewPagePreview`, `NewTaskSheet.swift`, `IssueTargetSheet.swift`, `TaskProposalEditor.swift`, `SearchSheet.swift`, `SearchResults.swift`, `GitHubTaskProvider.swift`, `EventKitGateway.swift`, `PlanStore.swift`, `FocusStore.swift`, `BackupCoverage.swift`, die Audit-Tests.

**Ungeprüfte Annahmen über fremde Systeme:** Verhalten von `DataScannerViewController` bei UPC-A und bei verweigerter Kamera; Schreibweise der Codes bei Open Food Facts; Vollständigkeit von `user/repos` mit weiteren Affiliations unter dem vorhandenen Scope; Sortierung und Kosten von `ProjectV2.items`; Verfügbarkeit von Project-Ereignissen in der Issue-Timeline; `creationDate` synchronisierter Erinnerungen. Jede dieser Annahmen ist einem Spike oder Gerätetest in den Schritten zugeordnet.
