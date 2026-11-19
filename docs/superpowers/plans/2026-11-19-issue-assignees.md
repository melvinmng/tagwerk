# GitHub-Issues an andere vergeben (#136) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026 auf Grundlage des freigegebenen Specs. Nichts gebaut, nichts am Gerät oder im Simulator geprüft. Code-Stand der Befunde: `d2eea38`.

**Goal:** Beim Anlegen und Bearbeiten eines GitHub-Issues lassen sich bis zu 10 Personen zuweisen (Blatt, Editor, KI-Assistent); ein Issue ohne mich verschwindet aus Liste und Planung, und eine von GitHub still verworfene Zuweisung wird gemeldet.

**Architecture:** `TagwerkCore` bekommt `assignees` an `TaskItem`/`TaskDraft`, eine Differenz `AssigneeChange` in `TaskEdit`, reine Regeln (`AssigneeRules`) und `TaskProvider.isListed`. `GitHubKit` lädt die Zuweisbaren je Repository in den vorhandenen Katalog (JSON, keine Schema-Änderung) und schreibt Zuweisungen als Differenz über `POST`/`DELETE …/assignees`. `TaskListModel` entscheidet quellenunabhängig über `isListed`, meldet „vergeben“ (`lastHandedOver`) und räumt über `onHandedOver` die Planung auf; Blatt, Editor und Assistent setzen darauf auf.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, Swift Testing, GitHub REST + GraphQL, String Catalogs (Deutsch als Quellsprache, Englisch).

**Spec:** `docs/superpowers/specs/2026-11-19-issue-assignees-design.md` (freigegeben 19.11.2026, maßgeblich). Mockup: `docs/superpowers/mockups/2026-11-19-issue-assignees-mockups.html`.

**Nicht in diesem Plan:** alle Nicht-Ziele aus Spec §2 (Filter „Vergeben“, fremde Repositories, Avatare, Suche/Klarnamen, „zuletzt benutzt“, Offline-Warteschlange, Umverteilen durch `update_task`, Zugewiesene in `get_task`/`list_tasks`/Widget/Benachrichtigungen).

## Global Constraints

- Höchstens **10** Zugewiesene je Issue (`AssigneeRules.maximum`); Fehlertext „Höchstens 10 Personen je Issue.“ vor jedem Netzaufruf.
- Vorgabe ist immer „Ich“; nie eine gemerkte Auswahl. `TaskDraft.assignees == nil` = Vorgabe der Quelle, `[]` = niemand.
- Zuweisbare: `GET repos/{repository}/assignees?per_page=100`, nur die erste Seite; Haltezeit `AppEnvironment.catalogMaxAge` (5 Minuten); nie im Voraus für alle Repositories, nie im Hintergrund-Refresh.
- Der Editor schreibt Zuweisungen nur als Differenz (`POST` hinzu, danach `DELETE` weg), nie als ersetzte Liste; das eigene Austragen ist der letzte Schreibschritt.
- `GitHubMapping.isVisible` bleibt unverändert und die einzige Leseregel.
- Login-Vergleiche ohne Groß-/Kleinschreibung; geschrieben wird die Schreibweise von GitHub.
- Logins Dritter gehen nur über `list_assignees`, `create_task`-Argumente und die Antwort von `create_task` an den KI-Anbieter; nicht in Logs, Widget, Benachrichtigungen, `list_tasks`, `get_task`.
- Kapsel „Vergeben“: 8 Sekunden, Knopf „Auf GitHub öffnen“, kein „Rückgängig“.
- Kein neues SwiftData-Modell, keine neue Einstellung, kein neuer Tab.
- Texte: Deutsch im Quelltext, Englisch im Katalog nach Spec §5.8. **Jeder Task trägt seine neuen Zeichenketten samt englischem Wert selbst ein** (`scripts/sync-strings.sh`, dann Englisch ergänzen), weil `app/test-all.sh` in der Stufe „string catalogs“ sonst rot wird.
- Code-Bezeichner, Kommentare, Log- und Testmeldungen englisch. Commits im Stil `feat: …`/`fix: …`/`docs: …`, ohne Hinweis auf KI, ohne Co-Authored-By.
- Neue Parameter haben Standardwerte; bestehende Aufrufer bleiben gültig.

**Testbefehle** (Kürzel in den Tasks; Schema je Paket `<Pkg>` oder `<Pkg>-Package` wie in `app/test-all.sh`):

- `PKG <Paket> <Suite>` = `cd app/Packages/<Paket> && xcodebuild test -testLanguage de -testRegion DE -scheme <Paket> -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:<Paket>Tests/<Suite>`
- `APP <Suite>` = `cd app && xcodegen --quiet && xcodebuild test -testLanguage de -testRegion DE -project Tagwerk.xcodeproj -scheme Tagwerk -destination 'platform=iOS Simulator,name=iPhone 18 Pro' -only-testing:TagwerkTests/<Suite>`
- `ALL` = `app/test-all.sh`, erwartet `ALL TESTS PASSED`.

## Review Focus

Fälle, die das Spec nahelegt, aber nicht ausbuchstabiert; jeder ist unten einem Test zugeordnet.

1. **Abweichende Schreibweise des eigenen Logins** (`Melvinmng` vs. `melvinmng`): Das Issue bleibt gelistet, „Ich“ wird erkannt, keine falsche Warnung. → Task 1 (`AssigneeRulesTests`), Task 3 (`isListed_ignoresCase`).
2. **Repository-Wechsel während des Ladens**: Die verspätete Antwort für das alte Repository darf die Auswahl des neuen nicht füllen. → Task 5 (`AssigneeLoadTests.staleResultIsDiscarded`).
3. **Anlegen an andere, GitHub verwirft alle**: Issue ist niemandem zugewiesen; Kapsel „ohne Zuweisung“ **und** Warnung, kein Eintrag in der Liste. → Task 4 (`create_droppedOnlyAssignee_warnsAndHandsOver`).
4. **Abgeben eines Issues mit geänderter Planung im selben Editor-Durchgang**: Nach dem Sichern darf `applyPlanning` keinen Tag oder Block für das abgegebene Issue neu anlegen. → Task 7 (`handOver_skipsPlanningEdit`).
5. **`DELETE …/assignees` scheitert nach erfolgreichem `POST`**: Ich bleibe zugewiesen, das Issue bleibt in der Liste, der Fehler wird gezeigt, die hinzugefügte Person bleibt (kein stiller Halbzustand ohne Meldung). → Task 3 (`apply_removeFails_keepsIssueListedAndThrows`).

## Ausgangslage (Befund)

| Stelle | Ist |
|---|---|
| `app/Packages/TagwerkCore/Sources/TagwerkCore/TaskItem.swift:42–44, 47–95, 98–123` | `TaskField` ohne `.assignees`; `TaskItem`, `TaskDraft` ohne Zugewiesene. |
| `TagwerkCore/TaskEdit.swift:15–50` | `TaskEdit` mit neun Feldern, `isEmpty`, `diff`. |
| `TagwerkCore/TaskProvider.swift:18–48` | Protokoll ohne `isListed`; Standardwerte in der Extension. |
| `app/Packages/GitHubKit/Sources/GitHubKit/GitHubCatalog.swift:5–20` | `repositories`, `projects`, `fetchedAt`; synthetisiertes `Codable`. |
| `GitHubKit/GitHubAPI.swift:103–115, 119–125` | `ownedRepositories()` als Muster für REST-Lesen; `rest(_:_:query:body:)`. |
| `GitHubKit/GitHubWriter.swift:54–64` | `createIssue(… assignee: String)` sendet `assignees: [assignee]`. |
| `GitHubKit/GitHubTaskProvider.swift:112–128, 168–191, 212–224, 237–274` | `apply` merkt `fresh` immer; `create` weist fest dem Viewer zu und merkt immer; `catalog(maxAge:)` ersetzt den Katalog ganz; `write` endet mit Status. |
| `GitHubKit/GitHubMapping.swift:49–53, 55–87` | `isVisible` vergleicht `assignees.contains(login)` exakt; `taskItem` füllt keine Zugewiesenen. |
| `GitHubKit/Tests/GitHubKitTests/Fixtures.swift:93–113` | `Fixtures.issue(…)` mit festem `assignees: octo`. |
| `app/Tagwerk/Tasks/TaskListModel.swift:285–293, 300–311, 322–347` | `create`, `didSave`, `applyReturning`, `createReturning` rufen `replace` ungeprüft. |
| `app/Tagwerk/Tasks/NewTaskSheet.swift:69–93, 148–162` | GitHub-Abschnitt mit festem Fußtext; `save()` ohne Zugewiesene. |
| `app/Tagwerk/Tasks/ProjectSelection.swift:22–68` | Vorbild für Menüzeile mit Schaltern. |
| `app/Tagwerk/Tasks/UndoCapsule.swift:5–78` | Knopftext „Rückgängig“, Symbol, Hinweis und Ansage fest; sieben Aufrufer (`TaskListView`, `PlanView` ×5, `CaptureView`, `DrinkSheet`). |
| `app/Tagwerk/Tasks/TaskListView.swift:85, 308–316`, `app/Tagwerk/Planning/PlanView.swift:98–102` | Kapsel über `safeAreaInset` bzw. `overlay`-Stapel mit `.padding(.bottom, 60)`. |
| `app/Tagwerk/Editor/TaskEditorModel.swift:31–37, 121–132, 158–178` | `init(item:provider:addComment:)`; `SaveQuestion` mit zwei Fällen; `write` kennt weder Login noch `isListed`. |
| `app/Tagwerk/Editor/TaskEditorView.swift:9, 65–67, 172–200, 250–257` | `onSaved: (TaskItem) -> Void`; feste Zeile „Repo“; ein Dialog; `finish` ruft `applyPlanning`. Aufrufer: `TaskListView.swift:115–123`, `RootView.swift:87–92`, `SuggestionViews.swift:719–724`. |
| `app/Tagwerk/Editor/ConflictChange.swift:17–27` | Feste Feldliste ohne Zugewiesene. |
| `app/Tagwerk/Planning/PlanningModel.swift:580–593`, `PlanStore.swift:26`, `BlockPlanner.swift:78` | `didChangeCompletion` als Muster; `plannedInfo(for:)` zählt Blöcke ab Tagesbeginn; `unassign`, `deleteFutureBlocks(of:after:)` vorhanden. |
| `app/Tagwerk/App/AppEnvironment.swift:57, 120–123, 168, 170–175` | `catalogMaxAge`; `AppTools`/`AssistantModel` ohne GitHub-Zugang; Verdrahtung `onCompletionChanged`. |
| `app/Tagwerk/AI/AppTools.swift:13, 31, 241–253`, `AppTools+Definitions.swift:65–72` | `readTools`, `definitions` statisch; `createTask` ohne Container. |
| `app/Tagwerk/AI/AssistantModel.swift:167–190, 349–366, 411–431` | `openCards` zählt nur `delete_event`; `confirmCards` lässt Löschungen nur einzeln zu; `describe` für `create_task`. |
| `TagwerkCore/Voice/VoiceReply.swift:40–52`, `VoiceModeMachine.swift:390–397`, `ActionAnnouncement.swift:63–77` | `OpenCards(ids:deletes:)`; bei `deletes > 0` verlangt die Maschine „Ja, löschen“ bzw. sagt `.deletesNeedTap`. |
| `app/Tagwerk/AI/ChatGPTSignInModel.swift:10–12` | Datenschutzhinweis ohne Benutzernamen. |
| `app/TagwerkTests/Fakes/FakeTaskProvider.swift` | `create`/`apply` ohne Zugewiesene, kein `isListed`. |

