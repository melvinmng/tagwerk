# Tagwerk – Design

Stand: 2026-11-17 · Status: **freigegeben am 2026-11-17** · Gate: Phase 1 (Machbarkeits-Spike) muss bestehen, bevor das MVP gebaut wird.

> Phase 2 ist im Nachtrag `2026-11-17-phase-2-design.md` genauer beschrieben. Er ersetzt hier die GitHub-Deadline-Quelle (Meilensteine → GitHub Projects) und den GitHub-Zugang (Fine-grained PAT → „Mit GitHub anmelden“).

## 1. Absicht und Warum

Eine private iPhone-App, die alle offenen Aufgaben (Apple Reminders, GitHub), den Kalender sowie Ernährung und Training an einem Ort zusammenführt. Eine KI-Schicht (Claude) hilft, den Tag zu planen, Deadlines im Blick zu behalten und Mahlzeiten schnell zu erfassen. Hauptnutzung: **unterwegs am iPhone**. Nur für eine Person, kein Vertrieb.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele (MVP)**
- Heute-Ansicht: Termine + fällige Aufgaben aus allen Quellen in einer Zeitleiste.
- Einheitlicher Eingang aller Aufgaben (Reminders, GitHub-Issues, lokale Aufgaben) mit Deadlines.
- KI-Tagesplan auf Knopfdruck: schlägt Zeitblöcke für Aufgaben zwischen Terminen vor.
- Deadline-Erinnerungen über lokale Benachrichtigungen.
- Schnellerfassung von Essen/Trinken (Text oder Foto → KI-Schätzung von Kalorien/Makros) und Training.

**Nicht-Ziele**
- App-Store-Vertrieb, Mehrbenutzerbetrieb, Android, Web-Version.
- Eigener Server/Backend.
- Geräteübergreifender Sync über CloudKit (mit kostenlosem Account nicht verfügbar, s. §4).

**Anti-Ziele (wäre trotz funktionierender Technik ein Fehlschlag)**
- Die App wird zur zweiten Aufgabenquelle, die von Reminders abweicht (Daten-Drift).
- Gesundheitsdaten verlassen das Gerät ohne bewusste Aktion.
- KI-Kalorienschätzungen werden als exakte Werte dargestellt.
- Erfassen dauert länger als in den Originalapps (> ~10 s für eine Mahlzeit).

## 3. Ansätze (entschieden)

| Weg | Kern | Abwägung | Entscheidung |
|---|---|---|---|
| 1. Native SwiftUI-App | EventKit, HealthKit, GitHub-API, Claude-API direkt auf dem Gerät | Einziger Weg mit direktem Reminders/Health-Zugriff am iPhone; höchster Aufwand, Xcode + Signierung nötig | **Gewählt** |
| 2. Claude-Artefakt | KI + Connectors im Browser | Keine Reminders/Health am iPhone; Mac-Brücke unterwegs tot | verworfen |
| 3. Web-App + Kurzbefehle | Server, Kurzbefehle pushen Daten | Laufende Kosten, nur periodischer Sync | verworfen |

## 4. Rahmenbedingungen (kostenloser Apple-Account)

| Regel | Status | Quelle/Folge |
|---|---|---|
| HealthKit ist mit kostenlosem Account nutzbar | **verifiziert** (Apple-Tabelle „Supported capabilities (iOS)“, Spalte „Apple Developer“) | Spike bestätigt Gerätelauf |
| App Groups, Background Modes verfügbar | **verifiziert** (gleiche Tabelle) | Widget/Hintergrund-Refresh möglich |
| CloudKit, Push, Time-Sensitive Notifications **nicht** verfügbar | **verifiziert** (gleiche Tabelle) | Kein iCloud-Sync, nur lokale Benachrichtigungen |
| Provisioning-Profil läuft nach 7 Tagen ab | verifiziert (Apple „Choosing a Membership“) | Wöchentlich per Xcode neu installieren. **Drüberinstallieren behält Daten, App löschen verliert sie.** |
| Max. 3 Apps pro Gerät | verifiziert (gleiche Quelle) | unkritisch |
| Upgrade auf bezahltes Programm (99 $/Jahr) jederzeit ohne Code-Änderung | Annahme | Lohnt sich erst, wenn das wöchentliche Neuinstallieren stört; brächte außerdem CloudKit/Push. Vorerst nicht nötig. |

## 5. Phasen

