# Phase 2a-GitHub: GitHub Projects in Tagwerk – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Man meldet sich in Tagwerk mit GitHub an und sieht die eigenen offenen, zugewiesenen Issues aus allen offenen GitHub Projects in der Aufgabenliste. Man kann sie bearbeiten, abhaken, verschieben und neu anlegen, mit Konfliktschutz und Offline-Cache.

**Architecture:** Neues Package `GitHubKit` mit Device-Flow-Login, Token-Erneuerung, GraphQL- und REST-Client und einem `GitHubTaskProvider`, der dasselbe `TaskProvider`-Protokoll wie Erinnerungen und lokale Aufgaben erfüllt. Netzwerk läuft über ein injiziertes `HTTPTransport`, deshalb ist alles ohne Netz testbar. Der Lese-Cache liegt in SwiftData im App-Target.

**Tech Stack:** wie Plan 2a, dazu GitHub GraphQL API (Projects v2) und REST API (`X-GitHub-Api-Version: 2022-11-28`).

**Spec:** `docs/superpowers/specs/2026-11-17-phase-2-design.md` §4, §5, §9, §12.1–12.6. Befunde: `docs/superpowers/spikes/2026-11-17-feasibility-results.md`, Abschnitt „Nachtrag Phase 2a“. Setzt Plan `2026-11-17-phase-2a-app.md` voraus.

## Ergebnis der ersten GitHub-Aufgabe (erledigt am 2026-11-17)

Device Flow mit `scope=repo project offline_access` gewährt `project, repo`. `viewer.projectsV2` funktioniert. Der Token läuft nach 8 h ab und kommt mit einem Refresh-Token (≈ 181 Tage), der sich **ohne Client-Secret** einlösen lässt und bei jeder Erneuerung rotiert. Damit gilt Design §5.6 „wirkt“, der Ausweichweg §5.7 (klassischer Token) wird **nicht** gebaut.

## Global Constraints

- Alle Global Constraints aus Plan 2a gelten.
- Client-ID `Ov23liLkF2p4Nh2ztZg0` steht in `app/Config/GitHub.xcconfig` (`GITHUB_CLIENT_ID`) und gelangt über die Info.plist-Eigenschaft `GitHubClientID` in die App. Kein Client-Secret, nirgends.
- Endpunkte: `POST https://github.com/login/device/code`, `POST https://github.com/login/oauth/access_token` (jeweils `Accept: application/json`), `POST https://api.github.com/graphql`, REST unter `https://api.github.com`. Header für die API: `Authorization: Bearer <token>`, `Accept: application/vnd.github+json`, `X-GitHub-Api-Version: 2022-11-28`.
- Scope beim Login: genau `repo project offline_access`.
- Token nie loggen, nie in Fehlermeldungen, nie in SwiftData. Zugangsdaten als **ein** JSON-Eintrag im Schlüsselbund, Account `github.credentials`.
- Genau eine laufende Token-Erneuerung. Alle Aufrufer warten auf denselben `Task`.
- Abmelden nur, wenn die Erneuerung selbst mit `bad_refresh_token` oder `incorrect_client_credentials` scheitert, oder auf Wunsch. Netzfehler und 5xx melden nie ab.
- Felder werden **nach Namen** zugeordnet: „Status“, „Priority“, „Due date“, „Estimate (h)“ (× 60 min), „Estimate (MDs)“ (× 8 × 60 min). Fehlt ein Feld, bleibt der Wert leer und das Feld ist nicht editierbar.
- Gezeigt werden nur Items, deren Inhalt ein **Issue** ist (keine Drafts, keine PRs), das offen ist, **dir zugewiesen** ist und dessen Status nicht „Done“ lautet.
- Identität ist das Issue (Node-ID). Ein Issue in mehreren Projects erscheint einmal: früheste Fälligkeit, höchste Priorität.
- „Erledigt“: erst Issue schließen (REST, `state_reason: completed`), dann Status „Done“ in allen Projects des Issues, dann neu lesen. „Wieder öffnen“: Issue öffnen, Status „Ready“.
- Offline: Liste aus dem Cache mit „Stand: hh:mm, offline“. Schreiben ist gesperrt.

