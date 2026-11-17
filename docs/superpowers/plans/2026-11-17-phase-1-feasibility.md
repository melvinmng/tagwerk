# Phase 1: Machbarkeitstest – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eine Wegwerf-App weist auf dem echten iPhone (kostenloser Personal Team) nach, dass EventKit (Reminders + Kalender, lesen und schreiben), HealthKit-Lesen, Claude-API und GitHub-REST funktionieren. Ein Mac-Job installiert die App automatisch neu, bevor das 7-Tage-Profil abläuft.

**Architecture:** XcodeGen-Projekt unter `spike/` mit einem SwiftUI-Bildschirm. Darauf stehen vier unabhängige „Probes“, die jeweils einen `ProbeResult` liefern. Die Secrets (API-Key, PAT) gibt man in der App ein, sie liegen im Schlüsselbund. Für die Neuinstallation baut ein Shell-Skript mit `xcodebuild -allowProvisioningUpdates` und installiert per `devicectl`, gestartet von einem `launchd`-Agent.

**Tech Stack:** Swift 6, SwiftUI, EventKit, HealthKit, URLSession, Security.framework (Keychain), XcodeGen 2.46, Xcode 27.2, iOS 27.0 als Deployment-Target, zsh, launchd.

**Spec:** `docs/superpowers/specs/2026-11-17-tagwerk-design.md` (§4, §5, §7, §10; Entscheidung „Automatische Neuinstallation“ = Weg A)

## Global Constraints

- Branch `spike/feasibility`. Der Spike-Code wird nicht in Phase 2 übernommen, nur die Erkenntnisse.
- Signierung: Personal Team (kostenlos). Keine Capabilities außer HealthKit. Kein CloudKit, kein Push.
- Bundle-ID `com.melvinmng.tagwerk.spike`, Deployment-Target `27.0`.
- Claude: `POST https://api.anthropic.com/v1/messages`. Header `x-api-key`, `anthropic-version: 2026-10-21` und `anthropic-beta: server-side-fallback-2026-07-01`. Body: `model: "claude-opus-5-5"`, `max_tokens: 1024`, `fallbacks: "default"`, `output_config: {effort: "low"}`, **kein** `thinking`-Feld, kein Prefill. Vor dem Lesen von `content` `stop_reason == "refusal"` prüfen.
- GitHub: `GET https://api.github.com/repos/melvinmng/tagwerk/issues?assignee=@me&state=open&per_page=1` (der repo-bezogene Endpunkt, den das MVP nutzt; ein Fine-grained PAT mit `Issues: Read and write` auf dieses Repo) mit den Headern `Authorization: Bearer <PAT>`, `Accept: application/vnd.github+json` und `X-GitHub-Api-Version: 2022-11-28`.
- ChatGPT (Sign in with ChatGPT, Open-Source-Self-Serve-Flow, Repo öffentlich unter MIT): Authorize `https://auth.openai.com/api/accounts/authorize`, Token `https://auth.openai.com/api/accounts/oauth/token`, Erstregistrierung mit `client_id=dynamic_agent_client`, `agent_name_hint=Tagwerk`, `ext_agent_host_id=urn:uuid:<einmalig, Schlüsselbund>`, Scope `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct`, `resource=https://api.openai.com/v1`, PKCE S256, Redirect `http://127.0.0.1:1455/auth/callback`. Die ausgestellte `oaiapp_…`-ID kommt aus der Callback-Query. Responses-Aufrufe mit `store:false`, `stream:true`, `input` als Array, `instructions` statt System-Rolle, ohne `max_output_tokens`/`temperature`. Das Modell wird aus `GET /v1/models` (`visibility == "list"`) gewählt.
- Secrets nie im Repo, nie in Logs. Nur im Schlüsselbund (`kSecClassGenericPassword`, Service `com.melvinmng.tagwerk.spike`).
- Code-Kommentare und Log-Texte auf Englisch, UI-Texte auf Deutsch.
- `.gitignore` ergänzen: `*.xcodeproj/`, `.build/`, `.swiftpm/`, `spike/build/`.
- Repo liegt in iCloud Drive: vor jedem Commit `git status --porcelain | grep ' 2'` muss leer sein.

## Review Focus