**Prüfung „Benachrichtigungen und Widget folgen `items`“ (Spec §5.3, §10):** `AppEnvironment.startNotificationUpdates` plant neu, wenn sich Aufgaben ändern (`AppEnvironment.swift:305 ff.`), der Snapshot wird über `scheduleSnapshot()` aus `taskList.items` gebaut. Beide lesen `items`; ein eigener Aufräumschritt ist nicht nötig. Task 4 sichert das mit einem Test ab (`handOver_removesPendingNotification`); am Gerät in Task 11 gegenprüfen.

## Abweichungen vom Spec

| Nr. | Spec | Befund im Code | Auflösung im Plan |
|---|---|---|---|
| A1 | §5.6: Blockzahl aus `PlanningModel.plannedInfo(for:)` | `plannedInfo` zählt Blöcke ab **Tagesbeginn**; gelöscht wird laut §5.3/F8 nur Künftiges, vergangene Blöcke bleiben. Zahl und Wirkung würden auseinanderfallen. | Neue Methode `PlanningModel.futureBlockCount(for:)` zählt ab `now()`; `didHandOver` löscht ab demselben `now()`. |
| A2 | §5.7/F13: Zuweisungskarte „zählt wie eine Löschung“ über `OpenCards` | `deletes > 0` lässt die Sprachmaschine „Ja, löschen“ verlangen und „Löschungen bitte einzeln bestätigen.“ sagen. | Eigener Zähler `OpenCards.guarded` (Standard 0): einzelne Karte mit „Ja“ bestätigbar, „alle“ wird abgelehnt mit neuer Ansage `.guardedNeedTap`. |
| A3 | §5.2: `didSave(_:requestedAssignees:)` | `onSaved` ist `(TaskItem) -> Void` an drei Aufrufstellen. | `onSaved: (TaskItem, [String]) -> Void`; `didSave(_:requestedAssignees: = [])` hält `AIPlanner.swift:526` gültig. |
| A4 | §5.2 Ändern, Schritt 4: „nicht mehr sichtbar → aus `records` entfernen“ | `apply` merkt heute auch geschlossene Issues (Erledigen/Rückgängig bauen darauf). | Entfernt wird nur, wenn der eigene Login nicht mehr zugewiesen ist; das Verhalten beim Schließen bleibt. `create` nutzt wie im Spec `isVisible`. |
| A5 | §5.8: Texte „Das Issue wird dir und %@ zugewiesen.“, „Zugewiesen: dir und %@“ | Mit genau zwei weiteren Personen entstünde „dir und lea-m und jonas-k“. | Ein Schlüssel mit fertiger Liste: „Das Issue wird %@ zugewiesen.“ / „Zugewiesen: %@“ / „Zugewiesen: %@ (nicht dir)“; „dir“/„you“ ist Listenelement, Verknüpfung über `ListFormatStyle(.and)`. Ausgabe für alle Beispiele des Specs unverändert. Die Karte nennt immer alle Logins (Anti-Ziel 4), nie eine Anzahl. |
| A6 | §5.7: Werkzeuge über Cast auf `GitHubTaskProvider` | `AppToolsTests` arbeiten mit `FakeTaskProvider`; ein Cast ist dort nicht prüfbar. | App-Protokoll `GitHubDirectory` (Task 8), `GitHubTaskProvider` erfüllt es; Blatt und Editor casten weiter wie im Spec. |
| A7 | §5.1: Zuweisbare „im Katalog speichern“ | Ohne gespeicherten Katalog gibt es kein Ziel. | Dann wird das Ergebnis zurückgegeben, aber nicht gehalten. |

## Betroffene Dateien

| Datei | Änderung |
|---|---|
| `TagwerkCore/AssigneeRules.swift` (neu) | `AssigneeChange`, `AssigneeRules`. |
| `TagwerkCore/TaskItem.swift`, `TaskEdit.swift`, `TaskProvider.swift` | Felder, `.assignees`, `isListed`. |
| `TagwerkCore/Voice/VoiceReply.swift`, `VoiceModeMachine.swift`, `ActionAnnouncement.swift` | `OpenCards.guarded`, Regel, Ansage. |
| `GitHubKit/GitHubCatalog.swift`, `GitHubAPI.swift`, `GitHubWriter.swift`, `GitHubMapping.swift`, `GitHubTaskProvider.swift`, `Resources/Localizable.xcstrings` | Lesen, Katalog, Schreiben. |
| `app/Tagwerk/Tasks/HandedOverNotice.swift` (neu) | Notiz für die Kapsel, `TaskItem.issueNumber`. |
| `app/Tagwerk/Tasks/AssigneeSelection.swift` (neu) | Texte (`AssigneeSelection`), Ladezustand (`AssigneeLoad`), `AssigneeSelectionRow`. |
| `app/Tagwerk/Tasks/TaskListModel.swift`, `NewTaskSheet.swift`, `UndoCapsule.swift`, `TaskListView.swift` | Listenregeln, Blatt, Kapsel. |
| `app/Tagwerk/Planning/PlanningModel.swift`, `PlanView.swift` | `didHandOver`, `futureBlockCount`, Kapsel. |
| `app/Tagwerk/Editor/TaskEditorModel.swift`, `TaskEditorView.swift`, `ConflictChange.swift` | Zeile, Rückfrage, Konfliktzeile. |
| `app/Tagwerk/App/AppEnvironment.swift`, `RootView.swift`, `app/Tagwerk/Planning/SuggestionViews.swift` | Verdrahtung, `onSaved`. |
| `app/Tagwerk/AI/GitHubDirectory.swift` (neu), `AppTools.swift`, `AppTools+Definitions.swift`, `AppTools+GitHub.swift` (neu), `AssistantModel.swift`, `ChatGPTSignInModel.swift` | Werkzeuge, Karte, Instruktionen, Hinweis. |
| `app/Tagwerk/Localizable.xcstrings` | Neue Texte deutsch/englisch. |
| Tests | `AssigneeRulesTests` (neu), `TaskEditTests`, `VoiceModeMachineTests`; `GitHubAssigneeTests` (neu), `GitHubCreateTests`, `GitHubTaskProviderWriteTests`, `GitHubMappingTests`, `Fixtures`; `AssigneeSelectionTests` (neu), `TaskListModelTests`, `TaskEditorModelTests`, `EstimateAndConflictTests`, `AppToolsTests`, `AssistantModelTests`, `GitHubPersistenceTests`, `LocalizedTests`, `Fakes/FakeTaskProvider.swift`, `Fakes/FakeGitHubDirectory.swift` (neu). |

## Tasks

Zuordnung zu den GitHub-Issues: Spalte „Issue-Gruppe“ nennt die Zeile aus Spec §11 (Aufgabenschnitt). Tasks 8 und 9 teilen sich Zeile 8.

| Task | Issue-Gruppe (Spec §11) | Schätzung | Hängt ab von |
|---|---|---|---|
| 0 Spike S1–S4 | Nr. 0 Spike | 1 h | – |
| 1 Kernmodell | Nr. 1 Kernmodell | 2 h | – |
| 2 GitHubKit lesen | Nr. 2 GitHubKit lesen | 2,5 h | 1 |
| 3 GitHubKit schreiben | Nr. 3 GitHubKit schreiben | 3 h | 0, 2 |
| 4 Listenmodell | Nr. 4 Listenmodell | 2,5 h | 1 |
| 5 Blatt „Neue Aufgabe“ | Nr. 5 Blatt | 2,5 h | 2, 4 |
| 6 Kapsel | Nr. 6 Kapsel | 1,5 h | 4 |
| 7 Editor | Nr. 7 Editor | 4 h | 3, 4, 5, 6 |
| 8 Assistent: Werkzeuge | Nr. 8 Assistent | 3,5 h | 3, 4 |
| 9 Assistent: Karte, Instruktionen, Sprachmodus | Nr. 8 Assistent | 2,5 h | 8 |
| 10 Texte | Nr. 9 Texte | 1 h | 5–9 |
| 11 Geräteprüfung | Nr. 10 Geräteprüfung | 1,5 h | alle |
| **Summe** | | **27,5 h** | |

