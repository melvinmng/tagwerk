# Tagwerk – KI-Planung: Kontext, Kapazität, Anzeige (Entscheidungsvorlage)

Stand 2026-11-18 · Grundlage: Gerätetest mit rund 150 offenen Aufgaben; Code in `AIPlanning.swift`, `AIPlanner.swift`, `PlanningModel.swift`; Design §6.1, §8.2, §11.10. Ändert §11.10 und die Kapazitätsprüfung aus §8.2, sobald freigegeben.

**Einordnung:** Alle Zahlen sind Startwerte ohne Messung. Die Befunde unter 0 sind aus dem Code abgeleitet, nicht auf dem Gerät nachgestellt.

## 0. Befunde aus dem Code (über die Diagnose hinaus)

1. **Überbuchter Tag sperrt jeden Block**, auch für Aufgaben, die schon mitgezählt sind: `validateBlocks` prüft `plannedMinutes − ersetzte Last + Blockminuten ≤ availableMinutes`. Bei 80 min Überbuchung scheitert das selbst dann, wenn der Block nur Last in Zeit umwandelt.
2. **Die Sortierung begräbt das Wichtige:** sortiert wird zuerst nach Fälligkeit, also stehen alle alten überfälligen Aufgaben vor einem P1 mit späterer Frist; bei mehr als 60 Kandidaten fällt er ganz heraus. P1 ohne Fälligkeit gilt nicht als „wichtig“ und kommt im Tagesplan gar nicht vor.
3. **Die KI rechnet freie Zeit selbst** aus Terminen, Puffer und Pause. `freeMinutes` gilt für den ganzen Tag, nicht ab jetzt. `freeGaps()` existiert lokal, wird aber nicht mitgeschickt.
4. **Verschieben ist in Woche/Monat praktisch tot:** dort gehen nur nicht zugeordnete Aufgaben in die Eingabe, ein Move braucht aber eine Aufgabe, die auf einem Tag lastet.

## 1. Auswahl der Aufgaben

Zwei Stufen: **Kern** (immer dabei, nur durch die Höchstzahl begrenzt) und **Auffüllung** (nur solange das Minutenbudget nicht erreicht ist).

| | Tag | Woche | Monat |
|---|---|---|---|
| Fälligkeitsfenster ab heute | 3 Tage | 14 Tage | 45 Tage |
| Budget = Faktor × freie Zeit des Zeitraums | 2,0 | 1,5 | 1,25 |
| Mindest- / Höchstzahl Aufgaben | 8 / 25 | 15 / 40 | 20 / 60 |

Freie Zeit: Tag = freie Lücken ab jetzt minus wiederkehrender Aufwand; Woche/Monat = Summe der freien Minuten der Arbeitstage. Aufgaben ohne Aufwand zählen mit der Standarddauer. Der Faktor sinkt mit der Länge des Zeitraums, weil die Auswahl bei vielen Tagen ohnehin groß ist.

**Kern**
- Dem Tag (bzw. einem Tag des Zeitraums) zugeordnet oder dort mitgezählt, ohne Block.
- Im Fenster fällig, oder Anker (Epic-Frist, verknüpfte Deadline) im Fenster.
- **P1 immer**, auch mit späterer oder ohne Fälligkeit (höchstens 10, nach Fälligkeit).
- Überfällig: nur wenn P1/P2, wichtig oder höchstens 14 Tage überfällig. Ältere überfällige mit P3 oder ohne Priorität gehen nicht mit; die KI bekommt nur ihre Anzahl (`olderOverdueCount`) für die Zusammenfassung.

**Auffüllung** (der Reihe nach, Abbruch bei erreichtem Budget oder Höchstzahl; läuft mindestens bis zur Mindestzahl)
1. Nur Tag: Aufgaben, die den nächsten zwei Tagen zugeordnet sind (vorarbeiten; ein Block heute setzt nach §11.3 den Arbeitstag um).
2. Fällig im doppelten Fenster (6 Tage / 4 Wochen / 90 Tage).
3. P2 ohne Fälligkeit.
4. Ältere überfällige (höchstens 5), dann übrige ohne Fälligkeit (höchstens 5).

