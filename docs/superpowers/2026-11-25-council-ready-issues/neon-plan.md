# Umsetzungs- und Designplan: Issues #319, #320, #331, #332

> **Rolle:** Design- & Architekturplan (Council-Beitrag). Stand der Codebasis: Branch `chore/plan-next-steps` (`app/project.yml`, iOS 27.0, Swift 6 Strict Concurrency, SwiftData, XcodeGen).
> **Mockups im selben Ordner:**
> - [`mockup-319-barcode.html`](mockup-319-barcode.html)
> - [`mockup-320-weekly-review.html`](mockup-320-weekly-review.html)
> - [`mockup-331-search.html`](mockup-331-search.html)
> - [`mockup-332-project-progress.html`](mockup-332-project-progress.html)

---

## Überblick, Abhängigkeiten und empfohlene Reihenfolge

### Rahmenbedingungen über alle vier Issues
- **Apple Personal Team (kostenlos):** Keines der vier Issues benötigt ein neues Entitlement, eine neue App-Extension oder ein kostenpflichtiges Capability.
  - #319 nutzt `VisionKit` (`DataScannerViewController`), ein System-Framework ohne eigenes Entitlement; `NSCameraUsageDescription` existiert bereits in `app/project.yml` (Zeile 60) und wird lediglich textlich um Strichcodes ergänzt.
  - #320 nutzt bestehende SwiftData-Stores (`IntakeStore`, `WeightStore`, `GoalStore`, `DayHealthStore`) und `HealthBridge` ohne neue Berechtigungsgruppe.
  - #331 ist reine App-/Core-Logik ohne neue Systemberechtigungen.
  - #332 nutzt bestehende GitHub-Scopes (`repo`, `project`), EventKit-Leserechte, lokale Stores und `Swift Charts` (bereits im Projekt durch `WeightChart.swift` / `IntakeChart.swift` etabliert).
- **Barrierefreiheit (durchgängig Pflicht):**
  - Alle interaktiven Elemente mindestens **44 × 44 pt** (`MinimumTapTarget.swift` / `TouchTarget.swift`).
  - **Dynamic Type bis AX5:** Keine festen Zeilenhöhen, `ViewThatFits` oder vertikaler Umbruch bei `dynamicTypeSize.isAccessibilitySize`, Diagramme mit gesprochener Textzusammenfassung (wie `TrendText.weightSummary`).
  - **Kontrast:** Text- und Symbolfarben ausschließlich über `TextTones.swift` (`Color("TextSecondary")`, `TextGreen`, `TextOrange`, `TextRed`, `TextPurple`, `AccentColor` aus `app/Design/Colors.xcassets`), geprüft durch `TextTonesTests`.
- **Lokalisierung:** Deutsch ist Quellsprache; jeder neue Text kommt in `Localizable.xcstrings` (App bzw. Paket) und `scripts/translations/en.json`.
- **SwiftUI-Konvention:** Niemals `.sheet`, `.confirmationDialog` oder `.alert` an eine `Section` oder Zeile innerhalb von `Form`/`List` hängen.

### Aufwandsübersicht und empfohlene Reihenfolge (max. 3 parallele Stränge)

| Issue | Thema | Aufwand (Schätzung) | Abhängigkeiten | Empfohlener Strang |
|---|---|---:|---|---|
| **#319** | Strichcode-Scan für Lebensmittel (E6) | **6–8 h** | Epic #254 (Strang E1–E5 bereits auf `main`) | **Strang 1** (sofort startbar, schließt Epic #254) |
| **#320** | Wochenrückblick: Zahlen zu Gewicht & Ernährung (C4) | **7–9 h** | Epic #254 (Strang A, C1, F1–F3 bereits auf `main`) | **Strang 2** (sofort startbar, schließt Epic #254) |
| **#331** | Suche für Einstellungen & Repositories/Projects | **10–14 h** | Keine harte Code-Abhängigkeit; **braucht Scope-Antwort des Owners** | **Strang 3** (nach kurzer Klärung parallel zu 1 & 2) |
| **#332** | Projektfortschritt: Global & Detail/Trend | **18–26 h** (2–3 PRs) | Profitiert konzeptionell von #331 (Repo-/Projekt-Katalog); **braucht 3 Owner-Entscheidungen** | **Nachgelagert** auf Strang 1/2 (sobald #319/#320 gemergt sind) |

**Begründung der Reihenfolge:**
1. **#319 und #320 zuerst und parallel (Stränge 1 & 2):** Beide sind die einzigen noch offenen Sub-Issues von Epic **#254** (aktuell 5/7 erledigt), haben keine überlappenden Dateien (`BarcodeScannerView`/`FoodPickerView` vs. `WeekReview`/`WeekReviewModel`/`WeekReviewView`) und schließen das Epic sauber ab.
2. **#331 auf Strang 3 parallel (nach Beantwortung der Scope-Fragen):** Berührt `Settings/`, `Search/`, `NewTaskSheet.swift`, `ProjectSelection.swift`, `IssueTargetSheet.swift`, `TaskProposalEditor.swift` – komplett disjunkt zu #319 und #320.
3. **#332 als zweiter Takt:** Größtes Feature mit eigenen Design- und API-Entscheidungen. Sollte nicht gleichzeitig mit #331 in `TasksEntrySection.swift` und `GitHubKit` kollidieren und in 2–3 kleinere PRs geschnitten werden (PR 1: Core-Modelle & globale Übersicht; PR 2: Projekt-Detail & Trend-Chart; PR 3: lokales Aktivitätslog & Zeitvergleich).

---

## Issue #319: Strichcode-Scan für Lebensmittel (E6)

