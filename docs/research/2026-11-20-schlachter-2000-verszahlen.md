# Kapitel- und Verszahlen der Schlachter 2000 (BS1, BV3a)

Stand: 22.11.2026. Gehört zu Strang BS (Bible Study) der Designgruppe 2 (#188). Erzeugt die Tabelle für `BibleVerseCounts`.

## 1. Ergebnis in Kürze

- **Die Tabelle ist vorläufig und für die Schlachter 2000 nicht belegt.** Sie enthält die **deutsche (Luther-)Zählung**: 66 Bücher, 1189 Kapitel, 31.172 Verse. Das ist die Zählung, die der Nutzer als führend festgelegt hat (Psalmüberschriften zählen als Vers, Joel mit vier, Maleachi mit drei Kapiteln).
- **Es gibt keine rechtlich saubere, maschinenlesbare Quelle für die Schlachter 2000 selbst.** Die beiden Online-Ausgaben (ERF Bibleserver, BibleGateway) untersagen automatisches Auslesen (Abschnitt 3). Ein offener Datensatz der Ausgabe 2000 wurde nicht gefunden.
- **Die Zählung der Schlachter 2000 weicht voraussichtlich an einzelnen Stellen von dieser Tabelle ab** (Abschnitt 6: 4. Mose, Apostelgeschichte 19). Das ist ein Hinweis, kein Beleg. Verbindlich lässt es sich nur mit der gedruckten Ausgabe klären.
- **Es gibt keine zweite unabhängige Quelle** (Abschnitt 4). Nach der Regel des Plans (Schritt 2) entscheidet die Hauptsitzung, ob eine Stichprobe von mindestens 40 Kapiteln gegen die gedruckte Ausgabe genügt. Die Liste dafür steht in Abschnitt 6.
- Die Regeln aus BS2 (nächster Vers, Ende, Buchende) hängen nicht an einzelnen Zahlen; sie lesen sie nur aus der Tabelle. Eine Korrektur der Tabelle ändert nur die JSON-Datei und die Prüfsumme.

## 2. Quellen und Abrufdatum

Alle Dateien wurden am 22.11.2026 geladen. Aus ihnen sind **nur Zahlen** entnommen (höchste Versnummer je Kapitel, Lücken in der Versfolge), kein Bibeltext. Die Zahlendateien liegen unter `docs/research/data/`; sie entstehen mit `scripts/extract-verse-counts.py`.

| Kurzname | Quelle | Lizenz laut Quelle | SHA-256 der Eingabedatei | Kapitel / Verse |
|---|---|---|---|---|
| `luther-1545-bolsinger` (**Grundlage der Tabelle**) | scrollmapper/bible_databases, `formats/json/GerBoLut.json` (Luther 1545, Bolsinger, moderne Rechtschreibung), Stand des Repositories `59b18c5af5845728c275d5b7178ad0d024172b1f` vom 24.10.2026 | Public Domain (README der Quelle); Repository MIT | `01f975f34328acdaa245db87de56f3f66b7e44767587e43402e59b9e4b32e5b9` | 1189 / 31.172 |
| `textbibel-1906` | dasselbe Repository, `GerTextbibel.json` (Textbibel 1906) | Public Domain | `bcf6ffc368875ad5dd5dfe25ad094dc0c71076c85eb9067309720b71309ba615` | 1189 / 31.172 |
| `schlachter-1951` | dasselbe Repository, `GerSch.json` (Schlachter 1951) | „Copyrighted; free non-commercial distribution“ (README der Quelle) | `f784c4a5c5842df02aa1ee25d8d6eb2a11c93398b607351f4b5b3c1d7263cc85` | 1189 / 31.172 |
| `elberfelder-1905` | dasselbe Repository, `GerElb1905.json` | Public Domain | `c3bc2115750db82fb7c9ab650fcd05e22251d29fbb1c7870db6e81c6a1b54557` | 1189 / 31.104 |
| `english-kjv` (englische Seite) | dasselbe Repository, `KJV.json` (King James Version 1769) | Datensatz „GPL“ (README), Text gemeinfrei | `f0b09dc49dfb97bb84f03aae1fbf026485048c3cab31a7a41017e2d86ac1d11c` | 1189 / 31.102 |
| `ebible-deu1951` | eBible.org, `https://ebible.org/Scriptures/deu1951_usfm.zip` (Schlachter 1951, USFM), Archiv-SHA-256 `c61ecc937a33fb8d9946ba49169bcb6648d4774a4b8a639ba1daac86c7614076`; Prüfsumme in der letzten Spalte über die verketteten USFM-Dateien in Kanonreihenfolge | CC BY 4.0, © Genfer Bibelgesellschaft (Urheberangabe der Quelle) | `afe61dbb6d792113dadbe895881c41b113d81587f18f7b9b2fa59def2b0d2d61` | 1189 / 31.102 |

Die Tabelle der App (`app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/schlachter2000-verses.json`) wird aus `luther-1545-bolsinger` erzeugt. Ihre Prüfsumme:

```
SHA-256 037874dfabbd3694ad9b3f3384653f1c7c2ac8ec7b876d8f51a1e614b9e37e08
```

Der Test `resource_checksumMatchesDocumentation` vergleicht die ausgelieferte Datei mit diesem Wert. Wer die Tabelle ändert, ändert Dokument und Test gemeinsam.

## 3. Warum nicht die Online-Ausgaben der Schlachter 2000

1. **ERF Bibleserver** (`bibleserver.com`, Übersetzung SLT = Schlachter 2000, © Genfer Bibelgesellschaft). Das Impressum (`https://www.bibleserver.com/imprint`, abgerufen am 22.11.2026) sagt: Die meisten Bibelübersetzungen seien urheberrechtlich geschützt und dürften „nicht heruntergeladen, automatisch ausgelesen oder außerhalb von bibleserver.com digital verarbeitet oder weitergegeben werden“.
2. **BibleGateway** (Version SCH2000). Die Nutzungsbedingungen (`https://www.biblegateway.com/legal/terms/`, abgerufen am 22.11.2026) untersagen, „technology or any automated system such as scripts or bots“ zu nutzen, um Daten aus dem Dienst zu sammeln. Die `robots.txt` erlaubt das Abrufen mit Wartezeit, ersetzt aber die Bedingungen nicht.
3. Weitere Suche (22.11.2026): Ein veröffentlichter Versifikationsdatensatz oder ein offenes Modul der Schlachter 2000 wurde nicht gefunden. Gefunden wurden nur die Schlachter 1951 (eBible.org, scrollmapper) und allgemeine Versifikationstabellen (STEPBible TVTMS u. a.), die keine Ausgabe-Zählung der Schlachter 2000 enthalten.

**Hinweis zum Ablauf (Offenlegung).** Bevor das Impressum und die Bedingungen gelesen waren, lief ein Skript mit Zahlenabruf auf beiden Seiten an: etwa 380 Kapitelseiten von Bibleserver (1. bis 5. Mose, Matthäus bis 1. Korinther) und etwa 30 Seiten von BibleGateway (1. bis 3. Mose), dazu einzelne Prüfabrufe (Psalm 51, Joel, Maleachi und weitere). Nach dem Fund der Bedingungen wurde alles gestoppt, die zwischengespeicherten Seiten gelöscht, das Abrufskript entfernt, und **nichts davon ist in der Tabelle, in den Zahlendateien oder im Repository**. Die Beobachtung dieses Abrufs wird in Abschnitt 6 nur als Hinweis auf Prüfstellen wiedergegeben, nicht als Quelle.

## 4. Gegenprobe: Warum die vorhandenen Quellen keine zweite Quelle sind

`scripts/check-verse-table.py` vergleicht die Tabelle mit allen Zahlendateien.

- `luther-1545-bolsinger`, `textbibel-1906` und `schlachter-1951` (scrollmapper) haben **in allen 1189 Kapiteln dieselben Zahlen**, obwohl es drei verschiedene Ausgaben von 1545 bis 1951 sind. Das spricht dafür, dass der Datensatz eine **einheitliche deutsche Zählung** auf alle drei Ausgaben legt, nicht dass jede Ausgabe einzeln gezählt wurde. Die drei Dateien sind deshalb **eine** Quelle, keine Gegenprobe.
- `elberfelder-1905` (scrollmapper) und `ebible-deu1951` (eBible.org) haben dagegen die **englische Zählung** (31.102 Verse; `ebible-deu1951` ist von der KJV in keinem Kapitel verschieden, `elberfelder-1905` in zwei Stellen: 3. Johannes 1 und Offenbarung 12). Die Elberfelder Übersetzung zählt in Wirklichkeit Psalmüberschriften als Vers; der Datensatz hat also ebenfalls vereinheitlicht.
- **Widerspruch zwischen zwei Quellen derselben Ausgabe:** Die Schlachter 1951 hat in `schlachter-1951` (scrollmapper) 31.172 Verse und in `ebible-deu1951` 31.102. Beide Datensätze geben also je ein Schema vor, nicht den Druck.
- Folge: **Aus keiner dieser Dateien lässt sich die Zählung der gedruckten Schlachter 2000 ablesen.** Sie belegen nur, dass es zwei übliche Schemata gibt (deutsch, 31.172 Verse; englisch, 31.102 Verse) und an welchen Stellen sie sich unterscheiden.

## 5. Tabelle

Kapitel und Verse je Buch in der deutschen Zählung (Spalten 3 und 4) im Vergleich zur KJV (Spalten 5 und 6). Die Verszahl je Kapitel steht in der JSON-Datei.

| Nr. | Buch | Kapitel | Verse | Kapitel (KJV) | Verse (KJV) |
|---:|---|---:|---:|---:|---:|
| 1 | 1. Mose | 50 | 1533 | 50 | 1533 |
| 2 | 2. Mose | 40 | 1213 | 40 | 1213 |
| 3 | 3. Mose | 27 | 859 | 27 | 859 |
| 4 | 4. Mose | 36 | 1289 | 36 | 1288 |
| 5 | 5. Mose | 34 | 959 | 34 | 959 |
| 6 | Josua | 24 | 658 | 24 | 658 |
| 7 | Richter | 21 | 618 | 21 | 618 |
| 8 | Rut | 4 | 85 | 4 | 85 |
| 9 | 1. Samuel | 31 | 811 | 31 | 810 |
| 10 | 2. Samuel | 24 | 695 | 24 | 695 |
| 11 | 1. Könige | 22 | 817 | 22 | 816 |
| 12 | 2. Könige | 25 | 720 | 25 | 719 |
| 13 | 1. Chronik | 29 | 943 | 29 | 942 |
| 14 | 2. Chronik | 36 | 822 | 36 | 822 |
| 15 | Esra | 10 | 280 | 10 | 280 |
| 16 | Nehemia | 13 | 406 | 13 | 406 |
| 17 | Ester | 10 | 167 | 10 | 167 |
| 18 | Hiob | 42 | 1070 | 42 | 1070 |
| 19 | Psalmen | 150 | 2527 | 150 | 2461 |
| 20 | Sprüche | 31 | 915 | 31 | 915 |
| 21 | Prediger | 12 | 222 | 12 | 222 |
| 22 | Hohelied | 8 | 117 | 8 | 117 |
| 23 | Jesaja | 66 | 1291 | 66 | 1292 |
| 24 | Jeremia | 52 | 1364 | 52 | 1364 |
| 25 | Klagelieder | 5 | 154 | 5 | 154 |
| 26 | Hesekiel | 48 | 1273 | 48 | 1273 |
| 27 | Daniel | 12 | 357 | 12 | 357 |
| 28 | Hosea | 14 | 197 | 14 | 197 |
| 29 | Joel | 4 | 73 | 3 | 73 |
| 30 | Amos | 9 | 146 | 9 | 146 |
| 31 | Obadja | 1 | 21 | 1 | 21 |
| 32 | Jona | 4 | 48 | 4 | 48 |
| 33 | Micha | 7 | 105 | 7 | 105 |
| 34 | Nahum | 3 | 47 | 3 | 47 |
| 35 | Habakuk | 3 | 56 | 3 | 56 |
| 36 | Zefanja | 3 | 53 | 3 | 53 |
| 37 | Haggai | 2 | 38 | 2 | 38 |
| 38 | Sacharja | 14 | 211 | 14 | 211 |
| 39 | Maleachi | 3 | 55 | 4 | 55 |
| 40 | Matthäus | 28 | 1071 | 28 | 1071 |
| 41 | Markus | 16 | 678 | 16 | 678 |
| 42 | Lukas | 24 | 1151 | 24 | 1151 |
| 43 | Johannes | 21 | 879 | 21 | 879 |
| 44 | Apostelgeschichte | 28 | 1006 | 28 | 1007 |
| 45 | Römer | 16 | 433 | 16 | 433 |
| 46 | 1. Korinther | 16 | 437 | 16 | 437 |
| 47 | 2. Korinther | 13 | 256 | 13 | 257 |
| 48 | Galater | 6 | 149 | 6 | 149 |
| 49 | Epheser | 6 | 155 | 6 | 155 |
| 50 | Philipper | 4 | 104 | 4 | 104 |
| 51 | Kolosser | 4 | 95 | 4 | 95 |
| 52 | 1. Thessalonicher | 5 | 89 | 5 | 89 |
| 53 | 2. Thessalonicher | 3 | 47 | 3 | 47 |
| 54 | 1. Timotheus | 6 | 113 | 6 | 113 |
| 55 | 2. Timotheus | 4 | 83 | 4 | 83 |
| 56 | Titus | 3 | 46 | 3 | 46 |
| 57 | Philemon | 1 | 25 | 1 | 25 |
| 58 | Hebräer | 13 | 303 | 13 | 303 |
| 59 | Jakobus | 5 | 108 | 5 | 108 |
| 60 | 1. Petrus | 5 | 105 | 5 | 105 |
| 61 | 2. Petrus | 3 | 61 | 3 | 61 |
| 62 | 1. Johannes | 5 | 105 | 5 | 105 |
| 63 | 2. Johannes | 1 | 13 | 1 | 13 |
| 64 | 3. Johannes | 1 | 15 | 1 | 14 |
| 65 | Judas | 1 | 25 | 1 | 25 |
| 66 | Offenbarung | 22 | 405 | 22 | 404 |

Summen: Altes Testament 23.215 Verse, Neues Testament 7.957 Verse, zusammen 31.172 Verse in 1189 Kapiteln. Lücken in der Versfolge (ausgelassene Verse innerhalb eines Kapitels) enthält keine der Quellen.

## 6. Unterschiede zur englischen Zählung und offene Stellen

Verglichen wird die Tabelle (deutsche Zählung) mit der KJV 1769 aus `scrollmapper/bible_databases`, Datei `KJV.json` (Prüfsumme in Abschnitt 2). Insgesamt weichen 62 Psalmen und 79 Kapitel anderer Bücher ab; dazu kommt die andere Kapiteleinteilung von Joel und Maleachi.

### 6.1 Psalmen mit Überschrift

In der deutschen Zählung steht die Überschrift als Vers 1 (oder Verse 1 und 2). Psalm 51 hat deshalb 21 Verse statt 19, Psalm 3 hat 9 statt 8, Psalm 60 hat 14 statt 12.

| Psalm | deutsch | KJV | Differenz |
|---:|---:|---:|---:|
| 3 | 9 | 8 | +1 |
| 4 | 9 | 8 | +1 |
| 5 | 13 | 12 | +1 |
| 6 | 11 | 10 | +1 |
| 7 | 18 | 17 | +1 |
| 8 | 10 | 9 | +1 |
| 9 | 21 | 20 | +1 |
| 12 | 9 | 8 | +1 |
| 18 | 51 | 50 | +1 |
| 19 | 15 | 14 | +1 |
| 20 | 10 | 9 | +1 |
| 21 | 14 | 13 | +1 |
| 22 | 32 | 31 | +1 |
| 30 | 13 | 12 | +1 |
| 31 | 25 | 24 | +1 |
| 34 | 23 | 22 | +1 |
| 36 | 13 | 12 | +1 |
| 38 | 23 | 22 | +1 |
| 39 | 14 | 13 | +1 |
| 40 | 18 | 17 | +1 |
| 41 | 14 | 13 | +1 |
| 42 | 12 | 11 | +1 |
| 44 | 27 | 26 | +1 |
| 45 | 18 | 17 | +1 |
| 46 | 12 | 11 | +1 |
| 47 | 10 | 9 | +1 |
| 48 | 15 | 14 | +1 |
| 49 | 21 | 20 | +1 |
| 51 | 21 | 19 | +2 |
| 52 | 11 | 9 | +2 |
| 53 | 7 | 6 | +1 |
| 54 | 9 | 7 | +2 |
| 55 | 24 | 23 | +1 |
| 56 | 14 | 13 | +1 |
| 57 | 12 | 11 | +1 |
| 58 | 12 | 11 | +1 |
| 59 | 18 | 17 | +1 |
| 60 | 14 | 12 | +2 |
| 61 | 9 | 8 | +1 |
| 62 | 13 | 12 | +1 |
| 63 | 12 | 11 | +1 |
| 64 | 11 | 10 | +1 |
| 65 | 14 | 13 | +1 |
| 67 | 8 | 7 | +1 |
| 68 | 36 | 35 | +1 |
| 69 | 37 | 36 | +1 |
| 70 | 6 | 5 | +1 |
| 75 | 11 | 10 | +1 |
| 76 | 13 | 12 | +1 |
| 77 | 21 | 20 | +1 |
| 80 | 20 | 19 | +1 |
| 81 | 17 | 16 | +1 |
| 83 | 19 | 18 | +1 |
| 84 | 13 | 12 | +1 |
| 85 | 14 | 13 | +1 |
| 88 | 19 | 18 | +1 |
| 89 | 53 | 52 | +1 |
| 92 | 16 | 15 | +1 |
| 102 | 29 | 28 | +1 |
| 108 | 14 | 13 | +1 |
| 140 | 14 | 13 | +1 |
| 142 | 8 | 7 | +1 |

### 6.2 Joel und Maleachi (andere Kapiteleinteilung)

| Buch | deutsch | KJV |
|---|---|---|
| Joel | 4 Kapitel: 20, 27, 5, 21 Verse (zusammen 73) | 3 Kapitel: 20, 32, 21 Verse (zusammen 73) |
| Maleachi | 3 Kapitel: 14, 17, 24 Verse (zusammen 55) | 4 Kapitel: 14, 17, 18, 6 Verse (zusammen 55) |

Joel 3,1–5 (deutsch) entspricht Joel 2,28–32 (KJV), Joel 4 (deutsch) entspricht Joel 3 (KJV). Maleachi 3,19–24 (deutsch) entspricht Maleachi 4,1–6 (KJV).

### 6.3 Weitere Kapitel

| Stelle | deutsch | KJV |
|---|---:|---:|
| 1. Mose 31 | 54 | 55 |
| 1. Mose 32 | 33 | 32 |
| 2. Mose 7 | 29 | 25 |
| 2. Mose 8 | 28 | 32 |
| 2. Mose 21 | 37 | 36 |
| 2. Mose 22 | 30 | 31 |
| 3. Mose 5 | 26 | 19 |
| 3. Mose 6 | 23 | 30 |
| 4. Mose 16 | 35 | 50 |
| 4. Mose 17 | 28 | 13 |
| 4. Mose 25 | 19 | 18 |
| 4. Mose 29 | 39 | 40 |
| 4. Mose 30 | 17 | 16 |
| 5. Mose 12 | 31 | 32 |
| 5. Mose 13 | 19 | 18 |
| 5. Mose 22 | 29 | 30 |
| 5. Mose 23 | 26 | 25 |
| 5. Mose 28 | 69 | 68 |
| 5. Mose 29 | 28 | 29 |
| 1. Samuel 21 | 16 | 15 |
| 1. Samuel 23 | 28 | 29 |
| 1. Samuel 24 | 23 | 22 |
| 2. Samuel 18 | 32 | 33 |
| 2. Samuel 19 | 44 | 43 |
| 1. Könige 4 | 20 | 34 |
| 1. Könige 5 | 32 | 18 |
| 1. Könige 22 | 54 | 53 |
| 2. Könige 11 | 20 | 21 |
| 2. Könige 12 | 22 | 21 |
| 2. Könige 15 | 39 | 38 |
| 1. Chronik 5 | 41 | 26 |
| 1. Chronik 6 | 66 | 81 |
| 1. Chronik 12 | 41 | 40 |
| 2. Chronik 1 | 18 | 17 |
| 2. Chronik 2 | 17 | 18 |
| 2. Chronik 13 | 23 | 22 |
| 2. Chronik 14 | 14 | 15 |
| Nehemia 3 | 38 | 32 |
| Nehemia 4 | 17 | 23 |
| Nehemia 9 | 37 | 38 |
| Nehemia 10 | 40 | 39 |
| Hiob 40 | 32 | 24 |
| Hiob 41 | 26 | 34 |
| Prediger 4 | 17 | 16 |
| Prediger 5 | 19 | 20 |
| Hohelied 6 | 12 | 13 |
| Hohelied 7 | 14 | 13 |
| Jesaja 8 | 23 | 22 |
| Jesaja 9 | 20 | 21 |
| Jesaja 64 | 11 | 12 |
| Jeremia 8 | 23 | 22 |
| Jeremia 9 | 25 | 26 |
| Hesekiel 20 | 44 | 49 |
| Hesekiel 21 | 37 | 32 |
| Daniel 3 | 33 | 30 |
| Daniel 4 | 34 | 37 |
| Daniel 5 | 30 | 31 |
| Daniel 6 | 29 | 28 |
| Hosea 1 | 9 | 11 |
| Hosea 2 | 25 | 23 |
| Hosea 11 | 11 | 12 |
| Hosea 12 | 15 | 14 |
| Hosea 13 | 15 | 16 |
| Hosea 14 | 10 | 9 |
| Joel 2 | 27 | 32 |
| Joel 3 | 5 | 21 |
| Jona 1 | 16 | 17 |
| Jona 2 | 11 | 10 |
| Micha 4 | 14 | 13 |
| Micha 5 | 14 | 15 |
| Nahum 1 | 14 | 15 |
| Nahum 2 | 14 | 13 |
| Sacharja 1 | 17 | 21 |
| Sacharja 2 | 17 | 13 |
| Maleachi 3 | 24 | 18 |
| Apostelgeschichte 19 | 40 | 41 |
| 2. Korinther 13 | 13 | 14 |
| 3. Johannes 1 | 15 | 14 |
| Offenbarung 12 | 18 | 17 |

### 6.4 Offen: Stellen, an denen die Schlachter 2000 abweichen kann

Die Tabelle ist ein Schema, nicht die Ausgabe. **Die Beobachtung aus dem gestoppten Abruf (Abschnitt 3) deutet darauf hin**, dass die Schlachter 2000 in Joel, Maleachi und den Psalmen der deutschen Zählung folgt (Joel mit vier, Maleachi mit drei Kapiteln, Psalm 51 mit 21 Versen), aber in 4. Mose (Summe 1288 statt 1289) und Apostelgeschichte (Summe 1007 statt 1006) der englischen. In den zehn weiteren damals gelesenen Büchern (1. bis 3. Mose, 5. Mose, Matthäus bis Johannes, Römer, 1. Korinther) stimmten Kapitel- und Verssumme mit der Tabelle überein. Das ist **kein Beleg** und wurde nicht in die Tabelle übernommen.

Für die Prüfung mit der gedruckten Ausgabe schlägt dieses Dokument die folgenden Stellen vor (Verszahl nachzählen und mit „deutsch“ und „KJV“ oben vergleichen). Die Liste ist aus den Unterschieden abgeleitet; die Punkte 1 bis 3 sind die wahrscheinlichsten Abweichungen.

1. 4. Mose 16 (deutsch 35, KJV 50), 4. Mose 17 (28 / 13), 4. Mose 25, 29, 30
2. Apostelgeschichte 19 (40 / 41)
3. 2. Korinther 13 (13 / 14), 3. Johannes 1 (15 / 14), Offenbarung 12 (18 / 17)
4. Psalm 3, 18, 51, 60 und ein Psalm ohne Überschrift (zum Beispiel 119, 176 Verse in beiden Zählungen)
5. Joel: Kapitelzahl (vier oder drei) und Joel 3 (5 oder 21 Verse); Maleachi: Kapitelzahl (drei oder vier) und letztes Kapitel
6. Weitere Kapitel aus 6.3 zur Auswahl: 1. Mose 31 und 32; 2. Mose 7, 8, 21, 22; 3. Mose 5, 6; 5. Mose 12, 13, 22, 23, 28, 29; 1. Samuel 21, 23, 24; 2. Samuel 18, 19; 1. Könige 4, 5, 22; 1. Chronik 5, 6, 12; Nehemia 3, 4, 9, 10; Hiob 40, 41; Jesaja 8, 9; Hesekiel 20, 21; Daniel 3, 4; Hosea 1, 2, 12, 13, 14

Das sind deutlich mehr als 40 Kapitel. Ergibt die Zählung der gedruckten Ausgabe an diesen Stellen überall die Zahl der Tabelle, ist die Tabelle für die Schlachter 2000 hinreichend belegt. Jede Abweichung wird einzeln als Änderung der JSON-Datei eingetragen (mit Prüfsumme, Testwert und diesem Dokument).

## 7. Lizenz

- Die Tabelle enthält **nur Zahlen**, keinen Bibeltext. Die Verszählung einer Ausgabe ist eine Tatsache über den Aufbau des Textes, nicht dessen Wortlaut; das Risiko wird als gering eingeschätzt. Das ist eine fachliche Einschätzung, keine Rechtsberatung.
- Die Schlachter 2000 ist © Genfer Bibelgesellschaft. Es werden weder Text noch Auszüge übernommen.
- Die Grundlage der Tabelle (Luther 1545 Bolsinger, Textbibel 1906) ist laut README der Quelle gemeinfrei. Aus `GerSch.json` (Schlachter 1951; „free non-commercial distribution“), `KJV.json` (Datensatz unter GPL) und `deu1951_usfm.zip` (CC BY 4.0, Urheberangabe: © 1951 Genfer Bibelgesellschaft, Quelle eBible.org) werden ebenfalls nur Zahlen für den Vergleich gespeichert.
- Die Web-Ausgaben der Schlachter 2000 wurden nicht als Quelle verwendet (Abschnitt 3).

## 8. Nachvollziehen

```
# Eingaben laden (Beispiel; die Dateien liegen nicht im Repository)
gh api -H "Accept: application/vnd.github.raw" repos/scrollmapper/bible_databases/contents/formats/json/GerBoLut.json > GerBoLut.json
python3 -I scripts/extract-verse-counts.py counts --input GerBoLut.json --out docs/research/data/luther-1545-bolsinger.json
python3 -I scripts/extract-verse-counts.py table --input docs/research/data/luther-1545-bolsinger.json \
    --out app/Packages/TagwerkCore/Sources/TagwerkCore/Resources/schlachter2000-verses.json
# prüfen
python3 -I scripts/check-verse-table.py --reference KJV --reference Schlachter1951-eBible
```

## 9. Entscheidung, die offen bleibt

Ob eine **vorläufige, unbelegte Tabelle** in `main` darf, entscheidet die Hauptsitzung oder der Nutzer, nicht der Umsetzer:

- **A:** Tabelle mit dem Vermerk „vorläufig“ übernehmen und die Stichprobe aus 6.4 mit der gedruckten Ausgabe nachholen (Korrekturen sind eine Änderung an JSON, Prüfsumme und Dokument).
- **B:** Gezählte Verszahlen bei der Genfer Bibelgesellschaft anfragen (lizenziert) und die Tabelle daraus erzeugen.
- **C:** Den Pull Request erst nach der Stichprobe zusammenführen.
