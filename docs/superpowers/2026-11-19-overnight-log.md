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
- Abschlussreview: Selbstreview des Autors, kein unabhängiger Reviewer (keine Subagenten erlaubt).

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