Tasks 1–6 ergeben einen lauffähigen Stand ohne Editor und Assistent; 7 und 8/9 sind voneinander unabhängig.

---

### Task 0: Spike S1–S4 am Gerät (manuell, vor Task 3)

**Issue-Gruppe:** Nr. 0 Spike. **Files:** keine Code-Änderung; Ergebnis als Abschnitt „Spike-Ergebnis (Datum)“ am Ende dieses Plans.

Vorbereitung: ein Wegwerf-Issue in einem eigenen Repository mit mindestens einem Mitarbeiter; das Token der App (Debug-Build, Device Flow `repo project offline_access`). Aufrufe mit `curl -H "Authorization: Bearer <token>" -H "X-GitHub-Api-Version: 2022-11-28"`.

- [ ] **S1:** `GET /repos/{owner}/{repo}/assignees?per_page=100` und `POST /repos/{owner}/{repo}/issues/{n}/assignees` mit `{"assignees":["<mitarbeiter>"]}`.
  Pass: 200 mit Login-Liste bzw. 201 und der Login steht in `assignees`. Fail (403/404): Task 2 erhält den Zusatzschritt „Scope erweitern“ (`DeviceFlowClient.swift:22`), einmalige Neuanmeldung und ein Hinweis in `GitHubSettingsSection`; Schätzung +2 h, vor Weiterarbeit mit dem Nutzer abstimmen.
- [ ] **S2:** `updatedAt` des Issues vor und nach S1 vergleichen (`GET /repos/{owner}/{repo}/issues/{n}`).
  Pass: Wert ändert sich. Fail: Task 3 nimmt die sortierten Logins in `GitHubMapping.version` auf (Zusatztest `version_changesWithAssignees`).
- [ ] **S3:** `POST …/assignees` mit einem Login ohne Zugriff auf das Repository.
  Pass: 201, Login fehlt in der Antwort. Fail (4xx): Der Vergleich nach dem Schreiben bleibt; zusätzlich bildet `GitHubTaskProvider.taskError` den Status auf „%@ ist in %@ nicht zuweisbar.“ ab (Task 3).
- [ ] **S4:** `DELETE /repos/{owner}/{repo}/issues/{n}/assignees` mit `{"assignees":["<eigener login>"]}`.
  Pass: 200, eigener Login fehlt. Fail: Task 3 trägt den eigenen Login über `PATCH` mit der vollständigen Zielliste aus, nur für diesen Fall; alle anderen Differenzen bleiben bei `POST`/`DELETE`.
- [ ] Ergebnis mit Datum im Plan festhalten; Wegwerf-Issue schließen.

---

### Task 1: Kernmodell (`TagwerkCore`)

**Issue-Gruppe:** Nr. 1 Kernmodell.

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/AssigneeRules.swift`
- Modify: `TagwerkCore/TaskItem.swift:42–44, 47–123`, `TagwerkCore/TaskEdit.swift:15–50`, `TagwerkCore/TaskProvider.swift:18–48`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/AssigneeRulesTests.swift` (neu), `TaskEditTests.swift`

**Interfaces – Produces:**

```swift
public struct AssigneeChange: Sendable, Equatable {
    public var add: [String]
    public var remove: [String]
    public init(add: [String] = [], remove: [String] = [])
}

public enum AssigneeRules {
    public static let maximum = 10
    /// Case-insensitive membership.
    public static func contains(_ logins: [String]?, _ login: String) -> Bool
    /// Requested logins that are not in `actual`, in the order of `requested`; `[]` when `requested` is nil.
    public static func missing(requested: [String]?, actual: [String]?) -> [String]
    /// Set difference without case; `nil` when both sides hold the same logins. `add` and `remove` keep source order.
    public static func change(original: [String]?, edited: [String]?) -> AssigneeChange?
    /// (current ∪ add) − remove, order of `current`, then `add`.
    public static func applying(_ change: AssigneeChange, to current: [String]) -> [String]
    /// Spelling of `login` as listed in `candidates`, or `nil` when it is not listed.
    public static func canonical(_ login: String, in candidates: [String]) -> String?
}
```

- `TaskField`: Fall `.assignees`.
- `TaskItem.assignees: [String]?` und `TaskDraft.assignees: [String]?`, jeweils letzter Init-Parameter mit Standard `nil`.
- `TaskEdit.assignees: FieldChange<AssigneeChange> = .unchanged`; zählt in `isEmpty`; `diff` setzt es aus `AssigneeRules.change(original:edited:)`.
- `TaskProvider.isListed(_ item: TaskItem) -> Bool` als Protokollanforderung, Standard `true` in der Extension.

- [x] **Step 1: Tests schreiben** (`AssigneeRulesTests`, Swift Testing):
  - `missing_reportsDroppedLoginsInRequestOrder`: `missing(requested: ["lea-m", "Jonas-K", "sam"], actual: ["jonas-k"]) == ["lea-m", "sam"]`
  - `missing_withoutRequest_isEmpty`: `missing(requested: nil, actual: []) == []`
  - `change_isNilForSameSetIgnoringCaseAndOrder`: `change(original: ["Octo", "lea-m"], edited: ["lea-m", "octo"]) == nil`
  - `change_listsAddAndRemove`: `change(original: ["octo", "lea-m"], edited: ["lea-m", "sam"]) == AssigneeChange(add: ["sam"], remove: ["octo"])`
  - `change_nilToEmpty_isNil`: `change(original: nil, edited: []) == nil`
  - `applying_keepsLoginsAddedMeanwhile`: `applying(AssigneeChange(add: ["sam"], remove: ["octo"]), to: ["octo", "lea-m", "new"]) == ["lea-m", "new", "sam"]`
  - `canonical_returnsGitHubSpelling`: `canonical("LEA-M", in: ["jonas-k", "lea-m"]) == "lea-m"`, unbekannt → `nil`
  - `contains_ignoresCase`: `contains(["Melvinmng"], "melvinmng")` (Review Focus 1)
  
  In `TaskEditTests`:
  - `diff_assignees_setsDifference`: `edit.assignees == .set(AssigneeChange(add: ["lea-m"], remove: []))` und `!edit.isEmpty`
  - `diff_sameAssigneesInOtherOrder_isEmpty`
- [x] **Step 2:** `PKG TagwerkCore AssigneeRulesTests` → FAIL (Typ fehlt).
- [x] **Step 3:** Umsetzen nach Interfaces.
- [x] **Step 4:** `PKG TagwerkCore AssigneeRulesTests` und `PKG TagwerkCore TaskEditTests` → PASS.
- [x] **Step 5:** Commit `feat: add assignees to the task model` (`git add app/Packages/TagwerkCore`).

---

### Task 2: GitHubKit lesen

**Issue-Gruppe:** Nr. 2 GitHubKit lesen.

**Files:**
- Modify: `GitHubKit/GitHubCatalog.swift`, `GitHubAPI.swift` (neben `ownedRepositories`), `GitHubMapping.swift:55–87`, `GitHubTaskProvider.swift:212–224` und neue Methoden
- Test: `GitHubKit/Tests/GitHubKitTests/GitHubAssigneeTests.swift` (neu), `GitHubMappingTests.swift`, `Fixtures.swift:93`; `app/TagwerkTests/GitHubPersistenceTests.swift`

**Interfaces:**
- Consumes: `TaskItem.assignees`, `TaskField.assignees`, `AssigneeRules.contains` (Task 1).
- Produces:

```swift
public struct AssignableUsers: Codable, Sendable, Equatable {
    public let logins: [String]
    public let fetchedAt: Date
}
// GitHubCatalog
public let assignable: [String: AssignableUsers]          // keyed by "owner/name"
public init(repositories: [String], projects: [ProjectInfo], fetchedAt: Date, assignable: [String: AssignableUsers] = [:])
public func withAssignable(_ users: AssignableUsers, for repository: String) -> GitHubCatalog
// GitHubAPI
public func assignableUsers(repository: String) async throws -> [String]   // GET repos/{repository}/assignees?per_page=100
// GitHubTaskProvider
public var storedCatalog: GitHubCatalog? { get }                            // catalogStore?.load(), no request
public func assignableUsers(in repository: String, maxAge: TimeInterval) async -> [String]?
public func isListed(_ item: TaskItem) -> Bool
```

Regeln: `GitHubCatalog.init(from:)` liest `assignable` mit `decodeIfPresent` (Standard `[:]`). `assignableUsers(in:maxAge:)`: gespeicherter Stand jünger als `maxAge` → zurück; sonst abrufen, per `withAssignable` in den gespeicherten Katalog schreiben (ohne gespeicherten Katalog nur zurückgeben, A7); bei Fehler gespeicherter Stand beliebigen Alters, sonst `nil`. `catalog(maxAge:)` übernimmt beim Neuladen `stored.assignable` für Repositories, die im neuen Ergebnis stehen. `GitHubMapping.taskItem`: `assignees: record.assignees`, `.assignees` immer in `editable`. `isListed`: `true`, wenn `login == nil` oder `AssigneeRules.contains(item.assignees, login)`. `Fixtures.issue` erhält `assignees: [String] = ["octo"]`.

