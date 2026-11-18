# Tagwerk – Phase 3 Design: Ernährung, Trinken und Training

Stand: 2026-11-18 · Status: **vorläufig nach Fable-Empfehlung, Freigabe des Nutzers offen** (der Nutzer war nicht erreichbar) · Baut auf: `2026-11-17-tagwerk-design.md` (Hauptdesign, §2, §6 `HealthBridge`, §7, §8 Skizze „Erfassen“, §9 „Datenhoheit Ernährung/Training“), `../spikes/2026-11-17-feasibility-results.md` (HealthKit, Apples Modell, Bild-Eingabe). Mockup: `../mockups/2026-11-18-phase-3-nutrition-training-mockups.html` (Empfehlungen E1a, E2a, E3a, E4a, E5a, E6a, E7a, E8a; vorläufig, Freigabe offen). Epic: GitHub #3.

## 1. Absicht und Warum

Tagwerk bündelt Aufgaben, Kalender und Planung. Phase 3 ergänzt das, was laut Hauptdesign §1 noch fehlt: Essen, Trinken und Training **schnell unterwegs erfassen**, mit einer KI-Schätzung für Mahlzeiten, und den Tagesstand gegenüber eigenen Zielen sehen. Apple Health bleibt der Ort, an dem andere Apps (Apple Watch, Fitness) die Daten sehen.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Neuer Tab **„Erfassen“** mit Tagesstand (kcal, Wasser, Eiweiß optional, Trainings der Woche), Schnellerfassung und Liste des Tages; zurückblättern zum Nachtragen.
- **Essen:** Text und/oder Foto → ChatGPT-Schätzung als einzelne Posten mit Spannen → editierbar → sichern. Ohne Anmeldung oder Einwilligung manuelle Eingabe. „Zuletzt und häufig“ mit Sofort-Erfassen.
- **Trinken:** 250/330/500 ml mit einem Tipp, andere Menge im Blatt.
- **Training:** manuell erfassen (Art, Dauer, Beginn, optional kcal); Trainings anderer Quellen aus Health anzeigen; Wochenzähler.
- **Spiegelung nach Health** (Hauptdesign §9): Mahlzeiten (Energie, Eiweiß, KH, Fett), Wasser und manuelle Trainings; Bearbeiten und Löschen werden nachgezogen.
- Ziele und Einwilligung in den Einstellungen; Health-Zugriff unter „Zugriff“.

**Nicht-Ziele (Phase 3)**
- Fortschritt/Wochenrückblick, Kalorien-Zeile im Kopf von „Planen“, Widget, Erfassen per Assistent oder Siri (Phase 4).
- Getränkearten mit Nährwerten (laufen über „Essen“), Verbrauchsschätzung für Trainings, Barcode, Lebensmitteldatenbank.
- Nahrungsdaten anderer Apps aus Health lesen (E11, s. §8).
- Schätzen mit Apples lokalem Modell (Spike: für Kalorien ungeeignet).

**Anti-Ziele** (aus Hauptdesign §2)
- Schätzungen erscheinen als exakte Werte. → Immer „~“ und Spanne; Health bekommt den Mittelwert mit Metadaten-Vermerk „geschätzt“.
- Gesundheitsdaten verlassen das Gerät ohne bewusste Aktion. → Nur Text/Foto der Mahlzeit, nur nach Einwilligung und Tippen auf „Schätzen“.
- Erfassen dauert länger als ~10 s. → Wasser mit einem Tipp, „＋“ in „Zuletzt und häufig“ ohne KI.
- Daten-Drift zwischen Tagwerk und Health. → Tagwerk ist Quelle der Wahrheit für eigene Einträge; Health ist Spiegel mit Nachholen.

## 3. Ansätze