## Review Focus

1. **Zwei Aufrufe laufen gleichzeitig in einen abgelaufenen Token:** Es gibt genau einen Refresh-Request, beide Aufrufe bekommen den neuen Token, niemand wird abgemeldet. Test in Task 1.
2. **Kein Netz beim Start oder Erneuern:** Die App bleibt angemeldet, zeigt den Cache und sperrt das Schreiben. Tests in Task 1 und Task 3.
3. **Issue liegt in zwei Projects mit unterschiedlicher Fälligkeit:** Eine Zeile, früheste Fälligkeit, und „Erledigt“ setzt beide Status auf „Done“. Tests in Task 2 und Task 4.
4. **Status-Workflow des Projects greift nach dem Schließen:** Die App liest danach neu und zeigt den Endzustand, statt „Done“ anzunehmen. Test in Task 4.
5. **Project ohne Priority-Feld oder mit „Estimate (MDs)“:** Priorität bleibt leer und ist ausgeblendet. 1,5 MDs werden zu 720 min, und zurückgeschrieben wird in MDs. Tests in Task 2 und Task 4.

---

### Task 1: Device-Flow-Login und Token-Verwaltung

**Files:**
- Create: `app/Config/GitHub.xcconfig`; in `app/Packages/GitHubKit/`: `Package.swift`, `Sources/GitHubKit/HTTPTransport.swift`, `DeviceFlowClient.swift`, `GitHubCredentials.swift`, `TokenManager.swift`
- Test: `app/Packages/GitHubKit/Tests/GitHubKitTests/DeviceFlowClientTests.swift`, `TokenManagerTests.swift`, `StubTransport.swift`
- Modify: `app/project.yml` (Package, xcconfig, Info.plist-Eigenschaft `GitHubClientID: $(GITHUB_CLIENT_ID)`)

**Interfaces:**
- Produces:
  - `public protocol HTTPTransport: Sendable { func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) }`, `public struct URLSessionTransport: HTTPTransport`
  - `public struct DeviceCode: Sendable, Equatable { let deviceCode: String; let userCode: String; let verificationURL: URL; let expiresIn: Int; let interval: Int }`
  - `public struct GitHubCredentials: Codable, Sendable, Equatable { var accessToken: String; var refreshToken: String?; var accessExpiresAt: Date?; var refreshExpiresAt: Date? }` mit `func needsRefresh(now: Date) -> Bool` (wahr, wenn `accessExpiresAt` existiert und weniger als 300 s entfernt ist)
  - `public enum GitHubAuthError: Error, Equatable { case expired, denied, signedOut, network(String), server(String) }`
  - `public struct DeviceFlowClient: Sendable` mit `init(clientID: String, transport: HTTPTransport, sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }, now: @Sendable () -> Date = Date.init)`, `func requestCode() async throws -> DeviceCode`, `func pollForToken(_ code: DeviceCode) async throws -> GitHubCredentials` (`authorization_pending` → weiter; `slow_down` → Intervall aus der Antwort, sonst +5 s; `expired_token` → `.expired`; `access_denied` → `.denied`), `func refresh(_ refreshToken: String) async throws -> GitHubCredentials`
  - `public protocol CredentialStore: Sendable { func load() throws -> GitHubCredentials?; func save(_: GitHubCredentials) throws; func delete() throws }`
  - `public actor TokenManager` mit `init(store: CredentialStore, client: DeviceFlowClient, now: @Sendable () -> Date = Date.init)`, `func validAccessToken() async throws -> String` (erneuert bei `needsRefresh`, single-flight), `func handleUnauthorized() async throws -> String` (erzwingt eine Erneuerung, ebenfalls single-flight), `func store(_: GitHubCredentials) async throws`, `func signOut() async throws`, `var isSignedIn: Bool { get async }`

