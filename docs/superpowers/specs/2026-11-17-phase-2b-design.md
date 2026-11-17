# Tagwerk – Phase 2b Design: Planen, Kalender und KI

Stand: 2026-11-17 · Status: **freigegeben am 2026-11-17** · Baut auf: `2026-11-17-tagwerk-design.md` (Hauptdesign), `2026-11-17-phase-2-design.md` (Phase 2, darin §7 und §8 für KI und Benachrichtigungen), `../spikes/2026-11-17-feasibility-results.md` (u. a. Nachtrag Function Calling). Mockups: `../mockups/2026-11-17-phase-2b-mockups.html` (freigegeben am 2026-11-17: a, b-A, c-A, d-A, e-A, f, g-A, h; je Bereich die grün markierte Empfehlung). Nachtrag nach der Geräteprüfung: `../mockups/2026-11-18-phase-2b-feedback-mockups.html` (freigegeben am 2026-11-17, siehe §13); wo er abweicht, gilt §13.

Dieser Nachtrag ersetzt für Phase 2b den bisherigen Plan „2b: KI-Tagesplan, Heute-Tab, Benachrichtigungen“ aus Phase 2 §11. Wo er dem Phase-2-Design widerspricht, gilt dieser Nachtrag.

## 1. Absicht und Warum

Tagwerk zeigt seit Phase 2a alle Aufgaben in einer Liste. Was fehlt, ist das eigentliche Planen: festlegen, **an welchem Tag** du was erledigst, über Tag, Woche und Monat, und dabei sehen, ob die Zeit reicht und welche **wichtigen Deadlines** näher rücken. Die KI (ChatGPT über dein Abo) soll dabei helfen, Pläne vorschlagen und überall in der App ansprechbar sein, auch zu einem einzelnen GitHub-Issue mit Kenntnis des Projekts. Zeitblöcke für Aufgaben legst du heute von Hand im Kalender an; künftig entstehen sie in Tagwerk und landen als echte Termine im Kalender.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Planungsbereich mit Ansichten **Tag**, **Woche**, **Monat**, umschaltbar. Tag mit Zeitleiste und Zeitblöcken; Woche und Monat verteilen Aufgaben auf Tage, ohne Uhrzeit.
- Pro Tag sichtbar: **freie Zeit** (Kapazität) und **wichtige Deadlines**.
- Planen per Ziehen **und** per KI („Tag/Woche/Monat planen“), Vorschläge einzeln oder mit „Alle übernehmen“ annehmen.
- Angenommene Zeitblöcke werden **echte Kalendertermine** in einem Kalender deiner Wahl, verknüpft mit der Aufgabe.
- **Verknüpfung Termin ↔ Aufgabe** mit Sprung in beide Richtungen: automatisch erkannt, von Hand gesetzt oder von der KI vorgeschlagen.
- **Wiederkehrender Aufwand** für wiederkehrende Erinnerungen (z. B. „Karteikarten“ täglich 3 h), pro Tag oder für alle anpassbar.
- **Gedrückthalten** einer Aufgabe: Aktionen mit einem Tipp, inklusive KI.
- **KI-Assistent** über einen schwebenden Knopf überall in der App, mit Kontext der aktuellen Ansicht und Funktionen zum Handeln.
- **Benachrichtigungen** und **Hintergrund-Refresh** wie in Phase 2 §8.

**Nicht-Ziele (2b)**
- Tags in Erinnerungen (EventKit bietet keine Schnittstelle; vom Nutzer zurückgestellt).
- Widget, Siri, Wochenrückblick (Phase 4); Ernährung und Training (Phase 3).
- Projects von Organisationen ohne Freigabe der OAuth-App.
- Eine zweite KI-Plattform neben ChatGPT als Standard. Die Claude-API bleibt Ausweichlösung nach Phase 2 §7.

**Anti-Ziele (Fehlschlag trotz funktionierender Technik)**
- Plan in Tagwerk und Kalender laufen auseinander (Daten-Drift, Hauptdesign §2).
- Die KI ändert etwas, ohne dass du es gesehen und bestätigt hast.
- Wichtige Deadlines gehen in der Wochen- oder Monatsansicht unter.
- Planen dauert länger als heute von Hand im Kalender.

## 3. Entscheidungen des Nutzers (2026-11-17)