- [x] **Step 1: Tests schreiben** (`GitHubAssigneeTests`, Aufbau wie `GitHubCreateTests.makeProvider`, mit `MemoryGitHubCatalogStore` falls nicht vorhanden als Test-Hilfstyp):
  - `assignableUsers_requestsFirstPageOfHundred`: Anfrage an `/repos/beispiel/app/assignees?per_page=100`; Antwort `[{"login":"octo"},{"login":"lea-m"}]` → `["octo", "lea-m"]`
  - `assignableUsers_freshCacheSkipsRequest`: zweiter Aufruf mit `maxAge: 300` → `transport.requests(to: "/repos/beispiel/app/assignees").count == 1`
  - `assignableUsers_expiredCacheRefetchesAndStores`: `maxAge: 0` → zwei Anfragen; `store.load()?.assignable["beispiel/app"]?.logins` ist die neue Liste
  - `assignableUsers_failureFallsBackToStoredThenNil`: `.failure(.notConnectedToInternet)` mit altem Stand → alter Stand; ohne Stand → `nil`
  - `catalogReload_keepsAssignableOfRemainingRepositories`: Katalog mit `assignable` für `beispiel/app` und `beispiel/alt`; Neuladen liefert nur `beispiel/app` → Schlüssel `["beispiel/app"]`
  - `catalog_decodesStoredJSONWithoutAssignable`: JSON `{"repositories":["beispiel/app"],"projects":[],"fetchedAt":0}` → `assignable.isEmpty`
  - `isListed_ignoresCase`: nach geladenem `login == "octo"` ist ein Item mit `assignees: ["Octo"]` gelistet, mit `["lea-m"]` nicht (Review Focus 1)
  - `isListed_unknownLogin_isTrue`
  
  In `GitHubMappingTests`: `taskItem_carriesAssigneesAndMakesThemEditable` (`item.assignees == ["octo"]`, `item.editableFields.contains(.assignees)`).
  In `GitHubPersistenceTests`: `catalog_roundTripsAssignable` (SwiftData-Store, `assignable["beispiel/app"]?.logins == ["octo"]`).
- [x] **Step 2:** `PKG GitHubKit GitHubAssigneeTests` → FAIL.
- [x] **Step 3:** Umsetzen nach Interfaces und Regeln.
- [x] **Step 4:** `PKG GitHubKit GitHubAssigneeTests`, `PKG GitHubKit GitHubMappingTests`, `APP SwiftDataCatalogStoreTests` → PASS.
- [x] **Step 5:** Commit `feat: load assignable users per repository into the GitHub catalog`.

---

### Task 3: GitHubKit schreiben

**Issue-Gruppe:** Nr. 3 GitHubKit schreiben. Voraussetzung: Spike-Ergebnis aus Task 0 liegt vor (bei Fail von S2/S3/S4 die dort genannten Zusätze einbauen).

**Files:**
- Modify: `GitHubKit/GitHubWriter.swift:54–64`, `GitHubTaskProvider.swift:112–128, 168–191, 237–274`, `Resources/Localizable.xcstrings`
- Test: `GitHubCreateTests.swift`, `GitHubTaskProviderWriteTests.swift`

**Interfaces:**
- Consumes: `TaskDraft.assignees`, `TaskEdit.assignees`, `AssigneeChange`, `AssigneeRules.maximum`/`applying` (Task 1); `isListed`, `Fixtures.issue(assignees:)` (Task 2).
- Produces (`GitHubWriter`, intern):

```swift
func createIssue(repository: String, title: String, body: String?, assignees: [String]) async throws -> String
func addAssignees(_ record: GitHubIssueRecord, logins: [String]) async throws      // POST repos/{repo}/issues/{n}/assignees
func removeAssignees(_ record: GitHubIssueRecord, logins: [String]) async throws   // DELETE repos/{repo}/issues/{n}/assignees
```

Regeln `create`: Zielmenge `draft.assignees ?? [viewer]`; mehr als 10 → `TaskWriteError.failed("Höchstens 10 Personen je Issue.")` **vor** `viewerProjects()`, sofern `draft.assignees` gesetzt ist; `fresh` nur bei `GitHubMapping.isVisible(fresh, login: viewer)` in `records`; Rückgabe immer `taskItem(fresh)`.
Regeln `apply` bei `.set(change)`: ist `login == nil`, vor dem Schreiben `viewerProjects()` laden; Prüfung `AssigneeRules.applying(change, to: current.assignees).count <= 10`, sonst Fehler ohne Schreiben; in `write` nach dem Status-Block erst `addAssignees(change.add)` (nur wenn nicht leer), zuletzt `removeAssignees(change.remove)`; nach dem Lesen `records[id] = nil`, wenn der eigene Login nicht mehr in `fresh.assignees` steht (A4), sonst wie heute.

- [x] **Step 1: Tests schreiben.**
  In `GitHubCreateTests`:
  - `create_withoutAssignees_assignsViewer` (bestehenden Test `create_postsIssueAssignedToViewer` behalten: `json["assignees"] == ["octo"]`)
  - `create_sendsChosenAssignees`: `draft.assignees = ["octo", "lea-m"]` → Body `["octo", "lea-m"]`
  - `create_emptyAssignees_sendsEmptyList`: `[]` → Body `[]`
  - `create_moreThanTen_failsBeforeAnyRequest`: 11 Logins → `TaskWriteError.failed`, `transport.requests.isEmpty`
  - `create_forOthersOnly_isNotRemembered`: letzte Antwort `Fixtures.issue(assignees: ["lea-m"])` → Rückgabe hat `assignees == ["lea-m"]`, `provider.cachedTasks.isEmpty`
  
  In `GitHubTaskProviderWriteTests`:
  - `assign_postsAddThenDeletesRemove_afterAllOtherWrites`: Edit mit Titel, `isCompleted` unverändert, `assignees: .set(AssigneeChange(add: ["lea-m"], remove: ["octo"]))` → Reihenfolge der Schreibaufrufe `["PATCH /repos/beispiel/app/issues/1", "POST /repos/beispiel/app/issues/1/assignees", "DELETE /repos/beispiel/app/issues/1/assignees"]`; POST-Body `{"assignees":["lea-m"]}`, DELETE-Body `{"assignees":["octo"]}`
  - `assign_addOnly_sendsNoDelete`
  - `assign_withoutVersionCheck_writesOnlyTheDifference`: `expectedVersion: nil`, aktueller Stand `["octo", "new"]`, Edit `add: ["lea-m"]` → kein Aufruf enthält `"new"`; kein `PATCH` mit `assignees`
  - `assign_overTenAfterMerge_failsWithoutWrites`: aktueller Stand mit 10 Logins, `add: ["x"]` → Fehler, keine Schreibaufrufe
  - `assign_removingMyself_dropsIssueFromRecords`: frischer Stand `Fixtures.issue(assignees: ["lea-m"])` → Rückgabe `assignees == ["lea-m"]`, `provider.issueReference(for:) == nil`
  - `apply_removeFails_keepsIssueListedAndThrows`: DELETE antwortet 500 → `TaskWriteError.failed`, `provider.issueReference(for:) != nil` (Review Focus 5)
- [x] **Step 2:** `PKG GitHubKit GitHubCreateTests` → FAIL (Signatur/Verhalten).
- [x] **Step 3:** Umsetzen; Fehlertext in `GitHubKit/Resources/Localizable.xcstrings` (EN „At most 10 people per issue.“).
- [x] **Step 4:** `PKG GitHubKit GitHubCreateTests`, `PKG GitHubKit GitHubTaskProviderWriteTests` → PASS.
- [x] **Step 5:** Commit `feat: write issue assignees as a difference`.

---

### Task 4: Listenmodell und Planung

**Issue-Gruppe:** Nr. 4 Listenmodell.

**Files:**
- Create: `app/Tagwerk/Tasks/HandedOverNotice.swift`
- Modify: `app/Tagwerk/Tasks/TaskListModel.swift:285–347`, `app/Tagwerk/Planning/PlanningModel.swift` (nach `:588`), `app/Tagwerk/App/AppEnvironment.swift:168`, `app/TagwerkTests/Fakes/FakeTaskProvider.swift`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/TaskListModelTests.swift`, `PlanningModelTests.swift`, `NotificationSchedulerTests.swift`

**Interfaces:**
- Consumes: `TaskProvider.isListed`, `AssigneeRules.missing`, `TaskItem.assignees`, `TaskDraft.assignees` (Task 1).
- Produces:

```swift
struct HandedOverNotice: Equatable, Identifiable {
    let id: TaskID
    let number: Int?
    let assignees: [String]
    let url: URL?
    init(item: TaskItem)
}
extension TaskItem { var issueNumber: Int? { get } }      // Int(url?.lastPathComponent)

// TaskListModel
private(set) var lastHandedOver: HandedOverNotice?
@ObservationIgnored var onHandedOver: ((TaskID) async -> Void)?
func dismissHandedOver()
func didSave(_ item: TaskItem, requestedAssignees: [String] = [])
static func unassignedMessage(number: Int?, created: Bool, missing: [String]) -> String

