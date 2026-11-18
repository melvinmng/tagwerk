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

## 11. Abweichungen und Ergänzungen bei der Umsetzung (2026-11-18)

Umgesetzt nach `../plans/2026-11-18-phase-3-nutrition-training.md` inkl. der Änderungen nach dem Fable-Review (gehen §4–§8 vor, wo sie abweichen).

- **Einwilligung:** nur ein Flag `mealEstimationConsent` (Standard aus). Der Schalter unter Einstellungen › Erfassen bindet daran; Einschalten gilt als Zustimmung. Ohne ChatGPT-Anmeldung ist er ausgegraut. Ein separates `mealEstimationEnabled` (§4.1) entfällt.
- **„~“ je Posten:** `MealItem.isEstimated`; ein überschriebener oder von Hand hinzugefügter Posten ist genau (min = mittel = max, ohne „~“). „~“ der Summe und `TagwerkEstimated` in Health folgen aus „irgendein Posten geschätzt“. Auf 10 kcal gerundet werden nur geschätzte Werte.
- **Mengen-Stepper** bleibt ein Faktor ×0,5–×3 („Menge ×1,5“), nicht die Stückzahl aus dem Mockup.
- **Ablehnung durch ChatGPT** wird nicht eigens erkannt: leere Postenliste → „Darin war kein Essen zu erkennen …“, sonst der allgemeine Fehlertext. Zeitlimit 30 s.
- **„Zuletzt und häufig“** zeigt „zuletzt <Tag>“ ohne Anzahl („12×“); „Nicht mehr vorschlagen“ ist nicht gebaut (Regel-Parameter vorhanden).
- **Health:** gemeinsamer Metadatenschlüssel `TagwerkEntryID` für das Löschen aller Samples eines Eintrags; Nährwerte ≤ 0 werden beim Bearbeiten in Health gelöscht; Trainings werden immer gelöscht und neu angelegt; abgelehnte Typen werden übersprungen, der Eintrag bleibt zum Nachholen markiert. Health-Löschungen laufen erst nach dem 4-s-Widerrufen-Fenster über eine Warteschlange (`PendingHealthDeletion`). Die Spiegelung läuft seriell. Gelesen werden fremde Trainings der Woche des angezeigten Tages (nicht „8 Tage“). Kein Titel, kein Postenname geht nach Health; manuelle Werte tragen `HKMetadataKeyWasUserEntered`.
- **Health-Karte** erscheint nur, solange iOS die Anfrage noch zeigen würde (`statusForAuthorizationRequest` = `.shouldRequest`) und sie nicht weggeklickt wurde. „Health öffnen“ öffnet `x-apple-health://`.
- **Assistent:** neuer Kontext „Erfassen“; er erhält ausdrücklich keine Ernährungs- oder Trainingsdaten.
- **Tab „Erfassen“** hat den Wert 3 und steht vor „Einstellungen“.
- **Demo:** `-TagwerkDemoData` setzt einen Demo-Health-Store (verbunden, ein Lauf der „Apple Watch“ um 07:05) und Beispielmahlzeiten; `-TagwerkDemoAI` beantwortet `meal_estimate` mit „Brötchen mit Käse“ (Eingabe mit „Tisch“ → nichts erkannt).
- **Review vor dem Merge (Fable):** Behoben: Der Tab folgt nach Mitternacht auf den neuen Tag, wenn er „Heute“ zeigte; „Sichern“ wartet nicht mehr auf Health und legt bei Doppeltipp kein zweites Training an; Löschen betrifft nur die Health-Typen der Eintragsart, abgelehnte Typen gelten als erledigt (keine endlosen Wiederholungen bei Teilberechtigung; vor der ersten Health-Anfrage verfallen Lösch-Wünsche); Zahlenfelder übernehmen jede Eingabe sofort (das Zehnerfeld hat keine Return-Taste); Posten haben eine stabile ID; „Stopp“ zeigt keinen Fehler mehr; Datum und Beginn nicht in der Zukunft; „Widerrufen“ auch im Trinken-Blatt; keine verlorene Spiegel-Anforderung; Health-Ergebnisse einer überholten Tagesnavigation werden verworfen; die Health-Karte blitzt nicht auf; „über Ziel“ rundet nur Schätzungen; Nachholen auch beim Öffnen des Tabs; die manuelle Form rechnet den Mengenfaktor ein. Offen (klein): Das Laden der Modellliste vor einer Schätzung liegt außerhalb der 30-s-Grenze.
- **Simulator-Prüfung fiel aus:** Der Simulator war wieder von der Sitzung des 2b-2-Threads belegt (`DEVICE_IN_USE`). Die Oberfläche ist nur gebaut und über Modelltests geprüft, nicht angesehen.

