# Notizen-Ordner, Tagebuch, Bible Study, Gewohnheiten-Vorschlag und Datensicherung (#152, #182, #186, #181, #158)

**Ziel:** Fünf aufeinander aufbauende Funktionen in einem Thread, in dieser Reihenfolge:

1. **#152** Ordner für Notizen, „Zuletzt gelöscht“, Verschieben, Sortieren, Suche in Notizen.
2. **#182** Tagebuch mit Gott als eigener Ordner mit Tagesvorlage und Import der bisherigen Einträge aus einem Notion-Export.
3. **#186** Bible Study mit Notiz je Bibelbuch, Sitzungen und Import aus Notion.
4. **#181** Gewohnheiten-Vorschlag aus dem früheren Notion-Tracker mit neuen automatischen Quellen (Tagesabschluss, Tagebuch, Bible Study).
5. **#158** Datensicherung als Export und Import einer Datei plus automatische Sicherung in einen gewählten Ordner. Deckt auch alle neuen Daten aus 1 bis 4 ab.

Abhängigkeiten: 2 und 3 brauchen die Ordner aus 1. 4 braucht die Quellen aus 2 und 3. 5 muss alle Datentypen kennen, die 1 bis 4 neu anlegen. Deshalb ein Thread in dieser Reihenfolge, je Stufe eigene Commits und ein grünes `app/test-all.sh`.

**Rahmen:** Rein technische Umsetzung ohne Mockups. Die Oberfläche folgt vorhandenen Mustern (List, Form, Swipe-Aktionen, Kontextmenüs, Sheets). Keine Änderungen an `TODO.md`, kein `t3gh`. Keine Zugriffe auf Notion. Der Import liest nur eine Exportdatei, die Melvin selbst in der App auswählt. Private Inhalte gehen nie an ChatGPT, außer über die bereits bestehende Zustimmung der Gedanken-Notizen, die für Tagebuch und Bible Study **nicht** gilt.

## Bestand (`APP` = `app/Tagwerk`, `PKG` = `app/Packages/TagwerkCore/Sources/TagwerkCore`)

- **Notizen:** SwiftData `NoteRecord` (`APP/Notes/NoteRecord.swift:8-36`): `id`, `text`, `createdAt`, `updatedAt`, `kindRaw` (`free/morning/evening`), `dayKey`, `isPinned`, `wasDictated`, `processedAt`, `derivedActionCount`. Bewusst CloudKit-tauglich: Standardwerte überall, keine Unique-Attribute, keine Relationships. Diese Regel gilt für alle neuen Notiz-Modelle weiter.
- `NoteStore` (`APP/Notes/NoteStore.swift`) ist der einzige Schreiber, mit `notes(_ filter: .all/.thoughts/.own)`. `NoteStore+Routines.swift` (`saveThought`). `NoteText`/`NoteKind`/`NoteDayKey` in `PKG/NoteText.swift`. `NoteTemplate` (Leitfragen) in `PKG/NoteTemplate.swift`.
- UI: `NotesListView` (Filter, Swipe, `captureBar`), `NoteEditorView` (TextEditor, 500 ms Debounce), `NoteEditorSheet` (`APP/App/EntrySheets.swift:52`). Navigation `TasksDestination { .notes, .note(UUID) }`, Einstiegszeile in `TasksEntrySection.swift:94`.
- Suche: `AppEnvironment.swift:444-455` → `NoteSearchItem`. `PKG/Search/SearchResults.swift`.
- **Gewohnheiten:** `PKG/HabitRules.swift` (`HabitSource: manual, water, workout, steps, daylight`, `HabitFacts`, `HabitRules.isSourceFulfilled` Z. 142, `maximumActive = 10`, eine automatische Quelle je Gewohnheit). Persistenz `APP/Routines/HabitRecords.swift`, `HabitsModel.refreshLocal` (Z. 121), `HabitSheet.sources` (Z. 20), `HabitText`. Das Rezept für eine neue Quelle steht in der Recherche: Enum-Fall, Regel, `HabitFacts`-Feld, Text, Befüllung, Picker, Strings, Tests.
- **Routinen:** `RoutineDayRecord.closeCompletedAt` (Tagesabschluss erledigt), `RoutineStore`, „Vorschlag übernehmen“-Muster `RoutineStore.adoptSuggestion()` (`RoutineRecords.swift:219`) mit `RoutineSchedule.suggestedItems` (`PKG/RoutineSchedule.swift:83-87`). Abendregel: vor 04:00 zählt zum Vortag.
- **Persistenz gesamt:** ein SwiftData-Store (`ModelContainerFactory.swift`, Application Support, nicht im App-Group-Container) mit 35 Modellen. Schlüsselbund: `github.credentials`, `chatgpt.tokens`, `chatgpt.client-id`, `chatgpt.host-id` (nie exportieren). UserDefaults nur `tagwerk.aiPlanningRuns` (Diagnose). Dateien: `widget-snapshot.json` (abgeleitet). Unique-Attribute siehe Recherche. Ein Restore arbeitet deshalb mit eigenen DTOs über natürliche Schlüssel, nicht mit `PersistentIdentifier`.
- Signierung: **Personal Team, also kein iCloud/CloudKit möglich.** iCloud-Abgleich scheidet aus. Sicherung als Datei, auch nach iCloud Drive über einen vom Nutzer gewählten Ordner (security-scoped Bookmark, keine Berechtigung nötig).
- Tests: Swift Testing. Reine Logik in `TagwerkCoreTests`, SwiftData in `app/TagwerkTests` mit `ModelContainerFactory.make(inMemory: true)` (Container als gespeicherte Eigenschaft der Suite halten). `testNow()`/`testCalendar()` in `TagwerkTests/Fakes/FakeTaskProvider.swift:134-146`. Demo-Daten `APP/App/DemoData.swift` (`seedNotes`).

