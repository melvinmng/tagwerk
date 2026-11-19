# Übernacht-Protokoll 19.11.2026

Jede umsetzende Instanz hängt hier einen eigenen Abschnitt an.

## #136 Zuweisung

Plan: `plans/2026-11-19-issue-assignees.md` · Spec: `specs/2026-11-19-issue-assignees-design.md` · Branch `feat/search-issues-planning`.
Umgesetzt sind die Tasks 1–10. Task 0 (Spike) und Task 11 (Geräteprüfung) sind manuell und offen.

Commits (in Reihenfolge): `7f63b0f` Kernmodell · `549c8f1` GitHubKit lesen · `993febb` GitHubKit schreiben · `06456ac` Listenmodell und Planung · `c6dc3ad` Blatt „Neue Aufgabe“ · `47494e5` Kapsel · `d7fdb7a` Editor · `02507da` Assistent: Werkzeuge · `8e8f556` Assistent: Karte, Instruktionen, Sprachmodus · `91631a9` Datenschutzhinweis und Texte.

### (a) Entscheidungen

Jede Entscheidung nennt die Optionen, die Wahl und das Risiko, falls sie falsch ist.

1. **Spikes S1–S4 nicht ausgeführt, Annahmen des Specs übernommen.** Optionen: warten oder mit den Vorgaben bauen. Gewählt: bauen. Damit gilt ungeprüft: der Scope `repo` reicht (kein Scope-Umbau), Zuweisen ändert `updatedAt` (Zugewiesene stehen nicht in `GitHubMapping.version`), GitHub verwirft nicht zuweisbare Logins still (kein eigener Fehlertext für 4xx), das eigene Austragen läuft über `DELETE …/assignees`. Risiko: Fällt ein Spike negativ aus, greifen die im Plan (Task 0) genannten Zusätze; sie sind nicht gebaut.
2. **`AssigneeSelection.names(… language: VoiceLanguage = .app)` statt `locale: Locale`.** Ein `Locale` wählt nur Formate, nicht die Sprache des Katalogs; die englische Karte (`describe(_:language:)`) braucht `Localized.string`. Risiko: Signatur weicht vom Plan-Interface ab; spätere Pläne nutzen sie nicht.
3. **Kapseltitel mit Textplatzhalter für die Nummer** (`%@ an %@`, `%@ ohne Zuweisung`, aufgerufen mit „#151“) statt `#%lld an %@`. Grund: Ohne Nummer in der URL entsteht „Issue an lea-m“ statt „#0 an …“. Die sichtbaren Texte entsprechen dem Spec. Risiko: zwei Katalogschlüssel heißen anders als in Spec §5.8.
4. **Fußtext bei drei oder mehr anderen ohne mich:** „Das Issue wird 3 Personen zugewiesen und erscheint danach nicht in deinen Aufgaben.“ Das Spec nennt nur „dir und 3 weiteren Personen“. Alternative wäre die volle Liste gewesen; gewählt wurde die Zählform wie in Zeile und Kapsel.
5. **Warnung bei mehreren verworfenen Logins behält den Wortlaut des Specs** („lea-m und sam konnte nicht zugewiesen werden.“). Eine Pluralform wäre sprachlich richtig, steht aber nicht im Spec. Risiko: holpriger Satz im seltenen Fall mehrerer verworfener Logins.
6. **Editor bietet „Ich“ nicht an, wenn ich weder zugewiesen noch zuweisbar bin**; bis die Liste geladen ist, zeigt das Menü nur die Zugewiesenen (Spec §5.6). Im Blatt wird „Ich“ dagegen immer angeboten (F5).
7. **`gitHubTarget`:** leeres `project_ids: []` wird wie `null` behandelt (die Quelle verlangt mindestens ein Project), der Repository-Name wird ohne Groß-/Kleinschreibung verglichen und in der Schreibweise des Katalogs geschrieben. Unbekannte Angaben erhalten eigene Fehltexte („Dieses Repository steht nicht in der Liste von list_github_targets.“).
8. **Nicht ladbare Zuweisbare** melden den vorhandenen Text „Personen konnten nicht geladen werden“ (Werkzeuge `list_assignees` und `create_task`), statt eines neuen Textes.
9. **Karte ohne auflösbares Ziel:** Fehlt der gespeicherte Katalog, zeigt die Karte das Repository aus dem Argument und „Project fehlt“; lässt sich nur das Project nicht auflösen, bleibt das Repository stehen.
10. **`OpenCards.guarded`:** „alle bestätigen“ wird auch dann abgelehnt, wenn die einzige offene Karte geschützt ist (gleiches Verhalten wie bei Löschungen); ein einfaches „Ja“ bestätigt sie.
11. **`SaveQuestion.handOver` hat Vorrang vor allen anderen Rückfragen**, auch vor `effortReach` (laut Spec kollidieren sie nicht; der Test legt es trotzdem fest).
12. **Anlegen über das Blatt mit ausschließlich verworfenem Login:** Warnung und Kapsel „ohne Zuweisung“ erscheinen beide (Review Focus 3).
13. **`apply` lädt den eigenen Login nach der Versionsprüfung und vor dem Schreiben** (nur wenn er unbekannt ist und Zuweisungen geändert werden). Alternative wäre vor dem ersten Lesen gewesen; so bleibt der Konfliktfall ohne Zusatzabruf.
14. **String Catalog:** Der App-Katalog bleibt im bisherigen JSON-Format (ein Lauf von `sync-strings.sh` hätte rund 13.000 Zeilen nur umformatiert); drei veraltete Schlüssel (zwei alte Fußtexte, alter Datenschutzhinweis) sind entfernt; deutsche Pluralformen für „%lld Personen“, „%lld weiteren Personen“ und „%lld geplante Zeitblöcke werden gelöscht.“ sind von Hand ergänzt, weil `check-strings.py` sie verlangt. Englische Texte stehen zusätzlich in `scripts/translations/en.json`.
15. **Zusätzliche Texte, die das Spec nicht nennt:** „Öffnet das Issue im Browser“ (VoiceOver-Hinweis des Kapselknopfs), „Vergeben: %@. Auf GitHub öffnen verfügbar.“ (Ansage), „Das Issue verschwindet aus Aufgaben und Planung.“ (Rückfrage ohne Nummer), „Mindestens ein Projekt wählen.“ (als eigener Satz), „Repository, Projects und Zugewiesene gibt es nur bei GitHub-Issues.“, „Project %@“.

### (b) Abweichungen vom Plan

- Neue Tests liegen in eigenen Suites mit eigenem Aufbau statt in den bestehenden: `TaskListAssigneeTests`, `TaskEditorAssigneeTests`, `AppToolsGitHubTests`, `AssistantGitHubCardTests`, `AssigneeLoadTests`. Dateien wie im Plan.
- Zusätzliche Hilfen: `AssigneeSelection.sorted(_:me:)` und `isMe`, `AssigneeLoad.logins(for:)`, `TaskEditorModel.setAssignees(_:candidates:)`, `HandedOverCapsule` (eine Ansicht für „Aufgaben“ und „Planen“), `AppTools.GitHubTargetError.message`, `Arguments.optionalStrings`.
- Task 8: Der rote Lauf bestand nur aus dem Übersetzungsfehler der neuen Tests; ein eigener Lauf vor der Umsetzung wurde nicht gestartet. Bei allen anderen Tasks wurde der rote Lauf ausgeführt und gelesen.
- `app/test-all.sh` lief vor jedem Commit ab Task 4. Die Commits der Tasks 1–3 wurden mit den Pakettests (`TagwerkCore`, `GitHubKit`) und den betroffenen App-Suites geprüft.
- Der Commit `549c8f1` (Task 2) enthält versehentlich die zu dem Zeitpunkt unversionierte Datei `plans/2026-11-19-phase-7-routines.md`; der spätere Commit `bb918c5` einer anderen Instanz hat sie überarbeitet. Inhaltlich ohne Folge.
- `DemoAITransport` sendet bei `create_task` jetzt die drei neuen Felder mit `null`.
- Die Sichtprüfungen im Simulator aus Task 5 Schritt 4 und Task 6 Schritt 4 entfielen (siehe c).

### (c) Offene manuelle Prüfungen am Gerät

- **S1** `GET …/assignees` und Zuweisen mit dem vorhandenen Token.
- **S2** Zuweisen ändert `updatedAt` des Issues.
- **S3** Stilles Verwerfen eines nicht zuweisbaren Logins.
- **S4** `DELETE …/assignees` mit dem eigenen Login im eigenen Repository.
- **S5** Menü mit rund 30 Einträgen und 10 gewählten bleibt bedienbar.
- **S6** Sprachmodus: Zuweisungskarte plus zweite Karte, „alle“ wird abgelehnt, einzelnes „Ja“ bestätigt.
- Abnahmekriterien 1–10 aus Spec §9 am Gerät.
- Sichtprüfung: Zeile „Zugewiesen“ im Blatt und im Editor, Fußtext, Rückfrage „Abgeben“, Kapsel „Vergeben“ in „Aufgaben“ und „Planen“ (8 Sekunden, Knopf öffnet GitHub).
- Benachrichtigung und Widget nach dem Abgeben eines Issues mit Fälligkeit (als Unit-Test abgedeckt, am Gerät ungeprüft).
- Dunkel, hell, größte Schriftstufe, Englisch, VoiceOver für die neuen Elemente.

### (d) Bekannte Lücken / nicht umgesetzt

- Für Menüzeile, Kapsel und Rückfrage gibt es keine UI-Tests; getestet ist die Logik dahinter (Texte, Reihenfolge, Ladezustand, Rückfrage-Entscheidung).
- Ohne S2 ist unbelegt, dass die Versionsprüfung fremde Änderungen an der Zuweisung erkennt.
- Weicht die Schreibweise des eigenen Logins im Entwurf von der GitHubs ab, merkt `create` das Issue nicht in `records` (die Regel `isVisible` blieb wie verlangt unverändert); die Liste zeigt es trotzdem, Kommentar und Issue-Chat gehen erst nach dem nächsten Laden. Blatt und Assistent schreiben immer GitHubs Schreibweise, der Fall ist dort nicht erreichbar.
- „Neu laden“ im Konfliktfall lädt die Zuweisbaren nicht erneut (Haltezeit 5 Minuten gilt weiter).
- Nicht-Ziele des Specs (§2) sind nicht gebaut: Filter „Vergeben“, fremde Repositories, Avatare, Suche, „zuletzt benutzt“, Offline-Warteschlange, Zuweisen über `update_task`.
- Abschlussreview: Selbstreview des Autors, kein unabhängiger Reviewer (keine Subagenten erlaubt).

### (e) Testergebnis

`app/test-all.sh`, letzter Lauf nach dem letzten Code-Commit (`91631a9`), alle Stufen grün einschließlich „string catalogs“:

- AIKit 98, GitHubKit 129, HealthBridge 11, RemindersKit 64, TagwerkCore 501, App 789 Tests bestanden.
- Letzte Zeile: `ALL TESTS PASSED`
