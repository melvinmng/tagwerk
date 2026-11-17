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
