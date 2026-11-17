# Tagwerk – Phase 2 Design (Nachtrag)

Stand: 2026-11-17 · Status: **Entwurf, wartet auf Freigabe** · Baut auf: `2026-11-17-tagwerk-design.md` (Hauptdesign) und `../spikes/2026-11-17-feasibility-results.md` (Ergebnisse Phase 1)

## 1. Ziel von Phase 2

Die erste echte Tagwerk-App für den Alltag mit drei Tabs, **Heute**, **Aufgaben** und **Einstellungen**:

- Aufgaben aus Apple Reminders, GitHub (über GitHub Projects) und lokalen Aufgaben in einer Liste, alle bearbeitbar.
- Kalendertermine des Tages.
- KI-Tagesplan über das ChatGPT-Abo (auf Tippen).
- Deadline-Benachrichtigungen für GitHub- und lokale Aufgaben.
- Geführte Einrichtung beim ersten Start.

Ernährung und Training (Tab „Erfassen“) kommen erst in Phase 3.

**Nicht-Ziele in Phase 2:** Widget, Siri, Wochenrückblick, Schreiben in den Kalender, Health-Daten.

## 2. Getroffene Entscheidungen (Nutzer, 2026-11-17)

| Thema | Entscheidung |
|---|---|
| GitHub-Quelle | **GitHub Projects (v2)** sind die Quelle für Fälligkeit, Priorität, Aufwand und Status. Gelesen werden **alle offenen Projects** des Kontos. |
| GitHub-Zugang | **„Mit GitHub anmelden“** über eine eigene OAuth-App im Device Flow (Code-Eingabe auf github.com). Scopes `repo` und `project`, weil die meisten Repos privat sind. Fine-grained Tokens scheiden aus: Sie können laut GitHub-Doku keine Projects eines persönlichen Kontos lesen. |
| Mockups | freigegeben (Heute, Aufgaben, Bearbeiten, Einrichtung, Einstellungen; siehe §9) |
| KI | ChatGPT-Abo als Standard; Claude-API als Ausweichlösung; Apples lokales Modell nur für zahlenfreie Hilfsaufgaben (Ergebnis Phase 1) |

## 3. App-Aufbau

- **Neues Xcode-Projekt** unter `app/` (XcodeGen, `app/project.yml`). Bundle-ID `com.melvinmng.tagwerk`, Anzeigename „Tagwerk“, Deployment-Target iOS 27.0, Swift 6 (strict concurrency).
- **Spike-Code wird nicht kopiert.** Phase 1 liefert nur Erkenntnisse. Pure Funktionen dürfen als Vorlage dienen, werden aber testgetrieben neu geschrieben.
- **Lokale Swift-Packages** in `app/Packages/`:

| Package | Verantwortung |
|---|---|
| `TagwerkCore` | Modelltypen (`TaskItem`, `TaskSource`, `CalendarEvent`, `DayPlan`), Protokolle, Zeit- und Datumslogik. Keine Frameworks außer Foundation. |
| `RemindersKit` | EventKit-Zugriff auf Erinnerungen und Kalender, Änderungsbeobachtung (`EKEventStoreChanged`) |
| `GitHubKit` | Device-Flow-Login, GraphQL (Projects v2) und REST (Issues), Konfliktschutz |
| `AIKit` | Protokoll `LLMProvider`, `ChatGPTProvider` (Sign in with ChatGPT), `ClaudeProvider` (Ausweichlösung), Tagesplan-Schema |
| `SecureStore` | Schlüsselbund mit Update-or-Add |
| `Scheduling` | lokale Benachrichtigungen, `BGAppRefreshTask` |

- **Persistenz:** SwiftData für lokale Aufgaben, Tagespläne, Einstellungen und einen Lese-Cache der GitHub-Items (für Offline-Anzeige). Reminders und Kalender werden nicht gespiegelt.
- **Capabilities:** Background Modes (Background fetch), kein HealthKit in Phase 2 (kommt in Phase 3 dazu).

## 4. Aufgabenmodell

`TaskItem` vereinheitlicht alle Quellen:

| Feld | Reminders | GitHub (Project-Item) | Lokal |
|---|---|---|---|
| `id` | `calendarItemIdentifier` | Project-Item-Node-ID | UUID |
| `title` | Titel | Issue-Titel | Titel |
| `due` | Datum + optional Uhrzeit | Feld „Due date“ (**nur Datum**) | Datum + optional Uhrzeit |
| `priority` | EK-Priorität (1–9) auf P1–P5 abgebildet | Feld „Priority“ (P1–P5) | P1–P5 |
| `estimateMinutes` | – (KI-Schätzung, editierbar, lokal gespeichert) | Feld „Estimate (h)“ ×60 | Feld |
| `status` | offen/erledigt | Project-Status + Issue-Zustand | offen/erledigt |
| `container` | Liste (Farbe) | Repo + Project | „Lokal“ |
| `url` | – | Issue-URL | – |
| `version` | `lastModifiedDate` | Issue `updatedAt` + Item `updatedAt` | SwiftData-Änderungszähler |

