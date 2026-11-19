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

## Suche

Plan: `plans/2026-11-19-search.md` · Spec: `specs/2026-11-19-search-design.md` · Branch `feat/search-issues-planning`, aufgesetzt auf dem Stand von #136 und Phase 5.
Umgesetzt sind die Tasks 2–11 und der automatisierbare Teil von Task 12 (zwei Korrekturen danach: `37352d8`, `7fe8097`). Task 1 (Spike am Gerät) und die manuellen Schritte 2–4 von Task 12 sind offen.

Commits (in Reihenfolge): `4e546c6` Suchkern · `05f133a` Terminquelle · `79d685a` Aufgabenquelle und Erledigte · `ec13138` Ergebnisse und `SearchModel` · `f87af68` Suchblatt · `3e33760` Einstieg (Lupe, Titelregel, `AppEnvironment`) · `f795343` Treffer-Aktionen · `4bdbf62` GitHub-Online-Suche · `1bcdac4` Notizen und Einkaufsliste · `465c016` Werkzeug `search` · `37352d8` VoiceOver-Aktionen für alle Menüeinträge · `7fe8097` feste Titelform in „Planen“. Die Tasks 3 und 4 lagen als unversionierter Stand eines früheren Laufs vor; ich habe sie geprüft (Pakettests, `app/test-all.sh`) und in zwei Commits getrennt.

**Schnittstellen für Phase 7:** `SearchButton` und `PlanHeaderText.titleCandidates(scope:anchor:range:calendar:)` heißen wie im Plan. Gedanken-Notizen (`morning`/`evening`) werden über denselben `NoteRecord`-Speicher durchsucht; die Zeile trägt „Tagesstart/Tagesabschluss · Tag“ über `NoteSearchItem.dayKey`.

### (a) Entscheidungen

Jede Entscheidung nennt die Wahl und das Risiko, falls sie falsch ist.

1. **Spike (Task 1) nicht ausgeführt, Standardannahmen des Specs gebaut:** eigener `EKEventStore` im `actor` `EventSearchReader`, `ViewThatFits` für den Titel (inzwischen durch den Rückfall ersetzt, siehe 5), `repo:`-Liste mit höchstens 30 Angaben, Blatt über Blatt. Der Rückfall `GatewayEventSearcher` ist nicht gebaut; `IssueSearchQuery.makeByOwner` ist gebaut und getestet, aber nicht verdrahtet. Risiko: Fällt ein Punkt am Gerät durch, ist die genannte Stelle nachzuziehen.
2. **Notizen und Einkaufsliste öffnen in eigenen Blättern mit eigenem `NavigationStack`** (`NoteEditorSheet`, `ShoppingListSheet` in `EntrySheets.swift`, Schaltfläche „Fertig“), angehängt an das `SearchSheet`. Damit funktioniert das Öffnen aus „Planen“ und aus „Aufgaben“ gleich und berührt `environment.tasksPath` nicht (der Stack von „Aufgaben“ zeigt außerhalb des Tabs nichts). Die zwei `tasksPath.append` in `ShoppingListView` liegen nur in den Zuständen „keine Liste“ und „Liste verschwunden“; sie sind bei Treffern (Zustand „bereit“) nicht erreichbar.
3. **`AppEnvironment.openSearch()` erzeugt das Modell, `activeSearch` ist stark statt schwach.** Das Blatt darf sein Modell nicht bei jedem Neuaufbau von `RootView` neu bekommen. `closeSearch()` schließt das Blatt und `SearchModel.close()` leert Termine, Erledigte und Online-Treffer, sodass nichts über die Lebensdauer des Blatts hinaus liegt.
4. **`SearchSources` und `SearchToolSources` sind `@MainActor`-Closures** statt nebenläufiger; der echte Abruf läuft trotzdem im `actor` `EventSearchReader`. Der Kalenderzugriff wird über `reminderStore.calendarAccessState` geprüft (testbar), `eventSearcher` ist über `AppEnvironment.init` ersetzbar.
5. **Titel in „Planen“: feste Form statt `ViewThatFits`.** Am iPhone-17-Simulator zeigte der Kopf mit `ViewThatFits` nur die kürzeste Form („19. Nov“): In einem Leisten-Eintrag bekommt `ViewThatFits` keine nutzbare Breite (das ist der Fehlerfall des Spike-Punkts 2). Deshalb gilt der Rückfall des Plans in angepasster Form: `PlanHeaderText.displayedTitle` nimmt in der Tagesansicht die mittlere Form („Thu 19. Nov“ im Simulator), in Woche und Monat die volle, bei Schriftgrößen der Bedienungshilfen immer die kürzeste. `titleCandidates` bleibt unverändert für Phase 7. Die Kandidaten folgen dem Formatter („Do. 19. Nov.“, „Nov“) statt dem Spec-Text („Do., 19. Nov.“, „Nov.“), damit sie auch auf Englisch stimmen. Risiko: Bei sehr langen Wochentagen anderer Sprachen kann die mittlere Form in der Standardschrift knapp werden; ungeprüft.
6. **„Im Plan zeigen“ für Termine ohne Markierung des Termins** (F5). Der Termin wird vor dem Öffnen über `SearchEventResolver` neu aufgelöst (Grundkennung, Beginn, Kalender des Treffers oder zusammengeführter Kalender); `PlanningModel.resolveEvent(matching:)` liest die rohe Tagesabfrage der lesbaren Kalender, nicht `markedEvents` (das `appliedMerges` verändert).
7. **Menüs gekürzt:** Aufgabe „Öffnen“, „Im Plan zeigen“/„In Aufgaben zeigen“, „Erledigt“ statt des vollen `TaskContextMenu` (der braucht Datums- und Löschdialoge). Termin: „Öffnen“, „Im Plan zeigen“, „Als Deadline markieren“ bzw. „Markierung entfernen“, Letzteres nur ohne Rückfrage (kein Serien- oder Verknüpfungsfall). Alle Einträge außer den Deadline-Einträgen sind auch VoiceOver-Aktionen (nachgezogen in `37352d8`).
8. **Lücke A4 doppelt geschlossen:** `TaskListModel.reopen(_:)` für das Menü und `didSave(_:wasCompleted:)` für den Editor. Ohne Letzteres hätte „Erledigt“ ausschalten im Editor einer erledigten Aufgabe die Planung nicht erreicht.
9. **Ausschnitt-Zeile immer, auch bei Ort und Kalender**, zusätzlich zur Unterzeile „Kalender · Ort“. Trefferhervorhebung als gelber Hintergrund plus fett über `inlinePresentationIntent` statt `semibold`, damit die Schriftgröße der Zeile bleibt.
10. **Online-Treffer ohne Hervorhebung** (GitHub kann im Text gefunden haben, nicht im Titel). `IssueSearchError.from` bildet 401 auf „abgemeldet“, 403/429 und „rate limit“ im GraphQL-Text auf „Limit“ ab; bei „abgemeldet“ lädt das Blatt `taskList.reload(only: [.github])` (vorhandener Weg `onSignedOut`). Repositories: erst die der Projects, dann die eigenen, höchstens 30.
11. **Werkzeug `search`:** Von Notizen, Terminnotizen und Aufgabennotizen geht nur `matchedIn` (Feldnamen) hinaus, nie ein Ausschnitt; `searched.to` ist bei „null“ das (exklusive) Fensterende wie in `SearchWindow.initial`, bei Angabe das übergebene Datum; ohne Kalenderzugriff steht `calendarAccess: false` in der Antwort, damit eine leere Terminliste nicht als „nichts gefunden“ gelesen wird.
12. **String-Kataloge:** Der App-Katalog bleibt im kompakten Format der Datei (ein Hilfsskript im Scratchpad stellt es nach `xcstringstool sync` wieder her), Pakete im Xcode-Stil unverändert; englische Texte stehen zusätzlich angehängt in `scripts/translations/en.json`. Zusätzliche Texte, die der Spec nicht nennt: „Eingabe löschen“, „Erledigte einbeziehen“, „Keine weiteren Treffer auf GitHub.“, „GitHub wird durchsucht …“, „Öffnet das Issue auf GitHub“, „Einkaufsliste öffnen“, „Einkauf“, die Kopf-Ansagen („Termine, 3 kommende“ usw.), „Titel/Nummer/Art/Menge“ als Feldnamen, die drei Werkzeug-Fehlertexte.