## Struktur in Notion (Recherche vom 2026-11-19, nur Struktur, keine Inhalte)

- **Habit Tracker (aktuelle Fassung):** eine Zeile je Tag, Checkboxen: Wasser trinken, Bett machen, Bewegung, Journal schreiben, Lesen, Sonnenlicht, Duschen, Tag reflektieren, Bible Study, Lernen. Eine ältere Kopie hatte zusätzlich Kalte Dusche und Meditieren. Maßgeblich ist die aktuelle Fassung mit den zehn Gewohnheiten aus #181.
- **Tagebuch mit Gott:** Einträge sind Zeilen der „📔 Notizen Datenbank“ und nur über die Relation `🗄️ Resource / FACH` = „📓 Mein Tagebuch mit Gott“ erkennbar (`Art der Notiz` ist „Normale Notiz“). 19 Einträge (18 von 2024-03-16 bis 2024-04-05, einer vom 2025-12-09).
  - Datum ohne Property: Titel `DD.MM.YYYY` (2024) bzw. `Tagebuch mit Gott (YYYY-MM-DD)` (2025).
  - Titel enthalten Tippfehler (`05.05.2024` statt 05.04., Jahr 2023 statt 2024). Darum gegen `Created time` prüfen. `Created time` ist UTC und liegt teils nach Mitternacht.
  - Seitenaufbau: „ALLGEMEINE STIMMUNG“ (Frage „Wie geht es mir im Moment grundsätzlich?“), „HAUPTERLEBNISSE DES HEUTIGEN TAGES“, „TAGEBUCH:“ mit Freitext.
- **Bible Study:** keine eigene Datenbank. 18 Zeilen der Notizen-Datenbank mit `🗄️ Resource / FACH` = „📖 Bible Studies“, **eine Notiz je Bibelbuch** (Titel = Buchname, z. B. „Römer“, „1. Korinther“). Aufbau: „GENERELLE GEDANKEN“, „ACTION ITEMS“ (Aufgaben), „NOTIZEN:“ mit einzelnen Beobachtungen samt Versangabe. Sitzungen wurden nur über das Häkchen „Bible Study“ im Habit-Tracker erfasst. Kein Leseplan gefunden.
- **Notion-Export „Markdown & CSV“** (Format laut Doku, nicht mit echter Datei geprüft):
  - `<Datenbank> <32-hex-id>_all.csv` (eine Spalte je Property, Datumswerte als lokalisierter Text, Relationen als Seitenname mit Link).
  - Daneben ein Ordner mit `<Titel> <id>.md` je Zeile: `# Titel`, dann `Key: value`-Zeilen, dann der Text. Callouts und Toggles werden flach.
  - Der Parser muss deshalb tolerant sein und gegen echte Exporte nachgebessert werden können. Testdaten erfindet der Thread selbst, nie echte Inhalte.

