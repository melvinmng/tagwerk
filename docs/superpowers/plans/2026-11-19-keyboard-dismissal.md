# Tastatur überall schließen (#184, #177)

**Ziel:** In der ganzen App schließt sich die Tastatur beim Tippen auf eine leere Fläche und beim Scrollen. Felder ohne Return-Taste und mehrzeilige Felder bekommen einen „Fertig“-Knopf über der Tastatur. Damit ist #177 (Tagesabschluss) behoben.

**Rahmen:** Rein technische Umsetzung ohne Mockups. Optische Fragen kommen in das Design-Sammelissue. Keine Änderungen an `TODO.md`, kein `t3gh`.

## Bestand (Stand `main`)

- `scrollDismissesKeyboard(.interactively)` gibt es nur in `Search/SearchSheet.swift:55` und `AI/ChatView.swift:177`.
- Einen Tastatur-„Fertig“ gibt es nur in `Editor/EstimateField.swift:47-52` (`ToolbarItemGroup(placement: .keyboard)`, nur solange `isTyping`).
- Kein Hintergrund-Tipp und kein `resignFirstResponder`-Helfer.
- Ohne jedes Schließen: `Routines/NoteField.swift:174` (TextEditor, gemeinsam für `EveningSheet` und `MorningSheet`), `Routines/MorningSheet.swift:76`, `Notes/NoteEditorView.swift:24`, `Capture/MealSheet.swift:635` (`DecimalField`, Dezimaltastatur), `Capture/WorkoutSheet.swift:35` (Zifferntastatur) und alle Formular-Blätter (`NewTaskSheet`, `TaskEditorView`, `EventEditSheet`, `HabitSheet`, `ChecklistItemSheet`, `ShoppingItemSheet`, `MealItemEditor`, `WeekReflectionSections`).
- Eingabeleisten am Rand, bei denen die Tastatur nach dem Senden offen bleiben soll: `AI/ChatView.swift:225` (Composer), `Shopping/ShoppingInputBar.swift:110`, `Notes/NotesListView.swift:106` (captureBar), `Search/SearchSheet.swift:176` (header), `Planning/SuggestionViews.swift:545` (Composer), `Planning/UnplannedDrawer.swift:80`.

## Lösung

Drei Bausteine in einer neuen Datei `app/Tagwerk/Common/KeyboardDismissal.swift`. Gibt es einen passenderen Ordner für gemeinsame Modifier, wird dieser verwendet.

1. **Fenster-weiter Tipp-Erkenner.** Ein `UITapGestureRecognizer` am Key-Window, beim App-Start einmal installiert (z. B. über einen kleinen `UIViewRepresentable`-Anker in `RootView` oder über die Szene). Eigenschaften:
   - `cancelsTouchesInView = false`, `delaysTouchesBegan = false`; erkennt gleichzeitig mit allen anderen Gesten (`shouldRecognizeSimultaneouslyWith` → `true`). Zeilen, Knöpfe und Menüs funktionieren unverändert.
   - `gestureRecognizer(_:shouldReceive:)` gibt `false` zurück, wenn
     - kein Textfeld aktiv ist (billig prüfen, z. B. über Benachrichtigungen `keyboardWillShow`/`keyboardWillHide`, die einen Zustand pflegen),
     - der Tipp auf einem Texteingabe-View liegt (`UITextField`, `UITextView` oder ein Superview davon, über die View-Hierarchie von `touch.view` aufwärts geprüft),
     - der Tipp in einem als „Tastatur behalten“ markierten Bereich liegt (Baustein 2).
   - Bei Erkennung: `window.endEditing(true)`.
   - Gilt automatisch auch für Blätter, weil sie im selben Fenster liegen. Das wird geprüft, siehe Tests.
2. **Modifier `.keepsKeyboardOnTap()`** für die oben genannten Eingabeleisten. Er meldet den globalen Rahmen des Views (`onGeometryChange` mit `.global`) in ein gemeinsames Register (`@MainActor final class KeyboardKeepZones`, Schlüssel je View-ID, beim Verschwinden entfernen). Der Erkenner ignoriert Tipps in diesen Rahmen. So schließt das Senden im Chat oder in der Einkaufsliste die Tastatur nicht.
3. **Modifier `.keyboardDoneButton()`** für ein einzelnes Feld: `@FocusState` intern oder per Binding übergeben, `ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Fertig") { focus = false } }` nur solange das Feld fokussiert ist. Das ist das Muster aus `EstimateField`. `EstimateField` wird darauf umgestellt, damit es nur eine Umsetzung gibt. Angewendet auf:
   - `NoteField` (TextEditor), `NoteEditorView`, `DecimalField`, das Minutenfeld in `WorkoutSheet`, die beiden Freitextfelder in `WeekReflectionSections` und die mehrzeiligen Notizfelder in `NewTaskSheet`, `TaskEditorView` und `EventEditSheet`.
   - Wichtig: Es darf nie zwei „Fertig“-Knöpfe gleichzeitig geben. Je Feld nur bei eigenem Fokus anzeigen.