| Thema | Entscheidung |
|---|---|
| Zweck Woche/Monat | Festlegen, an welchem Tag was erledigt wird; Deadlines im Blick behalten und hervorheben. |
| Planen | Beides verbinden: Ansicht mit Kapazität, Aufgaben per Ziehen auf Tage; „Woche/Monat planen“ lässt die KI auffüllen. Monat nur Tage, Uhrzeiten nur im Tag. |
| Wichtige Deadlines | P1-Aufgaben, Epic-Deadlines (GitHub), Termine aus konfigurierbaren **Deadline-Kalendern** (beim Nutzer „Uni“: Klausuren, Abgaben). Stehen besonders im Fokus. |
| Wiederkehrender Aufwand | In Tagwerk gespeichert; anpassbar für ein einzelnes Vorkommen oder alle. |
| KI und Datenschutz | Keine Rückfrage vor jeder Übertragung an OpenAI. Einmaliger Hinweis in der Einrichtung. Ohne deine Aktion gehen keine Daten an OpenAI (keine Hintergrundplanung). |
| KI-Vorschläge | Einzeln annehmen oder „Alle übernehmen“. |
| KI-Assistent | Schwebender Knopf überall; kennt den Kontext; handelt über Funktionen; jede Änderung als Aktionskarte bestätigen. Function Calling über das ChatGPT-Abo ist auf dem iPhone verifiziert. |
| Chat zum Issue | Kontext: Issue, Kommentare, Labels, Project-Felder, Nachbar-Issues in Project/Epic. Repo-Inhalte (README, Doku, Dateien, PRs) holt die KI auf Nachfrage per Funktion; die Anweisungen sagen ihr ausdrücklich, dass sie das kann. |
| Kalender | Tagwerk **schreibt** angenommene Zeitblöcke in den Kalender (hebt das Nicht-Ziel „Schreiben in den Kalender“ aus Phase 2 §1 auf). Erweitert in §13: Termine aller beschreibbaren Kalender lassen sich in Tagwerk anlegen, ändern und löschen. |
| Verknüpfung | Termin ↔ Aufgabe mit Sprung in beide Richtungen; automatisch erkannt, manuell, KI-Vorschlag. |
| Gedrückthalten | Heute, Morgen, Wochenende, Nächste Woche, Datum wählen, Erledigt, Löschen/Schließen, „Mit KI planen“, „Über diese Aufgabe sprechen“. Gestaltung mit Fable. |
| Ansatz | **A: Der Kalender ist die Quelle für Zeitblöcke** (siehe §4). |
| Aufteilung | Drei Pläne: 2b-1 Kalender & Planung, 2b-2 KI, 2b-3 Benachrichtigungen & Hintergrund. |

## 4. Ansätze

| Ansatz | Kern | Abwägung | Entscheidung |
|---|---|---|---|
| **A: Kalender ist die Quelle** | Ein angenommener Zeitblock ist ein Termin im Plan-Kalender mit Verweis auf die Aufgabe. In Tagwerk liegen nur Tageszuordnungen ohne Uhrzeit, Verknüpfungen und Aufwände. | Keine doppelte Datenhaltung; Änderungen im Apple-Kalender sieht Tagwerk sofort; Verknüpfung ergibt sich aus dem Termin. Tagwerk muss mit Terminen umgehen, die außerhalb geändert oder gelöscht werden. | **Gewählt** |
| B: Tagwerk ist die Quelle | Plan in SwiftData, Termine als Kopie im Kalender. | Volle Kontrolle, aber zwei Stände, die auseinanderlaufen (Anti-Ziel). | verworfen |
| C: Nur Tagwerk, kein Kalender | Wie Phase-2-Design. | Widerspricht der Entscheidung „explizit in den Kalender schreiben“. | verworfen |

## 5. Daten

### 5.1 Was wo liegt

| Daten | Ort | Hinweis |
|---|---|---|
| Zeitblöcke (Aufgabe zu einer Uhrzeit) | **Kalendertermin** im Plan-Kalender | Titel = Aufgabentitel (GitHub: `#<Nummer> <Titel>`), URL-Feld = `tagwerk://task/<quelle>/<id>` (Prozentkodierung der ID), Notiz enthält einen kurzen Hinweis „Geplant mit Tagwerk“. |
| Tageszuordnung ohne Uhrzeit (Woche/Monat) | SwiftData `DayAssignment` | `taskKey` (Quelle + ID), `day` (Jahr/Monat/Tag wie `DueDate`), `order`, `createdAt`. Eine Aufgabe hat höchstens eine Tageszuordnung. |
| Verknüpfungen Termin ↔ Aufgabe | SwiftData `EventTaskLink` | `eventKey` (`calendarItemExternalIdentifier`, bei Serien zusätzlich das Datum des Vorkommens), `taskKey`, `origin` (automatisch / manuell / KI-bestätigt). Für Tagwerk-eigene Blöcke ist das URL-Feld maßgeblich, `EventTaskLink` ist dann nicht nötig. |
| Abgelehnte Verknüpfungsvorschläge | SwiftData `DismissedLinkSuggestion` | damit derselbe Vorschlag nicht wiederkommt |
| Wiederkehrender Aufwand | SwiftData `RecurringEffort` | `reminderID` (Serie), `minutes`, plus `RecurringEffortOverride` (`reminderID`, `day`, `minutes`; 0 = an diesem Tag kein Aufwand). |
| Lokale Aufwandsschätzung für Erinnerungen | SwiftData `ReminderEstimate` | aus Phase 2 §4 („KI-Schätzung, editierbar, lokal“) |
| KI-Planvorschläge | SwiftData `PlanSuggestion` | bis zur Annahme/Ablehnung; angenommen → Termin bzw. `DayAssignment` |
| Chatverläufe | SwiftData `ChatThread`/`ChatMessage` | lokal, löschbar; pro Aufgabe ein Verlauf, plus ein allgemeiner |
| Einstellungen | `AppSettings` (additiv) | Plan-Kalender, Deadline-Kalender, Standard-Blockdauer, Arbeitszeit je Wochentag |
| Abweichende Arbeitszeit eines Tages | SwiftData `DayOverride` | `day`, `start`/`end` in Minuten oder `isOff`; gesetzt in der Tagesansicht oder per KI |

Alle neuen SwiftData-Attribute sind optional oder haben Standardwerte (Regel aus Plan 2a).

### 5.2 Kalender

- **Plan-Kalender:** In der Einrichtung bzw. den Einstellungen wählbar; Standard ist ein neu angelegter lokaler bzw. iCloud-Kalender „Tagwerk“ (je nachdem, welche Quelle verfügbar ist). Zeitblöcke landen in diesem Kalender; er ist auch der Standard für neue Termine (§13.10).
- **Deadline-Kalender:** Mehrfachauswahl in den Einstellungen, standardmäßig leer. Ganztägige und zeitgebundene Termine daraus gelten als wichtige Deadlines.
- Vor dem Ändern oder Löschen eines Termins (Tagwerk-Block oder fremder Termin) wird er neu geladen und verglichen (Konfliktschutz wie Phase 2 §5).