## Stufe 1: Ordner und Funktionsumfang (#152)

**Modell**
- Neues `@Model NoteFolderRecord`: `id: UUID`, `name: String`, `parentID: UUID?`, `order: Int`, `createdAt: Date`, `roleRaw: String?` (für Systemordner, z. B. `journal`, `bibleStudy`). Standardwerte, keine Unique-Attribute, keine Relationships.
- `NoteRecord` bekommt `folderID: UUID?` (nil = „Notizen“, der Standardordner) und `deletedAt: Date?`. Nur Felder mit Standardwert.
- Logik als reine Typen in TagwerkCore (`NoteFolderRules`), mit Tests:
  - Baum aus Ordnern bilden.
  - Maximale Tiefe 3.
  - Löschen eines Ordners verschiebt seine Notizen nach „Zuletzt gelöscht“ und löscht Unterordner mit.
  - Namensregeln: nicht leer, keine doppelten Namen auf derselben Ebene, Länge wie `HabitRules.nameLimit`.
  - Endgültiges Löschen nach 30 Tagen in „Zuletzt gelöscht“.
  - Ordner-Anzahl je Ordner einschließlich Unterordner.

**Store**
- `NoteStore` bleibt der einzige Schreiber: `folders()`, `createFolder(name:parentID:)`, `renameFolder`, `deleteFolder`, `moveFolder`, `move(noteIDs:to:)`, `trash(noteID)`, `restore(noteID)`, `purgeExpired(now:)`.
- `notes(_:)` blendet gelöschte aus, außer im Filter „Zuletzt gelöscht“.
- Bestehende Aufrufer von `delete` prüfen: Wischen in der Liste verschiebt künftig in den Papierkorb, `deleteIfEmpty` löscht weiterhin endgültig.

**Oberfläche**
- `NotesListView` wird zur Ordneransicht. Oben „Alle Notizen“, dann „Notizen“ (Standardordner), dann eigene Ordner als Baum (DisclosureGroup oder Navigation in Unterordner), dann Systemordner, unten „Zuletzt gelöscht“ mit Anzahl.
- Die Gedanken-Notizen (`morning`/`evening`) erscheinen als virtueller Ordner „Gedanken“. Der bisherige Filter Alle/Gedanken/Eigene entfällt dafür. Echte Ordner für Tagesstart und Tagesabschluss sind #180 und nicht Teil dieses Plans.
- Ordner-Ansicht: Notizliste wie heute, `.searchable` für die Suche innerhalb des Ordners (Titel und Text, Normalisierung wie in der globalen Suche, z. B. `SearchDocument` oder die Faltungsfunktion aus `PKG/Search`, wiederverwenden).
- Sortiermenü: Bearbeitet, Erstellt, Titel. Angeheftete bleiben oben. Wahl je Ordner nicht nötig, eine globale Einstellung in `AppSettings` genügt.
- Ordner anlegen, umbenennen und löschen über Toolbar-Menü und Kontextmenü (Bestätigung beim Löschen mit Anzahl der Notizen).
- Notiz verschieben: Kontextmenü und Swipe „Bewegen“ öffnen ein Blatt mit Ordnerauswahl. Mehrfachauswahl über `EditButton`/Auswahlmodus mit Aktionen „Bewegen“ und „Löschen“.
- „Zuletzt gelöscht“: Wiederherstellen (in den alten Ordner, falls es ihn noch gibt, sonst „Notizen“), „Endgültig löschen“, „Alle löschen“.
- Teilen: `ShareLink` mit dem Notiztext im Editor-Menü.
- `captureBar` legt neue Notizen im aktuell geöffneten Ordner an.
- `purgeExpired` beim App-Start und beim Öffnen der Notizen aufrufen.