- [ ] **Step 1: Failing tests** mit `StubTransport` (antwortet aus einer Warteschlange und zählt Requests pro URL):
  - `requestCode_sendsClientIDAndScope`: Body enthält `client_id=Ov23liLkF2p4Nh2ztZg0` und `scope=repo%20project%20offline_access` (bzw. `+`).
  - `poll_pendingThenToken_returnsCredentialsWithExpiry`: `expires_in` 28800 → `accessExpiresAt == now + 28800`.
  - `poll_slowDown_increasesInterval` (aufgezeichnete Sleeps: 5 s, dann 10 s), `poll_expired_throwsExpired`, `poll_denied_throwsDenied`, `poll_tokenWithoutExpiry_hasNilExpiry`.
  - `refresh_sendsGrantTypeWithoutSecret` (Body ohne `client_secret`).
  - `tokenManager_concurrentCallsWithExpiredToken_refreshOnce`: zwei parallele `validAccessToken()`, ein Refresh-Request, beide bekommen denselben neuen Token, gespeichert ist der neue Refresh-Token.
  - `tokenManager_refreshBadRefreshToken_signsOut` und `…_incorrectClientCredentials_signsOut` (Store gelöscht, Fehler `.signedOut`).
  - `tokenManager_refreshNetworkError_keepsCredentials` (Fehler `.network`, Store unverändert).
  - `credentials_json_neverContainsTokenInDescription`: `String(describing:)` enthält den Token nicht (eigene `CustomStringConvertible`-Implementierung, die ihn maskiert).
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren. Single-flight: `TokenManager` hält `private var refreshTask: Task<GitHubCredentials, Error>?`, startet ihn nur, wenn er `nil` ist, und setzt ihn nach Abschluss zurück.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(github): add device flow login and single-flight token refresh`.

### Task 2: Projects lesen und auf Aufgaben abbilden

**Files:**
- Create in `app/Packages/GitHubKit/Sources/GitHubKit/`: `GitHubAPI.swift`, `ProjectsQuery.swift`, `GitHubIssueRecord.swift`, `GitHubMapping.swift`
- Test: `GitHubMappingTests.swift`, `GitHubAPITests.swift`, `Fixtures/projects-page1.json`, `Fixtures/projects-page2.json`, `Fixtures/issue-node.json` (erfundene Daten)
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/TaskItem.swift` (additiv: `var subContainers: [TaskContainer] = []`, `var labels: [String]? = nil`), `TaskEdit.swift` (additiv: `var labels: FieldChange<[String]> = .unchanged`, `var targetSubContainerIDs: Set<String>? = nil`), `TaskField` (+ `.labels`)