**Nie dabei:** wiederkehrende Erinnerungen (wie bisher), Aufgaben mit einem künftigen Block, dessen Dauer den Aufwand deckt, im Tagesplan Aufgaben mit Arbeitstag nach dem Fenster. **Neu in Woche/Monat:** bis zu 10 zugeordnete Aufgaben überbuchter Tage als `movable`, sonst bleiben Zuordnungen unangetastet.

**Reihenfolge** (ersetzt „Fälligkeit, Priorität, Quelle“), zugleich die Rangfolge für die KI:
1. Kern vor Auffüllung.
2. Zieldatum = das frühere aus Fälligkeit und Anker; Überfälliges zählt als heute; ohne Datum zuletzt.
3. Priorität P1 → ohne.
4. Ursprüngliche Fälligkeit (älter zuerst), Quelle, Titel.

Ausnahme: P1 steht innerhalb des Kerns immer vor Nicht-P1 mit Zieldatum nach heute. Muss gekürzt werden, wird vom Ende her gekürzt und die Zahl als `omittedCount` mitgeschickt.

**Empfehlung:** so übernehmen. Der Kern erfüllt „nur was im Fenster fällig ist“, die Auffüllung „bei Luft mehr“, und das Budget bindet die Menge an die tatsächlich freie Zeit statt an eine feste Zahl.

## 2. Tage in der Eingabe

| Planung | Planungstage | Nur Ziel fürs Verschieben |
|---|---|---|
| Tag | heute | die nächsten 2 Arbeitstage (statt 7 Tage) |
| Woche | gezeigte Woche ab heute | keine |
| Monat | gezeigter Monat ab heute | keine |

Je Tag nur noch:
- **Planungstag im Tagesplan:** Datum, Arbeitsbeginn/-ende, `freeSlots` (lokal berechnete Lücken ab jetzt, schon ohne Puffer, Pause, Blöcke), `freeMinutes`, `overbookedBy`, belegende Termine und Deadlines nur mit Titel, Beginn, Ende.
- **Tage in Woche/Monat:** Datum, `dayOff`, `freeMinutes`, Titel der Deadlines.
- **Zieltage:** Datum, `dayOff`, `freeMinutes`.

Es entfallen: nicht belegende Termine, `bufferMinutes`, `recurringMinutes`, `availableMinutes`, `plannedMinutes`, `existingBlocks`, Lunch, die Termin-Flags.

**Empfehlung:** Lücken lokal rechnen und mitschicken. Das nimmt der KI die fehleranfälligste Rechnung ab und verkleinert die Eingabe deutlich (Größe nicht gemessen, siehe 6).

## 3. Kapazität in der Prüfung

**Empfehlung: Zeit ist hart, Last ist weich.**

- **Hart (Vorschlag wird verworfen):** innerhalb der (ggf. verlängerten) Arbeitszeit, keine Überschneidung mit Terminen samt Puffer, Pause, Blöcken; nicht in der Vergangenheit; nicht nach Fälligkeit oder Anker; Summe der neuen Blöcke ≤ freie Lücken minus wiederkehrender Aufwand.
- **Block für eine schon mitgezählte Aufgabe:** immer zulässig, wenn er zeitlich passt. Er senkt die Überbuchung.
- **Block für eine neue Aufgabe an einem überbuchten Tag:** zulässig, wenn die Aufgabe P1 oder wichtig ist oder bis übermorgen fällig; sonst nur, wenn Moves und Verlängerung derselben Antwort mindestens ihre Minuten freimachen. Andernfalls `overCapacity` und Nachfrage wie bisher.
- **Überbuchung als lokal berechnetes Risiko:** Restlast (Aufgaben ohne Uhrzeit, ohne Block) gegen Restzeit nach allen Vorschlägen. Bleibt etwas übrig, zeigt die Leiste „Danach noch 50 min zu viel“; nichts wird verworfen.
- **Reihenfolge wie heute:** erst Verlängerungen, dann Moves, dann Blöcke. Ein Move entlastet den Herkunftstag; der **Zieltag bleibt lastbasiert hart** (sonst wandert das Problem nur weiter) und darf nicht nach Fälligkeit/Anker liegen.
- **Verlängerung nur mit Wirkung:** angenommen, wenn mindestens ein Block in der Zusatzzeit liegt oder die Überbuchung sinkt; sonst verworfen.
- **Woche/Monat:** Zuordnungen bleiben lastbasiert hart, weil es dort keine Uhrzeit gibt, an der sich „passt“ prüfen ließe.
- **Lokale Garantie für P1:** Passt ein P1 in eine Lücke und hat nach der Nachfrage weder Block noch Move, legt Tagwerk selbst einen Vorschlag in die erste passende Lücke („von Tagwerk ergänzt“). Damit hängt die Kernforderung nicht am Modell.