**Abgleich mit Apple Notizen**
- Eine Tabelle im Plan: Funktion, Apple Notizen, Tagwerk nach dieser Stufe, offen.
- Checklisten, Formatierung, Tabellen, Bilder und Anhänge gehören zu #155. Tags, Sperren und Teilen mit anderen sind offen und kommen ins Design-Sammelissue.

**Farbfehler aus #173**
- Die Zeilen der Notizliste und der Kategorienliste der Einkaufsliste (`Shopping/ShoppingCategoriesView.swift`) erscheinen ganz in Akzentblau statt in normaler Textfarbe. Vermutlich fehlt bei `NavigationLink`/`Button` `.buttonStyle(.plain)` bzw. `.foregroundStyle(.primary)`.
- Beim Umbau der Notizliste beheben, die Kategorienliste ebenso.

**Suche (global)**
- `NoteSearchItem` bekommt den Ordnernamen als zusätzliches Feld, z. B. als `kindLabel` oder als eigenes Feld.
- Gelöschte Notizen erscheinen nicht.

**Tests:** `NoteFolderRules` (Core), `NoteStoreTests` (Ordner, Verschieben, Papierkorb, Ablauf nach 30 Tagen, Sortierung), Such-Tests.

**Demo-Daten:** zwei Ordner, einer davon mit einem Unterordner, und eine Notiz in „Zuletzt gelöscht“.

## Stufe 2: Tagebuch mit Gott (#182)

**Ablage**
- Systemordner mit `roleRaw = "journal"`, Name „Tagebuch mit Gott“ (umbenennbar, nicht löschbar).
- Er wird beim ersten Öffnen des Tagebuchs angelegt.

**Eintrag**
- `NoteKind.journal` (neuer Fall, unbekannte Werte fallen wie bisher auf `.free` zurück) mit `dayKey`, ein Eintrag je Tag, Upsert wie `saveThought`.
- Die Abendregel gilt: vor 04:00 zählt zum Vortag. Die vorhandene Funktion wiederverwenden.

**Vorlage**
- Reiner Text, wie bei den Leitfragen.
- `JournalTemplate` in TagwerkCore mit drei Abschnitten:
  - „Allgemeine Stimmung“ mit der Frage „Wie geht es mir im Moment grundsätzlich?“
  - „Haupterlebnisse des heutigen Tages“
  - „Tagebuch“
- Lokalisiert.
- `isOnlyTemplate(_:)` erkennt einen unberührten Eintrag. Wichtig für die Gewohnheitsquelle in Stufe 4 und für das Löschen leerer Einträge.

**Einstiege**
- Im Systemordner oben „Heute schreiben“.
- Im Blatt „Tagesabschluss“ eine Zeile „Tagebuch schreiben“, die den heutigen Eintrag im `NoteEditorSheet` öffnet.

**Datenschutz**
- Tagebuch-Einträge sind ausgeschlossen aus:
  - `NoteSuggestionModel`, auch mit Zustimmung
  - den Werkzeugen des Assistenten
  - dem Widget
- Die globale Suche in der App zeigt sie, denn sie ist lokal. Dafür ein zentrales Prädikat `NoteKind.isPrivate` und ein Test, der alle Ausschlussstellen absichert.

**Import aus Notion**
- Einstellungen → Notizen → „Aus Notion importieren“. Den Abschnitt „Notizen“ in `SettingsView` gibt es noch nicht. Er wird angelegt und zeigt auch die Sortierung.
- Ablauf:
  - `fileImporter` für einen Ordner. Melvin entpackt den Notion-Export vorher in der Dateien-App, das Entpacken passiert dort per Tipp.
  - Nur Ordner, kein eigener ZIP-Leser. Ein Hinweis erklärt das Entpacken in der Dateien-App.
- Parser als reiner Typ in TagwerkCore (`NotionExportParser`):
  - Findet die `_all.csv` der Notizen-Datenbank.
  - Filtert die Zeilen, deren Resource-Spalte „Tagebuch mit Gott“ enthält.
  - Ordnet die `.md`-Dateien über die ID-Endung zu.
  - Entfernt die `# Titel`-Zeile und die Property-Zeilen.
  - Übernimmt den Text und wandelt die Überschriften in die Abschnitte der Vorlage.
