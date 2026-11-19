# Tagwerk – Phase 7 Design: Routinen und Gewohnheiten

Stand: 2026-11-19 · Status: **vom Nutzer am 2026-11-19 freigegeben**.

Baut auf:
- `2026-11-17-tagwerk-design.md`: §2 Anti-Ziele, §4 Rahmenbedingungen (keine Time-Sensitive Notifications, kein CloudKit), §7 Datenschutz, §9 Benachrichtigungsbudget.
- `2026-11-17-phase-2b-design.md`: §8.4 (kein KI-Aufruf ohne Tippen), §9 Benachrichtigungen.
- `2026-11-18-phase-3-design.md`: Ziele in „Erfassen“, Regel 6 (zählende Trainings ab 10 min), §11.
- `2026-11-18-phase-4-design.md`: §4.1 Snapshot, §5.5 Routen, §8 App Intents, §12 (Store bleibt außerhalb des Group-Containers).
- `2026-11-19-phase-5-shopping-notes-design.md`: gemeinsamer Notizspeicher `NoteRecord`/`NoteStore`, Notizen-Liste in „Aufgaben“ mit Herkunftszeile.

Mockup: `../mockups/2026-11-19-phase-7-routines-mockups.html` (Rahmen GO1, GA1, GF1, GH1, GH3, GR2, GS1, GS·E, GS·B, GN1, GZ1, GK1, GW1, GB1, GL2; die übrigen Rahmen zeigen verworfene Varianten). Epic: GitHub #140 mit #141 bis #146.

## 1. Absicht und Warum

Tagwerk soll die täglichen Routinen abbilden, die früher in Notion lagen: Gewohnheiten abhaken, Tagesstart, Tagesabschluss, freie Gedanken-Notiz und eine kurze Wochenreflexion.

Hintergrund aus #140 (Beobachtung des Nutzers, kein Beleg): Das Notion-System lief drei Wochen fast täglich und endete dann. Genutzt wurden die täglichen Häkchen und die freien Notizen, die Wochenreflexion kam auf zwei Einträge, die Leitfragen auf keinen. Die Abendeinträge lagen meist deutlich nach der geplanten Zeit (#142).

Daraus folgt die Leitlinie dieses Designs:
- Der Mindestweg pro Tag sind wenige Tipps. Jedes Textfeld ist optional, nichts blockiert die App.
- Was die App schon weiß (Wasser, Training, Schritte), hakt sich selbst ab.
- Erinnerungen kommen **vor** dem Zeitpunkt, nicht als Checkliste danach.
- Vorhandenes wird wiederverwendet: „Erfassen“, Wochenrückblick, Benachrichtigungen, Widget, Kurzbefehle, Aktionskarten.

Ob die neue Form länger als drei Wochen hält, ist nicht belegt und zeigt erst die Nutzung. Die Mockups zeigen Bedienwege, keine Wirkung.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- **#141 Gewohnheiten:** anlegen, sortieren, pausieren, täglich abhaken; Quote über 7 und 30 Tage, laufende Serie; Rhythmus „Tage pro Woche 1–7“; automatische Erfüllung aus Wasserziel, Training und Schrittziel; Tageslicht hinter einem Geräte-Spike; Zähler „✓ 3 von 5“ in der vorhandenen Zeile von „Planen“ und im Widget „Heute“; Siri-Kurzbefehl „Gewohnheit abhaken“.
- **#142 Tagesabschluss:** Zielschlafzeit, frei konfigurierbare Abend-Checkliste mit Zeitankern relativ zur Schlafzeit, eine Mitteilung je Zeitanker (höchstens vier), kurzer Rückblick auf den Tag.
- **#145 Tagesstart:** bis zu drei Dankbarkeits-Einträge, Tagesfokus (ein bis drei Aufgaben von heute) als Karte mit Stern in „Planen“, Überblick, optionale Erinnerung.
- **#143 Gedanken-Notiz:** freier Text oder Sprache im Tagesstart und Tagesabschluss, gespeichert im gemeinsamen `NoteRecord`-Speicher aus Phase 5, sichtbar in der Notizen-Liste in „Aufgaben“; Vorschläge als Aktionskarten im selben Blatt, nur nach Zustimmung und nur auf Tippen.
- **#144 Wochenreflexion:** drei neue Abschnitte im vorhandenen Wochenrückblick (Gewohnheiten, Reflexion, Neue Woche planen), je Woche gespeichert.
- **#146 Leitfragen:** optionale Vorlage, die sechs Fragen als Text in die Gedanken-Notiz setzt.
- Neue Einstellungsseite „Routinen“, Deeplinks `tagwerk://routine/…`, alle Texte deutsch und englisch.

**Nicht-Ziele (Phase 7)**
- Neuer Tab oder eigener Bereich „Routinen“ (übergreifend entschieden: Tab-Leiste bleibt Planen, Aufgaben, Erfassen, Einstellungen).
- Aktionen in Mitteilungen („Abgehakt“, „In 10 min“; GS3) und antippbares Widget (GB2). Beides erst nach je einem Geräte-Spike als Folgeaufgabe.
- Rhythmus mit festen Wochentagen (GR3), Erinnerungen je Gewohnheit, Mengen-Gewohnheiten („8 Gläser“), Diagramme über Monate.
- Eigenes Formular und eigene Liste für Leitfragen (GL3).
- Tagesfokus für andere Tage als heute; Fokus-Marke im Tab „Aufgaben“.
- Blatt, das sich von selbst öffnet (GA3).
- KI über Gewohnheiten, Dankbarkeit oder Wochenreflexion; Werkzeuge des Assistenten für Routinen; Gedanken-Notiz im Assistenten-Chat (GK2).
- iCloud-Abgleich, Export, Sicherung der Routinedaten.

**Anti-Ziele**
- Der tägliche Aufwand wächst über wenige Tipps hinaus oder ein Pflichtfeld blockiert einen Schritt.
- Notiztext verlässt das iPhone ohne Zustimmung und ohne Tippen auf „Vorschläge holen“ (Hauptdesign §2, 2b §8.4).
- Dankbarkeits-Einträge, Wochenreflexion oder aus Health abgeleitete Zustände gelangen an ChatGPT, in das Widget auf dem Sperrbildschirm oder in Siri-Antworten.
- Routine-Erinnerungen verdrängen Deadline-Erinnerungen aus dem Benachrichtigungsplan.
- „Planen“ wird über dem Ablauf länger als heute plus **ein** Element.
- Gewohnheiten oder Checklistenpunkte werden zur zweiten Aufgabenquelle (Hauptdesign §2). Aufgaben aus einer Notiz entstehen immer in den vorhandenen Quellen.
- Datenverlust durch einen Store-Umzug für das Widget (Phase 4 §2).

## 3. Einschränkungen

**Im Quelltext geprüft (Stand dieses Worktrees)**

