# Tagwerk – Phase 4 Design: Widget, Siri-Kurzbefehle und Wochenrückblick

Stand: 2026-11-18 · Status: **vorläufig nach Fable-Empfehlung, Freigabe des Nutzers offen** (der Nutzer war nicht erreichbar).

Baut auf:
- `2026-11-17-tagwerk-design.md`: §2 Anti-Ziele, §4 App Groups, §5 Phase 4, §7 Datenschutz, §8 Skizze „Fortschritt“, §9.
- `2026-11-17-phase-2b-design.md`: Nicht-Ziele, §8.4.
- `2026-11-18-phase-3-design.md`: §2 Nicht-Ziele, §8.8, §11.

Mockup: `../mockups/2026-11-18-phase-4-comfort-mockups.html` (W1a–W4a, P1a, R1a–R3a, S1a, S2a; vorläufig, Freigabe offen). Epic: GitHub #4.

## 1. Absicht und Warum

Tagwerk soll im Alltag weniger Öffnen und Tippen verlangen:
- Ein **Widget** zeigt auf dem Home- und Sperrbildschirm, was als Nächstes ansteht.
- **Siri-Kurzbefehle** erfassen Wasser ohne die App und öffnen Essen und Training vorausgefüllt.
- Ein **Wochenrückblick** fasst Ernährung, Trinken, Training und erledigte Aufgaben einer Woche zusammen. Er setzt die Skizze „Fortschritt“ aus dem Hauptdesign §8 um.
- Dazu kommt die aus Phase 3 verschobene **Kalorien-/Wasser-Zeile im Kopf von „Planen“**.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Widgets:
  - „Als Nächstes“: klein, Sperrbildschirm rechteckig und Inline.
  - „Heute“: mittel, mit kcal und Wasser.
- Datenquelle der Widgets: ein Snapshot im App-Group-Container.
- URL-Schema `tagwerk://` für Widget-Ziele. Benachrichtigungen und Deeplinks nutzen dieselbe Routen-Logik.
- Vier App Intents mit deutschen Siri-Phrasen: „Wasser erfassen“, „Mahlzeit erfassen“, „Training erfassen“, „Was steht heute an?“.
- Wochenrückblick als Unterseite von „Erfassen“, Mo–So, zurückblätterbar.
- Zeile „~kcal / Ziel · Wasser“ im Kopf der Tagesansicht von heute.
- Einstellungen:
  - Schalter „In Planen anzeigen“ und „Ernährung im Widget zeigen“.
  - Abschnitt „Siri & Kurzbefehle“.
- `refresh-install.sh` signiert App und Extension und fällt bei einem Fehler auf den letzten guten Commit zurück.

**Nicht-Ziele (Phase 4)**
- Knöpfe im Widget (`Button(intent:)` liefe im Extension-Prozess ohne Store).
- Großes Widget, Widget-Konfiguration, Live Activities, Kontrollzentrum-Steuerelement.
- Kurzbefehl „Aufgabe anlegen“: Siri legt Erinnerungen an, und die erscheinen in Tagwerk. Ein eigener Weg fördert das Anti-Ziel „zweite Aufgabenquelle“.
- Erfassen per Assistent, auch nicht als „Blatt öffnen“-Tool. Der Assistent erhält weiter keine Ernährungsdaten (Phase 3 §11).
- KI-Wochenfazit, Benachrichtigung zum Rückblick, geplante Stunden im Rückblick, Deadline-Quote im Rückblick.
- Erledigte GitHub-Issues im Rückblick (bräuchte einen Netzabruf).
- **Kalender-Export** (Hauptdesign §9): ist seit 2b erledigt, weil der `BlockPlanner` Zeitblöcke in den gewählten Plan-Kalender schreibt.

**Anti-Ziele** (aus Hauptdesign §2 und 2b §8.4)
- Gesundheitsdaten auf dem Sperrbildschirm oder in Siri-Antworten bei gesperrtem Gerät. Deshalb:
  - Accessory-Widgets zeigen nie Ernährung.
  - Titel sind `.privacySensitive()`.
  - „Was steht heute an?“ verlangt ein entsperrtes Gerät.
