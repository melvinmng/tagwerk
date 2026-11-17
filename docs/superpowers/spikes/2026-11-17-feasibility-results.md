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

## Noch offen

- Token-Erneuerung (Knopf „Token-Erneuerung testen“): Ergebnis steht noch aus.
- Automatische Neuinstallation im echten launchd-Kontext (Task 5, Abnahme mit Nutzer am Mac).
- Langzeitbeobachtung über 2 Wochen: Zuverlässigkeit der WLAN-Installation und der Apple-ID-Anmeldung im Hintergrund.

## Folgen für Phase 2

- KI-Anbieter: ChatGPT-Abo als Standard. Apples Modell nur für zahlenfreie Hilfsaufgaben. Claude-API als Ausweichlösung.
- Keine Blocker für Weg 1 (native App mit kostenlosem Account).
