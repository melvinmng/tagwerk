# Phase 1 – Ergebnisse des Machbarkeitstests

Stand: 2026-11-17 · Gerät: iPhone 16 Pro, iOS 27.2.1 · Signierung: Personal Team (kostenloser Apple-Account) · Xcode 27.2

## Ergebnis je Prüfung

| Prüfung | Ergebnis auf dem Gerät | Konsequenz für das Design |
|---|---|---|
| Reminders & Kalender (EventKit) | ✅ Vollzugriff; 27 offene Erinnerungen, 3 Termine; Anlegen, Abhaken und Löschen ok | §10 F1 (Bearbeiten) ist machbar. |
| Apple Health (HealthKit) | ✅ Schritte und 3 Trainings in 7 Tagen gelesen. Das kostenlose Profil enthält `com.apple.developer.healthkit`. | Training und Ernährung können direkt auf HealthKit aufsetzen. |
| ChatGPT-Abo („Sign in with ChatGPT“) | ✅ Login im iPhone-Safari-Sheet mit Rücksprung auf `127.0.0.1:1455`; 8 Modelle, `gpt-6.1-sol`. Text ok, `text.format` json_schema ok, Bild-Eingabe ok. | Hauptanbieter für Tagesplan und Mahlzeiten-Schätzung. |
| Apples lokales Modell | ✅ verfügbar, Deutsch ja, 1,4–2,7 s. „2 Brötchen mit Käse“: 350 / 280 / 220 kcal in drei Läufen, jeweils als ein Posten. | Für Kalorien **ungeeignet**: streut stark und liegt zu niedrig. Höchstens für einfache Aufgaben ohne Zahlen (z. B. Titel kürzen, Klassifizieren). |
| Claude-API | ⏭️ übersprungen (bewusst kein Key) | Bleibt Ausweichlösung, Code vorhanden. |
| GitHub (Fine-grained PAT) | ✅ Issues gelesen | Wie geplant. |

Zum Vergleich hat ChatGPT dieselbe Mahlzeit sinnvoll zerlegt: 2 Brötchen (300 kcal) und 2 Scheiben Käse (180 kcal), zusammen 480 kcal.

## Erkenntnisse und Korrekturen

1. **GitHub:** Der Issues-Endpunkt des Repos lehnt `assignee=@me` mit HTTP 422 ab. Der Login kommt deshalb zuerst über `GET /user`.
2. **ChatGPT-Modellliste:** Die Antwort hat die Form `{"models":[{"slug","display_name","visibility"}]}`, nicht `data`/`id` (Doku: `jq '[.models[] | select(.visibility == "list") | {slug, display_name}]'`).
3. **Neuinstallation per `devicectl` behält Daten:** Startzähler, Schlüsselbund-Einträge und ChatGPT-Sitzung blieben über drei Neuinstallationen erhalten.
4. **Profil-Laufzeit:** Das Profil gilt bis 2026-11-24, also genau 7 Tage.

5. **ChatGPT-Token-Erneuerung:** ok, „Token erneuert, neuer Refresh-Token gespeichert“ (der Refresh-Token rotiert wie dokumentiert).
6. **Automatische Neuinstallation im echten launchd-Kontext:** Der LaunchAgent `de.tagwerk.refresh` lief beim Laden, baute aus dem Klon außerhalb von iCloud, signierte und installierte. Exit-Code 0, kein Schlüsselbund-Dialog, `install: ok`.
7. **Profil-Wiederverwendung (behoben):** Xcode verwendet ein gespeichertes Profil weiter, solange es gültig ist. Ein Build an Tag 5 hätte also das alte Profil mit nur noch 2 Tagen Restlaufzeit eingebettet. Das Skript löscht deshalb vor jedem Build das zwischengespeicherte Profil. Fällig ist eine Neuinstallation, wenn das installierte Profil weniger als 3 Tage gültig ist. Fehler melden sich ab weniger als 2 Tagen Restlaufzeit (nach dem Review umgestellt von „Tage seit Installation“ auf „Restlaufzeit des Profils“). Test mit `--renew-profile`: Das alte Profil wurde entfernt, Xcode stellte ein neues 7-Tage-Profil aus (Ausstellung 13:11 statt 12:08 UTC), Installation ok.