## 6. Regeln

### 6.1 Kapazität eines Tages

freie Zeit = Arbeitszeit − (Termine innerhalb der Arbeitszeit, ohne Plan-Kalender-Blöcke) − Mittagspause − Puffer je Termin − wiederkehrender Aufwand des Tages

Geplante Last = Summe der Aufwände der dem Tag zugeordneten Aufgaben + Plan-Blöcke des Tages. Aufgaben ohne Aufwand zählen mit einer Standarddauer (Einstellung, Standard 30 min) und sind als „geschätzt“ markiert. Ganztägige Termine verbrauchen keine Zeit. Die Anzeige zeigt Last gegenüber freier Zeit; Überbuchung wird hervorgehoben.

### 6.2 Wichtige Deadlines

Eine Deadline ist wichtig, wenn mindestens eins gilt:
1. Aufgabe mit Priorität P1 und Fälligkeit;
2. GitHub-Epic (Issue mit Label `epic`) mit „Due date“;
3. Termin aus einem Deadline-Kalender.

Sie erscheinen in allen Ansichten hervorgehoben (Gestaltung nach Mockups), im Tag als Kopfzeile, in Woche und Monat am Tag. Die KI-Planung behandelt sie als Anker: Aufgaben, die zu einer wichtigen Deadline gehören oder vor ihr fällig sind, werden rechtzeitig davor eingeplant.

### 6.3 Wiederkehrender Aufwand

- Gilt für Erinnerungen mit Wiederholungsregel. Der Aufwand belegt an jedem Tag, an dem die Serie ein Vorkommen hat, Zeit, bevor anderes verplant wird.
- Anpassen: „Nur dieser Tag“ (Override für das Datum) oder „Alle“ (neuer Grundwert **ab diesem Tag**; vergangene Tage behalten ihren Wert, Mockup g-A). Ein Override von 0 entfernt den Aufwand an diesem Tag.
- Erledigst du das Vorkommen vorzeitig, bleibt die Zeit dieses Tages belegt (die Kapazitätsanzeige zeigt es als erledigt).

### 6.4 Verknüpfung Termin ↔ Aufgabe

Reihenfolge der Erkennung:
1. URL-Feld `tagwerk://task/…` (Tagwerk-eigene Blöcke).
2. Manuelle Verknüpfung (`EventTaskLink`).
3. Automatisch: Titel enthält `#<Nummer>`, und genau ein zugewiesenes offenes Issue hat diese Nummer (bei mehreren Repos mit gleicher Nummer: kein automatischer Treffer, sondern Vorschlag). Oder: Titel stimmt nach Normalisierung (Groß/Klein, Leerzeichen) exakt mit genau einer offenen Erinnerung oder lokalen Aufgabe überein.
4. KI-Vorschlag: im Chat oder nach dem Planen; wird erst nach Bestätigung zu einer manuellen Verknüpfung.

Sprung: vom Termin (Tagesansicht, Termin-Detail in Tagwerk) zur Aufgabe und von der Aufgabe (Bearbeiten-Sheet, Gedrückthalten) zu verknüpften Terminen. Termine öffnet Tagwerk in einer eigenen Detailansicht; „Im Kalender öffnen“ führt in die Kalender-App.

### 6.5 Zeitblöcke schreiben

- Annahme eines Tagesplan-Vorschlags oder Ziehen einer Aufgabe auf eine Uhrzeit erzeugt einen Termin im Plan-Kalender.
- Verschiebst du die Aufgabe danach auf einen anderen Tag, fragt Tagwerk, ob der Block mitwandert oder gelöscht wird.
- Wird die Aufgabe erledigt, bleibt der Termin (er dokumentiert die Arbeit); erledigte Aufgaben erscheinen im Block als erledigt.
- Löscht oder verschiebt jemand den Termin im Kalender, übernimmt Tagwerk das ohne Rückfrage.

## 7. Ansichten

- **Tab-Struktur:** „Planen“ (Tag/Woche/Monat, Standard: Tag = heute) · „Aufgaben“ · „Einstellungen“. Endgültig nach Mockup-Freigabe.
- **Tag:** Kopfzeile mit ganztägigen Terminen und wichtigen Deadlines, Kapazität, Zeitleiste mit Terminen, Tagwerk-Blöcken und KI-Vorschlägen (lila gestrichelt, ✓/✕, Begründung aufklappbar, „Alle übernehmen“), Liste der dem Tag zugeordneten Aufgaben ohne Uhrzeit.
- **Woche:** sieben Tage mit Kapazität, Deadline-Markierungen und zugeordneten Aufgaben; Ziehen zwischen Tagen und aus einer Ablage „Nicht eingeplant“; „Woche planen“.
- **Monat:** Raster mit Last pro Tag und hervorgehobenen Deadlines; Tippen öffnet den Tag; „Monat planen“ verteilt auf Tage.
- **Gedrückthalten** (Aufgabe in allen Listen und Ansichten): Einplanen (Heute, Morgen, Wochenende, Nächste Woche, Datum wählen …), Fälligkeit verschieben …, Erledigt, Löschen bzw. „Als nicht geplant schließen“, „Mit KI planen“, „Über diese Aufgabe sprechen“, „Verknüpfte Termine“ (falls vorhanden).
- **KI-Knopf:** schwebend, in allen Tabs, verdeckt weder ＋ noch Tab-Leiste noch Wischbereiche (Platzierung nach Mockup).