Felder, die ein Project nicht hat (z. B. keine Priority-Spalte), bleiben leer und werden im Bearbeiten-Sheet ausgeblendet.

## 5. GitHub

**Login (Device Flow):**

1. Einmalige Einrichtung durch dich: eine OAuth-App unter github.com/settings/developers anlegen und dort „Enable Device Flow“ aktivieren. Die Client-ID ist kein Geheimnis und liegt in `app/Config/GitHub.xcconfig`. Ein Client-Secret wird für den Device Flow nicht gebraucht.
2. Die App fordert einen Gerätecode mit `scope=repo project` an, zeigt den Benutzercode an und öffnet `github.com/login/device`.
3. Die App fragt den Token im vorgegebenen Intervall ab und beachtet `slow_down`, `authorization_pending`, `expired_token` und `access_denied`.
4. Der Token liegt im Schlüsselbund (`AfterFirstUnlockThisDeviceOnly`).
5. Ein-Klick-Abmeldung löscht den lokalen Token. Hinweis in der App: vollständig widerrufen auf github.com unter Settings → Applications.

**Lesen:**
- GraphQL `viewer.projectsV2(first: 20, query: "is:open")` → Items mit Feldwerten (Status, Priority, Due date, Estimate) und verknüpftem Issue (Titel, Repo, Zustand, Assignees, `updatedAt`).
- Gezeigt werden nur Issues, die **dir zugewiesen** sind und deren Issue offen ist. Draft-Items und Pull Requests erscheinen nicht.
- Die Paginierung folgt den Cursors. Cache in SwiftData, „zuletzt aktualisiert“ wird angezeigt.

**Schreiben:**
- Issue-Felder (Titel, Text, Labels, Schließen/Wiedereröffnen, Kommentar) über REST.
- Project-Felder (Due date, Priority, Estimate, Status) über die GraphQL-Mutation `updateProjectV2ItemFieldValue`.
- „Erledigt“ = Issue schließen **und** Project-Status auf „Done“ setzen, in dieser Reihenfolge. Danach Status erneut lesen, weil Project-Workflows (z. B. „Item closed“) ihn selbst setzen können.
- „Verschieben“ (Wischen nach links) ändert nur das Due date dieses Items.

**Konfliktschutz (gilt für alle Quellen):**
- Vor jedem Schreiben lädt die App das Element neu und vergleicht `version`.
- Bei Abweichung: kein stilles Überschreiben. Ein Banner bietet „Neu laden“ oder „Trotzdem sichern“ an (siehe Mockup 3).
- Grund: t3gh und die GitHub-Weboberfläche schreiben in dieselben Projects.

**Anforderung aus Phase 1:** Ein Fine-grained PAT wird nicht mehr unterstützt. Der Token des Spikes wird nicht übernommen.

## 6. Reminders und Kalender

- Vollzugriff auf Erinnerungen und Termine. Ausgewählte Listen und Kalender kommen aus den Einstellungen. Abonnierte Kalender, Geburtstage und Feiertage sind standardmäßig aus.
- Erinnerungen lassen sich anlegen, bearbeiten (Titel, Fälligkeit, Notiz, Liste, Priorität), abhaken und wieder öffnen. Vor dem Schreiben wird `refresh()` aufgerufen und `lastModifiedDate` verglichen.
- Ganztägige Termine erscheinen als Kopfzeile in „Heute“.
- Live-Aktualisierung über `EKEventStoreChanged`.

## 7. KI-Tagesplan

**Datenschutzregel:** Termine und Aufgabentitel gehen **nur** an OpenAI, wenn du „Tag planen“ tippst. Es gibt keine automatische Planung im Hintergrund. Das steht in der Einrichtung und in den Einstellungen.

**Eingabe (JSON im Prompt):**
- Datum, aktuelle Uhrzeit, Zeitzone, Arbeitszeit, Pausen, Puffer.
- Heutige Termine (Start, Ende, Titel, ganztägig ja/nein).
- Offene Aufgaben mit Quelle, Titel, Fälligkeit, Priorität und geschätzter Dauer (falls vorhanden), maximal 40, sortiert nach Fälligkeit und Priorität.

**Ausgabe (`text.format` json_schema, strict, in Phase 1 verifiziert):**

```
DayPlan {
  blocks: [{ taskId: String, start: "HH:mm", minutes: Int, reason: String }],
  unscheduled: [{ taskId: String, reason: String }],
  risks: [String],          // z. B. „Deadline #42 wird knapp“
  estimates: [{ taskId: String, minutes: Int }]
}
```