| Bereich | Befund | Stelle |
|---|---|---|
| Planen | Über dem Ablauf stehen vier Elemente: Erfassen-Zeile, Deadline-Karte, Deadline-Vorschlag, Kapazitätskarte | `DayView.swift:67–71` |
| Planen | Die Zeile unter dem Datum zeigt nur in der Tagesansicht von heute und öffnet „Erfassen“ | `PlanHeader.swift:113–132`, `CaptureModel.swift:221–226` |
| Planen | Die Abendzeile „Morgen planen“ hängt an `eveningEntry` und existiert nur, wenn der Arbeitstag vorbei ist und ein Planungstag folgt | `DayView.swift:217–220`, `PlanningModel.swift:1215, 1284–1290` |
| Erfassen | Aufbau: Tagesnavigation, Tageswerte, Zeile „Wochenrückblick“, Schnellerfassung, danach die Listen | `CaptureView.swift:36–67` |
| Tab-Leiste, Blätter | Vier Tabs; Blätter und Routen werden in `RootView` geöffnet | `RootView.swift:26–55, 135–145` |
| Routen | `AppRoute` kennt fünf Ziele mit englischen Pfaden; Links navigieren nur | `AppRoute.swift:3–10` |
| Benachrichtigungen | Ziel einer Mitteilung ist nur Aufgabe oder Termin | `NotificationPlan.swift:6–9`, `NotificationNavigator.swift:7–14` |
| Benachrichtigungen | Nur einmalige Auslöser (`repeats: false`) | `NotificationCenterClient.swift:98` |
| Benachrichtigungen | Budget 50 von 64; jeder Lauf betrachtet **alle** Anfragen mit Präfix `tagwerk.` als eigene, zählt behaltene gegen das Budget und entfernt nicht mehr gewünschte | `NotificationScheduler.swift:25, 103, 116–127, 146–147` |
| Speicher | Ein SwiftData-Store, lokal, bewusst nicht im Group-Container | `ModelContainerFactory.swift:5–22` |
| Schemaregel | Spätere Attribute brauchen einen Standardwert oder sind optional | `AppSettings.swift:6` |
| Ziele | Wasserziel, Trainingsminuten je Woche, Schrittziel | `AppSettings.swift:57, 62, 64` |
| Daten für die automatische Erfüllung | Getränke je Tag, Trainings je Zeitraum lokal; fremde Trainings und Tagesschritte je Zeitraum aus Health | `IntakeStore.swift:45, 52`, `HealthStoring.swift:18, 26` |
| Zählende Trainings | ab 10 Minuten | `Intake.swift:240` |
| Health | Lesetypen sind Trainings und Schritte; ein neuer Typ darf nicht in `coreReadTypes`, sonst gilt der Zugriff für alle als „neu anfragen“ | `HealthKitStore.swift:33–40` |
| Zustimmung | Vorbild: einmaliges Blatt und Schalter für die Mahlzeiten-Schätzung, Standard aus | `MealConsentSheet.swift:4–38`, `CaptureSettingsView.swift:31–41`, `AppSettings.swift:70` |
| Aktionskarten | `ActionCardView` mit „Verwerfen“/„Bestätigen“; Kartentexte in `AssistantModel.describe` | `ChatView.swift:267–326`, `AssistantModel.swift:397–488` |
| KI-Funktionen | `create_task`, `reschedule_task`, `assign_to_day`, `create_time_block`, `update_event` vorhanden, schreibend nur nach Bestätigung | `AppTools+Definitions.swift:52–89`, `AppTools.swift:13, 33` |
| Gesprächsablauf | `Conversation.confirm` führt aus und startet danach eine weitere Runde mit dem ganzen Verlauf | `Conversation.swift:129–137` |
| Sprache | `VoiceInputModel` ist an ein Nachrichtenfeld mit Sende-Aktion gebunden | `VoiceInputModel.swift:8–19` |
| Wochenrückblick | Liste mit Abschnitten, blättert in die Vergangenheit; Daten aus `WeekReview.make` | `WeekReviewView.swift:11–48`, `WeekReview.swift:64–67` |
| Kurzbefehle | „Wasser erfassen“ schreibt im Hintergrund in den App-Store und aktualisiert das Widget | `TagwerkIntents.swift:19–35`, `IntentServices.swift:19–29` |
| Widget | Liest nur die Snapshot-Datei; im Hintergrund ohne geladene Quellen wird nur der Tageswert ersetzt | `WidgetSnapshot.swift:53–72`, `AppEnvironment.swift:374–385` |
| Neue Aufgabe | `NewTaskSheet(model:)` ohne Vorbelegung | `NewTaskSheet.swift:6`, `TaskListView.swift:112` |

**Aus Dokumenten übernommen**
- Kostenloser Apple-Account: keine Time-Sensitive Notifications, kein CloudKit, kein Push (Hauptdesign §4). Routine-Mitteilungen sind normale lokale Mitteilungen und können von einem Fokus-Modus stummgeschaltet werden.
- Die App wird alle fünf Tage neu installiert (Hauptdesign §10). Drüberinstallieren behält Daten.

**Annahmen (nicht geprüft)**
- `HKQuantityTypeIdentifier.timeInDaylight` liefert auf der Apple Watch des Nutzers Tageswerte. Der Nutzer trägt die Watch nur gelegentlich.
- Täglich wiederholende Auslöser überleben Neustart und Drüberinstallieren und brauchen keinen App-Start.
- Phase 5 wird so gebaut, wie ihr Design `NoteRecord` und die Notizen-Liste beschreibt (§5.4, §7.8).
- Die Spracheingabe lässt sich außerhalb des Assistenten in einem mehrzeiligen Textfeld betreiben.

## 4. Ansätze

Je Frage die betrachteten Varianten, die Abwägung und die Wahl des Nutzers. Empfehlung und Wahl stimmen überein, wo nichts anderes steht.

