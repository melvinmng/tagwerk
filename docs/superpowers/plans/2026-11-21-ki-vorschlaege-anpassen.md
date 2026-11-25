# „Anpassen“ für alle KI-Vorschläge – Implementation Plan (Entwurf)


> **Entscheidungen des Nutzers (21.11.2026, Kommentar in #255):** AN1a, AN2a, AN3a, AN4a, AN5a, AN6a, AN7b, AN8a, AN9a, AN10a, AN11a, AN12a, AN13a, AN14a – alle Empfehlungen. Offene Fragen des Plans nach Empfehlung.

> **For agentic workers:** Dieser Plan ist ein **Entwurf vor den Entscheidungen des Nutzers**. Kein Task wird begonnen, bevor die Entscheidungen im Abschnitt „Entscheidungen des Nutzers“ getroffen und hier eingetragen sind. Jeder Task nennt unter „Hängt ab von“ die Kürzel, gegen deren Empfehlung er geschrieben ist; fällt eine Entscheidung anders aus, wird der Task vor der Umsetzung überarbeitet. Danach gilt: Task für Task, jeweils mit TDD, Schritte als Checkbox (`- [ ]`).

> **Status:** Stand 21.11.2026, Code-Grundlage `origin/main` bei `8326a3c` (enthält PR #240–#252). Mockups: `docs/superpowers/mockups/2026-11-21-ki-vorschlaege-anpassen-mockups.html` (14 Entscheidungen, Kürzel AN). Nichts davon ist gebaut, nichts am Gerät geprüft. Es gibt noch kein Issue zu diesem Vorhaben.

**Anlass (Wortlaut des Nutzers):** „Außerdem finde ich die ‚Anpassen‘-Option gut, diese fehlt bisher noch bei den anderen KI-Vorschlägen und soll bei allen ergänzt werden. Ich möchte sowohl manuell anpassen können, als auch weiter mit der KI über einzelne oder alle Vorschläge schreiben.“

**Goal:**
- **Von Hand:** Jeder Vorschlag von ChatGPT lässt sich vor dem Bestätigen in den vorhandenen Feldern ändern. Der geänderte Vorschlag bleibt ein Vorschlag und ist als „von dir angepasst“ markiert.
- **Mit ChatGPT über einen Vorschlag:** Eine kurze Anfrage nur zu diesem Vorschlag; die Antwort ändert nur ihn, alles andere bleibt stehen, „Rückgängig“ holt den Stand davor zurück.
- **Mit ChatGPT über alle Vorschläge:** Die Nachricht geht mit dem aktuellen Stand aller offenen Vorschläge (samt Handänderungen) hinaus; zurück kommt ein überarbeiteter Satz.
- **Unverändert:** Einwilligung je Funktion, Prüfung beim Ausführen, Einzelbestätigung, `storedForm`, private Notizen verlassen das Gerät nie, nichts geschieht ohne Tippen.

**Architecture:**
- **`AIKit`:** `Conversation` bekommt `adjust(_:arguments:)` (Werte einer offenen Karte ersetzen), `confirm` führt den geänderten Stand aus und meldet dem Modell die Änderung, `revise(comment:)` gibt alle offenen Karten als „Rückfrage“ mit ihrem Stand zurück.
- **`TagwerkCore`:** `ProposalRevision` (Bezug `one`/`all`, Marke je Eintrag `byUser`/`byAssistant`, Regel „festgelegt“, lokales Begrenzen einer Antwort auf den Bezug, ein Schritt „Rückgängig“).
- **App, Karten:** `ActionCardView` mit drittem Knopf und Marke; `ProposalAdjustSheet` mit einem Editor je Funktion (`ProposalEditor`) und der Rückfrage-Zeile; `CardReviser` (kurze Einzelanfrage mit dem Schema der einen Funktion); `AssistantModel` und `NoteSuggestionModel` reichen beides durch.
- **App, Vorschau-Blätter:** gemeinsames Bauteil `FollowUpBar` (aus `SuggestionConversation` herausgelöst); je Funktion eine zweite Anfrage `revise(…)` neben der bestehenden (`MealEstimator`, `RecipeImporter`, `RecipeTranslator`, `ShoppingSorter`, `ShoppingTranslator`, `MailSummarizer`) mit demselben Antwortformat wie die erste.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), Swift Testing, XcodeGen. Keine neue Paketabhängigkeit, kein neues SwiftData-Modell.

**Issues:** noch keines. **Branches (Vorschlag):** je Stufe einer: `feat/adjust-cards`, `feat/adjust-previews`, `feat/adjust-mail-plan`.

## Global Constraints

- **Strings:** Deutsch ist Quellsprache. Jeder neue Text steht deutsch und englisch im Katalog und in `scripts/translations/en.json`; prüfen mit `scripts/sync-strings.sh --check --no-build --derived-data <dir>` und `scripts/check-strings.py --require-english`.
- **Code:** Kommentare, Logs und Testnamen englisch. Anweisungen an ChatGPT für Einzelanfragen englisch (wie in `MealEstimator`, `NoteSuggestionModel.instructions`), Anweisungen des Assistenten deutsch.
- **Ein Vorschlag bleibt ein Vorschlag.** Weder das Ändern von Hand noch eine Antwort von ChatGPT führt etwas aus. Ausgeführt wird nur über den vorhandenen Bestätigungsknopf.
- **Dieselbe Prüfung wie bisher.** Geänderte Werte laufen durch dieselbe Funktion (`ToolHandler.run`, `RecipeImporter.apply`, `ShoppingSorter.apply`, `ShoppingModel.rename`, `RecipeTranslationModel.replace`, `IntakeStore`) wie ungeänderte. Kein zweiter Schreibweg.
- **Datenschutz:**
  - Eine Rückfrage sendet nur, was die Funktion schon sendet, dazu den aktuellen Vorschlag, die Handänderungen und die Nachricht. Sie läuft nur mit der Einwilligung der jeweiligen Funktion und nur mit Anmeldung.
  - Private Notizen (Tagebuch, Bible Study, Traumtagebuch, private Ordner) gehen nie an ChatGPT; jede neue Anfrage läuft durch dieselbe Sperre wie die bestehende.
  - Rückfragen der Vorschau-Blätter und die Rückfrage zu einer Karte werden nicht gespeichert und stehen in keinem Log.
  - Geänderte Karten gehen wie alle Aufrufe durch `storedForm`.
- **Nichts von selbst:** Jede Anfrage folgt auf „Senden“ oder eine Schnellantwort.
- **SwiftUI-Falle:** Nie `.sheet`, `.confirmationDialog` oder `.alert` an eine `Section` oder Zeile in `Form`/`List` hängen. Das Blatt „Anpassen“ hängt an der Chat-Ansicht bzw. am umgebenden Blatt, nicht an der Karte.
- **Barrierefreiheit:** Die Marke „von dir angepasst“ / „von ChatGPT angepasst“ ist Teil des gesprochenen Kartentexts; „Anpassen“ ist auch als VoiceOver-Aktion der Karte erreichbar.
- **Commits:** Conventional Commits auf Englisch, ohne Hinweis auf KI.
- **Tests:** `app/test-all.sh` nach jedem Task (`TAGWERK_SKIP_UI_TESTS=1` für Zwischenstände, voller Lauf vor dem letzten Commit jeder Stufe).

## Ausgangslage (Befunde aus dem Quelltext, `origin/main` `8326a3c`)

Pfade unter `app/`, sofern nicht anders genannt.

### Zwei Arten von Vorschlägen

1. **Karten** entstehen aus Funktionsaufrufen des Modells. `Conversation` hält offene Schreibaufrufe in `pendingActions` (`Packages/AIKit/Sources/AIKit/Conversation.swift:99`); `confirm(_:)` führt die Argumente des Modells unverändert aus (`:140–148`), `decline(_:)` schreibt ein festes Ergebnis (`:150–154`). `send(_:)` schließt alle offenen Aufrufe als abgelehnt, bevor die Nachricht hinausgeht (`closeOpenCalls(output: Self.declinedOutput)`, `:132–139`): Wer zu offenen Karten etwas tippt, verwirft sie, und das Modell sieht nur „Vom Nutzer abgelehnt“.
2. **Jeder Aufruf braucht ein Ergebnis vor der nächsten Anfrage** („Once every call of a round has an output, the next call follows“, `:76–80`; `continueIfResolved`, `:306–314`). Einzelne Karten offen zu lassen und trotzdem weiterzuschreiben, sieht das Gespräch nicht vor.
3. **Karten werden aus den Argumenten beschrieben.** `ActionCardDescriber.describe` (`Tagwerk/AI/ActionCardDescriber.swift:35–125`) baut Titel, Änderungstext, Warnung und Knopftitel aus dem Aufruf; `Conversation.messages` baut die Karte bei jedem Lesen aus dem Verlauf (`Conversation.swift:216–240`). Ändert sich das Argument im Verlauf, ändern sich Karte, Warnung und Speicherform von selbst.
4. **`ActionCardView`** hat „Verwerfen“ und „Bestätigen“, eine optionale Zeile `accessory` und `canConfirm` (`Tagwerk/AI/ChatView.swift:285–330`).
5. **Vorschau-Blätter** stellen eine Einzelanfrage mit festem Antwortformat (`responder.respond(… jsonSchema: …)`) und zeigen das Ergebnis vor dem Übernehmen. Ein Gespräch gibt es nicht.
6. **Es gibt ein Vorbild für beide Wege:** „Tag planen“. `AIPlanner.moveSuggestion` ändert einen Vorschlag von Hand, merkt sich die Stelle der KI (`aiPosition`) und setzt ihn fest (`Tagwerk/AI/AIPlanner+Revision.swift:19–41`); `AIPlanner.revise(_:comment:)` sendet einen Kommentar zu einem Vorschlag samt den übrigen der Planung, wendet nur genannte Änderungen an, lässt von Hand verschobene stehen, prüft lokal und bietet „Rückgängig“ (`:62–104`, `revisionUndo`). Die Oberfläche dazu: `SuggestionMoveSection` („Von Hand ändern“, `Tagwerk/Planning/SuggestionViews.swift:433`) und `SuggestionConversation` mit Schnellantworten, Eingabezeile, Hinweis, was gesendet wird, und „Als Vorgabe merken“ (`:494–640`).
7. **Es gibt ein Vorbild für das Umschreiben einer offenen Karte:** `NoteSuggestionModel.setTarget` schreibt das Ziel eines Issues in den Aufruf der Karte (`Tagwerk/Routines/NoteSuggestionModel.swift:148–160`).

### Bestandsaufnahme: jeder Ort, an dem ChatGPT etwas vorschlägt und der Nutzer bestätigt

| Nr. | Ort | Anfrage und Vorschlag | Bestätigen | Von Hand (heute) | Mit ChatGPT (heute) |
|---|---|---|---|---|---|
| 1 | **Assistent: Aktionskarten** (allgemeiner Chat, Aufgaben-Chat, mit Notiz-Zugriff). Funktionen mit Karte: `create_task`, `update_task`, `reschedule_task`, `complete_task`, `assign_to_day`, `create_time_block`, `link_event_to_task`, `set_day_hours`, `set_lunch`, `mark_events_free`, `plan_period`, `add_comment`, `update_shopping`, `assign_task`, `create_event`, `update_event`, `delete_event` | `Conversation.runRound` (`Conversation.swift:254–304`); Karten in `ChatView.swift:209–212`, Texte in `ActionCardDescriber.swift:35–125`; Aufgaben-Chat `TaskChat.swift:57–83` | `AssistantModel.confirm` / `decline` (`AssistantModel.swift:323–338, 372–378`) | nein | nur frei tippen; offene Karten gelten dann als verworfen (Befund 1) |
| 2 | **Assistent: „Alle bestätigen (N)“** | `ChatView.swift:220–232` | `AssistantModel.confirmAll` (`:353–364`), nur `batchConfirmable` (`:214–218`) | nein | nein |
| 3 | **Assistent: Abgabe-Karte** (`assign_task`, „Abgeben“, rot, mit Warnung) | `ActionCardDescriber.swift:121, 208–227` | einzeln (`singleConfirmationTools`, `AssistantModel.swift:206–212`) | nein | nein |
| 4 | **Sprechmodus:** Karten ansagen und per Stimme bestätigen | `AssistantModel.confirmCards` (`:236 ff.`), `VoiceModeMachine.swift:395–399` | per Stimme; Löschungen und geschützte Karten einzeln | nein | ja, durch Sprechen (verwirft offene Karten) |
| 5 | **Gedanken-Notiz: „Vorschläge holen“** (Tagesstart, Tagesabschluss), einschließlich Issue-Vorschlägen mit Ziel | eine Anfrage, Antwort sind Funktionsaufrufe (`NoteSuggestionModel.swift:92–128`, `:113–114`); Karten in `Tagwerk/Routines/NoteField.swift:299–325` | `confirm`, `decline`, `confirmAll` (`NoteSuggestionModel.swift:185–208`) | nur das Ziel eines Issues (`setTarget`, `:148`; `targetRow`, `NoteField.swift:327–345`) | nein |
| 6 | **Planen: „Tag planen“ / „Woche planen“** (Blöcke, Zuweisungen, Verschiebungen) | `AIPlanner.swift:544–545`; Vorschläge in `SuggestionViews.swift:84–300`, Leiste `Tagwerk/Planning/AIPlanBar.swift:106–144` | `accept`, `acceptAll` (`AIPlanner.swift:202, 246`) | **ja** (`moveSuggestion`, `resetSuggestion`) | **ja, je Vorschlag** (`revise`, `undoRevision`); kein Einstieg „über alle“ |
| 7 | **Erfassen: Mahlzeit schätzen** | `MealEstimator.swift:52–53` (`meal_estimate`); Vorschau `Tagwerk/Capture/MealSheet.swift` (Phasen `:17`, Posten `:357–392`) | „Sichern“ (`:56–62`) | **ja** (Titel, Posten, Werte, Menge, Posten entfernen und hinzufügen) | nur „Neu schätzen“ (`:286`), verwirft Handänderungen |
| 8 | **Einkauf: Rezept lesen → Zutaten** | `RecipeImporter.swift:163–164` (`recipe_ingredients`); Vorschau `RecipeResultView` (`Tagwerk/Shopping/RecipeSheets.swift:506–700`) | „Auf die Liste“ → `RecipeImporter.apply` (`:683`) | teilweise: an/aus je Zutat, Portionen (`:595–597`), „Auch als Rezept-Notiz sichern“ (`:626`); Name, Menge, Kategorie nicht | nein |
| 9 | **Rezept-Notiz sichern** (aus gelesenem Rezept) | dieselbe Anfrage wie Ort 8; `Tagwerk/Shopping/RecipeNoteSaveSheet.swift:58–110` | „Sichern“ → `RecipeNoteWriter` | teilweise: Titel, Portionen; Zutaten und Schritte nicht | nein |
| 10 | **Notizen: Rezept übersetzen** | `RecipeTranslator.swift:63–64` (`recipe_translation`); `RecipeTranslationModel.Phase.preview` (`Tagwerk/Notes/RecipeTranslationModel.swift:14–19`); Vorschau `RecipeTranslationSheet.swift:125–160` | „Original ersetzen“ / „Als Kopie sichern“ (`RecipeTranslationModel.swift:121–137`) | nein (Lesevorschau) | nein |
| 11 | **Einkauf: „Mit ChatGPT sortieren“** | `ShoppingSorter.swift:100–101` (`shopping_sort`); `ShoppingSortResultSheet` (`Tagwerk/Shopping/ShoppingSortSheets.swift:66–142`) | „Vorschlag übernehmen“ → `ShoppingSorter.apply` (`ShoppingListView.swift:168`) | teilweise: an/aus je Änderung | nein |
| 12 | **Einkauf: „Artikel übersetzen“** | `ShoppingTranslator.swift:54–55` (`shopping_translation`); `ShoppingTranslationResultSheet` (`Tagwerk/Shopping/ShoppingTranslationSheets.swift:59–150`) | „Übernehmen“ → `ShoppingTranslationModel.apply` (`:158`) | teilweise: an/aus je Artikel | nein |
| 13 | **Teilen: Mail zu Aufgabe** | `MailSummarizer.swift:60–70` (`mail_task`); `MailTaskModel` (`Tagwerk/Share/MailTaskModel.swift:145–200`), Blatt `MailTaskSheet.swift:135–220` | „Weiter“ → „Neue Aufgabe“; „Vorschlag übernehmen“ je Feld (`:220`) | **ja** (Titel, Notiz, Frist; von Hand geänderte Felder werden nicht überschrieben, `MailTaskModel.apply`, `:185–200`) | nein (nur erneut zusammenfassen) |
| 14 | **Geplant:** Zielkarten (Plan „Ernährung, Gewicht und Ziele“, G6) und Etikett lesen (E3) | noch nicht im Quelltext | geplant | geplant (`GoalAdjustSheet`, `FoodEditSheet`) | Ziele: im Chat |

Keine KI-Vorschläge und deshalb nicht im Umfang: Treffer aus Open Food Facts (Daten eines Dienstes, kein Modell), das Debug-Werkzeug `ChatGPTCaptureSection` (`#if DEBUG`), `RealtimeProbe`, Lesefunktionen des Assistenten (kein Vorschlag, nichts zu bestätigen).

### Einwilligungen und Sperren, die erhalten bleiben

| Funktion | Einwilligung bzw. Hinweis | Sperre |
|---|---|---|
| Mahlzeit schätzen | `mealEstimationConsent` (`Tagwerk/Persistence/AppSettings.swift:74`) | – |
| Sortieren, Artikel übersetzen | `shoppingSortConsent` mit `shoppingSortConsentVersion` (`:84–87, 295–303`) | – |
| Rezept lesen, Rezept übersetzen | `shoppingRecipeConsent` (`:89`; `RecipeTranslationSheet.swift:34–35, 105`) | Übersetzen nur im Ordner „Rezepte“ (`RecipeTranslationModel.isOffered`, `:47–51`) |
| Mail zusammenfassen | `mailSummaryConsent` (`:91`) | Adressen werden entfernt, Länge begrenzt (`MailSummarizer.swift:51–56`) |
| Vorschläge aus der Notiz | `noteSuggestionConsent` (`:116`) | nur Gedanken-Notizen (`NoteSuggestionModel.fetch`, `:93–96`) |
| Assistent mit Notizen | `noteAssistantConsent` (`:94`) | private Notizen nie (`NoteToolAccess`), Kurzform im Verlauf (`AppTools.storedForm`, `Tagwerk/AI/AppTools.swift:72–80`) |

## Das Muster (verbindlich, vorbehaltlich der Entscheidungen)

**Begriffe.** *Vorschlag*: eine Karte oder eine Zeile bzw. das Ganze einer Vorschau. *Stand*: die Werte eines Vorschlags jetzt, nach Handänderungen und Antworten. *Marke*: `byUser` („von dir angepasst“) oder `byAssistant` („von ChatGPT angepasst“). *Bezug*: ein Vorschlag (`one`) oder alle offenen eines Satzes (`all`).

1. **Von Hand ändern** (alle Orte): Ein Blatt oder eine Zeile mit den Feldern, die es für die Sache schon gibt. „Fertig“ schreibt den Stand in den Vorschlag zurück und setzt die Marke `byUser`. Der Vorschlag der KI bleibt gemerkt, „Zurück zum Vorschlag der KI“ stellt ihn wieder her (wie `resetSuggestion`).
2. **Rückfrage zu einem Vorschlag** (`one`):
   - *Karte:* kurze Einzelanfrage mit dem Antwortformat genau dieser Funktion. Gesendet werden der Name der Funktion, der Stand, die Marken und die Nachricht. Die Antwort enthält neue Werte und einen Satz; sie füllt die Felder (Marke `byAssistant`). Kann ChatGPT die Bitte ohne Nachschlagen nicht erfüllen, sagt der Satz das, und die Werte bleiben.
   - *Vorschau-Zeile:* dieselbe Anfrage wie unter 3, mit Bezug auf die Zeile; Tagwerk übernimmt aus der Antwort **nur** Änderungen an dieser Zeile.
3. **Rückfrage zu allen Vorschlägen** (`all`):
   - *Karten im Chat:* Die Nachricht geht als Chatnachricht hinaus; jede offene Karte bekommt statt „abgelehnt“ das Ergebnis „Rückfrage“ mit ihrem Stand und ihrer Marke. Das Modell legt einen neuen Satz vor; die alten Karten stehen als „Überarbeitet“ im Verlauf.
   - *Karten ohne Chat (Gedanken-Notiz):* eine zweite Einzelanfrage mit Notiztext, offenem Kartensatz samt Stand und Nachricht; Antwort ist ein neuer Kartensatz.
   - *Vorschau-Blätter:* eine zweite Einzelanfrage mit ursprünglicher Eingabe, aktuellem Stand samt Marken und Nachricht; Antwort im Format der ersten Anfrage.
4. **Festgelegt:** Was der Nutzer von Hand geändert hat, bleibt, solange die Nachricht es nicht betrifft. Bei Bezug `one` erzwingt Tagwerk das lokal. Bei Bezug `all` steht es in der Anweisung; ändert die Antwort eine festgelegte Zeile dennoch, ist sie sichtbar markiert.
5. **Rückgängig:** Nach jeder Antwort lässt sich genau der Stand davor wiederherstellen (ein Schritt, wie `revisionUndo`). Im Chat gibt es für `all` kein „Rückgängig“; die überarbeiteten Karten kann der Nutzer verwerfen.
6. **Ausführen:** unverändert über „Bestätigen“ / „Übernehmen“ / „Sichern“. Im Chat nennt das Funktionsergebnis dem Modell die ausgeführten Werte, dass der Nutzer sie geändert hat, und den ursprünglichen Vorschlag.

**Was je Ort passt:**

| Ort | Von Hand | Rückfrage zu einem | Rückfrage zu allen |
|---|---|---|---|
| 1–3 Assistent-Karten | Blatt „Anpassen“ mit Editor je Funktion | Zeile im Blatt (Einzelanfrage) | „Alle anpassen …“ (Chat) |
| 4 Sprechmodus | – (nur am Bildschirm) | – | Sprechen; Karten gehen als „Rückfrage“ zurück |
| 5 Gedanken-Notiz | wie 1 | wie 1 | Eingabezeile unter den Karten (zweite Einzelanfrage) |
| 6 Tag planen | vorhanden | vorhanden | neu: „Alle Vorschläge besprechen“ |
| 7 Mahlzeit | vorhanden | Zeile im Postenblatt | Eingabezeile unter der Schätzung |
| 8–9 Rezept lesen | neu: Name, Menge, Kategorie je Zutat | Zeile antippen, dann Eingabezeile | Eingabezeile unter den Zutaten |
| 10 Rezept übersetzen | neu: Vorschau bearbeitbar | – (ein Text, kein Einzelteil) | Eingabezeile unter der Vorschau |
| 11 Sortieren | neu: Kategorie je Artikel | Zeile antippen, dann Eingabezeile | Eingabezeile |
| 12 Artikel übersetzen | neu: Name je Artikel | Zeile antippen, dann Eingabezeile | Eingabezeile |
| 13 Mail | vorhanden | – (drei Felder, eine Rückfrage genügt) | Eingabezeile unter den Feldern |
| 14 Zielkarten, Etikett | geplant | Ziele: wie 1; Etikett: – (abgelesene Werte, „Neu lesen“) | Ziele: „Alle anpassen …“ |

**Editoren je Funktion (Ort 1–3, 5):**

| Funktion | Editor (vorhandene Felder) | Bemerkung |
|---|---|---|
| `create_task`, `update_task` | Titel, Notiz, Frist, Liste bzw. Ziel, Personen (Felder aus `Tasks/NewTaskSheet.swift`, `IssueTargetSheetModel`) | Ein Issue für andere Personen wird dadurch zur geschützten Karte |
| `reschedule_task`, `assign_to_day` | Datum bzw. Tag | |
| `create_time_block`, `create_event`, `update_event` | Titel, Beginn, Ende, Kalender (Felder aus `Planning/EventEditSheet.swift`) | |
| `set_day_hours`, `set_lunch` | Zeitfelder | |
| `add_comment` | Textfeld | |
| `update_shopping` | Name und Menge je Artikel (Felder aus `Shopping/ShoppingItemSheet.swift`) | |
| `assign_task` | Personenauswahl (`AssigneeSelection`) | bleibt Einzelbestätigung; Warnung wird neu berechnet |
| `plan_period` | Zeitraum | |
| `propose_nutrition_goals`, `propose_activity_goals` | `GoalAdjustSheet` (Zahlenfelder) | Plan „Ernährung, Gewicht und Ziele“, G6 |
| `complete_task`, `delete_event`, `link_event_to_task`, `mark_events_free` | keiner | kein „Anpassen“ (AN11a) |

## Review Focus

1. **Kein zweiter Schreibweg:** Eine angepasste Karte wird von derselben Funktion ausgeführt wie eine unveränderte; ungültige Werte führen zur bekannten Fehlermeldung. Tests in A1, B1.
2. **Einzelbestätigung auf dem geänderten Stand:** Wird eine Karte durch Anpassen zur geschützten Karte (andere Person, Issue ohne Person), nimmt „Alle bestätigen“ sie nicht mehr mit; die Warnung der Abgabe-Karte folgt den neuen Personen. Tests in A2, B3.
3. **Die übrigen Karten bleiben unberührt**, wenn zu einer Karte eine Rückfrage läuft; der Chatverlauf wächst dabei nicht. Tests in B4.
4. **Handänderungen gehen nicht still verloren:** Bei Bezug `one` ändert sich lokal nur der gemeinte Vorschlag; bei Bezug `all` sind überschriebene Handänderungen markiert und rückholbar. Tests in A3, D1–D5.
5. **Private Notizen:** Die Rückfrage zu Notiz-Vorschlägen sendet für Tagebuch, Bible Study und Traumtagebuch nichts; die Rückfrage der Rezept-Übersetzung gibt es nur, wo die Übersetzung angeboten wird. Tests in C2, D3.
6. **Gespeicherter Verlauf:** Angepasste Karten stehen mit den ausgeführten Werten und in Kurzform im gespeicherten Verlauf; Rückfragen zu einer Karte und in Vorschau-Blättern sind nicht gespeichert. Tests in A1, B4.
7. **Ohne Einwilligung, Anmeldung oder Netz** gibt es keine Rückfrage, das Ändern von Hand bleibt möglich. Tests in A3 und je Ort.
8. **Prüfungen der Antwort bleiben:** Übersetzungen behalten Zeilenzahl und Mengen, Sortierungen nennen nur vorhandene Artikel, Schätzungen bleiben im strengen Format. Tests in D1–D5.

---

## Strang A: Grundlage

### Task A1: `Conversation` kennt geänderte Karten

**Hängt ab von:** AN2a, AN3a.

**Files:** Modify `Packages/AIKit/Sources/AIKit/Conversation.swift`; Tests `ConversationTests`.

- [ ] **Step 1: Tests.** `adjust_replacesArgumentsOfPendingCall`, `adjust_unknownOrRunningCall_doesNothing`, `adjust_keepsOriginalForReset`, `resetAdjustment_restoresModelArguments`, `confirm_afterAdjust_runsEditedArguments`, `confirm_afterAdjust_outputNamesAdjustmentAndOriginal`, `confirm_withoutAdjust_outputUnchanged`, `messages_showAdjustedArguments`, `storableHistory_usesStoredFormOfAdjustedCall`, `restore_withOpenAdjustedCall_closesItAsInterrupted`.
- [ ] **Step 2:** `adjust(_ call: ToolCall, arguments: Data) -> ToolCall?`: ersetzt die Argumente des offenen Aufrufs in `pendingActions` **und** im Verlauf (`history`), merkt sich die Argumente des Modells je Aufruf-ID im Arbeitsspeicher (`originalArguments`) und gibt den neuen Aufruf zurück. `resetAdjustment(_:)` stellt sie wieder her. `isAdjusted(_:)` für die Marke.
- [ ] **Step 3:** `confirm(_:)`: Ist der Aufruf angepasst, wird das Ergebnis der Funktion um zwei Felder ergänzt (`"adjusted_by_user": true`, `"proposed": <Argumente des Modells>`), sofern das Ergebnis ein JSON-Objekt ist; andernfalls wird ein Satz angehängt. Fehlerergebnisse (`error`, `status: not_run`) bleiben auf oberster Ebene lesbar (`ActionCardView.error(in:)`, `ChatView.swift:333–338`).
- [ ] **Step 4:** Der Verlauf enthält damit die ausgeführten Werte; Karte, Zeitstempel, Speicherform und Suche im Verlauf brauchen keine Nebenablage. Ein beim Beenden der App offener, angepasster Aufruf wird wie bisher als unterbrochen geschlossen (`closeOpenCalls`, `:316–321`).
- [ ] **Step 5:** Commit `feat: let a pending tool call be adjusted before it is confirmed`.

### Task A2: Karte mit „Anpassen“ und Marke

**Hängt ab von:** AN1a, AN2a, AN11a.

**Files:** Modify `Tagwerk/AI/ChatView.swift` (`ActionCardView`), `Tagwerk/AI/AssistantModel.swift` (`ActionCard`, `adjust`, `resetAdjustment`), `Tagwerk/AI/ActionCardDescriber.swift`; Create `Tagwerk/AI/ProposalMark.swift`; Tests, UI-Test.

- [ ] **Step 1: Tests.** `card_threeButtons_whenEditorExists`, `card_twoButtons_forToolsWithoutEditor`, `card_showsMarkAfterAdjust`, `card_changeText_showsOldAndNew`, `adjustedIssueForOthers_becomesSingleConfirmation`, `confirmAll_includesAdjustedUnguardedCards`, `spokenCard_namesAdjustment`, UI-Test `actionCard_adjustButton_opensSheet`, Layouttest der drei Knöpfe bei größter Schriftstufe (Umbruch: „Bestätigen“ in eigener Zeile).
- [ ] **Step 2:** `ActionCard` bekommt `mark: ProposalMark?` und `canAdjust: Bool`; `ActionCardView` bekommt `onAdjust: (() -> Void)?` und zeigt den dritten Knopf nur, wenn er gesetzt ist. Die Marke steht neben dem Titel und im VoiceOver-Text.
- [ ] **Step 3:** `AssistantModel.adjust(_:arguments:)` ruft `Conversation.adjust` und speichert nichts (offene Karten überleben einen Neustart ohnehin nicht). `needsSingleConfirmation` und `batchConfirmable` (`AssistantModel.swift:210–218`) lesen den aktuellen Aufruf; es ist keine Änderung nötig, aber ein Test hält es fest.
- [ ] **Step 4:** Commit `feat: add an adjust button and mark to action cards`.

### Task A3: `ProposalRevision` und `FollowUpBar`

**Hängt ab von:** AN6a, AN8a, AN10a, AN13a.

**Files:** Create `Packages/TagwerkCore/Sources/TagwerkCore/ProposalRevision.swift`, Tests; `Tagwerk/Common/FollowUpBar.swift`; Modify `Tagwerk/Planning/SuggestionViews.swift` (`SuggestionConversation` nutzt das Bauteil).

- [ ] **Step 1: Tests.** `scopeOne_keepsEverythingButTheNamedItem`, `scopeAll_marksOverwrittenUserChanges`, `undo_restoresStateBeforeAnswer`, `undo_clearedByManualEdit` (wie `moveSuggestion`, das `revisionUndo` verwirft), `pinned_listedInRequest`, `followUpBar_hiddenWithoutConsentOrSignIn`, `followUpBar_disabledOffline_manualEditStillWorks`, bestehende Tests zu `SuggestionConversation` bleiben grün.
- [ ] **Step 2:** `ProposalRevision<Item>`: `Scope` (`one(id)`, `all`), `Mark`, `merge(current:answer:scope:)` (begrenzt eine Antwort auf den Bezug, setzt Marken), `Undo`. Reine Regeln, ohne Netz und ohne SwiftUI.
- [ ] **Step 3:** `FollowUpBar`: letzte Nachricht, Satz der Antwort mit „Rückgängig“, Schnellantworten, Eingabezeile mit Mikrofon (wie `SuggestionConversation`, `SuggestionViews.swift:494–640`), Fußzeile „Senden gibt … an ChatGPT“ mit dem Text der jeweiligen Funktion, Bezugs-Chip („Zu: Feta ✕“ / „Zu allen“). Zustände: bereit, sendet, Fehler mit „Erneut versuchen“, nicht verfügbar.
- [ ] **Step 4:** `SuggestionConversation` wird auf `FollowUpBar` umgestellt, ohne sichtbare Änderung; „Als Vorgabe merken“ bleibt dort.
- [ ] **Step 5:** Commit `feat: add shared follow-up rules and input bar for AI proposals`.

### Task A4: Einwilligungstexte und Hinweise

**Hängt ab von:** AN10a.

**Files:** Modify `Tagwerk/Capture/MealConsentSheet.swift`, `Tagwerk/Shopping/ShoppingSortSheets.swift` (`ShoppingSortConsentSheet`), `RecipeConsentView`, das Einwilligungsblatt der Mail-Zusammenfassung, `Tagwerk/Routines/NoteConsentSheet.swift`; Katalog.

- [ ] **Step 1: Tests.** `consentTexts_mentionFollowUps` (Katalogprüfung je Blatt), `existingConsent_staysValid` (kein Versionssprung bei `shoppingSortConsentVersion`).
- [ ] **Step 2:** Je Blatt ein Satz: „Wenn du zu einem Vorschlag etwas zurückschreibst, sendet Tagwerk dieselben Angaben noch einmal, dazu den Vorschlag mit deinen Änderungen und deine Nachricht.“ Die bestehenden Zusagen („Nicht gesendet werden …“) bleiben wörtlich.
- [ ] **Step 3:** Commit `docs: name follow-ups in the consent texts`.

---

## Strang B: Karten des Assistenten

### Task B1: Blatt „Anpassen“ mit Editoren für Aufgaben

**Hängt ab von:** A1, A2; AN1a, AN2a.

**Files:** Create `Tagwerk/AI/ProposalAdjustSheet.swift`, `Tagwerk/AI/ProposalEditor.swift` (Protokoll: Argumente ↔ Felder), `Tagwerk/AI/TaskProposalEditor.swift`; Modify `ChatView.swift`; Tests.

- [ ] **Step 1: Tests.** `taskEditor_roundTripsArguments` (unbekannte Felder der Argumente bleiben erhalten), `taskEditor_onlyOffersValuesTheToolAccepts` (Listen, Ziele, Personen aus denselben Quellen wie die Funktion), `adjust_thenConfirm_createsEditedTask`, `adjust_invalidCombination_showsToolErrorOnCard`, `resetToAssistant_restoresProposal`, `rescheduleEditor_date`, `assignToDayEditor_day`.
- [ ] **Step 2:** `ProposalEditor`: `init?(call:)`, `fields` (SwiftUI-Ansicht), `arguments() -> Data`. Ein Register ordnet Funktionsnamen Editoren zu; fehlt einer, hat die Karte kein „Anpassen“.
- [ ] **Step 3:** `ProposalAdjustSheet`: Titel „Vorschlag anpassen“, die Felder des Editors, „Zurück zum Vorschlag der KI“ (nur bei Marke), Fußtext „Geändert wird nur der Vorschlag …“, „Fertig“ ruft `AssistantModel.adjust`. Das Blatt hängt an `ChatView`, gesteuert über die Aufruf-ID.
- [ ] **Step 4:** Editoren für `create_task`, `update_task`, `reschedule_task`, `assign_to_day`.
- [ ] **Step 5:** Commit `feat: adjust task proposals by hand`.

### Task B2: Editoren für Termine, Zeitblöcke und Tageszeiten

**Hängt ab von:** B1.

**Files:** Create `Tagwerk/AI/EventProposalEditor.swift`, `DayHoursProposalEditor.swift`; Tests.

- [ ] **Step 1: Tests.** `eventEditor_roundTripsStartEndCalendar`, `eventEditor_endBeforeStart_notAccepted`, `timeBlockEditor_keepsTaskLink`, `updateEvent_onlyTimeBlocks` (die Sperre der Funktion gilt weiter), `dayHoursEditor_roundTrips`, `lunchEditor_roundTrips`, `planPeriodEditor_range`.
- [ ] **Step 2:** Editoren für `create_event`, `update_event`, `create_time_block`, `set_day_hours`, `set_lunch`, `plan_period` mit den Feldern des Terminblatts.
- [ ] **Step 3:** Commit `feat: adjust event and day proposals by hand`.

### Task B3: Editoren für Einkauf, Kommentar und Abgabe

**Hängt ab von:** B1.

**Files:** Create `Tagwerk/AI/ShoppingProposalEditor.swift`, `CommentProposalEditor.swift`, `AssignProposalEditor.swift`; Tests.

- [ ] **Step 1: Tests.** `shoppingEditor_renameAndQuantity`, `commentEditor_text`, `assignEditor_changesPeople`, `assignEditor_warningFollowsNewPeople` (`ActionCardDescriber.swift:208–227`), `assign_staysSingleConfirmation`, `assignEditor_onlyAssignablePeople`.
- [ ] **Step 2:** Editoren für `update_shopping`, `add_comment`, `assign_task`.
- [ ] **Step 3:** Commit `feat: adjust shopping, comment and hand-over proposals by hand`.

### Task B4: Rückfrage zu einer Karte

**Hängt ab von:** B1, A3; AN4a.

**Files:** Create `Tagwerk/AI/CardReviser.swift` (Einzelanfrage), Tests; Modify `ProposalAdjustSheet.swift`, `Tagwerk/AI/DemoAITransport.swift`.

- [ ] **Step 1: Tests.** `request_containsToolSchemaCurrentArgumentsMarksAndComment`, `request_containsNoChatHistoryAndNoNoteText`, `answer_fillsFieldsAndSetsAssistantMark`, `answer_invalidForSchema_isRejectedWithMessage`, `answer_cannotChange_keepsValuesAndShowsSentence`, `undo_restoresFieldsBeforeAnswer`, `otherPendingCards_untouched`, `conversationHistory_unchangedByFollowUp`, `signedOut_hidesFollowUp`, `noteDerivedCard_followUpNeedsNoteConsent` (im Chat mit Notiz-Zugriff läuft die Rückfrage nur bei `noteAssistantConsent`).
- [ ] **Step 2:** `CardReviser.revise(call:definition:marks:comment:)`: eine Anfrage, Antwortformat `{ "arguments": <Schema der Funktion>, "message": string, "changed": bool }` (streng). Anweisung (englisch): nur die genannten Werte ändern, festgelegte Werte nur ändern, wenn die Nachricht sie meint, keine Kennungen erfinden, bei fehlendem Wissen `changed: false` und einen Satz.
- [ ] **Step 3:** `ProposalAdjustSheet` zeigt `FollowUpBar` unter den Feldern (Schnellantworten je Funktion, z. B. „Später“, „Kürzer“, „Andere Liste“). Die Antwort landet in den Feldern; erst „Fertig“ schreibt sie in die Karte.
- [ ] **Step 4:** Fußzeile: „Senden gibt diesen Vorschlag mit deinen Änderungen und deiner Nachricht an ChatGPT. Die anderen Karten bleiben, wie sie sind.“
- [ ] **Step 5:** Commit `feat: ask ChatGPT to revise a single proposal`.

### Task B5: „Alle anpassen …“ im Chat

**Hängt ab von:** A1, A2; AN5a, AN12a.

**Files:** Modify `Packages/AIKit/Sources/AIKit/Conversation.swift` (`revise(comment:)`), `AssistantModel.swift`, `ChatView.swift` (Knopf, Bezugs-Chip, Kartenstatus „Überarbeitet“), `Tagwerk/AI/AssistantModel.swift` (Anweisungen); Tests.

- [ ] **Step 1: Tests.** `revise_closesOpenCallsWithCurrentArgumentsAndMarks`, `revise_outputIsNotTheDeclinedOutput`, `oldCards_showRevisedStatus`, `send_withoutScope_behavesAsToday` (frei tippen verwirft weiter), `revise_guardedCardsStayGuardedInNewSet`, `revise_roundLimitStillApplies`, `voiceMode_spokenChange_usesRevise`, `instructions_explainRevisionOutput`, `storedHistory_keepsRevisionOutputs`.
- [ ] **Step 2:** `Conversation.revise(comment:)`: wie `send`, schließt offene Aufrufe aber mit `{"status":"revision_requested","current":<Stand>,"adjusted_by_user":<bool>}`. `ChatMessage.ActionStatus` bekommt `revised`; `status(of:output:)` (`Conversation.swift:242–246`) erkennt es am Ergebnis.
- [ ] **Step 3:** `ChatView.composer` (`:220–232`): neben „Alle bestätigen (N)“ der Knopf „Alle anpassen …“ (ab einer offenen Karte); er setzt den Bezugs-Chip „Zu allen N Vorschlägen ✕“ über die Eingabezeile und den Fokus hinein. Mit Chip ruft „Senden“ `revise`, ohne Chip `send`. Fußzeile unter der Eingabe nennt, was mitgeht.
- [ ] **Step 4:** Anweisungen des Assistenten: Bei „Rückfrage“ die genannten Vorschläge mit dem genannten Stand neu vorlegen; vom Nutzer geänderte Werte beibehalten, außer die Nachricht meint sie; nicht gemeinte Vorschläge unverändert wiederholen.
- [ ] **Step 5:** Sprechmodus: Eine gesprochene Änderung bei offenen Karten läuft über `revise` statt `send`; das Blatt „Anpassen“ wird im Sprechmodus nicht angeboten.
- [ ] **Step 6:** Commit `feat: revise all open proposals in the chat`.

---

## Strang C: Gedanken-Notiz

### Task C1: „Anpassen“ auf Notiz-Karten

**Hängt ab von:** B1–B3.

**Files:** Modify `Tagwerk/Routines/NoteSuggestionModel.swift` (`adjust`, Marke je Karte), `Tagwerk/Routines/NoteField.swift`; Tests.

- [ ] **Step 1: Tests.** `adjust_rewritesCallLikeSetTarget`, `adjust_keepsResolvedIssueTarget`, `adjustedCard_confirmRunsEditedCall`, `adjust_issueForOthers_leavesBatch`, `reset_dropsAdjustments`.
- [ ] **Step 2:** `NoteSuggestionModel.adjust(_:arguments:)` nach dem Muster von `setTarget` (`:148–160`); `Card` bekommt `mark` und `proposed`. `NoteField.suggestionSection` (`:299–325`) reicht `onAdjust` an `ActionCardView` und öffnet dasselbe `ProposalAdjustSheet` (am Blatt, nicht an der Zeile).
- [ ] **Step 3:** Commit `feat: adjust suggestions from a thoughts note by hand`.

### Task C2: Rückfragen zu Notiz-Vorschlägen

**Hängt ab von:** C1, B4, A3; AN6a, AN7b.

**Files:** Modify `NoteSuggestionModel.swift` (`revise(comment:)`), `NoteField.swift`; Tests.

- [ ] **Step 1: Tests.** `revise_privateKinds_sendNothing` (Tagebuch, Bible Study, Traumtagebuch; die gespeicherte Art zählt mit, wie in `fetch`, `:93–96`), `revise_withoutConsent_sendsNothing`, `revise_sendsNoteOpenCardsMarksAndComment`, `revise_doneAndDeclinedCards_notSent`, `revise_answerReplacesOpenCardsOnly`, `revise_noteTextInNoLogAndNoError`, `revise_dropsLateAnswerAfterReset` (Zähler `generation`), `undo_restoresPreviousCards`, `singleCardFollowUp_usesCardReviser`.
- [ ] **Step 2:** `revise(comment:)`: eine Anfrage wie `fetch`, mit dem zusätzlichen Abschnitt „Current suggestions“ (offene Karten als Funktionsname und Stand, Marke `fixed_by_user`) und der Nachricht. Antwort sind Funktionsaufrufe; sie ersetzen die offenen Karten, ausgeführte und verworfene bleiben stehen. Höchstens fünf Karten wie bisher.
- [ ] **Step 3:** `FollowUpBar` unter den Karten („Zu den Vorschlägen etwas sagen …“); die Rückfrage zu einer Karte läuft im Blatt „Anpassen“ über `CardReviser`.
- [ ] **Step 4:** Commit `feat: follow up on suggestions from a thoughts note`.

---

## Strang D: Vorschau-Blätter

Gemeinsam für D1–D5: Die zweite Anfrage nutzt das Antwortformat der ersten und läuft durch dieselbe Normalisierung. Gesendet wird die ursprüngliche Eingabe (solange das Blatt sie hält, AN7b), der Stand als JSON mit `fixed_by_user` je Eintrag und die Nachricht. Bezug `one` begrenzt Tagwerk lokal über `ProposalRevision.merge`.

### Task D1: Mahlzeit

**Hängt ab von:** A3, A4.

**Files:** Modify `Tagwerk/Capture/MealEstimator.swift` (`revise(text:jpeg:items:scope:comment:)`), `Tagwerk/Capture/MealSheet.swift`, `Tagwerk/AI/DemoAITransport.swift`; Tests.

- [ ] **Step 1: Tests.** `revise_requiresMealConsent`, `revise_sendsTextPhotoItemsAndComment`, `revise_scopeItem_changesOnlyThatItem`, `revise_scopeAll_keepsFixedItemsUnlessNamed`, `revise_strictSchema`, `undo_restoresDraft`, `newEstimate_stillDiscardsEverything` („Neu schätzen“ bleibt), `existingMeal_withoutOriginalInput_sendsItemsOnly`, `followUp_sendsNoGoalsNoHealthNoEarlierMeals`.
- [ ] **Step 2:** `FollowUpBar` unter den Posten (Schnellantworten „Größere Portion“, „Kleinere Portion“, „Genauer aufteilen“); im Postenblatt mit Bezug auf den Posten. Von Hand geänderte Posten tragen die Marke.
- [ ] **Step 3:** Die Zusage in `MealConsentSheet` („Nicht gesendet werden Daten aus Health, deine Ziele und frühere Einträge“) bleibt wahr: gesendet wird nur die Mahlzeit, die gerade im Blatt steht. Wird eine gespeicherte Mahlzeit bearbeitet, gilt sie als die aktuelle Mahlzeit, nicht als früherer Eintrag; der Text der Fußzeile sagt, was mitgeht.
- [ ] **Step 4:** Commit `feat: follow up on a meal estimate`.

### Task D2: Rezept lesen (Zutaten und Rezept-Notiz)

**Hängt ab von:** A3, A4; AN9a.

**Files:** Modify `Tagwerk/Shopping/RecipeImporter.swift` (`revise`), `Tagwerk/Shopping/RecipeSheets.swift` (`RecipeResultView`, Zeilenblatt), `RecipeNoteSaveSheet.swift`; Tests.

- [ ] **Step 1: Tests.** `row_edit_nameQuantityCategory`, `row_edit_categoryFromOwnListOnly`, `editedRow_keepsMarkThroughServingsScaling`, `revise_requiresRecipeConsent`, `revise_sendsSourceWhileSheetHoldsIt`, `revise_scopeRow_changesOnlyThatRow`, `revise_deselectedRows_stayDeselected`, `apply_usesEditedCandidates`, `noteSave_usesSameRevisedResult`.
- [ ] **Step 2:** Tippen auf eine Zutat öffnet ein kleines Blatt (Name, Menge mit `ValueStepper`/Textfeld, Kategorie aus den eigenen Kategorien); der Haken bleibt das Abwählen.
- [ ] **Step 3:** `FollowUpBar` unter den Zutaten („Ohne Gewürze“, „Mengen runden“, „Fehlt etwas?“). `RecipeNoteSaveView` zeigt denselben Stand.
- [ ] **Step 4:** Commit `feat: adjust and follow up on recipe ingredients`.

### Task D3: Rezept übersetzen

**Hängt ab von:** A3, A4; AN9a.

**Files:** Modify `Tagwerk/Shopping/RecipeTranslator.swift` (`revise`), `Tagwerk/Notes/RecipeTranslationModel.swift` (`Phase.preview` mit bearbeitetem Text, `revise`, `undo`), `RecipeTranslationSheet.swift`; Tests.

- [ ] **Step 1: Tests.** `preview_editable_replaceUsesEditedText`, `editedText_brokenStructure_blocksReplaceWithMessage` (die Prüfung „liest sich als Rezept, Mengen unverändert“ läuft vor dem Schreiben erneut), `revise_onlyWhereOffered` (`isOffered`), `revise_requiresRecipeConsent`, `revise_keepsIndicesAndQuantities`, `revise_noteChangedMeanwhile_reportsIt` (wie `replace`, `:121–131`), `undo_restoresPreviousTranslation`, `noteText_inNoLog`.
- [ ] **Step 2:** Die Vorschau der Übersetzung wird ein Textfeld; „Original“ bleibt Lesevorschau. `FollowUpBar` darunter („Du statt Sie“, „Maßeinheiten lassen“).
- [ ] **Step 3:** Commit `feat: edit and follow up on a recipe translation`.

### Task D4: Einkauf sortieren

**Hängt ab von:** A3, A4; AN9a.

**Files:** Modify `Tagwerk/Shopping/ShoppingSorter.swift` (`revise`), `ShoppingSortSheets.swift` (`ShoppingSortResultSheet`), `ShoppingListView.swift`; Tests.

- [ ] **Step 1: Tests.** `row_pickCategory_existingOrProposedNew`, `revise_requiresCurrentSortConsent` (`hasShoppingSortConsent`), `revise_sendsItemNamesCategoriesProposalAndComment`, `revise_unknownItemsInAnswer_dropped`, `revise_scopeRow_changesOnlyThatRow`, `apply_usesEditedProposal`, `newCategory_onlyCreatedWhenStillUsed`.
- [ ] **Step 2:** Tippen auf eine Zeile öffnet die Kategorieauswahl; `FollowUpBar` („Keine neuen Kategorien“, „Gröber einteilen“).
- [ ] **Step 3:** Commit `feat: adjust and follow up on the shopping sort proposal`.

### Task D5: Artikel übersetzen

**Hängt ab von:** A3, A4; AN9a.

**Files:** Modify `Tagwerk/Shopping/ShoppingTranslator.swift` (`revise`), `ShoppingTranslationModel.swift`, `ShoppingTranslationSheets.swift`; Tests.

- [ ] **Step 1: Tests.** `row_editName_trimmedAndNotEmpty`, `blockedRows_notEditable`, `revise_requiresCurrentSortConsent`, `revise_keepsQuantities`, `revise_scopeRow_changesOnlyThatRow`, `apply_renamesWithEditedNames`.
- [ ] **Step 2:** Tippen auf eine Zeile macht den neuen Namen tippbar; `FollowUpBar` („Britisches Englisch“, „Markennamen lassen“).
- [ ] **Step 3:** Commit `feat: adjust and follow up on translated shopping items`.

---

## Strang E: Mail und „Tag planen“

### Task E1: Mail zu Aufgabe

**Hängt ab von:** A3, A4.

**Files:** Modify `Tagwerk/Share/MailSummarizer.swift` (`revise`), `MailTaskModel.swift`, `MailTaskSheet.swift`; Tests.

- [ ] **Step 1: Tests.** `revise_requiresMailConsent`, `revise_sendsRedactedMailFieldsAndComment` (nie die Adresse, Länge begrenzt wie `summarize`), `revise_editedFields_sentAsFixed`, `revise_answerMarksChangedFieldsAsSuggested`, `undo_restoresFields`, `cancel_dropsRunningFollowUp`.
- [ ] **Step 2:** `FollowUpBar` unter den Feldern („Kürzer“, „Frist prüfen“, „Auf Deutsch“). Von Hand geänderte Felder gehen als festgelegt mit; ändert die Antwort sie, weil die Nachricht sie meint, tragen sie wieder die Vorschlags-Markierung (`suggestedFields`).
- [ ] **Step 3:** Commit `feat: follow up on the mail summary`.

### Task E2: „Alle Vorschläge besprechen“ bei „Tag planen“

**Hängt ab von:** A3; AN13a.

**Files:** Modify `Tagwerk/AI/AIPlanner+Revision.swift` (`revise(batch:comment:)`), `Tagwerk/Planning/AIPlanBar.swift`; Tests.

- [ ] **Step 1: Tests.** `reviseBatch_sendsAllOpenSuggestionsWithoutFocus`, `reviseBatch_keepsMovedSuggestions`, `reviseBatch_undo`, bestehende Tests zu `revise(_:comment:)` bleiben grün.
- [ ] **Step 2:** In der Planleiste (`AIPlanBar.swift:106–144`) neben „Alle übernehmen“ der Einstieg „Alle Vorschläge besprechen“; er öffnet ein Blatt mit `FollowUpBar` und der Liste der Vorschläge. Die Anfrage ist die bestehende, ohne hervorgehobenen Vorschlag.
- [ ] **Step 3:** Commit `feat: discuss all planning suggestions at once`.

---

## Gerätetests

| Bereich | Prüfung |
|---|---|
| Karte | Drei Knöpfe bei kleinster und größter Schrift, hell und dunkel; VoiceOver liest Marke und Aktion „Anpassen“. |
| Von Hand | Aufgabe, Termin, Zeitblock, Einkauf, Kommentar: ändern, bestätigen, Ergebnis in der App prüfen. Ungültige Kombination zeigt die Fehlermeldung auf der Karte. |
| Abgabe | Person in „Anpassen“ ändern: Warnung nennt die neuen Personen; „Alle bestätigen“ lässt die Karte aus. |
| Rückfrage zu einer Karte | Drei offene Karten, Rückfrage zu einer: die beiden anderen bleiben offen und bestätigbar; im Chat steht keine neue Nachricht. Bitte, die Nachschlagen braucht („anderer Kalender“): Satz statt Änderung. |
| Alle anpassen | Mit Handänderung an einer Karte: Der neue Satz behält sie. Alte Karten stehen als „Überarbeitet“. Nach Neustart ist der Verlauf lesbar. |
| Folgeantwort | Nach dem Bestätigen einer angepassten Karte nennt der Assistent die ausgeführten Werte. |
| Sprechmodus | Änderung ansagen bei offenen Karten: neue Karten werden angesagt; kein Blatt öffnet sich. |
| Gedanken-Notiz | Rückfrage sendet nur bei Gedanken-Notizen; im Tagebuch gibt es weder „Vorschläge holen“ noch die Eingabezeile. Diagnose: kein Netzverkehr. |
| Vorschau-Blätter | Je Blatt: Zeile von Hand ändern, Rückfrage zur Zeile (nur sie ändert sich), Rückfrage zu allem, „Rückgängig“, Übernehmen mit geändertem Stand. |
| Übersetzung | Bearbeitete Übersetzung mit zerstörter Zutatenliste lässt sich nicht übernehmen; die Meldung nennt den Grund. |
| Ohne Netz / ohne Anmeldung / ohne Einwilligung | Eingabezeile fehlt oder ist ausgegraut; von Hand ändern und Bestätigen funktionieren. |
| Tastatur | Eingabezeile im Blatt verdeckt weder Felder noch „Fertig“; Schließen der Tastatur wie in `2026-11-19-keyboard-dismissal.md`. |

## Reihenfolge und Abhängigkeiten

1. **Stufe 1 (Karten):** A1 → A2 → B1 → B2, B3 → A3 → B4 → B5 → C1 → C2. A4 kann parallel laufen.
2. **Stufe 2 (Vorschau-Blätter):** D1, D2, D4, D5 parallel (höchstens drei Agenten), danach D3.
3. **Stufe 3:** E1, E2.

**Fremde Abhängigkeiten:**
- Plan `2026-11-21-ernaehrung-gewicht-ziele.md`: G6 (Zielkarten) braucht A1 und A2 dieses Plans und liefert `GoalAdjustSheet` als Editor für die beiden Zielfunktionen; die Rückfrage zu einer Zielkarte (B4) und „Alle anpassen …“ (B5) gelten dort ohne weitere Arbeit, sobald die Zielfunktionen im Register stehen. Die Gegenrechnung der Zielkarte wird nach jeder Anpassung neu gerechnet (G6 Step 4). E3 (Etikett) nutzt `FoodEditSheet` als Handanpassung und bekommt keine Rückfrage.
- D1 berührt `MealSheet.swift` und `MealEstimator.swift` wie die Tasks D1, D2 und E2 des Ernährungsplans; D1 dieses Plans nach jenen einplanen.
- `SuggestionViews.swift` wird in A3 umgebaut; laufende Arbeiten an „Tag planen“ vorher abschließen.

## Nicht im Umfang

- Ein gespeichertes Gespräch je Vorschau-Blatt (AN6b), geparkte Karten im Chat (AN4c).
- „Anpassen“ per Sprachbefehl (AN12b).
- Neue Funktionen des Assistenten oder neue Editoren, die es in der App noch nicht gibt (z. B. Wiederholungen von Terminen in der Karte).
- Lernen aus Anpassungen über das laufende Gespräch hinaus („Als Vorgabe merken“ bleibt auf „Tag planen“ beschränkt).
- Treffer aus Open Food Facts und das Etikett-Foto (kein Gespräch).

## Entscheidungen des Nutzers (jeweils mit Empfehlung)

Alle Tasks sind gegen die Empfehlungen geschrieben. Bilder und Varianten stehen im Mockup unter dem jeweiligen Kürzel.

| Kürzel | Frage | Empfehlung | Begründung |
|---|---|---|---|
| AN1 | Wo sitzt „Anpassen“ auf einer Karte? | **AN1a** Dritter Knopf, ein Blatt mit beiden Wegen | Ein Knopf, ein Ort für beide Wege; derselbe Aufbau wie auf der Zielkarte ZI3b. |
| AN2 | Was passiert nach dem Ändern von Hand? | **AN2a** Zurück zur Karte, Bestätigen bleibt eigener Schritt | Ändern und Ausführen bleiben getrennt; Warnungen und Einzelbestätigung greifen auf den geänderten Stand. |
| AN3 | Was erfährt ChatGPT im Chat von einer Handänderung? | **AN3a** Ausgeführte Werte und der ursprüngliche Vorschlag | Sonst beschreibt der Assistent danach etwas, das so nicht ausgeführt wurde. |
| AN4 | Mit ChatGPT über eine Karte im Chat schreiben | **AN4a** Kurze Anfrage nur zu dieser Karte | Die übrigen Karten bleiben unberührt, ohne Umbau des Gesprächsverlaufs. |
| AN5 | Mit ChatGPT über alle Karten schreiben | **AN5a** „Alle anpassen …“ mit Bezug in der Eingabezeile | Der aktuelle Stand samt Handänderungen geht mit; heute geht er verloren. |
| AN6 | Vorschau-Blätter: Form der Rückfrage | **AN6a** Eingabezeile mit Schnellantworten im Blatt | Dasselbe Muster wie bei „Tag planen“, ohne einen zweiten Chatverlauf zu speichern. |
| AN7 | Was geht bei einer Rückfrage im Vorschau-Blatt mit? | **AN7b** Dazu die ursprüngliche Eingabe | Korrekturen wie „da fehlt das Mehl“ brauchen die Quelle; es geht keine neue Art von Daten hinaus. |
| AN8 | Handänderungen bei einer Rückfrage | **AN8a** Festgelegt, außer die Nachricht betrifft sie | Gleiche Regel wie bei „Tag planen“; Handarbeit geht nicht still verloren. |
| AN9 | Listen-Vorschauen von Hand ändern | **AN9a** Zeile antippen und Wert ändern | Ohne das wäre „manuell anpassen“ in drei Blättern nur Abwählen. |
| AN10 | Einwilligung und Hinweis | **AN10a** Fußzeile an der Eingabe, Satz im Einwilligungstext, kein erneutes Fragen | Dieselbe Art von Daten an denselben Empfänger; der Hinweis steht dort, wo gesendet wird. |
| AN11 | Karten ohne anpassbare Werte | **AN11a** Kein „Anpassen“ | Löschen, Erledigen und Verknüpfen haben nichts einzustellen. |
| AN12 | Sprechmodus | **AN12a** Unverändert; gesprochene Änderung geht als Rückfrage hinaus | Ein Blatt mit Feldern passt nicht zum freihändigen Gebrauch. |
| AN13 | „Tag planen“ angleichen | **AN13a** Nur ergänzen: „Alle Vorschläge besprechen“, gemeinsames Bauteil | Beide Wege gibt es dort schon; es fehlt nur der Einstieg „über alle“. |
| AN14 | Reihenfolge der Umsetzung | **AN14a** In drei Stufen | Die Karten-Grundlage wird für die Zielplanung gebraucht und sollte zuerst am Gerät geprüft sein. |

### Weitere offene Fragen

| Nr. | Frage | Empfehlung |
|---|---|---|
| 1 | **Angepasste Argumente im Verlauf:** Die Karte im Verlauf zeigt die ausgeführten Werte, weil A1 die Argumente des Aufrufs ersetzt; das Modell sieht „seinen“ Aufruf also mit den Werten des Nutzers und im Ergebnis den ursprünglichen Vorschlag. Alternativ bleibt der Aufruf unverändert und die Änderung steht in einer Nebenablage. | Ersetzen. Eine Ablage für Karte, Speicherform und Neustart entfällt; das Ergebnis erklärt dem Modell die Abweichung. |
| 2 | **Gesprächskontext bei der Rückfrage zu einer Karte:** nur die Karte, oder dazu die letzten Nachrichten des Chats? | Nur die Karte. Mehr Kontext brächte Notiztexte und Suchergebnisse in eine Anfrage außerhalb des Gesprächs; wer Kontext braucht, nutzt „Alle anpassen …“. |
| 3 | **Foto bei der Rückfrage zur Mahlzeit** erneut senden? | Ja, solange das Blatt es hält (AN7b); die Fußzeile nennt es. Kostet Datenvolumen bei jeder Rückfrage. |
| 4 | **Grenze für Rückfragen** je Vorschlag? | Keine feste Grenze; jede Rückfrage ist ein Tippen. |
| 5 | **Issue-Schnitt:** ein Issue je Stufe oder je Strang? | Je Stufe eines (drei Issues), Zielkarten bleiben im Issue der Zielplanung. |

## Risiken

1. **Zwei Mechanismen für Karten.** Die Rückfrage zu einer Karte (Einzelanfrage) und „Alle anpassen“ (im Gespräch) verhalten sich verschieden: Die erste kennt den Chat nicht und kann nichts nachschlagen. Nutzer können das als Unstimmigkeit erleben. Gegenmaßnahme: der Satz „dafür bitte ‚Alle anpassen‘“; ob das genügt, ist offen.
2. **„Alle anpassen“ hängt am Modell.** Tagwerk kann nicht erzwingen, dass nicht gemeinte Karten unverändert wiederkehren; eine Karte kann fehlen oder abweichen. Gegenmaßnahme: Anweisung, Test mit dem Demo-Transport, alte Karten bleiben als „Überarbeitet“ lesbar. Ein lokaler Vergleich alt/neu ist nicht geplant, weil neue Karten keine stabile Zuordnung zu alten haben.
3. **Umgeschriebene Aufrufe im Verlauf.** Das Modell sieht einen Aufruf mit Werten, die es nicht gewählt hat. Ob das Folgeantworten stört, ist nicht belegt (offene Frage 1).
4. **Editoren und Funktionen laufen auseinander.** Jede Funktion mit Karte braucht einen Editor, der genau ihre Argumente kennt; ein neues Feld in der Funktion fehlt sonst still im Blatt. Gegenmaßnahme: Round-Trip-Test je Editor, unbekannte Felder bleiben erhalten, ein Test listet Funktionen mit Karte ohne Editor und ohne Ausnahme.
5. **Einzelanfrage mit dem Schema einer Funktion.** Ein strenges Antwortformat aus den Parametern jeder Funktion setzt voraus, dass alle Definitionen im strengen Format gültig sind (alle Felder Pflicht, `null` erlaubt). Das ist für `AppTools+Definitions.swift` nicht geprüft.
6. **Mehr gesendete Daten.** Jede Rückfrage sendet die ursprüngliche Eingabe erneut (Foto, Mailtext, Notiz). Die Einwilligung deckt die Art der Daten, nicht die Häufigkeit; die Fußzeile ist die einzige Stelle, die es sagt.
7. **Umfang.** 18 Tasks über fast alle KI-Funktionen. Ohne die drei Stufen und Gerätetests je Stufe drohen Fehler im gemeinsamen Bauteil an vielen Stellen zugleich.
8. **Bearbeitbare Übersetzung.** Ein frei bearbeiteter Rezepttext kann die Struktur der Notiz zerstören; die Prüfung vor dem Ersetzen ist die Absicherung, ihre Trennschärfe ist am Gerät zu prüfen.
9. **Platz.** Drei Knöpfe auf der Karte, eine Eingabezeile mit Schnellantworten und Fußzeile im Blatt: bei großer Schrift und offener Tastatur eng.

## Nicht verifiziert

- Ob sich `NewTaskSheet`, `EventEditSheet` und `ShoppingItemSheet` als Felder in ein fremdes Blatt einbetten lassen oder eigene, schlanke Feldgruppen nötig sind; die Dateien wurden nur dem Namen nach geprüft.
- Die Parameter der einzelnen Funktionen in `AppTools+Definitions.swift` (Pflichtfelder, erlaubte Werte) wurden nicht gelesen; die Editor-Tabelle ist aus den Kartentexten in `ActionCardDescriber.swift` abgeleitet.
- `MealSheet.swift`, `RecipeSheets.swift`, `RecipeNoteSaveSheet.swift`, `ShoppingSortSheets.swift`, `ShoppingTranslationSheets.swift`, `MailTaskSheet.swift` und `SuggestionViews.swift` wurden nur in Ausschnitten gelesen; Zeilenangaben sind vor der Umsetzung zu bestätigen.
- Welche Eingabe die Vorschau-Blätter nach der ersten Antwort noch im Speicher halten (Foto, Rezeptquelle bei einem Link, Mailtext), ist je Blatt zu prüfen; davon hängt AN7b ab.
- Verhalten des Modells bei „Rückfrage“-Ergebnissen und bei umgeschriebenen Aufrufen; Zuverlässigkeit der Einzelanfrage je Funktion.
- Wie der Sprechmodus (`VoiceModeMachine`, `confirmCards`) eine gesprochene Änderung heute von einer Bestätigung unterscheidet; B5 Step 5 setzt voraus, dass diese Stelle `send` ruft.
- Weitere Orte mit KI-Vorschlägen außerhalb der gefundenen Anfragestellen (`responder.respond` in `Tagwerk/`, zehn Treffer) und der Karten des Gesprächs gibt es laut Suche nicht; Erweiterungen (Widget, Share-Erweiterung) wurden nicht eigens durchsucht.
- Kein Build, kein Testlauf, kein Simulator in dieser Runde.