**Interfaces:**
- Consumes: `HTTPTransport`, `TokenManager` (Task 1), `TaskItem` (Plan 2a Task 2).
- Produces:
  - `public struct ProjectField: Codable, Sendable, Equatable { let id: String; let name: String; let options: [String: String] }` (Optionsname → Options-ID; leer bei Datum/Zahl)
  - `public struct ProjectInfo: Codable, Sendable, Equatable { let id: String; let number: Int; let title: String; let fields: [ProjectField] }`
  - `public struct ProjectPlacement: Codable, Sendable, Equatable { let project: ProjectInfo; let itemID: String; let itemUpdatedAt: Date; var status: String?; var priority: Priority?; var due: DueDate?; var estimateMinutes: Int? }`
  - `public struct GitHubIssueRecord: Codable, Sendable, Equatable { let issueID: String; let number: Int; let repository: String; var title: String; var body: String?; var isOpen: Bool; let url: URL; let updatedAt: Date; var labels: [String]; var assignees: [String]; var placements: [ProjectPlacement] }`
  - `public struct GitHubAPI: Sendable` mit `init(transport: HTTPTransport, tokens: TokenManager)`, `func viewerLogin() async throws -> String`, `func openProjectIssues() async throws -> (login: String, projects: [ProjectInfo], issues: [GitHubIssueRecord])` (alle offenen Projects, Items seitenweise per Cursor, `first: 100`), `func issue(nodeID: String) async throws -> GitHubIssueRecord?` (über `node(id:) { ... on Issue { projectItems(first: 20) … } }`), `func graphQL(_ query: String, variables: [String: Any]) async throws -> Data` und `func rest(_ method: String, _ path: String, body: [String: Any]?) async throws -> Data`. Bei 401 einmal `tokens.handleUnauthorized()` und wiederholen.
  - `public enum GitHubMapping` mit `static func estimateMinutes(fieldName: String, value: Double) -> Int?`, `static func fieldValue(fromMinutes: Int, fieldName: String) -> Double`, `static func isVisible(_ record: GitHubIssueRecord, login: String) -> Bool`, `static func taskItem(_ record: GitHubIssueRecord) -> TaskItem` (`id` = `.github` + Issue-Node-ID; `container` = Repo; `subContainers` = Projects; `due` = früheste, `priority` = höchste über alle Placements; `estimateMinutes` = erster Nicht-nil-Wert nach Project-Nummer; `version` = Issue-`updatedAt` und alle `itemUpdatedAt` als ISO-8601, mit `|` verbunden, Placements nach `itemID` sortiert; `editableFields` = `.title`, `.notes`, `.labels` plus `.due`/`.priority`/`.estimate`, wenn mindestens ein Project das Feld hat), `static func defaultSelectedProjectIDs(projects: [ProjectInfo], visibleIssues: [GitHubIssueRecord]) -> Set<String>` (Design §12.1)