- Datum:
  - Titel parsen (`DD.MM.YYYY` oder `(YYYY-MM-DD)`) und gegen `Created time` prüfen.
  - Weicht der Titel um mehr als einen Tag ab, gilt `Created time` mit der 04:00-Regel in der Zeitzone des Geräts.
  - Ohne verwertbares Datum wird der Eintrag nicht importiert und in der Vorschau gelistet.
- Vorschau vor dem Import: Anzahl, Zeitraum, Konflikte (Tag hat schon einen Eintrag), nicht zuordenbare Einträge.
- Konflikt: Der importierte Text wird unter einer Trennlinie „Aus Notion importiert“ angehängt, nichts wird überschrieben.
- Ein zweiter Import derselben Datei erzeugt keine Dubletten: Marker mit der Notion-ID im Text oder ein Feld `importSourceID: String?` an `NoteRecord`. Das Feld ist sauberer.
- Tests: CSV-Parsing mit Anführungszeichen, Zeilenumbrüchen in Feldern und BOM, Datumsregeln samt beider Tippfehler-Fälle, Dubletten, Konflikte. Mit erfundenen Daten in `Fixtures`.

## Stufe 3: Bible Study (#186)

**Ablage:** Systemordner `roleRaw = "bibleStudy"`, Name „Bible Study“. Darin eine Notiz je Bibelbuch, wie in Notion.

**Buchliste**
- Statische Liste der 66 Bücher in deutscher Schreibweise wie in Notion („1. Korinther“) mit englischen Namen.
- Als `BibleBooks` in TagwerkCore, inklusive Normalisierung („1 Kor“, „1.Korinther“, „Römer“/„Roemer“).

**Buchnotiz-Vorlage:** „Generelle Gedanken“, „Action Items“, „Notizen“.

**Sitzung**
- Neues `@Model BibleStudySessionRecord`: `id`, `dayKey`, `book`, `passage: String` (z. B. „3,21-31“), `noteID: UUID`, `startedAt`, `completedAt: Date?`. Standardwerte, keine Unique-Attribute.
- Ablauf „Bible Study starten“:
  1. Buch wählen (zuletzt gelesenes Buch vorgeschlagen) und Stelle eingeben.
  2. Die Buchnotiz öffnet sich mit einem neuen datierten Abschnitt unter „Notizen“, z. B. „19.11.2026 · 3,21-31“.
  3. „Abschließen“ setzt `completedAt`.
  4. Eine abgeschlossene Sitzung erfüllt die Gewohnheit (Stufe 4).
- Einstiege:
  - im Systemordner
  - im Blatt „Tagesstart“ eine Zeile, wenn eine Gewohnheit mit Quelle Bible Study existiert, sonst in Stufe 4 nachziehen

**Datenschutz:** wie Stufe 2, gleiches Prädikat.

**Import aus Notion**
- Gleicher Importer und Parser, zweite Auswahl „Bible Study“.
- Zeilen mit Resource „Bible Studies“ werden zu Buchnotizen, der Titel ist der Buchname.
- Vorhandene Buchnotiz: Der Text wird unter „Aus Notion importiert“ angehängt.
- Sitzungen lassen sich aus Notion nicht ableiten und werden nicht erzeugt.

**Tests:** `BibleBooks`-Normalisierung, Sitzungs-Store, Import.

## Stufe 4: Gewohnheiten-Vorschlag (#181)

**Neue Quellen**
- `HabitSource.eveningClosed` (Tagesabschluss erledigt: `RoutineDayRecord.closeCompletedAt` für den Tag)
- `HabitSource.journal` (Tagebuch-Eintrag des Tages, der nicht nur aus der Vorlage besteht)
- `HabitSource.bibleStudy` (abgeschlossene Sitzung am Tag)
- Je Quelle nach dem Rezept der Recherche: Regel, `HabitFacts`-Feld (Menge von Tagen oder Bool je Tag im Fenster), `HabitText`, `HabitsModel`-Befüllung, `HabitSheet.sources`, Strings, Tests.