1. **Berechtigung verweigert oder nur „Hinzufügen“ für den Kalender:** Die Probe muss ❌ mit dem Grund anzeigen und darf nicht abstürzen. Abgedeckt durch einen Test in Task 2.
2. **HealthKit liefert keine Daten** (keine Watch, leeres Health): Das zählt als ✅ mit „0 Einträge“, nicht als Fehler, denn iOS verrät nicht, ob der Lesezugriff verweigert wurde. Abgedeckt durch einen Test in Task 3.
3. **Claude antwortet mit HTTP 401/429/529 oder `stop_reason: "refusal"`:** Die App zeigt Status und Grund lesbar an. Abgedeckt durch einen Test in Task 4.
4. **Die neue Installation überschreibt Daten:** Nach der Neuinstallation muss ein Wert, den die App vorher gespeichert hat, noch vorhanden sein. Abgedeckt durch die manuelle Prüfung in Task 6.
5. **iPhone nicht im WLAN oder Mac schläft:** Das Skript endet mit einem Exit-Code ≠ 0 ohne Teilinstallation, wiederholt stündlich und meldet sich ab Tag 6. Abgedeckt durch den Testmodus `--dry-run` in Task 5.

---

### Task 1: Projektgerüst und Signierung

**Files:**
- Create: `spike/project.yml`, `spike/Sources/TagwerkSpikeApp.swift`, `spike/Sources/ContentView.swift`, `spike/Sources/Info.plist`, `spike/Sources/TagwerkSpike.entitlements`, `spike/Tests/SmokeTests.swift`
- Modify: `.gitignore`

**Interfaces:**
- Produces: Target `TagwerkSpike` (App), Target `TagwerkSpikeTests` (Unit-Tests), Scheme `TagwerkSpike`. Team-ID steht in `spike/project.yml` unter `settings.base.DEVELOPMENT_TEAM`.

- [ ] **Step 1:** Team-ID ermitteln (**deine Aktion**). Ein Zertifikat existiert erst nach dem ersten signierten Build, deshalb so: `project.yml` zunächst ohne `DEVELOPMENT_TEAM` anlegen, `xcodegen` ausführen, danach `spike/TagwerkSpike.xcodeproj` in Xcode öffnen. Unter Target → Signing & Capabilities wählst du den Personal Team aus, Xcode legt dann Zertifikat und Profil an. Die Team-ID steht danach in `security find-identity -v -p codesigning` (Klammerwert) und wird in `project.yml` eingetragen.
- [ ] **Step 2:** `project.yml` anlegen:
  - iOS-App, Deployment-Target 27.0, `CODE_SIGN_STYLE: Automatic`.
  - Entitlement `com.apple.developer.healthkit: true`.
  - In `Info.plist` die Texte für `NSRemindersFullAccessUsageDescription`, `NSCalendarsFullAccessUsageDescription` und `NSHealthShareUsageDescription`, jeweils deutsch, etwa „Tagwerk liest deine Erinnerungen, um sie mit Kalender und GitHub zusammenzuführen.“
- [ ] **Step 3:** Test `test_appLaunches_bundleIdentifierMatches` prüft, dass `Bundle.main.bundleIdentifier` mit `com.melvinmng.tagwerk.spike` beginnt.
- [ ] **Step 4:** Ausführen: `cd spike && xcodegen && DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -scheme TagwerkSpike -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`. Erwartet: `** TEST SUCCEEDED **`. Den Simulatornamen vorher mit `xcrun simctl list devices available` bestätigen.
- [ ] **Step 5:** Auf das Gerät bauen: `xcodebuild -scheme TagwerkSpike -destination 'id=<DEVICE_ID>' -allowProvisioningUpdates build`. Erwartet: `** BUILD SUCCEEDED **` und ein angelegtes Profil. Schlägt die HealthKit-Signierung fehl, ist das ein Spike-Ergebnis: im Abschlussbericht festhalten.
- [ ] **Step 6:** Commit `spike: scaffold feasibility app with XcodeGen`.

### Task 2: Probe für EventKit (Reminders und Kalender)

**Files:** Create `spike/Sources/Probes/ProbeResult.swift`, `spike/Sources/Probes/EventKitProbe.swift`, Test `spike/Tests/EventKitProbeTests.swift`