| Ansatz | Kern | Abwägung | Entscheidung |
|---|---|---|---|
| **A: SwiftData ist Quelle, Health ist Spiegel** | Einträge in SwiftData; Health bekommt Kopien mit Sync-Kennung; eigene Samples werden beim Lesen ausgefiltert | Funktioniert ohne Health-Berechtigung; Bearbeiten/Löschen unter eigener Kontrolle; Nachholen nach späterem Verbinden | **Gewählt** (Hauptdesign §9) |
| B: Health ist Quelle | Nur in Health schreiben und lesen | Ohne Berechtigung nichts nutzbar; Lesestatus nicht erkennbar (Spike) → leere Liste nicht von Ablehnung unterscheidbar | verworfen |
| C: Nur SwiftData | Kein Health | Widerspricht Hauptdesign §9; Watch-Trainings fehlen | verworfen |

## 4. Daten

### 4.1 Was wo liegt

| Daten | Ort | Felder (Kern) |
|---|---|---|
| Mahlzeit | SwiftData `MealRecord` | `id` (UUID), `date`, `kind` (Frühstück/Mittagessen/Abendessen/Snack), `title`, `items` (JSON `[MealItem]`: Name, Menge-Text, Faktor, kcal min/mittel/max, Eiweiß/KH/Fett ~), `origin` (`estimated`/`manual`), `estimatedAt`, `healthVersion`, `healthSynced` |
| Wasser | SwiftData `DrinkRecord` | `id`, `date`, `milliliters`, `healthVersion`, `healthSynced` |
| Manuelles Training | SwiftData `WorkoutRecord` | `id`, `activity` (Rohwert `WorkoutActivity`), `start`, `minutes`, `kilocalories?`, `healthVersion`, `healthSynced` |
| Ausgeblendete Wiederholvorschläge | SwiftData `HiddenMealSuggestion` | normalisierter Titel |
| Trainings anderer Quellen | **Health**, nur gelesen | Art, Beginn, Dauer, kcal, Quellenname |
| Ziele, Einwilligung | `AppSettings` (additiv, mit Standardwerten) | `goalKilocalories = 2300`, `goalWaterMilliliters = 2000`, `goalWorkoutsPerWeek = 3`, `proteinGoalEnabled = false`, `goalProteinGrams = 120`, `mealEstimationConsent = false`, `mealEstimationEnabled = true`, `healthCardDismissed = false` |

Fotos werden nicht gespeichert (E3).

### 4.2 Spiegelung nach Health (Paket `HealthBridge`)

- Jedes Sample trägt `HKMetadataKeySyncIdentifier` = `tagwerk.<art>.<UUID>[.<nährwert>]` und `HKMetadataKeySyncVersion` = `healthVersion`; Bearbeiten erhöht die Version und ersetzt das Sample in Health. Zusätzlich Metadaten `TagwerkEntry = 1` und bei Schätzungen `TagwerkEstimated = 1`.
- Mahlzeit → je ein Quantity-Sample für Energie, Eiweiß, KH, Fett (nur Werte > 0), Zeitpunkt = Mahlzeitzeit. Wasser → `dietaryWater`. Training → `HKWorkoutBuilder` mit Art, Beginn/Ende und optional `activeEnergyBurned`.
- Löschen: `deleteObjects` mit Prädikat auf `HKMetadataKeySyncIdentifier`. Bearbeiten eines Trainings: löschen und neu anlegen (Workouts lassen sich nicht über die Sync-Version ersetzen, falls doch → am Gerät prüfen).
- Fehlschlag oder fehlende Berechtigung: Eintrag bleibt lokal mit `healthSynced = false`; Tagwerk holt nach (beim Öffnen des Tabs, nach Verbinden, bei Rückkehr in den Vordergrund). Lösch-Wünsche, die Health nicht erreichen, liegen in einer kleinen Warteschlange (`PendingHealthDeletion`).
- Lesen: nur Workouts der letzten 8 Tage (Wochenzähler + Tag); eigene über Metadaten `TagwerkEntry` und die eigene Quelle ausgefiltert.
- Berechtigung: schreiben Energie, Eiweiß, KH, Fett, Wasser, Workouts, Aktive Energie; lesen Workouts. Nur auf Tippen angefragt (Karte im Tab, Zeile unter „Zugriff“), nie beim Start. Lesestatus ist nicht erkennbar; die Zugriffszeile leitet sich nur aus den Schreibrechten ab (verbunden/teilweise/abgelehnt/nicht gefragt/nicht verfügbar).
- Keine Gesundheitswerte, Titel oder Mengen in Logs.