Zusätzlich `.scrollDismissesKeyboard(.interactively)` an jeden `Form`, jede `List` und jede `ScrollView`, die Eingabefelder enthält oder über einer Eingabeleiste liegt. Die Liste oben dient als Ausgangspunkt. Vor dem Abschluss mit `grep -rn "TextField\|TextEditor" app/Tagwerk` vollständig abgleichen. `.searchable`-Listen bekommen es ebenfalls.

## Aufgaben

1. Plan nach `docs/superpowers/plans/2026-11-19-keyboard-dismissal.md` legen und committen.
2. Logik-Teil testbar machen. Die Entscheidung „Tipp ignorieren?“ als reine Funktion, z. B. `KeyboardTapPolicy.shouldDismiss(isKeyboardVisible:touchIsInTextInput:point:keepZones:) -> Bool`, mit Swift-Testing-Tests im App-Testbundle (`app/TagwerkTests/`, Stil wie die bestehenden Tests).
3. Erkenner, Register und die beiden Modifier bauen. Erkenner im App-Start installieren, nicht im Test-Host (Muster: Abfragen, die heute schon den Test-Host auslassen, z. B. in `TagwerkApp.swift:30`).
4. Alle Eingabestellen umstellen (Inventar oben, per `grep` vervollständigt).
5. `EveningSheet` und `MorningSheet` (#177): `NoteField` mit `.keyboardDoneButton()` und `Form` mit `scrollDismissesKeyboard`. Tipp auf leere Fläche über den Erkenner.
6. Strings: „Fertig“ existiert bereits im Katalog und wird wiederverwendet. Neue Texte deutsch als Schlüssel mit englischer Übersetzung in `app/Tagwerk/Localizable.xcstrings`.
7. `app/test-all.sh` grün, einschließlich der Prüfung der String-Kataloge.
8. Kurzer Gerätetest-Abschnitt am Ende dieses Plans: Liste aller Eingabestellen mit Häkchen zum Abhaken durch Melvin auf dem iPhone.

## Abnahme

- Jedes Eingabefeld der App lässt sich durch Tipp auf eine leere Fläche oder durch Scrollen schließen. Felder ohne Return-Taste und TextEditoren haben „Fertig“.
- Senden im Chat, in der Einkaufsliste, in der Notiz-Schnellerfassung und in der Suche lässt die Tastatur offen.
- Tipps auf Zeilen, Knöpfe, Menüs und Wischaktionen funktionieren unverändert.
- Ein Tipp in ein anderes Textfeld wechselt den Fokus ohne Flackern.

## Für das Design-Sammelissue

- Ob auch Formulare zusätzlich einen sichtbaren „Fertig“-Knopf über der Tastatur bekommen sollen (heute nur Felder ohne Return-Taste und TextEditoren).

## Stand

### Gebaut

- `app/Tagwerk/Common/KeyboardDismissal.swift` (neuer Ordner `Common`, weil es keinen passenderen für gemeinsame Modifier gab):
  - `KeyboardTapPolicy.shouldDismiss(isKeyboardVisible:touchIsInTextInput:point:keepZones:)` als reine Funktion.
  - `KeyboardKeepZones` (Register der Rahmen, je View-ID ein Eintrag).
  - `KeyboardDismissalController` mit dem fensterweiten `UITapGestureRecognizer` (`cancelsTouchesInView = false`, `delaysTouchesBegan = false`, gleichzeitige Erkennung mit allen Gesten). Der Tastaturzustand kommt aus `keyboardWillShow`/`keyboardWillHide`. Der Tipp-Erkenner ignoriert Tipps auf `UITextField`, `UITextView`, `UISearchBar` und alle Views darin.
  - `KeyboardDismissalInstaller` (Anker in `RootView` per `.background`), im Test-Host nicht aktiv.
  - Modifier `.keepsKeyboardOnTap()`, `.keyboardDoneButton()` (eigener Fokus) und `.keyboardDoneButton(focus:)` (für Felder mit vorhandenem `@FocusState`).
- Tests: `app/TagwerkTests/KeyboardTapPolicyTests.swift` (Entscheidungsregeln und Register).
- `EstimateField` nutzt jetzt `.keyboardDoneButton(focus:)`; die eigene Toolbar entfällt.
- „Fertig“-Knopf an: `NoteField` (Abend und Morgen, #177), `NoteEditorView`, `DecimalField`, kcal-Feld in `WorkoutSheet`, beide Felder in `WeekReflectionSections`, Notizfelder in `NewTaskSheet`, `TaskEditorView` (Titel, Notiz, Kommentar) und `EventEditSheet`, Freitext in `MealSheet`.
- `.keepsKeyboardOnTap()` an: Chat-Composer, `ShoppingInputBar`, Notiz-`captureBar`, Suchkopf, beide Zeilen des Vorschlags-Composers (Schnellantworten und Eingabe), Suchfeld in `UnplannedDrawer`.
- `.scrollDismissesKeyboard(.interactively)` an allen `Form`/`List` mit Eingabefeldern oder über einer Eingabeleiste sowie an den `.searchable`-Listen (`MonthView`, `DeadlineViews`, `EntrySheet`).

### Abweichungen und Annahmen

- Der Plan sieht einen einzigen „Fertig“-Knopf je Feld vor. Dasselbe Wort steht in `MorningSheet` und `EveningSheet` bereits oben rechts für „Sheet abschließen“. Beide Bedeutungen unterscheiden sich (Tastatur schließen gegenüber Abschluss). Ich habe die vorhandene Beschriftung wie im Plan wiederverwendet; ob der Tastaturknopf anders heißen soll, gehört ins Design-Sammelissue.
- Zusätzlich zur Liste im Plan haben Mehrzeilenfelder mit `axis: .vertical` im `TaskEditorView` (Titel, Kommentar) und im `MealSheet` einen „Fertig“-Knopf bekommen, weil Return dort einen Zeilenumbruch einfügt. Chat-Composer und Notiz-Schnellerfassung bekommen ihn bewusst nicht (eigener Sendeknopf, Tastatur bleibt offen).
- Alert-Textfelder (`ShoppingListView:76`, `ShoppingCategoriesView:83/88`) und Felder in `RoutineSettingsView`-Zeilen sind einzeilig mit Return-Taste und blieben unverändert. Ob der Tipp-Erkenner in Alerts greift, ist ungeprüft (Alerts haben ihre eigene Präsentation); sie haben ohnehin eine Bestätigungstaste.
- Kein roter Testlauf vor der Implementierung: Die Tests referenzieren neue Typen und scheiterten damit schon am Build, der Ablauf ist also von Rot zu Grün gegangen.

### Offen

- Der Tipp-Erkenner lässt sich nur auf dem Gerät prüfen (keine UI-Tests im Projekt).
- Die Rahmen in `KeepZones` nutzen `.global` (Fensterkoordinaten); bei Rotation oder Split View wird neu gemeldet, das ist aber nicht getestet.
- Tastaturstatus kommt aus Benachrichtigungen. Bei einer Hardware-Tastatur ohne Bildschirmtastatur wird `keyboardWillShow` nicht in jedem Fall gesendet; dann bleibt der Hintergrund-Tipp ohne Wirkung, Scrollen und „Fertig“ funktionieren weiter.

### Gerätetest für Melvin (bitte abhaken)

Hintergrund-Tipp und Scrollen schließen die Tastatur in jedem Feld; „Fertig“ nur, wo angegeben.

- [ ] Tagesabschluss (`EveningSheet`): Gedanken-Feld, „Fertig“ über der Tastatur, Tipp auf leere Fläche, Scrollen (#177)
- [ ] Tagesstart (`MorningSheet`): Dankbar-Felder, Gedanken-Feld mit „Fertig“
- [ ] Wochenrückblick: beide Reflexionsfelder mit „Fertig“
- [ ] Notiz-Editor (`NoteEditorView`) mit „Fertig“
- [ ] Notiz-Schnellerfassung: Senden lässt die Tastatur offen
- [ ] Chat: Senden lässt die Tastatur offen; Tipp in den Verlauf schließt sie
- [ ] Einkaufsliste: Hinzufügen lässt die Tastatur offen; Artikel-Sheet schließt per Tipp
- [ ] Suche: Tippen in den Kopf behält die Tastatur, Tipp in die Ergebnisse schließt sie
- [ ] Vorschlags-Composer (Planung): Senden und Schnellantworten lassen die Tastatur offen
- [ ] Ungeplante-Ablage: Suchfeld, Tipp auf Zeile schließt
- [ ] Neue Aufgabe: Notizfeld mit „Fertig“
- [ ] Aufgabe bearbeiten: Titel, Notiz, Kommentar mit „Fertig“; Aufwandsfeld mit „Fertig“ (nur ein Knopf sichtbar)
- [ ] Termin bearbeiten: Notizfeld mit „Fertig“
- [ ] Mahlzeit: Freitext mit „Fertig“, Dezimalfelder (Zahlenblock) mit „Fertig“
- [ ] Training: Kalorienfeld (Zifferntastatur) mit „Fertig“
- [ ] Gewohnheit, Routine-Einstellungen, KI-Einstellungen: Tipp auf leere Fläche schließt die Tastatur
- [ ] Zeilen, Knöpfe, Menüs, Wischaktionen reagieren bei offener Tastatur unverändert
- [ ] Tipp in ein anderes Textfeld wechselt den Fokus ohne Flackern