| Nr. | Frage | Varianten und Abwägung | Entscheidung |
|---|---|---|---|
| 1 | Ort der Gewohnheiten | **GO1** Abschnitt in „Erfassen“ plus Zähler in der Planen-Zeile: nutzt Tagesnavigation und Nähe zu Wasser/Training, kostet einen Tab-Wechsel. GO2 Karte in „Planen“: fünftes Element über dem Ablauf, kein Platz für Quoten. GO3 eigener Tab: übergreifend ausgeschlossen | **GO1** |
| 2 | Auslöser für Tagesstart und Tagesabschluss | **GA1** Karte bzw. Zeile in „Planen“ plus Mitteilung: ruhig, nicht zu übersehen. GA2 nur Mitteilung: ohne Erlaubnis kein Einstieg. GA3 Blatt von selbst: blockiert den eigentlichen Grund, die App zu öffnen | **GA1** |
| 3 | Tagesfokus in „Planen“ | **GF1** Karte (mit Stern an den Zeilen): immer sichtbar, abhakbar. GF2 nur Stern: im Stundenraster oft außerhalb des Bildschirms. GF3 eine Zeile: nicht abhakbar | **GF1** |
| 4 | Automatische Erfüllung | **GH1** Häkchen setzt sich selbst: null Tipps, stimmt auch für Tage ohne App-Start. GH2 nur Vorschlag: ein Tipp je Tag, den die Daten schon beantworten. GH3 mit Tageslicht: neue Health-Freigabe, Wert nur mit Watch | **GH1** für Wasser, Training, Schritte. Tageslicht: automatisch nur, wenn Daten vorliegen, sonst von Hand; hinter einem Geräte-Spike |
| 5 | Rhythmus | GR1 nur täglich: Quote für Training irreführend. **GR2** Tage pro Woche 1–7: ein Feld, passt zum Wochenziel, zwei Serienbegriffe. GR3 feste Wochentage: passt nicht zu Health-Trainings | **GR2** |
| 6 | Erinnerungen am Abend | **GS1** eine Mitteilung je Zeitanker (höchstens vier): entspricht #142, bis zu vier Mitteilungen. GS2 eine Mitteilung: der späte Punkt bleibt ohne Signal. GS3 mit Aktionen: neue Technik, ungeprüft | **GS1**; Aktionen später |
| 7 | Speicher der Gedanken-Notiz | **GN1** gemeinsamer Notizspeicher mit Phase 5: ein Datentyp, auffindbar. GN2 Feld im Tageseintrag: nur tageweise auffindbar, spätere Migration | **GN1**; Notizen erscheinen in der Notizen-Liste in „Aufgaben“ mit Herkunft |
| 8 | Zustimmung für ChatGPT | **GZ1** Schalter (Standard aus) plus einmaliges Blatt. GZ2 jedes Mal fragen: wird blind bestätigt. GZ3 nur Schalter: Funktion unsichtbar | **GZ1**; als Kontext gehen die offenen Aufgaben und Termine der nächsten 7 Tage mit (§9.2, Entscheidung des Nutzers vom 2026-11-19) |
| 9 | Ort der Aktionskarten | **GK1** im Notizblatt: kein Wechsel, Notiz landet nicht im Chatverlauf. GK2 im Assistenten: Notiztext ginge bei jeder weiteren Nachricht erneut mit | **GK1** |
| 10 | Wochenreflexion | **GW1** Abschnitte im Rückblick: kein weiterer Tipp, frühere Antworten direkt lesbar. GW2 eigenes Blatt: ein Tipp mehr | **GW1** |
| 11 | Widget und Kurzbefehl | **GB1** Kurzbefehl plus Zähler im Widget: gleiche Technik wie „Wasser erfassen“. GB2 antippbares Widget: Knopf liefe im Widget-Prozess ohne Store | **GB1**; GB2 erst nach Spike |
| 12 | Leitfragen (#146) | GL1 zurückstellen (Empfehlung: im alten System nie genutzt). **GL2** Vorlage in der Notiz, etwa 2 h. GL3 eigenes Formular, etwa 6 h | **GL2 – Abweichung von der Empfehlung GL1.** Der Nutzer will #146 jetzt in der kleinen Form |
| 13 | Reihenfolge | #141 zuerst (meistgenutzt, keine Abhängigkeit), #142 vor #145 (legt den Tageseintrag an), Notiz danach | **#141 → #142 → #145 → #143 → #144 → #146** |

Architektur-Ansatz für die Vorschläge aus der Notiz (Entscheidung 9): betrachtet wurden (a) ein zweites `Conversation`-Objekt und (b) ein eigenes kleines Modell mit genau einem Aufruf. (a) schickt nach jeder Bestätigung den Verlauf samt Notiztext erneut (`Conversation.swift:129–137`). Das widerspricht „nur diese eine Notiz, nur auf Tippen“. Gewählt ist (b), siehe §9.

## 5. Daten

Alle neuen Typen liegen im vorhandenen SwiftData-Store und kommen in `ModelContainerFactory.schema`. Jedes Feld hat einen Standardwert oder ist optional. Es gibt keinen Store-Umzug.

### 5.1 Gewohnheiten

```
HabitRecord {
  id: UUID
  name: String                 // höchstens 40 Zeichen
  symbol: String               // SF-Symbol-Name aus einer festen Auswahl
  order: Int
  source: String               // "manual" | "water" | "workout" | "steps" | "daylight"
  daysPerWeek: Int = 7         // 1...7
  daylightMinutes: Int = 20    // Schwelle, nur für "daylight"
  startYear, startMonth, startDay: Int   // "Zählt ab", Standard: Tag des Anlegens
  pausedSinceKey: String?      // "YYYY-MM-DD", gesetzt solange pausiert
  pausesData: Data?            // JSON [{from, to}] abgeschlossener Pausen
  createdAt: Date
}

HabitCheckRecord {             // nur Handhäkchen
  habitID: UUID
  year, month, day: Int
  checkedAt: Date
}
```

- Automatische Häkchen werden berechnet und nie gespeichert. Ein Handhäkchen wird gespeichert.
- Löschen einer Gewohnheit entfernt auch ihre Handhäkchen (nach Rückfrage).

### 5.2 Tageseintrag, Abend-Checkliste, Fokus

```
RoutineDayRecord {
  dayKey: String (eindeutig, "YYYY-MM-DD")
  year, month, day: Int
  gratitudeData: Data?          // JSON [String], höchstens 3
  startCompletedAt: Date?
  startDismissed: Bool = false  // "✕" auf der Karte in Planen
  closeCompletedAt: Date?
  checkedItemIDsData: Data?     // JSON [UUID] der abgehakten Checklistenpunkte
}

EveningChecklistItemRecord {
  id: UUID
  title: String                 // höchstens 40 Zeichen
  order: Int
  offsetMinutes: Int?           // Minuten vor der Schlafzeit; nil = ohne Erinnerung
  createdAt: Date
}

FocusMarkRecord {
  taskKey: String               // TaskID.key
  year, month, day: Int
  order: Int
  doneAt: Date?                 // gesetzt, sobald die App die Aufgabe als erledigt sieht
  createdAt: Date
}
```

- `dayKey` ist eindeutig wie bei `DayOverrideRecord` (`DayAssignment.swift:34`). Diese Typen bleiben lokal; die iCloud-Vorgabe „kein eindeutiges Feld“ gilt nur für `NoteRecord`.
- `FocusMarkRecord` hat bewusst kein eindeutiges Feld: Dieselbe Aufgabe darf an mehreren Tagen Fokus sein.

### 5.3 Wochenreflexion

```
WeekReflectionRecord {
  weekKey: String (eindeutig, Montag der Woche als "YYYY-MM-DD")
  wentWell: String = ""
  burdens: String = ""
  plannedAppointments: Bool = false
  plannedHabits: Bool = false
  plannedTasks: Bool = false
  updatedAt: Date
}
```

### 5.4 Gedanken-Notiz (gemeinsamer Speicher aus Phase 5)

Phase 7 legt keinen eigenen Notiztyp an. Sie nutzt `NoteRecord` und `NoteStore` aus dem Phase-5-Design (§„Daten“ dort, gelesen am 2026-11-19; Phase 5 ist noch nicht gebaut):

| Feld (Phase 5) | Nutzung in Phase 7 |
|---|---|
| `id`, Text, angelegt, geändert | unverändert |
| `kindRaw` (`free`, `morning`, `evening`) | Phase 7 schreibt `morning` (Tagesstart) und `evening` (Tagesabschluss) |
| `dayKey` („YYYY-MM-DD“) | Tag des Tagesstarts bzw. Tagesabschlusses (abends nach Regel 10) |
| `wasDictated` | gesetzt, wenn Text aus einer Aufnahme stammt |
| `processedAt` | Zeitpunkt des letzten „Vorschläge holen“ |
| `isPinned` | von Phase 7 nicht gesetzt |

Phase 7 ergänzt ein Feld mit Standardwert: `derivedActionCount: Int = 0` (ausgeführte Vorschläge und von Hand angelegte Aufgaben, für „2 Aufgaben daraus“). Geschrieben wird nur über `NoteStore`. `NoteRecord` hat kein eindeutiges Feld; dass es je Tag und Art höchstens eine Gedanken-Notiz gibt, sichert der Code (vor dem Anlegen suchen).

### 5.5 Neue Felder in `AppSettings`

| Feld | Standard | Zweck |
|---|---|---|
| `bedtimeMinutes` | `1380` (23:00) | Zielschlafzeit, Minuten nach Mitternacht |
| `eveningRemindersEnabled` | `true` | Mitteilungen der Abend-Checkliste |
| `morningReminderEnabled` | `false` | Erinnerung an den Tagesstart |
| `morningReminderMinutes` | `450` (07:30) | Uhrzeit dieser Erinnerung |
| `showsRoutinesInPlan` | `true` | Karte „Tagesstart/Fokus“ und Zeile „Tagesabschluss“ in „Planen“ |
| `noteSuggestionConsent` | `false` | „Notizen an ChatGPT senden“ |

### 5.6 Snapshot

`SnapshotDay` bekommt ein optionales Feld `habits: SnapshotHabits? { done: Int, total: Int }`. Nur heute trägt es. Ältere Dateien bleiben lesbar, `schemaVersion` bleibt 1 (gleiches Vorgehen wie bei den Schritten, Phase 4 §13). Der Snapshot enthält keine Namen von Gewohnheiten, keine Dankbarkeit, keine Notizen.

## 6. Regeln (reine Logik in `TagwerkCore`, testbar)

Neue Dateien: `HabitRules.swift`, `RoutineSchedule.swift`, `NoteTemplate.swift`.

1. **Aktiv an Tag d:** `startDay ≤ d`, d liegt in keiner Pause, d ist nicht in der Zukunft. Nur aktive Gewohnheiten erscheinen in der Tagesliste.
2. **Erfüllt an Tag d:** Es gibt ein Handhäkchen für d, **oder** die Quelle ist erfüllt:
   - `water`: Summe der Getränke an d ≥ Wasserziel (Ziel > 0).
   - `workout`: mindestens ein Training ab 10 Minuten an d, aus Tagwerk oder Health.
   - `steps`: Tagesschritte an d ≥ Schrittziel (Ziel > 0).
   - `daylight`: Zeit bei Tageslicht an d ≥ `daylightMinutes`. Ohne Wert gilt die Quelle als nicht erfüllt.
   - Fehlt ein Wert (kein Health-Zugriff, Ziel 0, keine Watch), bleibt die Gewohnheit offen und lässt sich von Hand abhaken.
3. **Zieltage** eines Zeitraums: zählende Tage × `daysPerWeek` ÷ 7. Zählende Tage sind aktive Tage des Zeitraums; heute zählt erst mit, wenn heute erfüllt ist.
4. **Quote:** erfüllte Tage ÷ Zieltage, höchstens 100 %. Ohne zählende Tage „–“.
5. **Serie bei 7 Tagen pro Woche:** aufeinanderfolgende erfüllte Tage bis gestern, plus heute, falls erfüllt. Pausierte Tage werden übersprungen. Heute bricht die Serie erst nach Tagesende.
6. **Serie bei weniger als 7:** aufeinanderfolgende Kalenderwochen (Mo–So) mit erreichtem Wochenziel. Wochenziel = `daysPerWeek`, in Wochen mit weniger als 7 zählenden Tagen anteilig gerundet, mindestens 1. Wochen ohne zählenden Tag werden übersprungen. Die laufende Woche zählt, sobald das Ziel erreicht ist, und bricht die Serie vorher nicht.
7. **Rückblick-Fenster:** Alle Berechnungen lesen höchstens 90 Tage zurück. Eine längere Serie zeigt „90+“ Tage bzw. „12+“ Wochen.
8. **Zähler „✓ e von n“:** n = heute aktive Gewohnheiten. e = davon heute erfüllt; eine Gewohnheit mit weniger als 7 Tagen pro Woche zählt auch dann, wenn ihr Wochenziel schon erreicht ist. Ohne aktive Gewohnheit gibt es keinen Zähler.
9. **Zeitanker:** Uhrzeit = Zielschlafzeit − `offsetMinutes`, modulo 24 h. Eine Schlafzeit nach Mitternacht ist erlaubt.
10. **Abendgrenze 04:00:** Der Tagesabschluss und seine Checkliste gehören zwischen 00:00 und 03:59 zum Vortag. Gewohnheiten folgen dem Kalendertag.
11. **Sichtbarkeit in „Planen“** (nur Tagesansicht von heute, nur mit `showsRoutinesInPlan`):
    - Tagesstart-Karte: 04:00 bis 12:00, solange der Tagesstart weder abgeschlossen noch ausgeblendet ist.
    - Fokus-Karte: sobald ein Fokus gewählt ist und mindestens eine Fokus-Aufgabe offen ist.
    - Zeile „Tagesabschluss“: ab dem frühesten Zeitanker, ohne Anker ab 90 Minuten vor der Schlafzeit, bis 03:59; nach „Fertig“ mit Häkchen.
12. **Fokus:** höchstens drei Marken je Tag. Wählbar sind die Aufgaben von heute (für heute geplant, heute fällig oder mit Zeitblock heute), ohne wiederkehrende Vorkommen. Vorsortierung: P1 und heute fällige zuerst.
13. **Leitfragen-Vorlage:** sechs Fragen als Textzeilen, jeweils gefolgt von einer Leerzeile (§7.7).
14. **Tagesrückblick „Aufgaben erledigt e von n“:** n = Aufgaben von heute nach Regel 12 (hier einschließlich erledigter), e = davon erledigt. Wiederkehrende Vorkommen zählen nicht mit.

Die Werte berechnet ein eigenes App-Modell (`HabitsModel`) aus `IntakeStore` und `HealthStoring`. Es lädt mit dem Erfassen-Modell neu und nach jeder Änderung an Getränken, Trainings oder Häkchen. Health wird je Lauf höchstens mit drei Abfragen über das 90-Tage-Fenster gelesen (fremde Trainings, Tagesschritte, nach dem Spike Tageslicht).

## 7. Oberfläche

### 7.1 „Erfassen“ (GO1, GH1)

Reihenfolge der Abschnitte: Tagesnavigation mit Tageswerten und „Wochenrückblick“ (unverändert), Schnellerfassung (unverändert), Health-Karte (unverändert), **Routinen**, **Gewohnheiten**, danach Mahlzeiten, Getränke, Trainings.

- **Abschnitt „Routinen“:** zwei Zeilen für den gezeigten Tag.
  - „Tagesstart“: offen „Fokus wählen“, erledigt „✓ 07:42 · Fokus: Exposé Kapitel 2“.
  - „Tagesabschluss“: offen „Schlafzeit 23:00 · Checkliste 0 von 3“, erledigt „✓ 22:10“.
  - Tippen öffnet das jeweilige Blatt für den gezeigten Tag. So bleiben vergangene Tage nachlesbar und nachtragbar.
- **Abschnitt „Gewohnheiten“:** Kopf „Gewohnheiten · 3 von 5 · Bearbeiten“.
  - Zeile: Häkchen, Symbol, Name, Unterzeile.
  - Unterzeile bei 7 Tagen pro Woche: „7 Tage 5/7 · 30 Tage 73 % · Serie 3“.
  - Unterzeile bei weniger: „Diese Woche 2 von 3 · 30 Tage 80 % · Serie 4 Wochen“.
  - Automatisch erfüllt: Marke „automatisch“ und die Quelle, z. B. „2,1 l von 2,0 l“ oder „Laufen 42 min aus Health“. Tippen zeigt die Quelle und ändert nichts.
  - Offene Zeile: Tippen hakt für den gezeigten Tag ab, erneutes Tippen nimmt das Handhäkchen zurück.
  - Vergangene Tage lassen sich nachtragen, künftige nicht.
  - Ohne Gewohnheiten: Zeile „Gewohnheit anlegen“.
- **„Bearbeiten“** öffnet die Liste aller Gewohnheiten (auch pausierte) mit Sortieren, Anlegen und Öffnen des Blatts „Gewohnheit“.

### 7.2 Blatt „Gewohnheit“ (GH3, GR2)

- Name, Symbol (feste Auswahl von SF Symbols).
- „Erfüllt durch“: Von Hand abhaken, Wasserziel erreicht, Training erfasst, Schrittziel erreicht. „Zeit bei Tageslicht“ erscheint erst nach bestandenem Spike (§15.1), dann mit Schwelle 5–120 min und dem Hinweis aus GH3.
- „Tage pro Woche“ 1–7 mit dem Fußtext aus GR2.
- „Zählt ab“ (Datum, Standard heute; frühestens 90 Tage zurück).
- „Pausieren“ (Schalter), „Gewohnheit löschen“ (mit Rückfrage).
- Jede automatische Quelle kann höchstens eine Gewohnheit haben; vergebene Quellen sind in der Auswahl deaktiviert.
- Höchstens zehn nicht pausierte Gewohnheiten; danach ist „Anlegen“ deaktiviert mit Hinweis.

### 7.3 „Planen“ (GO1 dazu, GA1, GF1)

- **Zeile unter dem Datum:** „🔥 ~1.240 / 2.300 kcal · 2,1 l · ✓ 3 von 5 ›“. Der Zähler hängt am Ende. Tippen öffnet „Erfassen“ wie bisher.
- **Ein neues Element** zwischen dieser Zeile und der Deadline-Karte, die Routine-Karte. Sie hat zwei Zustände und zeigt nie beide:
  - *Tagesstart* (GA1 Karte): „☀︎ Tagesstart · Fokus wählen · 3 Termine, 5 Aufgaben“ mit „Starten“ und „✕“. Einzeilig.
  - *Fokus heute* (GF1): Kopf „Fokus heute · 1 von 2 · Ändern“, darunter höchstens drei Zeilen mit Kreis zum Abhaken, Titel, Zeitblock (falls vorhanden) und Stern. Erledigte Zeilen sind durchgestrichen. „Ändern“ öffnet das Blatt „Tagesstart“.
  - Nach dem Tagesstart ersetzt die Fokus-Karte die Tagesstart-Karte. Ist kein Fokus gewählt oder alles erledigt, entfällt das Element.
- **Stern** an Fokus-Aufgaben in den Aufgabenabschnitten und an ihren Zeitblöcken in „Planen“. Das Kontextmenü einer Aufgabe in der Tagesansicht von heute bekommt „Als Fokus markieren“ bzw. „Fokus entfernen“.
- **Abends** (GA1 abends): Die Kapazitätskarte bekommt eine Zeile „🛏 Tagesabschluss · Schlafzeit 23:00 · Checkliste 0 von 3 ›“, unabhängig von „Morgen planen“. Kein neues Element.
- Abhaken in der Fokus-Karte erledigt die Aufgabe über den vorhandenen Weg in ihrer Quelle. Die Fokus-Marke selbst schreibt nie in eine Quelle.

### 7.4 Blatt „Tagesstart“ (GA1 Blatt)

Ein Blatt, alles optional, „Fertig“ rechts oben.
- **Dankbar für:** ein Feld sichtbar; das zweite und dritte erscheinen nach Eingabe.
- **Tagesfokus · 1 von 3 gewählt:** drei vorsortierte Aufgaben mit Stern, darunter „Alle n Aufgaben von heute zeigen“.
- **Heute:** „3 Termine · 5 Aufgaben · 3 h 30 frei“ (aus dem Tagesplan).
- **Gedanken:** Notizfeld mit Mikrofon (§7.6).
- „Fertig“ speichert und markiert den Tagesstart als abgeschlossen, auch ohne Eingabe. Schließen durch Wischen speichert die Eingaben, schließt aber nicht ab.
- Für vergangene Tage ist der Fokus nur lesbar; Dankbarkeit und Notiz bleiben bearbeitbar.

### 7.5 Blatt „Tagesabschluss“ (GS·B)

- **Heute:** „Aufgaben erledigt 4 von 6“ (Regel 14), „Gewohnheiten 3 von 5“ (Regel 8), „★ Fokus 1 von 2“. Die Fokus-Zeile fehlt ohne Fokus.
- **Abend-Checkliste · Schlafzeit 23:00:** die Punkte mit ihrer Uhrzeit zum Abhaken. Ohne Punkte: „Punkte in den Einstellungen anlegen“.
- **Gedanken:** Notizfeld mit Mikrofon (§7.6).
- **„☾ Morgen planen · Fr. 20. Nov.“:** springt wie die vorhandene Abendzeile auf den nächsten Planungstag. Fehlt ein solcher, fehlt die Zeile.
- **Sonntags:** Zeile „Wochenreflexion ›“, öffnet den Wochenrückblick.
- „Fertig“ speichert und markiert den Tagesabschluss als abgeschlossen.

### 7.6 Gedanken-Notiz im Blatt (GK1, GZ1, GL2)

- Mehrzeiliges Textfeld „Was geht dir durch den Kopf?“. Der Text wird beim Tippen (entprellt) und beim Schließen in `NoteRecord` gespeichert, also bevor irgendetwas gesendet werden kann. Ein leerer Text löscht den Datensatz.
- Je Tag und Art gibt es höchstens eine Gedanken-Notiz; das Blatt bearbeitet sie.
- **Mikrofon:** Aufnahme über die vorhandene Erkennung auf dem Gerät. Der erkannte Text wird an der Schreibmarke eingefügt und nie gesendet. Es gelten `voiceInputEnabled` und die einmalige Erklärung.
- **Unter dem Feld**, sobald Text vorhanden ist:
  - „✦ Vorschläge holen“ (nur bei ChatGPT-Anmeldung; sonst ein Hinweis auf Einstellungen › KI).
  - „＋ Als Aufgabe anlegen“: öffnet das vorhandene Blatt „Neue Aufgabe“ mit der ersten Zeile der Notiz als Titel. Der Nutzer wählt Quelle und Felder wie sonst.
  - Fußtext: „‚Vorschläge holen‘ sendet diese Notiz an ChatGPT. Nichts wird ohne deine Bestätigung geändert.“
- **Karten** (GK1 Karten): Abschnitt „n Vorschläge aus der Notiz“ mit `ActionCardView`, darunter „Alle bestätigen (n)“ ab zwei offenen Karten. Zustände wie im Assistenten: vorgeschlagen, wird ausgeführt, ausgeführt mit Uhrzeit, verworfen, Fehler.
- Ohne Vorschlag: „Keine Vorschläge aus dieser Notiz.“ Bei einem Fehler: Meldung mit „Erneut versuchen“.
- Offene Karten gelten nur, solange das Blatt offen ist.

### 7.7 Leitfragen (GL2)

- Im Kopf des Abschnitts „Gedanken“ steht „Leitfragen einfügen“.
- Der Knopf hängt an den vorhandenen Text an: „Was war mein Ziel?“, „Was hat geholfen?“, „Was hat abgehalten?“, „Erfahrungen mit anderen“, „Meine eigene Rolle“, „Nächste Schritte“, jeweils mit Leerzeile.
- Der Knopf fehlt, wenn die Notiz die erste Frage schon enthält.
- Gespeichert wird eine normale Gedanken-Notiz. Wieder öffnen: über die Notizen-Liste in „Aufgaben“ oder über den Tag in „Erfassen“.

### 7.8 Notizen-Liste in „Aufgaben“ (GN1; Liste selbst gehört zu Phase 5)

- Phase 5 zeigt Gedanken-Notizen bereits mit Herkunft, Datum und Filter: „Tagesstart · 18.11.“ bzw. „Tagesabschluss · 18.11.“. Phase 7 ergänzt die Fußzeile um „· 2 Aufgaben daraus“ bei `derivedActionCount > 0`.
- Öffnen zeigt die Notiz im Notiz-Editor aus Phase 5. Löschen dort löscht nur die Notiz, nicht den Tageseintrag.
- Die Fußnote der Liste („… Sie werden nicht an ChatGPT gesendet.“) lautet ab Phase 7: „Notizen liegen nur auf diesem iPhone. An ChatGPT geht eine Gedanken-Notiz nur, wenn du bei ihr auf ‚Vorschläge holen‘ tippst.“ Freie Notizen (`free`) haben keinen solchen Knopf und werden nie gesendet.

### 7.9 Wochenrückblick (GW1)

Drei neue Abschnitte am Ende, auch in einer sonst leeren Woche:
- **Gewohnheiten:** je in der Woche aktiver Gewohnheit „3 von 4“ (erfüllte von zählenden Tagen, laufende Woche mit „bisher“) bzw. „2 von 3“ bei weniger als 7 Tagen pro Woche, mit Balken.
- **Reflexion:** zwei mehrzeilige Felder „Was lief gut?“ und „Belastet mich etwas?“, beide optional.
- **Neue Woche planen:** drei Häkchen „Termine eingeplant“, „Gewohnheiten eingeplant“, „Aufgaben der Woche festgelegt“ und die Zeile „Woche planen ›“ (öffnet „Planen“ in der Wochenansicht der Folgewoche).
- Gespeichert wird je Woche; vergangene Wochen bleiben bearbeitbar.

## 8. Benachrichtigungen und Deeplinks

### 8.1 Routine-Mitteilungen

- **Abend:** je Checklistenpunkt mit Zeitanker eine Mitteilung, höchstens vier. Titel = Name des Punkts, Text „Noch 60 min bis zur Schlafzeit (23:00)“. Bei Abstand 0: „Schlafzeit (23:00)“.
- **Morgen:** eine Mitteilung „Tagesstart“ mit dem Text „Fokus für heute wählen?“, Standard aus.
- **Auslöser:** täglich wiederholend nach Stunde und Minute (`UNCalendarNotificationTrigger`, `repeats: true`). Sie brauchen keinen App-Start. Folge: Die Texte sind statisch (keine Tageszähler wie im Rahmen GS1), und ein schon abgehakter Punkt erinnert an dem Abend trotzdem.
- **Kennungen:** `tagwerk.routine.evening.<UUID>` und `tagwerk.routine.morning`. Gruppierung über `threadIdentifier = "routine"`.
- **Neu einplanen:** bei Änderung von Schlafzeit, Checkliste oder Schaltern und bei jedem App-Start (alle Routine-Anfragen entfernen, gewünschte neu anlegen). Die Texte folgen der App-Sprache zum Zeitpunkt des Einplanens.
- **Erlaubnis:** Fehlt sie, zeigt Einstellungen › Routinen den Hinweis und den Knopf aus den Benachrichtigungs-Einstellungen. Ohne Erlaubnis bleiben Karte und Zeile in „Planen“ der Einstieg.

### 8.2 Budget

- iOS hält 64 ausstehende Anfragen. Der Benachrichtigungsplan bleibt bei 50. Routinen belegen fest höchstens 5 (4 Abend, 1 Morgen). Zusammen höchstens 55.
- `NotificationScheduler.performReschedule` muss Anfragen mit Präfix `tagwerk.routine.` aus seiner eigenen Menge ausschließen. Sonst würden sie gegen das Budget von 50 gezählt (`NotificationScheduler.swift:127`).
- `NotificationCenterClient` bekommt eine zweite Methode für wiederholende Anfragen; der Test-Fake zieht mit.

### 8.3 Sprungziele

- Neue Routen in `AppRoute`: `routine/start` und `routine/evening`. Sie öffnen „Planen“ auf heute und darüber das Blatt. Links schreiben nichts.
- Eine Routine-Mitteilung trägt in `userInfo` den Schlüssel `route` mit dem Pfad. Der Delegate reicht ihn an den `AppRouter` weiter, nicht an den `NotificationNavigator`.
- Die Blätter „Tagesstart“ und „Tagesabschluss“ hängen an `RootView`, damit Karte, Zeile, Erfassen-Zeilen, Mitteilung und Link dasselbe Blatt öffnen. Wie bei den anderen Routen schließen offene Blätter und der Assistent vorher.
- Zwischen 00:00 und 03:59 öffnet `routine/evening` den Tagesabschluss des Vortags (Regel 10).

## 9. KI: Vorschläge aus der Notiz

### 9.1 Zustimmung (GZ1)

- Schalter „Notizen an ChatGPT senden“ in Einstellungen › Routinen, Standard aus, ohne ChatGPT-Anmeldung deaktiviert.
- Beim ersten Tippen auf „Vorschläge holen“ mit ausgeschaltetem Schalter erscheint einmalig das Zustimmungsblatt, aufgebaut wie `MealConsentSheet`:
  - Einleitung: „Für Vorschläge sendet Tagwerk den Text dieser Notiz an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.“
  - **Gesendet wird** der Text dieser einen Notiz, dazu deine offenen Aufgaben und Termine der nächsten 7 Tage (Titel, Fälligkeit, Zeit).
  - **Nicht gesendet werden** Dankbarkeit, Gewohnheiten, Wochenreflexion, Daten aus Health und frühere Notizen.
  - **Nur auf dein Tippen:** Ohne „Vorschläge holen“ verlässt keine Notiz das iPhone.
  - Knöpfe „Einverstanden und Vorschläge holen“ und „Nicht jetzt“; Hinweis auf den Widerruf unter „Routinen“.
- „Einverstanden“ schaltet den Schalter ein und sendet diese Notiz. Danach sendet jeder weitere Tipp ohne Rückfrage, nie von selbst.

### 9.2 Kontext

Vom Nutzer entschieden (2026-11-19): Neben dem Notiztext gehen die offenen Aufgaben und Termine der nächsten 7 Tage (heute bis heute + 6) mit, damit „Aufgabe verschieben“ und „Block ändern“ auch für die folgenden Tage möglich sind (z. B. „Training morgen 18:00 → 07:00“).

| Gesendet | Inhalt |
|---|---|
| Notiz | Text der einen Notiz, Art (Morgen/Abend), heutiges Datum und Uhrzeit |
| Aufgaben der nächsten 7 Tage | offen und in den 7 Tagen geplant, fällig oder mit Zeitblock, dazu überfällige: Kennung, Titel, Fälligkeit, geplanter Tag, Aufwand, Quelle |
| Termine der nächsten 7 Tage | Termine und Zeitblöcke der 7 Tage: Kennung, Titel, Beginn, Ende, ob Zeitblock |

Nicht gesendet werden Notizen von Aufgaben, Kommentare, Tage außerhalb des 7-Tage-Fensters, Dankbarkeit, Gewohnheiten, Ziele, Health-Daten und frühere Notizen. Festlegung: Bei mehr als 60 Aufgaben bzw. 100 Terminen werden die ältesten bzw. spätesten abgeschnitten (Grenzen wie `list_tasks`/`list_events`).

### 9.3 Aufruf und Karten (GK1)

- Ein eigenes Modell `NoteSuggestionModel` ruft `ResponseStreaming.respond` genau einmal je Tipp auf: Anweisung plus Kontext plus Notiz, mit eingeschränkter Funktionsliste. Es benutzt weder `Conversation` noch `ChatStore`. Der Notiztext landet in keinem Verlauf und in keinem Log.
- Modell und Denkaufwand folgen den KI-Einstellungen wie beim Assistenten.
- **Funktionsliste:** `create_task`, `reschedule_task`, `assign_to_day`, `create_time_block`, `update_event`. Keine Lesefunktionen, kein Löschen, kein `plan_period`.
- **Prüfung vor der Anzeige:** Vorschläge mit Kennungen, die nicht im gesendeten Kontext standen, werden verworfen. `update_event` gilt nur für Tagwerk-Zeitblöcke. Höchstens fünf Karten.
- **Bestätigen** führt die Funktion über das vorhandene `AppTools.run` aus und zeigt das Ergebnis auf der Karte. Es folgt **kein** weiterer Aufruf an ChatGPT.
- Die Kartentexte kommen aus der vorhandenen Beschreibung (`AssistantModel.describe`); sie wird dafür so herausgelöst, dass beide Stellen sie nutzen.
- Nach dem Aufruf wird „verarbeitet am“ gesetzt; jede ausgeführte Karte erhöht `derivedActionCount`.
- Vorschläge gibt es nur, wenn das Blatt zum heutigen Tag gehört (abends bis 03:59 zum Vortag, Regel 10). Bei älteren Tagen fehlt der Knopf, weil das 7-Tage-Fenster ab heute nicht zur Notiz passt.

## 10. Siri und Widget (GB1)

- **Kurzbefehl „Gewohnheit abhaken“** (`CheckHabitIntent`): läuft im Hintergrund wie „Wasser erfassen“.
  - Parameter „Gewohnheit“ als App-Entität aus den aktiven Gewohnheiten; ohne Angabe fragt Siri nach.
  - Wirkung: legt für heute ein Handhäkchen an (auch bei Gewohnheiten mit automatischer Quelle) und schreibt den Snapshot.
  - Antwort: „Lesen 20 min ist für heute abgehakt.“ bzw. „Lesen 20 min war heute schon abgehakt.“ Keine Serie, keine Quote.
  - Phrasen mit `\(.applicationName)`, z. B. „\(Gewohnheit) in Tagwerk abhaken“ und „Gewohnheit in Tagwerk abhaken“. Nach jeder Änderung an den Gewohnheiten werden die Phrasen-Parameter aktualisiert.
  - Kein Zurücknehmen per Siri.
- **Widget „Heute“:** Zeile „✓ 3 von 5“ in der rechten Spalte unter Wasser und Schritten, `privacySensitive`. Ist „Ernährung im Widget zeigen“ aus (Layout W2b), ersetzt der Zähler die vierte Planzeile. Die Sperrbildschirm-Varianten zeigen ihn nie.
- **Quelle des Zählers:** Regel 8 mit den zuletzt bekannten Werten des Erfassen-Modells (Schritte und Health-Trainings nur, solange sie zum heutigen Tag gehören).
- Der Hintergrundweg (`replacingIntake`) ersetzt künftig Tageswerte **und** Zähler.
- Einstellungen › Erfassen › „Siri & Kurzbefehle“ nennt die neue Phrase.

## 11. Einstellungen › Routinen (GS·E, GZ1 Schalter)

Neue Unterseite neben „Erfassen“ in der Hauptliste.

| Abschnitt | Inhalt |
|---|---|
| Tagesabschluss | „Zielschlafzeit“ (Uhrzeit), Schalter „Erinnerungen am Abend“ |
| Abend-Checkliste | Punkte mit Name und „n min vorher · Uhrzeit“ oder „ohne Erinnerung“; hinzufügen, sortieren, löschen. Abstand 0–240 min in 5er-Schritten. Höchstens acht Punkte, höchstens vier mit Erinnerung. Leere Liste zeigt „Vorschlag übernehmen“ (Tagesabschluss öffnen 90, Handy weglegen 60, Ins Bett 30). Fußtext: „Die Zeiten folgen der Schlafzeit. Höchstens vier Punkte erinnern; weitere stehen nur in der Liste.“ |
| Tagesstart | Schalter „Erinnerung“, „Uhrzeit“ |
| Planen | Schalter „In Planen anzeigen“ (Karte und Abendzeile) |
| Gewohnheiten | Zeile „Gewohnheiten bearbeiten ›“ (dieselbe Liste wie in „Erfassen“) |
| Gedanken-Notiz | Schalter „Notizen an ChatGPT senden“ mit dem Fußtext aus GZ1, angepasst an §9.2 |

## 12. Lokalisierung (EN)

Alle neuen Texte stehen deutsch und englisch in den String Catalogs (`Localizable.xcstrings`, `AppShortcuts.xcstrings`, bei Tageslicht `InfoPlist.xcstrings`). Leitbegriffe:

| Deutsch | Englisch |
|---|---|
| Routinen | Routines |
| Gewohnheiten · 3 von 5 | Habits · 3 of 5 |
| Tagesstart / Tagesabschluss | Morning start / Evening wrap-up |
| Fokus heute | Today's focus |
| Dankbar für | Grateful for |
| Gedanken | Thoughts |
| Zielschlafzeit | Target bedtime |
| Abend-Checkliste | Evening checklist |
| Noch 60 min bis zur Schlafzeit (23:00) | 60 min until bedtime (11:00 PM) |
| Tage pro Woche | Days per week |
| Serie | Streak |
| automatisch | automatic |
| Vorschläge holen | Get suggestions |
| Als Aufgabe anlegen | Create as task |
| Notizen an ChatGPT senden | Send notes to ChatGPT |
| Leitfragen einfügen | Insert guiding questions |
| Reflexion · Was lief gut? · Belastet mich etwas? | Reflection · What went well? · Is something weighing on me? |
| Neue Woche planen | Plan the new week |
| Gewohnheit abhaken | Check off habit |
| Tagesstart · 18.11. / Tagesabschluss · 18.11. | Morning start · 11/18 / Evening wrap-up · 11/18 |

Datums- und Zeitformate folgen der Sprache über die vorhandenen Helfer (`DateText`). Die Leitfragen werden in der App-Sprache eingefügt und danach nicht mehr übersetzt, weil sie Text der Notiz sind.

## 13. Abhängigkeiten zu den anderen drei Vorhaben

Reihenfolge der Umsetzung: (1) Issue-Zuweisung #136, (2) Phase 5 Einkaufsliste und Notizen #113, (3) Suche, (4) Phase 7.

| Vorhaben | Abhängigkeit |
|---|---|
| **Phase 5** (hart) | Phase 7 nutzt `NoteRecord`, `NoteStore` und die Notizen-Liste in „Aufgaben“. #143 setzt Phase 5 voraus. Phase 5 legt `kindRaw`, `dayKey`, `processedAt` an und zeigt alle Arten mit Herkunftszeile und Filter. Phase 7 schreibt `morning`/`evening`, ergänzt `derivedActionCount`, die Angabe „n Aufgaben daraus“ und den geänderten Fußtext der Liste |
| **Phase 5** (weich) | Die Liste „Einkaufsliste“ ist aus Aufgaben und Planung ausgeschlossen. Fokus-Auswahl, Tagesrückblick und KI-Kontext lesen über `TaskListModel`/`PlanningModel` und erben den Ausschluss |
| **Suche** | Die Suche wird vor Phase 7 gebaut. Durchsucht sie `NoteRecord`, findet sie Gedanken-Notizen ohne Zutun, sobald es sie gibt; Phase 7 liefert nur die Beschriftung. Gewohnheiten, Dankbarkeit, Checkliste und Wochenreflexion sind kein Suchziel |
| **Issue-Zuweisung #136** | Keine fachliche Abhängigkeit. Ändert #136 die Funktion `create_task` (z. B. Zuweisung), übernimmt die Funktionsliste aus §9.3 die neue Definition, weil sie auf denselben Definitionen beruht |
| **Alle** | Kein neuer Tab. Die Einstellungs-Hauptliste bekommt durch Phase 7 genau eine Zeile „Routinen“ |

#141, #142, #145, #144 hängen nicht an Phase 5 und könnten vorgezogen werden. Die festgelegte Reihenfolge bleibt davon unberührt.

## 14. Festlegungen des Builders (meine Festlegungen)

Nicht vom Nutzer entschieden; aus dem früheren Entwurf übernommen (Ü) oder in diesem Dokument neu getroffen (N).

**Übernommen**
1. (Ü) Höchstens zehn aktive Gewohnheiten, höchstens drei Fokus-Aufgaben; der Fokus ist eine lokale Marke.
2. (Ü) Pausierte Tage und Tage vor „Zählt ab“ zählen nicht in die Quote.
3. (Ü) Neue Einstellungsseite „Routinen“.
4. (Ü) Vergangene Tage lassen sich nachtragen, künftige nicht.
5. (Ü) Täglich wiederholende Auslöser für die Abend-Erinnerungen.
6. (Ü) Dankbarkeit: ein Feld sichtbar, bis zu drei; nie an ChatGPT, nie im Widget.
7. (Ü, geändert) Deeplinks `tagwerk://routine/start` und `tagwerk://routine/evening`. Abweichung vom früheren `routine/abend`: Alle vorhandenen Pfade sind englisch (`AppRoute.swift:6–10`).

**Neu**
8. (N) **Ein Element in „Planen“:** Tagesstart und Fokus teilen sich eine Karte mit zwei Zuständen; der Tagesabschluss ist eine Zeile in der vorhandenen Kapazitätskarte (§7.3).
9. (N) Die Tagesstart-Karte erscheint von 04:00 bis 12:00; „✕“ blendet sie für den Tag aus; `showsRoutinesInPlan` schaltet Karte und Abendzeile dauerhaft ab.
10. (N) Abendgrenze 04:00 für Tagesabschluss und Checkliste (Regel 10).
11. (N) Die Zeile „Tagesabschluss“ erscheint ohne Zeitanker ab 90 Minuten vor der Schlafzeit.
12. (N) Zähler: Gewohnheiten mit erreichtem Wochenziel zählen als erfüllt (Regel 8). Der Zähler erscheint auch, wenn die Ernährungszeile ausgeschaltet oder noch leer ist; dann steht er allein.
13. (N) Anzeige bei weniger als 7 Tagen pro Woche: „Diese Woche e von n“ statt „7 Tage“; Serie in Wochen.
14. (N) Rückblick-Fenster 90 Tage (Regel 7). Automatische Erfüllung rechnet mit dem **aktuellen** Ziel; eine Zieländerung ändert auch vergangene Tage.
15. (N) Automatisch erfüllte Gewohnheiten lassen sich nicht abwählen; je automatischer Quelle höchstens eine Gewohnheit.
16. (N) Feld „Zählt ab“ statt Nachtragen vor dem Anlegetag.
17. (N) Die Abend-Checkliste startet leer mit „Vorschlag übernehmen“. Ohne Punkte kommen trotz eingeschaltetem Schalter keine Mitteilungen. Höchstens acht Punkte.
18. (N) Mitteilungstexte sind statisch; ein abgehakter Punkt erinnert trotzdem (bekannter Nachteil der wiederholenden Auslöser).
19. (N) Routinen reservieren 5 Plätze außerhalb des 50er-Budgets (§8.2).
20. (N) Routine-Mitteilungen laufen über den `AppRouter`, nicht über den `NotificationNavigator`.
21. (N) Höchstens eine Gedanken-Notiz je Tag und Art; leerer Text löscht sie.
22. (N) Vorschläge: ein Aufruf ohne Folgeaufruf nach dem Bestätigen, höchstens fünf Karten, offene Karten verfallen beim Schließen, nur für den heutigen Tag (§9.3).
23. (N) KI-Kontext: offene Aufgaben und Termine der nächsten 7 Tage (§9.2), vom Nutzer am 2026-11-19 entschieden.
24. (N) „Als Aufgabe anlegen“ belegt nur den Titel vor (erste Zeile der Notiz).
25. (N) Siri-Antwort ohne Serie; kein Zurücknehmen per Siri.
26. (N) Widget-Zähler als eigenes Feld des Snapshots, nicht Teil der Ernährungswerte; er bleibt auch bei ausgeschalteter Ernährung sichtbar.
27. (N) Die Wochenreflexion wird nie an ChatGPT gesendet; der Assistent bekommt keine Routine-Funktionen.
28. (N) Der Stern erscheint nur in „Planen“, nicht im Tab „Aufgaben“.
29. (N) Wiederkehrende Vorkommen sind nicht als Fokus wählbar.

## 15. Offene Punkte

### 15.1 Spikes am Gerät

| Spike | Frage | Folge |
|---|---|---|
| Tageslicht (2 h) | Liefert die Watch `timeInDaylight`-Tageswerte? Wie verhält sich die eigene Freigabe (eigener Status wie bei den Schritten)? Wie spät kommen die Werte an? Was liefert ein Tag ohne Watch? | Bestanden: Quelle „Zeit bei Tageslicht“ wird gebaut (etwa 3 h), automatisch nur mit Daten, sonst von Hand. Nicht bestanden: Die Quelle entfällt; „Draußen bei Tageslicht“ bleibt eine Gewohnheit von Hand |
| Antippbares Widget (3 h) | Läuft ein `Button(intent:)` nachweislich im App-Prozess mit Zugriff auf den Store? | Eigene Folgeaufgabe (GB2); nicht Teil dieses Schnitts |
| Aktionen in Mitteilungen (2 h) | Verhalten von Kategorien und Hintergrundstart bei beendeter App | Eigene Folgeaufgabe (GS3), erst wenn GS1 im Alltag läuft |

### 15.2 Geräte-Checkliste (ohne eigenes Zeitbudget, bei der Umsetzung)

- Wiederholende Auslöser: überleben Neustart und Drüberinstallieren; Verhalten bei Zeitumstellung und Zeitzonenwechsel; Verhalten im Fokus-Modus „Schlafen“.
- Spracheingabe im Notizfeld außerhalb des Assistenten.
- Siri erkennt die deutsche Phrase mit Gewohnheitsnamen; Abhaken bei gesperrtem Gerät.
- Fünf Mitteilungen pro Tag im Zusammenspiel mit vollen 50 Deadline-Plätzen.
- Höhe der Routine-Karte auf dem kleinsten unterstützten Gerät im Stundenraster.

### 15.3 Fragen an den Nutzer

Keine offen. Die Frage zum Umfang des KI-Kontexts hat der Nutzer am 2026-11-19 beantwortet: nächste 7 Tage (§9.2).

## 16. Aufgabenschnitt

Schätzungen in Stunden, einschließlich Tests und englischer Texte. Grob, nicht gemessen.

| Nr. | Aufgabe | Issue | h |
|---|---|---|---|
| 1 | Datentypen `HabitRecord`, `HabitCheckRecord`; `HabitRules` (Erfüllung, Quote, Serie, Zähler) mit Tests | #141 | 5 |
| 2 | Abschnitt „Gewohnheiten“ in „Erfassen“, Liste „Bearbeiten“, Blatt „Gewohnheit“ | #141 | 5 |
| 3 | Automatische Erfüllung (Wasser, Training, Schritte) über 90 Tage; Zähler in der Planen-Zeile | #141 | 3 |
| 4 | Kurzbefehl „Gewohnheit abhaken“; Zähler im Snapshot und im Widget „Heute“ | #141 | 4 |
| 5 | `RoutineDayRecord`, `EveningChecklistItemRecord`, `RoutineSchedule`; Einstellungen › Routinen | #142 | 4 |
| 6 | Blatt „Tagesabschluss“, Zeile in der Kapazitätskarte, Zeilen in „Erfassen“, Routen und Blatt-Anbindung in `RootView` | #142 | 4 |
| 7 | Wiederholende Mitteilungen, Ausschluss im `NotificationScheduler`, Sprung über den Router | #142 | 3 |
| 8 | Blatt „Tagesstart“ mit Dankbarkeit und Überblick; Erinnerung am Morgen | #145 | 4 |
| 9 | `FocusMarkRecord`, Routine-Karte in „Planen“ (zwei Zustände), Stern und Kontextmenü | #145 | 4 |
| 10 | Notizfeld auf `NoteRecord`/`NoteStore`, Spracheingabe, „Als Aufgabe anlegen“, „n Aufgaben daraus“ und Fußtext in der Notizen-Liste | #143 | 5 |
| 11 | Zustimmung, `NoteSuggestionModel`, Kontext, Karten im Blatt, Herauslösen der Kartentexte | #143 | 8 |
| 12 | Wochenreflexion: Datentyp, drei Abschnitte, Sonntagszeile | #144 | 5 |
| 13 | Leitfragen-Vorlage | #146 | 2 |
| 14 | Spikes: Tageslicht 2, antippbares Widget 3, Aktionen in Mitteilungen 2 | #141, #142 | 7 |
| 15 | Optional nach bestandenem Spike: Quelle „Zeit bei Tageslicht“ (HealthBridge, Freigabe, Blatt) | #141 | 3 |

Summen: #141 17 h · #142 11 h · #145 8 h · #143 13 h · #144 5 h · #146 2 h · Spikes 7 h. Zusammen etwa 63 h, mit Tageslicht etwa 66 h. Der frühere Entwurf nannte 57 h ohne #146; die Differenz kommt aus den Leitfragen, der Routine-Karte mit zwei Zuständen und dem eigenen Aufruf ohne Folgeaufruf.

Reihenfolge: Aufgaben 1–4, 5–7, 8–9, 10–11, 12, 13. Die Spikes laufen unabhängig; der Tageslicht-Spike sinnvollerweise nach Aufgabe 3.

## 17. Geprüft, angenommen, nicht belegt

- **Geprüft (Quelltext):** alle Stellen der Tabelle in §3.
- **Aus dem Phase-5-Design übernommen (noch nicht gebaut):** `NoteRecord`, `NoteStore`, Notizen-Liste mit Herkunftszeile.
- **Angenommen:** Verhalten der wiederholenden Auslöser; Tageslicht-Werte der Watch; Spracheingabe im Notizfeld; Erkennung der Siri-Phrase mit Gewohnheitsnamen.
- **Nicht geprüft:** nichts aus diesem Dokument lief am Gerät oder im Simulator. Die Stundenwerte sind Schätzungen.
- **Nicht belegt:** dass die Routinen diesmal länger als drei Wochen genutzt werden, und dass Erinnerungen vor dem Zeitpunkt die späten Abendeinträge verhindern. Beides ist eine Annahme aus einer einzelnen früheren Erfahrung des Nutzers.

## 18. Dem Umsetzenden überlassen

Ordnerstruktur, Testaufbau, Auswahl der SF Symbols für Gewohnheiten, Wortlaut der englischen Anweisung an das Modell, Farbgebung im Rahmen des Mockups, Wortlaut weiterer Siri-Phrasen.