**Prüfung nach dem Empfang (lokal, ohne KI):**
- Blöcke überlappen keine Termine und keine anderen Blöcke.
- Blöcke liegen innerhalb der Arbeitszeit, und jede `taskId` existiert.
- Ungültige Blöcke werden verworfen und unter „nicht eingeplant“ gezeigt.

**Übernahme:** Jeder Vorschlag lässt sich einzeln annehmen oder ablehnen. Der Plan liegt nur in SwiftData, Kalender und Reminders bleiben unverändert. `estimates` werden als lokale Schätzung gespeichert und sind editierbar.

**ChatGPTProvider (Anforderungen aus Phase 1 und Review):**
- Modellliste `GET /v1/models` → `models[]` mit `visibility == "list"`, Auswahl über `slug`. „Automatisch“ = das erste Modell in Server-Reihenfolge.
- Responses-Aufrufe mit `store:false`, `stream:true`, `input` als Array, `instructions` statt System-Rolle, ohne `max_output_tokens`/`temperature`. Erfolg nur bei `response.completed`.
- **Genau eine laufende Token-Erneuerung gleichzeitig.** Alle Aufrufer warten auf denselben Task (Review Important 3).
- `client_id` wird erst nach erfolgreichem Token-Tausch gespeichert.
- `invalid_grant` meldet nur auf dem Refresh-Pfad ab, nicht beim Login.
- Der Rücksprung-Server ignoriert Anfragen mit falschem `state`, statt den Login abzubrechen.
- Der Rücksprung-Server wartet auf `.ready`, bevor das Login-Sheet öffnet. Ein belegter Port wird als Fehler angezeigt.
- Die HTTP-Anfrage wird vollständig gelesen, bis `\r\n\r\n`.
- Die `nonce` wird nicht mehr gesendet, weil das ID-Token nicht ausgewertet wird. Damit entfällt eine halbe Prüfung.
- Fehlertexte für 429 `subscription_sharing_usage_limit_exceeded` und 401 `subscription_sharing_invalid_user`.

**Ausweichlösung:** Ist ChatGPT nicht angemeldet oder liefert es einen Fehler, bietet die App die Claude-API an, sofern ein Key hinterlegt ist. Anbieterwechsel nur manuell, nie automatisch.

## 8. Benachrichtigungen

- Nur für GitHub- und lokale Aufgaben mit Fälligkeit. Reminders erinnern selbst.
- Zeitpunkt: Fälligkeit minus Vorlauf (Standard 2 h). GitHub-Daten ohne Uhrzeit gelten als 18:00 Uhr Ortszeit.
- Höchstens 50 geplante Benachrichtigungen, die nächsten zuerst (iOS-Grenze: 64).
- Neu geplant werden sie beim App-Start, nach jeder Änderung und per `BGAppRefreshTask`. iOS bestimmt den Zeitpunkt des Hintergrund-Refreshs selbst, er ist also nicht garantiert.

## 9. Bildschirme

Freigegebene Mockups (`docs/superpowers/mockups/2026-11-17-phase-2-mockups.html`; im Browser öffnen):
1. **Heute:** Deadline-Banner, „Tag planen“, ganztägige Termine, Zeitleiste. Termine sind durchgezogen, KI-Vorschläge lila gestrichelt mit ✓/✕, die Begründung lässt sich aufklappen.
2. **Aufgaben:** Filter Alle/Erinnerungen/GitHub/Lokal; Abschnitte Überfällig/Heute/Diese Woche/Später/Ohne Datum; Wischen nach rechts = erledigt, nach links = verschieben; ＋ legt eine lokale Aufgabe oder eine Erinnerung an.
3. **Bearbeiten:** quellenspezifische Felder (§4) und Konflikt-Banner (§5).
4. **Einrichtung:** Erinnerungen → Kalender → „Mit GitHub anmelden“ → „Mit ChatGPT anmelden“ → Benachrichtigungen. Jeder Schritt lässt sich überspringen.
5. **Einstellungen:** Arbeitszeit, Mittagspause, Puffer, Kalender- und Listenauswahl, GitHub (Projects, Abmelden), KI (Anbieter, Modell, Abmelden), Vorlauf.

**Leer-, Fehler- und Offline-Zustände je Quelle:**

| Quelle | Leer | Kein Zugriff / nicht angemeldet | Offline / Fehler |
|---|---|---|---|
| Reminders/Kalender | „Keine Aufgaben/Termine“ | Hinweis mit Knopf „Einstellungen öffnen“ | – (lokal) |
| GitHub | „Keine zugewiesenen Issues in offenen Projects“ | Knopf „Mit GitHub anmelden“ | Cache anzeigen + „Stand: hh:mm, offline“; Schreiben gesperrt |
| ChatGPT | – | „Tag planen“ führt zur Anmeldung | Fehlertext; vorhandener Plan bleibt |