## 8. KI

### 8.1 Anbieter

ChatGPTProvider mit allen Anforderungen aus Phase 2 §7 (Modellliste, `store:false`, `stream:true`, eine laufende Token-Erneuerung, Rücksprung-Server-Regeln, `nonce`-Prüfung, Fehlertexte). Anmeldung in der Einrichtung und in den Einstellungen. Ausweichlösung Claude-API nur manuell.

### 8.2 Planen

- Auslöser: „Tag planen“, „Woche planen“, „Monat planen“, „Mit KI planen“ (eine Aufgabe).
- Eingabe: Zeitraum, Arbeitszeit je Wochentag, freie Tage, Pausen, Puffer, Kapazität je Tag, Termine (Titel, Zeit, ganztägig, Deadline ja/nein), wiederkehrender Aufwand, offene Aufgaben (Quelle, Titel, Fälligkeit, Priorität, Aufwand, wichtig ja/nein, bereits zugeordnet), bestehende Plan-Blöcke. Obergrenze für die Zahl der Aufgaben: dem Umsetzenden überlassen (bisher 40 für einen Tag).
- Ausgabe per `text.format` json_schema (strict): Tag → `blocks` (taskId, start, minutes, reason); Woche/Monat → `assignments` (taskId, day, reason); jeweils `unscheduled`, `risks`, `estimates`.
- Lokale Prüfung vor der Anzeige (ohne KI): keine Überschneidung mit Terminen oder anderen Blöcken, innerhalb der Arbeitszeit, Pausen und Puffer eingehalten, Kapazität je Tag nicht überschritten, jede taskId existiert, kein Tag nach der Fälligkeit, wenn es eine gibt. Ungültige Vorschläge landen unter „nicht eingeplant“ mit Grund.
- Annahme einzeln oder „Alle übernehmen“: Tag → Termine im Plan-Kalender; Woche/Monat → `DayAssignment`.

### 8.3 Assistent und Chat zum Issue

- Ein Chat-Sheet, geöffnet über den KI-Knopf (Kontext: aktuelle Ansicht und Zeitraum) oder „Über diese Aufgabe sprechen“ (Kontext: diese Aufgabe; bei Issues zusätzlich Kommentare, Labels, Project-Felder, Nachbar-Issues in Project/Epic).
- Funktionen (Function Calling, verifiziert): `create_task`, `update_task`, `reschedule_task`, `complete_task`, `assign_to_day`, `create_time_block`, `link_event_to_task`, `set_day_hours`, `plan_period` sowie lesend `list_tasks`, `list_events`, `get_task`, und für GitHub `get_issue_comments`, `get_repository_readme`, `get_repository_file`, `search_repository`, `get_pull_request`.
- **Lesende Funktionen** laufen ohne Rückfrage. **Ändernde Funktionen** erscheinen als Aktionskarte im Chat; erst dein Tipp führt sie aus. Das Ergebnis geht als `function_call_output` an das Modell zurück.
- Die Anweisungen an das Modell nennen ausdrücklich, dass es bei GitHub-Issues weitere Repo-Inhalte per Funktion holen kann und wann das sinnvoll ist.
- Der Verlauf wird bei jedem Aufruf vollständig mitgeschickt (wegen `store:false`).

### 8.4 Datenschutz

Einmaliger Hinweis in der Einrichtung und in den Einstellungen: Wenn du KI-Funktionen nutzt, gehen die dafür nötigen Daten (Termine, Aufgaben, bei Issues auch Repo-Inhalte) an OpenAI. Keine Rückfrage pro Aufruf. Keine KI-Aufrufe ohne deine Aktion, auch nicht im Hintergrund-Refresh.

## 9. Benachrichtigungen und Hintergrund

Unverändert nach Phase 2 §8 und §12.8. Zusätzlich: Benachrichtigungen für wichtige Deadlines aus Deadline-Kalendern (Vorlauf wie bei Aufgaben).

## 10. Aufteilung in Pläne

| Plan | Inhalt | Ergebnis auf dem iPhone |
|---|---|---|
| **2b-1 Kalender & Planung** | Termine lesen, Plan- und Deadline-Kalender, Kapazität, Tag/Woche/Monat, Ziehen, Tageszuordnung, Zeitblöcke schreiben, Verknüpfung (automatisch/manuell) und Sprung, wiederkehrender Aufwand, Gedrückthalten-Menü ohne KI-Einträge | Ohne KI planen |
| **2b-2 KI** | ChatGPT-Anmeldung, Planen (Tag/Woche/Monat) mit lokaler Prüfung, Assistent-Knopf mit Funktionen, Chat zum Issue mit Repo-Funktionen, KI-Einträge im Menü, Verknüpfungsvorschläge | Mit KI planen und sprechen |
| **2b-3 Benachrichtigungen & Hintergrund** | Phase 2 §8, Deadline-Kalender-Benachrichtigungen, `BGAppRefreshTask` | Deadline-Erinnerungen |

## 11. Klärungen nach dem Builder-Check

Die mit *(Nutzer)* markierten Punkte hat der Nutzer am 2026-11-17 entschieden, die mit *(Planer)* markierten habe ich festgelegt.