## 4. Anweisungen an die KI

Feste Reihenfolge, als nummerierte Regeln:
1. Nutze nur `freeSlots`; rechne keine eigenen Lücken.
2. Zuerst Blöcke für Aufgaben, die schon auf dem Tag liegen; danach die übrigen in Listenreihenfolge. Abweichen nur mit Grund.
3. **Jeder P1, der in eine freie Lücke passt, bekommt einen Block.** Passt keiner, steht er mit konkretem Grund in `unscheduled`.
4. Ein Block je Aufgabe, Dauer = Aufwand (sonst Schätzung in `estimates`), mindestens 15 min.
5. Ist es zu voll, in dieser Reihenfolge: (a) Aufgaben mit P3/ohne Priorität, deren Fälligkeit nach dem Zieltag liegt, auf einen Zieltag verschieben; nie P1 oder Wichtiges; (b) **längerer Tag, wenn danach noch Aufgaben mit P1 oder mit Fälligkeit/Anker bis übermorgen (Woche/Monat: im Zeitraum) nicht passen** – bis 10 h ohne Notfall-Begründung, in Schritten von 30 min; (c) 12 h oder freier Tag nur, wenn eine Frist innerhalb von 24 h sonst reißt, und der Grund sagt das; (d) Rest in `unscheduled`.
6. Ist Luft, ziehe Aufgaben aus der Auffüllung vor und sage das.
7. `summary` immer, ein bis zwei Sätze: was heute zählt, was wartet, ob vorgearbeitet wird.

Die bisherige Bedingung „nur wenn wichtige Aufgaben sonst ihre Frist verpassen“ entfällt zugunsten von 5b.

## 5. Anzeige

Blöcke (W1) und Verlängerungen (AO1, AR1, FT1) bleiben wie freigegeben. Neu ist nur das Verschieben, nach demselben Muster: gestrichelt, ✓/✕, entschieden wird am Herkunftstag.

- **Tag:** Die Aufgabe liegt im Panel „Ohne Uhrzeit“; dort wird ihre Zeile gestrichelt mit Kapsel „↷ Fr 20.“ und ✓/✕. Die Leiste nennt nur noch die Summe („↷ 3 verschieben · 1 h 30 entlastet“). Im Kapazitätsbalken ist der entlastete Anteil schraffiert. Nach dem Planen scrollt das Raster zum ersten Vorschlag; das Panel klappt auf, wenn es Moves enthält.
- **Woche:** Herkunftstag: Zeile abgeblendet mit „↷ nach Fr 20.“ und ✓/✕. Zieltag: gestrichelte Geisterzeile „↷ von Mi 18.“ ohne eigene Knöpfe; Antippen springt zur Herkunft.
- **Monat:** Zelle des Herkunftstags mit „↷“ (teilt den Platz von ◷ oben links; bei beidem nur ◷), Zieltag mit schraffiertem Balkenanteil; Tagesliste wie in der Woche.

```
Tag · Panel „Ohne Uhrzeit“            Woche
┌──────────────────────────────┐      Mi 18.  50 min zu viel → 0
│ ≡ Kapitel 2 gliedern    2 h  │       ⋮⋮ Kapitel 2 gliedern   2 h
│┄≡ Angebot nachfassen 30 min ┄│       ┄ Angebot nachfassen ↷ nach Fr 20. ✓ ✕
│┄   ↷ Fr 20.            ✓  ✕ ┄│      Fr 20.  5 h frei → 4 h 30
└──────────────────────────────┘       ┄ ↷ von Mi 18. · Angebot nachfassen ┄
```