### (b) Abweichungen vom Plan

- Task 5: `searchOnline` und `checkOffShopping` kamen erst in den Tasks 9 und 10 ins `SearchModel`; `SearchModel.settle()` (nur Debug) gibt Tests etwas zum Abwarten. Neuabruf wiederholt jedes geholte Intervall einzeln, weil EventKit je Anfrage höchstens vier Jahre beantwortet; erweiterte Jahre werden ohne doppelte IDs angehängt.
- Task 7: `activeSearch` stark, `openSearch()` neu (siehe a.3); `PageTitleLabel` bekam `titleScales`, die Zeile darüber `lineLimit(1)` und Verkleinerung bis 80 %.
- Task 8: `TaskEditorSheet` war schon durch die Vorschlagsblätter belegt; die neue Hülle heißt `AppTaskEditorSheet` und behält für „Planen“ das bisherige Verhalten (keine Container, keine Kommentare); die Suche schaltet beides wie die Aufgabenliste ein. `TaskListView` baut weiter ihren eigenen Editor.
- Task 9: Der Plan-Test legte unnötig eine Viewer-Antwort an; die Tests folgen dem tatsächlichen Ablauf (gespeicherter Katalog statt Abruf). `NoteSearchItem` bekam `dayKey`, `noteSubtitle` hat keinen `kindRaw`-Parameter.
- Task 10: Die Suche setzt `checkOffShopping` nur, wenn eine Einkaufsliste gewählt ist.
- Task 12: Die Demo-Daten wurden nicht erweitert; die vorhandenen Demo-Termine und -Aufgaben liefern schon Treffer (am iPhone-17-Simulator gesehen). Die Spec-Nachträge stehen am Ende des Specs.
- Roter Lauf: Bei den App-Tasks bestand er aus dem Übersetzungsfehler fehlender Typen (Paket-Tests Task 5 wurden separat rot gesehen), nicht aus einem eigenen Lauf vor der Umsetzung; Task 8 und 9 wurden zusätzlich während der Umsetzung rot (Namenskonflikt, Katalogabruf im Test) und korrigiert.
- `app/test-all.sh` lief vor jedem Commit, der die App berührt (Tasks 3 bis 11).
- Abschlussreview: Selbstreview des Autors, kein unabhängiger Reviewer (keine Subagenten erlaubt). Gegen die fünf Review-Focus-Punkte des Plans geprüft, jeweils mit gelaufenem Test: (1) `finishEvening_afterMidnight_writesTheDayTheSheetWasOpenedFor`, (2) `failedHealthRead_keepsLastFactsOfTheSameDay` und `backgroundSnapshot_withoutHealthFacts_neverLowersTheCounter`, (3) `vanishedTask_isDoneOnlyAfterItsSourceSettled`, (4) `close_flushesThePendingSave`, `whitespaceOnly_deletesTheNote`, `dictation_insertsAtTheCursor`, (5) `lateAnswerAfterReset_isDiscarded`. Der Selbstreview fand zwei Fehler, beide behoben: Habit-Zeilen konnten nach Aktivwerden oder Siri einen anderen Tag zeigen als „Erfassen“ (`checkHabit_keepsTheDayShownInCapture`, rot→grün), und die Blätter der Gewohnheiten hingen an der Section statt an einer Ansicht.

### (c) Offene manuelle Prüfungen am Gerät

- **Task 1 (Spike):** (1) Dauer des Terminabrufs über 18 Monate mit eigenem `EKEventStore`, Sichtbarkeit von Änderungen des ersten Stores; (2) Titelbreite in „Planen“ mit drei Einträgen rechts auf dem iPhone 16 Pro und mit größter Schrift (am iPhone-17-Simulator zeigte `ViewThatFits` nur die kürzeste Form, daher die feste Form; die mittlere Form passt dort in der Standardschrift); (3) GitHub-Suche mit 30 `repo:`-Angaben und privaten Repositories; (4) Blatt über Blatt inklusive „Im Plan zeigen“ aus dem inneren Blatt.
- **Task 12, Schritte 2–4:** Englisch im Simulator (alle sieben Köpfe, Fußzeilen, Fehlertexte), VoiceOver (Lupe, Köpfe mit Zähler, Marken „ausgewählt“, Schalter, Zeilen, Aktionen), größte Schriftstufe (Marken-Zeile rollt, Titel in „Planen“).
- **Geräte-Checkliste** (Ergebnis in den Spec-Nachtrag schreiben): Aufgaben sofort, Termine unter 1 s · Termin in Kalender-App ändern bei offenem Blatt · „Ältere Termine durchsuchen“ zweimal · Dauer von „✓ Erledigte“ über 12 Monate und erledigte Vorkommen wiederkehrender Erinnerungen · abonnierter und zusammengeführter Termin öffnen, Deadline-Marke wie in „Planen“ · Abhaken mit Kapsel, „Wieder öffnen“, „Im Plan zeigen“ · „Auf GitHub suchen“ mit und ohne Netz, im Flugmodus kein Abruf beim Tippen · Assistent „Wann ist die Statistik-Klausur?“ nutzt `search`, Antwort ohne Notiztext · Blatt schließt bei Assistent, Mitteilung und `tagwerk://plan/today`.
- Am Simulator gesehen (iPhone 17, nur Ansehen): Lupe öffnet das Blatt mit Fokus, „Planen“-Kopf mit Lupe, Plus und Assistent, Termin- und Aufgabentreffer mit Hervorhebung, „Ältere Termine durchsuchen“, Fußzeile, Termin-Blatt über der Suche und Rückkehr. Nicht gesehen: Notizen, Einkaufsliste, GitHub, Erledigte, Menüs, „Im Plan zeigen“, dunkle Darstellung, Englisch.

### (d) Bekannte Lücken / nicht umgesetzt