## Noch offen

- Langzeitbeobachtung über 2 Wochen: Zuverlässigkeit der WLAN-Installation und der Apple-ID-Anmeldung im Hintergrund.

## Folgen für Phase 2

- KI-Anbieter: ChatGPT-Abo als Standard. Apples Modell nur für zahlenfreie Hilfsaufgaben. Claude-API als Ausweichlösung.
- Keine Blocker für Weg 1 (native App mit kostenlosem Account).

## Nachtrag Phase 2a: GitHub Device Flow (2026-11-17)

Geprüft mit der OAuth-App „Tagwerk“ (Client-ID `Ov23liLkF2p4Nh2ztZg0`, Device Flow aktiviert, ohne Client-Secret) per `curl` vom Mac. Angefordert wurde `scope=repo project offline_access`. Der Token wurde weder geloggt noch gespeichert, die lokalen Dateien sind gelöscht.

| Prüfung | Ergebnis |
|---|---|
| Gewährte Scopes (Header `X-OAuth-Scopes` von `GET /user`) | `project, repo`. `project` wird gewährt, der Ausweichweg aus Design §5 Punkt 7 entfällt. |
| `viewer.projectsV2(first: 20, query: "is:open")` | ok, 7 offene Projects mit den Feldern Status, Priority, Due date, Start date, „Estimate (h)“ |
| Laufzeit des Access-Tokens | **läuft ab**: `expires_in` 28800 (8 h), Präfix `gho_`, Header `github-authentication-token-expiration` gesetzt |
| Refresh-Token | vorhanden, `refresh_token_expires_in` 15638400 (≈ 181 Tage) |
| Erneuerung ohne Client-Secret | **ok**: `POST /login/oauth/access_token` mit `client_id`, `grant_type=refresh_token`, `refresh_token`. Neuer Access-Token mit denselben Scopes, 8 h. |
| Rotation | Der Refresh-Token rotiert. Der alte Access-Token liefert sofort 401. Ein zweiter Einsatz des alten Refresh-Tokens scheitert mit `incorrect_client_credentials` (nicht `bad_refresh_token`). |

**Folgen für Plan 2a-GitHub:**
1. Design §5 Punkt 6 gilt in der Variante „wirkt“: Die App erneuert den Token selbst, mit genau einer laufenden Erneuerung (der Refresh-Token ist nur einmal verwendbar, zwei parallele Erneuerungen melden die App ab).
2. Erneuert wird vor Ablauf (Puffer 5 min) und nach einem 401. Abgemeldet wird nur, wenn die Erneuerung selbst mit `bad_refresh_token` oder `incorrect_client_credentials` scheitert. Netzfehler melden nicht ab.
3. Access-Token, Refresh-Token und beide Ablaufzeitpunkte werden zusammen als ein Schlüsselbund-Eintrag gespeichert, damit nie ein halber Stand entsteht.
4. Offen: Ob der Ablauf von `offline_access` oder von einer Einstellung der OAuth-App kommt, ist nicht unterscheidbar. Die App fordert `offline_access` immer an und verarbeitet beide Fälle (Token mit oder ohne `expires_in`).

## Nachtrag Phase 2b: Function Calling über das ChatGPT-Abo (2026-11-17)

Geprüft auf dem iPhone mit der Spike-App, angemeldet über „Sign in with ChatGPT“ (die Sitzung aus Phase 1, danach auch eine Neuanmeldung). Die Testprobe wurde nicht committet.

| Prüfung | Ergebnis |
|---|---|
| Modell | `gpt-6.1-sol` (erstes Modell mit `visibility == "list"`) |
| Schritt 1: Responses-Aufruf mit zwei Funktionen (`create_task`, `reschedule_task`, `strict: true`), `store:false`, `stream:true` | ✅ `response.completed`. Beide Funktionen wurden **parallel** in einer Antwort aufgerufen, die Argumente entsprechen dem Schema (`{"due":"2026-11-18","priority":"P2","title":"Testaufgabe"}`, `{"task_id":"local-7","due":"2026-11-20"}`). |
| Schritt 2: zweiter Aufruf mit `function_call` und `function_call_output` im `input` (ohne `previous_response_id`, weil `store:false`) | ✅ `response.completed`. Das Modell fasst die Ergebnisse zusammen und bemerkt sogar die abweichende ID in der Test-Rückmeldung. |