- [ ] **Step 1: Failing tests:**
  - `estimate_hours_and_mandays`: („Estimate (h)“, 1.5) → 90; („Estimate (MDs)“, 1.5) → 720; Rückweg 720 min nach MDs → 1.5.
  - `visible_excludesClosedUnassignedAndDone`: geschlossenes Issue, fremd zugewiesenes Issue und Status „Done“ fallen weg.
  - `api_skipsDraftsAndPullRequests` (Fixture enthält beide).
  - `api_followsCursorAcrossPages` (zwei Fixtures, zwei Requests, Items beider Seiten).
  - `taskItem_twoProjects_earliestDueHighestPriority`: P3/20.11. und P2/25.11. → P2 und 20.11.
  - `taskItem_projectWithoutPriority_hidesPriorityField`.
  - `taskItem_dueDate_isDateOnly` („2026-11-20“ → `DueDate(2026, 11, 20)` ohne Uhrzeit).
  - `version_changesWhenAnyItemChanges`.
  - `defaultSelection_excludesProjectsWithoutAssignedOpenIssues`.
  - `api_unauthorized_refreshesOnceAndRetries`.
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren. Die GraphQL-Abfrage lädt pro Item `fieldValues(first: 20)` mit `ProjectV2ItemFieldDateValue`, `…SingleSelectValue`, `…NumberValue` samt `field { ... on ProjectV2FieldCommon { id name } }` und den Inhalt `... on Issue { id number title body state updatedAt url repository { nameWithOwner } assignees(first: 10) { nodes { login } } labels(first: 20) { nodes { name } } }`. Die Felddefinitionen kommen aus `fields(first: 30)` mit `ProjectV2SingleSelectField { options { id name } }`.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(github): read open project issues and map them to tasks`.

### Task 3: GitHubTaskProvider lesen, Cache und Offline-Zustand

**Files:**
- Create: `app/Packages/GitHubKit/Sources/GitHubKit/GitHubTaskProvider.swift`, `GitHubCache.swift` (Protokoll); `app/Tagwerk/Persistence/CachedGitHubIssue.swift`, `app/Tagwerk/Persistence/SwiftDataGitHubCache.swift`, `app/Tagwerk/Persistence/KeychainCredentialStore.swift`
- Test: `app/Packages/GitHubKit/Tests/GitHubKitTests/GitHubTaskProviderReadTests.swift`, `app/TagwerkTests/SwiftDataGitHubCacheTests.swift`
- Modify: `app/Tagwerk/Persistence/AppSettings.swift` (additiv: `var selectedProjectIDs: [String]? = nil`), `ModelContainerFactory.swift` (Schema + `CachedGitHubIssue`), `TagwerkCore`: `TaskWriteError` + `.offline`, `app/Tagwerk/Tasks/TaskListModel.swift`: `SourceState` + `.offline(since: Date)` und `.signedOut`

**Interfaces:**
- Produces:
  - `public protocol GitHubCache: Sendable { func load() async -> (records: [GitHubIssueRecord], fetchedAt: Date)?; func store(_: [GitHubIssueRecord], fetchedAt: Date) async }`
  - `@MainActor public final class GitHubTaskProvider: TaskProvider` mit `init(api: GitHubAPI, tokens: TokenManager, cache: GitHubCache, selectedProjectIDs: @escaping @MainActor () -> Set<String>?, now: @escaping () -> Date)`, `private(set) var offlineSince: Date?`, `private(set) var projects: [ProjectInfo]`, `private(set) var login: String?`. `openTasks()`: online → laden, filtern (`isVisible`, ausgewählte Projects; `nil` = Standardauswahl), Cache schreiben, `offlineSince = nil`; Netzfehler → Cache liefern und `offlineSince = fetchedAt`; nicht angemeldet → `TaskWriteError.accessDenied`.
  - `@Model final class CachedGitHubIssue { @Attribute(.unique) var issueID: String; var payload: Data; var fetchedAt: Date }` (JSON von `GitHubIssueRecord`)
  - `struct KeychainCredentialStore: CredentialStore` auf `SecureStore`, Account `github.credentials`

- [ ] **Step 1: Failing tests:** `openTasks_online_storesCache`, `openTasks_networkError_returnsCacheAndSetsOffline`, `openTasks_signedOut_throwsAccessDenied`, `openTasks_respectsSelectedProjects`, `openTasks_nilSelection_usesDefaultSelection`; App: `cache_roundTripsRecords`, `cache_replacesPreviousSnapshot`; `TaskListModelTests`: `reload_githubOffline_marksOfflineAndShowsItems`.
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren und in `AppEnvironment` registrieren, sobald `TokenManager.isSignedIn`.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(github): add task provider with offline cache`.

### Task 4: GitHub-Aufgaben bearbeiten, abhaken, verschieben

**Files:**
- Create: `app/Packages/GitHubKit/Sources/GitHubKit/GitHubWriter.swift`
- Test: `app/Packages/GitHubKit/Tests/GitHubKitTests/GitHubWriterTests.swift`, `GitHubTaskProviderWriteTests.swift`
- Modify: `GitHubTaskProvider.swift` (`apply`, `addComment`)

**Interfaces:**
- Consumes: `GitHubAPI`, `GitHubIssueRecord`, `GitHubMapping` (Task 2), `TaskEdit` inkl. `labels` und `targetSubContainerIDs`.
- Produces:
  - `struct GitHubWriter: Sendable` mit `init(api: GitHubAPI)`, `func updateIssue(_ record: GitHubIssueRecord, title: String?, body: String??, labels: [String]?, state: IssueStateChange?) async throws` (`PATCH /repos/{repo}/issues/{number}`), `func setField(_ placement: ProjectPlacement, fieldName: String, value: ProjectFieldValue?) async throws` (`updateProjectV2ItemFieldValue` bzw. bei `nil` `clearProjectV2ItemFieldValue`; überspringt Projects ohne dieses Feld), `func addComment(_ record: GitHubIssueRecord, body: String) async throws`
  - `enum IssueStateChange: Sendable { case close, reopen }`, `enum ProjectFieldValue: Sendable, Equatable { case date(DueDate), singleSelect(String), number(Double) }`
  - `GitHubTaskProvider.apply(_:to:expectedVersion:)`: offline → `.offline`; `api.issue(nodeID:)` neu laden, Version vergleichen (`nil` = erzwingen) → `.conflict(current:)`; dann in dieser Reihenfolge: Issue-Felder, Project-Felder für `targetSubContainerIDs ?? alle`, bei `isCompleted == true` zuerst `close`, dann Status „Done“ in **allen** Placements, bei `false` zuerst `reopen`, dann Status „Ready“; zum Schluss erneut `issue(nodeID:)` lesen und das Ergebnis liefern.
  - `GitHubTaskProvider.addComment(to: TaskID, body: String) async throws`

