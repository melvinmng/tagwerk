# Tagwerk – Design: GitHub-Issues an andere vergeben (#136)

Stand: 2026-11-19 · Status: **vom Nutzer am 2026-11-19 freigegeben**.

Baut auf:
- `2026-11-17-tagwerk-design.md`: §2 Anti-Ziele, §7 Datenschutz, §10 F1 (Bearbeiten, Konflikte), F1b („Issues, die mir zugewiesen sind“).
- `2026-11-17-phase-2-design.md` und `2026-11-17-phase-2b-design.md`: GitHub Projects als Quelle, Konfliktkarte, Assistent mit Bestätigungskarten.
- `2026-11-18-phase-4-design.md`: Format dieses Dokuments.

Mockup: `../mockups/2026-11-19-issue-assignees-mockups.html` (ZW0, ZA1–ZA2, ZB1–ZB3, ZC1–ZC2, ZD1–ZD3, ZE1–ZE2, ZF1–ZF2; statisches HTML, nicht am Gerät geprüft). Epic: keines (eigenständiges Issue #136).

Kennzeichnung in diesem Dokument: **[Code]** = im Quelltext am Stand `d2eea38` nachgelesen, **[GitHub-Doku]** = aus der Planungsrunde übernommene Aussage der GitHub-Dokumentation (dort am 19.11.2026 geprüft, hier nicht erneut abgerufen), **[Annahme]** = nicht belegt, am Gerät zu prüfen (§10).

## 1. Absicht und Warum

Heute geht jedes in Tagwerk angelegte Issue fest an den angemeldeten Nutzer. Wer ein Issue für jemand anderen anlegen will, muss es danach auf GitHub umhängen. #136 verlangt, die Person schon beim Anlegen zu wählen.

Der Nutzer hat den Umfang in zwei Punkten über die Empfehlung hinaus erweitert: Die Zuweisung ist auch bei bestehenden Issues im Editor änderbar (ZE2), und der KI-Assistent darf beim Anlegen zuweisen (ZF2). Damit wird nebenbei ein bestehender Fehler behoben: Der Assistent kann derzeit gar keine Issues anlegen (§3.1, Punkt 6).

Die Grundregel aus Phase 2 bleibt: **Tagwerk zeigt meine Arbeit.** Ein Issue, das mir nicht (mehr) zugewiesen ist, erscheint weder in „Aufgaben“ noch in der Planung.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Blatt „Neue Aufgabe“: Zeile „Zugewiesen“ mit Mehrfachauswahl (höchstens 10), Vorgabe „Ich“, „Niemand“ zulässig.
- Zur Auswahl stehen die zuweisbaren Personen des gewählten Repositorys, je Repository geladen und 5 Minuten gehalten.
- Ein ohne mich angelegtes Issue kommt nicht in die Liste; eine Kapsel bestätigt Nummer und Person und führt zu GitHub.
- Nach jedem Schreiben vergleicht die App gewünschte und tatsächliche Zuweisung und warnt bei Abweichung.
- Editor: Zeile „Zugewiesen“ ist bei Issues änderbar, mit Konflikterkennung und Rückfrage, bevor ich mich selbst austrage.
- Assistent: `create_task` legt Issues mit Repository, Projects und Zugewiesenen an; die Bestätigungskarte nennt alle drei.
- Englische Texte für alle neuen Zeichenketten.

**Nicht-Ziele (#136)**
- Filter „Vergeben“ oder eine andere Nachverfolgung delegierter Issues (ZD2): eigenes Folge-Issue, abzustimmen mit der Suche.
- Repositories anderer Besitzer oder von Organisationen in der Repository-Liste. Die Liste bleibt bei `affiliation=owner`.
- Sortierung „im Project Aktive zuerst“ (ZA2), eigene Auswahlseite mit Suche und Klarnamen (ZC2), Avatar-Bilder.
- Vorgabe „zuletzt benutzt“ (ZB3).
- Offline-Anlegen oder eine Warteschlange.
- Umverteilen bestehender Issues durch den Assistenten (`update_task` bleibt ohne Zugewiesene; Festlegung F12).
- Zugewiesene in `get_task`/`list_tasks`, im Planungskontext der KI, im Widget oder in Benachrichtigungen.

**Anti-Ziele**
- Ein für mich gedachtes Issue landet unbemerkt bei jemand anderem. Deshalb: Vorgabe ist immer „Ich“, nie eine gemerkte Auswahl; der Fußtext nennt das Ergebnis vor dem Anlegen.
- Fremde Arbeit zählt in meiner Kapazität, in Deadlines, Benachrichtigungen oder im KI-Plan (wäre ZD3). Die Sichtbarkeitsregel `GitHubMapping.isVisible` bleibt unverändert.
- Eine Zuweisung geht still verloren. GitHub verwirft nicht zuweisbare Logins ohne Fehler; die App muss das melden.
- Der Assistent weist jemandem etwas zu, ohne dass der Nutzer die Person auf der Karte gesehen hat. Eine Zuweisung an Dritte ist nach außen sichtbar (GitHub benachrichtigt die Person).
- Logins Dritter gehen an den KI-Anbieter, ohne dass die Anfrage des Nutzers das verlangt.
- Ein Issue verschwindet durch eigenes Austragen aus der Planung, ohne dass der Nutzer vorher gefragt wurde.

## 3. Einschränkungen

### 3.1 Befund im Quelltext [Code]

1. **Anlegen:** `GitHubTaskProvider.create` (`GitHubTaskProvider.swift:168–191`) liest den eigenen Login über `viewerProjects()` und übergibt ihn fest an `GitHubWriter.createIssue(… assignee:)` (`GitHubWriter.swift:54–64`), das `assignees: [assignee]` sendet.
2. **Lesen:** Zugewiesene werden schon gelesen (`assignees(first: 10) { nodes { login } }`, `ProjectsQuery.swift:21`) und liegen in `GitHubIssueRecord.assignees` (`GitHubIssueRecord.swift:104`). `TaskItem`, `TaskDraft` (`TaskItem.swift:47–123`) und `TaskEdit` (`TaskEdit.swift:15–50`) kennen sie nicht.
3. **Sichtbarkeit:** Gelesen wird `is:issue is:open assignee:@me archived:false` (`ProjectsQuery.swift:37–51`); gezeigt wird nur, was offen, mir zugewiesen und in mindestens einem Project nicht „Done“ ist (`GitHubMapping.swift:49–53`).
4. **Katalog:** `GitHubCatalog` hält Repositories und Projects (`GitHubCatalog.swift:5–20`), Haltezeit 5 Minuten (`AppEnvironment.swift:57`), gespeichert als JSON in SwiftData (`SwiftDataGitHubCatalogStore.swift`), beim Abmelden gelöscht (`AppEnvironment.swift:170–175`). Repositories kommen aus `GET user/repos?affiliation=owner` (`GitHubAPI.swift:103`).
5. **Falle beim Anlegen:** `TaskListModel.create` und `createReturning` setzen das zurückgegebene Issue ungeprüft in die Liste (`TaskListModel.swift:285–293`, `341–347`). Ein Issue ohne mich bliebe bis zum nächsten Laden sichtbar.
6. **KI:** `create_task` bietet `source: "github"` an (`AppTools+Definitions.swift:65–72`), `createTask` setzt aber weder `containerID` noch `subContainerIDs` (`AppTools.swift:241–253`). Der Aufruf endet immer mit „Bitte Repository und mindestens ein Project wählen.“ (`GitHubTaskProvider.swift:169–171`).
7. **Editor:** zeigt bei Issues „Repo“ als feste Zeile (`TaskEditorView.swift:65–67`), keine Zugewiesenen. Die Konfliktkarte vergleicht eine feste Feldliste (`ConflictChange.swift:17–27`). Die Version eines Issues ist `updatedAt` des Issues plus `updatedAt` aller Project-Items (`GitHubMapping.swift:90–94`).
8. **Kapsel:** `UndoCapsule` hat einen fest verdrahteten Knopf „Rückgängig“ (`UndoCapsule.swift:57–77`).
9. **Sprachmodus:** Karten lassen sich per gesprochenem „Ja“ bestätigen, Löschungen nur einzeln (`AssistantModel.swift:173–190`).
10. **Token:** OAuth-App im Device Flow mit `repo project offline_access` (`DeviceFlowClient.swift:22`).
11. **Datenschutzhinweis KI:** „Wenn du KI-Funktionen nutzt, gehen die dafür nötigen Daten (Termine, Aufgaben, bei Issues auch Repo-Inhalte) an OpenAI.“ (`ChatGPTSignInModel.swift:10–12`).

Korrektur gegenüber dem Mockup: Dessen Zeilenangaben zu `ProjectsQuery.swift`, `GitHubIssueRecord.swift` und `GitHubTaskProvider.swift` weichen um wenige Zeilen ab; maßgeblich sind die Angaben oben.

### 3.2 Vorgaben von GitHub [GitHub-Doku]

- Ein Project (`ProjectV2`) hat keine lesbare Teilnehmerliste. „Teilnehmer je Project“ aus dem Titel von #136 lässt sich nur als „zuweisbare Personen des gewählten Repositorys“ umsetzen.
- Zuweisbar ist, wen `GET /repos/{owner}/{repo}/assignees` meldet: man selbst, Personen mit Schreibrecht, in Organisationen auch Mitglieder mit Leserecht.
- Höchstens 10 Zugewiesene je Issue.
- Stilles Verwerfen: Wer kein Schreibrecht hat, kann nicht zuweisen; nicht zuweisbare Logins werden ohne Fehler verworfen.
- Zum Ändern gibt es neben `PATCH …/issues/{n}` (ersetzt die ganze Liste) die Endpunkte `POST …/issues/{n}/assignees` (fügt hinzu) und `DELETE …/issues/{n}/assignees` (entfernt).

### 3.3 Annahmen [Annahme]

- A1: Der Scope `repo` reicht zum Lesen der Zuweisbaren und zum Zuweisen; keine neue Anmeldung nötig.
- A2: Eine geänderte Zuweisung ändert `updatedAt` des Issues. Nur dann erkennt die bestehende Versionsprüfung fremde Änderungen an der Zuweisung.
- A3: Die eigenen Repositories des Nutzers haben Mitarbeiter (vom Nutzer am 19.11.2026 bestätigt; als Auskunft übernommen, nicht geprüft).
- A4: Ein SwiftUI-`Menu` mit Schaltern bleibt bis etwa 30 Einträge bedienbar.

## 4. Ansätze

„Empf.“ ist die Empfehlung der Planungsrunde; **Abweichung** markiert, wo der Nutzer anders entschieden hat.

| Frage | Varianten | Abwägung | Entscheidung des Nutzers |
|---|---|---|---|
| **ZA** Wer steht zur Auswahl? | ZA1 Zuweisbare des Repositorys (Empf.) · ZA2 dieselben, im Project Aktive zuerst | ZA1: ein Abruf, genau die Menge, die GitHub annimmt. ZA2: kommt dem Wortlaut „je Project“ näher, braucht aber eine Heuristik über Project-Items und einen zweiten Cache | **ZA1** |
| **ZB** Wie viele, welche Vorgabe? | ZB1 genau eine · ZB2 mehrere, Vorgabe „Ich“ (Empf.) · ZB3 mehrere, zuletzt benutzt | ZB2 erhält das heutige Verhalten ohne Zutun und erlaubt „ich und Lea“. ZB3 riskiert das erste Anti-Ziel | **ZB2**, höchstens 10 |
| **ZC** Form der Auswahl | ZC1 Menü in der Zeile wie „Projekte“ (Empf.) · ZC2 eigene Seite mit Suche | ZC1: kleinster Aufwand, nur Logins. ZC2: Suche und Klarnamen, aber GraphQL statt REST und ein Seitenwechsel | **ZC1** |
| **ZD** Issue ohne mich | ZD1 verschwindet, Kapsel mit Link (Empf.) · ZD2 Filter „Vergeben“ · ZD3 überall wie eigene | ZD1 lässt Lesen, Planung, Widget und KI unberührt. ZD2 braucht zweite Suche und neue Sichtbarkeitsregel. ZD3 verletzt das zweite Anti-Ziel | **ZD1**; ZD2 als Folge-Issue |
| **ZE** Bestehende Issues | ZE1 nur anzeigen (Empf.) · ZE2 änderbar | ZE2 braucht ein Feld in `TaskEdit`, Konfliktlogik und die Rückfrage beim Austragen; etwa 5–6 h mehr | **ZE2 (Abweichung)** |
| **ZF** KI weist zu? | ZF1 nein (Empf.) · ZF2 ja, mit Karte | ZF2 setzt Repository- und Project-Wahl im Werkzeug voraus; Logins Dritter gehen an den KI-Anbieter; etwa 6–8 h mehr | **ZF2 (Abweichung)** |

Begründung der Abweichungen, soweit bekannt: Der Nutzer hat ZE2 und ZF2 ohne weitere Begründung gewählt. Die Folgen (Rückfrage beim Austragen, Logins an OpenAI) sind in §5.5, §5.6 und §6 ausgearbeitet.

Innerhalb von ZF2 standen drei Wege offen, wie der Assistent an Logins kommt (Wahl des Builders, F10):

| Weg | Kern | Abwägung | |
|---|---|---|---|
| Lesewerkzeug `list_assignees` | Das Modell fragt die Logins eines Repositorys nur ab, wenn es zuweisen soll | Logins verlassen das Gerät nur bei Bedarf; das Modell löst „Lea“ → `lea-m` selbst auf | **Gewählt** |
| Liste in den Instruktionen | Alle Zuweisbaren stehen in jedem Aufruf | Sendet Logins bei jeder Nachricht, auch ohne Bezug | verworfen |
| Zuordnung auf dem Gerät | Das Modell übergibt „Lea“, die App sucht den Login | Kein Login verließe das Gerät; ohne Klarnamen (nur REST-Logins) ist die Zuordnung unzuverlässig, bei Mehrdeutigkeit müsste die Liste doch ans Modell | verworfen |

## 5. Design im Einzelnen

### 5.1 Datenmodell

**`TagwerkCore`**

| Ort | Änderung | Bedeutung |
|---|---|---|
| `TaskItem` | `assignees: [String]?` (Standard `nil`) | Logins in der Reihenfolge von GitHub; `nil` bei Quellen ohne Zuweisung |
| `TaskField` | neuer Fall `.assignees` | steht in `editableFields` jedes GitHub-Issues |
| `TaskDraft` | `assignees: [String]?` (Standard `nil`) | `nil` = Vorgabe der Quelle (bei GitHub: ich), `[]` = niemand |
| `TaskEdit` | `assignees: FieldChange<AssigneeChange>` mit `AssigneeChange { add: [String], remove: [String] }` | immer eine Differenz, nie eine Zielliste (F6); `diff` bildet sie aus `original.assignees` und `edited.assignees` als Mengenvergleich ohne Groß-/Kleinschreibung; zählt in `isEmpty` |
| `TaskProvider` | `func isListed(_ item: TaskItem) -> Bool`, Standard `true` | sagt der Liste, ob ein geschriebenes Element in „meine“ Listen gehört |
| neu `AssigneeRules` (reine Logik) | `missing(requested:actual:)`, `change(original:edited:)`, `maximum = 10`, `canonical(_:in:)` | Vergleich nach dem Schreiben, Differenz für `TaskEdit.diff`, Schreibweise eines Logins gegen die Kandidatenliste |

Bestehende Aufrufer bleiben gültig, weil alle neuen Parameter Standardwerte haben.

Die Issue-Nummer für Kapsel, Rückfrage und Warnung kommt wie überall aus der URL (`url.lastPathComponent`, Muster aus `TaskRow.swift:61`); `TaskItem` erhält kein Nummernfeld.

**`GitHubKit`**

- `GitHubAPI.assignableUsers(repository:) -> [String]`: `GET repos/{repository}/assignees?per_page=100`, nur die erste Seite (F4).
- `GitHubCatalog` erhält `assignable: [String: AssignableUsers]` mit `AssignableUsers { logins: [String], fetchedAt: Date }`. Ältere gespeicherte Kataloge ohne den Schlüssel lesen sich weiter (`decodeIfPresent`, leeres Wörterbuch). Kein neues SwiftData-Modell, keine Schema-Änderung: Der Katalog ist ein JSON-Feld.
- `GitHubTaskProvider.assignableUsers(in repository:, maxAge:) async -> [String]?`:
  1. Gespeicherter Stand jünger als `maxAge` → zurückgeben.
  2. Sonst abrufen, im Katalog speichern, zurückgeben.
  3. Scheitert der Abruf: gespeicherter Stand beliebigen Alters, sonst `nil`.
- `catalog(maxAge:)` übernimmt beim Neuladen die `assignable`-Einträge der Repositories, die es weiter gibt. Zuweisbare werden nie im Voraus für alle Repositories geladen und nie im Hintergrund-Refresh.
- `GitHubMapping.taskItem` füllt `assignees` und `.assignees` in `editableFields`.
- `GitHubTaskProvider.isListed(item)`: `true`, wenn der eigene Login in `item.assignees` steht oder der Login unbekannt ist. Die Regel `isVisible` bleibt die einzige Quelle für das Lesen; `isListed` deckt nur den Moment nach einem Schreiben ab.
- `GitHubTaskProvider.storedCatalog` (synchron, liest nur den Speicher) für die Bestätigungskarte des Assistenten.
- **Eigener Login:** Blatt, Editor und Karte lesen `GitHubTaskProvider.login` (Zugriff über den Cast wie in `NewTaskSheet.swift:33`). Er ist nach dem ersten erfolgreichen Laden gesetzt; „GitHub-Issue“ wird im Blatt ohnehin nur bei geladenem GitHub angeboten (`NewTaskSheet.swift:38–45`). Ist er im Editor noch unbekannt (Start aus dem Offline-Cache), zeigt die Zeile die Logins ohne „Ich“; `apply` lädt ihn vor dem Schreiben über `viewerProjects()` nach.

### 5.2 Schreibregeln (`GitHubTaskProvider`)

**Anlegen (`create`)**
1. Zielmenge = `draft.assignees ?? [viewer]`. Mehr als 10 → Fehler „Höchstens 10 Personen je Issue.“ vor jedem Netzaufruf.
2. `createIssue(repository:title:body:assignees:)` sendet die Zielmenge.
3. Projects und Felder wie heute.
4. Das frisch gelesene Issue wird nur dann in `records` gemerkt, wenn `isVisible` es zulässt.
5. Rückgabe ist immer das `TaskItem` mit den tatsächlichen `assignees`.

**Ändern (`apply` mit `edit.assignees == .set(change)`)**
1. `change.add` (im Folgenden `hinzu`) und `change.remove` (`weg`) sind die Differenz gegen den Stand **beim Öffnen** des Editors. Der Provider wendet sie auf den aktuellen Stand an, mit und ohne Versionsprüfung gleich.
2. Prüfung: `(aktuell ∪ hinzu) − weg` hat höchstens 10 Einträge, sonst Fehler vor dem Schreiben.
3. Reihenfolge: Issue-Felder, Project-Felder, Schließen/Öffnen und Status wie heute; **danach** `POST …/assignees` mit `hinzu`, **zuletzt** `DELETE …/assignees` mit `weg`. Scheitert ein früherer Schritt, bin ich noch zugewiesen und das Issue bleibt sichtbar.
4. Frisch lesen; ist das Issue nicht mehr sichtbar, wird es aus `records` entfernt.

Warum Differenz statt `PATCH` mit ganzer Liste: „Trotzdem sichern“ verspricht, nur die eigenen Änderungen zu schreiben (`ConflictBanner.swift:69–74`). Eine ersetzte Liste würde eine zwischenzeitlich auf GitHub hinzugefügte Person wieder entfernen.

**Vergleich nach dem Schreiben** (in `TaskListModel`, quellenunabhängig)
- Anlegen: `AssigneeRules.missing(requested: draft.assignees, actual: created.assignees)`; bei `draft.assignees == nil` kein Vergleich.
- Ändern: fehlend = `hinzu − saved.assignees`. Der Editor reicht `hinzu` beim Zurückgeben an die Liste weiter (`didSave(_:requestedAssignees:)`).
- Nicht leer → Hinweis über den bestehenden Fehlerdialog der Liste (`lastError`), Texte in §5.8.

### 5.3 Listenmodell und Planung (`TaskListModel`, `PlanningModel`)

- `create`, `createReturning`, `didSave` und `applyReturning` fragen nach dem Schreiben `provider.isListed(item)`.
  - `true`: wie heute (`replace`).
  - `false`: Das Element wird aus `items` entfernt bzw. nicht aufgenommen, `lastHandedOver = HandedOverNotice(item:)` gesetzt (trägt Nummer, Zugewiesene und URL) und der Haken `onHandedOver(id)` gerufen.
- `onHandedOver` (in `AppEnvironment` verdrahtet wie `onCompletionChanged`): `PlanningModel` entfernt die Tageszuordnung (`planStore.unassign`) und löscht künftige Zeitblöcke (`blocks.deleteFutureBlocks(of:after:)`, vorhanden in `BlockPlanner.swift:78`), dann `reload()`. Vergangene Blöcke bleiben im Kalender (F8).
- `createReturning` (Assistent) setzt `lastHandedOver` nicht; dort berichtet der Assistent im Text (F11).
- Benachrichtigungen, Widget-Snapshot und Deadline-Karte brauchen keine eigene Regel: Sie lesen `items` und reagieren auf dessen Änderung. **[Annahme]**, im Plan gegen `NotificationScheduler` zu prüfen.

### 5.4 Blatt „Neue Aufgabe“ (Mockup ZB2/ZC1, Ist-Zustand ZW0)

Neue Zeile **„Zugewiesen“** im GitHub-Abschnitt unter „Projekte“, gebaut als `AssigneeSelectionRow` nach dem Muster von `ProjectSelectionRow` (`ProjectSelection.swift:22–68`): Menü mit Schaltern, bleibt beim Wählen offen (`menuActionDismissBehavior(.disabled)`).

- **Zustand:** `assignees: Set<String>`, Anfangswert `[eigener Login]`.
- **Laden:** `.task(id: repository)` ruft `assignableUsers(in:maxAge: AppEnvironment.catalogMaxAge)`. Ein Ergebnis für ein inzwischen abgewähltes Repository wird verworfen.
- **Repository-Wechsel:** setzt die Auswahl auf „Ich“ zurück, auch nach einer eigenen Wahl.
- **Reihenfolge im Menü:** „Ich (login)“ zuerst, dann alphabetisch ohne Groß-/Kleinschreibung. Abschnittstitel „Mehrere möglich · höchstens 10“. Logins ohne Avatar.
- **Grenze:** Sind 10 gewählt, sind die übrigen Schalter deaktiviert.
- **Wert in der Zeile** (`AssigneeSelection.value`): „Niemand“ · „Ich“ · „Ich, lea-m“ · ab drei „3 Personen“. „Ich“ steht immer vorn.
- **Zustände:**

| Zustand | Zeile | Menü |
|---|---|---|
| kein Repository gewählt | „Ich“, deaktiviert | – |
| lädt | „Ich“ | „Ich“ und die deaktivierte Zeile „Personen werden geladen …“ |
| geladen | Auswahl | alle Zuweisbaren |
| Abruf gescheitert, kein alter Stand | „Ich“ | „Ich“ und die deaktivierte Zeile „Personen konnten nicht geladen werden“ |
| nur ich zuweisbar | „Ich“ | nur „Ich“; abwählbar (ergibt „Niemand“) (F3) |

- **Fußtext** ersetzt den festen Satz (`NewTaskSheet.swift:77–85`). Vorrang wie heute: Fehler beim Katalog, dann „Mindestens ein Projekt wählen.“ als vorangestellter Satz, dann der Zuweisungssatz:

| Auswahl | Fußtext |
|---|---|
| nur ich | „Das Issue wird dir zugewiesen.“ |
| ich und andere | „Das Issue wird dir und lea-m zugewiesen.“ (ab drei weiteren: „dir und 3 weiteren Personen“) |
| nur andere | „Das Issue wird lea-m zugewiesen und erscheint danach nicht in deinen Aufgaben.“ |
| niemand | „Das Issue wird niemandem zugewiesen und erscheint danach nicht in deinen Aufgaben.“ |

- **Sichern:** `TaskDraft.assignees` = Auswahl in Menüreihenfolge. `canSave` bleibt unverändert.
- **VoiceOver:** Label „Zugewiesen“, Wert als Liste, Hinweis „Mehrfachauswahl“ (wie „Projekte“).

### 5.5 Kapsel nach dem Vergeben (Mockup ZD1)

- `UndoCapsule` wird verallgemeinert: Knopftext, Symbol, VoiceOver-Hinweis und Ansage werden Parameter; die Vorgaben entsprechen dem heutigen „Rückgängig“. Kein zweiter Kapseltyp.
- Inhalt: Beschriftung „Vergeben“, Titel „#151 an lea-m“ (mehrere: „#151 an lea-m und jonas-k“, ab drei „#151 an 3 Personen“, niemand: „#151 ohne Zuweisung“), Knopf „Auf GitHub öffnen“ (öffnet `url`, schließt die Kapsel). Kein „Rückgängig“.
- Dauer 8 Sekunden (F7); mit VoiceOver wie bisher ohne Zeitgrenze.
- Anzeige in „Aufgaben“ (neben `undoBar`, `TaskListView.swift:308–316`) und in „Planen“ (Kapselstapel in `PlanView`), jeweils aus `taskList.lastHandedOver`. Eine neue Kapsel ersetzt die alte.

### 5.6 Editor (Mockup ZE2)

- Zeile **„Zugewiesen“** unter „Repo“, nur bei GitHub-Issues, mit derselben `AssigneeSelectionRow`.
- Kandidaten: Zuweisbare des Repositorys **vereinigt** mit den aktuell Zugewiesenen. Wer zugewiesen, aber nicht mehr zuweisbar ist, bleibt sichtbar und lässt sich entfernen.
- Laden beim Öffnen des Editors. Bis dahin und bei gescheitertem Abruf zeigt das Menü nur die aktuell Zugewiesenen (entfernen geht, hinzufügen nicht).
- Offline (`isReadOnly`) ist die Zeile eine feste Anzeige.
- `hasChanges` und `TaskEdit.diff` erfassen die Änderung ohne Zutun des Editors (§5.1).

**Rückfrage vor dem Sichern** (neuer Fall `SaveQuestion.handOver(futureBlocks: Int)`):
- Auslöser: Ich stand in `original.assignees` und stehe nicht mehr in `draft.assignees`.
- Die Blockzahl kommt aus `PlanningModel.plannedInfo(for:)` (`PlanningModel.swift:591`); ohne Planungsmodell (Editor aus einem Kontext ohne `planning`) ist sie 0.
- Kollidiert nicht mit den bestehenden Fällen: Diese betreffen nur wiederkehrende Erinnerungen (`TaskEditorModel.swift:121–132`). Die Regel „nie zwei Dialoge“ bleibt gewahrt.
- Titel: „Du bist danach nicht mehr zugewiesen.“
- Text: „#151 verschwindet aus Aufgaben und Planung.“, bei Blöcken zusätzlich „2 geplante Zeitblöcke werden gelöscht.“, bei leerer Zielmenge zusätzlich „Das Issue ist dann niemandem zugewiesen.“
- Knöpfe: „Abgeben“ (destruktiv) · „Abbrechen“.
- Nach „Abgeben“ wird gesichert; §5.3 entfernt das Issue, räumt die Planung auf und zeigt die Kapsel.

**Konflikte**
- `ConflictChange.changes` erhält die Zeile „Zugewiesen“ (Logins kommagetrennt, „–“ bei leer; ohne „Ich“-Ersetzung, weil die Funktion den Login nicht kennt).
- „Neu laden“ übernimmt den Stand von GitHub. „Trotzdem sichern“ schreibt nur die eigene Differenz (§5.2). Die Rückfrage wird nach einer Bestätigung nicht erneut gestellt.
- Bin ich im aktuellen Stand schon ausgetragen (jemand anderes hat mich entfernt), verschwindet das Issue nach jedem Sichern über §5.3; die Kapsel erscheint auch dann.

### 5.7 KI-Assistent (Mockup ZF2)

**Neue Lesewerkzeuge** (laufen ohne Karte, wie `list_tasks`; nur registriert, wenn GitHub angemeldet ist)

| Werkzeug | Parameter | Antwort |
|---|---|---|
| `list_github_targets` | – | `{"repositories":[{"name":"melvinmng/tagwerk","linked_project_ids":["PVT_…"]}],"projects":[{"id":"PVT_…","title":"Tagwerk"}]}` aus `catalog(maxAge:)`; höchstens 30 Repositories (zuletzt gepusht zuerst) |
| `list_assignees` | `repository` | `{"repository":"…","me":"melvinmng","assignees":["jonas-k","lea-m","sam-dev"]}`; Fehler, wenn das Repository nicht im Katalog steht oder die Liste nicht ladbar ist |

**`create_task`** erhält drei Felder (strikt: Pflicht, aber `null` erlaubt):

| Feld | Bedeutung | Bei `null` |
|---|---|---|
| `repository` | `owner/name` aus `list_github_targets` | das einzige Repository des Katalogs; bei mehreren Fehler „Bitte ein Repository nennen.“ |
| `project_ids` | IDs aus `list_github_targets` | die mit dem Repository verknüpften Projects (`catalog.projectIDs(linkedTo:)`, dieselbe Vorauswahl wie im Blatt); sind keine verknüpft: das einzige Project, sonst Fehler „Bitte ein Project nennen.“ |
| `assignees` | Logins aus `list_assignees`; `[]` = niemand | ich |

Regeln beim Ausführen (nach der Bestätigung), nur für `source == "github"`; für andere Quellen müssen die drei Felder `null` sein, sonst Fehler:
1. Repository und Project-IDs müssen im Katalog stehen.
2. Enthält `assignees` jemanden außer mir, wird die Liste der Zuweisbaren geladen. Jeder Login muss darin stehen (Vergleich ohne Groß-/Kleinschreibung, geschrieben wird die Schreibweise von GitHub). Unbekannter Login oder nicht ladbare Liste → Fehler, es wird **nichts** angelegt. Kein blindes Zuweisen.
3. Höchstens 10.
4. `taskList.createReturning` mit `containerID`, `subContainerIDs`, `assignees`.
5. Antwort: `{"ok":true,"number":151,"url":"…","assignees":["lea-m"],"listed":false}`, bei Abweichung zusätzlich `"not_assigned":["…"]`. Nur bei `listed: true` enthält sie `id` und `task`.

**Instruktionen** (`AssistantModel.instructions`, ein Absatz): Für ein GitHub-Issue zuerst `list_github_targets` aufrufen und `repository` und `project_ids` ausdrücklich übergeben. `list_assignees` nur aufrufen, wenn der Nutzer das Issue jemandem zuweisen will. Passt ein genannter Name zu keinem oder zu mehreren Logins, nachfragen statt raten. Im Aufgaben-Chat eines Issues nennt der Kontext dessen Repository als naheliegendes Ziel.

**Bestätigungskarte** (`describe`, Fall `create_task` mit `source == "github"`):
- Titel: Issue-Titel.
- Änderung: „Issue anlegen · melvinmng/tagwerk · Project Tagwerk“, dazu Fälligkeit und Priorität wie heute, dann eine eigene Zeile zur Zuweisung, dann die Notizen.
- Zuweisungszeile: „Zugewiesen: dir“ · „Zugewiesen: dir und lea-m“ · „Zugewiesen: lea-m (nicht dir)“ · „Niemandem zugewiesen“.
- Repository und Projects kommen aus den Argumenten; bei `null` löst die Karte die Vorgabe synchron aus `storedCatalog` auf. Geht das nicht, steht dort „Repository fehlt“ bzw. „Project fehlt“; die Ausführung meldet dann den Fehler an das Modell.

**Sprachmodus:** Eine Karte, die an andere oder an niemanden zuweist, zählt wie eine Löschung: per Stimme nur einzeln bestätigbar, nie zusammen mit anderen Karten (`confirmCards`, `OpenCards`) (F13). „Alle bestätigen“ per Tippen bleibt möglich.

### 5.8 Einstellungen, Texte, Lokalisierung

- **Keine neue Einstellung.**
- **Datenschutzhinweis KI** (`AIStatusMessage.privacyNotice`) wird ergänzt: „… (Termine, Aufgaben, bei Issues auch Repo-Inhalte und GitHub-Benutzernamen zuweisbarer Personen) an OpenAI.“
- Neue Zeichenketten in `Tagwerk/Localizable.xcstrings` bzw. im Katalog von `GitHubKit` (Entwicklungssprache Deutsch, Übersetzung Englisch):

| Deutsch | Englisch |
|---|---|
| Zugewiesen | Assignees |
| Ich · Ich (%@) | Me · Me (%@) |
| Niemand | No one |
| %lld Personen | %lld people |
| Mehrere möglich · höchstens 10 | Multiple allowed · up to 10 |
| Personen werden geladen … | Loading people … |
| Personen konnten nicht geladen werden | Could not load people |
| Das Issue wird dir und %@ zugewiesen. | The issue will be assigned to you and %@. |
| Das Issue wird %@ zugewiesen und erscheint danach nicht in deinen Aufgaben. | The issue will be assigned to %@ and will not appear in your tasks. |
| Das Issue wird niemandem zugewiesen und erscheint danach nicht in deinen Aufgaben. | The issue will not be assigned to anyone and will not appear in your tasks. |
| %lld weiteren Personen | %lld other people |
| Vergeben | Assigned |
| #%lld an %@ · #%lld ohne Zuweisung | #%lld to %@ · #%lld unassigned |
| Auf GitHub öffnen | Open on GitHub (vorhanden) |
| #%lld angelegt, aber %@ konnte nicht zugewiesen werden. | #%lld created, but %@ could not be assigned. |
| %@ konnte nicht zugewiesen werden. | %@ could not be assigned. |
| Höchstens 10 Personen je Issue. | At most 10 people per issue. |
| Du bist danach nicht mehr zugewiesen. | You will no longer be assigned. |
| #%lld verschwindet aus Aufgaben und Planung. | #%lld will disappear from tasks and planning. |
| %lld geplante Zeitblöcke werden gelöscht. | %lld planned time blocks will be deleted. |
| Das Issue ist dann niemandem zugewiesen. | The issue will then be assigned to no one. |
| Abgeben | Hand over |
| Issue anlegen | Create issue |
| Zugewiesen: dir · dir und %@ · %@ (nicht dir) | Assigned to: you · you and %@ · %@ (not you) |
| Niemandem zugewiesen | Not assigned to anyone |
| Repository fehlt · Project fehlt | Repository missing · Project missing |
| Bitte ein Repository nennen. · Bitte ein Project nennen. | Please name a repository. · Please name a project. |
| %@ ist in %@ nicht zuweisbar. | %@ cannot be assigned in %@. |

Mehrzahlformen („1 geplanter Zeitblock wird gelöscht“) über die Plural-Varianten des String Catalogs.

### 5.9 Benachrichtigungen, Deeplinks, Widget

Keine neuen Benachrichtigungen, Routen oder Snapshot-Felder. Ein abgegebenes Issue fällt aus `items` und damit aus allen dreien.

## 6. Datenschutz

- **Neu auf dem Gerät:** Logins zuweisbarer Personen je Repository im Katalog (SwiftData, JSON). Gelöscht mit dem Katalog beim Abmelden von GitHub. Nicht im Widget-Snapshot, nicht in Benachrichtigungen, nicht in Logs.
- **An GitHub:** nur, was GitHub selbst liefert und was der Nutzer wählt.
- **An den KI-Anbieter (OpenAI):** Logins Dritter gehen in genau drei Fällen hinaus:
  1. als Antwort von `list_assignees` (vom Modell ausgelöst, ohne Karte),
  2. als Argument von `create_task`,
  3. in der Werkzeug-Antwort nach dem Anlegen.
  Nicht hinaus gehen sie über `list_tasks`, `get_task`, den Planungskontext oder „Tag planen“.
- **Restrisiko, bewusst in Kauf genommen (ZF2):** Das Modell kann `list_assignees` auch ohne zwingenden Anlass aufrufen; die Instruktion untersagt es, erzwingen lässt es sich nicht. Der Datenschutzhinweis nennt die Benutzernamen deshalb ausdrücklich (§5.8).
- Das Anti-Ziel „Gesundheitsdaten verlassen das Gerät“ aus dem Hauptdesign ist nicht berührt.

## 7. Abhängigkeiten zu den anderen drei Vorhaben

Reihenfolge laut Beschluss: (1) #136, (2) Phase 5, (3) Suche, (4) Phase 7. #136 wird zuerst gebaut und hat keine Voraussetzung in den anderen.

| Vorhaben | Berührung | Folge |
|---|---|---|
| **Phase 5 – Einkaufsliste und Notizen (#113)** | Gleiche Dateien: `NewTaskSheet`, `TaskListView`, `AppTools+Definitions` (falls Phase 5 Werkzeuge ergänzt) | Phase 5 baut auf dem Stand nach #136 auf; die verallgemeinerte Kapsel steht dort zur Verfügung |
| **Suche** | Die Suche durchsucht `TaskItem`. Abgegebene Issues stehen nicht in `items` und sind lokal nicht auffindbar. Das Such-Mockup erwägt eine GitHub-Online-Suche, die auch nicht zugewiesene Issues fände | Solche Treffer wären nur lesbar; der Editor setzt weiter ein mir zugewiesenes Issue voraus. Das Folge-Issue „Vergeben“ (ZD2) wird mit der Suche abgestimmt, nicht hier |
| **Phase 7 – Routinen (#140)** | Keine gemeinsame Logik | Ein abgegebenes Issue zählt nirgends als erledigt |

Kein neuer Tab; die Tab-Leiste bleibt Planen, Aufgaben, Erfassen, Einstellungen.

## 8. Festlegungen des Builders („meine Festlegungen“)

Vom Nutzer nicht entschieden, hier festgelegt. F1–F2 stammen aus der Planungsrunde und sind nach Code-Prüfung beibehalten.

1. **F1 (übernommen):** Liste je Repository bei dessen Wahl laden, 5 Minuten im Katalog halten; Repository-Wechsel setzt auf „Ich“; Logins ohne Avatar, „Ich“ oben; Ladefehler → nur „Ich“; offline kein Anlegen.
2. **F2 (übernommen):** „Niemand“ ist zulässig, mit Hinweis im Fußtext.
3. **F3 (Abweichung vom Sonderfall-Vorschlag des Mockups):** Auch wenn nur ich zuweisbar bin, bleibt das Menü aktiv. Sonst wäre „Niemand“ in diesem Fall nicht wählbar, und es gäbe einen Sonderzweig mehr.
4. **F4:** Nur die ersten 100 Zuweisbaren (eine Seite). Für persönliche Repositories reicht das; Organisationen sind Nicht-Ziel.
5. **F5:** „Ich“ wird immer angeboten und ist Vorgabe, auch wenn GitHub mich nicht als zuweisbar meldet. Der Vergleich nach dem Anlegen fängt den Fall ab.
6. **F6:** Der Editor schreibt Zuweisungen als Differenz über `POST`/`DELETE …/assignees`, nicht als ersetzte Liste; das eigene Austragen ist der letzte Schreibschritt.
7. **F7:** Kapsel 8 statt 5 Sekunden, weil sie der einzige Weg zum Link ist. Kein „Rückgängig“.
8. **F8:** Beim Abgeben werden Tageszuordnung und künftige Zeitblöcke gelöscht, vergangene Blöcke bleiben. Die Rückfrage nennt die Zahl der Blöcke.
9. **F9:** Die Liste entscheidet über `TaskProvider.isListed`, nicht über GitHub-Wissen im `TaskListModel`. Die Warnung bei stillem Verwerfen läuft über den bestehenden Fehlerdialog.
10. **F10:** Der Assistent bekommt Logins nur über das Lesewerkzeug `list_assignees`; kein neues Einstellungsfeld „Standard-Repository“. Repository und Projects wählt das Modell aus `list_github_targets`, Vorgaben nur als Sicherheitsnetz (§5.7).
11. **F11:** Legt der Assistent ein Issue ohne mich an, erscheint keine Kapsel; der Assistent nennt Nummer und Link im Text.
12. **F12:** Der Assistent weist nur beim **Anlegen** zu. `update_task` bekommt keine Zugewiesenen; Umverteilen bleibt dem Editor vorbehalten, weil dort die Rückfrage mit Blockzahl sitzt.
13. **F13:** Karten mit Zuweisung an andere oder niemanden sind per Stimme nur einzeln bestätigbar.
14. **F14:** `get_task` und `list_tasks` liefern keine Zugewiesenen (Datensparsamkeit). Der Assistent kann „wem ist #151 zugewiesen?“ damit nicht beantworten.
15. **F15:** Die Zeile „Zugewiesen“ erscheint im Editor bei jedem Issue, auch wenn nur ich zugewiesen bin (das Mockup ZE1 zeigte sie erst ab zwei Personen; bei ZE2 muss sie immer erreichbar sein).

## 9. Abnahmekriterien

1. Ohne Zutun verhält sich das Anlegen wie heute: Issue an mich, erscheint in der Liste.
2. „Ich + lea-m“: Issue erscheint in der Liste; GitHub zeigt beide.
3. Nur „lea-m“: Issue erscheint nicht in der Liste, auch nicht kurz; Kapsel mit funktionierendem Link.
4. „Niemand“: wie 3, Kapsel „#… ohne Zuweisung“.
5. Verwirft GitHub einen Login, erscheint die Warnung mit dem Namen.
6. Editor: Person hinzufügen und entfernen wirkt auf GitHub; eine zwischenzeitlich auf GitHub hinzugefügte Person bleibt nach „Trotzdem sichern“ erhalten.
7. Editor: Mich austragen fragt nach, nennt die Blockzahl, entfernt danach Issue, Tageszuordnung und künftige Blöcke.
8. Assistent: „Leg ein Issue … in tagwerk an und gib es Lea“ ergibt eine Karte mit Repository, Project und „Zugewiesen: lea-m (nicht dir)“; ohne Bestätigung wird nichts angelegt; ein unbekannter Name führt zu einer Rückfrage, nicht zu einem Issue.
9. Assistent: Ein GitHub-Issue ohne Zuweisungswunsch wird an mich angelegt (heute: Fehler).
10. Alle neuen Texte liegen auf Englisch vor.

## 10. Offene Punkte / Spikes am Gerät

Keine Frage an den Nutzer offen. Zu prüfen, bevor Aufgabe 3 beginnt (etwa 1 h, mit einem Wegwerf-Issue):

| Nr. | Prüfung | Folge bei negativem Ergebnis |
|---|---|---|
| S1 | `GET …/assignees` und Zuweisen mit dem vorhandenen Token (A1) | Scope erweitern, einmalige Neuanmeldung, Hinweis in den Einstellungen |
| S2 | Zuweisen ändert `updatedAt` des Issues (A2) | Zugewiesene in `GitHubMapping.version` aufnehmen |
| S3 | Stilles Verwerfen tritt wie dokumentiert auf (Login ohne Zugriff) | Warntext anpassen, falls GitHub doch mit Fehler antwortet |
| S4 | `DELETE …/assignees` mit dem eigenen Login in einem eigenen Repository | Austragen über `PATCH` mit ganzer Liste, nur für diesen Fall |
| S5 | Menü mit 10 gewählten und etwa 30 Einträgen bleibt bedienbar (A4) | Folge-Issue für ZC2 |
| S6 | Gesprochene Bestätigung einer Zuweisungskarte nur einzeln | – |

Nicht am Gerät, aber im Plan zu prüfen: Benachrichtigungen und Widget-Snapshot folgen dem Entfernen aus `items` (§5.3).

## 11. Aufgabenschnitt

| Nr. | Aufgabe | Inhalt | Schätzung |
|---|---|---|---|
| 0 | Spike | S1–S4 am Gerät | 1 h |
| 1 | Kernmodell | `TaskItem`/`TaskDraft`/`TaskEdit`/`TaskField`, `isListed`, `AssigneeRules`, Tests | 2 h |
| 2 | GitHubKit lesen | `assignableUsers`, Katalog-Erweiterung mit Rückwärtskompatibilität, Mapping, Tests mit `StubTransport` | 2,5 h |
| 3 | GitHubKit schreiben | `create` mit Zielmenge, Differenz-Schreiben, Reihenfolge, Sichtbarkeit nach dem Schreiben, Tests | 3 h |
| 4 | Listenmodell | `isListed`-Prüfung in vier Schreibwegen, `lastHandedOver`, Vergleich und Warnung, `onHandedOver` mit Planungs-Aufräumen, Tests | 2,5 h |
| 5 | Blatt „Neue Aufgabe“ | `AssigneeSelectionRow`, `AssigneeSelection` (Wert, Fußtext), Zustände, Tests | 2,5 h |
| 6 | Kapsel | `UndoCapsule` verallgemeinern, Anzeige in Aufgaben und Planen | 1,5 h |
| 7 | Editor | Zeile, Kandidaten, `SaveQuestion.handOver`, Konfliktzeile, Weitergabe an die Liste, Tests | 4 h |
| 8 | Assistent | zwei Lesewerkzeuge, `create_task`-Erweiterung, Karte, Instruktionen, Sprachmodus-Regel, Tests (`AppToolsTests`, `AssistantModelTests`) | 6 h |
| 9 | Texte | Englisch, Datenschutzhinweis, Plural-Varianten | 1 h |
| 10 | Geräteprüfung | Abnahmekriterien §9, S5–S6 | 1,5 h |
| | **Summe** | | **27,5 h** |

Die Schätzungen sind Erfahrungswerte des Builders ohne Messgrundlage. Aufgaben 1–6 (etwa 14 h) ergeben für sich einen lauffähigen Stand ohne Editor und Assistent; 7 und 8 sind voneinander unabhängig.

## 12. Dem Umsetzenden überlassen

Ordner- und Dateinamen, Testaufbau, genaue Typnamen (`AssigneeRules`, `HandedOverNotice`, `AssignableUsers`), Wortlaut der Werkzeug-Beschreibungen für das Modell, Abstände und Symbole im Rahmen des Mockups.