**Vorschlag**
- `HabitSuggestions` in TagwerkCore mit den zehn Gewohnheiten aus Notion, mit Symbol und Quelle:

| Gewohnheit | Quelle | Symbol (Beispiel) |
|---|---|---|
| Tag reflektieren | `eveningClosed` | `moon.stars` |
| Bett machen | manuell | `bed.double` |
| Bewegung | `workout` | `figure.walk` |
| Journal schreiben | `journal` | `book.closed` |
| Duschen | manuell | `shower` |
| Sonnenlicht | manuell (`daylight` ist noch nicht gebaut) | `sun.max` |
| Wasser trinken | `water` | `drop` |
| Lernen | manuell | `graduationcap` |
| Lesen | manuell | `book` |
| Bible Study | `bibleStudy` | `book.pages` |

- Namen lokalisiert, zum Übernahmezeitpunkt gelesen wie `suggestedItems`.

**Übernahme**
- In `HabitListView` ein Knopf „Vorschlag übernehmen“, solange mindestens eine vorgeschlagene Gewohnheit fehlt (Vergleich über Namen, normalisiert).
- Er öffnet ein Blatt mit Häkchen je Gewohnheit, vorausgewählt.
- Beachtet `maximumActive = 10` und die Regel „eine automatische Quelle je Gewohnheit“ (`takenSources`). Ist eine Quelle schon vergeben, wird der Vorschlag als manuell übernommen, mit Hinweis.
- Die Regeln als reine Funktion mit Tests.

## Stufe 5: Datensicherung (#158)

**Format**
- Eine JSON-Datei `Tagwerk-Sicherung-YYYY-MM-DD-HHmm.json` mit `{ format: "tagwerk-backup", schemaVersion: 1, appVersion, createdAt, entities: { … } }`.
- Eigene `Codable`-DTOs je Modell in einem Ordner `APP/Backup/`. Natürliche Schlüssel statt `PersistentIdentifier`.

**Enthalten:** alle eigenen Daten.
- Einstellungen (`AppSettings` ohne Geheimnisse)
- lokale Aufgaben samt Erledigt-Vorkommen
- Planung (DayAssignment usw.), Event-Markierungen
- Erfassen (Mahlzeiten, Getränke, Training)
- Einkaufs-Kategorien und -Zuordnungen
- Notizen, Ordner, Tagebuch
- Bible-Study-Sitzungen
- Gewohnheiten und Häkchen
- Routinen-Tage, Abend-Checkliste, Fokus-Markierungen, Wochenreflexion

**Ausgeschlossen**
- Caches: `CachedGitHubIssue`, `CachedGitHubCatalog`, `GitHubSyncState`, `PlanSuggestionRecord`, `PendingHealthDeletion`
- `ChatThreadRecord` (Chatverlauf)
- `tagwerk.aiPlanningRuns`, Widget-Snapshot
- **alle Schlüsselbund-Einträge**

**Vollständigkeitsprüfung**
- Ein Test verlangt für jeden registrierten Modelltyp in `ModelContainerFactory.schema` entweder einen DTO oder einen Eintrag in einer expliziten Ausschlussliste. Ein künftiges Modell ohne Entscheidung lässt den Test scheitern.

**Datenschutz-Schalter**
- Einstellung „Tagebuch und Bible Study einschließen“ (Standard: an), gilt für „Jetzt sichern“ und die automatische Sicherung.
- Footer: Die Datei ist unverschlüsselt und liegt dort, wo sie gespeichert wird (z. B. iCloud Drive).
- Wird eine Datei ohne diese Inhalte wiederhergestellt, bleiben vorhandene Tagebuch- und Bible-Study-Einträge erhalten, statt gelöscht zu werden.

**Wiederherstellen**
- Ersetzt nach Bestätigung alle enthaltenen Daten.
- Vorher wird automatisch eine Sicherung des aktuellen Stands in den App-Dokumenten abgelegt.
- Dateien mit höherer `schemaVersion` werden mit Meldung abgelehnt.
- Geräteabhängige IDs (Kalender, Erinnerungslisten, Einkaufsliste) werden übernommen. Fehlen sie auf dem Gerät, gilt das bestehende Verhalten für fehlende Listen. Das wird im Footer erklärt.