**Phase 0 – Einrichtung (nur durch dich möglich)**
1. Xcode aus dem App Store installieren (groß), danach `sudo xcode-select -s /Applications/Xcode.app`.
2. In Xcode → Settings → Accounts mit der Apple-ID anmelden (Personal Team entsteht).
3. iPhone per Kabel verbinden, Entwicklermodus aktivieren (Einstellungen → Datenschutz & Sicherheit).
4. Nach der ersten Installation dem Entwicklerprofil vertrauen (Einstellungen → Allgemein → VPN & Geräteverwaltung).
5. `brew install xcodegen` (Projektgenerator, s. §6).
6. Anthropic-API-Key und GitHub-Token bereitstellen. Der Token-Typ und seine Rechte hängen von F1/F1b ab: nur lesen oder auch schreiben, REST oder GraphQL. Eingabe erfolgt in der App, gespeichert wird im Schlüsselbund.

**Phase 1 – Machbarkeits-Spike (Wegwerf-Code, Branch `spike/feasibility`)**
Eine Minimal-App mit einem Bildschirm, die nacheinander:
- eine Erinnerung und einen Termin über EventKit liest,
- HealthKit-Lesezugriff (Schritte, Workouts, Nahrungsenergie) anfordert und einen Wert liest,
- einen Claude-Aufruf ausführt und die Antwort anzeigt,
- ein GitHub-Issue über die REST-API liest.

Bestanden, wenn alle vier auf dem echten iPhone mit Personal Team funktionieren. Fällt HealthKit aus: Training/Ernährung nur manuell in SwiftData, Rest unverändert. Fällt EventKit-Reminders aus: Projekt neu bewerten.

**Phase 2 – MVP (Aufgaben, Kalender, KI-Tagesplan, Deadlines)**
**Phase 3 – Ernährung & Training**
**Phase 4 – Komfort** (Widget, Siri-Kurzbefehle/App Intents, Wochenrückblick)

## 6. Architektur

- **Sprache/UI:** Swift 6, SwiftUI, Deployment-Target iOS 27.0 (Gerät: iOS 27.2.1).
- **Projekt-Tooling:** XcodeGen (`project.yml` erzeugt das Xcode-Projekt; `.xcodeproj` wird nicht eingecheckt – beim Scaffolding kommen `*.xcodeproj/`, `.build/` und `.swiftpm/` in die `.gitignore`). Tests per `xcodebuild test` im Simulator; Geräteinstallation über Xcode.
- **Persistenz:** SwiftData für lokale Daten (lokale Aufgaben, Mahlzeiten, Trainings, Tagespläne, KI-Cache). Reminders/Kalender werden nie kopiert, sondern live über EventKit gelesen (Quelle der Wahrheit bleibt Apple).
- **Module (Swift Packages im Repo):**
  - `TaskSources` – Protokoll `TaskSource`; Implementierungen `RemindersSource` (EKReminder), `GitHubSource` (REST, PAT), `LocalSource` (SwiftData). Einheitlicher Typ `TaskItem { id, source, title, due, priority, url, isCompleted }`.
  - `CalendarSource` – EKEvent-Lesezugriff, Aktualisierung über `EKEventStoreChanged`.
  - `HealthBridge` – HealthKit lesen (Workouts, Schritte, Energie), optional Mahlzeiten als `dietaryEnergyConsumed` schreiben.
  - `Planner` – Claude-Client + Prompts (s. §7).
  - `Notifications` – lokale Benachrichtigungen für Deadlines.
  - `Secrets` – Schlüsselbund-Wrapper.
- **Schreibrechte:** Reminders und GitHub sind les- und schreibbar, s. §10 F1.

## 7. KI-Schicht

> **Aktualisiert 2026-11-17:** Die KI läuft über ein austauschbares Protokoll `LLMProvider` mit drei Anbietern: (1) **ChatGPT-Abo (Pro)** über „Sign in with ChatGPT“ als Standard. Das Repo ist dafür öffentlich (MIT), um den Open-Source-Self-Serve-Flow zu nutzen. (2) **Apples lokales Modell** (Foundation Models) für einfache Aufgaben wie das Zerlegen von Mahlzeiten, kostenlos und ohne Netz. (3) **Claude-API** als Ausweichlösung, falls OpenAI die Vorschau ändert. Die Claude-Details unten gelten für Anbieter 3. Der Machbarkeitstest entscheidet, welcher Anbieter welche Aufgabe übernimmt.