**Geräte-Checkliste (offen):** Signierung mit HealthKit-Entitlement über `scripts/refresh-install.sh`; Ersetzung per Sync-Version; erneutes Sichern einer gelöschten Kennung; Verbleib des Energie-Samples nach dem Löschen eines Trainings; `HKWorkoutBuilder` ohne Gerät (auch Schwimmen); Trainings der Apple Watch werden gelesen und eigene nicht doppelt gezählt; Kamera; echte ChatGPT-Schätzung mit Text und Foto (Dauer, Güte); Ziel von „Health öffnen“.

## 12. Nachtrag: Schritte und Trainingszeit (2026-11-18)

Umgesetzt nach `../plans/2026-11-18-steps-training-time.md` (ST1) mit den freigegebenen Entscheidungen am Ende des Plans; sie gehen §4.2 und §8 vor, wo sie abweichen.

- **Schritte als Lesetyp:** `HKQuantityType(.stepCount)`, Tagessummen über eine Statistikabfrage (`.cumulativeSum`, Intervall ein Tag); Health führt iPhone und Apple Watch zusammen. Der Schritt-Typ hat einen eigenen Status (`stepsAccess()`) und eine eigene Anfrage (`requestStepsAuthorization()`). `access()` fragt weiter nur Trainings ab (`HealthKitStore.coreReadTypes`), damit bestehende Nutzer nicht wieder als „nicht gefragt“ gelten; ein Test sichert das. Die Health-Karte fragt bei Neuverbindung beide Gruppen in einem Blatt an.
- **Anfrage nur nach Tippen:** „In Health erlauben“ in der Kachel „Schritte“ (vor der ersten Health-Verbindung das gemeinsame Blatt, danach nur Schritte) oder „Schritte erlauben“ in Einstellungen › Zugriff.
- **Ohne Daten „–“, nie 0:** iOS unterscheidet eine abgelehnte Leseerlaubnis nicht von „keine Schritte“.
- **Trainingszeit statt Anzahl:** Ziel `goalWorkoutMinutesPerWeek` (Platzhalter 150 min, 0 blendet aus) statt `goalWorkoutsPerWeek`; das alte Attribut bleibt im Schema. Einmalige Übernahme (`workoutGoalMigrated`): War das alte Ziel 0, wird das Minutenziel 0. Zur Trainingszeit zählen alle Trainings, auch unter 10 min; die 10-min-Schwelle gilt nur noch für die Zahl der Trainings im Wochenrückblick.
- **Schrittziel:** `goalStepsPerDay` (Platzhalter 8.000, 0 = ohne Ziel).
- **Schreibweise:** Ab 60 min überall „x h y min“, auch gegen das Ziel („2 h 7 min / 2 h 30 min“), in Liste, Abschnittskopf, Kachel, Wochenrückblick, Einstellungen und Trainingsblatt.
- **Datenschutz:** Schritte werden nur gelesen und angezeigt, nicht in SwiftData gespeichert, nicht geloggt und nie an den Assistenten oder die Mahlzeitenschätzung gegeben. Zu Widget und Kopf von „Planen“ siehe Phase-4-Design §13.

## Quellen

- Apple: HealthKit `HKMetadataKeySyncIdentifier`, `HKMetadataKeySyncVersion`, `HKWorkoutBuilder` (Dokumentation in Xcode 27.2).
- Spike-Ergebnisse: `../spikes/2026-11-17-feasibility-results.md`.