**Automatische Sicherung**
- In den Einstellungen einen Ordner wählen (`fileImporter` mit `.folder`, security-scoped Bookmark als `Data` in `AppSettings`), etwa iCloud Drive/Tagwerk.
- Beim Wechsel in den Hintergrund wird gesichert, wenn die letzte Sicherung älter als 24 Stunden ist.
- Die letzten 7 Dateien bleiben, ältere werden gelöscht. Gelöscht werden nur Dateien mit dem eigenen Namensmuster.
- Fehler, etwa ein ungültiges Bookmark, erscheinen in den Einstellungen und blockieren nichts.

**Einstellungen:** neue Seite „Datensicherung“ mit:
- „Jetzt sichern“ (Teilen-Blatt bzw. `fileExporter`)
- „Wiederherstellen …“ (`fileImporter`)
- Ordner für die automatische Sicherung, letzte Sicherung, Schalter

**Tests**
- Rundlauf Export → Import für jeden DTO in einen leeren In-Memory-Store mit Gleichheitsvergleich.
- Abwehr einer höheren Version.
- Keine Geheimnisse in der Datei (Suche nach Token-Schlüsseln im JSON).
- Vollständigkeitsprüfung.
- Aufräumen der alten Dateien als reine Funktion.

## Für das Design-Sammelissue

- **Notizen:**
  - Ordneransicht und Verhalten von „Alle Notizen“ und „Gedanken“
  - Sortiermenü
  - Mehrfachauswahl
  - Tags, Sperren und Teilen mit anderen: gewünscht?
  - Abgleich mit Apple Notizen bestätigen
- **Tagebuch:**
  - Einstieg im Tagesabschluss
  - Vorlage als Text oder Felder
  - Verhältnis zur Gedanken-Notiz
  - Import-Ablauf und Anhängen bei Konflikten
- **Bible Study:**
  - Ablauf einer Sitzung
  - Buchauswahl
  - Leseplan und Erinnerung: gewünscht?
  - Action Items als Tagwerk-Aufgaben?