- KI-Aufruf ohne Tippen. Keiner der folgenden Wege schätzt:
  - Widget-Provider: liest nur die Datei, ohne Netz, Health oder EventKit.
  - Intents: „Mahlzeit erfassen“ öffnet nur das Blatt.
  - Deeplinks: navigieren nur.
- Datenverlust durch Store-Umzug. Der SwiftData-Store bleibt, wo er ist.
- Ein Widget, das nach wenigen Tagen ausfällt, weil das Profil der Extension nicht erneuert wird. Dagegen hilft das Skript in §7.

## 3. Ansätze

| Ansatz | Kern | Abwägung | Entscheidung |
|---|---|---|---|
| **A: Snapshot-Datei im App-Group-Container** | Die App schreibt nach Änderungen eine versionierte JSON-Datei, das Widget liest nur sie | Keine Migration, kein Schema in der Extension, keine zwei Prozesse auf einer SQLite-Datei. Nachteil: Der Inhalt ist so aktuell wie der letzte Schreibvorgang | **Gewählt** |
| B: SwiftData-Store in den Group-Container verschieben | Widget öffnet denselben Store | Migration bestehender Daten mit Verlustrisiko; Extension braucht alle Modelle; gleichzeitiger Zugriff | verworfen |
| C: Widget ohne Daten | Nur Knopf „Tagwerk öffnen“ | Kein Nutzen | verworfen |

## 4. Daten

### 4.1 Snapshot (`TagwerkCore/WidgetSnapshot.swift`)

```
WidgetSnapshot {
  schemaVersion: Int (= 1)
  createdAt: Date
  days: [SnapshotDay]
  showsNutrition: Bool
}

SnapshotDay {
  day: PlanDay
  entries: [SnapshotEntry]
  deadlineCount: Int
  intake: SnapshotIntake?
}

SnapshotEntry {
  id
  title
  start
  end
  kind: event | block | deadline
  colorHex?
  isAllDay
}

SnapshotIntake {
  kcal
  hasEstimate
  goalKcal
  waterMilliliters
  goalWaterMilliliters
}
```

- `days` umfasst heute und die zwei folgenden Tage. So rückt das Widget ohne laufende App weiter, auch über Mitternacht. Nur heute trägt `intake`, und zwar nur bei `showsNutrition`. An Folgetagen zeigt das Widget dann 0 statt der Summe von gestern.
- Datei: `<Group-Container>/Library/Application Support/widget-snapshot.json`.
  - Atomar geschrieben.
  - Dateischutz `.completeUntilFirstUserAuthentication`, damit das Widget auch gesperrt rendern kann.
  - Ohne Container (`containerURL == nil`) wird still übersprungen.
- Die Gruppen-ID steht unter dem Info.plist-Schlüssel `TagwerkAppGroup` = `group.$(TAGWERK_BUNDLE_ID)` in beiden Targets. Sie ist nie im Code festgeschrieben.
- Geschrieben wird nach Änderungen an Plan, Aufgaben oder Erfassen (entprellt, 1 s), beim Wechsel in den Hintergrund und am Ende des bestehenden Hintergrund-Refreshs. `WidgetCenter.reloadAllTimelines()` läuft nur, wenn sich der Inhalt ohne `createdAt` geändert hat (Reload-Budget).
- Keine Werte in Logs.

### 4.2 Neue Felder

| Ort | Feld | Standard |
|---|---|---|
| `AppSettings` | `showsIntakeInPlan` | `true` |
| `AppSettings` | `widgetShowsNutrition` | `true` |
| `LocalTask` | `completedAt: Date?` | `nil` (gesetzt beim Abhaken, gelöscht beim Wiederöffnen) |
| `ReminderRecord` / `ReminderStore` | `completedReminders(in: DateInterval, listIDs:) -> [CompletedReminder]` (Titel nicht nötig: ID, Erledigungsdatum) | – |

## 5. Regeln (reine Logik in `TagwerkCore`)

1. **Snapshot bauen** (`WidgetSnapshotBuilder`): Einträge eines Tages sind Termine, Blöcke und Deadlines mit Uhrzeit.
   - Ganztägige Einträge stehen vorn und werden in „Als Nächstes“ nicht als „nächster“ gezählt.
   - Pro Tag höchstens 12 Einträge, sortiert nach Beginn.