- Für Blatt, Zeilen und Menüs gibt es keine UI-Tests; getestet ist die Logik (Kern, Modell, Texte, Auflösung, Quellen, Werkzeug).
- `NotesListView` in „Aufgaben“ schiebt Notizen weiter über `environment.tasksPath`; nur die Suche nutzt die eigenen Blätter.
- `ShoppingListView` zeigt in der Leiste des Einkaufsblatts den Assistenten-Knopf; ein Tipp schließt die Suche und öffnet den Assistenten.
- Die Deadline-Einträge im Termin-Menü fehlen für Serien-Marken und Marken mit Vorbereitungs-Verknüpfungen (dort bleibt der Weg über „Öffnen“); VoiceOver-Aktionen gibt es dafür nicht.
- Der erste Terminabruf startet auch bei Filter „Aufgaben“ (einmal je Blatt); wer nur Aufgaben sucht, bezahlt ihn mit.
- Ältere Erledigte als 12 Monate fehlen bei Erinnerungen (F6); „Erledigt“-Zeilen von GitHub gibt es nur über die Online-Suche.
- `searched.to` im Werkzeug ist bei Standardfenster das exklusive Ende (ein Tag nach dem letzten gesuchten).
- Die Menü-Einträge „Erledigt“ und „Wieder öffnen“ schreiben ohne Rückfrage; bei Konflikt erscheint der Hinweis „Die Aufgabe wurde inzwischen geändert …“.

### (e) Testergebnis

`app/test-all.sh`, letzter Lauf nach dem letzten Code-Commit (`7fe8097`), alle Stufen grün einschließlich „string catalogs“ (`check-strings.py --require-english` und `sync-strings.sh --check`):

- AIKit 98, GitHubKit 137 (vorher 129), HealthBridge 11, RemindersKit 87 (vorher 84), TagwerkCore 571 (vorher 529), App 965 (vorher 893) Tests bestanden.
- Letzte Zeile: `ALL TESTS PASSED`

## Phase 7 Routinen

Plan: `plans/2026-11-19-phase-7-routines.md` · Spec: `specs/2026-11-19-phase-7-routines-design.md` (§9.2: KI-Kontext sind die offenen Aufgaben und Termine der nächsten 7 Tage) · Branch `feat/search-issues-planning`, aufgesetzt auf dem Stand von #136, Phase 5 und Suche.
Umgesetzt sind die Tasks 4–16 (Gewohnheiten, Tagesabschluss, Tagesstart, Fokus, Gedanken-Notiz mit Vorschlägen, Wochenreflexion, Leitfragen). Die Spikes (Tasks 1–3), die optionale Tageslicht-Quelle (Task 17) und die Geräte-Schritte von Task 18 sind offen.

Commits (in Reihenfolge): `907b40d` Datentypen und `HabitRules` · `5c29fcf` `HabitsModel`, Zähler in „Planen“ · `3e5f5e9` Abschnitt, Liste und Blatt „Gewohnheit“ · `e55e719` Kurzbefehl, Snapshot, Widget · `dbbf9da` Tageseintrag, Checkliste, Einstellungen › Routinen · `5c89f0d` Blatt „Tagesabschluss“, Routen, Abendzeile · `3eb3129` wiederholende Mitteilungen · `9ecff95` Blatt „Tagesstart“, Morgen-Erinnerung · `0f504ed` Fokus, Routine-Karte, Stern · `5078322` Gedanken-Notiz · `ada7f38` Vorschläge aus der Notiz · `e6afae0` Wochenreflexion · `0642ff0` Leitfragen · `26f82ad` Korrektur nach der Sichtprüfung (Karte umbrechen, „0/0“ vermeiden) · `16501c4` Korrektur aus dem Selbstreview (Tag der Gewohnheiten, Blätter, Kalender des KI-Kontexts).

**Schnittstellen für spätere Arbeit:** `AppRoute.routineStart`/`.routineEvening`, `SnapshotDay.habits`, `NoteRecord.derivedActionCount`, `ActionCardDescriber` (von `AssistantModel.describe` und `NoteSuggestionModel` genutzt), `PlanningModel.focusTaskIDs` und `taskIDsWithBlocks(on:)`, `NoteStore.saveThought`/`addDerivedAction`.

### (a) Entscheidungen

Jede Entscheidung nennt die Wahl und das Risiko, falls sie falsch ist.