**Interfaces:**
- Produces: `struct ProbeResult: Sendable { let name: String; let ok: Bool; let detail: String }`
- Produces: `protocol Probe { var name: String { get }; func run() async -> ProbeResult }`
- Produces: `struct EventKitProbe: Probe`. Ablauf: Vollzugriff für Reminders und Kalender anfordern, Anzahl offener Reminders und heutiger Termine lesen, dann eine Test-Erinnerung „Tagwerk-Spike Test“ anlegen, abhaken und wieder löschen. Das prüft den Schreibweg aus F1. Das Löschen steht in einem `defer`, damit die Test-Erinnerung auch bei einem Fehler verschwindet.
- Produces: `static func describe(status: EKAuthorizationStatus) -> String` (deutsche Kurztexte)

- [ ] **Step 1:** Test `test_describe_deniedStatus_isReadable` prüft, dass `describe(.denied)` den Text „verweigert“ enthält, und `test_describe_writeOnly_isNotOk` prüft, dass `.writeOnly` als nicht ausreichend gilt.
- [ ] **Step 2:** Test fehlschlagen lassen, dann implementieren und grün machen. Befehl wie in Task 1, Step 4.
- [ ] **Step 3:** Commit `spike: add EventKit probe`.

### Task 3: Probe für HealthKit

**Files:** Create `spike/Sources/Probes/HealthKitProbe.swift`, Test `spike/Tests/HealthKitProbeTests.swift`

**Interfaces:**
- Produces: `struct HealthKitProbe: Probe`. Ablauf: `HKHealthStore.isHealthDataAvailable()` prüfen, dann Lesezugriff für `stepCount`, `workoutType()` und `dietaryEnergyConsumed` anfordern. Danach die Schrittsumme von heute und die Anzahl der Workouts der letzten 7 Tage lesen.
- Produces: `static func summarize(steps: Double?, workouts: Int) -> ProbeResult`

- [ ] **Step 1:** Test `test_summarize_noData_isOkWithZero` prüft, dass `summarize(steps: nil, workouts: 0)` den Wert `ok == true` liefert und `detail` den Text „0“ enthält.
- [ ] **Step 2:** Rot, implementieren, grün.
- [ ] **Step 3:** Commit `spike: add HealthKit probe`.

### Task 4: Schlüsselbund, Claude-Probe und GitHub-Probe

**Files:** Create `spike/Sources/Secrets.swift`, `spike/Sources/Probes/ClaudeProbe.swift`, `spike/Sources/Probes/GitHubProbe.swift`, Test `spike/Tests/HTTPProbeTests.swift`

**Interfaces:**
- Produces: `enum Secrets { static func save(_ value: String, account: String) throws; static func load(account: String) -> String? }` mit den Accounts `"anthropic"` und `"github"`.
- Produces: `struct ClaudeProbe: Probe` sowie `static func makeRequest(apiKey: String) -> URLRequest` und `static func interpret(status: Int, body: Data) -> ProbeResult`.
- Produces: `struct GitHubProbe: Probe` sowie `static func makeRequest(token: String) -> URLRequest` und `static func interpret(status: Int, body: Data) -> ProbeResult`.

- [ ] **Step 1:** Tests in `HTTPProbeTests`:
  - `test_claudeRequest_hasRequiredHeadersAndBody`: Header `anthropic-version == "2026-10-21"`, `anthropic-beta == "server-side-fallback-2026-07-01"`. Body-JSON mit `model == "claude-opus-5-5"`, `fallbacks == "default"`, ohne Schlüssel `thinking`.
  - `test_claudeInterpret_refusal_isNotOk`: `{"stop_reason":"refusal","content":[]}` mit Status 200 ergibt `ok == false` und `detail` enthält „abgelehnt“.
  - `test_claudeInterpret_429_isReadable`: `detail` enthält „429“.
  - `test_githubRequest_usesBearerAndApiVersion`.
  - `test_githubInterpret_401_mentionsToken`: `detail` enthält „Token“.