2. **Als Nächstes zum Zeitpunkt t** (`WidgetSnapshot.upcoming(at:limit:)`): Einträge, deren Ende nach t liegt, ab dem Tag von t. Ein laufender Eintrag zählt.
   - Ist heute nichts mehr: der erste Eintrag des nächsten Tages mit Präfix „Morgen“.
   - Sonst: „Heute nichts mehr geplant“.
3. **Timeline:** ein Eintrag je Beginn und Ende der Einträge der nächsten 24 h, dazu Mitternacht. Höchstens 30 Einträge, Policy `.atEnd`.
4. **Veraltet:** Ein Snapshot gilt als veraltet, wenn sein `createdAt` mehr als 3 Tage zurückliegt, er fehlt oder die Version unbekannt ist. Das Widget zeigt dann „Tagwerk öffnen, um den Plan zu laden“.
5. **Routen** (`AppRoute.parse(URL)`): `tagwerk://plan/today`, `tagwerk://capture`, `tagwerk://capture/meal`, `tagwerk://capture/workout`, `tagwerk://review`. Alles andere ergibt `nil`. Parameter werden nicht ausgewertet, denn Deeplinks schreiben nie.
6. **Wochenrückblick** (`WeekReview.make(…)`), Woche Mo–So in Ortszeit:
   - kcal je Tag mit `hasEstimate`. Tage ohne Mahlzeit sind `nil` (nicht 0).
   - Schnitt kcal nur über Tage mit Mahlzeiten.
   - Wasser: Tage mit erreichtem Ziel, Schnitt über Tage mit Wasser-Einträgen.
   - Trainings: zählende Trainings ab 10 min (Regel 6 aus Phase 3) und Minuten-Summe.
   - Eiweiß-Schnitt nur bei aktivem Ziel.
   - Erledigte Aufgaben: Erinnerungen mit Erledigungsdatum in der Woche (gewählte Listen) plus lokale Aufgaben mit `completedAt` in der Woche.
   - In der laufenden Woche sind künftige Tage `future`.
7. **Kopfzeile Planen:** nur Tagesansicht und Anker = heute und `showsIntakeInPlan` und mindestens ein Eintrag (Mahlzeit oder Wasser) heute. Text: „~1.240 / 2.300 kcal · 1,2 / 2,0 l“; „~“ nur bei Schätzung.
8. **Siri-Antworten:**
   - Wasser: „250 ml Wasser erfasst.“ Keine Tagessumme, damit bei gesperrtem Gerät keine Gesundheitsdaten vorgelesen werden.
   - Heute: „Heute: 3 Termine, 2 Blöcke, 1 Deadline. Als Nächstes 10:30 Issue #12 Login.“ Kommt aus dem Snapshot, ohne Ernährung.

## 6. Oberfläche (Mockup, vorläufig)

- **W1a „Als Nächstes“ (klein):**
  - Zeit „10:30–12:00“, Titel.
  - „danach 13:00 Lernzettel“.
  - Fuß „⚠︎ 2 Deadlines heute“.
  - Tippen → `tagwerk://plan/today`.
- **W2a „Heute“ (mittel):**
  - Links „HEUTE · Di 18. Nov“ mit drei Einträgen (Zeit, Titel, Quellenfarbe).
  - Rechts „~1.240 / 2.300 kcal“ mit Balken und „1,2 / 2,0 l“ (`.privacySensitive()`).
  - Linke Hälfte → Planen, rechte → Erfassen.
  - Ohne Ernährung (W2b) vier Einträge in voller Breite.
- **W3a Sperrbildschirm:**
  - Rechteckig: „10:30 Issue #12 Login“ / „danach 13:00 Lernzettel“.
  - Inline: „10:30 Issue #12“.
  - Titel bei gesperrtem Gerät verdeckt, Uhrzeiten sichtbar.
- **W4a Zustände:** „Heute nichts mehr geplant“, „Morgen 09:00 …“, „Tagwerk öffnen, um den Plan zu laden“, verdeckte Darstellung.
- **P1a Planen-Kopf:** Zeile unter dem Titel „~1.240 / 2.300 kcal · 1,2 / 2,0 l ›“, Tippen → Erfassen.
- **R1a Rückblick:** eine scrollende Seite mit folgenden Teilen:
  - Kopf: „KW 47 · 16.–22. Nov“ mit ‹ ›.
  - Kalorien: sieben Balken mit Ziellinie und „Ø ~2.150 kcal an 6 Tagen“.
  - Wasser: „Ziel an 4 von 7 Tagen · Ø 1,7 l“.
  - Training: „3 / 3 · 145 min“.
  - Erledigt: „12 Aufgaben (Erinnerungen und lokal, ohne GitHub)“.