## 5. Regeln (reine Logik in `TagwerkCore`)

1. **Mahlzeitentyp nach Uhrzeit:** 05:00–10:29 Frühstück, 11:30–14:29 Mittagessen, 17:30–21:29 Abendessen, sonst Snack; änderbar.
2. **Summen eines Tages:** kcal (Mittelwert, Spanne aus Summe der min/max), Eiweiß, KH, Fett, Wasser (ml). Nur eigene Einträge (E11). Tag = Kalendertag in Ortszeit.
3. **Darstellung:** Schätzung „~520 kcal“ und „wahrscheinlich zwischen 410 und 550 kcal“, in Listen „410–550“; manuelle Werte ohne „~“. Gerundet auf 10 kcal bzw. 1 g. Kopf: „noch ~990“ bzw. „120 über Ziel“ (orange, nicht rot).
4. **Posten-Faktor:** Ein Mengen-Stepper (×0,5 bis ×3 in 0,5-Schritten) skaliert die Werte eines Postens.
5. **Prüfung der KI-Antwort:** kcal-Werte ≥ 0, min ≤ mittel ≤ max (sonst korrigiert), höchstens 20 Posten, Werte über 5.000 kcal je Posten verworfen; leere Postenliste = „Darin war kein Essen zu erkennen.“
6. **Wochenzähler:** Mo–So in Ortszeit; eigene und fremde Trainings ab 10 min zählen je einmal.
7. **Überschneidung:** Warnung, wenn ein manuelles Training sich zeitlich mit einem Health-Training überschneidet (zählt sonst doppelt).
8. **„Zuletzt und häufig“:** Mahlzeiten der letzten 30 Tage, gruppiert nach normalisiertem Titel (klein, ohne Leerzeichen am Rand); sortiert nach Anzahl, dann jüngstem Datum; höchstens 8; ausgeblendete fehlen; beim Tippen nach Titel gefiltert. „＋“ legt eine Kopie mit Zeit = jetzt und Typ nach Uhrzeit an.

## 6. KI-Schätzung

- Anbieter: ChatGPT über `AIEnvironment` (Modellwahl wie bisher), `text.format` json_schema strict: `{ title, items: [{ name, amount, kcal_min, kcal, kcal_max, protein_g, carbs_g, fat_g }], note }`. Anweisung auf Deutsch, Mengen in üblichen Portionen, Spanne ehrlich.
- Eingabe: nur der Text und optional ein Foto (JPEG, lange Kante ≤ 1.024 px, neu kodiert → keine EXIF-/Ortsdaten). AIKit erhält dafür einen Eingabefall mit `input_image` (Format aus dem Spike). Chat-Verläufe speichern keine Bilder.
- **Einwilligung (E3a):** einmaliges Blatt vor der ersten Schätzung; „Einverstanden und schätzen“ setzt `mealEstimationConsent` und schätzt sofort. Widerruf: Schalter „Mahlzeiten von ChatGPT schätzen“ unter Einstellungen › Erfassen (aus = manuelle Eingabe, Einwilligung bleibt gespeichert).
- Fehler (Netz, Zeitüberschreitung, abgelaufene Anmeldung, Kontingent, Ablehnung, nichts erkannt) mit festen Texten aus dem Mockup; Text und Foto bleiben stehen, „Ohne Schätzung eintragen“ ist immer möglich.
- Kein KI-Aufruf ohne Tippen; der Hintergrund-Refresh berührt Erfassen nicht (2b §8.4).

