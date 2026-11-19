# Übernacht-Protokoll 19.11.2026

Jede umsetzende Instanz hängt hier einen eigenen Abschnitt an.

## #136 Zuweisung

Plan: `plans/2026-11-19-issue-assignees.md` · Spec: `specs/2026-11-19-issue-assignees-design.md` · Branch `feat/search-issues-planning`.
Umgesetzt sind die Tasks 1–10. Task 0 (Spike) und Task 11 (Geräteprüfung) sind manuell und offen.

Commits (in Reihenfolge): `7f63b0f` Kernmodell · `549c8f1` GitHubKit lesen · `993febb` GitHubKit schreiben · `06456ac` Listenmodell und Planung · `c6dc3ad` Blatt „Neue Aufgabe“ · `47494e5` Kapsel · `d7fdb7a` Editor · `02507da` Assistent: Werkzeuge · `8e8f556` Assistent: Karte, Instruktionen, Sprachmodus · `91631a9` Datenschutzhinweis und Texte.

### (a) Entscheidungen

Jede Entscheidung nennt die Optionen, die Wahl und das Risiko, falls sie falsch ist.

1. **Spikes S1–S4 nicht ausgeführt, Annahmen des Specs übernommen.** Optionen: warten oder mit den Vorgaben bauen. Gewählt: bauen. Damit gilt ungeprüft: der Scope `repo` reicht (kein Scope-Umbau), Zuweisen ändert `updatedAt` (Zugewiesene stehen nicht in `GitHubMapping.version`), GitHub verwirft nicht zuweisbare Logins still (kein eigener Fehlertext für 4xx), das eigene Austragen läuft über `DELETE …/assignees`. Risiko: Fällt ein Spike negativ aus, greifen die im Plan (Task 0) genannten Zusätze; sie sind nicht gebaut.
2. **`AssigneeSelection.names(… language: VoiceLanguage = .app)` statt `locale: Locale`.** Ein `Locale` wählt nur Formate, nicht die Sprache des Katalogs; die englische Karte (`describe(_:language:)`) braucht `Localized.string`. Risiko: Signatur weicht vom Plan-Interface ab; spätere Pläne nutzen sie nicht.
3. **Kapseltitel mit Textplatzhalter für die Nummer** (`%@ an %@`, `%@ ohne Zuweisung`, aufgerufen mit „#151“) statt `#%lld an %@`. Grund: Ohne Nummer in der URL entsteht „Issue an lea-m“ statt „#0 an …“. Die sichtbaren Texte entsprechen dem Spec. Risiko: zwei Katalogschlüssel heißen anders als in Spec §5.8.
4. **Fußtext bei drei oder mehr anderen ohne mich:** „Das Issue wird 3 Personen zugewiesen und erscheint danach nicht in deinen Aufgaben.“ Das Spec nennt nur „dir und 3 weiteren Personen“. Alternative wäre die volle Liste gewesen; gewählt wurde die Zählform wie in Zeile und Kapsel.
5. **Warnung bei mehreren verworfenen Logins behält den Wortlaut des Specs** („lea-m und sam konnte nicht zugewiesen werden.“). Eine Pluralform wäre sprachlich richtig, steht aber nicht im Spec. Risiko: holpriger Satz im seltenen Fall mehrerer verworfener Logins.
6. **Editor bietet „Ich“ nicht an, wenn ich weder zugewiesen noch zuweisbar bin**; bis die Liste geladen ist, zeigt das Menü nur die Zugewiesenen (Spec §5.6). Im Blatt wird „Ich“ dagegen immer angeboten (F5).
7. **`gitHubTarget`:** leeres `project_ids: []` wird wie `null` behandelt (die Quelle verlangt mindestens ein Project), der Repository-Name wird ohne Groß-/Kleinschreibung verglichen und in der Schreibweise des Katalogs geschrieben. Unbekannte Angaben erhalten eigene Fehltexte („Dieses Repository steht nicht in der Liste von list_github_targets.“).
8. **Nicht ladbare Zuweisbare** melden den vorhandenen Text „Personen konnten nicht geladen werden“ (Werkzeuge `list_assignees` und `create_task`), statt eines neuen Textes.
9. **Karte ohne auflösbares Ziel:** Fehlt der gespeicherte Katalog, zeigt die Karte das Repository aus dem Argument und „Project fehlt“; lässt sich nur das Project nicht auflösen, bleibt das Repository stehen.
10. **`OpenCards.guarded`:** „alle bestätigen“ wird auch dann abgelehnt, wenn die einzige offene Karte geschützt ist (gleiches Verhalten wie bei Löschungen); ein einfaches „Ja“ bestätigt sie.
11. **`SaveQuestion.handOver` hat Vorrang vor allen anderen Rückfragen**, auch vor `effortReach` (laut Spec kollidieren sie nicht; der Test legt es trotzdem fest).
12. **Anlegen über das Blatt mit ausschließlich verworfenem Login:** Warnung und Kapsel „ohne Zuweisung“ erscheinen beide (Review Focus 3).
13. **`apply` lädt den eigenen Login nach der Versionsprüfung und vor dem Schreiben** (nur wenn er unbekannt ist und Zuweisungen geändert werden). Alternative wäre vor dem ersten Lesen gewesen; so bleibt der Konfliktfall ohne Zusatzabruf.
14. **String Catalog:** Der App-Katalog bleibt im bisherigen JSON-Format (ein Lauf von `sync-strings.sh` hätte rund 13.000 Zeilen nur umformatiert); drei veraltete Schlüssel (zwei alte Fußtexte, alter Datenschutzhinweis) sind entfernt; deutsche Pluralformen für „%lld Personen“, „%lld weiteren Personen“ und „%lld geplante Zeitblöcke werden gelöscht.“ sind von Hand ergänzt, weil `check-strings.py` sie verlangt. Englische Texte stehen zusätzlich in `scripts/translations/en.json`.
15. **Zusätzliche Texte, die das Spec nicht nennt:** „Öffnet das Issue im Browser“ (VoiceOver-Hinweis des Kapselknopfs), „Vergeben: %@. Auf GitHub öffnen verfügbar.“ (Ansage), „Das Issue verschwindet aus Aufgaben und Planung.“ (Rückfrage ohne Nummer), „Mindestens ein Projekt wählen.“ (als eigener Satz), „Repository, Projects und Zugewiesene gibt es nur bei GitHub-Issues.“, „Project %@“.

### (b) Abweichungen vom Plan

- Neue Tests liegen in eigenen Suites mit eigenem Aufbau statt in den bestehenden: `TaskListAssigneeTests`, `TaskEditorAssigneeTests`, `AppToolsGitHubTests`, `AssistantGitHubCardTests`, `AssigneeLoadTests`. Dateien wie im Plan.
- Zusätzliche Hilfen: `AssigneeSelection.sorted(_:me:)` und `isMe`, `AssigneeLoad.logins(for:)`, `TaskEditorModel.setAssignees(_:candidates:)`, `HandedOverCapsule` (eine Ansicht für „Aufgaben“ und „Planen“), `AppTools.GitHubTargetError.message`, `Arguments.optionalStrings`.
- Task 8: Der rote Lauf bestand nur aus dem Übersetzungsfehler der neuen Tests; ein eigener Lauf vor der Umsetzung wurde nicht gestartet. Bei allen anderen Tasks wurde der rote Lauf ausgeführt und gelesen.
- `app/test-all.sh` lief vor jedem Commit ab Task 4. Die Commits der Tasks 1–3 wurden mit den Pakettests (`TagwerkCore`, `GitHubKit`) und den betroffenen App-Suites geprüft.
- Der Commit `549c8f1` (Task 2) enthält versehentlich die zu dem Zeitpunkt unversionierte Datei `plans/2026-11-19-phase-7-routines.md`; der spätere Commit `bb918c5` einer anderen Instanz hat sie überarbeitet. Inhaltlich ohne Folge.
- `DemoAITransport` sendet bei `create_task` jetzt die drei neuen Felder mit `null`.
- Die Sichtprüfungen im Simulator aus Task 5 Schritt 4 und Task 6 Schritt 4 entfielen (siehe c).

### (c) Offene manuelle Prüfungen am Gerät

- **S1** `GET …/assignees` und Zuweisen mit dem vorhandenen Token.
- **S2** Zuweisen ändert `updatedAt` des Issues.
- **S3** Stilles Verwerfen eines nicht zuweisbaren Logins.
- **S4** `DELETE …/assignees` mit dem eigenen Login im eigenen Repository.
- **S5** Menü mit rund 30 Einträgen und 10 gewählten bleibt bedienbar.
- **S6** Sprachmodus: Zuweisungskarte plus zweite Karte, „alle“ wird abgelehnt, einzelnes „Ja“ bestätigt.
- Abnahmekriterien 1–10 aus Spec §9 am Gerät.
- Sichtprüfung: Zeile „Zugewiesen“ im Blatt und im Editor, Fußtext, Rückfrage „Abgeben“, Kapsel „Vergeben“ in „Aufgaben“ und „Planen“ (8 Sekunden, Knopf öffnet GitHub).
- Benachrichtigung und Widget nach dem Abgeben eines Issues mit Fälligkeit (als Unit-Test abgedeckt, am Gerät ungeprüft).
- Dunkel, hell, größte Schriftstufe, Englisch, VoiceOver für die neuen Elemente.

### (d) Bekannte Lücken / nicht umgesetzt

- Für Menüzeile, Kapsel und Rückfrage gibt es keine UI-Tests; getestet ist die Logik dahinter (Texte, Reihenfolge, Ladezustand, Rückfrage-Entscheidung).
- Ohne S2 ist unbelegt, dass die Versionsprüfung fremde Änderungen an der Zuweisung erkennt.
- Weicht die Schreibweise des eigenen Logins im Entwurf von der GitHubs ab, merkt `create` das Issue nicht in `records` (die Regel `isVisible` blieb wie verlangt unverändert); die Liste zeigt es trotzdem, Kommentar und Issue-Chat gehen erst nach dem nächsten Laden. Blatt und Assistent schreiben immer GitHubs Schreibweise, der Fall ist dort nicht erreichbar.
- „Neu laden“ im Konfliktfall lädt die Zuweisbaren nicht erneut (Haltezeit 5 Minuten gilt weiter).
- Nicht-Ziele des Specs (§2) sind nicht gebaut: Filter „Vergeben“, fremde Repositories, Avatare, Suche, „zuletzt benutzt“, Offline-Warteschlange, Zuweisen über `update_task`.
- Abschlussreview: Selbstreview des Autors, kein unabhängiger Reviewer (keine Subagenten erlaubt).

### (e) Testergebnis

`app/test-all.sh`, letzter Lauf nach dem letzten Code-Commit (`91631a9`), alle Stufen grün einschließlich „string catalogs“:

- AIKit 98, GitHubKit 129, HealthBridge 11, RemindersKit 64, TagwerkCore 501, App 789 Tests bestanden.
- Letzte Zeile: `ALL TESTS PASSED`

## Phase 5 Einkaufsliste und Notizen

Plan: `plans/2026-11-19-phase-5-shopping-notes.md` · Spec: `specs/2026-11-19-phase-5-shopping-notes-design.md` · Branch `feat/search-issues-planning`, aufgesetzt auf dem Stand von #136.
Umgesetzt sind die Tasks 2–17. Task 1 (Spike am Gerät), die Sichtprüfungen im Simulator und die Geräte-Checkliste sind offen.

Commits (in Reihenfolge): `04a6611` RemindersKit: erledigte Erinnerungen, Datumsfelder, Schreibbarkeit · `16a8da7` `ShoppingListFilter`, Ausschluss im Provider · `645e943` Einstellungen, Ausschluss in Planung und Rückblick · `8c0646e` Eingabe zerlegen · `62b254e` Wörterbuch und Einordnung · `6eadb94` Kategorien-Speicher · `bf111a4` `ShoppingModel` · `14c6ad4` Einkaufsseite · `720ec00` Seite „Kategorien“ · `6edd59c` Einstieg in „Aufgaben“, Einstellungen · `0e3abe2` „Mit ChatGPT sortieren“ · `35b698a` Notizspeicher · `c58ac8e` Notizen: Liste, Schnellerfassung, Editor · `de84231` Assistent · `2f273c9` Kurzbefehle und Deeplink · `cfd6a9e` Abschluss (englische Texte, Demo-Daten, Nachtrag in der Spec) · `64f834b` Korrektur aus dem Abschlussreview.

**Schnittstellen für Suche und Phase 7:** alle Namen aus dem Plan sind unverändert vorhanden (`AppSettings.shoppingListID`, `ShoppingModel`, `ShoppingItem`, `ShoppingListView`, `NoteRecord` mit `kindRaw`/`dayKey`/`processedAt`/`wasDictated`, `NoteKind`, `NoteDayKey`, `NoteText`, `NoteStore` mit allen Methoden, `NoteEditorView`, `NotesListView.footer(for:now:calendar:)`, `AppRoute.shopping`, `TasksDestination`, `AppEnvironment.tasksPath`/`setShoppingList`/`taskReminderListIDs`, `ReminderStore.completedReminders`). **Keine Umbenennung.** Zusätzlich vorhanden: `ShoppingModel.categoryName(of:)`, `AppEnvironment.openShopping()`, `AssistantModel.describe(_:language:spoken:)` (neuer Parameter mit Standardwert).

### (a) Entscheidungen

Jede Entscheidung nennt die Optionen, die Wahl und das Risiko, falls sie falsch ist.

1. **Spike S1–S5 nicht ausgeführt, Annahmen der Spec übernommen.** Optionen: warten oder bauen. Gewählt: bauen. Ungeprüft gilt damit: `completionDate` ist gefüllt (sonst bleibt „Erledigt“ leer und das Wiederöffnen greift nicht), der Hintergrund-Intent darf schreiben, das Lesen erledigter Artikel ist schnell genug. Die Rückfälle aus Plan Task 1 sind nicht gebaut.
2. **`ä` wird zu `a` gefaltet, die Plan-Testzeile `key("Äpfel") != key("Apfel")` ist ersetzt.** Die Zeile widerspricht R2 der Spec; die Spec gilt. Folge: „Äpfel“ und „Apfel“ gelten als derselbe Artikel. Zusätzlich macht Foundation aus „ß“ ein „ss“; die Wörterbuchbegriffe folgen dem.
3. **Eine Zuordnung ohne Kategorie bedeutet immer „Sonstiges“**, auch wenn sie von ChatGPT stammt (Plan A4 nennt nur die Handzuordnung). Alternative: nur Handzuordnungen schlagen das Wörterbuch. Gewählt, weil eine übernommene Änderung „→ Sonstiges“ sonst wirkungslos wäre.
4. **Wörterbuch mit 581 Begriffen**, erzeugt aus Wortlisten je Kategorie. „Sojasauce“ und „Sauce“ fehlen bewusst, damit das Beispiel der Spec („Sojasauce · Sonstiges → Vorrat“) stimmt. Mehrere absehbare Fehltreffer der Endungsregel sind durch eigene Einträge abgefangen (Zahnpasta, Mundwasser, Sonnenmilch, Eiscreme, Thunfisch, Kaffeebohnen). Die Trefferquote ist nicht gemessen.
5. **Notizfeld gilt als „lang“, sobald nach der ersten Zeile Text folgt**, auch bei leerer erster Zeile. Schützt von Hand geschriebene Notizen; Preis: bei solchen Notizen ist die Menge nur lesbar.
6. **`restoreBuiltins` lässt eine Standardkategorie aus**, wenn ihr Name schon vergeben ist oder die Grenze von 30 erreicht wäre. Alternative wäre ein doppelter Name gewesen (Verstoß gegen R10).
7. **Marken der Eingabezeile entstehen laufend aus dem Feldinhalt;** „Senden“ legt genau die gezeigten Marken an, der Pfeil der Aufnahmeleiste füllt nur das Feld. Damit wird nach dem Diktat nie ohne weiteres Tippen gespeichert. Bei Notizen speichert der Pfeil dagegen sofort (dort verlangt die Spec keine Vorschau).
8. **Unterzeile der Einkaufsseite als erste Listenzeile** statt im Navigationskopf, weil ich die Verfügbarkeit von `navigationSubtitle` auf iOS nicht geprüft habe.
9. **Leerer Zustand von „Aufgaben“ ist jetzt eine Listenzeile** statt einer Überlagerung (vom Plan so vorgegeben, weil der neue Abschnitt immer Zeilen hat). Ungeprüft: ob die Zeile optisch dem bisherigen Bild entspricht.
10. **Zeile „Erinnerungslisten“ zeigt immer „n von m“** (vorher „Alle“, wenn alles gewählt war). Der Plan-Test legt „2 von 2“ fest.
11. **Mehrzahl mit zwei Platzhaltern in zwei Texte zerlegt** (Rückfrage beim Löschen einer Kategorie, „und 4 weitere“, „7 offene Erinnerungen.“, „3 Artikel hinzugefügt:“). Eine Pluralform mit zwei Platzhaltern in einem Katalogschlüssel bräuchte Ersetzungen; der sichtbare deutsche Wortlaut bleibt wie in der Spec.
12. **ChatGPT-Sortierung:** Eine vorgeschlagene neue Kategorie erscheint nur, wenn ihr ein Artikel zugeordnet wird; je Artikel zählt der erste Eintrag der Antwort, auch wenn er ungültig ist; `ShoppingSorter.apply` ist eine eigene, getestete Funktion; ohne sendbare Artikel erscheint „Es gibt keine Artikel zum Sortieren.“ und es geht nichts an ChatGPT.
13. **Sammelkarte des Assistenten nennt die Menge** („＋ 2 Zwiebeln“), weil alles, was geschrieben wird, vor dem Bestätigen sichtbar sein soll. **Für die Ansage** heißt die Karte „Hinzufügen: … · Abhaken: …“: Die Sprachausgabe verwirft „✓“, ein abgehakter Artikel klang sonst wie ein hinzugefügter (Fund aus dem Abschlussreview, mit Test behoben).
14. **Englische Texte:** „Übernehmen“ im Ergebnisblatt hat den eigenen Schlüssel „Vorschlag übernehmen“ (englisch „Apply“), weil „Übernehmen“ an anderer Stelle „Accept“ heißt; „Lösen“ bei Notizen hat den Schlüssel „Anheftung lösen“ (englisch „Unpin“, vorhandenes „Lösen“ heißt „Remove“); „Nicht jetzt“ bleibt beim vorhandenen „Not now“ statt „Not Now“ aus der Spec-Tabelle.
15. **Zugriffsabfragen und Einrichtung nutzen den eingesetzten `reminderStore`** (nicht mehr fest das Gateway). Im Betrieb ist das dasselbe Objekt.
16. **Kurzbefehl:** Wieder geöffnete Artikel zählen in der Antwort als hinzugefügt (Plan); „Liste verschwunden“ antwortet wie „keine Liste“. `AddToShoppingListIntent` bleibt im Hintergrund-Modus (S4 ungeprüft).
17. **Einkaufsliste wird zusätzlich mit jedem Neuladen der Aufgabenliste geladen** (Ziehen und Erscheinen von „Aufgaben“), damit der Zähler der Karte stimmt (Spec §5.1; der Plan nannte nur Start, EventKit-Meldung und Listenwechsel).

### (b) Abweichungen vom Plan

- `TasksDestination` und `AppEnvironment.tasksPath` sind schon in Task 9 entstanden (die Einkaufsseite braucht sie), nicht erst in Task 11.
- Neue Tests liegen teils in eigenen Suites statt in den genannten Dateien: `AppToolsShoppingTests` (statt `AppToolsTests`/`AssistantModelTests`), `ShoppingIntentTests` (statt `IntentServicesTests`).
- `FakeReminderStore.defaultListID` (Paket-Fake) heißt jetzt `defaultList`, weil Eigenschaft und Protokollfunktion `defaultListID()` nicht denselben Namen tragen können.
- Der Plan-Test `schema_opensExistingStore` ist durch `schema_containsNoteRecord` plus das unveränderte `ModelStoreLocationTests` ersetzt. Das Öffnen eines vorhandenen Stores mit altem Schema ist damit nicht als Test belegt.
- `ShoppingModel` hat zusätzlich `categoryName(of:)`; `InMemoryReminderStore` zählt zusätzlich `saveCount`.
- Task 12: Der Menüpunkt war nach Task 9/10 ausgegraut (wie im Plan), „✦ Sortieren“ aber schon sichtbar und ohne Wirkung; seit Task 12 arbeiten beide.
- `app/test-all.sh` lief vor jedem Commit, der die App berührt. Die Commits der Tasks 2, 3, 5 und 6 (nur Pakete) wurden mit den Pakettests geprüft, Task 6 zusätzlich mit der Katalogprüfung.
- Roter Lauf: bei jedem Task ausgeführt und gelesen. Bei reinen Text-Tests (Task 17, englische Texte) bestand der Test für die schon vorhandenen Texte sofort; rot waren nur die zwei abweichenden Zeilen.
- Die Kataloge werden über ein Hilfsskript im Scratchpad gepflegt (Abgleich wie `sync-strings.sh`, Format der Dateien bleibt erhalten); im Repository liegt es nicht. Englische Texte stehen zusätzlich in `scripts/translations/en.json`.

### (c) Offene manuelle Prüfungen am Gerät

- **S1** Einsortierung über EventKit angelegter Artikel in Apples Einkaufsliste.
- **S2** `creationDate` und `completionDate` für Artikel von anderen Geräten.
- **S3** Geteilte Liste: anlegen, abhaken, löschen; Verzögerung fremder Änderungen.
- **S4** Hintergrund-Intent schreibt, auch bei gesperrtem Gerät und beendeter App.
- **S5** Dauer von `predicateForCompletedReminders` über 7 Tage.
- Geräte-Checkliste aus Plan Task 17 Schritt 4, alle acht Punkte: Diktat mit Marken, Siri-Sätze und Rückfrage „Was soll auf die Liste?“, Kaltstart über `tagwerk://shopping`, Abhaken in „Erinnerungen“ erscheint ohne Neustart, keine Mitteilung und kein Eintrag in Planen/Widget/Rückblick für Artikel, Wörterbuch-Trefferquote, ChatGPT-Sortierung samt Flugmodus, Darstellung (hell, dunkel, größte Schrift, Englisch, VoiceOver).
- **Sichtprüfungen im Simulator (Tasks 9, 10, 11, 12, 14) sind ebenfalls nicht erfolgt.** Kein neuer Bildschirm wurde angesehen: Einkaufsseite, Blatt „Artikel“, Seite „Kategorien“ (dauerhafter Bearbeitungsmodus, Tippen zum Umbenennen), Karten und Vorschlagskarte in „Aufgaben“, leerer Zustand von „Aufgaben“ als Zeile, Einstellungsseite „Einkaufsliste“, gesperrte Zeile in „Erinnerungslisten“, Einwilligungs- und Ergebnisblatt, Notizenliste und Editor.

### (d) Bekannte Lücken / nicht umgesetzt

- Für alle neuen Ansichten gibt es keine UI-Tests; getestet ist die Logik dahinter. Layout, Gesten und Navigation sind unbelegt.
- Ob Knöpfe in der dauerhaft bearbeitbaren Kategorienliste antippbar sind und ob `navigationDestination(isPresented:)` im Pfad-Stack von „Aufgaben“ wie erwartet schiebt, ist nur aus dem Aufbau abgeleitet.
- `NotesListView` öffnet den Editor über `environment.tasksPath` (Vorgabe des Plans). Außerhalb des Tabs „Aufgaben“ (z. B. in einem Blatt der Suche) öffnet ein Tipp auf eine Karte deshalb nichts Sichtbares.
- Der Editor einer Notiz speichert nicht, wenn die App im Hintergrund beendet wird, bevor die 0,5 s Entprellung abläuft oder die Seite verschwindet.
- Die Rückfälle für durchgefallene Spikes (S2, S4, S5) sind nicht gebaut.
- Demo-Daten: drei Notizen und die Kategorien; einen Demo-Store für Erinnerungen gibt es nicht (wie im Plan). Die Demo-Antwort für `shopping_sort` ist ungeprüft.
- Die englische Ansage der Sammelkarte nennt die Artikelnamen in der Sprache, in der sie eingetragen sind.
- Nicht-Ziele der Spec (§2) sind nicht gebaut: Widget, fünfter Tab, Apples Abschnitte, mehrere Listen, Notiz-Funktionen im Assistenten, iCloud-Abgleich.
- Abschlussreview: Selbstreview des Autors, kein unabhängiger Reviewer (keine Subagenten erlaubt). Ein Fund (angesagte Sammelkarte) wurde mit Test behoben.

### (e) Testergebnis

`app/test-all.sh`, letzter Lauf nach dem letzten Code-Commit (`64f834b`), alle Stufen grün einschließlich „string catalogs“ (`check-strings.py --require-english` und `sync-strings.sh --check`):

- AIKit 98, GitHubKit 129, HealthBridge 11, RemindersKit 84 (vorher 64), TagwerkCore 529 (vorher 501), App 893 (vorher 789) Tests bestanden.
- Letzte Zeile: `ALL TESTS PASSED`