- **R2a Zustände:**
  - Laufende Woche: „bisher“, künftige Tage leer.
  - Leere Woche: „In dieser Woche wurde nichts erfasst.“
  - Tag ohne Eintrag: gestrichelter Platzhalter.
- **R3a Einstieg:** Der Wochenzähler im Kopf von „Erfassen“ wird zu „Training 2 / 3 · Woche ›“.
  - Ist der Zähler ausgeblendet (Ziel 0), steht „Woche ›“ allein.
- **S1a Siri:** Textantworten aus §5.8. „Was steht heute an?“ zeigt zusätzlich ein Listen-Snippet mit den nächsten drei Einträgen.
- **S2a Einstellungen › Erfassen:**
  - Schalter „In Planen anzeigen“ und „Ernährung im Widget zeigen“.
  - Abschnitt „Siri & Kurzbefehle“ mit den vier Phrasen und dem Hinweis, dass sich „Wasser erfassen“ auf die Aktionstaste oder den Home-Bildschirm legen lässt.

## 7. Signierung und Installation

- Extension-Bundle-ID `$(TAGWERK_BUNDLE_ID).widget`. App Group `group.$(TAGWERK_BUNDLE_ID)` steht in beiden Entitlements (über `project.yml`).
- `refresh-install.sh`:
  1. `remove_cached_profiles` räumt die Profile von App und Extension. Dafür prüft die testbare Funktion `is_tagwerk_profile <app-id> <team> <bundle>`, ob die ID exakt `<team>.<bundle>` oder `<team>.<bundle>.*` ist.
  2. Das Ablaufdatum ist das früheste aus App-Profil und `PlugIns/*.appex/embedded.mobileprovision`, berechnet von `earliest_expiry`.
  3. Der Commit jeder erfolgreichen Installation wird gemerkt (`last-good-commit.<bundle>`).
  4. Bei Build- oder Signierfehler baut das Skript einmal diesen Commit erneut und installiert ihn. So läuft die App nicht ab, nur weil ein neuer Stand nicht signiert. Die Benachrichtigung meldet den Rückfall.
     - Ein Rückfall auf einen Stand vor einer Schema-Erweiterung ist ausgeschlossen, weil der gemerkte Commit installiert war und damit das aktuelle Schema geöffnet hat.
  5. Das Signier-Grep erfasst auch Fehler der Extension.
- Fables Empfehlung, Phase 4 erst nach einer bestandenen Geräte-Installation zu mergen, ist **nicht** umgesetzt. Der Nutzer hat den Merge für diese Kette ausdrücklich angeordnet. Der Rückfall in Punkt 4 ersetzt das Gate nur, wenn es schon einen gemerkten Commit gibt. Darum gehört „einmal `install-dev.sh` bzw. `refresh-install.sh` beobachten“ in die offene Liste.

## 8. App Intents

- Alle Intents liegen im App-Target. `TagwerkApp.init` registriert einen `@MainActor`-Dienst `IntentServices` beim `AppDependencyManager`.
  - Der Dienst nutzt **denselben** `ModelContainer` wie die App, es gibt keinen zweiten Container.
  - Bei einem Hintergrundstart läuft `RootView.task` nicht, deshalb braucht der Dienst nur `IntakeStore`, `HealthMirror` und den Snapshot-Schreiber.

| Intent | Modus | Wirkung |
|---|---|---|
| `LogWaterIntent` (Menge optional, Standard 250 ml, 50–2.000 ml) | Hintergrund | legt `DrinkValue` jetzt an, spiegelt nach Health (bei Fehler: Nachholen), schreibt Snapshot; Antwort ohne Tagessumme |
| `LogMealIntent` (Text optional) | Vordergrund | öffnet „Erfassen“ mit Essen-Blatt, Text vorausgefüllt; geschätzt wird nur nach Tippen im Blatt (Einwilligung unverändert) |
| `LogWorkoutIntent` (Art optional, Dauer optional) | Vordergrund | öffnet das Trainingsblatt vorausgefüllt (Überschneidungswarnung braucht Health-Lesezugriff, der gesperrt fehlt) |
| `TodayOverviewIntent` | Hintergrund, `authenticationPolicy = .requiresAuthentication` | antwortet aus dem Snapshot; kein Netz, keine KI, keine Gesundheitsdaten |