1. **Einplanen vs. Fälligkeit** *(Nutzer)*: Ziehen in Woche/Monat und „Einplanen: Heute / Morgen / Wochenende / Nächste Woche / Datum …“ setzen nur den **Arbeitstag** (`DayAssignment`) in Tagwerk; die Fälligkeit bleibt. „Fälligkeit verschieben …“ ist ein eigener Menüpunkt und ändert sie wie in 2a (Reminders, GitHub „Due date“, lokal). Liegt der Arbeitstag nach der Fälligkeit, warnt Tagwerk (Markierung am Tag), blockiert aber nicht. *(Planer)*
2. **Arbeitstage** *(Nutzer)*: Arbeitszeit **pro Wochentag** (Beginn, Ende oder „frei“), Mittagspause und Puffer weiterhin global. Standard: Mo–Fr 09:00–18:00, Sa/So frei *(Planer)*. Für **einzelne Tage** lässt sich das abweichend einstellen (`DayOverride`: anderer Beginn/Ende, „frei“ oder zusätzliche Stunden), direkt in der Tagesansicht über die Kapazitätsanzeige. Auch die **KI** kann das setzen, z. B. „Ich habe heute bis 20 Uhr Zeit“: Funktion `set_day_hours` (bestätigungspflichtig, Aktionskarte). Freie Tage haben Kapazität 0; die KI plant dort nichts ein, Ziehen ist möglich (mit Überbuchungsanzeige).
3. **Arbeitstag und Zeitblöcke** *(Planer)*: Ein Zeitblock für eine Aufgabe setzt deren Arbeitstag auf den Tag des Blocks (bei mehreren Blöcken: der früheste noch offene). Eine Aufgabe darf **mehrere Blöcke** haben (z. B. 2 h + 1 h). „Einplanen auf einen anderen Tag“ fragt, ob die zukünftigen Blöcke mitwandern oder gelöscht werden; vergangene Blöcke bleiben.
4. **Verknüpfte Termine zählen als Planung** *(Planer)*: Ein Termin, der mit einer Aufgabe verknüpft ist (egal in welchem Kalender), zählt als geplante Last dieser Aufgabe und nicht zusätzlich als fremde belegte Zeit. Nicht verknüpfte Termine zählen als belegte Zeit. Ganztägige, abgelehnte und als „frei“ markierte Termine verbrauchen keine Zeit. Termine aus Deadline-Kalendern mit Uhrzeit (z. B. eine Klausur) verbrauchen Zeit.
5. **Puffer** *(Planer)*: vor und nach jedem belegenden Termin; zwischen direkt aufeinanderfolgenden Terminen nur einmal.
6. **Epics** *(Planer)*: Ein Epic ist ein Issue mit Label `epic` (Konvention von t3gh). Zugehörigkeit über GitHubs **Sub-Issues** (Feld `parent` des Issues). GitHubKit lädt zu jedem zugewiesenen Issue sein Parent-Issue mit Titel, Labels und „Due date“ nach, auch wenn das Epic nicht dir zugewiesen ist. Epics, die dir zugewiesen sind, erscheinen normal als Aufgabe; nicht zugewiesene nur als Deadline-Markierung.
7. **„Gehört zu einer wichtigen Deadline“** *(Planer)*: Sub-Issues gehören zu ihrem Epic; Aufgaben gehören zu einem Termin aus einem Deadline-Kalender nur über eine Verknüpfung (manuell oder bestätigter KI-Vorschlag). Lokale Regel: Eine zugehörige Aufgabe darf nicht nach dem Anker eingeplant werden (wird verworfen).
8. **Überfällige Tageszuordnungen** *(Planer)*: Nicht erledigte Aufgaben mit einem Arbeitstag in der Vergangenheit werden nicht automatisch verschoben; sie erscheinen im Tag „Heute“ in einem Abschnitt „Von früher übrig“ mit „Auf heute“ und „Neu einplanen“. Erledigte, gelöschte oder geschlossene Aufgaben verlieren ihre Tageszuordnung.
9. **Wiederkehrender Aufwand** *(Planer)*: Tagwerk berechnet die Vorkommen aus der `EKRecurrenceRule` der Erinnerung (täglich, wöchentlich mit Wochentagen, monatlich, mit Intervall und Ende); nicht unterstützte Regeln zeigen einen Hinweis und reservieren nur am nächsten Fälligkeitstag. Die Erinnerung selbst erscheint weiterhin in „Aufgaben“, ihre Zeit zählt aber nur einmal (über den Aufwand). Den Hinweis „erledigt“ für vorzeitig erledigte Vorkommen gibt es nicht (EventKit führt keine Vorkommens-Historie); die reservierte Zeit bleibt.
10. **KI-Planung, Auswahl der Aufgaben** *(Planer)*: Tag: dem Tag zugeordnete, am Tag oder früher fällige und wichtige Aufgaben. Woche/Monat: nicht zugeordnete offene Aufgaben, sortiert nach Fälligkeit und Priorität; bestehende Zuordnungen bleiben unangetastet (die KI darf sie nur als Risiko nennen). Obergrenze 60 Aufgaben je Aufruf. Verwirft die lokale Prüfung Vorschläge, wird **einmal** mit den Verstößen nachgefragt; danach landen verbleibende unter „nicht eingeplant“.
11. **Funktionen im Chat** *(Planer)*: `plan_period` startet nach Bestätigung die normale Planung (§8.2); die Vorschläge erscheinen in der Planen-Ansicht, der Chat zeigt eine Zusammenfassung mit Sprung dorthin. `update_task` kann alles, was `TaskEdit` kann (inkl. Labels, Project-Felder); Kommentare über eine eigene Funktion `add_comment` (bestätigungspflichtig).
12. **Plan-Kalender** *(Planer)*: Standard ist ein neuer Kalender „Tagwerk“ in iCloud, falls verfügbar (damit Blöcke auf Mac und Watch sichtbar sind), sonst lokal. Fehlt er später (gelöscht), sperrt Tagwerk das Schreiben von Blöcken und bietet „Neu anlegen“ oder „Anderen wählen“ an.
13. **Benachrichtigungen für Deadline-Kalender** *(Planer)*: Termine mit Uhrzeit: Beginn minus Vorlauf; ganztägige: am Vortag 18:00. Sie zählen zum Budget von 50. Ein eigener Schalter in den Einstellungen (Standard an), weil der Kalender selbst schon erinnern kann.
14. **Tabs** *(Planer)*: „Planen“ ersetzt den nie gebauten „Heute“-Tab; „Tag“ mit dem heutigen Datum ist die frühere Heute-Ansicht.
15. **Reihenfolge** *(Planer)*: Plan 2b-1 wird vollständig geplant und gebaut, 2b-2 und 2b-3 danach. Die UI-Tasks in 2b-1 folgen den freigegebenen Mockups.