// PlanningModel
func futureBlockCount(for id: TaskID) -> Int              // blocks.futureBlocks(for:after: now()).count
func didHandOver(_ id: TaskID) async                      // planStore.unassign, blocks.deleteFutureBlocks(of:after: now()), reload()
```

Regeln: Eine private Hilfsfunktion `settle(_ item:, provider:, announce: Bool) -> Bool` ersetzt `replace` in `create`, `createReturning`, `didSave`, `applyReturning`: gelistet → `replace`; sonst aus `items` entfernen, `onHandedOver` rufen und nur bei `announce` `lastHandedOver` setzen (`createReturning` und `applyReturning`: `announce: false`, F11). Warnung über `lastError`: beim Anlegen `missing(requested: draft.assignees, actual: created.assignees)` mit „#%lld angelegt, aber %@ konnte nicht zugewiesen werden.“; in `didSave` `missing(requested: requestedAssignees, actual: item.assignees)` mit „%@ konnte nicht zugewiesen werden.“ (`%@` = Logins mit `ListFormatStyle(.and)`). `createReturning` setzt weder `lastError` noch `lastHandedOver`; die Abweichung meldet Task 8 in der Werkzeug-Antwort. `didHandOver` schreibt einen Löschfehler nach `lastError`. `AppEnvironment`: `taskList.onHandedOver = { id in await planning.didHandOver(id) }`.

`FakeTaskProvider` erhält: `var viewerLogin: String?` (`isListed` = `viewerLogin == nil || AssigneeRules.contains(item.assignees, viewerLogin!)`), `var droppedAssignees: Set<String>` (werden beim Schreiben still verworfen), `private(set) var createdDrafts: [TaskDraft]`; `create` setzt bei `source == .github` `assignees = draft.assignees ?? [viewerLogin].compactMap { $0 }` und `url = https://github.com/beispiel/app/issues/151`; `apply` wendet `edit.assignees` mit `AssigneeRules.applying` an.

- [x] **Step 1: Tests schreiben** (`TaskListModelTests`, GitHub-Fake mit `viewerLogin = "octo"`):
  - `create_forMe_addsItemWithoutNotice`: `draft.assignees == nil` → Item in `items`, `lastHandedOver == nil`, `lastError == nil`
  - `create_forOthers_neverEntersItems_andSetsNotice`: `assignees: ["lea-m"]` → `!items.contains { $0.id.source == .github }`, `lastHandedOver?.number == 151`, `lastHandedOver?.assignees == ["lea-m"]`
  - `create_forNoOne_setsNoticeWithoutAssignees`
  - `create_droppedAssignee_warnsByName`: `droppedAssignees = ["lea-m"]`, Draft `["octo", "lea-m"]` → `lastError == "#151 angelegt, aber lea-m konnte nicht zugewiesen werden."`, Item gelistet
  - `create_droppedOnlyAssignee_warnsAndHandsOver`: Draft `["lea-m"]`, verworfen → Warnung **und** `lastHandedOver?.assignees == []`, nicht in `items` (Review Focus 3)
  - `didSave_handedOver_removesItem_callsHookAndSetsNotice`: Hook erhält die ID
  - `didSave_missingRequestedAssignee_warns`: `didSave(item, requestedAssignees: ["sam"])` mit `item.assignees == ["octo"]` → `lastError == "sam konnte nicht zugewiesen werden."`
  - `createReturning_forOthers_setsNoNotice_butRemovesFromItems`
  - `applyReturning_handedOver_removesItem`
  
  `PlanningModelTests`: `didHandOver_removesDayAndFutureBlocks_keepsPastBlocks` (ein Block gestern, einer morgen; danach `planStore.assignment(for:) == nil`, nur der gestrige Block übrig), `futureBlockCount_countsFromNow`.
  `NotificationSchedulerTests`: `handOver_removesPendingNotification` (Issue mit Fälligkeit geplant; nach `didSave` eines nicht gelisteten Stands und `reschedule()` keine Anfrage mehr für die ID).
- [x] **Step 2:** `APP TaskListModelTests` → FAIL.
- [x] **Step 3:** Umsetzen; Texte mit Englisch in `Localizable.xcstrings`.
- [x] **Step 4:** `APP TaskListModelTests`, `APP PlanningModelTests`, `APP NotificationSchedulerTests` → PASS.
- [x] **Step 5:** Commit `feat: keep handed-over issues out of the list and the plan`.

---

### Task 5: Blatt „Neue Aufgabe“

**Issue-Gruppe:** Nr. 5 Blatt „Neue Aufgabe“.

**Files:**
- Create: `app/Tagwerk/Tasks/AssigneeSelection.swift`
- Modify: `app/Tagwerk/Tasks/NewTaskSheet.swift:26–30, 69–93, 148–162`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/AssigneeSelectionTests.swift` (neu)

**Interfaces:**
- Consumes: `GitHubTaskProvider.assignableUsers(in:maxAge:)`, `.login` (Task 2); `AssigneeRules.maximum`, `TaskDraft.assignees` (Task 1).
- Produces:

```swift
enum AssigneeSelection {
    /// "Ich" first, then case-insensitive alphabetical; `me` is always included when known.
    static func ordered(candidates: [String], me: String?) -> [String]
    /// Row value: "Niemand" · "Ich" · "Ich, lea-m" · "3 Personen".
    static func value(selected: [String], me: String?) -> String
    /// Menu label of one login: "Ich (login)" for `me`, else the login.
    static func label(_ login: String, me: String?) -> String
    /// Footer sentence of spec §5.4.
    static func footer(selected: [String], me: String?) -> String
    /// "dir, lea-m und jonas-k"; from three others on "dir und 3 weiteren Personen" (count form only when `summarize`).
    static func names(selected: [String], me: String?, summarize: Bool, locale: Locale = .current) -> String
    /// "#151 an lea-m" · "#151 an lea-m und jonas-k" · "#151 an 3 Personen" · "#151 ohne Zuweisung".
    static func capsuleTitle(number: Int?, assignees: [String]) -> String
    static func canAdd(selectedCount: Int) -> Bool            // < AssigneeRules.maximum
}

/// Load state of the candidates for one repository.
enum AssigneeLoad: Equatable {
    case idle, loading(repository: String), loaded(repository: String, logins: [String]), failed(repository: String)
    /// Adopts a result only when it belongs to the repository that is still selected.
    func adopting(_ logins: [String]?, for repository: String, selected: String?) -> AssigneeLoad
}

struct AssigneeSelectionRow: View {
    let candidates: [String]          // already ordered
    let me: String?
    let load: AssigneeLoad            // drives the disabled hint rows
    @Binding var selection: Set<String>
    var isEnabled = true
}
```

Regeln der Zeile: wie `ProjectSelectionRow` (`Menu`, `Toggle`, `menuActionDismissBehavior(.disabled)`), Abschnittstitel „Mehrere möglich · höchstens 10“, nicht gewählte Schalter deaktiviert bei `!canAdd`, deaktivierte Hinweiszeile „Personen werden geladen …“ bzw. „Personen konnten nicht geladen werden“, VoiceOver-Label „Zugewiesen“, Wert als Liste, Hinweis „Mehrfachauswahl“. Im Blatt: `@State assignees: Set<String>` (Anfang `[login]`), `@State assigneeLoad`; `.task(id: repository)` setzt zuerst die Auswahl auf „Ich“ zurück, lädt und übernimmt über `adopting`; ohne Repository ist die Zeile deaktiviert; Fußtext: Katalogfehler, sonst (ggf. vorangestellt „Mindestens ein Projekt wählen.“) `AssigneeSelection.footer`. `save()`: `assignees:` = Auswahl in Menüreihenfolge, nur bei `target == .github`. „Ich“ steht auch dann zur Wahl, wenn GitHub mich nicht meldet (F5); nur ich zuweisbar → Menü bleibt aktiv (F3).

- [x] **Step 1: Tests schreiben** (`AssigneeSelectionTests`, `me = "octo"`):
  - `ordered_putsMeFirstThenAlphabeticalIgnoringCase`: `ordered(candidates: ["sam-dev", "Jonas-k", "octo", "lea-m"], me: "octo") == ["octo", "Jonas-k", "lea-m", "sam-dev"]`
  - `ordered_addsMeWhenGitHubOmitsMe`: `ordered(candidates: ["lea-m"], me: "octo") == ["octo", "lea-m"]`
  - `value_cases`: `[] → "Niemand"`, `["octo"] → "Ich"`, `["lea-m", "octo"] → "Ich, lea-m"`, drei → `"3 Personen"`
  - `footer_cases`: nur ich → „Das Issue wird dir zugewiesen.“; ich + lea-m → „Das Issue wird dir und lea-m zugewiesen.“; ich + vier weitere → „Das Issue wird dir und 4 weiteren Personen zugewiesen.“; nur lea-m → „Das Issue wird lea-m zugewiesen und erscheint danach nicht in deinen Aufgaben.“; niemand → „Das Issue wird niemandem zugewiesen und erscheint danach nicht in deinen Aufgaben.“
  - `footer_twoOthers_usesOneList`: ich + lea-m + jonas-k → „Das Issue wird dir, jonas-k und lea-m zugewiesen.“ (A5)
  - `capsuleTitle_cases`: `(151, ["lea-m"]) → "#151 an lea-m"`, zwei → `"#151 an lea-m und jonas-k"`, drei → `"#151 an 3 Personen"`, `[] → "#151 ohne Zuweisung"`
  - `canAdd_stopsAtTen`: `canAdd(selectedCount: 9)`, `!canAdd(selectedCount: 10)`
  - `AssigneeLoadTests.staleResultIsDiscarded`: `AssigneeLoad.loading(repository: "a/x").adopting(["lea-m"], for: "a/x", selected: "a/y") == .loading(repository: "a/x")` (Review Focus 2)
  - `AssigneeLoadTests.nilResultFails`: `adopting(nil, for: "a/x", selected: "a/x") == .failed(repository: "a/x")`
- [x] **Step 2:** `APP AssigneeSelectionTests` → FAIL.
- [x] **Step 3:** Umsetzen; Texte mit Englisch eintragen (Spec §5.8; nach A5 „Das Issue wird %@ zugewiesen.“ → „The issue will be assigned to %@.“, „dir“ → „you“).
- [x] **Step 4:** `APP AssigneeSelectionTests`, `APP ProjectSelectionTests` → PASS; im Simulator Blatt öffnen: Zeile unter „Projekte“, Fußtext folgt der Auswahl.
- [x] **Step 5:** Commit `feat: choose assignees when creating an issue`.

---

### Task 6: Kapsel „Vergeben“

**Issue-Gruppe:** Nr. 6 Kapsel.

**Files:**
- Modify: `app/Tagwerk/Tasks/UndoCapsule.swift`, `app/Tagwerk/Tasks/TaskListView.swift:85–86, 308–316`, `app/Tagwerk/Planning/PlanView.swift:98–102`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/AssigneeSelectionTests.swift` (Text der Ansage)