- **Zugriff:** Claude Messages API per HTTPS (`URLSession`, kein offizielles Swift-SDK). API-Key im Schlüsselbund, nie im Code/Repo.
- **Modell:** `claude-opus-5-5` als Standard, `effort` je Funktion explizit (Tagesplan `medium`, Mahlzeit-Parsing `low`). Ein günstigeres Modell (z. B. Haiku 5.5 fürs Mahlzeiten-Parsing) ist deine Entscheidung – derzeit nicht gesetzt.
- **Antwortformat:** Structured Outputs (`output_config.format`, JSON-Schema) für Tagesplan und Mahlzeitenschätzung; kein Prefill; `thinking` wird nicht gesetzt.
- **Ablehnungen:** `stop_reason == "refusal"` wird geprüft; serverseitige Fallbacks (`fallbacks: "default"`, Beta-Header `server-side-fallback-2026-07-01`) sind aktiviert.
- **Funktionen:**
  1. *Tagesplan:* Eingabe = heutige Termine, offene Aufgaben mit Deadlines, Präferenzen (Arbeitszeiten, Pausen) → Ausgabe = Zeitblöcke + Begründung + Risiken („Deadline X wird knapp“). Vorschlag; Übernahme nur auf Tippen.
  2. *Mahlzeit erfassen:* Text oder Foto → Lebensmittel, geschätzte kcal/Protein/KH/Fett mit Unsicherheitsangabe; vor dem Speichern editierbar.
  3. *Deadline-Check:* bei App-Start lokal berechnet (ohne KI); KI nur für Priorisierungsvorschläge.
- **Datenschutz:** Gesundheits- und Mahlzeitendaten gehen nur für die jeweilige Funktion und nur nach einmaliger Einwilligung in der App an die API. Keine Telemetrie.

## 8. UI-Design (Skizzen)

Tab-Leiste mit vier Tabs. Visuelle Richtung: ruhig, iOS-nativ (SF Symbols, Systemfarben, Dark Mode), Quellen farblich markiert (Reminders = Systemfarbe der Liste, GitHub = Grau/Schwarz, Lokal = Akzentfarbe).

```
┌ Heute ─────────────────────┐   ┌ Aufgaben ──────────────────┐
│ Di, 17. Nov      ✨ Planen  │   │ [Alle|Reminders|GitHub|…]  │
│ ⚠︎ 2 Deadlines heute        │   │ Überfällig                 │
│ 09:00 ▇ Vorlesung (Kal.)    │   │  ○ Abgabe Portfolio  ⏰ heute│
│ 10:30 ░ Issue #12 (vorgeschl)│  │ Diese Woche                │
│ 12:00 ▇ Mittag              │   │  ○ #34 Fix login   (GitHub)│
│ 13:00 ░ Lernzettel (Remind.)│   │  ○ Einkaufen   (Reminders) │
│ ─────────────────────────── │   │ Ohne Datum                 │
│ 🔥 1.240 / 2.300 kcal  💧 1,2l│  │  ○ …                       │
└─────────────────────────────┘   └────────────────────────────┘
┌ Erfassen ──────────────────┐   ┌ Fortschritt ───────────────┐
│ [🍽 Essen] [💧 Trinken] [🏋︎] │   │ Woche: kcal-Balken, Protein │
│ „2 Brötchen mit Käse“ 📷    │   │ Trainings: 3/4 ✓           │
│ → KI: ~520 kcal (±20 %)     │   │ Deadlines erledigt: 8/10   │
│   P 22 · KH 60 · F 20  ✎    │   │                             │
│        [Speichern]          │   │                             │
└─────────────────────────────┘   └────────────────────────────┘
```

Nächster Schritt nach Freigabe: gerenderte Mockups der vier Screens zum Abstimmen von Farben/Typografie.

## 9. Entschieden vs. dem Umsetzenden überlassen

**Entschieden:** Weg 1 (native App), kostenloser Account zuerst, kein eigener Server, EventKit als Quelle der Wahrheit, KI über austauschbare Anbieter (ChatGPT-Abo zuerst, Apple lokal, Claude-API als Ausweichlösung, s. §7), XcodeGen, SwiftData, lokale Benachrichtigungen.