## 12. Dem Umsetzenden überlassen

Konkrete Prompts und JSON-Schemas, Funktionssignaturen im Detail, Obergrenzen für Kontextgrößen, Darstellung innerhalb der freigegebenen Mockups, Ordnerstruktur, Testaufbau, Animationen.

## 13. Nachtrag nach der Geräteprüfung von 2b-1 (2026-11-17)

Der Nutzer hat 2b-1 auf dem iPhone geprüft. Die Gestaltung wurde mit Fable als Advisor erarbeitet und als Mockup `../mockups/2026-11-18-phase-2b-feedback-mockups.html` freigegeben: **A1, B1, C1+C2+C3+C4, D1, E1+E2, F1 (Rückfall F2), G1+G2+G3+G4, H1, I1, J1+J2+J4+J5+J6, K1+K3**. Die Punkte unten gehen §6, §7 und §11 vor, wo sie abweichen.

1. **Kopf der Tagesansicht (A1):** Großer Datumstitel im Inhalt statt in der Navigationsleiste; Antippen öffnet einen Monatskalender als Popover, waagerechtes Wischen im Inhalt wechselt den Tag, die Pfeile bleiben. Die Wischaktionen „Zeitblock“ und „Ausplanen“ auf Aufgabenzeilen der Tagesansicht entfallen (Nutzer); beides geht über Antippen bzw. Menü.
2. **Freie Zeit (B1):** Am heutigen Tag zählt nur die Zeit ab jetzt („1 h 10 noch frei“), der Tageswert steht als Unterzeile; vergangene Tage zeigen „Vergangen“, künftige wie bisher. Dauern als „2 h 05“. Ergänzt §6.1: Restkapazität = Kapazität des Tages, beschränkt auf das Intervall [jetzt, Arbeitsende].
3. **Erledigtes Vorkommen (Nutzer):** Hakt der Nutzer das heutige Vorkommen einer wiederkehrenden Erinnerung **in Tagwerk** ab, gibt Tagwerk dessen reservierten Aufwand für diesen Tag frei (Tagwerk merkt sich das Vorkommen lokal). Abhaken in der Erinnerungen-App ist nicht erkennbar (EventKit führt keine Vorkommens-Historie). Ersetzt den letzten Satz von §6.3 und §11.9.
4. **Zeitblöcke ändern (C1–C4):** Antippen eines Blocks öffnet ein Menü (Beginn/Dauer ±15 min, „Auf anderen Tag“, „Löschen“). Die Tagesansicht hat ein **maßstäbliches Stundenraster** (C3: Körper ziehen = verschieben, Griff = Dauer, Raster 15 min) und die bisherige Zeilen-Zeitleiste mit Lückenzeilen (C2: Aufgabe auf eine freie Lücke ziehen); **umschaltbar** per Schalter in der Tagesansicht (Nutzer). Im Bearbeiten-Sheet (C4) sind Arbeitstag, Blockzeit und Dauer direkt änderbar, Blöcke löschbar; „Blöcke mitverschieben“ wird dort ein Schalter statt eines Dialogs.
5. **Ablage „Ungeplant“ (D1):** Ausziehbare Ablage in drei Höhen mit Liste, Suche und Filter statt der Chip-Leiste. Standard: zuerst die im angezeigten Zeitraum fälligen Aufgaben, darunter die ohne Fälligkeit (Nutzer). Ziehen auf Tage bleibt, „＋“ ist der Weg ohne Ziehen.
6. **Monat (E1+E2):** Tippen wählt einen Tag und zeigt seine Termine, Deadlines und Aufgaben unter dem Raster. In „Tag“ geht es über „Tag öffnen ›“, einen zweiten Tipp oder langes Drücken (Menü mit „Tag öffnen“, „Aufgabe hier einplanen …“, „Neuer Termin“, „Arbeitszeit an diesem Tag …“).
7. **Kontextmenü (F1, Rückfall F2):** Zwei benannte Abschnitte „Einplanen · nur in Tagwerk“ (Heute, Morgen, Wochenende, Nächste Woche als 2 × 2 beschriftete Elemente, dazu „Anderer Tag …“) und „Fälligkeit · ändert <Quelle>“ mit dem aktuellen Fälligkeitswert. Zeigt iOS zwei gestapelte Gruppen nicht sauber, gilt F2 (Dreierreihe Heute/Morgen/Nächste Woche, Wochenende als Zeile).
8. **Aufgaben-Tab (G1–G4):** Auswahlmodus mit „Für heute einplanen“ und Summe gegen die Restzeit (G1); Wischaktion „Heute“ ohne Modus (G2); „Aufgabe öffnen“ an Terminen heißt „Aufgabe zeigen“ und springt in die Aufgabenliste mit Hervorhebung (G3, ändert §6.4). Antippen öffnet das Bearbeiten-Sheet. Wiederkehrende Erinnerungen tragen ↻; das Sheet trennt „Erinnerung“ (gilt immer für alle Tage, EventKit kennt beim Speichern von Erinnerungen keine Reichweite) und „In Tagwerk“ mit „Nur heute / Alle ab heute“ für Aufwand und Zeitblock (G4). „Alle ab heute“ ändert nur den Aufwand und legt keinen Serien-Zeitblock an (Nutzer).
9. **Fälliges (H1):** Heute fällige Aufgaben erscheinen im heutigen Tag automatisch und zählen zur Last. Überfällige erscheinen im Abschnitt „Von früher offen“ (ersetzt „Von früher übrig“, §11.8, und nimmt auch Überfälliges ohne Arbeitstag auf) und zählen erst nach „Heute“ zur Last.
10. **Termine in allen Kalendern (J1, J2, J4–J6):** Ersetzt den Grundsatz „Tagwerk schreibt nur in den Plan-Kalender“. Eigene Detailansicht und Kurzform zum Anlegen/Ändern mit Abgleich gegen die freie Zeit; „Weitere Optionen …“ öffnet Apples Termin-Editor. Neue Termine landen standardmäßig im **Plan-Kalender** (Nutzer). Schreibgeschützte Kalender (Abos, Feiertage, Geburtstage) zeigen keine Bearbeiten-/Löschen-Aktionen und nennen den Grund (J4); Einladungen anderer sind lesbar und verknüpfbar, aber nicht änderbar, Antworten nur in der Kalender-App (J5); Serien fragen beim Sichern und Löschen „Nur dieser Termin“ / „Dieser und alle folgenden“ (J6, entspricht `EKSpan`). Versionsprüfung wie §5.2.
11. **Doppelte Termine (I1):** Termine mit gleichem Titel, Beginn, Ende und Ganztags-Status aus verschiedenen Kalendern werden eine Zeile mit „2 Kalender“; im Detail „Getrennt anzeigen“. Neue Einstellung „Gleiche Termine zusammenfassen“ (Standard an). Die freie Zeit war nie betroffen (Vereinigung überlappender Intervalle in §6.1).
12. **KI (K1+K3, für 2b-2):** Der KI-Knopf sitzt neben der Tab-Leiste (abgesetzter Platz der Tab-Leiste; Rückfall K2 oben rechts neben ＋, falls das am Gerät nicht trägt). Ein Modell für alle KI-Funktionen, wählbar aus der Modellliste von ChatGPT (`GET /v1/models`, `visibility == "list"`), Vorgabe „Automatisch“ (§8.1).
13. **Bereits behoben (ohne Gestaltung):** Deadline-Kalender-Termine erscheinen als Deadline statt unter „Ganztägig“, die Deadline-Karte folgt dem angezeigten Tag; neue Zeitblöcke beginnen standardmäßig zur nächsten vollen Stunde innerhalb der Arbeitszeit, nie in der Vergangenheit; „Aufwand ändern …“ und der Sprung zum Arbeitstag funktionieren auch aus dem Aufgaben-Tab; „Nächste Woche“ ist im Menü erreichbar.