- Verwendet wird `supportedModes`, weil `openAppWhenRun` unter iOS 26+ veraltet ist. Jede Phrase enthält `\(.applicationName)`. In Phrasen stehen nur Enum-Parameter, z. B. Trainingsart.

## 9. Vorläufige Entscheidungen (Fable, Freigabe offen)

1. SwiftData bleibt am Standard-Speicherort. Das Widget liest einen versionierten JSON-Snapshot (heute + 2 Tage) aus `group.$(TAGWERK_BUNDLE_ID)`.
2. Das Widget ist rein lesend. Es hat keine Knöpfe und greift nicht auf KI, Netz, Health oder EventKit zu.
3. Neues URL-Schema `tagwerk://`. Deeplinks navigieren nur und schreiben nie.
4. Vier Siri-Kurzbefehle wie in §8. „Wasser erfassen“ läuft im Hintergrund mit Standardmenge 250 ml. Essen und Training öffnen das Blatt.
5. Kein Kurzbefehl „Aufgabe anlegen“.
6. Eine Mahlzeit wird nie per Siri geschätzt.
7. Der Assistent bekommt kein Erfassen-Tool.
8. Der Wochenrückblick ist eine Unterseite von „Erfassen“, kein fünfter Tab. Er läuft Mo–So und blättert nur in die Vergangenheit.
9. Der Rückblick enthält kcal, Wasser, Training, Eiweiß bei aktivem Ziel und erledigte Aufgaben. Schnitte zählen nur Tage mit Einträgen. Es gibt keine KI-Zusammenfassung.
10. Erledigte Aufgaben kommen aus den Quellen, nicht aus einem eigenen Protokoll:
    - Erinnerungen über ihr Erledigungsdatum.
    - Lokale Aufgaben über `completedAt`; sie zählen erst ab Phase 4.
    - GitHub fehlt und ist so beschriftet.
    - Wiederkehrende Erinnerungen erzeugen in EventKit keine erledigten Einzelvorkommen und zählen deshalb nicht.
11. Geplante Stunden und die Deadline-Quote erscheinen nicht im Rückblick. Die Skizze „Deadlines erledigt 8/10“ entfällt.
12. Die Planen-Kopfzeile erscheint nur in der Tagesansicht von heute und erst ab dem ersten Eintrag. Sie ist abschaltbar, Standard an.
13. Es gibt zwei Widgets, „Als Nächstes“ und „Heute“. Ein großes Widget und eine Konfiguration fehlen.
14. Der Sperrbildschirm zeigt nie Ernährung. Titel werden bei gesperrtem Gerät verdeckt. Steht „Ernährung im Widget zeigen“ auf aus, fehlen die Werte schon im Snapshot.
15. Signierung und Rückfall wie in §7. Es gibt keine Build-Variante ohne Widget.
16. Der Kalender-Export gilt seit 2b als erledigt.
17. Nicht in Phase 4: Live Activities, Kontrollzentrum-Steuerelement, Benachrichtigung zum Rückblick.
18. Siri bestätigt Wasser ohne Tagessumme.

## 10. Offen (Gerät)

- **Signierung:** App Group mit dem Personal Team; Ersetzung von `$(TAGWERK_BUNDLE_ID)` im Entitlement; Extension-Profil wird erneuert. Mit dem Standardwert `local.tagwerk.app` kann die Gruppe vergeben sein, maßgeblich ist die eigene Bundle-ID aus der lokalen Config. Der kostenlose Account begrenzt die App-IDs je 7 Tage, die Extension zählt mit.
- **Widget-Darstellung:** getönt und transparent, `.privacySensitive()` auf Sperrbildschirm, Always-On und StandBy; Tageswechsel ohne App-Start.
- **Siri:** erkennt die deutschen Phrasen. Hintergrundstart schreibt Wasser bei gesperrtem Gerät; Health-Nachholen danach.
- **Deeplinks:** Kaltstart aus dem Widget.
- **Rückblick:** Abfrage erledigter Erinnerungen dauert bei vielen Listen nicht spürbar lange.