- [ ] **Step 2:** Rot, implementieren, grün.
- [ ] **Step 3:** In `ContentView` zwei `SecureField`s mit „Speichern“-Knopf (schreibt in `Secrets`), einen Knopf „Alle Prüfungen starten“ und eine Liste der `ProbeResult`s mit ✅/❌ und Detailtext. Dazu einen Zähler „Starts seit Installation“ in `UserDefaults` als Messwert für Review Focus 4.
- [ ] **Step 4:** Commit `spike: add keychain, Claude and GitHub probes`.


### Task 4b: ChatGPT-Login und Responses-Aufruf (Nachtrag 2026-11-17)

**Files:** Create `spike/Sources/ChatGPT/ChatGPTAuth.swift`, `spike/Sources/ChatGPT/LoopbackServer.swift`, `spike/Sources/ChatGPT/ChatGPTSession.swift`, `spike/Sources/Probes/ChatGPTProbe.swift`, Test `spike/Tests/ChatGPTTests.swift`

**Interfaces:**
- Produces: `ChatGPTAuth.codeChallenge(verifier:) -> String`, `authorizeURL(...) -> URL`, `parseCallback(_:expectedState:isRegistration:) throws -> ChatGPTCallback`, `tokenRequest(...)`/`refreshRequest(...) -> URLRequest`
- Produces: `ChatGPTProbe.filterModels(_:) -> [String]`, `parseStream(_:) -> StreamOutcome`, `makeResponsesRequest(...)`, `describe(status:body:)`
- Produces: `LoopbackServer` (NWListener nur auf 127.0.0.1:1455), der den Callback mit 302 auf `tagwerkspike://auth/done` beantwortet; Login per `ASWebAuthenticationSession` (System-Safari-Sheet, App bleibt im Vordergrund)

- [ ] Tests: RFC-7636-Testvektor (Anhang B), Authorize-URL-Parameter, Callback mit falschem `state` bzw. fehlender `client_id` bei Registrierung wirft, Token-Formular, Modellfilter, SSE-Parser (Deltas, `response.completed`, `response.failed`), Fehlertexte für 429 `subscription_sharing_usage_limit_exceeded` und 401 `subscription_sharing_invalid_user`.
- [ ] Gerät: Login, Modellliste, ein Aufruf mit `text.format` json_schema (sonst Funktions-Tool, Ergebnis festhalten), ein Aufruf mit kleinem Bild, erzwungene Token-Erneuerung mit neuem Refresh-Token im Schlüsselbund.

### Task 4c: Apples lokales Modell (Nachtrag 2026-11-17)

**Files:** Create `spike/Sources/Probes/AppleModelProbe.swift`, Test `spike/Tests/AppleModelProbeTests.swift`

- [ ] Test: Verfügbarkeitsgründe (Apple Intelligence aus, Modell nicht bereit, Gerät ungeeignet) ergeben lesbare deutsche Texte.
- [ ] Gerät: Prüfen, ob Deutsch unterstützt wird, und eine Guided-Generation-Anfrage mit einer `@Generable`-Mahlzeitenstruktur für „2 Brötchen mit Käse“.

Die Claude-Probe zeigt ohne Schlüssel „übersprungen“, nicht ❌.

### Task 5: Automatische Neuinstallation (Mac)

**Files:** Create `scripts/refresh-install.sh`, `scripts/de.tagwerk.refresh.plist`, `scripts/README.md`

**Interfaces:**
- Consumes: Scheme `TagwerkSpike` und Geräte-ID (`DEVICE_ID` aus `~/Library/Application Support/Tagwerk/config`, nicht im Repo).
- Produces: `refresh-install.sh [--dry-run] [--force]`. Exit-Codes: 0 = installiert oder noch nicht fällig, 1 = Build-Fehler, 2 = Gerät nicht erreichbar, 3 = Signierfehler.
  - Zustand in `~/Library/Application Support/Tagwerk/last-install` als ISO-Datum.
  - Fällig ab 5 Tagen. Ab Tag 6 ohne Erfolg kommt eine Mitteilung per `osascript -e 'display notification …'`.
  - Logs in `~/Library/Logs/Tagwerk/refresh.log`.
- Produces: LaunchAgent, der stündlich läuft (`StartInterval 3600`) und `refresh-install.sh` aufruft, mit `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` in `EnvironmentVariables`.