**Empfehlung:** ohne weiteres HTML-Mockup umsetzen; die Bausteine sind freigegeben.

## 6. Feinabstimmung

- **Einstellungen (wenige):** „Vorarbeiten, wenn Luft ist“ (an/aus, Standard an); „Längere Tage vorschlagen“ (nie / bei Fristen und P1 / nur im Notfall, Standard Mitte). Standarddauer und Puffer gibt es schon.
- **Konstanten an einer Stelle:** Fenster, Faktoren, Mindest-/Höchstzahlen, 14-Tage-Grenze für Überfälliges, P1-Obergrenze, Zahl der Zieltage, Grenzen aus `WorkdayLimits`.
- **Protokoll auf dem Gerät** (Ringspeicher der letzten 50 Läufe, sichtbar unter Einstellungen › Diagnose, nur Zahlen, keine Titel oder IDs): Zeitraum; Kandidaten gesamt, Kern, Auffüllung und erreichte Stufe, gekürzt; Budget und freie Minuten; Größe der Eingabe in Zeichen; Modell, Dauer, Nachfrage ja/nein; Vorschläge je Art; Verstöße je Grund (erste und zweite Antwort); P1 mit passender Lücke ohne Block; lokal ergänzte Blöcke; Überbuchung vorher/nachher; übernommen/verworfen je Art.
- **Woran wir drehen:** viele Verstöße `overCapacity` → Regel 3 prüfen; viele lokal ergänzte P1 → Anweisungen schärfen; viele verworfene Vorschläge aus der Auffüllung → Faktor senken; häufig „gekürzt“ → Fenster verkleinern.

## 7. Offene Fragen

1. **Woche = gezeigte Kalenderwoche ab heute oder gleitend 7 Tage?** Empfehlung: gezeigter Zeitraum, weil die Vorschläge dort angezeigt werden; bleiben weniger als zwei Arbeitstage, bietet die Leiste „Nächste Woche planen“ an. Fälligkeitsfenster zählen immer ab heute.
2. **Zieltage: die nächsten zwei Kalendertage oder Arbeitstage?** Empfehlung: Arbeitstage (innerhalb von höchstens fünf Kalendertagen), sonst gibt es am Freitag kein Ziel.
3. **P1 ohne nahe Frist:** immer Kandidat für heute und Grund für einen längeren Tag bis 10 h? Empfehlung: ja für beides; 12 h und freie Tage bleiben an eine Frist gebunden.
4. **Darf Tagwerk einen passenden P1 selbst einplanen, wenn die KI es zweimal nicht tut?** Empfehlung: ja, gekennzeichnet.
5. **Alte überfällige Aufgaben (über 14 Tage, P3/ohne) aus dem KI-Kontext nehmen und nur zählen?** Empfehlung: ja, mit Hinweis „37 ältere überfällige – aufräumen“ in der Zusammenfassung.

## 8. Entscheidungen des Nutzers (2026-11-18)

- Vorschlag freigegeben, mit einer Änderung: **Überfällige gehen immer in den Kern**, unabhängig von Alter und Priorität. Sie zählen als heute fällig und stehen vorne (Priorität, dann Alter). Übersteigt der Kern die Höchstzahl, wird vom Ende gekürzt und die Zahl als `omittedCount` mitgeschickt; die Einschätzung nennt sie.
- Fragen 1–3 wie empfohlen: Woche = gezeigte Kalenderwoche ab heute; Zieltage = die nächsten 2 Arbeitstage (höchstens 5 Kalendertage); P1 ohne nahe Frist ist immer Kandidat und darf einen längeren Tag bis 10 h begründen.
- Frage 4 (lokale P1-Ergänzung): umgesetzt wie empfohlen, gekennzeichnet; Frage 5 entfällt durch die Änderung oben.
