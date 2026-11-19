# Tagwerk – Design: Suche nach Terminen und Aufgaben

Stand: 2026-11-19 · Status: **vom Nutzer am 2026-11-19 freigegeben**.

Baut auf:
- `2026-11-17-tagwerk-design.md`: §2 Anti-Ziele, §6 Architektur (EventKit als Quelle der Wahrheit), §7 Datenschutz.
- `2026-11-17-phase-2b-design.md`: Assistent und Bestätigungsregel für schreibende Werkzeuge.
- `2026-11-18-phase-4-design.md`: Format dieses Dokuments, `AppRoute`, `completedAt` an lokalen Aufgaben.
- Den drei parallelen Entwürfen vom 2026-11-19 (Issue-Zuweisung #136, Phase 5 #113, Phase 7 #140), siehe §8.

Mockup: `../mockups/2026-11-19-search-mockups.html` (Entscheidungen QE, QZ, QG, QF, QR, QT, QK, QA; die Bilder tragen das Kürzel der Variante, z. B. „QE1“, „QG2“). Epic: **noch keines**; Vorschlag in §11: eigenständiges Epic „Suche“.

Kennzeichnung in diesem Dokument: **[Code]** = im Quelltext dieses Standes (Commit `d2eea38`) nachgelesen; **[Doku]** = aus Apple- oder GitHub-Dokumentation bekannt, für dieses Dokument nicht erneut nachgeschlagen; **[Annahme]** = ungeprüft; **[Festlegung]** = Entscheidung des Verfassers ohne Rückfrage, in §9 gesammelt.

## 1. Absicht und Warum

Tagwerk führt Termine, Erinnerungen, GitHub-Issues und lokale Aufgaben zusammen, aber nichts davon lässt sich übergreifend finden. Heute filtern nur vier Auswahl-Blätter lokal nach dem Titel **[Code]** (`DeadlineViews.swift:192`, `:375`, `EntrySheet.swift:402`, `PlanningModel.swift:373`). Fragen wie „Wann ist die Statistik-Klausur?“, „Habe ich das Übungsblatt schon erledigt?“ oder „Wann war das Erstgespräch?“ verlangen deshalb Blättern im Kalender oder einen Wechsel in die Apple-Apps.

Die Suche soll diese Fragen in einem Blatt beantworten, ohne Netz für den Normalfall, und denselben Suchkern dem Assistenten geben, der heute Zeiträume raten muss (`list_events` braucht ein Datumspaar, `AppTools+Definitions.swift:40–41` **[Code]**).

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Ein Suchblatt, erreichbar über eine Lupe oben in „Planen“ und „Aufgaben“ (QE1).
- Durchsucht werden: Termine der gewählten Kalender, offene Aufgaben aller drei Quellen, auf Wunsch erledigte Aufgaben (QF2), Notizen und die Einkaufsliste aus Phase 5 (QK3, Notizen als Festlegung).
- Termine in einem festen Fenster von 6 Monaten zurück bis 12 Monate voraus, erweiterbar um je ein Jahr zurück (QZ2).
- Geladene GitHub-Issues sofort und ohne Netz; die GitHub-Suche nur auf Tipp (QG2).
- Treffer nach Art gruppiert, mit Filter-Marken „Alle / Termine / Aufgaben“ (QR1).
- Tipp öffnet das vorhandene Blatt über der Suche, Gedrückthalten bietet „Im Plan zeigen“ (QT3).
- Ein lesendes Assistenten-Werkzeug `search` auf demselben Suchkern (QA2).
- Der Suchkern liegt als reine, getestete Logik in `TagwerkCore`.

**Nicht-Ziele (diese Fassung)**
- Eigener Tab „Suchen“ oder ein Suchfeld per `.searchable` (QE2, QE3 verworfen).
- Einstellung für das Zeitfenster (QZ3 verworfen); Erweiterung in die Zukunft über 12 Monate hinaus.
- Verlauf „Zuletzt gesucht“, Suchvorschläge, Rangfolge nach Trefferqualität (QR3 verworfen).
- Systemweite Suche (Core Spotlight), Siri-Kurzbefehl „Suchen“, Deeplink `tagwerk://search`.
- Suche in Mahlzeiten, Trainings, Chat-Verläufen des Assistenten und GitHub-Kommentaren.
- Bearbeiten von GitHub-Online-Treffern in Tagwerk.
- Volltextindex. Bei der erwarteten Menge (einige tausend Termine, wenige hundert Aufgaben) genügt lineares Filtern **[Annahme]**, Messung in §10.

**Anti-Ziele** (aus Hauptdesign §2 und den Regeln aus Phase 5)
- Die Suche wird zur zweiten Aufgabenquelle. Sie hält keine eigene Kopie von Terminen oder Erinnerungen über die Lebensdauer des Blatts hinaus.
- Netzabrufe beim Tippen. Ohne ausdrücklichen Tipp auf „Auf GitHub suchen“ verlässt kein Suchwort das Gerät.
- Notiztext verlässt das Gerät über die Suche. Das Werkzeug `search` liefert nie Notizen (Phase-5-Regel: Notiztext nur nach Zustimmung im Einzelfall).
- Eine Suche, die die Oberfläche blockiert. Der Terminabruf läuft nicht auf dem Hauptthread.
- Einkäufe verdrängen Aufgaben in der Trefferliste (Grund für QK3 statt QK1).

## 3. Einschränkungen

| Punkt | Befund | Status | Folge |
|---|---|---|---|
| Textsuche in EventKit | Termine lassen sich nur nach Zeitraum abfragen (`predicateForEvents(withStart:end:calendars:)`, `EventKitGateway.swift:263–272`) | **[Code]** für den Aufruf, **[Doku]** dafür, dass es keine Textabfrage gibt | Zeitraum holen, in Tagwerk filtern |
| Höchstspanne je Abfrage | Vier Jahre je Terminabfrage | **[Doku]** | Fenster 18 Monate; jede Erweiterung ist eine eigene Ein-Jahres-Abfrage |
| Hauptthread | `EventKitGateway` ist `@MainActor` und alleiniger Besitzer des `EKEventStore` (`EventKitGateway.swift:6–10`); `events(in:)` ist synchron | **[Code]** | Eigener Leseweg für die Suche, §5.3 |
| Termin-IDs | `CalendarBlockRules.uniqueIDs` vergibt IDs abhängig von der Menge eines Abrufs (`CalendarStore.swift:119–134`) | **[Code]** | IDs aus einem 18-Monats-Abruf können von denen des Tagesabrufs abweichen; vor dem Öffnen wird der Termin neu aufgelöst, §5.6 |
| Kalenderauswahl | „Planen“ liest gewählte Kalender plus Plan- und Deadline-Kalender (`PlanningModel.swift:1716–1722`); `nil` heißt alle | **[Code]** | Die Suche nutzt dieselbe Menge |
| Assistent heute | `list_events` liest **alle** Kalender (`AppEnvironment.swift:120–121`), höchstens 100 Termine; `list_tasks` höchstens 60 (`AppTools.swift:14`) | **[Code]** | `search` nutzt die Kalenderauswahl der Suche; der Unterschied steht in der Werkzeugbeschreibung |
| Geladene Issues | Nur offene, mir zugewiesene Issues in offenen Projects (`ProjectsQuery.swift:42–56`), gezeigt die der gewählten Projects (`GitHubTaskProvider.swift:281–294`), mit Offline-Cache | **[Code]** | Diese Menge ist ohne Netz durchsuchbar |
| GitHub-Rechte | Scope `repo project offline_access` (`DeviceFlowClient.swift:22`) | **[Code]**; dass er für die Issue-Suche genügt: **[Annahme]** | Probe in §10 |
| GitHub-Suchlimit | Die Suche hat ein eigenes, engeres Abfragelimit | **[Doku]**, Zahlen nicht nachgeschlagen | Ein Abruf je Tipp, keine Abfrage beim Tippen |
| Erledigte Aufgaben | `TaskProvider.openTasks` liefert nur offene (`LocalTaskProvider.swift:18–24`, `EventKitGateway.swift:65–78`); erledigte Erinnerungen liest heute nur `completionDates` und gibt nur Datumswerte heraus (`EventKitGateway.swift:80–96`) | **[Code]** | Neuer Leseweg mit Titeln, §5.4 |
| Kopf von „Planen“ | Titel links als `PlanTitleButton` mit `.fixedSize()` (`PlanHeader.swift:73`), rechts ＋ und der Assistent-Knopf (`PlanView.swift:107–114`) | **[Code]** | Dritter Knopf verengt den Titel, §6.1 |
| Blätter | Aufgaben- und Termin-Blatt hängen an der `TabView` (`RootView.swift:85–98`) | **[Code]** | Ein Blatt über dem Suchblatt muss am Suchblatt selbst hängen, §6.5 |
| Mindestversion | iOS 27.0 | **[Code]** (Hauptdesign §6) | `ToolbarSpacer`, `Tab` usw. verfügbar |

## 4. Ansätze

Je Entscheidung die erwogenen Wege, die Abwägung und die Wahl des Nutzers. Die Empfehlung stammt aus dem Mockup.

| Kürzel | Frage | Erwogen | Abwägung | Wahl des Nutzers |
|---|---|---|---|---|
| QE | Wo sitzt die Suche? | QE1 Lupe oben in „Planen“ und „Aufgaben“ · QE2 `.searchable` in „Aufgaben“ · QE3 eigener Tab | QE1 lässt die Tab-Leiste unberührt und ist aus beiden Tabs erreichbar, kostet aber einen dritten Knopf oben. QE2 ist am billigsten, macht Termine aber nur über „Aufgaben“ auffindbar. QE3 widerspricht der Querschnittsentscheidung „kein neuer Tab“ | **QE1** (wie empfohlen). Bekanntes Risiko: Titelbreite in „Planen“, gelöst in §6.1 |
| QZ | Zeitfenster für Termine | QZ1 fest · QZ2 fest plus „Ältere Termine durchsuchen“ · QZ3 Einstellung | QZ1 hat einen toten Punkt für alte Termine. QZ3 ist eine Einstellung, die kaum jemand anfasst | **QZ2** (wie empfohlen): 6 Monate zurück, 12 voraus, je Tipp ein Jahr weiter zurück |
| QG | GitHub | QG1 nur geladene · QG2 GitHub-Suche auf Tipp · QG3 immer live | QG1 findet geschlossene und fremde Issues nie. QG3 wartet bei jeder Suche aufs Netz und verbraucht das Suchlimit beim Tippen | **QG2** (wie empfohlen, vom Nutzer bestätigt) |
| QF | Erledigte | QF1 nein · QF2 Schalter · QF3 immer | QF3 füllt die Liste mit alten Treffern | **QF2** (wie empfohlen), Standard aus |
| QR | Gruppierung | QR1 nach Art · QR2 nach Zeit · QR3 nach Trefferqualität | QR2 mischt zwei Zeilenformen und braucht einen Sonderabschnitt für Aufgaben ohne Datum. QR3 wirkt bei wenigen Dutzend Treffern willkürlich | **QR1** (wie empfohlen) |
| QT | Tipp auf einen Treffer | QT1 Blatt · QT2 Sprung · QT3 Blatt, Sprung über Gedrückthalten | QT2 schließt die Suche und verliert die Trefferliste | **QT3** (wie empfohlen) |
| QK | Einkaufsliste | QK1 wie alle Erinnerungen · QK2 ausschließen · QK3 eigener Abschnitt | QK1 lässt „Brot“ und „Milch“ Aufgaben verdrängen. QK2 beantwortet „Steht Brot schon drauf?“ nicht | **QK3 – Abweichung von der Empfehlung (QK2).** Eigener Abschnitt „Einkaufsliste“ ganz am Ende der Treffer. Grund laut Entscheidung: auffindbar, ohne zu stören |
| QA | Assistent | QA1 kein Werkzeug · QA2 lesendes Werkzeug | QA1 kostet mehrere Abrufe und scheitert außerhalb des geratenen Zeitraums | **QA2 – Abweichung im Zeitpunkt:** empfohlen war eine Folgeaufgabe, der Nutzer will das Werkzeug **in diesem Umfang** |

Nicht vom Nutzer entschieden und deshalb Festlegung (§9, F1): Notizen aus dem `NoteRecord`-Speicher von Phase 5 werden durchsucht, als eigener Abschnitt „Notizen“ direkt über „Einkaufsliste“.

**Architektur-Ansatz** (Wahl des Verfassers, **[Festlegung]**):

| Ansatz | Kern | Abwägung | Entscheidung |
|---|---|---|---|
| A: Filtern bei Bedarf | Quellen laden, im Speicher filtern, Ergebnis verwerfen, wenn das Blatt schließt | Kein Index, keine Kopie, keine Migration. Kosten: ein Terminabruf über 18 Monate je Blatt-Öffnung | **Gewählt** |
| B: Eigener Suchindex in SwiftData | Termine und Aufgaben beim Laden indizieren | Schnell, aber zweite Kopie der EventKit-Daten (Anti-Ziel Daten-Drift), Abgleich bei jeder Änderung, Migration | verworfen |
| C: Core Spotlight | Systemindex, auch außerhalb der App | Titel landen im Systemindex; eigener Abgleich nötig; löst die Suche in der App nicht | verworfen (Nicht-Ziel) |

## 5. Design: Daten und Regeln

### 5.1 Bausteine

| Baustein | Ort | Aufgabe |
|---|---|---|
| `SearchQuery`, `SearchText` | `TagwerkCore/Search/` | Normalisierung, Zerlegung in Wörter, Treffer-Prüfung, Fundstellen für die Markierung |
| `SearchDocument` | `TagwerkCore/Search/` | Durchsuchbare Felder eines Eintrags (aus `CalendarEvent`, `TaskItem`, Notiz, Einkaufsartikel) |
| `EventSeriesGrouping` | `TagwerkCore/Search/` | Fasst Vorkommen einer Serie zu einer Zeile zusammen |
| `SearchResults` | `TagwerkCore/Search/` | Abschnitte, Reihenfolge, Zähler; reine Funktion aus Eingaben und Suchwort |
| `EventSearchReader` | `RemindersKit` | Terminabruf über einen Zeitraum außerhalb des Hauptthreads |
| `ReminderStore.completedReminders(in:listIDs:)` | `RemindersKit` | Erledigte Erinnerungen mit Titel |
| `TaskProvider`-Ergänzung für lokale erledigte Aufgaben | App (`LocalTaskProvider`) | Erledigte lokale Aufgaben |
| `GitHubAPI.searchIssues(text:repositories:)` | `GitHubKit` | Online-Suche (QG2) |
| `SearchModel` (`@Observable`, `@MainActor`) | `Tagwerk/Search/` | Zustand des Blatts: Suchwort, Filter, Schalter, Fenster, Laden, Fehler |
| `SearchSheet` und Zeilen | `Tagwerk/Search/` | Oberfläche |
| Werkzeug `search` | `Tagwerk/AI/AppTools*.swift` | Assistent |

Es gibt **kein neues SwiftData-Modell** und **keine neue Einstellung**.

### 5.2 Suchregeln (reine Logik)

1. **Normalisierung:** Suchwort und Felder werden ohne Rücksicht auf Groß-/Kleinschreibung, Akzente/Umlaute und Zeichenbreite verglichen (`folding` mit case-, diacritic- und width-insensitive). Zusätzlich wird „ß“ zu „ss“. Folge: „ubung“ findet „Übung“, „strasse“ findet „Straße“. „ue“ findet „ü“ **nicht** (bewusst, sonst entstehen Fehltreffer wie „Quelle“).
2. **Mehrere Wörter:** Das Suchwort wird an Leerraum geteilt. Jedes Wort muss in mindestens einem Feld als Teilzeichenkette vorkommen (UND über Wörter, ODER über Felder).
3. **Felder:**

| Art | Felder |
|---|---|
| Termin | Titel, Notizen, Ort, Kalendername |
| Aufgabe | Titel, Notizen, Listen- bzw. Repository-Name (`container.name`), Project-Namen (`subContainers`), Labels, Issue-Nummer |
| Notiz (Phase 5) | Text; Art-Bezeichnung („Tagesstart“, „Tagesabschluss“) |
| Einkaufsartikel (Phase 5) | Titel, Mengenangabe im Notizfeld |

4. **Issue-Nummer:** Ein Wort der Form `#42` trifft nur ein Issue mit genau dieser Nummer. Ein Wort aus reinen Ziffern (`42`) trifft ein Issue mit genau dieser Nummer **oder** jede Fundstelle im Text. `TaskItem` trägt die Nummer nicht als Feld (`GitHubMapping.swift:55–77` **[Code]**); sie wird aus dem letzten Pfadteil der Issue-URL (`TaskItem.url`, `…/issues/42`) gelesen.
5. **Mindestlänge:** Gesucht wird ab zwei Zeichen (nach Abschneiden von Leerraum). Darunter zeigt das Blatt den leeren Zustand.
6. **Verzögerung:** 250 ms nach dem letzten Tastendruck. Ein neuer Tastendruck bricht eine laufende Auswertung ab. Aufgaben filtern ohne Verzögerung, weil sie schon geladen sind.
7. **Fundstellen:** Für den Titel liefert der Kern die Bereiche zum Hinterlegen. Trifft kein Wort den Titel, liefert er einen Ausschnitt des ersten treffenden Felds (höchstens 80 Zeichen um die Fundstelle) als zweite Zeile.

### 5.3 Termine

- **Fenster:** Beginn = Tagesanfang heute minus 6 Monate, Ende = Tagesanfang heute plus 12 Monate, im Kalender `Calendar.tagwerk`.
- **Erweiterung:** Jeder Tipp auf „Ältere Termine durchsuchen“ holt ein weiteres Jahr vor dem bisherigen Beginn als eigene Abfrage und hängt das Ergebnis an. Die Erweiterung gilt, bis das Blatt schließt, auch wenn das Suchwort wechselt. Eine Obergrenze gibt es nicht; der Knopf bleibt, solange das zuletzt geholte Jahr nicht leer **und** nicht älter als zehn Jahre ist.
- **Kalender:** gewählte Kalender plus Plan- und Deadline-Kalender, wie `readableCalendarIDs()`. Diese Funktion ist heute `private`; sie wird für die Suche zugänglich gemacht, nicht nachgebaut.
- **Abruf außerhalb des Hauptthreads:** `EventSearchReader` ist ein eigener `actor` in `RemindersKit` mit **eigenem, nur lesendem** `EKEventStore`. Er wandelt an seiner Grenze in `CalendarEvent` (ist `Sendable`) um, mit derselben Funktion `EventKitGateway.calendarEvent`. Begründung: Der vorhandene Store darf den Hauptaktor nicht verlassen (`EventKitGateway.swift:6–10`), und ein zweiter Store teilt die Berechtigung der App **[Doku]**. Dass ein zweiter Store dieselben Daten ohne spürbare Verzögerung sieht, ist **[Annahme]** und Teil des Spikes (§10). Rückfallweg, falls nicht: Abruf über den vorhandenen Gateway in Scheiben von drei Monaten mit `Task.yield()` dazwischen.
- **Zeitpunkt:** Der Abruf startet beim ersten Suchwort ab zwei Zeichen, nicht beim Öffnen des Blatts. Das Ergebnis bleibt für die Lebensdauer des Blatts im `SearchModel`; weitere Tastendrücke filtern nur noch im Speicher. Meldet EventKit eine Änderung (vorhandener Strom `gateway.changes`, verteilt in `AppEnvironment.swift:293–295`) oder schließt ein Termin-Blatt über der Suche, wird neu abgerufen.
- **Zusammenführen:** Bei `settings.mergeDuplicateEvents` läuft `mergingDuplicates` (`EventMerging.swift:6`) wie in „Planen“, damit derselbe Termin aus zwei Kalendern nur einmal erscheint.
- **Zeitblöcke:** Termine im Plan-Kalender, deren URL eine Aufgabe trägt (`TaskLinkURL.parse`), sind keine Treffer. Ihre Aufgabe ist schon Treffer.
- **Serien:** Vorkommen mit `isRecurring == true` und gleicher Grundkennung (Teil der ID vor `|`, `CalendarBlockRules.parseOccurrenceID`) im selben Kalender bilden eine Serie.
  - Kommende Vorkommen: eine Zeile mit dem nächsten Vorkommen und dem Zusatz „↻ wöchentlich · 9 weitere bis Februar“ (Zahl und letzter Monat aus den Treffern im Fenster; die Rhythmus-Angabe nur, wenn sie sich ohne weiteren Abruf ergibt, sonst „↻ · 9 weitere bis Februar“).
  - Vergangene Vorkommen: nur das jüngste, ohne Zähler.
  - Einzeln verschobene Vorkommen ohne Serienregel bleiben eigene Zeilen.
- **Kommend oder vergangen:** Ein Termin ist vergangen, wenn sein Ende vor „jetzt“ liegt. Ein ganztägiger Termin von heute ist kommend.
- **Deadline-Marke:** Die Zeile zeigt „⚑ Deadline“, wenn `planning.deadlineEventIDs(among:)` den Termin enthält.
- **Ohne Kalenderzugriff:** Der Abschnitt „Termine“ entfällt; der leere Zustand nennt den fehlenden Zugriff einmal.

### 5.4 Aufgaben

- **Offene:** `taskList.items` (schon geladen, alle drei Quellen, inklusive GitHub-Offline-Cache). Die Einkaufsliste ist seit Phase 5 nicht mehr darin.
- **Reihenfolge:** `sortedTasks` (`TaskSections.swift`), also dieselbe wie überall.
- **Erledigte (Schalter „✓ Erledigte“):**
  - Erinnerungen: neuer Leseweg `completedReminders(in:listIDs:)` mit `predicateForCompletedReminders`, gewählte Listen ohne Einkaufsliste, erledigt in den letzten **12 Monaten**. Nur mit Vollzugriff.
  - Lokal: alle `LocalTask` mit `isCompleted`, sortiert nach `completedAt` (jüngste zuerst; ohne Datum ans Ende, weil `completedAt` erst seit Phase 4 gesetzt wird, `LocalTask.swift:23–24`).
  - GitHub: keine (geschlossene Issues gibt es nur über die Online-Suche); der Abschnitt nennt das in seiner Fußzeile.
  - Geladen wird erst beim Einschalten des Schalters, einmal je Blatt.
  - Gleiche erledigte Erinnerungen (gleicher Titel, gleiche Liste) erscheinen als eine Zeile mit dem jüngsten Datum und „n weitere“.
  - Der Schalter ist nicht gespeichert; jedes Öffnen beginnt mit „aus“.
- **Wiederkehrende Erinnerungen:** Ob EventKit erledigte Einzelvorkommen liefert, ist seit Phase 4 offen (dortige Geräte-Checkliste). Die Suche zeigt, was die Abfrage liefert, und macht darüber keine Zusage.

### 5.5 GitHub-Online-Suche (QG2)

- **Auslöser:** nur der Tipp auf die Zeile „Auf GitHub suchen“. Sie erscheint, wenn GitHub angemeldet ist, das Suchwort mindestens zwei Zeichen hat und der Filter nicht „Termine“ ist.
- **Abfrage:** dieselbe GraphQL-`search` wie beim Laden (`type: ISSUE`), mit `is:issue`, dem Suchwort und der Eingrenzung auf Repositories. Die Eingrenzung sind `repo:`-Angaben aus dem vorhandenen `GitHubCatalog.repositories` (eigene und mit Projects verknüpfte), höchstens 30; ist der Katalog leer, `user:<Login>`. Erste Seite, höchstens 20 Treffer, kein Nachladen. Ob GitHub so viele `repo:`-Angaben in einer Abfrage annimmt, ist **[Annahme]** (§10); Rückfallweg: `user:<Login>` plus je ein `org:`/`user:` für die Besitzer der Project-Repositories.
- **Ergebnis:** Treffer, die schon unter den geladenen Aufgaben stehen (gleiche Issue-ID), werden ausgelassen. Übrig bleiben geschlossene, nicht (mir) zugewiesene und Issues ohne Project. Jede Zeile trägt ihren Zustand als Marke: „geschlossen“, „nicht zugewiesen“, „anderen zugewiesen“, „ohne Project“ (mehrere möglich, die erste zutreffende in dieser Reihenfolge wird gezeigt).
- **Nur lesbar:** Tipp öffnet die Issue-URL über `openURL`. Kein Blatt, kein Kreis zum Abhaken (gestrichelter Kreis wie bei „GitHub offline“). Begründung: Priorität, Aufwand und Status sind Project-Felder; ein Issue ohne Project hat sie nicht.
- **Lebensdauer:** Ändert sich das Suchwort, verschwindet der Abschnitt „GitHub · online“, und die Zeile „Auf GitHub suchen“ steht wieder da.
- **Fehler:** ohne Netz „Keine Verbindung zu GitHub.“ mit „Erneut versuchen“; abgelaufene Anmeldung führt über den vorhandenen Weg (`onSignedOut`) zur Neuanmeldung; Limit erreicht: „GitHub nimmt gerade keine Suche an. Später erneut versuchen.“
- **Datenschutz:** Mit dem Tipp geht das Suchwort an GitHub. Das steht als Unterzeile an der Zeile („auch geschlossene und fremde“) und im leeren Zustand; eine eigene Einwilligung gibt es nicht, weil der Tipp die bewusste Aktion ist.

### 5.6 Öffnen und Springen (QT3)

| Treffer | Tipp | Gedrückthalten (Menü) |
|---|---|---|
| Termin | `EntrySheet` über der Suche | „Öffnen“, „Im Plan zeigen“, „Als Deadline markieren“ bzw. „Deadline-Markierung entfernen“ (vorhandenes Termin-Menü, `DeadlineViews.swift:448 ff.`) |
| Offene Aufgabe | `TaskEditorView` über der Suche | „Öffnen“, „Im Plan zeigen“ (wenn ein Arbeitstag zugewiesen ist) oder „In Aufgaben zeigen“, danach die Einträge des vorhandenen `TaskContextMenu` |
| Erledigte Aufgabe | `TaskEditorView` über der Suche | „Öffnen“, „Wieder öffnen“ |
| GitHub-Online-Treffer | öffnet GitHub | „Auf GitHub öffnen“, „Link kopieren“ |
| Notiz | Notiz-Blatt aus Phase 5 über der Suche | „Öffnen“ |
| Einkaufsartikel | Kreis: abhaken wie in Phase 5; Zeile: Einkaufsliste aus Phase 5 als Blatt über der Suche | „Abhaken“, „Einkaufsliste öffnen“ |

- **„Im Plan zeigen“:** schließt die Suche und ruft die vorhandenen Wege auf: für Termine `showDay` mit dem Tag des Termins (`RootView.swift:147–151`), für Aufgaben mit Arbeitstag ebenfalls `showDay`, sonst `showTask` mit Markierung in der Liste (`RootView.swift:111–117`).
- **Termin neu auflösen:** Vor dem Öffnen eines Termins holt das Blatt die Termine dieses Tages über den Weg von „Planen“ und sucht den Treffer über Grundkennung, Kalender und Beginn. So trägt der geöffnete Termin die ID, die Verknüpfungen und Deadline-Marken erwarten (Einschränkung „Termin-IDs“ in §3). Ist er nicht mehr da: Hinweis „Der Termin wurde geändert.“ und neuer Abruf.
- **Abhaken in der Suche:** Der Kreis einer offenen Aufgabe ruft `taskList.complete`. Die vorhandene Widerrufen-Kapsel (`UndoCapsule`) erscheint unten im Suchblatt. Die Zeile wandert bei eingeschaltetem Schalter nach „Erledigt“, sonst verschwindet sie.
- **Wieder öffnen:** schreibt `isCompleted = false` über den Provider der Quelle und meldet das Ergebnis mit `taskList.didSave` (`TaskListModel.swift:300–311`). `applyReturning` taugt dafür nicht, weil es die Aufgabe in den offenen `items` erwartet (`TaskListModel.swift:322–324`).
- **Nach dem Schließen eines Blatts** bleibt die Suche mit Suchwort, Filter und Rollposition stehen; die betroffene Zeile wird neu bewertet (geänderter Titel kann den Treffer beenden).

## 6. Design: Oberfläche

### 6.1 Einstieg (Bild „QE1 Lupe oben“)

- **„Planen“:** Lupe (`magnifyingglass`, Label „Suchen“) als eigener Eintrag rechts, **links vom ＋**; beide teilen sich die Glasfläche, der Assistent-Knopf bleibt abgesetzt außen (`AssistantToolbarItems`, `AssistantButton.swift:28–36`). Reihenfolge von links: Lupe, ＋, Abstand, Assistent.
- **Titelregel in „Planen“** (das bekannte Risiko): Der Datumstitel darf nie mit „…“ abgeschnitten werden. Er wählt die längste Form, die passt:
  1. Tag: „Donnerstag, 19. Nov.“ → „Do., 19. Nov.“ → „19. Nov.“
  2. Woche: „16.–22. Nov.“ (unverändert, kurz genug) → „16.–22.11.“
  3. Monat: „November“ → „Nov.“
  - Umsetzung über `ViewThatFits` im `PlanTitleButton`; das `.fixedSize()` gilt dann je Kandidat. Die Zeile darüber („HEUTE · KW 47“) bleibt und darf als einzige kürzen (`lineLimit(1)`, Verkleinerung bis 80 %).
  - VoiceOver liest weiter die lange Form (`accessibilityLabel` bleibt `title` in voller Länge).
  - Ob `ViewThatFits` in einem Toolbar-Eintrag die verfügbare Breite erhält, ist **[Annahme]** (§10). Rückfallweg ohne Messung: In der Tagesansicht immer „Do., 19. Nov.“, sobald die Lupe eingebaut ist.
  - Phase 7 legt Karten in den Inhalt von „Planen“, keine Knöpfe in die Leiste (Querschnittsentscheidung). Die Leiste hat damit nach diesem Vorhaben ihren Endstand: drei Einträge rechts.
- **„Aufgaben“:** Lupe rechts, links vom ＋. Während „Auswählen“ aktiv ist, ist die Lupe ausgeblendet. Die Offline-Anzeige (`TaskListView.swift:90–92`) bleibt links von der Lupe.
- **„Erfassen“ und „Einstellungen“:** keine Lupe.
- **Sprachmodus:** Läuft der Sprachmodus, ist die Lupe deaktiviert (gleiche Regel wie für die Blätter in `RootView.swift:29–38`).

### 6.2 Suchblatt (Bild „QE1 Das Suchblatt“)

- Ein Blatt über dem aktuellen Tab in voller Höhe (`.sheet`, großes Detent), an der `TabView` in `RootView`. Der Zustand „Suche offen“ liegt im `AppEnvironment` (wie `assistant.isPresented`), damit Assistent, Mitteilungen und Deeplinks das Blatt schließen können (`RootView.swift:59–62`, `:120–145`).
- **Kopf:** Suchfeld mit Lupe und Löschen-Kreuz, rechts „Abbrechen“. Das Feld hat beim Öffnen den Fokus, die Tastatur ist sofort da. Eingabehilfen: keine Autokorrektur, keine automatische Großschreibung, Return-Taste „Suchen“ (schließt nur die Tastatur).
- **Marken-Zeile:** „Alle“, „Termine“, „Aufgaben“ als Einfachauswahl; rechts abgesetzt der Schalter „✓ Erledigte“ (Bild „QF2“). Die Zeile ist waagerecht rollbar, falls die Schriftgröße sie sprengt.
- **Liste:** Abschnitte nach §6.3. Rollen schließt die Tastatur (`scrollDismissesKeyboard(.interactively)`).
- **Fußzeile der Liste** (kein Abschnitt): „Durchsucht: 6 Monate zurück, 12 Monate voraus.“ bzw. nach Erweiterung „Durchsucht: ab Mai 2025, 12 Monate voraus.“
- **Schließen:** „Abbrechen“ oder Herunterziehen. Das Suchwort wird verworfen; das nächste Öffnen beginnt leer.

### 6.3 Abschnitte und Reihenfolge (Bilder „QR1“, „QF2“, „QG2“, „QK3“)

| # | Abschnitt | Kopf | Inhalt und Reihenfolge | Sichtbar bei Filter |
|---|---|---|---|---|
| 1 | Termine | „Termine · 3 kommende“ | kommende Termine, nächster zuerst; Serien als eine Zeile | Alle, Termine |
| 2 | Aufgaben | „Aufgaben · 3 offen“ | offene Aufgaben in App-Reihenfolge; letzte Zeile „Auf GitHub suchen“ | Alle, Aufgaben |
| 3 | Erledigt | „Erledigt · 2“ | nur mit Schalter; jüngste zuerst, grau | Alle, Aufgaben |
| 4 | GitHub · online | „GitHub · online · 2 weitere“ | nur nach dem Tipp; Reihenfolge wie von GitHub geliefert | Alle, Aufgaben |
| 5 | Vergangene Termine | „Vergangene Termine · 2“ | jüngster zuerst; letzte Zeile „Ältere Termine durchsuchen · vor Mai 2026“ | Alle, Termine |
| 6 | Notizen | „Notizen · 1“ | jüngste Änderung zuerst | nur Alle |
| 7 | Einkaufsliste | „Einkaufsliste · 2“ | offene Artikel in der Reihenfolge von Phase 5 | nur Alle |

- „Einkaufsliste“ ist immer der **letzte** Abschnitt (QK3), „Notizen“ steht direkt darüber.
- Leere Abschnitte entfallen samt Kopf. Ausnahmen: Die Zeilen „Auf GitHub suchen“ und „Ältere Termine durchsuchen“ erscheinen auch ohne Treffer in ihrem Abschnitt, dann unter einem Kopf ohne Zähler.
- Jeder Abschnitt zeigt zunächst höchstens 25 Zeilen, darunter „Weitere n zeigen“ (je Tipp 25 mehr).
- Für Notizen gibt es im Mockup **kein Bild**; die Zeile folgt der Notizzeile aus dem Phase-5-Entwurf.

### 6.4 Zeilen

- **Termin:** links Datum als Zwischenkopf („Fr. 27.11.“) und Uhrzeit („10:00“, ganztägig „ganztägig“); Titel mit hinterlegter Fundstelle; ggf. „⚑ Deadline“; Unterzeile „Kalender · Ort“ und der Serienzusatz. Bei vergangenen Terminen bis sieben Tage zurück zusätzlich „vor 2 Tagen“. Liegt der Termin nicht im laufenden Jahr, trägt das Datum die Jahreszahl („Mo. 12.10.2025“).
- **Aufgabe:** die vorhandene `TaskRow` (Kreis, Titel, Fälligkeit, Liste bzw. Repository, Priorität), ergänzt um die Fundstellen-Hinterlegung. Kein Wischen nach links/rechts außer dem vorhandenen „Erledigt“.
- **Erledigte Aufgabe:** gefüllter Kreis, grauer Titel, „erledigt 12.11. · To Do“.
- **Online-Treffer:** gestrichelter Kreis, Titel mit Nummer, Zustandsmarke, „Repository · Datum der letzten Änderung“.
- **Notiz:** erste Textzeile als Titel, Unterzeile „Notiz · 12.11.“ bzw. „Tagesabschluss · 18.11.“ (Bezeichnung aus Phase 5/7), darunter der Ausschnitt mit der Fundstelle.
- **Einkaufsartikel:** Kreis, Titel, Mengenangabe; rechts „Einkauf“.
- **Fundstelle:** gelb hinterlegt und halbfett, damit sie nicht nur über Farbe erkennbar ist. Steht die Fundstelle nicht im Titel, zeigt eine zweite Zeile den Ausschnitt mit vorangestelltem Feldnamen („Notiz: …“, „Ort: …“, „Label: …“).

### 6.5 Blätter über der Suche (Bild „QT1“/„QT3“)

`SearchSheet` trägt eigene `.sheet(item:)` für `TaskEditorView`, `EntrySheet`, das Notiz-Blatt und die Einkaufsliste. Die Aufrufe entsprechen denen in `RootView.swift:85–98`; der Plan zieht dafür eine gemeinsame Hilfsfunktion heraus, statt die Parameterlisten zu verdoppeln. `onShowDay` und `onShowTask` der Blätter schließen erst die Suche und rufen dann die Wege aus `RootView`.

### 6.6 Zustände

| Zustand | Anzeige |
|---|---|
| Leer oder ein Zeichen | „Durchsucht Termine, Aufgaben, Notizen und die Einkaufsliste.“ und darunter das Zeitfenster. Ohne Kalenderzugriff zusätzlich „Kein Zugriff auf Kalender – Termine werden nicht durchsucht.“ |
| Termine laden noch | Aufgaben-Treffer stehen sofort da; im Abschnitt „Termine“ eine Zeile mit Fortschrittsanzeige „Termine werden durchsucht …“ |
| Keine Treffer | „Keine Treffer für „statistik“.“ Darunter, soweit zutreffend, die Wege weiter: „Ältere Termine durchsuchen“, „Auf GitHub suchen“, „Erledigte einbeziehen“ |
| GitHub nur aus dem Cache | Fußzeile im Abschnitt „Aufgaben“: „GitHub: Stand von 10:32.“ |
| GitHub nicht verbunden | keine Zeile „Auf GitHub suchen“ |
| Phase 5 nicht eingerichtet | Abschnitte „Notizen“/„Einkaufsliste“ entfallen still |

## 7. Design: Assistent, Einstellungen, Texte

### 7.1 Werkzeug `search` (Bild „QA2“)

- **Art:** lesend; wird in `AppTools.readTools` aufgenommen (`AppTools.swift:13`) und braucht deshalb keine Bestätigung.
- **Parameter** (alle Pflicht, optionale als `null`, wie in `AppTools+Definitions.swift`):

| Name | Typ | Bedeutung |
|---|---|---|
| `query` | string | Suchtext; Regeln aus §5.2 |
| `kind` | `all` \| `events` \| `tasks` | Eingrenzung |
| `include_completed` | boolean | erledigte Erinnerungen und lokale Aufgaben einbeziehen |
| `from` | `YYYY-MM-DD` \| null | früherer Beginn für Termine; `null` = 6 Monate zurück |
| `to` | `YYYY-MM-DD` \| null | späteres Ende für Termine; `null` = 12 Monate voraus |

- **Beschreibung (englisch, wie alle Werkzeuge):** “Searches calendar events and tasks by text (title, notes, location, list or repository, labels, issue number). Events are searched in the calendars selected in the settings, by default from 6 months back to 12 months ahead; pass from/to for another period of at most 4 years. Use it instead of guessing periods with list_events.”
- **Antwort:** `{"events":[…],"tasks":[…],"eventCount":n,"taskCount":n,"searched":{"from":"…","to":"…"}}`.
  - Termine in der Form von `list_events` (ID, Titel, Beginn, Ende, Kalender, Ort, `recurring`, `deadline`, `linkedTask`), bei Serien zusätzlich `moreOccurrences`. Höchstens 20, kommende zuerst.
  - Aufgaben in der Form `summary` von `list_tasks`, erledigte mit `"completed": true` und ggf. `completedAt`. Höchstens 20.
  - Zusätzlich je Eintrag `matchedIn` (Feldnamen). Der Notiztext eines Termins oder einer Aufgabe wird **nicht** mitgeschickt; dafür gibt es `get_task`.
- **Nicht im Werkzeug:** Notizen (Phase-5-Regel, Anti-Ziel in §2), Einkaufsliste (dafür gibt es in Phase 5 `list_shopping`), GitHub-Online-Suche.
- **Fehler:** `query` unter zwei Zeichen, `from` nach `to` oder Spanne über vier Jahre ergeben `{"error":"…"}` mit deutschem Text wie die übrigen Werkzeuge.
- **Anweisungen des Assistenten:** ein Satz, dass `search` für Fragen nach einem bestimmten Termin oder einer bestimmten Aufgabe zu nutzen ist.
- **Sprachmodus:** Das Werkzeug steht dort wie die anderen lesenden Werkzeuge zur Verfügung; eine Vorlese-Sonderregel gibt es nicht.

### 7.2 Einstellungen

Keine neue Einstellung, kein neuer Abschnitt. Die Suche folgt der vorhandenen Auswahl von Kalendern, Erinnerungslisten, Projects und der Einkaufslisten-Einstellung aus Phase 5.

### 7.3 Lokalisierung (EN)

Alle neuen Zeichenketten kommen mit englischem Text in die String-Kataloge (App: `Localizable.xcstrings`; Pakete: deren Kataloge).

| Deutsch | Englisch |
|---|---|
| Suchen | Search |
| Termine, Aufgaben, Notizen | Events, tasks, notes |
| Alle / Termine / Aufgaben | All / Events / Tasks |
| ✓ Erledigte | ✓ Completed |
| Termine · %lld kommende | Events · %lld upcoming |
| Aufgaben · %lld offen | Tasks · %lld open |
| Erledigt | Completed |
| Vergangene Termine | Past events |
| GitHub · online · %lld weitere | GitHub · online · %lld more |
| Notizen / Einkaufsliste | Notes / Shopping list |
| Ältere Termine durchsuchen | Search older events |
| vor %@ | before %@ |
| Auf GitHub suchen | Search on GitHub |
| auch geschlossene und fremde | including closed and unassigned issues |
| geschlossen / nicht zugewiesen / anderen zugewiesen / ohne Project | closed / unassigned / assigned to others / no project |
| %lld weitere bis %@ | %lld more until %@ |
| Weitere %lld zeigen | Show %lld more |
| Im Plan zeigen / In Aufgaben zeigen | Show in plan / Show in tasks |
| Wieder öffnen | Reopen |
| Durchsucht: 6 Monate zurück, 12 Monate voraus. | Searched: 6 months back, 12 months ahead. |
| Durchsucht: ab %@, 12 Monate voraus. | Searched: from %@, 12 months ahead. |
| Durchsucht Termine, Aufgaben, Notizen und die Einkaufsliste. | Searches events, tasks, notes and the shopping list. |
| Keine Treffer für „%@“. | No results for “%@”. |
| Termine werden durchsucht … | Searching events … |
| Online-Treffer öffnen sich auf GitHub. Zum Bearbeiten in Tagwerk muss ein Issue dir zugewiesen sein und in einem Project liegen. | Online results open on GitHub. To edit an issue in Tagwerk it must be assigned to you and belong to a project. |
| Keine Verbindung zu GitHub. / Erneut versuchen | No connection to GitHub. / Try again |
| Der Termin wurde geändert. | The event has changed. |

### 7.4 Mitteilungen und Deeplinks

Keine neuen. Trifft eine Mitteilung oder ein `tagwerk://`-Link ein, schließt das Suchblatt wie die anderen Blätter (`RootView.swift:120–145`), bevor navigiert wird.

### 7.5 Bedienungshilfen

- Lupe: Label „Suchen“, Hinweis „Durchsucht Termine und Aufgaben“.
- Abschnittsköpfe sind Überschriften; der Zähler ist Teil des Labels („Termine, 3 kommende“).
- Marken und Schalter melden ihren Zustand („ausgewählt“, „ein/aus“).
- Zeilen lesen Art, Titel, Zeit bzw. Fälligkeit und Quelle; die Fundstellen-Hinterlegung wird nicht vorgelesen.
- Menüeinträge aus §5.6 stehen zusätzlich als VoiceOver-Aktionen bereit.

## 8. Abhängigkeiten zu den anderen drei Vorhaben

Reihenfolge der Umsetzung (bindend): (1) #136 Issue-Zuweisung, (2) Phase 5 #113, (3) **Suche**, (4) Phase 7 #140.

| Vorhaben | Was die Suche davon braucht | Was die Suche liefert oder beachtet |
|---|---|---|
| **#136 Issue-Zuweisung** (vorher) | Zugewiesene stehen an der Aufgabe bzw. am `GitHubIssueRecord` zur Verfügung. Issues, die nicht (mehr) mir zugewiesen sind, verschwinden aus der geladenen Menge | Solche Issues findet nur die Online-Suche; die Marke „anderen zugewiesen“ in §5.5 deckt den Fall ab. Die Suche fügt den durchsuchten Feldern **keine** Zugewiesenen hinzu (Festlegung F12) |
| **Phase 5 Einkaufsliste und Notizen** (vorher) | (a) Einstellung „Einkaufsliste“ und der Ausschluss dieser Liste aus `taskList.items`; (b) ein Leseweg für offene Artikel und die Funktion „abhaken“; (c) `NoteRecord` mit Text, Art, Tag, Änderungsdatum und ein Notiz-Blatt, das sich als eigenes Blatt zeigen lässt; (d) die Einkaufsliste als einbettbare Ansicht | Abschnitte „Notizen“ und „Einkaufsliste“ (§6.3). Die Karte, die Phase 5 oben in „Aufgaben“ einfügt, liegt im Inhalt, nicht in der Leiste, und berührt die Lupe nicht |
| **Phase 7 Routinen** (danach) | nichts | Gedanken-Notizen (#143) liegen im selben `NoteRecord`-Speicher und werden dadurch ohne weitere Arbeit durchsucht; die Zeile nutzt die Bezeichnung „Tagesabschluss · 18.11.“. Phase 7 fügt in „Planen“ Karten ein, keine Leisten-Knöpfe; die Titelregel aus §6.1 bleibt gültig |

Wird Phase 5 wider Erwarten nach der Suche gebaut, entfallen die Aufgaben S9 und die Abschnitte 6 und 7; der Rest ist unabhängig.

## 9. Festlegungen des Builders („meine Festlegungen“)

Ohne Rückfrage getroffen; bei Bedarf widersprechen. **Fett** = bitte kurz ansehen.

1. **F1 Notizen werden durchsucht** (vom Nutzer offen gelassen): eigener Abschnitt „Notizen“ direkt über „Einkaufsliste“, alle Arten (frei, Tagesstart, Tagesabschluss), nur lokal.
2. **F2 Notizen und Einkaufsliste erscheinen nur unter „Alle“.** Es gibt keine vierte Marke; „Termine“ und „Aufgaben“ blenden beide Abschnitte aus.
3. **F3 Das Werkzeug `search` liefert Termine und Aufgaben, aber weder Notizen noch Einkaufsartikel noch GitHub-Online-Treffer.** Notizen wegen der Phase-5-Regel, Einkaufsartikel wegen `list_shopping`.
4. **F4 `search` nutzt die in den Einstellungen gewählten Kalender**, obwohl `list_events` heute alle Kalender liest. `list_events` bleibt unverändert.
5. **F5 „Im Plan zeigen“ springt bei Terminen zum Tag, ohne den Termin dort zu markieren.** Eine Markierung im Tagesraster wäre ein eigener Baustein (rund 2 h) und ist nicht enthalten.
6. **F6 Erledigte Erinnerungen: nur die der letzten 12 Monate**; erledigte lokale Aufgaben ohne Grenze. Der Schalter wird nicht gespeichert.
7. **F7 Einkaufsliste: nur offene Artikel**, auch bei eingeschaltetem „✓ Erledigte“.
8. **F8 GitHub-Online-Suche: höchstens 20 Treffer, kein Nachladen**, eingegrenzt auf die Repositories des Katalogs (höchstens 30).
9. F9 Durchsuchte Felder, Normalisierung („ß“ = „ss“, „ue“ ≠ „ü“), UND-Verknüpfung, Regel für Issue-Nummern wie in §5.2.
10. F10 Ab zwei Zeichen; 250 ms Verzögerung; der Terminabruf läuft einmal je Blatt und wird im Speicher gefiltert.
11. F11 Serien: eine Zeile mit „n weitere“; vergangene Vorkommen nur das jüngste. Zeitblöcke sind keine Treffer. Doppelte Termine werden wie in „Planen“ zusammengeführt.
12. F12 Zugewiesene (#136) sind kein Suchfeld.
13. F13 Zeitfenster-Erweiterung nur in die Vergangenheit; sie gilt bis zum Schließen des Blatts.
14. F14 Titelregel in „Planen“ (§6.1) mit Rückfallweg „Do., 19. Nov.“; Lupe links vom ＋; in „Aufgaben“ während „Auswählen“ ausgeblendet; im Sprachmodus deaktiviert.
15. F15 Eigener, nur lesender `EKEventStore` in einem `actor` für den Terminabruf; Rückfallweg in §5.3.
16. F16 Abschnitte zeigen zunächst 25 Zeilen; Suchwort und Filter werden beim Schließen verworfen; kein Verlauf, kein Spotlight, kein Deeplink.
17. F17 Online-Treffer sind nur lesbar und öffnen GitHub.
18. F18 Keine neue Einstellung und kein neues SwiftData-Modell.
19. F19 Abhaken in der Suche nutzt die vorhandene Widerrufen-Kapsel; „Wieder öffnen“ geht direkt über den Provider.
20. F20 Epic: eigenständiges Epic „Suche“ mit den Aufgaben aus §11.

## 10. Offene Punkte / Spikes am Gerät

Nichts in diesem Dokument ist am Gerät oder im Simulator geprüft. Vor dem Umsetzungsplan (S0, rund 2 h):

1. **Dauer des Terminabrufs über 18 Monate** mit den echten Kalendern, einmal über den vorhandenen Gateway (Hauptthread) und einmal über einen zweiten `EKEventStore` im Hintergrund. Ziel: Treffer unter 1 s nach dem ersten Suchwort. Zusätzlich: Sieht der zweite Store Änderungen des ersten ohne Neustart?
2. **Titelbreite in „Planen“** mit drei Einträgen rechts auf dem iPhone 16 Pro: längster Fall „Donnerstag, 25. Sept.“ bei Standard- und bei größter Schrift. Erhält `ViewThatFits` im Toolbar-Eintrag die verfügbare Breite?
3. **GitHub-Suche:** Reicht der Scope für die Issue-Suche in privaten Repositories? Nimmt eine Abfrage 30 `repo:`-Angaben an? Wie zählt ein Abruf gegen das Limit?
4. **Erledigte Erinnerungen:** Dauer der Abfrage über 12 Monate; liefert EventKit erledigte Vorkommen wiederkehrender Erinnerungen (offen seit Phase 4)?
5. **Blatt über Blatt:** `TaskEditorView` und `EntrySheet` über dem Suchblatt, inklusive Tastatur-Fokus beim Zurückkehren und „Im Plan zeigen“ aus dem inneren Blatt.

Am Quelltext geklärt, nicht am Gerät: Die Issue-Nummer kommt aus der URL (§5.2). `TaskEditorView` hat einen Schalter „Erledigt“ (`TaskEditorView.swift:115` **[Code]**) und kann damit eine erledigte Aufgabe zeigen und wieder öffnen; ob das Blatt mit einer Aufgabe außerhalb von `taskList.items` an jeder Stelle zurechtkommt, prüft S7 mit einem Test.

## 11. Aufgabenschnitt

Vorschlag: eigenständiges Epic **„Suche nach Terminen und Aufgaben“**, Aufgaben in dieser Reihenfolge. Stunden sind Schätzungen des Verfassers, keine Messwerte.

| # | Aufgabe | Inhalt | Hängt ab von | Stunden |
|---|---|---|---|---|
| S0 | Spike am Gerät | Punkte 1–3 und 5 aus §10, Ergebnis als Nachtrag in dieses Dokument | – | 2 |
| S1 | Suchkern | `SearchQuery`, Normalisierung, Felder, Issue-Nummer, Fundstellen, Tests | – | 4 |
| S2 | Terminquelle | `EventSearchReader`, Fenster, Erweiterung, Zusammenführen, Zeitblöcke, Serien-Gruppierung, Tests | S0, S1 | 5 |
| S3 | Aufgabenquelle und Erledigte | offene Aufgaben, `completedReminders`, erledigte lokale Aufgaben, Zusammenfassen gleicher Erledigter, Tests | S1 | 4 |
| S4 | `SearchModel` | Zustand, Verzögerung, Abbruch, Abschnitte aus `SearchResults`, Neuabruf bei Änderungen, Tests | S2, S3 | 3 |
| S5 | Suchblatt | Feld, Marken, Schalter, Abschnitte, Zeilen, Hinterlegung, Zustände, Fußzeile | S4 | 6 |
| S6 | Einstieg | Lupe in „Planen“ und „Aufgaben“, Titelregel, Zustand im `AppEnvironment`, Schließen durch Assistent/Mitteilung/Link | S0, S5 | 3 |
| S7 | Treffer-Aktionen | Blätter über der Suche, Termin neu auflösen, Menüs, „Im Plan zeigen“, Abhaken und Wieder öffnen | S5 | 4 |
| S8 | GitHub-Online-Suche | `searchIssues`, Abbildung, Abschnitt, Fehlerzustände, Tests mit dem Fake-Transport | S5 | 4 |
| S9 | Notizen und Einkaufsliste | zwei Abschnitte, Zeilen, Blätter, Abhaken | Phase 5, S5 | 3 |
| S10 | Werkzeug `search` | Definition, Ausführung, Antwortform, Anweisungssatz, Tests in `AppToolsTests` | S4 | 2,5 |
| S11 | Abschluss | englische Texte, Bedienungshilfen, `test-all.sh`, Geräte-Checkliste (§10, Punkt 4) | alle | 2 |
| | **Summe** | | | **42,5** |

Dem Umsetzenden überlassen: Ordnerstruktur innerhalb von `Search/`, Namen der Typen, Testaufbau, Farbton der Hinterlegung im Rahmen des Mockups.

## Nachtrag: Abweichungen bei der Umsetzung und Geräte-Checkliste

Stand 2026-11-19. Die Umsetzung steht auf dem Branch `feat/search-issues-planning`; Einzelheiten, Entscheidungen und offene Punkte stehen im Abschnitt „Suche“ von `../2026-11-19-overnight-log.md`.

**Abweichungen vom Spec.**
- Titelkandidaten in „Planen“ folgen dem Formatter („Do. 19. Nov.“, „Nov“) statt der festen Schreibweise aus §6.1.
- Notizen und Einkaufsliste öffnen in eigenen Blättern mit eigenem `NavigationStack` am Suchblatt; beide Phase-5-Ansichten sind dafür unverändert.
- Das Menü einer offenen Aufgabe ist gekürzt (Öffnen, Im Plan/In Aufgaben zeigen, Erledigt); der volle `TaskContextMenu` fehlt.
- Das Werkzeug `search` liefert von Notizfeldern nur `matchedIn`, nie Ausschnitte; ohne Kalenderzugriff meldet es `calendarAccess: false`.
- Wieder öffnen aus dem Editor einer erledigten Aufgabe meldet die Planung über `TaskListModel.didSave(_:wasCompleted:)`.

**Spike S0 (§10) und Geräte-Checkliste: noch offen.** Punkte 1, 2, 3 und 5 aus §10 wurden nicht am Gerät geprüft; gebaut ist der jeweilige Standardweg des Specs. Auszufüllen, sobald ein Gerät zur Verfügung steht:

| Prüfung | Ergebnis |
|---|---|
| Terminabruf 18 Monate (eigener Store), Sicht auf Änderungen des ersten Stores | offen |
| Titelbreite „Planen“, Standard- und größte Schrift | offen (Simulator iPhone 17, Standardschrift: lange Form passt) |
| GitHub: 30 `repo:`-Angaben, private Repositories | offen |
| Erledigte Erinnerungen: Dauer über 12 Monate, wiederkehrende Vorkommen | offen |
| Blatt über Blatt, „Im Plan zeigen“ aus dem inneren Blatt | offen |
| Erstes Suchwort: Aufgaben sofort, Termine unter 1 s | offen |
| Termin in der Kalender-App ändern, Blatt offen | offen |
| „Ältere Termine durchsuchen“ zweimal | offen |
| Abonnierter und zusammengeführter Termin, Deadline-Marke | offen |
| Abhaken mit Kapsel, „Wieder öffnen“, „Im Plan zeigen“ | offen |
| „Auf GitHub suchen“ mit und ohne Netz; kein Abruf beim Tippen | offen |
| Assistent nutzt `search`, Antwort ohne Notiztext | offen |
| Blatt schließt bei Assistent, Mitteilung, `tagwerk://plan/today` | offen |