**Interfaces:**
- Consumes: `TaskListModel.lastHandedOver`, `dismissHandedOver()`, `HandedOverNotice` (Task 4); `AssigneeSelection.capsuleTitle` (Task 5).
- Produces: neue Parameter von `UndoCapsule` mit den heutigen Werten als Standard, sodass die sieben bestehenden Aufrufer unverändert bleiben:

```swift
var actionTitle: LocalizedStringResource = "Rückgängig"
var actionSymbol = "arrow.uturn.backward"
var actionHint: LocalizedStringResource = "Markiert die Aufgabe wieder als offen"
/// Spoken on appear; `nil` keeps "<caption>: <title>. Rückgängig verfügbar."
var announcement: String? = nil
```

Der Parameter `onUndo` bleibt die Aktion des Knopfs. Anzeige: in `TaskListView` eine eigene `handedOverBar` im selben `safeAreaInset` (über `undoBar`, `VStack`), in `PlanView` ein weiterer `overlay` mit `.padding(.bottom, 60)`; beide lesen `taskList.lastHandedOver`. Werte: `caption: "Vergeben"`, `symbol: "person.crop.circle.badge.checkmark"`, `duration: 8`, `actionTitle: "Auf GitHub öffnen"`, `actionSymbol: "arrow.up.right"`, Aktion `openURL(url)` und `dismissHandedOver()`, `onExpire` nur wenn dieselbe Notiz noch steht, `.id(notice.id)`. Ansage: „Vergeben: #151 an lea-m. Auf GitHub öffnen verfügbar.“

- [x] **Step 1:** Test `handedOverAnnouncement_namesNumberAndPeople` in `AssigneeSelectionTests`: `AssigneeSelection.announcement(number: 151, assignees: ["lea-m"]) == "Vergeben: #151 an lea-m. Auf GitHub öffnen verfügbar."` (Funktion in `AssigneeSelection` ergänzen).
- [x] **Step 2:** `APP AssigneeSelectionTests` → FAIL.
- [x] **Step 3:** Umsetzen.
- [x] **Step 4:** `APP AssigneeSelectionTests` → PASS; `APP AppSmokeTests` → PASS (bestehende Kapseln unverändert). Im Simulator: Issue nur an eine andere Person anlegen → Kapsel 8 s in „Aufgaben“ und „Planen“, Knopf öffnet GitHub.
- [x] **Step 5:** Commit `feat: show a capsule with a GitHub link after handing over an issue`.

---

### Task 7: Editor

**Issue-Gruppe:** Nr. 7 Editor.

**Files:**
- Modify: `app/Tagwerk/Editor/TaskEditorModel.swift:31–37, 121–132, 158–178`, `TaskEditorView.swift:9, 21–34, 65–67, 172–200, 250–257`, `ConflictChange.swift:17–27`, `app/Tagwerk/Tasks/TaskListView.swift:115–123`, `app/Tagwerk/App/RootView.swift:87–92`, `app/Tagwerk/Planning/SuggestionViews.swift:719–724`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/TaskEditorModelTests.swift`, `EstimateAndConflictTests.swift`

**Interfaces:**
- Consumes: `AssigneeSelectionRow`, `AssigneeSelection`, `AssigneeLoad` (Task 5); `didSave(_:requestedAssignees:)`, `PlanningModel.futureBlockCount(for:)` (Task 4); `GitHubTaskProvider.assignableUsers`, `.login`, `isListed` (Task 2); `TaskEdit.assignees` (Task 1).
- Produces:

```swift
// TaskEditorModel
init(item: TaskItem, provider: any TaskProvider, addComment: CommentAction? = nil, viewerLogin: String? = nil)
var viewerLogin: String?
/// I was assigned when the editor opened and am not in the draft any more.
var handsOver: Bool { get }
/// Logins this save adds; handed to the list for the comparison after writing.
var requestedAssignees: [String] { get }
/// False when the saved item no longer belongs to my lists.
var savedIsListed: Bool { get }
/// Candidates of the row: assignable ∪ currently assigned, ordered.
func assigneeCandidates(assignable: [String]?) -> [String]
enum SaveQuestion { …; case handOver(futureBlocks: Int) }
static func saveQuestion(effortChanged: Bool, blocksOffSeries: [CalendarEvent], handOverFutureBlocks: Int? = nil) -> SaveQuestion?
static func handOverMessage(number: Int?, futureBlocks: Int, leavesUnassigned: Bool) -> String

// TaskEditorView
let onSaved: (TaskItem, [String]) -> Void
```

Regeln: Zeile „Zugewiesen“ unter „Repo“, nur bei `source == .github`, immer (F15); Bindung auf `model.draft.assignees` (Reihenfolge wie `assigneeCandidates`); Laden in `.task` über `(provider as? GitHubTaskProvider)?.assignableUsers(in: original.container.id, maxAge: AppEnvironment.catalogMaxAge)`; bis dahin und bei Fehler nur die aktuell Zugewiesenen; bei `isReadOnly` `LabeledContent("Zugewiesen", value:)`. `viewerLogin` kommt aus `(provider as? GitHubTaskProvider)?.login`; unbekannt → Zeile ohne „Ich“, `handsOver == false`. „Sichern“: `handOverFutureBlocks = model.handsOver ? (planning?.futureBlockCount(for: id) ?? 0) : nil`; `.handOver` hat Vorrang (kollidiert laut Spec nicht mit den Erinnerungs-Fällen). Dialog: Titel „Du bist danach nicht mehr zugewiesen.“, Text aus `handOverMessage`, Knöpfe „Abgeben“ (`role: .destructive`) und „Abbrechen“. „Trotzdem sichern“ fragt nicht erneut. `finish`: `onSaved(saved, model.requestedAssignees)`; `applyPlanning` nur bei `model.savedIsListed`. `ConflictChange.changes`: Zeile „Zugewiesen“ nach „Labels“, Logins kommagetrennt, „–“ bei leer oder `nil`. Die drei Aufrufer reichen `requested` an `didSave(_:requestedAssignees:)` weiter.

- [x] **Step 1: Tests schreiben.**
  `TaskEditorModelTests` (GitHub-Item mit `assignees: ["octo", "lea-m"]`, `viewerLogin: "octo"`):
  - `assignees_addPerson_sendsOnlyTheDifference`: Draft `["octo", "lea-m", "sam"]` → `appliedEdits.last?.edit.assignees == .set(AssigneeChange(add: ["sam"], remove: []))`, `requestedAssignees == ["sam"]`
  - `assignees_unchanged_hasNoChanges`
  - `handsOver_onlyWhenIWasAssignedAndLeave`: Draft `["lea-m"]` → `true`; Original ohne mich → `false`; `viewerLogin == nil` → `false`
  - `saveQuestion_handOverWins`: `saveQuestion(effortChanged: false, blocksOffSeries: [], handOverFutureBlocks: 2) == .handOver(futureBlocks: 2)`; mit `nil` unverändert wie bisher
  - `handOverMessage_cases`: `(151, 0, false) == "#151 verschwindet aus Aufgaben und Planung."`; `(151, 2, false)` endet auf „2 geplante Zeitblöcke werden gelöscht.“; `(151, 1, false)` endet auf „1 geplanter Zeitblock wird gelöscht.“; `(151, 0, true)` endet auf „Das Issue ist dann niemandem zugewiesen.“
  - `assigneeCandidates_keepAssignedPeopleWhoAreNoLongerAssignable`: `assigneeCandidates(assignable: ["octo", "sam"]) == ["octo", "lea-m", "sam"]`; `assignable: nil` → `["octo", "lea-m"]`
  - `saveAnyway_afterConflict_writesDifferenceAgainstOpeningState`: Konflikt mit aktuellem Stand `["octo", "lea-m", "new"]`, eigene Änderung `add: ["sam"]` → zweiter Aufruf mit `expectedVersion == nil` und derselben Differenz
  - `handOver_skipsPlanningEdit`: Fake mit `viewerLogin = "octo"`, Sichern mit Draft `["lea-m"]` → `savedIsListed == false` (Review Focus 4)
  
  `EstimateAndConflictTests`: `conflictChanges_listAssignees`: Original `["octo"]`, aktuell `["octo", "new"]`, Draft `["octo", "sam"]` → `ConflictChange(field: "Zugewiesen", before: "octo", after: "octo, new", mine: "octo, sam")`.
- [x] **Step 2:** `APP TaskEditorModelTests` → FAIL.
- [x] **Step 3:** Umsetzen; Texte mit Englisch und Plural-Varianten für „%lld geplante Zeitblöcke werden gelöscht.“.
- [x] **Step 4:** `APP TaskEditorModelTests`, `APP EstimateAndConflictTests` → PASS.
- [x] **Step 5:** Commit `feat: edit issue assignees with a hand-over question`.

---

### Task 8: Assistent – Lesewerkzeuge und `create_task`

**Issue-Gruppe:** Nr. 8 Assistent (Teil 1 von 2).

**Files:**
- Create: `app/Tagwerk/AI/GitHubDirectory.swift`, `app/Tagwerk/AI/AppTools+GitHub.swift`, `app/TagwerkTests/Fakes/FakeGitHubDirectory.swift`
- Modify: `app/Tagwerk/AI/AppTools.swift:13, 23–31, 50–59, 241–253`, `AppTools+Definitions.swift:35–72`, `app/Tagwerk/App/AppEnvironment.swift:120–123`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/AppToolsTests.swift`

