# GitHub: Issues ohne Project und Status je Project (#153, #154)

**Ziel:**
- (#153) Ein GitHub-Issue lässt sich ohne Project anlegen, im Blatt „Neue Aufgabe“ und über den Assistenten.
- (#154) Der Status eines Issues lässt sich je Project setzen, mit den Stufen aus dem jeweiligen Project: beim Anlegen, im Editor und als schneller Wechsel im Kontextmenü. Das Zusammenspiel mit Abhaken und Wiederöffnen ist festgelegt.

Beides liegt im selben Thread, weil es denselben Anlege- und Schreibweg (`GitHubTaskProvider.create/addToProject/write`) ändert.

**Rahmen:** Rein technische Umsetzung ohne Mockups. Die Oberfläche folgt vorhandenen Mustern (Picker, Menü, Kapsel). Keine Änderungen an `TODO.md`, kein `t3gh`. Das Statuswerkzeug für den Assistenten ist laut #154 „später“ und nicht Teil dieses Plans.

## Bestand (Pfade relativ zu `app/`, `GK` = `Packages/GitHubKit/Sources/GitHubKit`)

- Schreiben: `GK/GitHubWriter.swift`. `setField` (Z. 32) mit `updateProjectV2ItemFieldValue` und `clear…` existiert, `ProjectFieldValue.singleSelect(optionName)`. Bei fehlendem Feld oder fehlender Option kehrt die Funktion stillschweigend zurück.
- Lesen: `GK/ProjectsQuery.swift`. `fieldsSelection` (Z. 6) liest Optionen. `ItemNode.placement(in:)` (Z. 189-205) setzt `placement.status`.
- **`ProjectField.options` ist ein Dictionary** (`GK/GitHubIssueRecord.swift` Z. 5). Die Reihenfolge der Optionen geht verloren. Die Dekodierung alter Caches muss tolerant bleiben (`decodeIfPresent` wie in `ProjectInfo.init(from:)` Z. 38).
- Fest verdrahtet: `doneStatus = "Done"` und `reopenStatus = "Ready"` (`GK/GitHubMapping.swift` Z. 11-12). Verwendet in `GitHubTaskProvider.swift` Z. 155 (Löschen), 228 (Anlegen → Ready), 320 (Abhaken/Wiederöffnen) und 346, sowie `GitHubMapping.isVisible` Z. 52.
- Anlegen: `GitHubTaskProvider.create` Z. 183-208. Pflicht-Prüfung Z. 184, `addToProject` Z. 214-229. `NewTaskSheet.swift`: `canSave` Z. 67-70, Footer Z. 240-245, `ProjectSelectionRow` (`Tasks/ProjectSelection.swift`). Test `GitHubCreateTests.create_withoutProject_throwsFailed` (Z. 120) fixiert das alte Verhalten.
- Sichtbarkeit: `GitHubTaskProvider.isListed` (Z. 272) prüft nur den Assignee. `GitHubAPI.openProjectIssues` (Z. 54) und `GitHubMapping.isVisible` verlangen mindestens eine Platzierung, die nicht Done ist.
- Kapsel nach Vergabe: `HandedOverNotice` (`Tasks/HandedOverNotice.swift`), `HandedOverCapsule` (`Tasks/UndoCapsule.swift` Z. 90-109), Titel aus `AssigneeSelection.capsuleTitle` (Z. 73-80), ausgelöst in `TaskListModel.settle`/`handOver` (Z. 432/442).
- Assistent: `AI/AppTools+Definitions.swift` Z. 93-103 (`create_task`), `AI/AppTools+GitHub.swift` `gitHubTarget` Z. 29-50 (`.projectMissing`) und `createIssue` Z. 87-140 (Antwort mit `listed`), `AI/ActionCardDescriber.swift` `issueTarget` Z. 125-146, `AI/AssistantModel.swift` `gitHubInstructions()` Z. 395-407.
- Modell: `TaskItem`, `TaskDraft`, `TaskEdit`, `TaskField` in `Packages/TagwerkCore/Sources/TagwerkCore/` ohne Status. Editor `Editor/TaskEditorView.swift` (Projekt-Ziel-Picker Z. 95-100), `Editor/TaskEditorModel.swift`, `Editor/ConflictChange.swift` Z. 17-29. Kontextmenü `Tasks/TaskContextMenu.swift` (`TaskMenuActions` Z. 5-24, „Fälligkeit“ Z. 55-68), gebaut in `TaskListView.swift:397` und `PlanView.swift:165`.
- Tests: Swift Testing. `GKT/Fixtures.swift` (Optionen bisher nur Ready/Done), `StubTransport`, `GitHubTaskProviderWriteTests`, `GitHubCreateTests`, App-Tests `TaskListModelTests`, `AppToolsTests` (`AppToolsGitHubTests` ab Z. 516), `TaskEditorModelTests`, `Fakes/FakeTaskProvider.swift`.

## Regeln (technische Vorgaben, ins Design-Sammelissue übernommen)

1. **Optionen in Board-Reihenfolge.** `ProjectField` bekommt eine geordnete Liste `orderedOptions: [ProjectFieldOption]` (id, name). Das Dictionary bleibt für die Abwärtskompatibilität oder wird daraus berechnet. Alte Caches ohne Reihenfolge dekodieren weiter, und dann gilt die Reihenfolge des Dictionarys nach Name, bis zum nächsten Laden.
2. **Status-Modell.** In TagwerkCore ein generischer Typ, z. B. `public struct SubContainerStatus: Hashable, Sendable { subContainerID, subContainerName, current: String?, options: [String], isWritable }`. `TaskItem.statuses: [SubContainerStatus]` (Standard `[]`), `TaskField.status`, `TaskEdit.statusChanges: [String: String]` (Project-ID → Optionsname, Standard leer). `TaskDraft.startStatus: String?`.
3. **Done und Erledigt.**
   - Abhaken setzt wie bisher Done in allen beschreibbaren Projects und schließt das Issue.
   - Ein Status-Wechsel auf die Done-Option in **allen** beschreibbaren Projects gilt als Abhaken (gleicher Weg wie `isCompleted`, damit kein offenes Issue unsichtbar wird).
   - Done in nur einem von mehreren Projects setzt nur das Feld. Das Issue bleibt offen und bleibt sichtbar, solange ein Project nicht Done ist.
   - Ein Wechsel weg von Done bei einem geschlossenen Issue öffnet es wieder.
   - Die Done-Option wird über den Namen „Done“ erkannt (Groß-/Kleinschreibung ignorieren). Fehlt sie, gibt es kein Abhaken über den Status.
4. **Wiederöffnen.** Status „Ready“, wenn vorhanden. Sonst die erste Option in Board-Reihenfolge, die nicht Done ist. Das gilt auch für den Startstatus beim Anlegen ohne Auswahl.
5. **Startstatus beim Anlegen.** Ein Picker „Status“ im GitHub-Abschnitt von „Neue Aufgabe“. Er zeigt die Optionen, die alle gewählten Projects gemeinsam haben, in der Reihenfolge des ersten Projects, ohne Done. Vorauswahl wie Regel 4. Ohne Project ist der Picker ausgeblendet.
6. **Ohne Project (#153).** `ProjectSelectionRow` erlaubt 0 Projects mit dem Wert „Kein Project“. `canSave` verlangt nur noch das Repository. Footer bei 0 Projects: „Ohne Project erscheint das Issue nicht in deinen Aufgaben.“ `isListed` verlangt zusätzlich mindestens eine Platzierung. Nach dem Anlegen erscheint die bestehende Kapsel mit eigenem Titel, z. B. „#N angelegt · ohne Project“, und „Auf GitHub öffnen“. Dafür `HandedOverNotice` um einen Grund erweitern (`.handedOver` / `.noProject`) statt eine zweite Kapsel zu bauen.
7. **Assistent (#153).** `create_task`: `project_ids: []` bedeutet ausdrücklich „ohne Project“. Fehlt der Parameter (`nil`), gilt die bisherige Vorbelegung (verknüpfte Projects, sonst das einzige). Bleibt es mehrdeutig, kommt wie bisher `.projectMissing`. Aktionskarte: „Kein Project“ statt „Project fehlt“, wenn ausdrücklich leer. Beschreibung und `gitHubInstructions()` entsprechend anpassen. Die Antwort enthält weiterhin `listed: false` mit `number` und `url`.
8. **Editor.** Eigener Abschnitt „Status“ mit einer Zeile je Project (Picker mit den Optionen des Projects). Nur sichtbar, wenn `editableFields` `.status` enthält, also nur bei GitHub-Issues mit Project-Status-Feld. Der Projekt-Ziel-Picker „Ändern in“ gilt nicht für den Status, weil der Status immer je Project gesetzt wird. Konfliktkarte: Status-Zeile in `ConflictChange`.
9. **Kontextmenü.** Menü „Status“ neben „Fälligkeit“, nur bei GitHub und `isWritable`. Bei einem Project eine Liste der Optionen mit Häkchen am aktuellen Status, bei mehreren ein Untermenü je Project. Neue Closure in `TaskMenuActions` mit Standardwert, damit `DayView`, `WeekView` und `DayGridScreen` unverändert bleiben.
10. **Schreiben.** Statuswechsel in `GitHubTaskProvider.write` je Ziel-Project über `setField(.singleSelect)`. Abhaken- und Wiederöffnen-Logik nach Regel 3 und 4 statt fest „Ready“. Nach jedem Schreiben wird das Issue neu gelesen (`apply` tut das bereits), weil Project-Workflows den Status ändern können. Eine fehlende Option ist ein Fehler mit Meldung (`TaskWriteError.failed`), kein stilles Überspringen, wenn der Nutzer sie ausdrücklich gewählt hat.

## Aufgaben

1. Plan nach `docs/superpowers/plans/2026-11-19-github-status-and-no-project.md` legen und committen.
2. GitHubKit: geordnete Optionen (Lesen, Mapping, Cache-Kompatibilität). Tests mit erweitertem Fixture (Backlog, Ready, In progress, Blocked, In review, Done) und einem alten Cache-JSON ohne Reihenfolge.
3. TagwerkCore: `SubContainerStatus`, `TaskItem.statuses`, `TaskField.status`, `TaskEdit.statusChanges` inklusive `diff(from:to:)`, `TaskDraft.startStatus`. Tests.
4. GitHubKit: Mapping `taskItem` füllt `statuses` und `.status`. `write` mit Statuswechseln und Regeln 3/4. `create` ohne Project (Regel 6), Startstatus (Regel 5), `isListed` mit Platzierung. Tests für jede Regel, auch Done in einem von zwei Projects, Wiederöffnen ohne Ready-Option und ein Issue in zwei Projects mit verschiedenen Stufen. `create_withoutProject_throwsFailed` umschreiben.
5. App: `NewTaskSheet` (Regel 5/6), `ProjectSelection`, `HandedOverNotice` und Kapsel mit Grund, `TaskListModel.settle`. Editor, `ConflictChange`, Kontextmenü (Regeln 8/9). `FakeTaskProvider` verarbeitet `statusChanges`. Tests in `TaskListModelTests`, `TaskEditorModelTests`, `ProjectSelectionTests`.
6. Assistent (Regel 7) mit Tests in `AppToolsTests`.
7. Strings deutsch als Schlüssel mit Englisch, GitHubKit-Texte im Paket-Katalog.
8. `app/test-all.sh` grün.

## Abnahme

- Issue ohne Project anlegbar (Blatt und Assistent), mit Kapsel und Hinweis. Mit Project unverändert.
- Status je Project im Editor und Kontextmenü änderbar, Optionen in Board-Reihenfolge. Projects mit anderen Stufen funktionieren.
- Abhaken und Wiederöffnen verhalten sich nach Regel 3/4. Kein offenes Issue wird durch einen Statuswechsel unsichtbar, ohne dass es geschlossen ist.

## Für das Design-Sammelissue

- Platzierung und Aussehen von Status im Editor, im Kontextmenü und im Blatt „Neue Aufgabe“. Status als Marke in der Aufgabenzeile, ja oder nein.
- Wortlaut der Kapsel und des Footers für Issues ohne Project.
- Regeln 3 und 4 bestätigen (Done in einem von mehreren Projects, Wiederöffnen ohne „Ready“).
- Später: Issues ohne Project trotzdem anzeigen (eigene Quelle je Repository). Status über den Assistenten.