- [ ] **Step 0:** Build-Klon außerhalb von iCloud anlegen: `git clone https://github.com/melvinmng/tagwerk ~/Library/Developer/Tagwerk/src`. Das Skript macht vor jedem Build `git -C ~/Library/Developer/Tagwerk/src pull --ff-only` und baut nur dort. Grund: Prozesse, die launchd startet, dürfen iCloud Drive (`~/Library/Mobile Documents`) ohne Freigabe nicht lesen, und iCloud kann Dateien auslagern. Im Skript stehen absolute Pfade, `PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin` wird im plist gesetzt.
- [ ] **Step 1:** `--dry-run` prüft nur und gibt aus: Fälligkeit, Erreichbarkeit des Geräts (`xcrun devicectl list devices` mit Zustand `connected`/`available`) und Signier-Identität. Ausführen: `scripts/refresh-install.sh --dry-run`. Erwartet bei angeschlossenem iPhone: `device: reachable`, Exit 0.
- [ ] **Step 2:** Echter Lauf. Ablauf: `xcodegen` → `xcodebuild -allowProvisioningUpdates -scheme TagwerkSpike -destination id=$DEVICE_ID -derivedDataPath ~/Library/Developer/Tagwerk/DerivedData build` → `xcrun devicectl device install app --device $DEVICE_ID <App-Pfad>`. Ausführen mit `--force`. Erwartet: Exit 0 und die App auf dem iPhone aktualisiert.
- [ ] **Step 3:** Agent installieren: `cp scripts/de.tagwerk.refresh.plist ~/Library/LaunchAgents/ && launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/de.tagwerk.refresh.plist`. **Abnahme im echten launchd-Kontext** (du sitzt am Mac): `launchctl setenv TAGWERK_FORCE 1 && launchctl kickstart -k gui/$(id -u)/de.tagwerk.refresh`. Erscheint ein Schlüsselbund-Dialog für `codesign`, klickst du „Immer erlauben“. Erwartet: In `~/Library/Logs/Tagwerk/refresh.log` steht `install: ok`, `launchctl print gui/$(id -u)/de.tagwerk.refresh` meldet `last exit code = 0`, danach `launchctl unsetenv TAGWERK_FORCE`. Ein Terminal-Lauf allein zählt nicht als Abnahme.
- [ ] **Step 4:** In `scripts/README.md` festhalten: Installieren und Entfernen des Agents (`launchctl bootout …`), Voraussetzungen (Mac wach, iPhone im selben WLAN, in Xcode unter Devices „Connect via network“ aktiv).
- [ ] **Step 5:** Commit `spike: add automatic weekly reinstall via launchd`.

### Task 6: Geräteprüfung und Ergebnisbericht

**Files:** Create `docs/superpowers/spikes/2026-11-xx-feasibility-results.md`; Modify `docs/superpowers/specs/2026-11-17-tagwerk-design.md` §4/§5 (Ergebnisse eintragen)

- [ ] **Step 1 (du am iPhone):** App öffnen, API-Key und PAT eingeben, „Alle Prüfungen starten“ tippen und alle Berechtigungen erlauben. Screenshot der Ergebnisliste.
- [ ] **Step 2:** iPhone vom Kabel trennen, nur WLAN. `scripts/refresh-install.sh --force` ausführen. Erwartet: Exit 0, der Zähler „Starts seit Installation“ und die Secrets sind danach noch vorhanden (Review Focus 4).
- [ ] **Step 3:** Ergebnisbericht schreiben, je Probe ✅/❌ mit Konsequenz fürs Design. Hinzu kommen die offenen Punkte aus Weg A: Hält die Apple-ID-Anmeldung im Hintergrund? Wie zuverlässig ist die Installation per WLAN? Das zweite lässt sich erst nach 2 Wochen Laufzeit beurteilen, als Folge-Issue anlegen.
- [ ] **Step 4:** Aufräumen für Phase 2: Spike-App vom iPhone löschen (belegt einen von 3 App-Plätzen) und `DEVICE_ID`/Scheme im Refresh-Skript auf die echte App umstellen, sobald sie existiert.
- [ ] **Step 5:** Commit `docs: record phase 1 feasibility results` und PR `spike/feasibility` → `main`, nur Docs und Skripte; den Spike-Ordner entscheiden wir im PR.