- **Gewohnheiten:**
  - Zuordnung der Quellen bestätigen (Bewegung über Training oder Schritte?)
  - Symbole
  - Darstellung automatisch erfüllter Gewohnheiten (siehe auch #173, Punkt 11)
  - Import der Häkchen-Historie aus Notion: gewünscht?
- **Datensicherung:**
  - Einstellungsseite
  - Chatverlauf sichern, ja oder nein
  - Standard des Schalters „Tagebuch und Bible Study einschließen“ und ob Sicherungen verschlüsselt werden sollen
  - Intervall und Anzahl der automatischen Sicherungen
  - Wiederherstellen als Ersetzen statt Zusammenführen

## Aufgaben

1. Plan nach `docs/superpowers/plans/2026-11-19-notes-journal-bible-habits-backup.md` legen und committen.
2. Stufen 1 bis 5 in dieser Reihenfolge. Je Stufe:
   1. reine Logik in TagwerkCore mit Tests
   2. Store und Modelle mit App-Tests
   3. Oberfläche
   4. Strings (deutsch als Schlüssel, Englisch)
   5. Demo-Daten
   6. `app/test-all.sh` grün
   7. Commits mit Präfix `feat:`/`fix:`/`test:`/`docs:`
3. Nach jeder Stufe einen kurzen Abschnitt „Stand“ am Ende dieses Plans: Was ist gebaut, welche Entscheidungen weichen ab, was ist offen.
4. Wenn eine Stufe wegen eines Befunds im Code nicht wie geplant geht: begründete Annahme treffen, im Plan dokumentieren, weiterarbeiten. Nur bei einer echten Richtungsfrage (z. B. Datenverlust möglich) anhalten und fragen.

## Stand nach Stufe 1 (Notizen-Ordner, #152)

**Gebaut**
- Core: `NoteFolderRules` (Baum, Tiefe 3, Namensregeln, Verschiebe-Prüfung, Zähler samt Unterordnern, 30-Tage-Frist), `NoteSortOrder`/`NoteSortKey`, `NoteText.matches` (Suche mit der Faltung der globalen Suche).
- App: `NoteFolderRecord`, `NoteRecord.folderID`/`deletedAt`, `AppSettings.noteSortOrderRaw`; `NoteStore` mit Ordnern, `move`, `trash`/`restore`/`emptyTrash`/`purgeExpired`, Sortierung, `ensureSystemFolder` (für Stufe 2 und 3).
- Oberfläche: `NotesFoldersView` (Alle Notizen, Notizen, Gedanken, Ordnerbaum, Systemordner, Zuletzt gelöscht), `NotesListView` je Ordner (Suche, Sortiermenü, Mehrfachauswahl mit Bewegen und Löschen, Swipe, Kontextmenü, Teilen), `NoteFolderPickerSheet`, Teilen und Papierkorb im Editor.
- Farbfehler #173: `.buttonStyle(.plain)` auf den Zeilen der Notizliste und der Kategorienliste der Einkaufsliste. Nur per Quelltext behoben, nicht am Gerät gesehen.
- Globale Suche: Notizen im Ordner tragen den Ordnernamen als Art-Bezeichnung (`kindLabel`), gelöschte Notizen erscheinen nicht.
- Demo-Daten: zwei Ordner (einer mit Unterordner) und eine Notiz in „Zuletzt gelöscht“.

**Entscheidungen und Abweichungen**
- Der Ordnerbaum steht eingerückt in einer flachen Liste statt als `DisclosureGroup`. Ein Tipp öffnet die Notizen genau dieses Ordners, die Zahl am Rand zählt Unterordner mit.
- Systemordner (`roleRaw` gesetzt) lassen sich umbenennen, aber weder löschen noch bewegen und nehmen keine Unterordner auf.
- Nur eigene Notizen (`kind == .free`) lassen sich bewegen. Gedanken-Notizen bleiben im virtuellen Ordner „Gedanken“, der nur erscheint, wenn es welche gibt.
- „Notizen“ (Standardordner) zeigt eigene Notizen ohne Ordner. Eine Notiz mit unbekanntem Ordner zählt dazu. „Alle Notizen“ zeigt alles außer dem Papierkorb.
- Eine gelöschte Notiz behält ihre `folderID`. „Wiederherstellen“ setzt sie zurück, oder nach „Notizen“, wenn der Ordner fehlt. Ein Ordner löscht seine Unterordner und schickt deren Notizen in den Papierkorb. Angeheftete Notizen verlieren dabei die Anheftung.
- Wischen und das Editor-Menü verschieben ohne Rückfrage in den Papierkorb (es gibt den Weg zurück). Endgültiges Löschen fragt nach. `NoteStore.delete` bleibt endgültig (Tagesabschluss ohne Text, `deleteIfEmpty`).
- Eine gelöschte Gedanken-Notiz blockiert keine neue für denselben Tag (`note(kind:dayKey:)` ignoriert den Papierkorb).
- `purgeExpired` läuft beim Öffnen der Ordneransicht und der Notizliste. Der Aufruf beim App-Start folgt in Stufe 5 zusammen mit dem Hintergrundwechsel.

**Abgleich mit Apple Notizen**

| Funktion | Apple Notizen | Tagwerk nach Stufe 1 | Offen |
|---|---|---|---|
| Ordner und Unterordner | ja | ja, bis Tiefe 3 | – |
| Zuletzt gelöscht (30 Tage) | ja | ja | – |
| Notizen verschieben, Mehrfachauswahl | ja | ja | – |
| Sortierung | ja (Datum, Titel) | ja (Bearbeitet, Erstellt, Titel), global | Wahl je Ordner |
| Suche | ja | ja, je Ordner und global | Suche im Papierkorb |
| Anheften | ja | ja | – |
| Teilen als Text | ja | ja | Teilen mit anderen |
| Checklisten, Formatierung, Tabellen, Bilder, Anhänge | ja | nein | #155 |
| Tags, Sperren | ja | nein | Design-Sammelissue |