**Vorschläge des Planers (nach Builder-Check, bitte prüfen):**
- *Tagesplan übernehmen* speichert den Plan nur in SwiftData und zeigt ihn in „Heute“. Kalender und Reminders werden nicht verändert. Ein Kalender-Export kommt optional in Phase 4. `TaskItem` erhält ein Feld `estimatedMinutes`: Claude schätzt, du kannst korrigieren.
- *Datenhoheit Ernährung/Training:* Mahlzeiten und Getränke liegen in SwiftData und werden nach HealthKit gespiegelt (mit App-Metadaten). Beim Lesen werden eigene Einträge ausgefiltert, damit nichts doppelt zählt. Workouts liest die App aus HealthKit (z. B. von der Apple Watch). Manuell erfasste Trainings schreibt sie als `HKWorkout` dorthin. Tagesziele (kcal, Wasser, Trainings pro Woche) stellst du in den Einstellungen ein.
- *Benachrichtigungen* nur für GitHub- und lokale Aufgaben, weil Reminders selbst erinnern. Es gibt eine einstellbare Vorlaufzeit, und die App plant höchstens die nächsten 50 Benachrichtigungen ein (iOS erlaubt maximal 64).
- *Kalender und Listen:* Auswahl in den Einstellungen. Abonnierte Kalender, Geburtstage und Feiertage sind standardmäßig aus. Ganztägige Termine erscheinen als Kopfzeile.
- *Sprache:* App und Prompts auf Deutsch, Texte über String Catalogs lokalisierbar.

**Dem Umsetzenden überlassen:** konkrete Prompts, Schema-Felder, Ordnerstruktur, Testaufbau, visuelle Details innerhalb der Richtung oben.

## 10. Entscheidungen zu den offenen Fragen (2026-11-17)

- **F1 Bearbeiten:** Aufgaben müssen in der App bearbeitet werden können.
  - *Reminders:* anlegen, bearbeiten (Titel, Fälligkeit, Notiz, Liste), abhaken und wieder öffnen, über EventKit mit Vollzugriff.
  - *GitHub:* Issues anlegen, bearbeiten (Titel, Text, Labels, Meilenstein), schließen und wieder öffnen, kommentieren. Dafür ein Fine-grained PAT mit `Issues: Read and write` auf die gewählten Repos, das im Schlüsselbund liegt.
  - *Konflikte:* Vor jedem Schreiben lädt die App den aktuellen Stand neu (EventKit `refresh`, GitHub `updated_at`). Hat sich das Element inzwischen geändert, fragt sie nach, statt es zu überschreiben.
- **F1b GitHub-Deadlines:** Die Deadline kommt vom Fälligkeitsdatum des Meilensteins, wie vorgeschlagen und ohne Einwand. Es zählen offene Issues, die mir zugewiesen sind, in den gewählten Repos. Felder aus GitHub Projects (GraphQL) kommen höchstens später.
- **F2 iOS:** Auf dem iPhone 16 Pro läuft iOS 27.2.1, Xcode ist 27.2. Deployment-Target: iOS 27.0.
- **F3:** Die 99 $ kommen erst später, wenn das wöchentliche Neuinstallieren lästig wird.
- **Automatische Neuinstallation (Weg A):** Ein `launchd`-Agent auf dem Mac baut die App alle 5 Tage neu und installiert sie per WLAN (`xcodebuild -allowProvisioningUpdates` + `devicectl`). Ist das iPhone nicht erreichbar, versucht er es stündlich erneut und meldet sich ab Tag 6. Die Alternativen bezahlter Account (später möglich) und SideStore (verworfen: inoffiziell, instabil, HealthKit ungeklärt) sind damit nachrangig. Ob WLAN-Installation und Hintergrundanmeldung zuverlässig sind, prüft Phase 1.
- **F4 Speicherort:** Das Repo bleibt in iCloud Drive, der Ordner ist auf „Immer auf diesem Gerät behalten“ gestellt. Zusätzliche Schutzmaßnahmen:
  - Build-Ausgaben liegen außerhalb des Repos (Standard-DerivedData unter `~/Library/Developer`).
  - Das generierte `.xcodeproj` steht nicht in Git.
  - Vor jedem Commit prüft die Arbeit `git status` auf Konfliktkopien („… 2“).

## Quellen

- Apple: Supported capabilities (iOS) – https://developer.apple.com/help/account/reference/supported-capabilities-ios/
- Apple: Choosing a Membership – https://developer.apple.com/support/compare-memberships
- Apple: Configuring HealthKit access – https://developer.apple.com/documentation/xcode/configuring-healthkit-access