**Interfaces:**
- Consumes: `GitHubCatalog.projectIDs(linkedTo:)`, `storedCatalog`, `catalog(maxAge:)`, `assignableUsers(in:maxAge:)`, `login` (Task 2); `TaskListModel.createReturning`, `provider.isListed` (Task 4); `AssigneeRules.canonical`/`missing`/`maximum` (Task 1).
- Produces:

```swift
/// What the assistant needs from GitHub; lets tests replace the provider.
@MainActor protocol GitHubDirectory: AnyObject {
    var login: String? { get }
    var storedCatalog: GitHubCatalog? { get }
    func catalog(maxAge: TimeInterval) async -> GitHubCatalog?
    func assignableUsers(in repository: String, maxAge: TimeInterval) async -> [String]?
}
extension GitHubTaskProvider: GitHubDirectory {}

// AppTools
init(taskList:planning:planner:events:gitHub: @escaping () -> (any GitHubDirectory)? = { nil })
static let readTools: Set<String>            // adds "list_github_targets", "list_assignees"
static let maxListedRepositories = 30
static var gitHubDefinitions: [ToolDefinition]
var definitions: [ToolDefinition]             // allDefinitions + gitHubDefinitions when gitHub() != nil

/// Repository and projects a create_task call resolves to; shared by execution (Task 8) and card (Task 9).
struct GitHubTarget: Equatable { let repository: String; let projectIDs: [String] }
enum GitHubTargetError: Error, Equatable { case repositoryMissing, repositoryUnknown, projectMissing, projectUnknown }
static func gitHubTarget(repository: String?, projectIDs: [String]?, catalog: GitHubCatalog) -> Result<GitHubTarget, GitHubTargetError>
```

Regeln (Spec §5.7): `create_task` erhält `repository` (string, nullable), `project_ids` (array of string, nullable), `assignees` (array of string, nullable). Für `source != "github"` müssen alle drei `null` sein, sonst Fehler. `gitHubTarget`: `repository == nil` → einziges Repository, sonst `.repositoryMissing` („Bitte ein Repository nennen.“); `projectIDs == nil` → `projectIDs(linkedTo:)`, sind keine verknüpft das einzige Project, sonst `.projectMissing` („Bitte ein Project nennen.“); unbekannte Angaben → `.repositoryUnknown`/`.projectUnknown`. Ausführung nutzt `catalog(maxAge: AppEnvironment.catalogMaxAge)`. Enthält `assignees` jemanden außer mir: Zuweisbare laden; nicht ladbar oder Login unbekannt → Fehler „%@ ist in %@ nicht zuweisbar.“ und **kein** Anlegen; geschrieben wird `AssigneeRules.canonical`. Mehr als 10 → „Höchstens 10 Personen je Issue.“. Antwort: `ok`, `number`, `url`, `assignees`, `listed`; `not_assigned` nur bei Abweichung; `id` und `task` nur bei `listed: true`. `list_github_targets`: Repositories in Katalogreihenfolge, höchstens 30, je `linked_project_ids`; `list_assignees`: `repository`, `me`, `assignees` (ohne mich, alphabetisch); Fehler bei unbekanntem Repository oder nicht ladbarer Liste. Werkzeug-Beschreibungen englisch; `create_task`: „For GitHub issues call list_github_targets first and pass repository and project_ids; assignees only with logins from list_assignees, [] for no one, null for the user.“

`FakeGitHubDirectory`: `login`, `storedCatalog`, `assignable: [String: [String]]`, `private(set) var assignableRequests: [String]`.

- [x] **Step 1: Tests schreiben** (`AppToolsTests`; GitHub-Fake mit `viewerLogin = "octo"`, Katalog mit `beispiel/app` ↔ `PVT_1 „App“`, Zuweisbare `["octo", "lea-m", "jonas-k"]`):
  - `definitions_includeGitHubToolsOnlyWhenSignedIn`: ohne Directory fehlen beide Namen; mit Directory vorhanden und `kind(of:) == .read`
  - `createTaskSchema_requiresTheThreeNullableGitHubFields`: `required` enthält `repository`, `project_ids`, `assignees`; Typ jeweils mit `"null"`
  - `listGitHubTargets_returnsRepositoriesWithLinkedProjects`: JSON `repositories[0] == {"name":"beispiel/app","linked_project_ids":["PVT_1"]}`, `projects[0] == {"id":"PVT_1","title":"App"}`
  - `listGitHubTargets_capsAtThirtyRepositories`
  - `listAssignees_returnsMeAndOthers`: `{"repository":"beispiel/app","me":"octo","assignees":["jonas-k","lea-m"]}`
  - `listAssignees_unknownRepository_returnsError`
  - `createIssue_withoutAssignees_goesToMe`: Antwort `listed == true`, `createdDrafts.last?.containerID == "beispiel/app"`, `subContainerIDs == ["PVT_1"]`, `assignees == nil`, `assignableRequests.isEmpty` (Abnahme 9)
  - `createIssue_nullTargets_resolveToTheOnlyRepositoryAndLinkedProjects`
  - `createIssue_twoRepositoriesWithoutName_returnsError`: Fehlertext „Bitte ein Repository nennen.“, nichts angelegt
  - `createIssue_forOther_usesGitHubSpelling_andReportsNotListed`: Argument `["LEA-M"]` → `createdDrafts.last?.assignees == ["lea-m"]`; Antwort `{"ok":true,"number":151,"url":…,"assignees":["lea-m"],"listed":false}` ohne `id`/`task`; `taskList.lastHandedOver == nil`
  - `createIssue_unknownLogin_createsNothing`: `["ghost"]` → `error` nennt „ghost“ und „beispiel/app“; `createdDrafts.isEmpty`
  - `createIssue_assignableNotLoadable_createsNothing`
  - `createIssue_droppedAssignee_reportsNotAssigned`: `"not_assigned":["lea-m"]`
  - `createIssue_moreThanTen_returnsError`
  - `createLocalTask_withGitHubFields_returnsError`: `source: "local"`, `assignees: ["lea-m"]`
  - `gitHubTarget_noLinkedProjects_fallsBackToOnlyProject_orAsks`
- [x] **Step 2:** `APP AppToolsTests` → FAIL.
- [x] **Step 3:** Umsetzen; `AppEnvironment` übergibt `gitHub: { [taskList] in taskList.provider(for: .github) as? GitHubTaskProvider }`. Bestehende Tests, die `create_task` aufrufen, um die drei `null`-Felder ergänzen.
- [x] **Step 4:** `APP AppToolsTests` → PASS.
- [x] **Step 5:** Commit `feat: let the assistant create GitHub issues with repository, projects and assignees`.

---

### Task 9: Assistent – Karte, Instruktionen, Sprachmodus

**Issue-Gruppe:** Nr. 8 Assistent (Teil 2 von 2).

**Files:**
- Modify: `app/Tagwerk/AI/AssistantModel.swift:57, 167–190, 349–366, 411–431`, `app/Tagwerk/App/AppEnvironment.swift` (nach `:146`), `TagwerkCore/Voice/VoiceReply.swift:40–52`, `VoiceModeMachine.swift:390–397`, `ActionAnnouncement.swift:63–77`, `app/Tagwerk/Localizable.xcstrings`
- Test: `app/TagwerkTests/AssistantModelTests.swift`, `TagwerkCore/Tests/TagwerkCoreTests/VoiceModeMachineTests.swift`

**Interfaces:**
- Consumes: `GitHubDirectory`, `AppTools.gitHubTarget`, `GitHubTargetError` (Task 8); `AssigneeSelection.names` (Task 5).
- Produces:

```swift
// OpenCards
public var guarded: Int                                   // cards that must be confirmed one by one
public init(ids: [String], deletes: Int, guarded: Int = 0)
// ActionAnnouncement: case guardedNeedTap
//   german: "Zuweisungen an andere bitte einzeln bestätigen." · english: "Please confirm assignments to others one by one."
// AssistantModel
@ObservationIgnored var gitHubDirectory: () -> (any GitHubDirectory)? = { nil }
/// True for a create_task call that assigns to other people or to no one.
static func assignsBeyondMe(_ call: ToolCall, me: String?) -> Bool
```

Regeln: `assignsBeyondMe`: `name == "create_task"`, `source == "github"`, `assignees` nicht `null` und (leer oder ein Login ≠ `me` ohne Groß-/Kleinschreibung; `me == nil` → `true`). `openCards.guarded` zählt diese Karten. `confirmCards`: mehrere Karten nur, wenn keine `delete_event` **und** keine geschützte dabei ist. `VoiceModeMachine`: `.confirmAll where cards.guarded > 0` → `say(.guardedNeedTap)`; eine einzelne geschützte Karte bestätigt ein einfaches „Ja“ (A2). „Alle bestätigen“ per Tippen bleibt.
Karte (`describe`, `create_task` mit `source == "github"`): Titel = Issue-Titel; erste Zeile „Issue anlegen · <repository> · Project <Titel, …>“, dazu Fälligkeit und Priorität wie heute; eigene Zeile „Zugewiesen: dir“ · „Zugewiesen: dir und lea-m“ · „Zugewiesen: lea-m (nicht dir)“ · „Niemandem zugewiesen“ (immer alle Logins, A5); danach Notizen. Ziel synchron aus `gitHubDirectory()?.storedCatalog` über `AppTools.gitHubTarget`; nicht auflösbar → „Repository fehlt“ bzw. „Project fehlt“ an der Stelle. Andere Quellen wie bisher.
Instruktionen: ein Absatz nach dem Termin-Absatz, nur wenn `gitHubDirectory() != nil`: „Für ein GitHub-Issue rufst du zuerst list_github_targets auf und übergibst repository und project_ids ausdrücklich. list_assignees rufst du nur auf, wenn der Nutzer das Issue jemandem zuweisen will. Passt ein genannter Name zu keinem oder zu mehreren Logins, frag nach, statt zu raten.“ Im Aufgaben-Chat eines Issues zusätzlich „Naheliegendes Ziel für neue Issues: <repository>.“ aus `issueReference`.