## 11. Dem Umsetzenden überlassen

Ordnerstruktur, Testaufbau, Farbgebung im Rahmen des Mockups, Wortlaut der Phrasen-Varianten.

## 12. Abweichungen und Ergänzungen bei der Umsetzung (2026-11-18)

Umgesetzt nach `../plans/2026-11-18-phase-4-comfort.md` inkl. der Änderungen nach dem Fable-Review. Diese gehen §4–§9 vor, wo sie abweichen.

**Snapshot**
- **Veraltet:** Ein Snapshot gilt als veraltet, wenn der heutige Tag nicht in `days` steht. Die 3-Tage-Regel aus §5.4 entfällt: Ein Snapshot von Montag würde am Donnerstag sonst fälschlich „nichts geplant“ zeigen.
- **Kein `showsNutrition` im Snapshot:** `intake == nil` genügt. Nach Mitternacht und ohne Tageswerte zeigt „Heute“ das Layout W2b, also ohne Ernährungshälfte.
- **Deadline-Kalender-Termine** erscheinen genau einmal, als Deadline. Termine über Mitternacht haben je Tag eine eigene ID.
- **Planteil:** Ihn schreibt nur ein Lauf mit geladenen Aufgabenquellen, über `PlanningModel.snapshotInput`. Das ist ein reiner EventKit-Lesezugriff: Anker und Ansicht bleiben unverändert, es gibt keinen Netzabruf.
- **Siri im Hintergrund:** „Wasser erfassen“ ersetzt nur die Tageswerte einer vorhandenen Datei. Gibt es noch keine Datei, wird keine geschrieben, damit das Widget nicht fälschlich „nichts geplant“ zeigt.
- **Auslöser:** Geschrieben wird
  - entprellt nach Änderungen an Plan, Aufgaben, Tageswerten und den relevanten Einstellungen (Nährwerte im Widget, Ziele, Kalender, Einrichtung),
  - direkt beim Wechsel in den Hintergrund,
  - am Ende des Hintergrund-Refreshs.
- **Abwägung:** Die Datei ist ab dem ersten Entsperren lesbar und enthält Titel und kcal, sonst könnte das Widget bei gesperrtem Gerät nicht rendern. Sie ist von der Datensicherung ausgenommen.

**Kopfzeile, Rückblick, Siri**
- **Kopfzeile in „Planen“:** Die Tagessumme kommt aus `CaptureModel.todayIntake`. Sie wird bei jeder lokalen Änderung neu berechnet, auch beim Löschen und Widerrufen. Eine eigene Klasse `TodaySummary` gibt es nicht. Tippen öffnet „Erfassen“ über den Router.
- **Einstieg in den Rückblick (R3a):** eine eigene Zeile „Wochenrückblick · Woche ›“ unter der Tagesübersicht. Der Trainingszähler selbst ist nicht tippbar, damit VoiceOver die Übersicht weiter als ein Element liest.
- **Erledigte Aufgaben:**
  - Erinnerungen über `completionDates` (EventKit, gewählte Listen, nur mit Vollzugriff; es verlassen nur Datumswerte die Abfrage).
  - Lokale Aufgaben über `LocalTask.completedAt`.
- **Siri-Texte nach dem Mockup:**
  - „Heute steht nichts an.“
  - „… Davon steht nichts mehr an.“
  - „Öffne Tagwerk, um den Plan zu laden.“
  - Parameter „Menge“, „Beschreibung“, „Art“, „Dauer“.
  - Eine Menge außerhalb von 50–2.000 ml wird begrenzt, nicht abgelehnt: Das System prüft den Bereich schon beim Parameter.
- **Registrierung:** `AppDependencyManager.shared.add(dependency:)` in `TagwerkApp.init`. Intents und App teilen den einen `ModelContainer`.

