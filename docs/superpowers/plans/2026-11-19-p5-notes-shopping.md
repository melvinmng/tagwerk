# P5: Notizen und Einkauf (Ordner, #180, #155, #156, #150) – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026 auf dem Stand `origin/main` 70a2b9c. Ohne Mockups (Designrunde #188 folgt später). Nichts gebaut, nichts im Simulator oder am Gerät geprüft.

**Goal:** Notizen bekommen drei feste Ordner („Brain Dump“, „Tagesstart“, „Tagesabschluss“), Markdown mit Ansicht, sicheres HTML, Bilder und Dateianhänge. Die Einkaufsliste bekommt zwei Sammelaktionen und „Rezept hinzufügen“ mit ChatGPT.

**Architecture:** Reine Regeln in `TagwerkCore` (Ordnerrollen, Markdown-Klartext, HTML-Erzeugung und -Bereinigung, Rezept-Text, Rezept-Antwort prüfen), ohne App testbar. Die App erweitert `NoteStore`, `NoteEditorView`, `NotesFoldersView`, `NotesListView`, `BackupService`/`BackupDTOs`, `ShoppingModel`, `ShoppingListView` und bekommt `NoteAttachmentRecord`, `NoteAttachmentStore`, `NoteMarkdownView` (WKWebView) und `RecipeImporter` (Muster `ShoppingSorter`).

**Tech Stack:** Swift 6, SwiftUI (iOS 27), SwiftData, WebKit, PhotosUI, QuickLook, UniformTypeIdentifiers, AIKit (`ResponseStreaming`, `.userImage`), RemindersKit, Swift Testing; XcodeGen (`app/project.yml`). Neue Abhängigkeit: `swift-markdown` (Apple) im Paket `TagwerkCore`.