1. **Spikes, Tageslicht und Geräteschritte nicht ausgeführt.** Die Quelle „Zeit bei Tageslicht“ (Task 17) ist nicht gebaut: Sie ändert Health-Lesetypen und `InfoPlist`; die Freigabe lässt sich ohne Gerät nicht prüfen. `HabitSource.daylight` liegt im Datentyp und in den Regeln, erscheint aber nie in der Auswahl. Risiko: keines für den Bestand; die Quelle fehlt bis zum Spike.
2. **Fußtext der Notizenliste (Hinweis des Auftrags):** Der Fußtext der Notizenliste lautet jetzt „Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Gedanken-Notiz nur, wenn du bei ihr auf ‚Vorschläge holen‘ tippst.“ Der alte Katalogschlüssel („… nicht an ChatGPT gesendet“) ist gelöscht. Eine Suche in App und Katalogen ergab keinen weiteren Text, der behauptet, Notizen gingen nie an ChatGPT.
3. **Tagesrückblick „Aufgaben erledigt e von n“:** e zählt Erledigungen aus Erinnerungen und lokalen Aufgaben (die Leser des Wochenrückblicks), n = e + offene Aufgaben des Tages; GitHub-Issues zählen nur als offen. Fußtext im Blatt: „Erledigt: Erinnerungen und lokale Aufgaben, ohne GitHub.“ Risiko: Die Zahl ist für GitHub-Nutzer zu niedrig.
4. **Zähler im Snapshot bleibt hoch, wenn Health nicht lesbar ist (Review Focus 2).** Ohne aktuelle Health-Werte (Kaltstart, Hintergrund, fehlgeschlagene Abfrage) behält der Snapshot den zuletzt geschriebenen Zähler desselben Tages, wenn er höher ist und `total` gleich bleibt (`snapshotHabits(existing:now:)`). Risiko: Ein bewusst zurückgenommenes Handhäkchen senkt den Wert im Widget erst nach dem nächsten Health-Lauf; ein Siri-Häkchen bei Health-Gewohnheiten ohne Health-Lesung kann im Widget bis zum nächsten App-Start fehlen.
5. **Wöchentliches Ziel zählt künftige Tage der laufenden Woche mit** (`isCountable` ohne „nicht in der Zukunft“). Sonst wäre das Ziel am Montag `round(3·1/7) = 1` und nach einem Häkchen erreicht. Risiko: bei Pausen mitten in der Woche rundet das Ziel anteilig wie im Spec.
6. **Serie in Wochen:** Die Obergrenze ist 12 Wochen („12+“), unabhängig davon, ob die laufende Woche mitgezählt wird (Plan-Test: 13 erreichte Wochen ergeben `.weeks(12, isCapped: true)`).
7. **Automatische Zeilen** zeigen die Marke „automatisch“ und die Quelle dauerhaft; ein Tipp ändert nichts (Spec: „Tippen zeigt die Quelle“). Risiko: weniger interaktiv als im Spec; die Information ist dieselbe.
8. **Health wird nur beim Erscheinen von „Erfassen“, beim Ziehen und beim Aktivwerden gelesen**, nicht bei jedem Tageswechsel in „Erfassen“ (`HabitsModel.show` liest nur den Speicher). Risiko: Health-Werte eines vergangenen Tages stehen erst nach dem nächsten Lauf da; innerhalb des 90-Tage-Fensters sind sie bereits geladen.
9. **Englische Texte „Tagesstart“/„Tagesabschluss“** lauten jetzt „Morning start“/„Evening wrap-up“ (Spec §12) statt „Morning“/„Evening“ aus Phase 5; `LocalizedTests` ist angepasst. Risiko: Die Herkunftszeile der Notizliste wird auf Englisch länger.
10. **Vorschläge aus der Notiz:** `create_task` mit `source: "github"` wird verworfen (kein `list_github_targets`, Zuweisungen sind nicht prüfbar; die Karten der Zuweisung aus #136 gelten damit nicht für Notiz-Karten). Der Kontext schneidet bei mehr als 60 Aufgaben die ältesten und bei mehr als 100 Terminen die spätesten ab (Spec §9.2). `update_event` ist auf Termine beschränkt, die Tagwerk geschrieben hat (`canEditAsBlock`, Abweichung A7). Risiko: keine Issue-Vorschläge aus Notizen.
11. **Der Pfeil in der Aufnahmeleiste der Notiz ist abgeschaltet** (`canSend: false`): `DictationMachine.send` würde den Entwurf leeren; das Diktat füllt nur das Feld. Das Diktat steht an der Schreibmarke, der Text dahinter wird nach dem Diktat wieder angesetzt.
12. **Schließen des Blatts** (`routines.sheet == nil`) beendet eine Aufnahme, verwirft offene Karten und späte Antworten; `onDisappear` der Zeile speichert nur den Text, weil Formularzeilen beim Scrollen verschwinden.
13. **Spec/Plan-Lücke bei der Notiz „ausgeführte Vorschläge“:** `derivedActionCount` zählt nur Karten ohne Fehler und „Als Aufgabe anlegen“, wenn `NewTaskSheet.create` keinen neuen Fehlertext setzt (die Funktion liefert kein Ergebnis).
14. **String-Kataloge:** Das App-Format bleibt kompakt; Abgleich über ein Hilfsskript im Scratchpad (nicht im Repository). Englische Texte stehen zusätzlich in `scripts/translations/en.json`. Plural-Formen sind vermieden: „1 Termin“/„1 Aufgabe“/„Serie 1 Woche“ haben eigene Schlüssel. Prozentwerte erscheinen in beiden Sprachen als „73 %“.
15. **Zusätzliche Texte, die das Spec nicht nennt:** Hinweis „Mitteilungen sind für Tagwerk nicht erlaubt …“ samt Knöpfen, „Heute ausblenden“, „An diesem Tag ist keine Gewohnheit aktiv.“, „In dieser Woche war keine Gewohnheit aktiv.“, „Heute ist noch keine Aufgabe geplant.“, „Vorschläge werden geholt …“, Fehlertexte der Vorschläge, VoiceOver-Texte der Zeilen.

### (b) Abweichungen vom Plan

- **Task 4/15:** `HabitRules.weekSummaries` und `HabitWeekSummary` (Task 15) entstanden schon in Task 4, mit den Core-Tests dort. Der Schema-Test für `HabitRecord` liegt in `HabitStoreTests`, nicht in `ModelStoreLocationTests`.
- **Task 5:** `FakeHealthStore` zählt Abfragen schon (`foreignReads`, `stepsReads`, `failStepReads`); keine neuen Zähler.
- **Task 7:** Die Phrase nutzt `HabitEntity` mit eigener Abfrage; `HabitsModel.onListChanged` aktualisiert die Siri-Parameter (nicht `onChanged`).
- **Task 8:** `RoutineSchedule.suggestedItems` ist eine berechnete Eigenschaft (Titel in der Sprache beim Übernehmen); `RoutineStore` ist `@Observable`.
- **Task 9:** `RoutinesModel.tasks(of:)` verallgemeinert Regel 12 auf beliebige Tage; neu ist `PlanningModel.taskIDsWithBlocks(on:)`.
- **Task 10:** `NotificationDelegate.handle(_:)` als testbarer Einstieg; `RoutineNotificationScheduler` ist `@Observable` und reiht Läufe ein. Die Mitteilungsplanung der Routinen läuft zusätzlich über `Observations` (Schlafzeit, Schalter, Checkliste).
- **Task 12:** Der Stern liest `PlanningModel.focusTaskIDs` (von `RoutinesModel` gesetzt), statt `RoutinesModel` durch die Zeitleiste zu reichen. `RoutinesModel.init` hat eine optionale Closure `isRecurring` (Testnaht).
- **Task 13:** `NoteStore.save()` ist nicht mehr privat. `NoteField` ist eine einzige Formularzeile.
- **Task 14:** `ActionCardDescriber` ist wirklich herausgelöst (inklusive `spoken:`), `AssistantModel.describe` leitet weiter; die vorhandenen `describe`-Tests blieben unverändert grün. Die Funktionsliste wird aus `AppTools.definitions` gefiltert.
- **TDD:** Für Task 4 (App-Teil), Task 6 (`HabitText`), Task 14 und Teile von Task 13/16 liefen Test und Code in einem Schritt; ein eigener roter Lauf wurde nicht in jedem Task gesehen. Rot gesehen wurde bei Core-Tests (Tasks 4, 7, 8, 9, 10, 11, 16) und bei den App-Tests der Tasks 5, 7, 8, 9, 10, 11, 12, 13, 15.
- `app/test-all.sh` lief vor jedem Commit (nach Task 4 nachgeholt). Er dauert etwa eine Minute.
- Sichtprüfung im Simulator (iPhone 17, Demo-Daten) am Ende für Planen (Zähler, Tagesstart-Karte), Erfassen (Routinen, Gewohnheiten), Blatt „Gewohnheit“ (anlegen, abhaken) und Blatt „Tagesstart“; daraus entstand `26f82ad`.
- Abschlussreview: Selbstreview des Autors, kein unabhängiger Reviewer (keine Subagenten erlaubt).

### (c) Offene manuelle Prüfungen am Gerät

- **Task 1:** Tageslicht-Spike (Watch, Freigabe, Werte ohne Watch). **Task 2:** antippbares Widget. **Task 3:** Aktionen in Mitteilungen. **Task 17** (Quelle „Zeit bei Tageslicht“) hängt an Task 1.
- **Task 10 Schritt 5:** Mitteilung kommt ohne App-Start; überlebt Neustart und Drüberinstallieren; Verhalten im Fokus „Schlafen“; Tippen öffnet das Blatt bei beendeter App.
- **Task 13 Schritt 4:** Spracheingabe im Notizfeld außerhalb des Assistenten (Diktat an der Schreibmarke).
- **Task 18 Schritte 2–3:** Zeitumstellung und Zeitzonenwechsel bei wiederholenden Auslösern; Siri erkennt die deutsche Phrase mit Gewohnheitsnamen; Abhaken bei gesperrtem Gerät; fünf Routine-Mitteilungen bei vollen 50 Deadline-Plätzen; Höhe der Routine-Karte auf dem kleinsten Gerät; Drüberinstallieren über einen Stand vor Phase 7 (Store öffnet, Widget liest alte Snapshot-Datei).
- Widget „Heute“ mit und ohne Ernährung (Zähler, Platz in der rechten Spalte); Sperrbildschirm-Widgets zeigen den Zähler nie.
- Sichtprüfung: Blatt „Tagesabschluss“ (abends), Fokus-Karte und Sterne in Liste und Stundenraster, Wochenrückblick-Abschnitte, Einstellungen › Routinen, Zustimmungsblatt und Vorschlagskarten (braucht ChatGPT-Anmeldung), jeweils hell, dunkel, größte Schrift, Englisch, VoiceOver.
- Echter Lauf von „Vorschläge holen“ gegen ChatGPT (Qualität der Karten, Latenz, `update_event` auf einem Zeitblock).

### (d) Bekannte Lücken / nicht umgesetzt

- Für Ansichten (Karte, Blätter, Abschnitte) gibt es keine UI-Tests; getestet ist die Logik dahinter.
- Das Widget wurde nicht im Simulator angesehen; die Planen-Zeile, Erfassen und das Blatt „Tagesstart“ schon.
- Die Quelle `daylight` ist nur Datentyp und Regel; ohne Spike gibt es keine Auswahl und keine Freigabe.
- Bei Health-Gewohnheiten ohne aktuelle Health-Lesung kann der Zähler im Snapshot kurz zu hoch oder zu niedrig stehen (Entscheidung 4).
- Die Tagesstart-Karte zeigt die Zahlen erst nach dem Laden der Aufgaben; die Karte kann „0 Aufgaben“ nennen, das Blatt danach „1 Aufgabe“.
- Vorschläge aus der Notiz erzeugen keine GitHub-Issues (Entscheidung 10); Karten kennen keine Rückfrage zur Zuweisung.
- Die Gedanken-Notiz im Assistenten, Aktionen in Mitteilungen, antippbares Widget und feste Wochentage bleiben Nicht-Ziele des Specs.
- Der KI-Kontext der Vorschläge liest Termine aus den in „Planen“ lesbaren Kalendern (`planning.readableCalendarIDs()`), wie die Suche; abgewählte Kalender gehen nicht an ChatGPT. Der Assistent (`list_events`) liest weiterhin alle Kalender (unverändert).
- Abschlussreview: Selbstreview des Autors.

### (e) Testergebnis

`app/test-all.sh`, letzter Lauf nach dem letzten Code-Commit (`16501c4`), alle Stufen grün einschließlich „string catalogs“ (`check-strings.py --require-english` und `sync-strings.sh --check`):

- AIKit 98, GitHubKit 137, HealthBridge 11, RemindersKit 87, TagwerkCore 621 (vorher 571), App 1108 (vorher 965) Tests bestanden.
- Letzte Zeile: `ALL TESTS PASSED`

## Siri Einkaufsliste

Auftrag: Siri soll offenere Formulierungen verstehen, auch einen Satz, der den Artikel nennt („Füge Milch zur Einkaufsliste in Tagwerk hinzu“). Branch `feat/search-issues-planning`. Commits: `f5ea6e7` Namensliste für Siri (`TagwerkCore`) · `8b5c4a9` Sätze, Entity, Intent, Katalog, Einstellungstext · `e41424d` Korrekturen aus der Durchsicht (Auffrischen bei Hintergrundstart, genauer Treffer).

### (a) Was gebaut ist

- **Grenzen der Schnittstelle (im SDK 27.2 geprüft):** Sätze eines App-Kurzbefehls dürfen nur `AppEntity`/`AppEnum`-Parameter enthalten, nie einen freien `String`, und jeder Satz braucht `\(.applicationName)`. Ein Artikel im Satz geht deshalb nur über eine Entity; `EntityStringQuery` und `updateAppShortcutParameters()` sind vorhanden.
- **Fünf neue Sätze ohne Parameter** (am bestehenden `AddToShoppingListIntent`, Rückfrage „Was soll auf die Liste?“, die alten drei bleiben): „Füge etwas zur Einkaufsliste in Tagwerk hinzu“ · „Ich brauche etwas aus dem Laden in Tagwerk“ · „Einkaufsliste in Tagwerk“ · „Neuer Artikel in Tagwerk“ · „Etwas auf die Einkaufsliste in Tagwerk setzen“.
- **Drei neue Sätze mit Artikel** (neuer `AddShoppingArticleIntent`, Hintergrund-Modus, Parameter `ShoppingArticleEntity`): „Füge \(Artikel) zur Einkaufsliste in Tagwerk hinzu“ · „\(Artikel) auf die Einkaufsliste in Tagwerk“ · „Setz \(Artikel) auf die Einkaufsliste in Tagwerk“. Der Intent ruft `IntentServices.addToShopping(article:)`, das den bestehenden Weg nutzt (`addToShopping(text:)` → Zerlegen, Duplikate, Wiedereröffnen, Kategorie). Es gibt jetzt 8 App-Kurzbefehle (Grenze des Systems: 10).
- **Vorschlagsliste** (`ShoppingSuggestions.articles`): zuerst die eigenen Namen aus der Einkaufsliste (offen und erledigt, bis 180 Tage zurück), sortiert nach Häufigkeit, dann Aktualität, dann Name; danach häufige Begriffe in der App-Sprache (die andere Sprache folgt); Duplikate ohne Rücksicht auf Groß-/Kleinschreibung und Umlaute; Obergrenze 150; von mehreren Schreibweisen gilt die neueste.
- **Auffrischen:** `ShoppingModel.onNamesChanged` meldet, wenn sich die Menge der Namen nach einem Neuladen ändert (auch beim ersten Laden). Der Haken wird in `TagwerkApp.init` gesetzt (nicht erst in `RootView.task`, das bei einem Hintergrundstart durch einen Intent nicht läuft, E10) und ruft `TagwerkShortcuts.updateAppShortcutParameters()` auf; in Unit-Tests ist er nicht gesetzt. Zusätzlich ruft `startSnapshotUpdates` die Aktualisierung einmal beim Vordergrundstart auf. Die Verdrahtung in `TagwerkApp.init` ist nicht automatisch getestet, nur der Haken im Modell.
- **Englisch:** alle acht Sätze im Katalog `AppShortcuts.xcstrings` (mit `${applicationName}`, bzw. `${article}`), Titel und Beschreibung des neuen Intents, zwei Zeilen in der Einstellungsseite „Erfassen“ (Beispielsatz mit Milch); `scripts/translations/en.json` nachgezogen.
- **Einstellungen › Erfassen:** neue Zeile „Füge Milch zur Einkaufsliste in Tagwerk hinzu“ (nicht verlangt; sonst wäre der Satz nirgends auffindbar).

### (b) Entscheidungen

1. **Häufige Begriffe als gepflegte Liste statt aus dem Wörterbuch abgeleitet.** Das Wörterbuch hat nur gefaltete Schlüssel („kase“, „apfel“) und keine Häufigkeit; Siri bekäme „Kase“. Gewählt: eine Liste in `ShoppingSuggestions` (≈ 80 deutsche, ≈ 45 englische Begriffe, richtig geschrieben, nach Häufigkeit sortiert). Ein Test stellt sicher, dass jeder Begriff ein Begriff des Offline-Wörterbuchs ist. Risiko: die Rangfolge ist geschätzt, nicht gemessen.
2. **Unbekannte Namen lösen sich zu sich selbst auf**, statt leer zu bleiben. Die Vorgabe „unbekannte Namen fallen auf die Frage zurück“ hätte sonst bei der Antwort auf „Was soll auf die Liste?“ eine Schleife erzeugt (leeres Ergebnis → Siri fragt erneut). Leerer oder nicht zerlegbarer Text löst sich zu nichts auf. Entspricht der Text genau einem Vorschlag („Milch“), ist das der einzige Treffer, damit Siri nicht zwischen „Milch“, „Milchreis“ und „Hafermilch“ rückfragt; bei Teiltext („hafer“) kommen alle Treffer, Anfang vor Mitte. Ein frei getippter Text wird beim Hinzufügen wie gesprochener Text zerlegt („2 Zwiebeln“ → Zwiebeln mit Menge 2; „Milch und Brot“ → zwei Artikel). Ein Name mit Komma in der Historie würde dabei ebenfalls zerlegt (selten, nicht behandelt).
3. **Entity-ID ist der Name selbst**; `entities(for:)` baut die Entity daraus wieder auf, ohne die Liste zu lesen. Gespeicherte Kurzbefehle brauchen so keinen Treffer in der aktuellen Vorschlagsliste.
4. **Reihenfolge der eigenen Namen:** erst Häufigkeit, dann Aktualität. Da Tagwerk wiederholte Artikel wieder öffnet statt neu anzulegen, zählt die Häufigkeit in der Praxis meist 1 und die Aktualität entscheidet. Die Historie umfasst 180 Tage (`ShoppingModel.historyWindow`); die Seite „Erledigt“ bleibt bei 7 Tagen. Die Dauer von `predicateForCompletedReminders` über 180 Tage ist nicht gemessen (wie S5); sie fällt nur an, wenn das System die Vorschläge abfragt.
5. **Auffrischen nur bei Änderung der Namensmenge** (Schlüsselmenge der offenen und der 7 Tage erledigten Artikel), nicht bei jedem Neuladen, damit `updateAppShortcutParameters()` nicht ständig läuft. Namen, die nur in der längeren Historie stehen, ändern die Menge nicht und werden beim nächsten Auffrischen oder Start berücksichtigt.
6. **Kein eigenes Verhalten ohne Liste oder Zugriff:** dann bleiben nur die häufigen Begriffe; beim Hinzufügen antwortet der Intent wie bisher („Wähle zuerst …“).
7. **`AddShoppingArticleIntent.services` ist nicht `private`**, damit der Test die Abhängigkeit setzen kann (`AppDependencyManager.add` greift außerhalb des Systemablaufs nicht).
8. **Satz „Einkaufsliste in Tagwerk“ ohne Verb** steht so im Auftrag und liegt neben „Einkaufsliste in Tagwerk zeigen“. Wer nur „Einkaufsliste in Tagwerk“ sagt und die Seite sehen will, bekommt die Rückfrage.
9. **Rot-Lauf:** Die Tests für `ShoppingSuggestions` und die App-Seite wurden vor dem Code geschrieben, aber nicht einzeln rot gelaufen (kein Lauf zwischen Test und Implementierung). Der erste grüne Lauf der App-Tests fand einen Fehler im Test (Wörterbuchbegriff „Hafermilch“) und eine Abhängigkeits-Falle (Punkt 7).

### (c) Offene Prüfungen am Gerät (Siri-Erkennung ist im Simulator nicht prüfbar)

- Sätze ohne Parameter: jeder der fünf neuen Sätze und die drei alten lösen die Rückfrage „Was soll auf die Liste?“ aus; Antwort „Kaffee und Reis“ legt zwei Artikel an.
- Sätze mit Artikel: „Füge Milch zur Einkaufsliste in Tagwerk hinzu“, „Eier auf die Einkaufsliste in Tagwerk“, „Setz Käse auf die Einkaufsliste in Tagwerk“ — mit einem Namen aus der eigenen Liste, mit einem häufigen Begriff, mit einem unbekannten Namen (was sagt Siri?).
- Ein neu angelegter Artikel wird nach kurzer Zeit sprechbar (nach `updateAppShortcutParameters()`); die Wartezeit ist unbekannt. Auch prüfen, wenn der Artikel per Siri bei beendeter App angelegt wurde (Haken in `TagwerkApp.init`).
- Antwort „Milch“ auf die Rückfrage: Siri fragt nicht zwischen „Milch“ und „Milchreis“ nach.
- Mehrdeutigkeit zwischen „Einkaufsliste in Tagwerk“ und „Einkaufsliste in Tagwerk zeigen“.
- Menge der Sätze: 3 Sätze × bis 150 Namen plus Gewohnheiten bleiben unter der Grenze des Systems (angenommen 1000, nicht geprüft); sonst Obergrenze senken.
- Englisch: die englischen Sätze, Anzeige der Entity („Item“) in der App „Kurzbefehle“, Verhalten der Vorschlagsliste mit englischer App-Sprache (englische Begriffe zuerst).
- Hintergrund-Ausführung bei gesperrtem Gerät (wie S4 der Phase 5).

### (d) Testergebnis

`app/test-all.sh`, Lauf nach dem Code-Commit `e41424d`, alle Stufen grün einschließlich „string catalogs“: AIKit 98, GitHubKit 137, HealthBridge 11, RemindersKit 87, TagwerkCore 636 (vorher 621), App 1119 (vorher 1108) Tests bestanden. Neue Tests: 15 in `ShoppingSuggestionsTests` (Quellen, Reihenfolge, Duplikate, Grenze 150, Wörterbuchbezug, Treffersuche) und 11 in `ShoppingSiriTests` (Namensliste, Auflösung, Hinzufügen über den bestehenden Weg mit Fake-Speicher, Intent-`perform`, Auffrischen-Hook).

Letzte Zeile: `ALL TESTS PASSED`

## Korrekturen aus der Prüfung

Alle neun Befunde wurden im Code bestätigt; keiner war falsch. Die doppelten Hilfsfunktionen `withTimeout`/`collect` wurden bewusst nicht angefasst (Backlog-Punkt). Ein Commit je Befund.

| # | Befund | Status | Korrektur | Test |
|---|--------|--------|-----------|------|
| 1 | `refreshFocus` hakte Fokus-Aufgaben ab, wenn die Quelle fehlgeschlagen war, den Zugriff verloren hatte oder abgemeldet war | bestätigt (`6336abb`) | `isSettled` akzeptiert nur `.loaded` und `.offline`, wie `allSourcesSettled` | `vanishedTask_staysOpenWhenItsSourceFailedOrLostAccess` (vor der Korrektur rot: 3 Fehlschläge) |
| 2 | Die Online-Suche setzte bis zu 30 `repo:`-Qualifier in eine Anfrage; GitHub begrenzt die Länge (256 Zeichen), `makeByOwner` blieb ungenutzt | bestätigt (`8f6058b`) | `IssueSearchQuery.make` fällt auf `makeByOwner` zurück, sobald die Anfrage 256 Zeichen übersteigt; `makeByOwner` lässt Eigentümer weg, die nicht mehr passen (`user:<login>` bleibt immer). Die Grenze von 256 Zeichen für GraphQL ist angenommen, nicht geprüft; eine abgelehnte Anfrage wird nicht erneut mit Eigentümern versucht | `manyRepositoriesFallBackToOwnerQualifiersWithinTheLimit`, `manyRepositoriesOfOneOwnerCollapseToOneQualifier`, `queryListsRepositoriesWhileItFitsTheLengthLimit` (ersetzt den Test zur 30er-Grenze; mit der Längengrenze ist diese praktisch nicht mehr erreichbar) |
| 3 | Ohne bekannte Anmeldung war die Vorauswahl leer, der Entwurf ging mit `assignees: []` (niemand) statt `nil` (ich) hinaus | bestätigt (`0c1f079`) | Solange der Nutzer nichts gewählt hat, sendet das Blatt `nil` (`AssigneeSelection.draftAssignees`); die Zeile zeigt dann „Ich“, die Fußzeile „wird dir zugewiesen“. Eine ausdrückliche Wahl, auch „Niemand“, geht unverändert hinaus. Offen: Ist die Anmeldung beim ersten Antippen unbekannt, fehlt „Ich“ im Menü und wird nicht mit der neuen Wahl kombiniert | `draftAssignees_untouchedDefaultStaysNil_soTheProviderAssignsTheViewer`, `draftAssignees_explicitChoiceIsSentAsIs_includingNobody` (Teil der Logik liegt in der View und ist nicht getestet) |
| 4 | `.routineStart`/`.routineEvening` schlossen andere Sheets und zeigten das Routine-Sheet im selben Update; SwiftUI verwirft es | bestätigt (`6715040`) | War vorher ein Sheet offen, wird das Routine-Sheet 350 ms später gezeigt (wie bei `showTask`), sonst sofort | kein Test: reine View-Logik; der Build ist grün, Verhalten am Gerät zu prüfen |
| 5 | Der Erfolg von `create` wurde über den Vergleich von `lastError` geraten (falsch in beide Richtungen) | bestätigt (`7db153e`) | `TaskListModel.create` liefert die angelegte Aufgabe oder `nil`; `onCreated` hängt nur daran | `create_returnsTheCreatedItem_evenWhenAnAssigneeWasDropped`, `create_returnsNilOnFailure_evenWithTheSameMessageAsBefore`, `create_returnsNilWithoutARegisteredSource` |
| 6 | Erledigte Aufgaben wurden nur einmal geladen; nach Aus-, Erledigen- und Wieder-Einschalten blieb die Liste veraltet | bestätigt (`255d2d5`) | Jedes Einschalten von „Erledigt“ lädt neu (außer ein Laden läuft bereits) | `completedTaskCompletedWhileSwitchWasOff_showsAfterTurningItOnAgain` (vorher rot); `completedLoadOnceWhenSwitchTurnsOn` wurde zu `completedReloadedEachTimeSwitchTurnsOn` mit zwei Ladevorgängen (vorher rot) |
| 7 | `searched.to` nannte ohne `to` den exklusiven Fensterende-Tag | bestätigt (`c30f770`) | Gemeldet wird der letzte durchsuchte Tag (Ende minus ein Tag) | `search_findsEventsAndTasksInDefaultWindow` erwartet jetzt `2027-11-17` statt `2027-11-18` (vorher rot) |
| 8 | Wiederholte Komplett-Neuladungen je Aufruf (Start und Ende von `ShoppingModel.add`, je `checkOff`) | bestätigt (`8c0acc5`) | `add(_:reloadFirst:)` ohne führendes Neuladen für Aufrufer, die gerade geladen haben (`update_shopping`, Siri-Weg); neues `checkOff(ids:)` speichert alle und lädt einmal; `update_shopping` nutzt es. `update_shopping` liest die Liste nun dreimal statt 2 + n + 1 Mal | `add_afterAFreshLoad_skipsTheLeadingReload`, `checkOffSeveral_savesAllAndReloadsOnce`, `updateShopping_reloadsTheListOnlyThreeTimes` (Zähler `openReminderCalls` im Fake-Speicher) |
| 9 | `listShopping` rief je Artikel `categoryName(of:)` auf (je Aufruf alle Zuordnungen und Kategorien) | bestätigt (`2f139df`) | `ShoppingModel.categoryNamesByItemID()` bildet die Namen aus den bereits sortierten Abschnitten und einem einzigen Abruf der Kategorien | `categoryNamesByItemID_nameTheSectionOfEachOpenItem_andSkipOther`; die bestehenden `listShopping`-Tests decken das Ergebnis ab |

Rot-Lauf: Bei 1, 6 und 7 lief der Test vor der Korrektur nachweislich rot. Bei 2, 3, 5, 8 und 9 besteht der rote Zustand darin, dass der Test neue API verwendet und vorher nicht kompiliert; bei 2 wurde der Rot-Lauf nicht einzeln ausgeführt (die alte Anfrage mit 30 Qualifiern ist länger als 256 Zeichen).

`app/test-all.sh` nach den Korrekturen, alle Stufen grün einschließlich „string catalogs“: AIKit 98, GitHubKit 139, HealthBridge 11, RemindersKit 87, TagwerkCore 636, App 1130 Tests bestanden.

Letzte Zeile: `ALL TESTS PASSED`

## P3 Fokus und Aufwand (#161, #162)

Plan: `plans/2026-11-19-p3-focus-effort.md` · Spike: `spikes/2026-11-19-family-controls.md` · Branch `feat/p3-focus-effort`.
Umgesetzt sind die Tasks 0–11 und 13. Task 12 (App-Sperre) entfällt, weil der Spike negativ ausfiel. Ungeprüft am Gerät (siehe c).

Commits (in Reihenfolge): `1099676` Plan · `0941342` Spike · `ebb5a5c` Phasenregeln · `a7c7ea7` Belohnungsstufen · `4c20e81` Aufwandsregeln · `b93fcf5` Aufwandsstatistik · `0f28458` Speicher · `382af85` Timer, Live Activity und Oberfläche (Tasks 6–8) · `1a1ec4b` Aufwandsmessung · `b85fdb7` Wochenrückblick und KI-Faktor (Tasks 10–11) · `bfc5f61` und `fec397a` Korrekturen aus der Prüfung (Taste der Live Activity nach Hintergrundstart, Link beim Kaltstart).

### Spike (Task 0): negativ

`com.apple.developer.family-controls` ließ sich mit dem Personal Team nicht signieren (Profil enthält die Fähigkeit nicht). In der Kommandozeilen-Sitzung fehlte zusätzlich das Xcode-Konto („No Accounts“), das Profil ließ sich also nicht neu anfordern; das ist im Spike-Dokument vermerkt. Nach der Vorgabe des Plans entfällt Task 12: keine App-Sperre, kein Entitlement, kein Eintrag in den Einstellungen. Im PR-Text steht: „App-Sperre nicht gebaut: Family Controls mit Personal Team nicht signierbar.“

### (a) Entscheidungen

1. **Blockende wird aufgerundet, nicht abgerundet** (Vorgabe der Hauptsitzung, gegen den Plan): Abhaken um 14:21 kürzt den Block auf 14:25, um 14:20 auf 14:20. Gerundet wird auf die Uhr, nicht relativ zum Blockbeginn. Der Ist-Aufwand bleibt unrundet (21 min). Ein Block wird nie verlängert; liegt das aufgerundete Ende am oder nach dem alten Ende, bleibt er. Unter 5 Minuten seit Blockbeginn wird nicht gekürzt.
2. **Zukünftige Blöcke einer erledigten Aufgabe bleiben unberührt** (Vorgabe der Hauptsitzung). Ihre Löschung ist weiter offen.
3. **Eigenes Protokoll für die Mitteilung statt `NotificationCenterClient`.** Optionen: das Protokoll um eine Methode erweitern (Fake und Konflikte mit P4) oder ein eigenes kleines Protokoll. Gewählt: `FocusNotificationCenter` mit eigenem Fake. Der Bezeichner `focus.phaseEnd` liegt außerhalb des Präfixes `tagwerk.`, den `NotificationScheduler` und `RoutineNotificationScheduler` bereinigen. Risiko: zwei Wege zum Mitteilungszentrum.
4. **Nur eine Mitteilung (Ende der laufenden Phase), wie im Plan.** Folge: Läuft ein Pomodoro bei geschlossener App, kommt die Mitteilung nur zum ersten Phasenende; die weiteren Phasen zeigt die Live Activity. Der Gerätetest 2 („Mitteilung zu jedem Phasenende“) kann so nicht bestehen. Alternative: bis zu 3 vorplanen (Budget: 50 + 6 + 1 = 57 von 64, Platz für 7). Nicht gebaut, weil der Plan „höchstens eine“ vorgibt.
5. **Phasenwechsel ergeben sich aus Zeitstempeln, auch ohne Antippen.** Ein 25/5-Pomodoro, um 10:00 gestartet und um 10:26 geöffnet, zeigt die Pause mit 4 Minuten Rest; um 10:31 läuft Runde 2 mit 24 Minuten. Der Plan nennt 10:31 mit „Pause noch 4 min“, das passt nicht zu 25 + 5 Minuten; der Test nutzt 10:26 und 10:31.
6. **„Weiter“ der Live Activity:** In einer Pause überspringt es die Pause, nach dem Ende der Sitzung beendet es sie als gewachsen und startet eine neue für dieselbe Aufgabe. Während der Arbeitsphase gibt es keinen „Weiter“-Knopf.
7. **„Verschieben“ verschiebt zukünftige Blöcke mit** (`assign(… moveBlocks: true)`), statt die Rückfrage der Planung zu öffnen oder die Blöcke zu löschen. Grund: Die Rückfrage wäre über der Live Activity nicht sichtbar, Löschen wäre zerstörend.
8. **Sitzung vor Aufgabe beenden.** `finish(.complete)` speichert die Sitzung (Ende, Fokus-Zeit), bevor die Aufgabe abgehakt wird; sonst sähe die Aufwandsmessung die Fokus-Zeit nicht. Wird die Aufgabe anderswo abgehakt, endet ihre laufende Sitzung als gewachsen (`didComplete(taskKey:)`).
9. **Veraltete Sitzung (über 12 Stunden):** Lief sie durch, zählt sie als gewachsen, sonst als abgebrochen (unter 1 Minute Fokus: verworfen). Ältere offene Reste neben der neuesten werden abgebrochen.
10. **Eine Sitzung unter 1 Minute Fokus hinterlässt nichts** (kein Stück), auch wenn sie „Erledigt“ endet.
11. **Rückgängig stellt das Blockende nur her, wenn niemand den Block danach änderte** (gespeichert: altes und neues Ende des Blocks, Prüfung auf das neue Ende; zusätzlich die Versionsprüfung des Kalenders). Die Stichprobe wird in jedem Fall gelöscht, aber nur für das Abhaken der letzten 24 Stunden.
12. **Wiederkehrende Aufgaben:** Blöcke zählen nur, wenn sie nach dem vorigen Abhaken begannen. Ein Block, der beim vorigen Abhaken lief, wird so nicht ein zweites Mal gezählt.
13. **Fokus-Sitzungen und Messwerte sind nicht in der Datensicherung** (`BackupCoverage` mit Begründung). Offen: Soll die Sammlung eine Wiederherstellung überleben? Dann bräuchte es zwei Backup-Typen.
14. **Branch `feat/p3-focus-effort`** (vorgegeben) statt `feat/focus-timer-effort` aus dem Plan.
15. **Neue Wörter:** „Kurze Pause“ (Phase) und „Pausieren“ (Knopf), damit „Pause“ im Englischen nicht „Pause“ für die Pausenphase heißt; „%lld min Fokus“ ohne Plural; „Dauern im Schnitt …“ als Satzbaustein mit Prozentwert aus dem Format des Gebietsschemas.
16. **Live Activity öffnet den Fokus mit `tagwerk://focus`.** Das ist kein `AppRoute`, sondern wird in `RootView.onOpenURL` vor dem Router abgefangen; ein Link ohne Sitzung wird vorgemerkt und öffnet das Blatt, sobald `restore()` eine Sitzung zurückgebracht hat.

### (b) Abweichungen vom Plan

- **Commits zusammengelegt:** Tasks 6, 7 und 8 sind ein Commit, ebenso 10 und 11 (die Änderungen an `AppEnvironment`, den Katalogen und `en.json` liegen quer zu den Tasks). Die Zwischenstände `0f28458` und `1a1ec4b` wurden nicht einzeln gebaut; `app/test-all.sh` lief auf dem vollständigen Baum vor dem Aufteilen, danach auf `fec397a`.
- **Zusätzliche Eingriffe außerhalb der Konflikttabelle:** `Editor/TaskEditorView.swift` (Eintrag „Fokus starten“ in der Werkzeugleiste, statt in `AppTaskEditorSheet`, weil der Editor seine eigene Navigation hat; nur ohne offene Änderungen), `App/TagwerkApp.swift` (`restore()` beim Start und beim Aktivwerden), `Settings/AISettingsView.swift` (ein Satz im Datenschutzhinweis; `ChatGPTSignInModel.privacyNotice` blieb unverändert, damit `LocalizedTests` und die Kataloge stabil bleiben), `AI/AIPlanner+Revision.swift` (Anweisung mit dem neuen Hinweis), `Backup/BackupCoverage.swift`, `TagwerkTests/Fakes/FakeCalendarStore.swift` (Hook `beforeUpdate`).
- **Mehr als eine Zeile in Dateien der Tabelle:** `RootView` (Blatt, `onOpenURL`, Schließen-Kette in beide Richtungen), `AppEnvironment` (Eigenschaften `focusStore`, `focus`, `effort`, Parameter `focusNotificationCenter` im `init`, Zeile für den Planer, die Hooks), `TaskListModel` (Hook `onCompletedItem`; `didSave` und `applyReturning` sind umgebaut, nicht nur ergänzt, damit die Messung vor `onCompletionChanged` läuft).
- **`FocusShielding` und `FocusShieldPolicy` entfallen** mit Task 12.
- **Sichtprüfung im Simulator (Task 8)** nicht ausgeführt (die Geräte- und Simulatorwerkzeuge sind für diese Instanz gesperrt); sie steht unter den offenen Gerätetests.
- **`FocusTimerModel` bekommt `now` öffentlich und Hooks `completeTask`/`postponeTask`** statt der App-Modelle direkt, damit die Tests ohne `TaskListModel` laufen.
- **Backup:** siehe (a) 13.

### (c) Offene Gerätetests

Die Tests 1–10 aus dem Plan sind alle offen. Zusätzlich:

- Start aus einem Blockblatt und aus dem Aufgabeneditor: Das Blatt schließt, 400 ms später öffnet sich das Fokus-Blatt; prüfen, dass es zuverlässig erscheint.
- `.secondaryAction` im Aufgabeneditor: Sitz und Sichtbarkeit des Eintrags „Fokus starten“.
- Live Activity: Tippen auf die Karte öffnet das Fokus-Blatt, auch bei kaltem Start; „Erledigt“ aus der Sperrbildschirm-Karte nach einem Hintergrundstart schließt die Aufgabe wirklich.
- Gerätetest 2 (Mitteilung zu jedem Phasenende) erwartet mehr als die eine geplante Mitteilung; siehe (a) 4.
- Sichtprüfung des Fokus-Blatts, der Sammlung und des Wochenrückblicks in hell, dunkel und bei großer Schrift (AX3).

### (d) Tests

`app/test-all.sh` auf `fec397a`, alle Stufen grün einschließlich „string catalogs“: AIKit 98, GitHubKit 180, HealthBridge 11, RemindersKit 87, TagwerkCore 798, App 1327 Tests bestanden. Letzte Zeile: `ALL TESTS PASSED`.