**Folgen für Phase 2b:** Der KI-Assistent kann App-Funktionen aufrufen. Der Verlauf eines Gesprächs muss vollständig im `input` mitgeschickt werden, weil `store:false` keine serverseitige Fortsetzung erlaubt.

**Login auf dem Mac:** Im Mac-Browser endete die Erstregistrierung (`client_id=dynamic_agent_client`) nach der Passkey-Anmeldung mit „Signup not complete“. Auf dem iPhone funktionierten sowohl die bestehende Sitzung als auch eine Neuanmeldung. Die Ursache wird gesondert geklärt; für die App betrifft es nur Tests auf dem Mac.

## Nachtrag Phase 2b-2: Mitschnitt am iPhone (2026-11-18)

Aufgenommen mit dem DEBUG-Abschnitt „ChatGPT (Debug)“ der App nach einer Erstregistrierung über `ChatGPTLogin`. Login, Wechsel in eine 2FA-App während der Anmeldung, Abbruch mit sofortiger Neuanmeldung sowie Abmelden und erneutes Anmelden funktionierten. Anonymisierte Ausschnitte liegen als Fixtures in `app/Packages/AIKit/Tests/AIKitTests/Fixtures/`.

| Frage | Ergebnis |
|---|---|
| Modellliste | 12 Modelle, 10 mit `visibility == "list"`, erstes `gpt-6.2-sol`. Die Antwort ist rund 850 KB groß (u. a. `base_instructions` je Modell); dekodiert werden nur `slug`, `display_name`, `visibility`. |
| Form der `tools` | Flach: `{"type":"function","name","description","parameters","strict":true}`. |
| Funktionsaufrufe im Stream | Zwei parallele `function_call`-Items. Die Argumente sind in `response.output_item.done` (und `response.function_call_arguments.done`) vollständig; Argument-Deltas kamen nicht. Jedes Item hat `id` (`fc_…`) und `call_id` (`call_…`). |
| Folgeaufruf | `function_call_output` bezieht sich auf `call_id`. Es genügt, die Aufrufe als `{"type":"function_call","call_id","name","arguments"}` ohne `id` und `status` zurückzuschicken (Variante B). |
| Reasoning-Items | Keine: `reasoning_tokens` war 0, auch mit `include: ["reasoning.encrypted_content"]`. Alle drei Varianten (alle Items zurück, nur Funktionsaufrufe, mit verschlüsseltem Reasoning) endeten mit `response.completed`. Tagwerk schickt nur Nachrichten und Funktionsaufrufe zurück und ignoriert andere Item-Arten. |
| Antworttext | `message`-Item mit `content[].type == "output_text"` und `phase: "final_answer"`; Text kommt als `response.output_text.delta`. |
| Zeilen | `event:`- und `data:`-Zeilen; Leerzeilen fallen beim zeilenweisen Lesen weg. Ausgewertet werden nur `data:`-Zeilen. |
| Token-Erneuerung | Erzwungene Erneuerung ok; Access- und Refresh-Token rotieren. |
| Ungültiger Refresh-Token | HTTP 400 `{"error":"invalid_grant"}`. Die Regel „Abmelden bei OAuth-Fehlercode mit 400/401“ deckt das ab. |
| `response.completed` | Enthält u. a. `safety_identifier` (kontobezogen) und `prompt_cache_key`; beides wird nicht gespeichert oder geloggt. |

**Nicht geprüft:** die Form früherer Assistenten-Antworten im `input` eines späteren Aufrufs (mehrere Runden Chat). Tagwerk schickt sie als `{"type":"message","role":"assistant","content":[{"type":"output_text","text":…}]}`, wie es die Responses-API für eigene Ausgaben zurückgibt; das wird bei der Geräteprüfung des Assistenten bestätigt.