**Reihenfolge der Tasks:** 1–4 (Ordner, #180) → 5–11 (#155) → 12 (#156) → 13–15 (#150) → 16 (Texte, Abschluss). Jede Task endet mit grünem `app/test-all.sh` und einem Commit.

## Global Constraints

- **Abgrenzung zu P1:** P1 benennt die Gedanken-Notiz in `MorningSheet`/`EveningSheet`/`NoteField` in „Brain Dump“ um und ändert die Routinen-Blätter. P5 fasst diese Dateien **nicht** an. Ausnahme ist eine einzige Zeile in `NoteSuggestionModel.request(...)`, die den Notiztext vor dem Senden durch `MarkdownText.plainText` schickt (Task 8). Sie ist bewusst klein gehalten, damit der Rebase einfach bleibt.
- **Konflikte:** Alle Pakete ändern `app/Tagwerk/Localizable.xcstrings`. Texte werden erst in Task 16 gesammelt synchronisiert (`scripts/sync-strings.sh`), englische Werte über `scripts/translations/en.json` und `scripts/apply-translations.py`. Vor jedem Push `git fetch && git rebase origin/main`, Katalogkonflikte durch erneutes `scripts/sync-strings.sh` lösen, nicht von Hand mischen. Weitere geteilte Dateien: `ModelContainerFactory.schema`, `BackupDTOs.swift` (`BackupEntities.modelNames`), `AppSettings.swift`, `project.yml`.
- **SwiftData:** Jedes neue Attribut hat einen Standardwert oder ist optional, nichts `unique` außer wie bisher, keine Relationships. `NoteAttachmentRecord` kommt in `ModelContainerFactory.schema` und in `BackupEntities.modelNames` (Task 10). `ModelStoreLocationTests` und der Vollständigkeitstest von `BackupCoverage` bleiben grün.
- **Datenschutz:**
  - Bilder, Anhänge und HTML gehen nie an ChatGPT, an den Assistenten oder ins Widget.
  - An ChatGPT geht von einer Notiz höchstens der Klartext (`MarkdownText.plainText`), und das nur, wo es heute schon erlaubt ist (Gedanken-Notiz mit Zustimmung).
  - Die Suche durchsucht nur den Klartext.
  - Private Notizen (`NoteKind.isPrivate`) bleiben unverändert privat.
- **WebView-Sicherheit:** JavaScript der Seite ist aus (`WKWebpagePreferences.allowsContentJavaScript = false`). Es gilt eine CSP `default-src 'none'; img-src tagwerk-attachment:; style-src 'unsafe-inline'`. Eine `WKContentRuleList` blockiert jede Ladung mit `http`, `https`, `ftp`, `data` und `blob`. Die Seite hat keine Base-URL (`loadHTMLString(_:baseURL: nil)`). Die Tag-Allowlist (Task 6) ist eine zusätzliche Schicht, nicht die einzige.
- Kein Blatt öffnet sich von selbst. Kein KI-Aufruf ohne Tippen.
- Deutsch ist Quellsprache, jeder neue Text steht deutsch und englisch im Katalog. Code-Bezeichner, Kommentare, Log- und Testmeldungen sind englisch.
- Commits: Conventional Commits auf Englisch, ohne Hinweis auf KI, ohne `Co-Authored-By`. Branch `feat/notes-folders-markdown-shopping`.

## Review Focus

1. **Einsortieren ist idempotent und verlustfrei:**
   - Zweimal `ensureDefaultFolders()` legt keine doppelten Ordner an.
   - Ein umbenannter Ordner bleibt umbenannt.
   - Eine Gedanken-Notiz mit verwaistem `folderID` (nach einer Wiederherstellung) landet im richtigen Ordner.
   - Freie Notizen werden nie bewegt.
2. **Sicherung ohne private Inhalte:** Brain Dump, Tagesstart und Tagesabschluss samt Notizen sind enthalten, Tagebuch und Bible Study samt ihren Anhängen nicht.
3. **Anhänge verschwinden genau dann:**
   - wenn die Notiz endgültig gelöscht wird (Papierkorb leeren, Ablauf, `delete`, leere Notiz),
   - oder wenn der Verweis beim Schließen des Editors nicht mehr im Text steht.
   - Nicht beim Verschieben in den Papierkorb.
4. **HTML kann nichts nachladen und nichts ausführen** (Testvektoren in Task 6).
5. **„Gesamte Liste leeren“ löscht nur Erinnerungen der Einkaufsliste**, nie andere Listen (gleicher Schutz wie `shoppingRecord(_:)`).

---

## Teil A: Feste Ordner und #180

### Task 1: Ordnerrollen in TagwerkCore

**Files:**
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/NoteFolderRules.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/NoteFolderRulesTests.swift`

- [ ] `NoteFolderRole` um drei Fälle erweitern: `brainDump`, `morningRoutine`, `eveningRoutine`.
- [ ] Neue Eigenschaften der Rolle:
  - `isPrivate`: `journal`, `bibleStudy` sind privat.
  - `acceptsOwnNotes`: `brainDump` true, Routinen-Ordner false, `journal`/`bibleStudy` wie bisher (heute false: `move` nimmt nur freie Notizen, Picker zeigt Systemordner nicht als Ziel – im Code prüfen und das bestehende Verhalten festschreiben).
  - `noteKind`: `morningRoutine` → `.morning`, `eveningRoutine` → `.evening`, sonst `nil`.
- [ ] `canCreateFolder(under:)` bleibt für alle Systemordner `false` (keine Unterordner in Brain Dump).
- [ ] Tests:
  - `role_rawValues_areStable` (`"brainDump"`, `"morningRoutine"`, `"eveningRoutine"`)
  - `role_isPrivate_onlyJournalAndBibleStudy`
  - `role_noteKind_mapsRoutineFolders`
  - `canCreateFolder_belowBrainDump_isFalse`
  - `validateMove_brainDump_throwsSystemFolder`

### Task 2: NoteStore legt die Ordner an und sortiert ein

**Files:**
- Create: `app/Tagwerk/Notes/NoteStore+DefaultFolders.swift`
- Modify: `app/Tagwerk/Notes/NoteStore.swift` (`create` für `.morning`/`.evening`, `move`)
- Modify: `app/Tagwerk/App/AppEnvironment.swift` (Aufruf nach dem Anlegen von `notes`)
- Modify: `app/Tagwerk/Backup/BackupService.swift` (Aufruf nach `restore`)
- Test: `app/TagwerkTests/NoteStoreTests.swift`

- [ ] `ensureDefaultFolders()`:
  - legt die drei Ordner über `ensureSystemFolder` an, mit den Namen `String(localized: "Brain Dump")`, `"Tagesstart"` und `"Tagesabschluss"`,
  - Reihenfolge: Brain Dump vor Tagesstart vor Tagesabschluss, alle hinter den vorhandenen Systemordnern,
  - ruft danach `sortRoutineNotes()`.
- [ ] `sortRoutineNotes()`:
  - setzt bei jeder `.morning`/`.evening`-Notiz, auch im Papierkorb, `folderID` auf den Ordner ihrer Rolle, wenn er abweicht,
  - speichert nur bei Änderung,
  - freie Notizen, Tagebuch und Bible Study bleiben unberührt.
- [ ] `create(...)` setzt für `.morning`/`.evening` `folderID = ensureSystemFolder(role).id` statt `nil`.
- [ ] `move(noteIDs:to:)` lehnt Ziele ab, deren Rolle `acceptsOwnNotes == false` ist.
- [ ] Aufruf in `AppEnvironment.init` direkt nach `self.notes = NoteStore(context:)`. Er muss vor dem ersten Zeichnen laufen und in Tests mit In-Memory-Store harmlos sein.
- [ ] Nach `BackupService.restore` wird `ensureDefaultFolders()` erneut aufgerufen. `BackupService` hat keinen `NoteStore`: über einen Closure-Parameter `afterRestore` aus `AppEnvironment` lösen, nicht `NoteStore` in `BackupService` erzeugen.
- [ ] Tests:
  - `ensureDefaultFolders_createsThreeFoldersOnce`
  - `ensureDefaultFolders_keepsRenamedFolder`
  - `sortRoutineNotes_movesExistingThoughtNotesIntoTheirFolders`
  - `sortRoutineNotes_repairsDanglingFolderID`
  - `sortRoutineNotes_leavesFreeNotesAlone`
  - `saveThought_landsInTheRoutineFolder`
  - `move_intoRoutineFolder_isRefused`
  - `move_intoBrainDump_works`
  - `deleteFolder_brainDump_throwsSystemFolder`

### Task 3: Ordneransicht und Listen

**Files:**
- Modify: `app/Tagwerk/Notes/NotesFoldersView.swift`, `NotesScope.swift`, `NotesListView.swift`, `NoteFolderPickerSheet.swift`, `NoteEditorView.swift`
- Test: `app/TagwerkTests/NotesListTextTests.swift`

- [ ] **Virtuellen Ordner „Gedanken“ entfernen:** `NotesScope.thoughts`, die Zeile in `NotesFoldersView` und den Titel in `NotesListView`. `NoteStore.Filter.thoughts` und `hasThoughts` entfernen, wenn danach nichts mehr sie nutzt (grep).
- [ ] **Brain Dump steht im ersten Abschnitt direkt unter „Notizen“:**
  - SF-Symbol `brain.head.profile` (Kandidaten für #188: `brain`, `brain.filled.head.profile`), in der Akzentfarbe wie die übrigen Zeilen.
  - Wischaktion von vorne „Neu“ (`square.and.pencil`): legt eine leere freie Notiz im Ordner an und öffnet den Editor. Muster: `NotesListView.writeToday()` und `environment.tasksPath`. Eine leer verlassene Notiz verschwindet über `deleteIfEmpty`.
  - In der Ordnerliste des Brain Dump bleibt die Schnellerfassung (`allowsCapture`) an.
- [ ] **Tagesstart und Tagesabschluss stehen im Abschnitt der Systemordner** vor Tagebuch und Bible Study.
  - Symbole: `sun.horizon` und `moon.stars`.
  - In ihren Listen keine Schnellerfassung. `NotesListView` erkennt die Rolle über `store.folder(id:)?.role`, weil `NotesScope` sie nicht kennt.
  - Kartentitel ist das Datum: neue statische Funktion `routineTitle(_:calendar:)` nach dem Muster `journalTitle`, z. B. „Do. 19. Nov.“.
  - Sortierung nach `dayKey` absteigend, nicht nach Änderung.
- [ ] **Dankbarkeit im Tagesstart:**
  - Die Dankbarkeit bleibt in `RoutineDayRecord` (keine Datenwanderung).
  - Die Morgen-Karte zeigt sie als Vorschauzeile „Dankbar für: A · B · C“.
  - Der Editor einer Morgen-Notiz zeigt sie über dem Text als nicht editierbaren Kopf. Lesen über den vorhandenen Routinen-Store der Umgebung (`environment.routines`, nur lesend).
  - Tage nur mit Dankbarkeit und ohne Brain Dump erscheinen **nicht** (Punkt für #188).
- [ ] **`NoteFolderPickerSheet`** zeigt Brain Dump als Ziel, die Routinen-Ordner nicht.
- [ ] **Kontextmenü:** Umbenennen bleibt für alle Systemordner möglich, Löschen und Bewegen nicht (wie heute über `role == nil`).
- [ ] Tests:
  - `routineTitle_showsTheDay`
  - `morningPreview_listsGratitude`
  - `morningPreview_withoutGratitude_isEmpty`
  - Die Texte als statische Funktionen testen, die Views nicht.

### Task 4: Sicherung behält die neuen Ordner

**Files:**
- Modify: `app/Tagwerk/Backup/BackupDTOs.swift` (Zeile mit `noteFolders = … filter { includePrivate || $0.role == nil }`)
- Test: `app/TagwerkTests/BackupTests.swift`

- [ ] Filter auf `includePrivate || $0.role?.isPrivate != true` ändern.
- [ ] Prüfen, ob `NoteFolderBackup` `roleRaw` mitsichert. Falls nicht: als optionales Feld ergänzen (`decodeIfPresent`, alte Dateien bleiben lesbar).
- [ ] Tests:
  - `backupWithoutPrivate_keepsBrainDumpAndRoutineFolders`
  - `backupWithoutPrivate_dropsJournalAndBibleStudyFolders`
  - `restore_routineNotesLandInTheirFolders`

---

## Teil B: #155 Markdown, HTML, Bilder, Anhänge

### Verweis-Format

Anhänge stehen als Markdown-Verweis im Text:
- Bilder als `![Bild](attachment:<UUID>)`
- Dateien als `[Name.pdf](attachment:<UUID>)`

Der Text bleibt so lesbar, exportierbar und durchsuchbar. Der Verweis wird an der Schreibmarke eingefügt.

### Task 5: Markdown-Klartext und Verweise (TagwerkCore)

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/MarkdownText.swift`
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/NoteText.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/MarkdownTextTests.swift`, `NoteTextTests.swift`

- [ ] `MarkdownText.plainText(_:)` ist zeilenbasiert und ohne Parser, weil der Titel bei jeder Zeile gebraucht wird. Es entfernt bzw. vereinfacht:
  - führende `#`, `>`, `- `, `* `, `+ `, `1. ` sowie `- [ ] ` und `- [x] `
  - `**`, `__`, `*`, `_` und `~~` um Wörter
  - Inline-Code-Backticks
  - Links `[text](url)` → `text`
  - Bilder `![alt](…)` → leer
  - HTML-Tags → leer, Entities `&amp;` usw. dekodiert
  - Tabellenzeilen `| a | b |` → `a b`, Trennzeilen `|---|` → leer
- [ ] `MarkdownText.attachmentIDs(in:) -> Set<UUID>` findet `attachment:<UUID>` in Links und Bildern, unabhängig von Groß-/Kleinschreibung.
- [ ] `MarkdownText.reference(for:name:isImage:) -> String`. Klammern und `]` im Namen escapen.
- [ ] `MarkdownText.togglingCheckbox(at index: Int, in text: String) -> String`: Die n-te Checkbox-Zeile (`- [ ]`/`- [x]`, auch `*`/`+`, eingerückt) wechselt. Codeblöcke werden übersprungen.
- [ ] `NoteText.title`, `preview` und `matches` arbeiten auf `plainText`. Der Titel einer Notiz „# Einkauf“ ist dann „Einkauf“.
- [ ] Tests:
  - `plainText_stripsHeadingsListsAndEmphasis`
  - `plainText_linkKeepsText_imageVanishes`
  - `plainText_stripsHtmlTagsAndDecodesEntities`
  - `plainText_tableRowsBecomeWords`
  - `attachmentIDs_findsImagesAndLinks`
  - `attachmentIDs_ignoresOtherSchemes`
  - `reference_escapesBrackets`
  - `togglingCheckbox_secondBoxFlips`
  - `togglingCheckbox_skipsCodeBlocks`
  - `togglingCheckbox_outOfRange_returnsTextUnchanged`
  - `title_ofMarkdownHeading_isPlain`
  - `matches_findsWordInsideBold`
  - `matches_doesNotFindAttachmentUUID`

### Task 6: HTML erzeugen und bereinigen (TagwerkCore + swift-markdown)

**Files:**
- Modify: `app/Packages/TagwerkCore/Package.swift`: Abhängigkeit `https://github.com/swiftlang/swift-markdown`, **exakte Version**. Vorher den neuesten Release-Tag per `git ls-remote --tags` bestimmen. Er muss mindestens zwei Wochen alt sein. Version im Commit nennen.
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/NoteHTMLRenderer.swift`, `HTMLSanitizer.swift`
- Test: `NoteHTMLRendererTests.swift`, `HTMLSanitizerTests.swift`

- [ ] `NoteHTMLRenderer.html(markdown:attachmentNames:) -> String`. Ein `MarkupVisitor` über `Document(parsing:options: [.parseBlockDirectives aus])` erzeugt:
  - Überschriften, Absätze, Listen, Aufgabenlisten, Zitate, Code und Codeblöcke (escaped), Tabellen, horizontale Linien, Hervorhebungen und Durchgestrichenes
  - Links nur für `http`, `https`, `mailto`, `tel` und `attachment`, sonst nur Text
  - Bilder nur mit `attachment:<UUID>` als `<img src="tagwerk-attachment://<UUID>">`, andere Bild-URLs als Text „[Bild]“
  - Datei-Links als Chip `<a class="file" href="attachment:<UUID>">📎 Name</a>`
  - Checkboxen als `<input type="checkbox" disabled data-index="n">` mit fortlaufendem Index in derselben Zählung wie `togglingCheckbox`
- [ ] Rohes HTML (`HTMLBlock`, `InlineHTML`) läuft durch `HTMLSanitizer.clean(_:)`:
  - Tag-Allowlist: p, br, b, strong, i, em, u, s, del, mark, sub, sup, small, h1–h6, ul, ol, li, blockquote, pre, code, hr, table, thead, tbody, tr, th, td, span, div, details, summary, a, img
  - Attribut-Allowlist: href (nur erlaubte Schemata), src (nur `attachment:`, umgeschrieben auf `tagwerk-attachment://`), alt, title, colspan, rowspan
  - Alles mit `on…`, `style`, `srcset`, `xlink` fällt weg
  - Inhalte von script, style, iframe, object, embed, form, svg, math, template, noscript fallen ganz weg
  - Kommentare fallen weg
  - Ein einfacher Tokenizer genügt, weil JavaScript, CSP und Content Rules die eigentliche Grenze sind (siehe Global Constraints)
- [ ] `NoteHTMLRenderer.page(body:colorScheme:dynamicTypeSize:)` setzt `<meta http-equiv="Content-Security-Policy" …>` und ein eingebettetes Stylesheet mit Systemschrift, hellem und dunklem Schema sowie Tabellenrahmen.
- [ ] Tests:
  - `renderer_headingListTableChecklist`
  - `renderer_codeIsEscaped`
  - `renderer_javascriptLink_becomesText`
  - `renderer_remoteImage_isNotLoaded`
  - `renderer_attachmentImage_usesCustomScheme`
  - `renderer_checkboxIndicesMatchToggling`
  - `sanitizer_dropsScriptWithContent`
  - `sanitizer_dropsEventHandlers`
  - `sanitizer_dropsIframeAndSvg`
  - `sanitizer_keepsAllowedFormatting`
  - `sanitizer_dataURLInImg_isDropped`
  - `sanitizer_unclosedTag_doesNotSwallowRest`
  - `page_containsCSP`

### Task 7: Anhänge speichern

**Files:**
- Create: `app/Tagwerk/Notes/NoteAttachmentRecord.swift` (`@Model`: `id: UUID = UUID()`, `noteID: UUID? = nil`, `fileName: String = ""`, `typeIdentifier: String = ""`, `byteCount: Int = 0`, `createdAt: Date = .now`)
- Create: `app/Tagwerk/Notes/NoteAttachmentStore.swift`
- Modify: `app/Tagwerk/Persistence/ModelContainerFactory.swift` (Schema), `app/Tagwerk/Notes/NoteStore.swift` (Löschpfade)
- Test: `app/TagwerkTests/NoteAttachmentStoreTests.swift`

- [ ] **Ablage:**
  - Dateien liegen unter `Application Support/NoteAttachments/<UUID>.<ext>`, geschrieben mit `.completeFileProtection`.
  - Der Ordner ist injizierbar, damit Tests ein Temp-Verzeichnis nutzen.
- [ ] **Bilder:**
  - `addImage(_ image: UIImage, to noteID:)` verkleinert über `ImageDownscaler.jpeg(from:maxEdge: 2048, quality: 0.8)`.
  - HEIC und PNG werden dadurch JPEG. Transparenz geht verloren; das wird für #188 notiert.
- [ ] **Dateien:**
  - `addFile(at url: URL, to noteID:)` kopiert die Datei mit `startAccessingSecurityScopedResource`.
  - Höchstens 25 MB je Datei, sonst Fehler `.tooLarge` mit eigenem Text.
- [ ] `url(for id:)`, `attachments(of noteID:)` und `delete(ids:)`.
- [ ] **`removeUnreferenced(noteID:text:)`:** löscht die Anhänge der Notiz, deren ID nicht mehr in `MarkdownText.attachmentIDs(in: text)` steht.
- [ ] **`purgeOrphans(existingNoteIDs:)`:** beim Start, für Anhänge ohne lebende oder gelöschte Notiz.
- [ ] **`NoteStore` ruft die Löschung auf in:** `delete`, `deleteIfEmpty`, `emptyTrash` und `purgeExpired`. Nicht in `trash` und nicht in `deleteFolder` (das verschiebt nur in den Papierkorb).
  - Umsetzung: optionaler `attachments: NoteAttachmentStore?` im Initialisierer von `NoteStore`, Standard `nil`, damit bestehende Tests unverändert bleiben.
- [ ] Tests:
  - `addImage_storesDownscaledJPEG`
  - `addFile_copiesAndRecordsSize`
  - `addFile_over25MB_throwsTooLarge`
  - `removeUnreferenced_deletesOnlyDroppedOnes`
  - `trash_keepsAttachments`
  - `emptyTrash_deletesAttachments`
  - `purgeExpired_deletesAttachments`
  - `purgeOrphans_removesFilesWithoutNote`

### Task 8: Datenschutz der Klartext-Pfade

**Files:**
- Modify: `app/Tagwerk/Routines/NoteSuggestionModel.swift` (eine Zeile, siehe Abgrenzung)
- Modify: Notiz-Lieferant in `app/Tagwerk/Search/SearchModel.swift` (`NoteSearchItem`-Erzeugung)
- Modify: Assistent-Werkzeuge, falls sie Notiztext liefern (grep `NoteRecord`/`notes.notes(` in `Tagwerk/AI`)
- Test: `NoteSuggestionModelTests.swift`, `PrivateNotesTests.swift`

- [ ] Vorschläge senden `MarkdownText.plainText(text)`. Darin stehen keine `attachment:`-Verweise und kein HTML.
- [ ] Suche und Assistent bekommen nur Klartext.
- [ ] Tests:
  - `request_sendsPlainTextWithoutAttachmentReferences`
  - `request_sendsNoHtml`
  - `search_matchesPlainText_notMarkup`

### Task 9: Ansicht und Editor

**Files:**
- Create: `app/Tagwerk/Notes/NoteMarkdownView.swift` (`UIViewRepresentable` mit `WKWebView`)
- Create: `app/Tagwerk/Notes/NoteAttachmentMenu.swift`
- Modify: `app/Tagwerk/Notes/NoteEditorView.swift`

- [ ] **`NoteMarkdownView`:**
  - **Konfiguration:**
    - `defaultWebpagePreferences.allowsContentJavaScript = false`
    - `setURLSchemeHandler(_, forURLScheme: "tagwerk-attachment")`: liefert nur Dateien aus `NoteAttachmentStore`, unbekannte IDs → 404
    - `WKContentRuleList` mit `block` für `^(https?|ftp|data|blob):`
    - Hintergrund transparent
  - **Checkboxen:**
    - Ein `WKUserScript` in `WKContentWorld.defaultClient` hängt Klick-Handler an `input[data-index]`. Skripte in eigener Welt laufen trotz `allowsContentJavaScript = false`; das zuerst im Simulator prüfen und das Ergebnis im Commit nennen.
    - Der Handler meldet den Index über `WKScriptMessageHandler`, die App ruft `togglingCheckbox` und speichert.
    - Rückfall, falls das Skript nicht läuft: Checkboxen nur im Bearbeiten-Modus änderbar, Punkt für #188.
  - **Navigation (`WKNavigationDelegate`):**
    - Nur `about:blank` und das erste Laden zulassen.
    - Ein Tipp auf einen `http`/`https`/`mailto`/`tel`-Link öffnet über `UIApplication.shared.open` außerhalb der App.
    - `attachment:<UUID>` öffnet QuickLook. Teilen geht dort über das Teilen-Symbol.
- [ ] **Modus-Umschalter:**
  - Toolbar-Knopf „Ansicht“ (`eye`) / „Bearbeiten“ (`pencil`).
  - Eine neue oder leere Notiz öffnet im Bearbeiten-Modus, eine vorhandene mit Text in der Ansicht.
  - Der Modus gilt je Öffnung und wird nicht gespeichert (Punkt für #188).
  - Beim Wechsel speichert der Editor sofort (vorhandene Speicherlogik).
- [ ] **Menü „Anhängen“** (`paperclip`, in der Toolbar und in der Tastaturleiste):
  - „Foto auswählen“ (`PhotosPicker`, mehrere)
  - „Foto aufnehmen“ (vorhandener `CameraPicker` aus `Capture`, nur wenn die Kamera verfügbar ist). Die Kamera-Zweckangabe in `project.yml`/`Info.plist` erweitern, sodass sie auch Notizen nennt (deutsch; `InfoPlist.xcstrings` englisch).
  - „Bild einfügen“ (`PasteButton(supportedContentTypes: [.image])`)
  - „Datei“ (`fileImporter`, `[.item]`)
  - Jede Aktion fügt den Verweis an der Schreibmarke ein (`selection`), sonst am Ende, und wechselt in den Bearbeiten-Modus.
- [ ] **Teilen:**
  - `ShareLink(item: text)` bleibt für den Text.
  - Gibt es Anhänge, gibt es zusätzlich „Anhänge teilen“ mit den Datei-URLs.
- [ ] **Schließen des Editors:** `removeUnreferenced(noteID:text:)` nach dem letzten Speichern.
- [ ] **Tagebuch und Bible Study:** Anhänge erlaubt, ihre Privatsphäre gilt über die Notiz.
- [ ] Kein Unit-Test für die View. Testbare Teile liegen in den Tasks 5–7. Sichtprüfung im Simulator in Task 16.

### Task 10: Sicherung der Anhänge

**Entscheidung:** Anhänge kommen in die Sicherung, als Base64 im JSON.

**Begründung:**
- Eine Wiederherstellung ohne Dateien ließe tote `attachment:`-Verweise zurück. Das wäre stiller Datenverlust bei einer Funktion, deren Zweck Wiederherstellung ist.
- Die Größe bleibt durch Verkleinerung der Bilder (2048 px) und die 25-MB-Grenze je Datei beherrschbar.
- Die Einstellungsseite zeigt die Gesamtgröße der Anhänge, damit die Dateigröße nachvollziehbar bleibt.
- Für Anhänge privater Notizen gilt der Schalter „Tagebuch und Bible Study einschließen“.

**Files:**
- Modify: `app/Tagwerk/Backup/BackupDTOs.swift` (`NoteAttachmentBackup` mit `id`, `noteID`, `fileName`, `typeIdentifier`, `createdAt`, `data: Data`; `BackupEntities.noteAttachments` mit `decodeIfPresent`; `modelNames` ergänzen)
- Modify: `app/Packages/TagwerkCore/Sources/TagwerkCore/BackupRules.swift` (`schemaVersion` + 1; ältere Dateien bleiben lesbar)
- Modify: `app/Tagwerk/Backup/BackupSettingsView.swift` (Zeile „Anhänge: 12 · 34 MB“)
- Test: `app/TagwerkTests/BackupTests.swift`

- [ ] Tests:
  - `backup_containsAttachmentData`
  - `backupWithoutPrivate_dropsAttachmentsOfJournal`
  - `restore_writesAttachmentFiles`
  - `restore_ofOlderFileWithoutAttachments_works`
  - `coverage_includesNoteAttachmentRecord` (der bestehende Vollständigkeitstest muss grün sein)

### Task 11: Suche und Listenkarten

**Files:** `NotesListView.swift`, `SearchRows.swift` (falls die Notizvorschau dort gebaut wird)

- [ ] Kartenvorschau und Suchtreffer zeigen den Klartext.
- [ ] Hat die Notiz Bilder, zeigt die Karte rechts ein kleines Vorschaubild des ersten Bilds (`NoteAttachmentStore.url`, `AsyncImage` mit lokaler URL ist nicht nötig, `UIImage(contentsOfFile:)` genügt).
- [ ] Hat sie Dateien, zeigt die Karte ein `paperclip`-Symbol mit Anzahl.
- [ ] Test: `card_previewUsesPlainText` (statische Textfunktion).

---

## Teil C: #156 Einkaufsliste leeren

### Task 12: Sammelaktionen

**Files:**
- Modify: `app/Tagwerk/Shopping/ShoppingModel.swift`, `ShoppingListView.swift`
- Test: `app/TagwerkTests/ShoppingModelTests.swift`

- [ ] **`allCompletedCount() async -> Int`:** liest erledigte Erinnerungen der Einkaufsliste über `store.completedReminders(in: DateInterval(start: .distantPast, end: now + 60), listIDs: [listID])`. Am Gerät prüfen, ob EventKit `distantPast` annimmt. Rückfall: `Date(timeIntervalSince1970: 0)`.
- [ ] **`removeAllCompleted() async -> Int`:** löscht alle erledigten Artikel der Liste, auch ältere als 7 Tage. Jeder über `shoppingRecord(_:)` geprüft, also nur diese Liste.
- [ ] **`clearList() async -> Int`:** löscht alle offenen und alle erledigten Artikel der Liste. Liste und Kategorien bleiben. Kategorie-Zuordnungen nach Namen bleiben, weil sie für künftige Artikel gelten.
- [ ] **Menü „⋯“:**
  - „Erledigte entfernen“ wird zu „Alle erledigten löschen“ (Text aus dem Issue), aktiv bei Anzahl > 0. Die Anzahl wird beim Öffnen des Dialogs geladen.
  - Neu: „Liste leeren“ (`trash.slash`), destruktiv, aktiv wenn offen + erledigt > 0.
  - Rückfragen als `confirmationDialog`:
    - „12 erledigte Artikel löschen?“
    - „Gesamte Liste leeren? 20 Artikel werden gelöscht.“
    - jeweils mit Hinweis „Sie verschwinden auch aus Apple Erinnerungen.“
- [ ] `removeCompleted()` entfernen, wenn kein Aufrufer bleibt (AppTools prüfen: `AppToolsShoppingTests`).
- [ ] Tests:
  - `removeAllCompleted_deletesOlderThanSevenDaysToo`
  - `removeAllCompleted_leavesOpenItems`
  - `clearList_deletesOpenAndCompleted`
  - `clearList_keepsCategoriesAndAssignments`
  - `clearList_neverTouchesOtherLists`
  - `allCompletedCount_countsBeyondWindow`

---

## Teil D: #150 Rezept hinzufügen

### Task 13: Rezepttext lokal gewinnen (TagwerkCore)

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/RecipeText.swift`
- Test: `RecipeTextTests.swift`

- [ ] **`RecipeText.ingredients(fromHTML:) -> [String]?`:** sucht `<script type="application/ld+json">` mit `@type` `Recipe`, auch in `@graph` und in Arrays, und liefert `recipeIngredient`. Ohne Treffer `nil`.
- [ ] **`RecipeText.plainText(fromHTML:) -> String`:**
  - entfernt script, style, nav, header und footer samt Inhalt,
  - entfernt die übrigen Tags,
  - dekodiert Entities und kürzt Leerraum.
- [ ] **`RecipeText.limited(_:) -> String`:** höchstens 8000 Zeichen.
- [ ] Tests:
  - `ingredients_fromJsonLd`
  - `ingredients_fromGraph`
  - `ingredients_missing_returnsNil`
  - `plainText_dropsScriptsAndNav`
  - `limited_cutsAt8000`

### Task 14: RecipeImporter (Muster ShoppingSorter)

**Files:**
- Create: `app/Tagwerk/Shopping/RecipeImporter.swift`
- Modify: `app/Tagwerk/App/AppEnvironment.swift` (Erzeugung wie `shoppingSorter`)
- Modify: `app/Tagwerk/Persistence/AppSettings.swift` (`shoppingRecipeConsent: Bool = false`)
- Test: `app/TagwerkTests/RecipeImporterTests.swift`

- [ ] **Eingabe:** `enum Input { case text(String), photo(jpeg: Data), link(URL) }`
  - Foto: über `ImageDownscaler.jpeg(maxEdge: 1024)` wie bei Mahlzeiten.
  - Link:
    - nur `http`/`https`, geladen mit `URLSession` (Timeout 15 s, höchstens 2 MB),
    - danach zuerst `ingredients(fromHTML:)`, sonst `plainText`,
    - an ChatGPT geht nur dieser Text, nie die URL.
- [ ] **Anfrage:**
  - Rezepttext bzw. Foto und die Kategorienamen inkl. „Sonstiges“, über `ResponseStreaming.respond(..., jsonSchema: "recipe_ingredients")`.
  - Antwort `{ items: [{ name, quantity?, category }] }`, höchstens 40.
- [ ] **Prüfung (`static func validate`):**
  - unbekannte Kategorie → „Sonstiges“,
  - leere Namen weg,
  - Duplikate nach `ShoppingName.key` zusammengefasst,
  - Artikel, die offen auf der Liste stehen, als `alreadyOnList` markiert und standardmäßig abgewählt,
  - keine neuen Kategorien.
- [ ] **Fehler** wie `ShoppingSorter.Failure`: `consentMissing`, `network`, `signedOut`, `usageLimit`, `failed`, dazu `linkUnreadable` und `nothingFound`. Ohne Zustimmung wird nichts geladen, auch der Link nicht.
- [ ] **Übernehmen:**
  - `model.add(parsedItems)` mit Menge.
  - Danach je Artikel die Kategorie über `ShoppingCategoryStore` als automatische Zuordnung (`isManual == false`), damit eine spätere Handzuordnung Vorrang hat.
- [ ] Tests:
  - `noConsent_sendsNothing`
  - `noConsent_doesNotFetchLink`
  - `validate_unknownCategoryBecomesOther`
  - `validate_dropsEmptyAndMergesDuplicates`
  - `validate_marksItemsAlreadyOnList`
  - `validate_capsAt40`
  - `link_onlyHttp`
  - `link_sendsExtractedIngredientsNotUrl`
  - `timeout_mapsToFailed`
  - `apply_addsItemsAndAutoAssignsCategories`

### Task 15: Blätter für das Rezept

**Files:**
- Create: `app/Tagwerk/Shopping/RecipeSheets.swift`
- Modify: `ShoppingListView.swift` (Menüpunkt), `ShoppingSettingsView.swift` (Widerruf), `ShoppingSortSheets.swift` (nur falls gemeinsame Bausteine herausgezogen werden)

- [ ] **Menüpunkt „Rezept hinzufügen …“** (`fork.knife`) im Menü „⋯“, deaktiviert ohne ChatGPT-Anmeldung mit Hinweiszeile wie beim Sortieren.
- [ ] **Zustimmungsblatt beim ersten Mal**, aufgebaut wie `ShoppingSortConsentSheet`:
  - Gesendet wird: Rezepttext oder Foto und Kategorienamen.
  - Bei einem Link nur der gelesene Text, nicht die Adresse.
  - Nicht gesendet: Liste, Mengen, Aufgaben, Termine, Notizen, Health.
  - Nur auf dein Tippen.
- [ ] **Eingabeblatt** mit Segment „Text | Foto | Link“:
  - Text: `TextEditor`.
  - Foto: `PhotosPicker` oder Kamera.
  - Link: Textfeld, vorbelegt aus der Zwischenablage nur nach Tippen auf „Einfügen“.
  - Knopf „Zutaten holen“.
  - Fortschritt mit „Abbrechen“ wie `sortingOverlay`.
- [ ] **Ergebnisblatt:**
  - Liste mit Häkchen, Name, Menge und Kategorie als Untertitel.
  - Bereits vorhandene Artikel mit Marke „schon auf der Liste“ und abgewählt.
  - Knöpfe „n Artikel hinzufügen“ und „Verwerfen“.
- [ ] **`ShoppingSettingsView`:** Schalter „Rezepte mit ChatGPT lesen“ zum Widerruf.

---

## Task 16: Texte, Simulator, Abschluss

- [ ] `scripts/sync-strings.sh` laufen lassen, englische Werte in `scripts/translations/en.json` ergänzen, `scripts/apply-translations.py`, dann `scripts/sync-strings.sh --check` grün.
- [ ] `app/test-all.sh` grün.
- [ ] **Sichtprüfung im eigenen Simulator** (Demo-Daten mit `-TagwerkDemoData`), mit Screenshots für die Prüfung:
  - Ordneransicht
  - Brain Dump mit „Neu“
  - Tagesstart-Liste mit Dankbarkeit
  - Markdown-Ansicht mit Tabelle, Checkliste, Bild und PDF-Chip, hell und dunkel
  - HTML-Testnotiz (`<script>`, `<img src=https://…>`, `<b>`)
  - Einkaufs-Menü mit beiden Rückfragen
  - Rezept-Blätter. Ohne Anmeldung nur Zustimmung und Eingabe; die Antwort über einen Fake-Responder im Test.
- [ ] Nach Abschluss Simulator und DerivedData des Checkouts löschen:
  - `xcrun simctl delete "Tagwerk Tests <checkout key>"`
  - `rm -rf ~/Library/Developer/Tagwerk/DerivedData-tests-<checkout key>`
  - Den Schlüssel liefert `scripts/test-env.sh`.
- [ ] Commit `docs: record P5 notes and shopping state` mit Abweichungen vom Plan im Plan-Dokument (Abschnitt „Stand“).

---

## Designpunkte für #188

- **Brain Dump:**
  - endgültiges Symbol (`brain.head.profile` / `brain` / `brain.filled.head.profile`) und ob es eine eigene Farbe bekommt,
  - Platz in der Ordnerliste (erster Abschnitt unter „Notizen“ oder bei den Systemordnern),
  - Form des schnellen Anlegens (Wischaktion, eigener Knopf in der Zeile, Kurzbefehl/Widget).
- **Tagesstart-Ordner:**
  - Dankbarkeit als Kopf im Editor und als Vorschauzeile oder als Teil des Notiztexts,
  - ob Tage nur mit Dankbarkeit als Eintrag erscheinen.
- **Systemordner:** Umbenennen der drei neuen Ordner erlauben oder sperren.
- **Markdown:**
  - Standardmodus beim Öffnen (heute: vorhandene Notiz in der Ansicht) und Platz des Umschalters,
  - Formatierungsleiste über der Tastatur (Überschrift, Liste, Checkliste, Fett) ja oder nein,
  - Checkboxen in der Ansicht antippbar oder nur im Bearbeiten-Modus.
- **Anhänge:**
  - Größe der eingebetteten Bilder in der Ansicht,
  - Aussehen der Datei-Chips,
  - Vorschaubild auf der Notizkarte,
  - Hinweis auf verlorene Transparenz bei PNG.
- **Ansicht:** Typografie (Schriftgrößen der Überschriften, Tabellenstil, Codeblöcke) und Abstand zum Rand.
- **Einkaufsliste:**
  - Wortlaut und Reihenfolge von „Alle erledigten löschen“ und „Liste leeren“ im Menü,
  - Gestaltung der Rückfragen.
- **Rezept:**
  - Eingabeblatt (Segment oder drei Einstiege),
  - Ergebnisliste (Mengen editierbar ja oder nein, Darstellung „schon auf der Liste“).

## Gerätetests

1. **Update von einem Stand vor P5:**
   - Gedanken-Notizen landen in Tagesstart und Tagesabschluss.
   - Kein doppelter Ordner nach zweitem Start.
   - Der Ordner „Gedanken“ ist weg.
2. **Brain Dump „Neu“:** Notiz anlegen, leer verlassen → verschwindet; mit Text → bleibt im Ordner.
3. **Tagesstart:** Dankbarkeit und Brain Dump eingeben → Eintrag im Ordner mit Datum und Dankbarkeit.
4. **Fotos:**
   - Foto aus der Mediathek, mit der Kamera und aus der Zwischenablage (aus Fotos kopiert) einfügen.
   - Dauer und Dateigröße prüfen.
5. **PDF über „Datei“ anhängen:** öffnen in QuickLook, teilen per AirDrop/Mail.
6. **Markdown-Ansicht:**
   - Tabelle, Checkliste (Tippen in der Ansicht), Link öffnet Safari, `mailto:` öffnet Mail.
   - Hell und dunkel, große Schrift.
7. **HTML-Notiz:**
   - Mit `<script>alert(1)</script>`, `<img src="https://…">`, `<iframe>`: nichts wird ausgeführt.
   - Im Flugmodus und mit Netz: kein Netzwerkzugriff (Proxy oder Konsole).
8. **Notiz mit Anhang in den Papierkorb, wiederherstellen:** Anhang ist noch da. Papierkorb leeren → Datei gelöscht (Speicherbelegung in den iOS-Einstellungen).
9. **Sicherung mit Anhängen:**
   - Erstellen, Größe ansehen, auf zweitem Gerät oder nach Löschen der App wiederherstellen.
   - Bilder sind wieder da.
   - Ohne „Tagebuch und Bible Study“: deren Anhänge fehlen.
10. **„Alle erledigten löschen“** mit erledigten Artikeln älter als 7 Tage: alle weg, auch in Apple Erinnerungen. Gilt auch für eine geteilte Liste.
11. **„Liste leeren“:** Liste und Kategorien bleiben, andere Erinnerungslisten unberührt.
12. **Rezept:**
    - Rezept per Foto (Kochbuch), per Text und per Link (Seite mit und ohne JSON-LD) holen.
    - Kategorien stimmen, vorhandene Artikel sind abgewählt.
    - Ohne Netz kommt eine Meldung.
    - Nach Widerruf der Zustimmung erscheint die Rückfrage erneut.