## 7. Oberfläche (Mockup E1a–E8a)

- **Tabs:** Planen (0), Aufgaben (1), **Erfassen (3)**, Einstellungen (2). Der Wert 3 hält bestehende Sprünge (`requestedTab`, Benachrichtigungen) stabil; in der Leiste steht „Erfassen“ vor „Einstellungen“.
- **E1a Übersicht:** Kopf mit Tag und Pfeilen (nur zurück bis heute), kcal mit Balken, Wasser, Eiweiß (mit Ziel), Wochenzähler; Knöpfe Essen/Trinken/Training; Wasser-Knöpfe; Liste nach Art gruppiert (Mahlzeiten, Wasser als eine Zeile, Trainings inkl. Health). Einmalige Health-Karte, solange nicht verbunden und nicht weggeklickt.
- **E2a Essen:** Blatt mit Eingabe, Foto (Kamera, Mediathek), „Schätzen“ bzw. „Weiter“; Vorschau mit Posten (Stepper), Gesamtsumme mit Spanne, Typ und Zeit; „Sichern“. „Zuletzt und häufig“ unter der Eingabe.
- **E4a Trinken:** Sofort-Knöpfe mit „Widerrufen“ (4 s); Blatt für andere Menge/Zeit.
- **E5a Training:** Form mit Art, Dauer, Beginn, kcal optional; Vorbelegung vom letzten Training; Überschneidungswarnung.
- **E8a:** Tippen öffnet das passende Formular; Wischen löscht mit „Widerrufen“.
- **E6a Einstellungen:** Zeile „Erfassen“ (Ziele, Schätzung) und Zeile „Health“ unter „Zugriff“.

## 8. Vorläufige Entscheidungen (Fable, Freigabe offen)

1. Spanne in kcal statt „± %“ (Skizze im Hauptdesign zeigte ± %).
2. Fotos werden nicht gespeichert.
3. Nur Wasser zählt als Trinken.
4. Jedes Training ab 10 min zählt für den Wochenzähler, auch mehrere pro Tag.
5. Standardziele 2.300 kcal, 2,0 l, 3 Trainings/Woche, Eiweiß-Ziel aus (120 g) – Platzhalter, keine Empfehlung.
6. Kein eigener Schalter „In Health speichern“; die iOS-Berechtigung regelt es.
7. Nahrungsdaten anderer Apps aus Health werden nicht mitgezählt.
8. Kalorien-/Wasser-Zeile im Kopf von „Planen“ erst in Phase 4.
9. Apples lokales Modell wird in Phase 3 nicht verwendet (Spike: Kalorien zu ungenau).
10. Kein Einrichtungsschritt für Health; Anfrage über Karte im Tab und Einstellungen.
11. Zurückblättern nur in die Vergangenheit (Nachtragen), nicht in die Zukunft.

## 9. Offen (Gerät)

- HealthKit-Signierung mit dem Personal Team für die App (nicht nur den Spike); Schreib-/Löschverhalten mit Sync-Kennung unter iOS 27; Trainings der Apple Watch werden gelesen; „Health öffnen“-Ziel.
- Kamera nur am Gerät (Simulator hat keine).
- Güte der Foto-Schätzung, Dauer einer Schätzung (Ziel ≤ 10 s für Text).
- Echter ChatGPT-Aufruf mit Bild aus der App (Spike hat das Format geprüft).

## 10. Dem Umsetzenden überlassen

Prompt-Wortlaut, Schema-Details, Ordnerstruktur, Testaufbau, Animationen, Darstellung innerhalb des Mockups.

## Quellen

- Apple: HealthKit `HKMetadataKeySyncIdentifier`, `HKMetadataKeySyncVersion`, `HKWorkoutBuilder` (Dokumentation in Xcode 27.2).
- Spike-Ergebnisse: `../spikes/2026-11-17-feasibility-results.md`.