**Widget und Skript**
- **Widget:** `Color+Hex.swift` liegt in beiden Targets. Das Widget nutzt einen eigenen Kalender (gregorianisch, Montag). Die Gruppen-ID kommt aus dem Info.plist-Schlüssel `TagwerkAppGroup`, ein Test prüft, dass sie zur Bundle-ID passt und in der Extension gleich ist.
- **Skript `refresh-install.sh`:**
  - räumt die Profile von App und Extension (`is_tagwerk_profile`, schützt vor Präfix-Täuschung);
  - nimmt das früheste Ablaufdatum, ein unlesbares Extension-Profil gilt als „unbekannt“;
  - startet sich nach dem Git-Update einmal mit der neuen Version neu;
  - merkt sich `last-good-commit` und `last-installed` (`install-dev.sh` schreibt `dev`);
  - baut bei Build- oder Signierfehler den letzten guten Commit in einem eigenen Git-Worktree (Exit 4, Mitteilung immer).
- **Merge-Gate:** Fables Merge-Gate (erst nach bestandener Geräte-Installation) ist nicht umgesetzt, weil der Nutzer den Merge angeordnet hat.
- **Erste Installation:** Für sie gibt es noch keinen gemerkten Commit, also keinen Rückfall. Sie muss beobachtet werden, siehe Geräte-Checkliste.

**Geräte-Checkliste (offen)**
- **Signierung und Installation**
  - Signierung mit App Group und Extension über `refresh-install.sh` bzw. `install-dev.sh`.
  - Ersetzung von `$(TAGWERK_BUNDLE_ID)` in den Entitlements.
  - Zahl der App-IDs im kostenlosen Account.
  - Rückfall bei Signierfehler.
- **Widget-Darstellung**
  - In der Galerie, hell, dunkel, getönt und transparent.
  - `.privacySensitive()` auf Sperrbildschirm, Always-On, StandBy, CarPlay und auf dem Mac (iPhone-Widgets).
  - Tageswechsel ohne App-Start.
  - Kaltstart über das Widget.
- **Siri**
  - Erkennt die deutschen Phrasen.
  - „Wasser erfassen“ bei gesperrtem Gerät (Health-Nachholen danach).
  - „Was steht heute an?“ verlangt Entsperren.
- **Rückblick**
  - Ob EventKit erledigte Vorkommen wiederkehrender Erinnerungen liefert.
  - Dauer der Abfrage bei vielen Listen.

**Review vor dem Merge (Fable, 2026-11-18)**

*Behoben*
- **Kritisch:** Der SwiftData-Store bleibt am alten Ort (`groupContainer: .none`). Mit dem App-Group-Entitlement hätte SwiftData sonst einen neuen, leeren Store im Group-Container geöffnet; das war im Simulator belegt. Ein Test sichert den Ort.
- **Tageswerte im Snapshot:** Sie kommen direkt aus dem Store für den Tag von „jetzt“, nicht aus dem Erfassen-Modell. Damit stimmen sie nach Mitternacht und beim Hintergrundstart.
- **`replacingIntake`:** Ein fehlender Tag macht einen veralteten Snapshot nicht mehr „frisch“, und ältere Tage verlieren ihre Werte.
- **Planteil:** Er wird nur geschrieben, wenn alle Quellen fertig geladen sind (`allSourcesSettled`).
- **Kaltstart:** Der Router wird auch beim ersten Erscheinen ausgewertet.
- **Schreiben im Hintergrund:** Der Snapshot wird vor allen anderen Schritten geschrieben.
- **EventKit-Änderungen** lösen ein Schreiben aus.
- **„Erfassen“-Link:** Er springt auf heute. Das Blatt öffnet sofort, ohne auf Health zu warten. Eine neue Vorbelegung ersetzt ein offenes Blatt.
- **Kürzung:** Ganztägige Einträge verdrängen keine zeitgebundenen mehr. Die Zähler für Siri werden vor dem Kürzen gespeichert.
- **Siri-Wasser** hinterlässt keine „Widerrufen“-Leiste.
- **Skript:**
  - Compilerfehler zählen nicht als Signierfehler.
  - Ein unlesbares Extension-Profil führt nicht zur stündlichen Neuinstallation; es wird gemeldet.
  - Ein Rückfall erfolgt auch, wenn das Gerät die Installation ablehnt.
  - Signale führen zu Exit 129, 130 und 143.

*Offen*
- **Erste Phase-4-Installation:** Für sie gibt es keinen gemerkten Commit, also keinen Rückfall. Siehe Liste für den Nutzer.
- **Prüfung der eingebetteten Extension:** Sie läuft nur im Simulator-Build (gehosteter Test), nicht für den Geräte-Build in `test-all.sh`.
