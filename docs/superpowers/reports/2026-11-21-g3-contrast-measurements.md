# Strang K (Kontrast): Messung vor und nach den Textfarben

Stand 21.11.2026, Branch `feat/g3-contrast`. Gemessen mit `scripts/stress-audits.sh --collect-all 3` (alle sechs Audit-Klassen, drei Wiederholungen, je ein eigener Lauf ohne Wiederholung bei Fehlschlag). Jede Zahl ist die Summe der Befunde über die drei Wiederholungen; „Standard“ ist der Lauf in Standardgröße, „AX5“ der Lauf mit der größten Schrift im Dunkeln.

| | Ausgangsmessung K1 | Nach K2–K4 (K5) |
|---|---|---|
| Code-Stand | `fe75d52` (nach dem Merge von T, L, S in `main` und dem Merge von `main` in #261) | `1f3101f` |
| Testläufe | 42 von 42 grün | 40 von 42 grün (zwei Läufe der Abend-Klassen scheiterten an der Last, siehe unten) |
| Kontrastbefunde insgesamt | 739 (265 „failed“, 474 „nearly passed“) | 345 (188 „failed“, 157 „nearly passed“) |
| davon Standardgröße / AX5 | 660 / 79 | 283 / 62 |
| Befunde, die auf keinem Listeneintrag standen | 0 | 0 |
| Einträge der Liste (alle Arten) | 28 | 27 |
| Kontrast-Einträge | 13 | 12 |
| Muster in den Kontrast-Einträgen | 178 | 136 |

Die Befunde je Eintrag (Summe über drei Wiederholungen, Standard / AX5):

| Eintrag (Kontrast) | K1 | K5 | Ergebnis |
|---|---|---|---|
| Sekundärtext auf Hintergrund und Karte (Gruppe 1) | 261 / 18 | 92 / 10 | 10 Muster gestrichen, Rest bleibt |
| Text auf getönten Karten (rot, orange, grau, lila) | 48 / 17 | 17 / 9 | 1 Muster gestrichen, Rest bleibt |
| Knopf- und Segmenttexte (Akzent, Liquid Glass) | 42 / 12 | 23 / 15 | 1 Muster gestrichen, Rest bleibt |
| „Abschließen“ (Tagesabschluss) | 6 / 3 | 5 / 2 | bleibt (Liquid Glass) |
| „Unerledigt von heute“ | 3 / 0 | 2 / 0 | bleibt (Kopfzeile aus dem System) |
| Kapazitätskarte am Abend | 9 / 2 | 2 / 1 | keins gestrichen (Abend-Läufe unvollständig), „Tagesabschluss“ ergänzt |
| Titel der grauen Rastereinträge | 6 / 0 | 4 / 0 | unverändert |
| Titelzeile des gefalteten Blocks (AX5) | 0 / 0 | 0 / 0 | unverändert gelassen (siehe unten) |
| Rezept-Seiten, Fuß- und Kopftexte | 156 / 12 | 93 / 9 | 10 Muster gestrichen, Rest bleibt |
| Übersetzungs-Vorschau („Milch“, „Milk“) | 6 / 6 | 6 / 6 | bleibt |
| Seite „Siri & Kurzbefehle“ | 36 / 0 | 12 / 1 | 4 Muster gestrichen, Rest bleibt |
| Zutaten des Rezepts (Zutatenblatt) | 24 / 0 | 0 / 0 | **Eintrag entfernt** (7 Muster) |
| Akzent- und Knopftexte der Rezept-Seiten | 63 / 9 | 27 / 9 | 10 Muster gestrichen, Rest bleibt |

Ein Muster wurde nur gestrichen, wenn es in K1 in allen drei Wiederholungen traf und in K5 in keiner, auf Bildschirmen, deren Läufe vollständig waren. Muster ohne Treffer in beiden Messungen blieben stehen: frühere Läufe hatten sie gemeldet, und die Abend-Läufe der Messung sind unvollständig (in K5 scheiterte je Klasse ein Lauf von drei an Last). Das zeigte sich beim vollen Lauf danach: „von heute übrig“, „Tagesabschluss“, „Ganztägig“, „Schlafzeit 23:00“ und „Projektwoche“ wurden im Abend-Lauf in AX5 wieder gemeldet, ein CI-Lauf meldete „Anmeldung Abschlussarbeit“; diese Muster stehen wieder auf der Liste. Die Regel ohne Element für einen Kontrastbefund der Übersetzen-Karte (in beiden Messungen nie getroffen) entfiel.

## Was K2–K4 bewirkt haben

- **Akzentfarbe (`AccentColor` #005FCC):** Die Akzenttexte der Rezept-Seiten („Einverstanden“, „Rezept speichern“, „Neues Rezept“, „So lassen“, „Mit ChatGPT übersetzen“ u. a.) und „Alle“ im Suchblatt werden nicht mehr gemeldet.
- **Schrifttöne (`secondaryText`, `redText`, `orangeText`, `purpleText`, `greenText`):** Die Zutaten des Rezepts, „morgen“ und viele Kopf- und Fußtexte werden nicht mehr gemeldet; die Sekundärtexte sinken von 279 auf 102 Befunde. Die Texte der Kapazitätskarte am Abend (Material als Hintergrund) bleiben intermittierend.
- **Uhrzeit im Raster (`gridTimeText`):** Die Uhrzeitzeile der Rastereinträge wurde im Ausgangslauf nicht gemeldet (Kontrast-Muster ohne Treffer); K4 ändert daran nichts Messbares, sie steht jetzt im 85-%-Ton.

## Was bleibt, und warum

1. **Sekundärtext (78 %).** Der Audit meldet weiterhin Kopf- und Fußtexte, Zählungen und die Stundenmarken („13:00“) in kleiner Schrift, viele als „failed“. Die Rechnung (`TextTonesTests`) liegt hell bei mindestens 4,5 : 1; der Audit misst das gerenderte Bild kleiner Schrift mit 78 % Deckkraft und kommt zu einem anderen Ergebnis. **Plan K5, Schritt 3** sieht vor, zuerst den Asset-Wert anzuheben (z. B. 78 % → 82 % oder deckend) und neu zu messen. Das ist in dieser Messung **nicht** geschehen: die Obergrenze von drei Wiederholungen war erreicht, und ein dunkleres Grau verändert das Erscheinungsbild der Standardgröße sichtbar. Der Wert ist eine Entscheidung des Nutzers.
2. **Text auf Liquid Glass und vom System abgeblendete Knöpfe** („Abschließen“, „Verwerfen“, „Übernehmen“, „Auswählen“, „Abbrechen“, „Getrennt lassen“, „Zusammenfassen“, „Rezept holen“, „Zutaten holen“). Das System zeichnet den Hintergrund; wie im Plan erwartet.
3. **Kopfzeile „Unerledigt von heute“** (Systemfarbe einer Abschnittskopfzeile).
4. **Titel grauer Rastereinträge** („Sprechstunde“, „Mittagspause“) und die drei Texte der Kapazitätskarte am Abend: Text auf getönter oder durchscheinender Fläche.
5. **Namen in der Übersetzungs-Vorschau:** Der Audit meldet sie unverändert (12 Befunde vorher und nachher); die Zutatenzeilen des Rezeptblatts, die gleich aussahen, bestehen jetzt.

## Nicht angefasst

- **Titelzeile des gefalteten Blocks (AX5).** Der Eintrag hat in beiden Messungen (sechs Wiederholungen) keinen Befund gedeckt. Er bleibt, weil sein gemessener Wert (16,5 : 1 hell, 15,9 : 1 dunkel, `MarkerRenderContrastTests.collapsedBlock_renderedContrast`) und die Bedingung (Überlappung am Vormittag) nicht Teil von K sind; ob er gestrichen werden kann, ist eine Entscheidung nach einem Lauf mit anderer Uhrzeit.
- Alle Einträge der Arten Dynamic Type, „Text clipped“ und Trefferfläche: unverändert (nicht Ziel von K).
- Kapsel „knapp“ im Plan-Raster (5,4 : 1) und die Marker-Farben: eigene Assets aus Strang P, nicht verändert.

## Zwei Fehlschläge der K5-Messung

- `AccessibilityAuditEveningLargeTextUITests`: „The leftover row cannot be scrolled into view“ (Iteration 1). Ein Wischversuch des Tests, kein Audit-Befund.
- `AccessibilityAuditEveningUITests`: „Audit failed to complete in time“ in allen drei Versuchen (Iteration 3). Die Maschine war mit weiteren Läufen anderer Strände belastet (Iterationen von 1151 s bis 1513 s statt 1038 s bis 1090 s in K1).

Beide Läufe fehlen in der Auswertung der jeweiligen Iteration; die Abend-Einträge stützen sich damit auf zwei von drei Wiederholungen.