### Ausgangslage im Code (bereits vorhanden)
Ein Großteil der technischen Basis aus Strang E (#254) existiert bereits auf `main`:
- `app/Packages/TagwerkCore/Sources/TagwerkCore/OpenFoodFacts.swift`: `OpenFoodFactsAPI.productRequest(barcode:userAgent:)` (prüft 8–14 ASCII-Ziffern, fragt `/api/v2/product/<code>` mit `fields=` ab), `OpenFoodFactsAPI.readProduct(_:)` (unterscheidet `status == 0` → `nil` von JSON-Fehler) und `ProductCandidate`.
- `app/Tagwerk/Capture/ProductLookup.swift`: `ProductLookingUp.product(barcode:)`, `ProductLookup.product(barcode:)` mit Einwilligungs-Gate (`hasConsent`), Offline-Prüfung (`ConnectivityMonitor`), lokalem Rate-Limiter (`productLimiter`: 15/min) und In-Memory-Cache (`products[code]`).
- `app/Tagwerk/Capture/ProductSearchView.swift`: `ProductPreviewView`, `ProductAttribution`, `ProductRow` sowie `ProductPreviewModel` in `ProductSearchModel.swift`.
- `app/Tagwerk/Capture/FoodLookupConsentSheet.swift`: Einwilligungsblatt nennt bereits „(später auch ein Strichcode)“ – dieser Satz wird auf „oder ein Strichcode“ aktualisiert.
- `app/Tagwerk/Capture/FoodPickerView.swift`: `FoodPickerCoordinator`, `FoodPickerSection`, `FoodAmountSheet`, `FoodPickerSheet`.
- `app/Tagwerk/Capture/FoodStore.swift`: `FoodStore` speichert `FoodValue` inklusive optionalem `barcode: String?`, hat aber noch keine Methode `food(barcode:)`.
- `app/Tagwerk/Capture/DemoProductTransport.swift`: Beantwortet `/api/v2/product` aktuell immer mit `{"status":0}` (muss um einen Demo-Treffer erweitert werden).

### Scope
- **In Scope:**
  - Live-Strichcode-Scanner auf dem Gerät via `VisionKit.DataScannerViewController` für Lebensmittel-Barcodes (`.ean13`, `.ean8`, `.upce`, `.upca` bzw. EAN/UPC-Familie).
  - Prüfen gegen `FoodStore.food(barcode:)` **vor** jedem Netzaufruf (bereits gespeichertes eigenes Lebensmittel direkt nutzbar, keine unnötige Anfrage an Open Food Facts).
  - Einwilligungs-Gate: Ohne `settings.isFoodLookupEnabled` wird zuerst `FoodLookupConsentSheet` gezeigt; erst nach Zustimmung geht die Abfrage raus.
  - Abruf über `environment.productLookup.product(barcode:)`, danach Anzeige in der bestehenden `ProductPreviewView` („Als Lebensmittel speichern“ → `FoodEditSheet`, bei Lücken „Stattdessen Etikett fotografieren“).
  - Manuelle Eingabe der Strichcode-Nummer als barrierefreier Fallback (und für Simulator/UI-Tests sowie beschädigte Etiketten).
  - Aktualisierung von `NSCameraUsageDescription` in `app/project.yml` / `Info.plist` / `InfoPlist.xcstrings` und des Einwilligungstexts in `FoodLookupConsentSheet.swift`.
- **Out of Scope:**
  - Produktbilder von Open Food Facts laden (CC BY-SA 3.0, bewusst ausgeschlossen laut Plan #254).
  - Automatisches Speichern ohne Prüf-Vorschau (`ProductPreviewView` bleibt Pflichtschritt).
  - QR-Codes, Mehrpaket-Stapelscan oder Offline-Datenbank.
  - Eigener zweiter Einwilligungsschalter (laut Entscheidung LM2b gilt derselbe Schalter „Online-Suche in Open Food Facts“).

### UX, Varianten und Zustände (deutscher Copy)
Mockup: [`mockup-319-barcode.html`](mockup-319-barcode.html)

- **Einstieg (Design-Entscheidung Variante A vs. B):**
  - **Variante A (empfohlen):** Im Segment „Meine Lebensmittel“ (`FoodPickerSection` in `MealSheet` und `FoodPickerSheet`) eine eigene Aktionszeile **„Strichcode scannen“** (`barcode.viewfinder`) direkt über „Etikett fotografieren“ sowie ein optionales kompaktes Scanner-Icon im Suchfeld-Kopf von `FoodPickerSheet`.
  - **Variante B:** Nur als Aktionszeile am Ende der Liste unter „Neues Lebensmittel“ und „Etikett fotografieren“.
- **Duplikat-Verhalten bei bereits lokal gespeichertem Strichcode (Variante A vs. B):**
  - **Variante A (empfohlen):** Lokaler Treffer in `FoodStore` öffnet eine kompakte Treffer-Karte im Scanner-Sheet: **„Bereits in ‚Meine Lebensmittel‘“** mit primärer Aktion **„Menge eingeben“** (direkt `FoodAmountSheet`, kein Netzaufruf!) und sekundärer Aktion **„Online neu abrufen“**.
  - **Variante B:** Immer online abrufen und als neues Lebensmittel anlegen (verursacht unnötige Duplikate und Netzverkehr).
- **Alle Zustände mit deutschem Copy:**
  1. **Sucher / Bereit:** Navigationsleiste `Abbrechen` · Titel `Strichcode` · Taschenlampen-Knopf (`flashlight.off.fill` / `flashlight.on.fill`, 44×44 pt). Hinweis im Sucher: *„Strichcode in den Rahmen halten“*. Darunter Button: *„Nummer von Hand eingeben“*.
  2. **Ohne Einwilligung (vor Netzabruf):** Öffnet `FoodLookupConsentSheet` (Titel *„Online-Suche in Open Food Facts“*, aktualisierter Text ohne „später“). Hinweis: Ohne Zustimmung verlässt der gescannte Code das Gerät nicht; ein lokaler Treffer in `FoodStore` funktioniert trotzdem.
  3. **Laden:** Nach Erkennung (einmaliges haptisches Feedback `.success`, Scanner pausiert): Overlay/Sheet-Karte mit `ProgressView` und *„Suche Produkt 4008400404127 …“* + `Abbrechen`.
  4. **Gefunden (Online):** Übergang in bestehende `ProductPreviewView` (Nährwerte, *„keine Angabe“* bei Lücken, *„Bitte mit der Verpackung vergleichen“*, *„Als Lebensmittel speichern“*, optional *„Stattdessen Etikett fotografieren“*, Fußzeile *„Daten: Open Food Facts (ODbL)“*).
  5. **Nicht gefunden (`nil`):** Karte im Sheet: Titel *„Strichcode nicht gefunden“*, Text *„Zu 4008400404127 gibt es keinen Eintrag bei Open Food Facts.“* Aktionen: *„Etikett fotografieren“* (wenn `ai.isSignedIn`), *„Lebensmittel selbst anlegen“* (öffnet `FoodEditSheet` mit vorausgefülltem `barcode`), *„Erneut scannen“*.
  6. **Fehlerzustände:** Nutzt direkt `ProductLookupError.message`:
     - Offline: *„Keine Verbindung“* (+ Hinweis: lokale Lebensmittel mit diesem Strichcode wurden geprüft).
     - Rate-Limit: *„Bitte kurz warten, noch X s. Open Food Facts erlaubt nur wenige Anfragen pro Minute.“*
     - 403 / 429 / 5xx / Netzwerkfehler: bestehende Texte aus `ProductLookupError` + Button *„Erneut versuchen“* / *„Erneut scannen“*.
     - Ungültiger Code (bei manueller Eingabe): *„Das ist kein gültiger Strichcode.“* (8–14 Ziffern).
  7. **Kamera-Zugriff verweigert (`AVAuthorizationStatus.denied` / `.restricted`):** Kein leerer schwarzer Bildschirm, sondern `ContentUnavailableView`: *„Kamerazugriff benötigt“*, Beschreibung *„Erlaube Tagwerk den Kamerazugriff in den iOS-Einstellungen, um Strichcodes zu scannen.“*, primärer Button *„Einstellungen öffnen“* (`UIApplication.openSettingsURLString`), sekundärer Button *„Nummer von Hand eingeben“*.
  8. **Scanner nicht verfügbar (z. B. Simulator oder Hardware ohne Unterstützung):** Direkter Hinweis *„Kamera-Scan auf diesem Gerät nicht verfügbar.“* und sofort geöffnetes Zahlenfeld *„Strichcode-Nummer (8–14 Ziffern)“* + Button *„Suchen“*.

### Daten & Architektur
- **Neue Dateien:**
  - `app/Tagwerk/Capture/BarcodeLookupModel.swift` (`@MainActor @Observable`): Zustandsautomat (`scanning`, `localMatch(FoodValue, code: String)`, `needsConsent(code: String)`, `loading(code: String)`, `found(ProductCandidate)`, `notFound(code: String)`, `failed(code: String, message: String)`). Enkapsuliert Single-Shot-Sperre (verhindert Mehrfach-Auslösung während der Verarbeitung) und prüft zuerst `FoodStore.food(barcode:)`.
  - `app/Tagwerk/Capture/BarcodeScannerView.swift`: `BarcodeScannerSheet` (SwiftUI-Wrapper mit `NavigationStack`, Kamera-Berechtigungsprüfung via `AVCaptureDevice.authorizationStatus(for: .video)`, Taschenlampe, manueller Eingabe, Zustandsanzeige und Push zu `ProductPreviewView`) + `DataScannerRepresentable: UIViewControllerRepresentable` für `VisionKit.DataScannerViewController`.
- **Zu erweiternde Dateien:**
  - `app/Tagwerk/Capture/FoodStore.swift`: `func food(barcode: String) -> FoodValue?` (exakter Vergleich nach Trimming).
  - `app/Tagwerk/Capture/FoodPickerView.swift`: `FoodPickerCoordinator.showsBarcodeScanner: Bool`, `.sheet(isPresented:)` in `FoodSheetsModifier`, Aktionszeile *„Strichcode scannen“* in `FoodPickerSection`.
  - `app/Tagwerk/Capture/FoodEditSheet.swift`: Optionalen `barcode: String?` in `FoodEditSheet.Seed` sauber übernehmen, auch beim Start aus „Nicht gefunden → Lebensmittel selbst anlegen“.
  - `app/Tagwerk/Capture/FoodLookupConsentSheet.swift`: Textzeile 46 von „(später auch ein Strichcode)“ auf „oder ein Strichcode“ aktualisieren.
  - `app/Tagwerk/Capture/DemoProductTransport.swift`: Bekannter Demo-Barcode (z. B. `4000000000001` → Demo Skyr natur, `4000000000002` → unvollständig, alle anderen → `{"status":0}`).
  - `app/project.yml` & `app/Tagwerk/Info.plist` & `app/Tagwerk/InfoPlist.xcstrings`: `NSCameraUsageDescription` um Strichcodes ergänzen.
  - `app/Tagwerk/Common/AccessibilityID.swift`: IDs für `FoodLookup.scanRow`, `FoodLookup.manualBarcodeField`, `FoodLookup.manualBarcodeSubmit`.

### Implementierungsschritte (kleine Commits + Tests)
1. **Commit 1:** `feat: look up own foods by barcode and add barcode lookup model`
   - `FoodStore.food(barcode:)`, `BarcodeLookupModel` (inkl. Zustandsübergänge, Einwilligungs-Gate, lokaler Treffer vor Netzabruf, Single-Shot-Sperre).
   - Unit-Tests (`BarcodeLookupModelTests`): `localMatch_skipsNetworkAndConsent`, `unknownCode_withoutConsent_asksConsentFirst`, `consentAgreed_runsLookupOnce`, `notFound_offersLabelPhotoOnlyWhenSignedIn`, `offline_reportsOfflineWithoutRequest`, `invalidManualBarcode_rejected`, `duplicateScanWhileLoading_ignored`.
2. **Commit 2:** `feat: add VisionKit barcode scanner sheet and manual fallback`
   - `BarcodeScannerView.swift`, `DataScannerRepresentable`, Kamera-Berechtigungs-Handling, Taschenlampe, manuelle Eingabe, Anbindung an `ProductPreviewView` und `FoodEditSheet`.
   - `Info.plist` / `project.yml` / `InfoPlist.xcstrings`, `FoodLookupConsentSheet` Text-Update, `Localizable.xcstrings` + `en.json`.
3. **Commit 3:** `feat: wire barcode scanner into food picker and add UI tests`
   - Integration in `FoodPickerView.swift` / `FoodPickerCoordinator`, Erweiterung `DemoProductTransport.swift`.
   - UI-Tests (`BarcodeLookupUITests` mit `-TagwerkDemoFoodLookup` über den manuellen Code-Fallback im Simulator): `scanFlow_manualCode_showsPreviewAndSavesFood`, `scanFlow_unknownCode_showsNotFoundAndManualCreate`, `scanFlow_localMatch_opensAmountDirectly` + Barrierefreiheits-Audit.

### Risiken & Gegenmaßnahmen
- **Simulator hat keine Kamera:** Manuelle Strichcode-Eingabe ist sowohl für echte Nutzer (zerknittertes Etikett / abgelehnte Kamera) als auch für deterministische Simulator-UI-Tests essenziell.
- **Kontinuierliche VisionKit-Callbacks:** `DataScannerViewController` feuert mehrfach pro Sekunde. Strikte Sperre im `BarcodeLookupModel` (`guard case .scanning = phase else { return }`) + `scanner.stopScanning()` sofort beim ersten gültigen Code verhindert Rate-Limit-Verbrauch.
- **Datenschutz-Invariante:** Gescannte Strichcodes dürfen niemals geloggt werden (wie in `ProductLookup.swift` bereits für `send()` beachtet) und verlassen das Gerät nur nach expliziter Einwilligung.

### Offene Fragen an den Owner (#319)
1. **Einstieg (Variante A vs. B):** Soll „Strichcode scannen“ prominent im Bereich „Meine Lebensmittel“ stehen (direkt neben/über „Etikett fotografieren“, **Empfehlung: A**), oder zusätzlich als eigener Schnell-Button direkt auf dem Haupt-Tab „Erfassen“?
2. **Lokaler Treffer (Variante A vs. B):** Wenn ein gescannter Strichcode bereits in „Meine Lebensmittel“ liegt, soll Tagwerk direkt das eigene Lebensmittel ohne Netzabruf anbieten (**Empfehlung: A**) oder trotzdem online bei Open Food Facts nachschlagen (**B**)?
3. **Einwilligung vor oder nach dem Scan:** Soll der Scanner zuerst lokal nachsehen dürfen und erst bei einem unbekannten Code nach der Open-Food-Facts-Einwilligung fragen (**Empfehlung: A**, spart unnötige Zustimmung bei eigenen Lebensmitteln), oder die Einwilligung schon beim Öffnen des Scanners verlangen (**B**)?

---

## Issue #320: Wochenrückblick: Zahlen zu Gewicht und Ernährung (C4)

### Ausgangslage im Code (Lückenanalyse gegen Plan #254 C4 / OR4b)
Die Code-Inspektion zeigt, dass Teile von C4 bereits umgesetzt wurden, aber **zentrale Bausteine fehlen**:
- **Bereits vorhanden:**
  - `WeekReview.swift` & `WeekReviewModel.swift` nutzen bereits `DayBudgets` (`EnergyBudget` pro Tag, gespeicherte `DayHealthRecord`s für vergangene Tage, `GoalPlan` pro Tag).
  - `WeekReviewView.swift` zeigt bereits `caloriesSection` (mit `GoalBars` gegen tägliche Budget-Striche), `nutrientsSection` (Ballaststoffe, Zucker, optional gesättigte Fettsäuren, Salz), Wasser, Training, Schritte, Eiweiß (nur wenn `proteinGrams != nil`), Erledigt, `GoalPlanningEntries(offer: .reviewOnly)`, `EffortReviewSection` und `WeekReflectionSections`.
- **Noch fehlend (Kern von #320):**
  1. **Budget-Trefferquote bei Kalorien:** `WeekReview` berechnet noch nicht `daysWithinBudget` („Im Budget an X von Y Tagen“, laut OR4b: *„Ein Tag gilt als ‚im Budget‘, wenn das Gegessene das Budget dieses Tages nicht übersteigt“*).
  2. **Gewicht im Wochenrückblick (komplett fehlend):** `WeekReviewModel` kennt keinen `WeightStore`; `WeekReview` hat keine Gewichtsfelder. Es fehlen 7-Tage-Mittel (am Ende der betrachteten Woche), 28-Tage-Trend in kg/Woche (via `WeightTrend`), Anzahl Wiegetage, Abstand zum Zielgewicht und (wenn `settings.bodyFatEnabled`) Körperfett-Mittel.
  3. **Makronährstoffe (Kohlenhydrate & Fett) + Eiweiß-Darstellung:** Kohlenhydrate und Fett fehlen komplett im Wochenrückblick; Eiweiß erscheint isoliert als eigene Section weiter unten und verschwindet ganz, wenn kein Eiweiß-Ziel aktiv ist.
  4. **`WeekReview.isEmpty`:** Eine Woche mit nur Gewichtsmessungen würde aktuell fälschlich „In dieser Woche wurde nichts erfasst.“ anzeigen.
  5. **`WeekReviewPagePreview`:** Muss beim Wischen zwischen Wochen den neuen Abschnitt konsistent mitanzeigen.

### Scope
- **In Scope:**
  - `WeekReview` (in `TagwerkCore`) erweitern um:
    - `daysWithinBudget: Int` (Anzahl Tage mit Mahlzeiten/fremder Ernährung, an denen `kcal <= Double(goalKcal)`).
    - `averageCarbs: Double?`, `averageFat: Double?`, `averageProtein: Double?` (unabhängig davon, ob ein Eiweiß-Ziel gesetzt ist; Ziel-Vergleich optional anzeigen).
    - `weight: WeekReview.WeightSummary?` (Messungstage in der Woche, Wochenmittel bzw. 7-Tage-Mittel am Stichtag `min(weekEnd, today)`, 28-Tage-Trend in kg/Woche via `WeightTrend.trendPerWeek`, Zielgewicht aus dem Zielstand am Stichtag, optionales Körperfett-Mittel).
  - `WeekReviewModel` um `WeightStore` erweitern (mit 35 Tagen Vorlauf vor `weekEnd`, damit `WeightTrend.trendPerWeek` für jede vergangene Woche exakt über 28+7 Tage rechnen kann).
  - `AppEnvironment.makeWeekReviewModel()` um `weights: capture.weights` erweitern.
  - `WeekReviewView` um Kalorien-Budget-Quote, vereinheitlichte Makro-/Nährwerte-Übersicht und neuen Abschnitt **„Gewicht“** (mit Link zu „Verlauf und Ziele“) ergänzen.
- **Out of Scope:**
  - Änderungen an `PlanHeader` oder `TagwerkWidget` (diese nutzen bereits `DayBudgets` / `EnergyBudget`).
  - Eigene Gewichts-Eingabe direkt im Wochenrückblick (bleibt in „Erfassen“ und Tagesstart).
  - Neue Health-Berechtigungsabfrage im Wochenrückblick (liest fremde Gewichte nur, wenn Gruppe `.body` bereits angefragt wurde – genau wie bei Schritten und Trainings).

### UX, Varianten und Zustände (deutscher Copy)
Mockup: [`mockup-320-weekly-review.html`](mockup-320-weekly-review.html)

- **Gewicht-Abschnitt (Design-Entscheidung Variante A vs. B):**
  - **Variante A (empfohlen):** Kompakte Kennzahlen-Sektion **„Gewicht“** mit `LabeledContent`-Zeilen: *7-Tage-Mittel* (`81,4 kg · 5 Messungen`), *Trend (4 Wochen)* (`−0,4 kg/Woche`, farblich neutral/grün bei Annäherung ans Ziel, orange bei > Limit `GoalGuardConstants`), optional *Körperfett* (`18,2 %`), *Ziel* (`78,0 kg · noch 3,4 kg`) und Navigationszeile *„Verlauf und Ziele öffnen“*.
  - **Variante B:** Zusätzlich eine kompakte 7-Tage-Sparkline (Messpunkte + 7-Tage-Mittel-Linie) direkt über den Kennzahlen in der Sektion.
- **Nährwerte & Makros (Design-Entscheidung Variante A vs. B):**
  - **Variante A (empfohlen):** Eine gebündelte Sektion **„Ernährung & Nährwerte“** direkt unter Kalorien: oben die 3 Makros (Eiweiß, Kohlenhydrate, Fett als `Ø ~132 g / 140 g` bzw. ohne Ziel `Ø ~218 g`), darunter Ballaststoffe, Zucker und (wenn aktiviert) gesättigte Fettsäuren & Salz – jeweils mit `an X Tagen`. Die separate untere Eiweiß-Sektion entfällt.
  - **Variante B:** Bestehende getrennte Sektionen beibehalten (Eiweiß unten, Makros ergänzen) – länger, weniger übersichtlich.
- **Alle Zustände mit deutschem Copy:**
  1. **Standard (vollständige Daten):**
     - Kalorien-Kopf: *„Ø ~2.180 kcal an 6 Tagen · Im Budget an 5 von 6 Tagen“*.
     - Gewicht: *„7-Tage-Mittel: 81,4 kg (5 Messungen)“*, *„Trend: −0,4 kg/Woche“*, Fußtext: *„7-Tage-Mittel am Ende der Woche; Trend vergleicht mit dem Stand 4 Wochen davor. Eigene Einträge und Messungen aus Health.“*
  2. **Wenige Gewichtsmessungen (< 3 in 7 Tagen oder keine Daten 4 Wochen zuvor):**
     - < 3 Messungen in der Woche, aber mind. 1 Messung: *„Wochenmittel: 81,6 kg (2 Messungen) · 7-Tage-Mittel ab 3 Tagen“*, *„Trend: –“*.
     - Genug für 7-Tage-Mittel, aber kein 28-Tage-Vergleich: *„Trend: – (ab 4 Wochen Verlauf)“*.
  3. **Keine Gewichtsmessungen in der Woche (oder Health-Lesen verweigert/still):**
     - Kein Fehlerbanner (iOS meldet verweigertes Lesen nicht). Zeile: *„Keine Messungen in dieser Woche“* (in `.secondaryText`) + dezenter Link *„Verlauf und Ziele“*.
  4. **Laden (initial / Wochenwechsel):** Bestehendes `PagedContainer`-Muster; lokale Daten (Mahlzeiten, eigene Gewichte, gespeicherte `DayHealthRecord`s) erscheinen sofort, Health-Werte und geschlossene GitHub-Issues aktualisieren nach.
  5. **Aktuelle Woche:** Sektions-Header tragen wie bisher rechts das Label *„bisher“*; Budget-Tage und Gewichts-Stichtag rechnen bis `today`, nicht bis Sonntag.
  6. **Leere Woche (weder Essen, Wasser, Training, Aufgaben noch Gewicht):** Bestehende Meldung *„In dieser Woche wurde nichts erfasst.“*

### Daten & Architektur
- **Zu erweiternde Dateien:**
  - `app/Packages/TagwerkCore/Sources/TagwerkCore/WeekReview.swift`:
    - `WeekReview.WeightSummary`: `measurementDays: Int`, `weekMeanKg: Double?`, `sevenDayMeanKg: Double?`, `trendPerWeekKg: Double?`, `targetKg: Double?`, `averageBodyFatPercent: Double?`, `exceedsLossLimit: Bool`.
    - `WeekReview.Day`: zusätzlich `carbs: Double?`, `fat: Double?`.
    - `WeekReview`: zusätzlich `daysWithinBudget: Int`, `averageCarbs: Double?`, `averageFat: Double?`, `weight: WeightSummary?`.
    - `WeekReview.make(...)` bekommt optionalen Parameter `weightDays: [PlanDay: DayWeight] = [:]` (abwärtskompatibel für bestehende Tests!).
    - `isEmpty` prüft zusätzlich `(weight?.measurementDays ?? 0) == 0`.
  - `app/Tagwerk/Capture/WeekReviewModel.swift`:
    - Optionales `weights: WeightStore? = nil` im Initializer.
    - In `reload()`: `let referenceDay = min(requested.adding(days: 6, calendar: calendar), today)`; lädt Gewichte für `[referenceDay - 35 Tage ... referenceDay + 1 Tag]` über `weights.dayValues(in:)` und übergibt sie an `WeekReview.make(...)`.
  - `app/Tagwerk/Capture/WeekReviewView.swift`:
    - `caloriesSection`: Budget-Quote ergänzen (`Im Budget an X von Y Tagen`).
    - `nutrientsSection`: Makros (Eiweiß, Kohlenhydrate, Fett) + weitere Nährwerte zusammenführen; isolierte alte Eiweiß-Sektion entfernen.
    - Neue `weightSection(_ review:)` mit VoiceOver-Zusammenfassung (nutzt `WeightFormat` aus `TagwerkCore`) und Navigation/Link zu `TrendView`.
  - `app/Tagwerk/App/AppEnvironment.swift`: `makeWeekReviewModel()` übergibt `weights: capture.weights`.

### Implementierungsschritte (kleine Commits + Tests)
1. **Commit 1:** `feat: compute budget hit rate, macros and weight summary in WeekReview`
   - Erweiterung von `WeekReview.swift` (`daysWithinBudget`, `averageCarbs`, `averageFat`, `WeightSummary`, `isEmpty`).
   - Unit-Tests (`WeekReviewTests` in `TagwerkCoreTests`): `daysWithinBudget_countsDaysAtOrBelowDailyBudget`, `daysWithinBudget_usesHistoricalPlanAndActivity`, `weightSummary_computesSevenDayMeanAnd28DayTrendAtWeekEnd`, `weightSummary_fewerThanThreeDays_noSevenDayMean`, `weightSummary_pastWeek_doesNotUseFutureMeasurements`, `isEmpty_falseWhenOnlyWeightRecorded`.
2. **Commit 2:** `feat: load weight history in WeekReviewModel`
   - `WeekReviewModel.swift` + `AppEnvironment.swift` (`WeightStore` verdrahten, 35-Tage-Vorlauf für Trend).
   - Unit-Tests (`WeekReviewModelTests`): `reload_loadsWeightTrendForPastWeek`, `reload_withoutHealthBodyAccess_usesOwnWeightsOnly`.
3. **Commit 3:** `feat: display budget hit rate, macros and weight in WeekReviewView`
   - UI-Update in `WeekReviewView.swift`, `Localizable.xcstrings` + `en.json`.
   - UI-Tests (`WeekReviewUITests` + Barrierefreiheits-Audit inkl. AX5): `weekReview_showsBudgetCountAndWeightTrend`, `weekReview_emptyWeightWeek_showsPlaceholder`.

### Risiken & Gegenmaßnahmen
- **Stichtag bei vergangenen Wochen:** `WeightTrend.trendPerWeek` darf im Wochenrückblick niemals `today` als Referenz nehmen, sondern immer `min(weekEnd, today)` – sonst zeigt eine Woche im Oktober den Trend von heute. Wird per Unit-Test abgesichert.
- **Makro-Ziele variieren pro Tag (BU3c):** Da Kohlenhydrat- und Fett-Ziele täglich mit der angerechneten Aktivität skalieren, zeigt der Wochenrückblick bei Makros das Wochenmittel (und beim Eiweiß das feste Ziel aus `goalPlan.proteinGrams`, bei KH/Fett das mittlere skalierte Tagesbudget oder nur den Durchschnitt ohne irreführende Einzelzahl).
- **Dynamic Type AX5:** `LabeledContent` mit langen Werten (`Ø ~132 g / 140 g an 6 Tagen`) bricht bei AX5 automatisch vertikal um, wenn `.lineLimit(nil)` gilt und kein starres `HStack` verwendet wird.

### Offene Fragen an den Owner (#320)
1. **Gewichtsdarstellung (Variante A vs. B):** Genügt im Wochenrückblick die kompakte Kennzahlen-Sektion (7-Tage-Mittel, Trend, Zielabstand + Link zu „Verlauf und Ziele“, **Empfehlung: A**), oder soll zusätzlich eine 7-Tage-Sparkline direkt im Wochenrückblick erscheinen (**B**)?
2. **Nährwerte-Struktur (Variante A vs. B):** Sollen Eiweiß, Kohlenhydrate und Fett zusammen mit Ballaststoffen/Zucker in einer gebündelten Sektion „Nährwerte“ stehen (**Empfehlung: A**, ersetzt die separate Eiweiß-Sektion), oder soll Eiweiß als eigene Sektion bleiben (**B**)?
3. **Gewicht ohne Messungen in der Woche:** Soll der Abschnitt „Gewicht“ in einer Woche ohne Messungen trotzdem mit *„Keine Messungen in dieser Woche“* sichtbar bleiben (**Empfehlung: A**, analog zu Kalorien/Wasser) oder komplett ausgeblendet werden (**B**)?

---

## Issue #331: Suchfunktion für Einstellungen und Repositories/Projects (v. a. bei Issue-Erstellung)

> **Hinweis zum Issue:** #331 hat keinen Body – nur den Titel *„Suchfunktion für Einstellungen und repositories/projects (v. a. auch bei der Erstellung von issues) hinzufügen oder diese in der bisherigen Suche integrieren“*. Der folgende Plan leitet den Scope vollständig aus dem Titel und der Codebasis ab und benennt die offenen Entscheidungen explizit.

### Ausgangslage im Code
1. **Issue-Erstellung & GitHub-Auswahl (Schmerzpunkt im Titel explizit hervorgehoben):**
   - `app/Tagwerk/Tasks/NewTaskSheet.swift` (Zeilen 125–130):
     - `Picker("Repository", selection: $repository)` ist ein unfilterbares Standard-Menü über alle `catalog?.repositories`.
     - `ProjectSelectionRow` (`app/Tagwerk/Tasks/ProjectSelection.swift`) ist ein `Menu` mit `Toggle`s über alle `catalog?.projects` – ohne Suchfeld.
   - Dieselbe Auswahl existiert zusätzlich an zwei weiteren Stellen:
     - `app/Tagwerk/Routines/IssueTargetSheet.swift` (Zeile 129, Gedanken-Notiz → GitHub-Issue).
     - `app/Tagwerk/AI/TaskProposalEditor.swift` (Zeile 297, KI-Vorschlag „Anpassen“ für neues Issue).
2. **Einstellungen & Quellenauswahl:**
   - `app/Tagwerk/Settings/SettingsView.swift`: ~16 Sektionen und über 15 Unterseiten (`PlanningSettingsSection`, `GitHubSettingsSection`, `AISettingsView`, `CaptureSettingsView`, `RoutineSettingsView`, `NotesSettingsView`, `BackupSettingsView`, `FocusSettingsView`, `SiriShortcutsSettingsView`, `LanguageSettingsView`, `ReminderDefaultsView`, `QuietHoursSettingsView`, etc.) – **keine Suchfunktion**.
   - `app/Tagwerk/Settings/SourceSelectionView.swift`: Mehrfachauswahl-Liste für GitHub-Projekte (`GitHubSettingsSection`), Kalender, Erinnerungslisten und Deadline-Kalender – **kein `.searchable`**.
   - `app/Tagwerk/Settings/SettingsDestination.swift`: Bisher nur 6 Destinations (`languages`, `ai`, `aiVoice`, `capture`, `shopping`, `siri`) für programmatische Navigation.
3. **Globale Suche (`SearchSheet`):**
   - `app/Tagwerk/Search/SearchSheet.swift`, `SearchModel.swift`, `app/Packages/TagwerkCore/Sources/TagwerkCore/Search/SearchResults.swift`:
     - Durchsucht aktuell Termine, offene/erledigte Aufgaben, Online-GitHub-Issues, Notizen und Einkaufsliste.
     - Filter-Chips: `Alle`, `Termine`, `Aufgaben`, plus Toggle `✓ Erledigte`.
     - Sucht **nicht** nach Einstellungen und **nicht** nach GitHub-Repositories/-Projekten.

### Scope
- **In Scope (Kern + empfohlene Integration):**
  1. **Durchsuchbare Repository- & Projekt-Auswahl bei der Issue-Erstellung** (wiederverwendbare Komponenten für `NewTaskSheet`, `IssueTargetSheet`, `TaskProposalEditor`):
     - `RepositoryPickerSheet` / `SearchableRepositoryPicker`: Durchsuchbare Liste aller `catalog.repositories`, mit Suche nach Owner und Repo-Name (Token-Suche über `SearchQuery` / `SearchText.fold`), aktuellem Treffer oben und optionalem Abschnitt „Zuletzt verwendet“.
     - `ProjectPickerSheet` / `SearchableProjectPicker`: Durchsuchbare Mehrfachauswahl aller `catalog.projects`, inkl. Option „Kein Projekt“, hervorgehobenen „Mit Repository verknüpft“-Projekten und Zähler-Badge.
  2. **Suche in `SourceSelectionView` (Einstellungen › GitHub › Projekte, Kalender, Erinnerungslisten):**
     - Natives `.searchable(text:prompt:)` ab z. B. ≥ 6 Einträgen (oder immer sichtbar), filtert live nach Titel, behält Auswahl-Checkmarks und `lockedIDs` bei.
  3. **Suche für Einstellungen (zweistufig – siehe Varianten A/B):**
     - Statischer, lokalisierter `SettingsSearchIndex` in `TagwerkCore` (Eintrag: Titel, Pfad z. B. *„Einstellungen › Erfassen“*, Schlüsselwörter/Synonyme wie *„Open Food Facts“*, *„Ruhezeiten“*, *„Puffer“*, *„Health“*, *„Strichcode“*, *„Backup“*, Ziel-`SettingsTarget`).
     - Direktes `.searchable` in `SettingsView` **und** (empfohlen) Integration als neue Sektion **„Einstellungen“** in die globale `SearchSheet` (mit Sprung in Tab 2 + `settingsPath`).
  4. **Optionale Integration von Repositories & Projekten in die globale `SearchSheet`:**
     - Lokales Durchsuchen der bereits geladenen/gecachten Repositories & Projekte (`GitHubCatalog`) als eigene Sektion **„Repositories & Projekte“** (nur wenn GitHub aktiv) mit Aktionen: *„Neues Issue hier anlegen“* (öffnet `NewTaskSheet` vorausgefüllt!) oder *„In Aufgaben filtern“* / *„Auf GitHub öffnen“*.
- **Out of Scope:**
  - Online-Suche über fremde öffentliche GitHub-Repositories (nur der eigene `GitHubCatalog` des angemeldeten Nutzers).
  - Volltextsuche innerhalb von Hilfe-Texten oder externen iOS-Systemeinstellungen.

### UX, Varianten und Zustände (deutscher Copy)
Mockup: [`mockup-331-search.html`](mockup-331-search.html)

- **Design-Entscheidung 1 — Ort der Einstellungssuche (Variante A vs. B):**
  - **Variante A (empfohlen):** **Beides (Hybrid):** Natives `.searchable(prompt: "Einstellungen durchsuchen")` direkt in `SettingsView` **plus** Integration als Sektion „Einstellungen“ (und optional „Repositories & Projekte“) in der globalen `SearchSheet` (neuer Filter-Chip `Einstellungen` oder sichtbar unter `Alle`). Vorteil: Wer schon in den Einstellungen ist, findet es sofort; wer über die globale Lupe sucht, ebenso.
  - **Variante B:** Nur Integration in die bestehende globale `SearchSheet` (keine eigene Suchleiste in `SettingsView`). Schlanker in `SettingsView`, aber Nutzer im Tab „Einstellungen“ erwarten dort eine Suchleiste (iOS-Standard).
- **Design-Entscheidung 2 — Repo-/Projekt-Auswahl in `NewTaskSheet` (Variante A vs. B):**
  - **Variante A (empfohlen):** Tippen auf die Zeile „Repository“ bzw. „Projekte“ öffnet ein **durchsuchbares Sheet** (`.large` mit Fokus im Suchfeld, `Abbrechen`/`Fertig`, konsistent mit `FoodPickerSheet` und `SearchSheet`).
  - **Variante B:** Push-Navigation innerhalb der `NavigationStack` von `NewTaskSheet` (mit `.searchable` in der Navigationsleiste). Spart eine Sheet-Ebene, ist aber bei `TaskProposalEditor` / `IssueTargetSheet` weniger einheitlich.
- **Alle Zustände mit deutschem Copy:**
  1. **Repo-Picker (gefüllt):** Suchfeld *„Repository suchen“*, Abschnitt *„Zuletzt verwendet“* (max. 3), Abschnitt *„Alle Repositories (24)“* mit Owner/Name (`melvinmng/tagwerk`), Haken am gewählten Repo.
  2. **Projekt-Picker (Mehrfachauswahl):** Suchfeld *„Projekt suchen“*, Zeile *„Kein Projekt“*, Abschnitt *„Verknüpft mit tagwerk“* (vorausgewählt), Abschnitt *„Alle Projekte“* mit Checkmarks, Toolbar `Fertig` (zeigt Auswahlzähler).
  3. **Laden (Katalog noch nicht da):** Zeile in `NewTaskSheet` zeigt `ProgressView` + *„Repositories werden geladen …“*; im Picker-Sheet zentrierter `ProgressView`.
  4. **Leer / Keine Treffer:** `ContentUnavailableView.search(text: query)` → *„Kein Repository für ‚xyz‘ gefunden.“* / *„Keine Einstellung für ‚xyz‘ gefunden.“*
  5. **Fehler / Offline:** Wenn `catalog == nil` und GitHub offline: Hinweisbanner *„Repositories konnten nicht geladen werden. Prüfe deine Verbindung oder versuch es erneut.“* + Button *„Erneut laden“*. Bei vorhandenem Cache funktioniert die Suche komplett offline!
  6. **GitHub nicht angemeldet:** In der globalen Suche erscheint die Sektion „Repositories & Projekte“ nicht; in `SettingsView` findet die Suche nach „GitHub“ den Eintrag *„GitHub · Anmelden“*.

### Daten & Architektur
- **Neue Dateien:**
  - `app/Packages/TagwerkCore/Sources/TagwerkCore/Search/SettingsSearchIndex.swift`: `SettingsSearchItem` (`id`, `title`, `sectionPath`, `keywords: [String]`, `destinationID: String`, `symbol: String`) + `SettingsSearchIndex.matching(_:query:)` über bestehendes `SearchQuery` / `SearchText.fold`.
  - `app/Tagwerk/Tasks/GitHubTargetPickers.swift`: `RepositoryPickerRow` + `RepositoryPickerSheet`, sowie Erweiterung/Ablösung von `ProjectSelectionRow` durch `ProjectPickerSheet` (gleiche `ProjectSelection`-Regeln für `preselect`, `value(titles:)`, `commonStatusOptions` bleiben unverändert!).
- **Zu erweiternde Dateien:**
  - `app/Tagwerk/Settings/SettingsDestination.swift`: Vollständige Abdeckung aller Unterseiten (`planning`, `calendars`, `reminderLists`, `githubProjects`, `routines`, `notes`, `backup`, `focus`, `reminderDefaults`, `quietHours`, `access`, `travel`, `mergeRules`, `calendarDiagnostics` zusätzlich zu den 6 bestehenden).
  - `app/Tagwerk/Settings/SettingsView.swift`: `.searchable` + Trefferliste bei aktivem Suchtext (ersetzt das `Form` während der Suche, Tippen navigiert direkt zur Unterseite oder scrollt via `ScrollViewReader` zur Inline-Sektion wie *Mittagspause* / *Puffer* / *Benachrichtigungen* / *Zugriff*).
  - `app/Tagwerk/Settings/SourceSelectionView.swift`: `.searchable(text: $searchText, prompt: "Suchen")` + Filterung der `items` über `SearchText.fold`.
  - `app/Tagwerk/Tasks/NewTaskSheet.swift`, `app/Tagwerk/Routines/IssueTargetSheet.swift`, `app/Tagwerk/AI/TaskProposalEditor.swift`: Umstellung auf `RepositoryPickerRow` und durchsuchbare `ProjectSelectionRow`. Optional: `NewTaskSheet` um `prefilledRepository: String?` und `prefilledProjectIDs: Set<String>` erweitern (für Sprung aus der globalen Suche).
  - `app/Packages/TagwerkCore/Sources/TagwerkCore/Search/SearchResults.swift` + `app/Tagwerk/Search/SearchModel.swift` + `app/Tagwerk/Search/SearchSheet.swift` + `app/Tagwerk/Search/SearchRows.swift` + `app/Tagwerk/Search/SearchTexts.swift` + `app/Tagwerk/App/RootView.swift`:
    - Neue `SearchSectionKind`-Fälle `.settings` und (optional) `.projects` (Repositories & Projekte).
    - Callback `onOpenSettings: (SettingsDestination) -> Void` und `onCreateIssueIn: (String?, [String]) -> Void` in `SearchSheet` / `RootView`.

### Implementierungsschritte (kleine Commits + Tests)
1. **Commit 1:** `feat: add searchable repository and project pickers for issue creation`
   - `GitHubTargetPickers.swift`, Integration in `NewTaskSheet.swift`, `IssueTargetSheet.swift`, `TaskProposalEditor.swift`.
   - Unit-Tests (`GitHubTargetPickersTests` / `ProjectSelectionTests`): Filterung nach Owner/Name, Groß-/Kleinschreibung, Umlaute, „Verknüpfte Projekte“ oben, Mehrfachauswahl + „Kein Projekt“.
2. **Commit 2:** `feat: make SourceSelectionView searchable`
   - `.searchable` in `SourceSelectionView.swift` (deckt GitHub-Projekte, Kalender, Erinnerungslisten, Deadline-Kalender in den Einstellungen ab).
   - Unit-Tests für Filterlogik + UI-Test in Einstellungen › GitHub › Projekte.
3. **Commit 3:** `feat: add SettingsSearchIndex and searchable SettingsView`
   - `SettingsSearchIndex.swift` in `TagwerkCore`, vollständige `SettingsDestination`, `.searchable` + `ScrollViewReader` in `SettingsView.swift`.
   - Unit-Tests (`SettingsSearchIndexTests`): Vollständigkeit gegen alle `SettingsDestination`-Fälle, Treffer über Titel & Synonyme (z. B. „Open Food Facts“ → Erfassen, „Pomodoro“ → Fokus-Timer), leere Query.
4. **Commit 4:** `feat: integrate settings and repositories/projects into global SearchSheet`
   - Erweiterung von `SearchResults.swift`, `SearchModel.swift`, `SearchSheet.swift`, `SearchRows.swift`, `RootView.swift`.
   - Unit-Tests (`SearchResultsTests`, `SearchModelTests`) + UI-Tests (`SearchUITests` + Barrierefreiheits-Audit).

### Risiken & Gegenmaßnahmen
- **Drift im `SettingsSearchIndex`:** Wenn später neue Einstellungen hinzukommen, könnten sie im Index fehlen. Ein Unit-Test prüft, dass jeder `SettingsDestination`-Case mindestens einen Eintrag im Index hat.
- **Lokalisierte Synonyme (DE & EN):** Suchbegriffe müssen in beiden App-Sprachen funktionieren (`String(localized:)` für Titel und Schlüsselwort-Listen im Katalog).
- **Verhalten bei wenigen Einträgen:** Wenn ein Nutzer nur 2 Repositories hat, darf der durchsuchbare Picker nicht umständlicher sein als ein Menü – die Liste öffnet direkt mit allen Einträgen sichtbar, Tippen auf einen Eintrag wählt sofort aus und schließt das Sheet (1 Tipp wie beim `Picker`).

### Offene Fragen an den Owner (#331)
1. **Wo soll nach Einstellungen gesucht werden (Variante A vs. B)?** Direkt im Tab „Einstellungen“ (`.searchable`) **und** in der globalen Suche (**Empfehlung: A**), oder nur in der globalen Suche (**B**)?
2. **Repositories & Projekte in der globalen Suche:** Sollen GitHub-Repositories und -Projekte auch in der globalen `SearchSheet` erscheinen (mit Aktion „Neues Issue anlegen“ / „Auf GitHub öffnen“, **Empfehlung: A**) oder reicht die Suche in den Pickern bei der Issue-Erstellung und in `SourceSelectionView` (**B**)?
3. **Darstellung der Repo-/Projekt-Auswahl in `NewTaskSheet` (Variante A vs. B):** Durchsuchbares Modal-Sheet (**Empfehlung: A**, einheitlich mit `FoodPickerSheet` und auch in `IssueTargetSheet`/`TaskProposalEditor` identisch nutzbar) oder Push-Navigation in der `NavigationStack` (**B**)?
4. **„Zuletzt verwendet“-Sortierung bei Repositories:** Soll Tagwerk die 3 zuletzt für neue Issues gewählten Repositories oben im Picker anpinnen (**Empfehlung: Ja**), oder rein alphabetisch sortieren?

---

## Issue #332: Projektfortschritt: Übersicht über alle Projekte und Verlauf/Trend pro Projekt

### Ausgangslage im Code & ehrliche Datenlage
Der Issue-Body fordert **zwei Ebenen** (Global oberflächlich + Pro Projekt sehr detailliert) und stellt 3 offene Fragen. Ein genauer Blick in den Code zeigt, was heute real vorhanden ist und wo Lücken liegen:

| Datenpunkt aus #332 | Heute im Code vorhanden? | Konkreter Fundort / Lücke |
|---|---|---|
| Offene GitHub-Issues je Projekt/Repo | **Teilweise** | `GitHubTaskProvider` lädt aktuell nur *dir zugewiesene offene Issues* (`assignedIssues` in `ProjectsQuery.swift`). Nicht-zugewiesene Issues oder die Gesamtzahl eines Projekts fehlen. |
| Erledigte / geschlossene Aufgaben je Zeitraum | **Ja (für zugewiesene)** | `ClosedIssues.swift` (`closedIssues(assignedTo:closedSince:closedUntil:)`), `CompletedTask` für lokale Aufgaben & Erinnerungen (`SearchSources.completedTasks`). |
| Erstellungsdatum (`createdAt`) | **Fehlt bei GitHub** | `ProjectsQuery.issueSelection` liest `updatedAt`, aber noch kein `createdAt`. Bei lokalen Aufgaben/Erinnerungen vorhanden bzw. leicht ergänzbar. |
| „Verschoben“ / Statuswechsel-Verlauf | **Fehlt überall** | Weder Apple Erinnerungen noch `ProjectsQuery` liefern eine Änderungshistorie. Müsste für Tagwerk-Aktionen ab Aktivierung über ein lokales Protokoll (`TaskActivityRecord` in SwiftData) erfasst werden. |
| Eingeplante vs. investierte Zeit | **Teilweise** | Schätzung (`estimateMinutes`) auf `TaskItem`, geplante Zeitblöcke in `PlanningModel` (`CalendarEvent` mit `tagwerk://task/…`), gemessene Fokus-Zeit in `EffortStats` / Fokus-Store. Verknüpfung auf Projekt-Ebene neu. |
| Offene Punkte, Blocker, Fristen | **Ja** | `TaskItem.due`, `TaskItem.priority`, `TaskItem.statuses` (z. B. Status *„Blocked“* oder Label `blocked`), `TaskItem.isEpic` / `ImportantDeadline`. |
| Jira-Projekte | **Nein** | Issue #115 (*Phase 6: Jira*) steht im Backlog und ist nicht implementiert. Darf nicht vorausgesetzt werden; Architektur bleibt per Protokoll erweiterbar. |

### Scope (empfohlener realistischer 2-Stufen-Schnitt)
- **In Scope (Stufe 1 – Kern-Feature aus realen Daten):**
  - **Ebene 1 (Global, oberflächlich):**
    - Übersicht aller aktiven Projekte (Gruppierung gemäß Owner-Entscheidung; empfohlen: GitHub-Projekte + Erinnerungslisten + „Lokal“, optional filterbar nach Quelle).
    - Pro Projekt-Karte: Name + Quellen-Badge, Stand (`erledigt` im Zeitraum / `offen` gesamt), kompakter Fortschrittsbalken, Trend-Indikator (`↑ geht voran` / `→ stabil` / `↓ stockt` bzw. `Backlog wächst`), und Aktivitätsstatus (*„zuletzt bewegt vor 2 Tagen“* vs. *„ruht seit 18 Tagen“*).
    - Sortierung: *„Zuletzt bewegt“*, *„Am längsten ruhig“*, *„Meiste offene Punkte“*, *„Alphabetisch“*.
  - **Ebene 2 (Pro Projekt, detailliert):**
    - Zeitraum-Auswahl: `Woche` (4 Wochen), `Monat` (3 Monate), `Jahr` oder `Frei` (Start-/Enddatum per `DatePicker`, analog `TrendView`).
    - **Trend-Diagramm (Swift Charts):** Pro Woche/Intervall Balken für *Erledigt* (grün) vs. *Neu angelegt* (blau) + Linie für *Offener Bestand* (Netto-Entwicklung). Vollständige VoiceOver-Zusammenfassung wie in `IntakeChart` / `WeightChart`.
    - **Zeit-Auswertung:** Eingeplante Zeit (Zeitblöcke + Schätzungen offener Aufgaben) vs. tatsächlich investierte Zeit (gemessene Fokus-Sitzungen / erledigte Zeitblöcke) im gewählten Zeitraum, falls Daten vorliegen.
    - **Offene Punkte, Blocker & Fristen:** Überfällige Aufgaben, anstehende Deadlines, blockierte Einträge (Status *„Blocked“* / Label *„blocked“* / P1) mit direktem Sprung in den `TaskEditorView`.
    - **Verlauf der letzten Schritte:** Chronologische Liste der Ereignisse (*Erledigt*, *Angelegt*, *Geschlossen*, und – ab Einführung – *Status geändert* / *Verschoben* aus dem lokalen `TaskActivityRecord`). Transparente Fußzeile, ab welchem Datum lokale Verschiebungen mitgeschrieben werden.
- **Out of Scope (für später / eigene Issues):**
  - Jira-Anbindung (hängt an Backlog #115).
  - Vollständige GitHub-Timeline-API pro Issue (würde bei 50+ Issues sofort an GitHub-API-Rate-Limits scheitern).
  - KI-Analyse der Projekte im Chat (kann später sauber auf `ProjectProgressSummary` aufsetzen).
  - Team-Auswertung über andere Personen (bleibt zunächst auf eigene/zugewiesene Aufgaben fokussiert, optional per Schalter auf „Ganzes GitHub-Projekt“ erweiterbar).

### UX, Varianten und Zustände (deutscher Copy)
Mockup: [`mockup-332-project-progress.html`](mockup-332-project-progress.html)

- **Design-Entscheidung 1 — Einstieg in der App (Variante A vs. B):**
  - **Variante A (empfohlen):** Eigene Zeile **„Projektfortschritt“** (`chart.line.uptrend.xyaxis`) in `TasksEntrySection` ganz oben im Tab **„Aufgaben“** (direkt bei Einkaufsliste, Notizen, Bible Study), mit kompaktem Untertitel z. B. *„5 Projekte · 2 zuletzt bewegt, 1 ruht“*. Behält die 4-Tab-Leiste unverändert (wie OR1a in #254).
  - **Variante B:** Einstieg als eigene Karte/Zeile im Tab **„Planen“** (im Wochen-/Monatskopf bzw. Wochenrückblick). Passt thematisch zur Reflexion, ist aber weiter weg von den eigentlichen Aufgaben/Projekten.
- **Design-Entscheidung 2 — Was zählt als Projekt? (Variante A vs. B):**
  - **Variante A (empfohlen):** **Alle Aufgaben-Quellen mit Filter-Chips** (`Alle`, `GitHub`, `Erinnerungen`, `Lokal`): jedes ausgewählte GitHub-Projekt (plus Repos ohne Projekt als Gruppe), jede ausgewählte Erinnerungsliste und „Lokale Aufgaben“. Einheitsmodell, funktioniert auch ohne GitHub-Login!
  - **Variante B:** **Nur GitHub-Projekte & Repositories.** Schärferer Projektbegriff, aber für Nutzer ohne GitHub leer und ignoriert Erinnerungslisten.
- **Alle Zustände mit deutschem Copy:**
  1. **Global — Gefüllt:** Kopfbereich mit Schnell-Zusammenfassung (*„Diese Woche: 14 erledigt · 9 neu · 2 Projekte ruhen“*), Quellen-Filter-Chips, Sortier-Menü, Projektkarten mit Fortschritt, Trend-Pille (`↑ +5 netto`, `→ ausgeglichen`, `↓ +4 offen`) und letzter Bewegung (*„Heute“*, *„Vor 3 Tagen“*, *„Ruht seit 21 Tagen“* in `.orangeText`).
  2. **Global — Leer (keine Projekte/Aufgaben):** `ContentUnavailableView`: *„Noch keine Projekte“*, Text *„Verbinde GitHub-Projekte in den Einstellungen oder lege Aufgaben in Listen an, um hier deinen Fortschritt zu sehen.“*
  3. **Global — Laden / Nachladen:** Lokale Daten & Cache erscheinen sofort; während GitHub geschlossene/neue Issues lädt, dezenter Ladehinweis oben (*„GitHub-Verlauf wird aktualisiert …“*).
  4. **Global / Detail — Offline:** Gelbe/graue Statuszeile wie in `TaskListView`: *„Offline · GitHub-Stand von 14:10 Uhr. Lokale Aufgaben und Erinnerungen sind aktuell.“*
  5. **Detail — Ruhendes Projekt (keine Aktivität im Zeitraum):** Chart zeigt flache offene Bestandslinie, Hinweis: *„In den letzten 4 Wochen keine erledigten oder neuen Schritte. Letzte Bewegung: 28. Okt.“* Offene Punkte & Fristen bleiben darunter sichtbar.
  6. **Detail — Fehler (GitHub-API / Rate-Limit):** Lokaler Stand bleibt sichtbar; Banner: *„GitHub-Verlauf konnte gerade nicht geladen werden.“* + Button *„Erneut laden“*.
  7. **Detail — Keine Zeitdaten:** Abschnitt „Zeit“ zeigt *„Keine Zeitblöcke oder Fokus-Zeiten im Zeitraum“* (nie `0 h` als angebliche Messung, wenn keine Daten erfasst wurden).

### Daten & Architektur
- **Neue Dateien in `TagwerkCore` (reine, testbare Regeln):**
  - `app/Packages/TagwerkCore/Sources/TagwerkCore/ProjectProgress.swift`:
    - `ProjectKey` (`.gitHubProject(id)`, `.gitHubRepository(name)`, `.reminderList(id)`, `.local`) – vorbereitet für spätere `.jira(key)`.
    - `ProjectActivityKind` (`.created`, `.completed`, `.reopened`, `.statusChanged(from:to:)`, `.rescheduled(from:to:)`, `.closedNotPlanned`).
    - `ProjectActivityEvent` (`id`, `projectKey`, `taskID`, `title`, `kind`, `date`).
    - `ProjectTrendDirection` (`.advancing`, `.steady`, `.stalled`, `.growingBacklog`), explizite Schwellenwerte als benannte Konstanten (z. B. `stalledThresholdDays = 14`).
    - `ProjectSummary` (Stand offen/erledigt, Trend, letzte Bewegung, Blocker-/Fristen-Zähler, Zeit-Summen).
    - `ProjectTrendBucket` (Zeitintervall, `completedCount`, `createdCount`, `openCountAtEnd`, `plannedMinutes`, `actualMinutes`).
    - `ProjectProgressRules`: reine Berechnungsfunktionen für Übersicht, Trend-Buckets (Woche/Monat/Frei), offene Bestands-Rekonstruktion (rückwärts vom aktuellen offenen Bestand über `createdAt` und `completedAt`!) und VoiceOver-Zusammenfassung.
- **Erweiterung in `GitHubKit`:**
  - `app/Packages/GitHubKit/Sources/GitHubKit/ProjectsQuery.swift` & `GitHubIssueRecord.swift`: `createdAt` (optional, rückwärtsverträglich für alten Cache) in `issueSelection` und `GitHubIssueRecord` ergänzen.
  - `app/Packages/GitHubKit/Sources/GitHubKit/ClosedIssues.swift`: `ClosedIssue` um `title: String`, `number: Int`, `repository: String`, `createdAt: Date?` ergänzen (nur 4 kleine Felder in derselben GraphQL-Query, keine zusätzlichen Requests!).
- **Persistenz & Lokales Aktivitätslog (SwiftData):**
  - `app/Tagwerk/Persistence/TaskActivityRecord.swift` & `TaskActivityStore.swift`: Schreibt Ereignisse lokal mit, wenn der Nutzer in Tagwerk Aufgaben anlegt, erledigt, wieder öffnet, verschiebt (`PlanningModel.assign`) oder den Status ändert (`TaskEditorView`).
  - Registrierung in `ModelContainerFactory.schema` + Eintrag in `BackupDTOs.swift` / `BackupService.swift` / `BackupCoverage.swift` (Vollständigkeitstest bleibt grün!).
- **UI & Models in `app/Tagwerk/Projects/` (neuer Ordner):**
  - `ProjectProgressModel.swift` (`@MainActor @Observable`): Aggregiert `TaskListModel`, `GitHubTaskProvider`, `ReminderStore`, `LocalTaskStore`, `PlanningModel` (Zeitblöcke), Fokus-/Aufwandsdaten (`EffortStats`-Quelle) und `TaskActivityStore`. Lädt GitHub-Verlauf lazy & mit 5-Minuten-In-Memory-Cache (Rate-Limit-Schutz).
  - `ProjectProgressListView.swift`: Ebene 1 (Globale Übersicht).
  - `ProjectDetailView.swift`: Ebene 2 (Detailansicht mit Zeitraum-Picker, Kennzahlen, `ProjectTrendChart`, Zeit-Karte, Blocker/Fristen, Aktivitätsverlauf).
  - `ProjectTrendChart.swift`: Swift Charts (Balken erledigt/neu + Linie offener Bestand, mit Accessibility-Summary).
  - Erweiterung `TasksEntrySection.swift` & `TasksDestination.swift` & `TaskListView.swift`: Neuer Einstieg `.projects` und `.projectDetail(ProjectKey)`.

### Implementierungsschritte (kleine Commits, aufteilbar in 2–3 PRs)
- **PR 1 — Grundlagen & Globale Übersicht (~8–10 h):**
  1. `feat: add ProjectProgress domain rules and trend calculations` (`TagwerkCore` + `ProjectProgressRulesTests`: Bestands-Rekonstruktion, Trend-Klassifikation, Ruhend-Erkennung, leere Zeiträume, VoiceOver-Texte).
  2. `feat: read issue createdAt and metadata in GitHubKit for project history` (`ProjectsQuery`, `GitHubIssueRecord`, `ClosedIssues` + `GitHubKitTests`, Cache-Rückwärtskompatibilität).
  3. `feat: add global project progress overview in Tasks tab` (`ProjectProgressModel`, `ProjectProgressListView`, `TasksEntrySection`, `TasksDestination` + Unit- & UI-Tests).
- **PR 2 — Detailansicht, Trend-Diagramm & Zeitvergleich (~7–10 h):**
  4. `feat: add Swift Charts trend view and period selector for projects` (`ProjectTrendChart`, `ProjectDetailView` mit Woche/Monat/3 Monate/Frei, Blocker & Fristen + `ProjectProgressModelTests`).
  5. `feat: compute planned vs actual time per project` (Verknüpfung Zeitblöcke & Fokus-Aufwand je `ProjectKey` + Tests).
- **PR 3 — Lokales Aktivitätsprotokoll für Verschiebungen & Statuswechsel (~4–6 h):**
  6. `feat: record local task activity events and include in backup` (`TaskActivityRecord`, `TaskActivityStore`, Hooks in `TaskListModel`/`PlanningModel`, `BackupDTOs`/`BackupCoverage` + Backup-Roundtrip-Tests).
  7. `test: add UI and accessibility tests for project progress` (`ProjectProgressUITests` inkl. AX5 & Dark Mode).

### Risiken & Gegenmaßnahmen
- **GitHub-API-Rate-Limits (30 Search-Requests/min):** Pro Detail-Abruf max. 1–3 Seiten wie in `ClosedIssues.closedIssuesMaxPages`, Ergebnis im Speicher cachen, erst bei explizitem Pull-to-Refresh neu laden.
- **Unvollständige Historie vor Einführung:** Rückwirkend sind nur `createdAt` und `closedAt`/`completedAt` bekannt; Verschiebungen und Statuswechsel erst ab Einführung des lokalen `TaskActivityRecord`. Ein ehrlicher Fußtext im Verlauf erklärt das, statt falsche Vollständigkeit vorzutäuschen.
- **Offener Bestand rückwärts gerechnet:** `open(t - 1) = open(t) - created(t) + closed(t)` ist eine saubere Näherung; wenn Issues das Projekt gewechselt haben, kann es kleine Abweichungen geben. Wird als „Verlauf des offenen Bestands“ mit klarem Tooltip/Fußtext dokumentiert.
- **SwiftData & Backup-Test:** Jedes neue `@Model` (`TaskActivityRecord`) muss zwingend in `ModelContainerFactory.schema` und `BackupCoverage` eingetragen werden, sonst schlägt der bestehende Vollständigkeitstest fehl.

### Offene Fragen an den Owner (#332)
1. **Was zählt als Projekt (Variante A vs. B)?** Alle Quellen (GitHub-Projekte, Repos ohne Projekt, Erinnerungslisten, Lokale Aufgaben) mit Quellen-Filter (**Empfehlung: A**), oder ausschließlich GitHub-Projekte & Repositories (**B**)? *(Hinweis: Jira #115 ist noch im Backlog und wird erst mit Phase 6 angebunden.)*
2. **Einstieg in der App (Variante A vs. B):** Neue Zeile „Projektfortschritt“ oben im Tab **Aufgaben** (`TasksEntrySection`, **Empfehlung: A**), oder Abschnitt im Tab **Planen** / Wochenrückblick (**B**)?
3. **Auswählbare Zeiträume:** Reichen die Voreinstellungen `4 Wochen`, `3 Monate`, `1 Jahr` plus `Frei` (Start-/Enddatum) (**Empfehlung: A**), oder zusätzlich `Diese Woche` (7 Tage tagesgenau) (**B**)?
4. **Umfang bei GitHub-Projekten:** Sollen im Projektfortschritt nur **dir zugewiesene** Issues zählen (konsistent mit dem Rest von Tagwerk, **Empfehlung: A** für Stufe 1), oder **alle** Issues eines GitHub-Projekts inkl. fremder Assignees (**B**, erfordert zusätzliche GraphQL-Projekt-Item-Query)?
5. **Ruhend-Schwelle:** Ab wie vielen Tagen ohne Bewegung gilt ein Projekt als „ruht“? Vorschlag: **14 Tage** (fest oder einstellbar?).