### 13.14 Abweichungen bei der Umsetzung (2026-11-17)

- **§13.3:** EventKit setzt eine wiederholte Erinnerung beim Abhaken sofort auf das nächste Vorkommen (im Simulator geprüft). Damit gibt auch Abhaken in der Erinnerungen-App den Aufwand des Tages frei. Tagwerk merkt sich das Vorkommen zusätzlich, damit „Rückgängig“ den Aufwand wieder reserviert.
- **D1:** Die Ablage ist ein unten eingesetztes Panel mit drei Höhen, kein System-Sheet. So lassen sich Aufgaben weiter auf die Tage dahinter ziehen.
- **C3:** Im Stundenraster verschiebt ein Block erst nach kurzem Gedrückthalten. Griffe oben und unten ändern Beginn bzw. Ende in beide Richtungen. Antippen öffnet die Block-Aktionen als Dialog. Grund: Ohne Halten verschob normales Scrollen über einen Block diesen ungewollt.
- **C1/C4:** Block-Aktionen gelten nur für Tagwerk-eigene Blöcke in beschreibbaren Kalendern. Andere verknüpfte Termine öffnen die Termin-Detailansicht mit Serienfrage.
- **F1:** iOS blendet den Abschnittstitel über Symbolgruppen aus. Eine Zeile mit dem aktuellen Arbeitstag („Arbeitstag: Mi. 18. Nov.“) hält den Titel sichtbar.
- **G1, Nutzerwunsch:** Für ausgewählte Aufgaben gibt es alle Aktionen des Einzelmenüs: Einplanen auf jeden Tag, Fälligkeit verschieben, Erledigt, Löschen. Die Reihenfolge entspricht dem Einzelmenü. Schreibende Aktionen überspringen offline nur lesbare Aufgaben.
- **„Heute“ (Auswahl, Wischen):** Künftige Zeitblöcke wandern ohne Rückfrage mit, wie beim Einplanen auf andere Tage.
- **Doppelte Termine:** Eine nicht verknüpfte Kopie eines verknüpften Termins zählt nicht als belegte Zeit.