## 10. Umstieg vom Spike auf die echte App

- Im selben PR, in dem die App erstmals installiert wird, stellt `scripts/refresh-install.sh` auf `SCHEME=Tagwerk`, `BUNDLE_ID=com.melvinmng.tagwerk` und `PROJECT_DIR_NAME=app` um.
- Danach löschst du die Spike-App vom iPhone (gibt einen der drei App-Plätze frei). `spike/` bleibt bis dahin auf `main`.
- In der neuen App meldest du dich bei GitHub und ChatGPT neu an. Neue App, neuer Schlüsselbund, neue `oaiapp_`-Registrierung.

## 11. Aufteilung in Pläne

| Plan | Inhalt | Ergebnis auf dem iPhone |
|---|---|---|
| **2a** | App-Gerüst, Packages, SecureStore, Reminders/Kalender, GitHub (Device-Flow-Login, Projects lesen/schreiben, Issues anlegen, Konfliktschutz), lokale Aufgaben, Aufgaben-Tab, Bearbeiten-Sheet, Einrichtung, Einstellungen, Umstieg des Refresh-Skripts | Alle Aufgaben sehen und bearbeiten |
| **2b** | AIKit (ChatGPT/Claude), Tagesplan inkl. lokaler Prüfung, Heute-Tab, Benachrichtigungen, Hintergrund-Refresh | Tag planen lassen, Deadline-Erinnerungen |

## 12. Klärungen nach dem Builder-Check

Geprüft gegen die echten Projects (GraphQL, 2026-11-17) oder aus früheren Entscheidungen abgeleitet. Die mit *(Planer)* markierten Punkte habe ich festgelegt.

1. **Feldstruktur:** Alle offenen, eigenen Projects stammen aus derselben Vorlage: Status (Backlog/Ready/In progress/Blocked/In review/Done), Priority (P1–P5), Due date, Start date, Estimate. Die App ordnet Felder **nach Namen** zu. „Estimate (h)“ zählt in Stunden, „Estimate (MDs)“ in Personentagen zu 8 h. Fehlt ein Feld, bleibt es leer (§4). Projects mit `template == true` werden übersprungen. *(Planer)*
2. **Nur eigene Projects:** `viewer.projectsV2` liefert Projects deines Kontos. Projects von Organisationen gehören nicht zu Phase 2, sie bräuchten eine Freigabe der OAuth-App durch die Organisation. *(Planer)*
3. **Issue in mehreren Projects:** Identität ist das **Issue**, nicht das Project-Item. Es erscheint einmal. Gezeigt werden die früheste Fälligkeit und die höchste Priorität. „Erledigt“ setzt den Status in allen Projects auf „Done“. Ändert man ein Feld, fragt die App bei mehreren Projects, wo es geändert werden soll (Standard: alle). *(Planer)*
4. **GitHub-Issues anlegen:** gehört dazu (Hauptdesign §10 F1). Das ＋ bietet „Lokal“, „Erinnerung“ und „GitHub-Issue“ an. Für ein Issue wählt man Repo und Project, danach folgen `addProjectV2ItemById` und die Feldwerte, zugewiesen an dich. Meilensteine werden in Phase 2 nicht bearbeitet. *(Planer)*
5. **Status:** Als offen gilt ein Item, wenn das Issue offen ist **und** der Status nicht „Done“ lautet. Wiedereröffnen setzt den Status „Ready“, wie der Project-Workflow „Item reopened“. *(Planer)*
6. **Verschieben:** Wischen nach links öffnet die Auswahl „Morgen“, „Nächste Woche (Mo)“ und „Datum wählen …“. Bei Erinnerungen mit Uhrzeit bleibt die Uhrzeit erhalten. Gilt für alle Quellen. *(Planer)*
7. **Pausen und Puffer** sind harte Regeln der lokalen Prüfung: Ein Block in der Mittagspause oder ohne Puffer zu Terminen wird verworfen. *(Planer)*
8. **Hintergrund-Refresh** lädt GitHub neu, sofern Token und Netz verfügbar sind. Der Token ist ab dem ersten Entsperren lesbar. Sonst plant er aus dem Cache. *(Planer)*

## 13. Dem Umsetzenden überlassen

Konkrete Prompts, Ordnerstruktur innerhalb der Packages, Testaufbau, visuelle Details innerhalb der Mockups, GraphQL-Query-Zuschnitt.

## Quellen

- GitHub Docs: Managing your personal access tokens (Fine-grained-Einschränkungen) – https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/managing-your-personal-access-tokens
- GitHub Docs: Authorizing OAuth apps (Device Flow) – https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps
- GitHub Docs: Scopes for OAuth apps – https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/scopes-for-oauth-apps
- OpenAI: Sign in with ChatGPT – https://developers.openai.com/siwc
