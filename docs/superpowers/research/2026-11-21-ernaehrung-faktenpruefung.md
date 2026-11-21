# Faktenprüfung Ernährungsziele, Open Food Facts, HealthKit (21.11.2026)

Recherche durch Sonnet für #254. Quellen sind jeweils verlinkt; **Interpretation** und **Lücke** sind markiert. Festlegungen der Hauptsitzung stehen am Ende.

## 1. Mifflin–St Jeor (Ruheenergie)

- Mifflin MD, St Jeor ST, Hill LA et al. (1990), Am J Clin Nutr 51(2):241–247, [doi:10.1093/ajcn/51.2.241](https://doi.org/10.1093/ajcn/51.2.241).
- Männer: 10 × kg + 6,25 × cm − 5 × Jahre **+ 5**; Frauen: dasselbe **− 161** (kcal/Tag).
- Stichprobe 498 Gesunde, 19–78 Jahre, normalgewichtig und adipös, R² = 0,71.
- Validierung: [Frankenfield et al. 2005](https://doi.org/10.1016/j.jada.2005.02.005) (am häufigsten innerhalb ±10 %), [Frankenfield 2013](https://doi.org/10.1016/j.clnu.2013.03.022) (82 % innerhalb ±10 %, Adipöse 75 %), [Frankenfield et al. 2003](https://doi.org/10.1016/s0002-8223(03)00982-9) (22 % mehr als 10 % daneben).
- **Interpretation:** Etwa jede fünfte Person liegt mehr als 10 % daneben. Text: „Schätzwert, Einzelfehler von ±10 % und mehr möglich“.

## 2. Faktor 1,2

- [FAO/WHO/UNU 2004, Tab. 5.3](https://www.fao.org/4/y5686e/y5686e07.htm): sitzend/leicht aktiv PAL 1,40–1,69; ~1,2 nur Kurzzeit-Überleben völlig Inaktiver („too low“).
- [DGE-FAQ Energiezufuhr](https://www.dge.de/gesunde-ernaehrung/faq/energiezufuhr/): 1,2–1,3 für gebrechliche, immobile Menschen; Büro 1,4–1,5.
- [EFSA 2017](https://www.efsa.europa.eu/sites/default/files/2017_09_DRVs_summary_report.pdf): PAL 1,4 = „low active (sedentary)“.
- **Interpretation:** Als Gesamtbedarf unterschätzt 1,2; eine Defizitwarnung auf dieser Basis schlägt zu spät an.

## 3. 7.700 kcal je kg

- Ursprung [Wishnofsky 1958](https://doi.org/10.1093/ajcn/6.5.542) (3.500 kcal/lb).
- [Hall 2008](https://doi.org/10.1038/sj.ijo.0803720), [Hall et al. 2011, Lancet](https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593): Regel ignoriert Anpassungen; Beispiel −480 kcal/Tag: Regel 22 kg im ersten Jahr, Modell etwa die Hälfte.
- Empfehlung: nur als Kurzfrist-Näherung (4–8 Wochen), „grobe Schätzung; der tatsächliche Verlauf flacht ab“; Hauptprüfung über das tägliche Defizit; Verweis auf den [NIDDK Body Weight Planner](https://www.niddk.nih.gov/bwp).

## 4. Abnahmetempo

- [CDC](https://www.cdc.gov/healthy-weight-growth/losing-weight/index.html): etwa 0,45–0,9 kg pro Woche. AHA/ACC/TOS 2013: 500–750 kcal/Tag Defizit (nur sekundär bestätigt).
- „1 % pro Woche“ ist keine Leitlinie; Prozentwerte nur aus dem Sport ([Garthe et al. 2011](https://doi.org/10.1123/ijsnem.21.2.97): 0,7 % besser als 1,4 %).
- Empfehlung: Warnschwelle `min(1 % Körpergewicht, 1 kg)` pro Woche, als App-Regel formuliert.

## 5. Untergrenzen

| Größe | Wert | Quelle |
|---|---|---|
| Kalorien | Warnung unter 1.200 (Frauen) / 1.500 (Männer); unter 800 nur ärztlich | AHA/ACC/TOS 2013 (sekundär) |
| Kalorien, harte Grenze | 1.000/Tag | [NIDDK Body Weight Planner](https://www.niddk.nih.gov/bwp) |
| Eiweiß | 0,8 g/kg (19–<65 J.), 1,0 g/kg ab 65; bei Übergewicht Referenzgewicht BMI 22 | [DGE](https://www.dge.de/wissenschaft/referenzwerte/protein/), [DGE-FAQ](https://www.dge.de/gesunde-ernaehrung/faq/ausgewaehlte-fragen-und-antworten-zu-protein-und-unentbehrlichen-aminosaeuren/) |
| Ballaststoffe | ≥ 30 g/Tag bzw. 14,6 g je 1.000 kcal (weiche Warnung) | [DGE](https://www.dge.de/wissenschaft/referenzwerte/ballaststoffe/) |
| Wasser | DGE: Getränke etwa 1,2–1,5 l (gesamt 2,25–2,7 l inkl. Nahrung, nach Alter, nicht Geschlecht); EFSA 2,0/2,5 l gesamt | [DGE](https://www.dge.de/wissenschaft/referenzwerte/wasser/), EFSA 2017 |

## 6. Aktivenergie vom Handgelenk

- [Fuller et al. 2020](https://doi.org/10.2196/18694): „no brand was accurate“; Apple überschätzte in 58 % der Vergleiche.
- [Shcherbina et al. 2017](https://doi.org/10.3390/jpm7020003): kein Gerät unter 20 % Fehler; Apple Watch geringster Gesamtfehler.
- [Lambe et al. 2025](https://www.nature.com/articles/s41746-025-02238-1): MAPE 9,7 % (Laufen) bis 151,7 % (Gehen), Richtung uneinheitlich.
- **Interpretation:** 100 % Anrechnung ist nicht belegbar; Teilanrechnung (z. B. 50 %) ist ein Erfahrungswert, keine Quelle.

## 7. Open Food Facts

- [API-Doku](https://openfoodfacts.github.io/openfoodfacts-server/api/), [Terms](https://world.openfoodfacts.org/terms-of-use), [Privacy](https://world.openfoodfacts.org/privacy).
- Limits: Produktabfrage 15/min, Suche 10/min (pro Nutzer bei Apps); Überschreitung → Sperre/503.
- User-Agent Pflicht: `AppName/Version (Kontakt-E-Mail)`.
- Textsuche: nur Legacy `/cgi/search.pl` oder Search-a-licious (`search.openfoodfacts.org`); kein Search-as-you-type. **Lücke:** Bedingungen von Search-a-licious unbekannt.
- Lizenz: Datenbank ODbL, Inhalte DbCL, Bilder CC BY-SA 3.0; Nennung mit Link; eigene Werte nicht mit OFF-Daten mischen.
- Cache erlaubt (ODbL), für nutzergetriebene Apps aber nicht empfohlen. IP-Logs werden 3 Jahre gespeichert; die Suchanfrage geht an OFF.

## 8. HealthKit

- [HKStatistics](https://developer.apple.com/documentation/healthkit/hkstatistics): Abfragen führen alle Quellen automatisch zusammen; `separateBySource` für Summen je Quelle. **Lücke:** Algorithmus/Priorität nicht dokumentiert (für die Health-App: [Apple Support](https://support.apple.com/en-us/108779), oberste Quelle hat Vorrang).
- iPhone ohne Uhr: laut [Apple-Engineer im Forum 2022](https://developer.apple.com/forums/thread/711396) kann das iPhone Aktivenergie berechnen; Nutzer berichten Nullwerte → fehlende Werte als „unbekannt“.
- Eigene Samples ausschließen: `HKQuery.predicateForObjects(from:)` mit `HKSource.default()` und `NSCompoundPredicate(notPredicateWithSubpredicate:)` – nicht dokumentiert, am Gerät testen, sonst `separateBySource`.
- Leseberechtigung wird nicht offengelegt ([Apple](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)).

## Festlegungen der Hauptsitzung (21.11.2026)

1. Mifflin–St Jeor unverändert, mit Hinweis auf ±10 %.
2. **Zwei Größen statt eines Faktors:** Das Tagesbudget rechnet wie Apple Health mit Grundbedarf ohne Bewegung (Ruheenergie × 1,2, beschriftet als „Grundbedarf ohne Bewegung“) plus angerechneter Aktivenergie; so gibt es keine doppelte Alltagsbewegung. Die Warnung vor zu großem Defizit rechnet dagegen mit dem tatsächlichen Gesamtumsatz: Grundbedarf + mittlere Aktivenergie der letzten 14 Tage; ohne Health-Daten PAL 1,4.
3. 7.700 kcal/kg nur als kurzfristige grobe Schätzung; Hauptprüfung über das tägliche Defizit.
4. Abnahmetempo: Warnung über `min(1 % Körpergewicht, 1 kg)` pro Woche, als App-Regel formuliert.
5. Untergrenzen wie Tabelle: weiche Warnung 1.200/1.500 kcal, harte Grenze 1.000 kcal; Eiweiß 0,8 g/kg (ab 65: 1,0) auf Referenzgewicht; Ballaststoffe und Wasser nur Hinweise.
6. Anrechnungsanteil (BU1b): einstellbar, **Voreinstellung 50 %** (Nutzer, 21.11.2026).
7. Open Food Facts: Limits einhalten (Suche nur auf Absenden, höchstens 10/min), Attribution in den Einstellungen, OFF-Daten getrennt von „Meine Lebensmittel“ (Übernahme als eigener Eintrag mit Quellenangabe), Kontaktadresse im User-Agent **fragt die App beim Nutzer ab** (Feld beim Einschalten der Online-Suche; ohne Adresse keine Anfrage an OFF; nie automatisch eine Adresse eintragen) (Nutzer, 21.11.2026).
8. HealthKit: eigene Samples ausschließen und Überlappung Uhr/iPhone am Gerät prüfen; fehlende Werte als „unbekannt“.