- [x] **Step 1: Tests schreiben.**
  `AssistantModelTests`:
  - `describe_gitHubIssue_namesRepositoryProjectAndAssignees`: Argumente `repository: "beispiel/app"`, `project_ids: ["PVT_1"]`, `assignees: ["lea-m"]` → `change` enthält „Issue anlegen · beispiel/app · Project App“ und die Zeile „Zugewiesen: lea-m (nicht dir)“
  - `describe_gitHubIssue_assigneeVariants`: `null` → „Zugewiesen: dir“; `["octo", "lea-m"]` → „Zugewiesen: dir und lea-m“; `[]` → „Niemandem zugewiesen“
  - `describe_gitHubIssue_nullTargets_resolveFromStoredCatalog`
  - `describe_gitHubIssue_unresolvableTargets_sayMissing`: zwei Repositories, `repository: null` → „Repository fehlt“
  - `describe_gitHubIssue_inEnglish`: `language: .english` → „Assigned to: lea-m (not you)“
  - `openCards_countGuardedAssignmentCards`: eine Karte an `lea-m`, eine an mich → `guarded == 1`
  - `confirmCards_refusesGuardedCardTogetherWithOthers`: zwei IDs, eine geschützt → `.rejected`, nichts angelegt; einzeln → angelegt
  - `instructions_mentionGitHubToolsOnlyWithGitHub`: enthält `list_github_targets` und `list_assignees` nur mit Directory
  
  `VoiceModeMachineTests`: `confirmAll_withGuardedCard_asksForSingleConfirmation` (Effekt spricht `.guardedNeedTap`), `confirm_singleGuardedCard_confirms`.
- [x] **Step 2:** `APP AssistantModelTests` → FAIL.
- [x] **Step 3:** Umsetzen; `AppEnvironment` setzt `assistant.gitHubDirectory` wie in Task 8.
- [x] **Step 4:** `APP AssistantModelTests`, `PKG TagwerkCore VoiceModeMachineTests`, `APP VoiceModeControllerTests` → PASS.
- [x] **Step 5:** Commit `feat: show repository, projects and assignees on the assistant's issue card`.

---

### Task 10: Texte und Datenschutzhinweis

**Issue-Gruppe:** Nr. 9 Texte.

**Files:**
- Modify: `app/Tagwerk/AI/ChatGPTSignInModel.swift:10–12`, `app/Tagwerk/Localizable.xcstrings`, `app/Packages/GitHubKit/Sources/GitHubKit/Resources/Localizable.xcstrings`
- Test: `app/TagwerkTests/LocalizedTests.swift`

**Interfaces – Consumes:** alle Zeichenketten aus Tasks 3–9.

- [x] **Step 1:** Tests in `LocalizedTests`:
  - `privacyNotice_namesGitHubUsernames`: deutsch enthält „GitHub-Benutzernamen zuweisbarer Personen“; englisch „GitHub usernames of assignable people“
  - `handOverBlocks_pluralForms`: deutsch `1 → "1 geplanter Zeitblock wird gelöscht."`, `2 → "2 geplante Zeitblöcke werden gelöscht."`; englisch `1 → "1 planned time block will be deleted."`, `2 → "2 planned time blocks will be deleted."`
  - `people_pluralForms`: englisch `"3 people"`, deutsch `"3 Personen"`
- [x] **Step 2:** `APP LocalizedTests` → FAIL.
- [x] **Step 3:** `privacyNotice` auf „… (Termine, Aufgaben, bei Issues auch Repo-Inhalte und GitHub-Benutzernamen zuweisbarer Personen) an OpenAI.“ ändern; `scripts/sync-strings.sh` ausführen; englische Werte und Plural-Varianten gegen die Tabelle in Spec §5.8 abgleichen (Abweichungen nur nach A5).
- [x] **Step 4:** `APP LocalizedTests` → PASS; `ALL` → `ALL TESTS PASSED` (einschließlich Stufe „string catalogs“).
- [x] **Step 5:** Commit `docs: mention GitHub usernames in the AI privacy notice and complete English texts`.

---

### Task 11: Geräteprüfung (manuell)

**Issue-Gruppe:** Nr. 10 Geräteprüfung. **Files:** Ergebnis als Abschnitt „Geräteprüfung (Datum)“ am Ende dieses Plans.

- [ ] Abnahmekriterien 1–10 aus Spec §9 der Reihe nach am Gerät durchgehen, je Kriterium „erfüllt/nicht erfüllt“ mit Issue-Nummer notieren.
- [ ] **S5:** Repository mit etwa 30 Zuweisbaren (oder Debug-Liste), 10 wählen: Menü bleibt scrollbar, übrige Schalter deaktiviert. Fail → Folge-Issue für ZC2 anlegen lassen (Nutzer entscheidet), kein Umbau in #136.
- [ ] **S6:** Sprachmodus: Karte „an lea-m“ plus eine zweite Karte; „alle“ wird mit der Ansage aus Task 9 abgelehnt, einzelnes „Ja“ bestätigt.
- [ ] Benachrichtigung und Widget: Issue mit Fälligkeit abgeben; ausstehende Benachrichtigung und Widget-Zeile verschwinden.
- [ ] Dunkel, hell, größte Schriftstufe, Englisch, VoiceOver für Blatt, Editor-Zeile, Rückfrage und Kapsel.
- [ ] Bei Abweichungen: `fix:`-Commit je Befund; sonst kein Commit.

## Schnittstellen zu den anderen Plänen

**Produziert (von späteren Plänen nutzbar):** `TaskItem.assignees`, `TaskDraft.assignees`, `TaskField.assignees`, `TaskEdit.assignees`, `AssigneeChange`, `AssigneeRules`, `TaskProvider.isListed(_:)`, `TaskListModel.lastHandedOver`/`onHandedOver`/`didSave(_:requestedAssignees:)`, `HandedOverNotice`, `UndoCapsule`-Parameter `actionTitle`/`actionSymbol`/`actionHint`/`announcement`, `AppTools.gitHubDefinitions`, die erweiterte Definition von `create_task` (Felder `repository`, `project_ids`, `assignees`), `GitHubDirectory`, `OpenCards.guarded`.

**Konsumiert aus anderen Plänen:** nichts; #136 wird zuerst gebaut.

| Plan | Berührung |
|---|---|
| Phase 5 (`2026-11-19-phase-5-shopping-notes.md`) | Gleiche Dateien `NewTaskSheet.swift`, `TaskListView.swift`, `TaskListModel.swift`, `AppTools+Definitions.swift`; baut auf dem Stand nach diesem Plan auf. Jeder Aufrufer von `create_task` muss die drei neuen Felder (ggf. `null`) senden. |
| Suche (`2026-11-19-search.md`) | Liest `TaskItem`; `assignees` ist dort kein Suchfeld (Such-Spec F12). Abgegebene Issues stehen nicht in `items`. |
| Phase 7 (`2026-11-19-phase-7-routines.md`) | Übernimmt die Funktionsliste samt neuer `create_task`-Definition; keine gemeinsame Logik. |

## Risiken

| Risiko | Folge | Gegenmaßnahme |
|---|---|---|
| S1 negativ (Scope reicht nicht) | Neuanmeldung nötig, +2 h | Task 0 zuerst; Abstimmung mit dem Nutzer vor Task 2 |
| S2 negativ (`updatedAt` ändert sich nicht) | fremde Zuweisungsänderung bleibt unerkannt | Zugewiesene in `GitHubMapping.version` (Task 0 → Task 3) |
| `DELETE` nach `POST` scheitert | Person hinzugefügt, ich noch zugewiesen | Fehler wird gezeigt, Issue bleibt sichtbar (Review Focus 5) |
| `create_task` strikt: bestehende Aufrufe ohne die drei Felder | Werkzeugaufruf schlägt fehl | Tests in Task 8 ergänzen alle Aufrufe; Hinweis an Phase 5/7 |
| Modell ruft `list_assignees` ohne Anlass auf | Logins gehen unnötig an OpenAI | Instruktion, Datenschutzhinweis (Spec §6, bewusst in Kauf genommen) |
| Menü mit vielen Einträgen | schwer bedienbar | S5 in Task 11; Folge-Issue ZC2 |

## Self-Review (19.11.2026)

- Spec-Abdeckung: §5.1 → Tasks 1–2; §5.2 → 3–4; §5.3 → 4; §5.4 → 5; §5.5 → 6; §5.6 → 7; §5.7 → 8–9; §5.8 → jeweils im Task und 10; §5.9/§6 → 4, 10, 11; §9 → 11; §10 → 0, 11. Keine Lücke gefunden.
- Typkonsistenz geprüft: `AssigneeChange`, `AssigneeRules.*`, `isListed`, `HandedOverNotice`, `didSave(_:requestedAssignees:)`, `futureBlockCount(for:)`, `GitHubDirectory`, `gitHubTarget`, `OpenCards.guarded` tragen in allen Tasks dieselben Namen.
- Offen für den Nutzer: nichts, sofern der Spike (Task 0) positiv ausfällt.