### 13.15 Geräte-Feedback Runde 3 (2026-11-17)

Freigegeben aus `../mockups/2026-11-18-phase-2b-feedback-round3-mockups.html`: **L1, G1, S1, D1, U1, F1, R1, M1**. Geht §6, §7, §11 und §13.4–13.14 vor, wo es abweicht.

1. **Mittagspause (L1):** Die Pause ist ein Eintrag im Raster und lässt sich wie ein Termin verschieben und in der Länge ändern. Die Änderung gilt nur für diesen Tag (`DayOverride` um optionalen Pausenbeginn und -dauer erweitert, Dauer 0 = keine Pause). Eine Leiste bietet danach „Für alle Tage“ (ändert die Einstellung) und „Widerrufen“ (Nutzer). §6.1: Die Pause ist globaler Standard mit Abweichung je Tag.
2. **Griffe (G1):** Erst 0,3 s Halten wählt einen Eintrag aus; dann erscheinen die Griffe für Beginn und Ende. Antippen öffnet das Blatt (U1), Wischen scrollt, ein Tipp daneben beendet die Auswahl.
3. **Flüssiges Ziehen (S1):** Das Raster ist eine eigene Scrollansicht, nicht mehr eine Listenzeile. Der Eintrag folgt dem Finger ungerundet, nur Ziellinie und Uhrzeit rasten auf 15 min ein, mit Haptik je Schritt. Gespeichert wird einmal beim Loslassen, ohne Neuladen dazwischen. Das Raster ist die Standardansicht des Tages; die Liste bleibt wählbar (Nutzer). Die Ablage „Ungeplant“ in Woche und Monat bewegt sich per Versatz statt per Höhe.
4. **Ohne Uhrzeit ins Raster (D1):** Eine Leiste „Ohne Uhrzeit“ liegt unten am Raster. Halten und Ziehen einer Aufgabe zeigt einen maßstäblichen Vorschau-Block; Loslassen legt den Zeitblock an.
5. **Ein Blatt für alles (U1):** Termine, Zeitblöcke und Pause öffnen dasselbe Blatt: Kopf, Beginn und Dauer mit ±15 min, „Zählt als Belegt/Frei“, Aufgabe, Aktionen. Gesperrte Zeilen bleiben sichtbar und nennen den Grund. Ersetzt Block-Menü, Block-Dialog und die bisherige Termin-Detailansicht. Verschieben per Ziehen gilt für alle Termine in beschreibbaren Kalendern, nicht nur für Tagwerk-Blöcke.
6. **„Frei“ (F1):** Eine lokale Markierung in Tagwerk (`EventAvailabilityMark`), Vorrang vor `EKEvent.availability`; der Kalender bleibt unverändert, auch bei Abos und Einladungen (Nutzer). Freie Termine sind grau gestrichelt mit dem Wort „Frei“ und zählen nicht zur belegten Zeit; Vorschläge und Blöcke dürfen hinein. Auswahlmodus in der Tagesansicht mit „Auf Frei setzen“ / „Belegt“. Bei Serienterminen fragt Tagwerk „Nur an diesem Tag / Auch alle künftigen“ (Nutzer).
7. **Eine Aufwandsschätzung (R1):** Wiederkehrende Erinnerungen haben ein einziges Aufwandsfeld (Wert des Tages). Die Frage „Nur am … / Für alle ab …“ kommt beim Sichern und nur, wenn der Aufwand geändert wurde; Titel, Fälligkeit und Priorität gelten ohne Rückfrage für alle. Serientermine fragen „Nur diesen / alle folgenden“ beim Loslassen nach dem Ziehen und beim Sichern. Ersetzt die zwei Karten aus §13.8 (G4).
8. **Zusammenfassen (M1):** Automatisch nur bei gleichem Titel, Beginn und Ende. Gezeigt wird die Kopie nach Rangfolge: verknüpft, dann Zahl der gefüllten Felder, dann beschreibbar, dann Reihenfolge. Gleiche Zeit mit Platzhaltertitel („Busy“, „Away“, „Free“, „Tentative“ …) auf der einen Seite erkennt Tagwerk **lokal ohne KI** und zeigt eine Vorschlagskarte „Zusammenfassen / Getrennt lassen“, optional „künftig immer“ (Nutzer; §8.4 bleibt unverändert). Die KI hilft nur, wenn der Nutzer den Assistenten fragt.
   **Geändert am 2026-11-18 (Nutzer):** Tagwerk blendet nie ungefragt aus. Auch Termine mit gleichem Titel, Beginn und Ende in verschiedenen Kalendern bekommen nur eine Vorschlagskarte; erst „Zusammenfassen“ (optional „künftig immer“) zeigt eine Zeile. Deadline-Kalender nehmen nicht teil. Der Schalter „Termine zusammenfassen (mit Rückfrage)“ schaltet Vorschläge und angewandte Entscheidungen ab; „Zusammenfassungen zurücksetzen“ löscht alle Entscheidungen; „Getrennt anzeigen“ im Blatt hebt sie für einen Termin auf. Einstellungen › „Kalender-Diagnose“ zeigt je Kalender gelesene, gezeigte und ausgeblendete Termine der nächsten 7 Tage.

## Quellen

- Verifikation Function Calling: `../spikes/2026-11-17-feasibility-results.md`, Nachtrag Phase 2b.
- Apple: EventKit `EKEvent.url`, `calendarItemExternalIdentifier` (Dokumentation in Xcode 27.2).