- [ ] **Step 1: Failing tests** (Stub zeichnet Requests in Reihenfolge auf):
  - `complete_closesIssueBeforeSettingDoneInAllProjects` (Reihenfolge: PATCH `state: closed`, `state_reason: completed`, dann zwei Mutations mit der Options-ID von „Done“, dann Lesen).
  - `complete_returnsStateReadAfterWrite` (Fixture nach dem Schreiben zeigt einen anderen Status als „Done“ → Ergebnis zeigt diesen).
  - `reopen_setsStatusReady`.
  - `reschedule_changesOnlyDueDate` (genau eine Mutation, Feld „Due date“, keine REST-Anfrage).
  - `editPriority_targetSingleProject_onlyThatProject`.
  - `editEstimate_mandaysProject_writesMandays` (720 min → `number: 1.5`).
  - `clearDue_usesClearMutation`.
  - `apply_staleVersion_throwsConflictWithoutWrites`.
  - `apply_offline_throwsOffline`.
  - `editTitleOnly_sendsOnlyTitle` (PATCH-Body enthält nur `title`).
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(github): write issue and project fields with conflict check`.

### Task 5: GitHub-Issues anlegen

**Files:**
- Modify: `GitHubWriter.swift`, `GitHubTaskProvider.swift` (`create`), `GitHubAPI.swift` (`ownedRepositories()`), `TagwerkCore/TaskDraft` (additiv: `var subContainerID: String? = nil`)
- Test: `GitHubCreateTests.swift`

**Interfaces:**
- Produces: `GitHubAPI.ownedRepositories() async throws -> [String]` (`GET /user/repos?affiliation=owner&sort=pushed&per_page=100`, `full_name`), `GitHubTaskProvider.create(_:)` mit `draft.containerID` = Repo (`owner/name`) und `draft.subContainerID` = Project-ID: `POST /repos/{repo}/issues` mit `title`, `body`, `assignees: [login]` → `node_id`; `addProjectV2ItemById(projectId, contentId)` → Item-ID; danach Due date, Priority, Estimate wie in Task 4; Status „Ready“; Ergebnis neu lesen.

- [ ] **Step 1: Failing tests:** `create_postsIssueAssignedToViewer`, `create_addsToProjectThenSetsFields` (Reihenfolge prüfen), `create_withoutProject_throwsFailed` (Project ist Pflicht, sonst taucht das Issue nicht in der Liste auf), `create_offline_throwsOffline`.
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(github): create issues in a project`.

### Task 6: Oberfläche für GitHub

**Files:**
- Create: `app/Tagwerk/GitHub/GitHubLoginModel.swift`, `app/Tagwerk/GitHub/GitHubLoginView.swift`, `app/Tagwerk/Settings/GitHubSettingsSection.swift`
- Test: `app/TagwerkTests/GitHubLoginModelTests.swift`, Ergänzungen in `TaskEditorModelTests.swift`
- Modify: `SetupModel.swift` (`SetupStep.github` nach `.calendar`), `SetupView.swift`, `SettingsView.swift`, `TaskEditorView.swift`, `TaskEditorModel.swift`, `TaskListView.swift`, `NewTaskSheet.swift`, `AppEnvironment.swift`

**Interfaces:**
- Consumes: `DeviceFlowClient`, `TokenManager` (Task 1), `GitHubTaskProvider` (Tasks 3–5).
- Produces: `@MainActor @Observable final class GitHubLoginModel` mit `enum Phase { case idle, showingCode(DeviceCode), waiting, signedIn(String), failed(String) }`, `func start() async` (Code holen, `UIPasteboard` mit Benutzercode füllen, `openURL(verificationURL)`, dann pollen), `func cancel()`, `func signOut() async`. `TaskEditorModel` bekommt `var comment: String`, `func postComment() async` und `var targetProjects: Set<String>` (Standard: alle `subContainers`).

- [ ] **Step 1: Failing tests:** `login_success_movesToSignedInAndRegistersProvider`, `login_expired_showsRestartableError` („Code abgelaufen, bitte neu starten“), `login_denied_showsError`, `signOut_deletesCredentialsAndRemovesProvider`, `editor_multiProject_defaultsToAllProjects`, `editor_postComment_callsProvider`.
- [ ] **Step 2:** `app/test-all.sh` → FAIL.
- [ ] **Step 3:** Implementieren:
  - Einrichtung: Schritt „Mit GitHub anmelden“ zeigt den Benutzercode groß an, Knopf „Code kopieren und GitHub öffnen“, überspringbar.
  - Einstellungen, Abschnitt „GitHub“: „Angemeldet als <login>“, Project-Auswahl (Mehrfachauswahl, Standard nach §12.1), „Abmelden“ mit dem Hinweis „Vollständig widerrufen: github.com → Settings → Applications → Authorized OAuth Apps“ und dem Satz „Die Anmeldung erneuert sich automatisch. Ohne Nutzung läuft sie nach etwa 6 Monaten ab.“
  - Liste: Segment „GitHub“, Zeilen mit `#<Nummer>`, Repo und Prioritäts-Chip; Leerzustand „Keine zugewiesenen Issues in offenen Projects“; nicht angemeldet → Knopf „Mit GitHub anmelden“; offline → Banner „Stand: hh:mm, offline“, Wisch-Aktionen und Sichern gesperrt.
  - Bearbeiten (Mockup 3): Repo (nur Anzeige), Labels (kommagetrennt), Beschreibung (Markdown), Kommentar mit „Senden“, „Auf GitHub öffnen“; bei mehreren Projects die Auswahl „Ändern in: alle / <Project>“ für Fälligkeit, Priorität und Aufwand.
  - ＋: dritte Option „GitHub-Issue“ mit Repo- und Project-Auswahl.
- [ ] **Step 4:** `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 5:** Commit `feat(github): add login, settings and editor integration`.

### Task 7: Geräteprüfung und Dokumentation

**Files:**
- Modify: `README.md`, `docs/superpowers/spikes/2026-11-17-feasibility-results.md` (falls die Geräteprüfung Neues zeigt)

- [ ] **Step 1:** `scripts/install-dev.sh`. **Geräteprüfung durch den Nutzer:** Anmelden über den Device Flow; Issues aus mehreren Projects erscheinen; ein Test-Issue in einem Test-Project anlegen, Fälligkeit verschieben, abhaken (Status „Done“ in GitHub prüfen), wieder öffnen; parallel auf github.com ändern → Konflikt-Banner; Flugmodus → Cache mit „offline“, Schreiben gesperrt; nach 8 h erneut öffnen → weiter angemeldet.
- [ ] **Step 2:** Befunde beheben (je Befund ein Test zuerst), `app/test-all.sh` → `ALL TESTS PASSED`.
- [ ] **Step 3:** `README.md`: GitHub-Anmeldung, Widerruf, was die App liest und schreibt.
- [ ] **Step 4:** Commit `docs: describe GitHub integration`.
