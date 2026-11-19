# P6 Teilen-Erweiterung und Mail zu Aufgabe – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Status:** Entwurf vom 19.11.2026, ohne Mockups (Designrunde folgt in #188). Nichts gebaut, nichts am Gerät geprüft.
>
> **Voraussetzung:** P6 setzt auf dem Stand von `main` **nach dem Merge von P5** auf, weil P6 drei Dinge aus P5 nutzt:
> - Notiz-Anhänge (#155)
> - den Rezept-Ablauf (#150)
> - den Ordner „Brain Dump“
>
> Fehlt beim Start ein P5-Baustein auf `main`, wird das Ziel ohne ihn gebaut, also Notiz nur mit Text und Rezept als Text in die Artikel-Eingabe. Das kommt in den Bericht.

**Goal:**
- **#165:** Aus Safari, Mail, Dateien, Fotos und anderen Apps lässt sich über „Teilen“ direkt etwas in Tagwerk anlegen: eine Aufgabe mit Link bzw. Anhang, eine Notiz mit Anhang oder Einkaufsartikel bzw. ein Rezept.
- **#166:** Aus einer geteilten Mail wird eine Aufgabe. ChatGPT schlägt Titel, kurze Zusammenfassung und Fälligkeit vor, aber nur nach Zustimmung. Die Aufgabe enthält einen Link zurück zur Mail. Übernommen wird erst nach Bestätigung.

**Architecture:**

*Erweiterung (`TagwerkShare`):*
- Neues Target vom Typ `app-extension` mit dem Extension Point `com.apple.share-services`, `NSExtensionPrincipalClass` als UIKit-Controller und einem SwiftUI-Inhalt.
- Die Erweiterung legt **selbst nichts in den Quellen an**, also nicht in Erinnerungen, GitHub, im SwiftData-Store oder bei ChatGPT. Diese Daten liegen nur in der App, der Store bewusst nicht im Group-Container (Phase-7-Constraint). Die Tokens stehen in der Keychain der App.
- Die Erweiterung zeigt ein kleines Blatt: Ziel wählen, Titel und Text prüfen. Den Eintrag legt sie als **Eingang** (`ShareInboxItem`, JSON plus kopierte Dateien) im App-Group-Container ab.

*App:*
- Beim nächsten Aktivwerden liest die App den Eingang (`ShareInboxImporter`).
- Für jeden Eintrag öffnet sie das passende, vorbefüllte Blatt: „Neue Aufgabe“, Notiz-Editor oder Rezept- bzw. Artikel-Blatt.
- Gespeichert wird erst, wenn du im Blatt bestätigst. Danach wird der Eintrag samt Dateien gelöscht.

*Reine Regeln in `TagwerkCore`, ohne App testbar:*
- `SharePayload`: Klassifizierung der geteilten Inhalte.
- `ShareInboxItem`: Codable mit Version.
- `MailMessageParser`: Kopfzeilen einer `.eml` lesen.
- `MailLink`: `message:`-URL aus der Message-ID.
- `MailTaskSuggestion`: JSON-Antwort von ChatGPT, Normalisierung der Fälligkeit.

**Tech Stack:** Swift 6, SwiftUI und UIKit (Share Extension), App Groups, UniformTypeIdentifiers, AIKit (`ResponseStreaming`, ein einzelner Aufruf wie `MealEstimator`), Swift Testing, XcodeGen.

**Issues:** #165, #166. **Branch:** `feat/p6-share-mail`.

## Global Constraints

**Parallelbetrieb:** P2 bis P5 ändern gleichzeitig `RootView`, `AppEnvironment`, `AppSettings`, `NewTaskSheet`, `Localizable.xcstrings` und `project.yml`.
- In diesen Dateien gibt es nur additive Eingriffe: neue Parameter mit Standardwerten, eine neue `.sheet`-Zeile, ein neues Target-Kapitel.
- Keine Umbenennungen und kein Umsortieren.

**Keine Daten verlassen das Gerät aus der Erweiterung:**
- Die Erweiterung macht keinen Netzaufruf.
- Sie liest weder Keychain-Tokens noch den SwiftData-Store.
- Sie schreibt nur in `<group>/Library/Application Support/ShareInbox/`. Datenschutzklasse ist `.completeUntilFirstUserAuthentication`, gesetzt wird `isExcludedFromBackup`.

**ChatGPT:**
- Text einer Mail geht nur an ChatGPT, wenn beide Bedingungen erfüllt sind:
  - Die neue Einstellung `mailSummaryConsent` ist an. Standard ist aus, die Zustimmung kommt aus einem eigenen Blatt wie `MealConsentSheet`.
  - Du tippst im Blatt auf „Mit ChatGPT zusammenfassen“.
- Kein automatischer Aufruf.
- Gesendet werden nur Betreff, Absendername (ohne Adresse) und der Text, gekürzt auf höchstens 12 000 Zeichen.
- Nicht gesendet werden Anhänge, Message-ID und Empfänger.
- Nichts davon steht in Logs, im Chatverlauf oder in `ChatStore`.

**Eingang:**
- Höchstens 20 offene Einträge; ältere als 14 Tage werden beim Import verworfen.
- Dateien bis 25 MB je Eintrag. Größere werden in der Erweiterung abgelehnt, mit dem Hinweis „Zu groß für Tagwerk (höchstens 25 MB)“.
- Grund: Die Speichergrenze der Erweiterung liegt bei etwa 120 MB. Dateien werden deshalb per `loadFileRepresentation` kopiert, nicht in den Speicher geladen.

**Erweiterung:**
- Hängt nur an `TagwerkCore`.
- Keine SwiftData-, AIKit- oder GitHubKit-Abhängigkeit.
- `Tagwerk/App/Color+Hex.swift` darf wie beim Widget als geteilte Datei eingebunden werden.

**Texte und Commits:**
- Deutsch ist Quellsprache, jeder neue Text steht deutsch und englisch in `Localizable.xcstrings`.
- Die Erweiterung bekommt einen eigenen String Catalog `TagwerkShare/Localizable.xcstrings`, weil Kataloge nur im eigenen Target gelesen werden.
- Danach `scripts/sync-strings.sh` und `scripts/check-strings.py` ausführen. Prüfen, ob beide Skripte den neuen Katalog finden. Wenn nicht, den Suchpfad additiv ergänzen.
- Code, Kommentare, Logs und Testmeldungen sind englisch.
- Conventional Commits ohne Hinweis auf KI.

**Tests:**
- `app/test-all.sh` vor jedem Commit ab Task 3.
- Die Erweiterung selbst hat keine Unit-Tests. Ihre Logik liegt in `TagwerkCore`, die Oberfläche prüft das Gerät.

**SwiftUI:** `.sheet` und `.confirmationDialog` nie an Sections oder Zeilen in Form oder List hängen.

**Nicht in P6:**
- Direktes Anlegen aus der Erweiterung ohne die App zu öffnen.
- Teilen mehrerer Einträge mit unterschiedlichen Zielen in einem Schritt.
- Teilen an den Assistenten.
- Kurzbefehl-Aktion „In Tagwerk teilen“.

## Review Focus

1. **Eingang bei kaltem Start und mehreren Einträgen:**
   - Drei Teilungen hintereinander, danach wird die App erstmals geöffnet. Erwartet: Die Blätter erscheinen nacheinander, nach jedem Bestätigen oder Verwerfen das nächste. Kein Blatt geht verloren und keines erscheint doppelt.
   - Ein Eintrag, der gerade importiert wird, wird nicht ein zweites Mal geöffnet, auch wenn die App zweimal aktiv wird.
   - Tests: `ShareInboxImporterTests.threeItems_areOfferedInOrder`, `reactivation_doesNotOfferTheSameItemTwice`.
2. **Abbruch:**
   - „Verwerfen“ löscht Eintrag und Dateien.
   - Wird das Blatt weggewischt, bleibt der Eintrag für das nächste Aktivwerden, aber höchstens dreimal angeboten. Danach erscheint er nur noch als Zeile „Geteilt (n)“ in „Aufgaben“ (Task 9).
   - Test: `dismissedItem_isOfferedAgainAtMostThreeTimes`.
3. **Setup noch offen oder anderes Blatt offen:**
   - Vor `setupCompleted` wird nichts angeboten.
   - Ist ein anderes Blatt offen (Editor, Assistent), wartet der Eingang, bis es geschlossen ist. Kein Blatt über einem Blatt, siehe `presentRoutine(afterSheetClosed:)` in `RootView`.
4. **Mail ohne Zustimmung:**
   - Ist die Zustimmung aus, geht kein Byte an ChatGPT. Das Blatt zeigt Betreff als Titel und den Link zurück zur Mail.
   - Test: `MailTaskModelTests.withoutConsent_neverCallsTheResponder`.
5. **Fälligkeit aus der KI:**
   - Datum in der Vergangenheit, unparsebar oder mehr als 2 Jahre entfernt: keine Fälligkeit vorschlagen.
   - Nur Datum ohne Uhrzeit wird zu einer ganztägigen Fälligkeit.
   - Tests in `MailTaskSuggestionTests`.

---

## Task 0: Spikes (max. 3 h, Ergebnis als Nachtrag in diesen Plan)

**S1 Signierung mit dem Personal Team:**
1. Ein leeres Share-Extension-Target in `project.yml` anlegen (Bundle-ID `$(TAGWERK_BUNDLE_ID).share`, App Group wie das Widget).
2. Mit der lokalen Konfiguration aus `scripts/install-config.zsh` bauen: `xcodebuild -scheme Tagwerk -destination generic/platform=iOS -allowProvisioningUpdates DEVELOPMENT_TEAM=… TAGWERK_BUNDLE_ID=… build`. Werte nur aus der Konfigurationsdatei lesen, nie in den Plan oder Commits schreiben.
3. **Risiko:** Kostenlose Teams dürfen nur eine begrenzte Zahl neuer App-IDs je 7 Tage registrieren (laut Apple 10). Jede Erweiterung braucht eine eigene App-ID mit App Group. Bricht die Profilerstellung mit einem Limit- oder Capability-Fehler ab, gilt:
   - Fehlermeldung wörtlich festhalten.
   - Den Rest des Pakets trotzdem bauen und im Simulator testen, denn der Simulator braucht kein Profil.
   - Im Bericht vermerken, dass das Gerät erst nach Ablauf der Frist bzw. mit bezahltem Konto installiert werden kann.
4. Nicht auf dem iPhone installieren; das macht die Hauptsitzung mit dem Nutzer.

**S2 Was liefert Apple Mail im Teilen-Blatt (iOS 27)?**
1. Im eigenen Simulator der Arbeitskopie eine Mail-Quelle nachbilden, denn im Simulator gibt es kein Mail-Konto:
   - eine `.eml`-Datei über „Dateien“ teilen,
   - markierten Text aus Safari teilen.
2. Die Erweiterung loggt in DEBUG nur Typ-Kennungen (`registeredTypeIdentifiers`) und Größen, nie Inhalte.
3. Aus Apples Dokumentation und den Headern des SDK prüfen, ob Mail auf iOS 27 einen Teilen-Knopf für ganze Nachrichten hat und welche UTTypes es liefert (`com.apple.mail.email`, `public.email-message`/`.eml`, `public.plain-text`, `public.url`).
4. Ergebnis in eine Tabelle: Quelle → gelieferte Typen → was Tagwerk daraus macht.
5. **Rückfälle, wenn Mail keine ganze Nachricht teilt:**
   - **R1:** In Mail markierter Text wird über „Teilen“ geteilt. Es gibt keinen Betreff und keinen Link, aber eine Zusammenfassung.
   - **R2:** Eine `.eml` wird über „Dateien“ geteilt, etwa aus „Sichern in Dateien“ oder vom Mac.
   - **R3:** Kopierten Text in Tagwerk einfügen, über „Aus Zwischenablage“ im Blatt „Mail zu Aufgabe“ (Task 8).
6. Die Gerätetests prüfen das am echten iPhone nach.

**S3 `message:`-Link:**
- Prüfen, ob `UIApplication.shared.canOpenURL(URL(string: "message://%3C…%3E")!)` die Mail-App öffnet. Dazu braucht es `LSApplicationQueriesSchemes: [message]` in `Info.plist`.
- Falls nicht verlässlich: Link nur anlegen, wenn eine Message-ID vorliegt, und ohne `canOpenURL` speichern. Am Gerät prüfen.

- [x] Nachtrag „Spike-Ergebnis“ mit S1–S3 unter diesem Task, Commit `docs: record p6 spike results`.

### Spike-Ergebnis (Stand 19.11.2026, Arbeitskopie ohne Gerät und ohne Apple-ID in Xcode)

**S1 Signierung mit dem Personal Team: nicht entscheidbar, Rückfall gebaut.**
- Befund: `xcodebuild -scheme Tagwerk -destination generic/platform=iOS -allowProvisioningUpdates` mit den Werten aus `scripts/install-config.zsh` scheitert hier vor der Profilerstellung, weil in dieser Xcode-Sitzung keine Apple-ID angemeldet ist. Wörtlich:
  - `error: No Accounts: Add a new account in Accounts settings. (in target 'TagwerkShare' from project 'Tagwerk')`
  - `error: No profiles for '<Bundle-ID>.share' were found: Xcode couldn't find any iOS App Development provisioning profiles matching '<Bundle-ID>.share'. (in target 'TagwerkShare' from project 'Tagwerk')`
- Das ist kein Limit- oder Capability-Fehler. Ob das Personal Team eine weitere App-ID (`<Bundle-ID>.share` mit App Group) anlegen darf, ist damit weder bestätigt noch widerlegt. Es wurde keine App-ID registriert.
- Folge: Das Paket ist komplett gebaut und im Simulator getestet (der Simulator braucht kein Profil). Die Signierung der Erweiterung prüft die Hauptsitzung mit dem Nutzer (Gerätetest 1). Die Bundle-ID steht nicht in diesem Plan und nicht in den Commits.

**S2 Was liefert Apple Mail im Teilen-Blatt: am Gerät offen, alle drei Rückfälle gebaut.**
- Belegt: Im SDK (iPhoneSimulator 27.2) gibt es `UTType.emailMessage` (`public.email-message`). `com.apple.mail.email` ist in den SDK-Dateien nicht deklariert; die Kennung ist aus Mail auf dem Mac bekannt, für iOS **nicht belegt**. Die Erweiterung erkennt beide Kennungen und die Endung `.eml`.
- Nicht belegt: Der Simulator enthält kein Mail (39 Apps, keine Mail-App) und das Briefing verbietet die Gerätewerkzeuge; „Teilen“ aus „Dateien“ und Safari wurde deshalb nicht im Simulator ausgeführt. Die Erweiterung loggt in DEBUG die `registeredTypeIdentifiers` (nur Kennungen, nie Inhalte), damit der Gerätetest 7 die Antwort liefert.

| Quelle | gelieferte Typen (Erwartung, ungeprüft) | Was Tagwerk daraus macht |
|---|---|---|
| Datei `.eml` (Dateien, Mac, „Sichern in Dateien“) | `public.email-message` oder `com.apple.mail.email`, Dateiendung `.eml` | R2: Die Erweiterung liest höchstens die ersten 2 MB, `MailMessageParser` liest Betreff, Absender, Datum, Message-ID, Text. Die Datei wird nicht abgelegt. Ziel „Mail zu Aufgabe“. |
| In Mail markierter Text | `public.plain-text` | R1: Text; die Auswahl enthält „Mail zu Aufgabe“ (neben Aufgabe, Notiz, Einkauf, Rezept). Kein Betreff, kein Link. |
| Ganze Nachricht über Teilen in Mail | unbekannt (am Gerät klären) | Je nach Typ wie `.eml`, Text oder Link. |
| Kopierter Text | `public.utf8-plain-text` | R3: Menü am „+“ in „Aufgaben“ → „Mail aus Zwischenablage“. |

**S3 `message:`-Link: Entscheidung ohne `canOpenURL`.**
- Befund: `xcrun simctl openurl <Simulator> "message://%3Cabc@example.com%3E"` schlägt im eigenen Simulator mit `LSApplicationWorkspaceErrorDomain` Code 115 fehl, weil dort kein Mail installiert ist. Das sagt nichts über das iPhone.
- Entscheidung (konservativ, wie im Plan vorgesehen): Der Link steht als Text in den Notizen, wenn die Mail eine Message-ID hat, ohne `canOpenURL`. Deshalb kommt `LSApplicationQueriesSchemes` **nicht** in die `Info.plist`. Gerätetest 7 prüft, ob der Link genau diese Mail öffnet.

## Task 1: `SharePayload` – Klassifizierung (TagwerkCore)

**Files:**
- Create: `app/Packages/TagwerkCore/Sources/TagwerkCore/Share/SharePayload.swift`
- Test: `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/SharePayloadTests.swift`

**Datentyp:** `SharePayload` mit:
- `kind`: `.url`, `.text`, `.image`, `.file`, `.mail`
- `title?`, `text?`, `url?`, `fileNames: [String]`, `mail: MailMessage?`

`SharePayload.classify(_ parts: [SharePart])` ist rein. Ein `SharePart` ist ein Enum: Text, URL, Datei mit UTType-Kennung, Dateiname und Größe. Die Regeln:
1. Ist eine Datei vom Typ `.eml` oder `com.apple.mail.email` dabei, ergibt das `.mail`.
2. Ist eine URL mit `http`/`https` dabei, ergibt das `.url`. Ein zusätzlicher Text wird zum Titel, sonst der Host.
3. Bilder (`public.image`) ergeben `.image`, andere Dateien `.file`. Bei gemischten Dateien entscheidet die erste.
4. Sonst Text, wobei der Titel die erste nicht leere Zeile ist, gekürzt auf 120 Zeichen.
5. Leer, also nur Leerraum oder keine Teile, ergibt `nil`.

`SharePayload.suggestedTarget` liefert das vorgeschlagene Ziel:
- `.url` mit Rezeptmerkmal (Pfad oder Titel enthält „rezept“, „recipe“, „chefkoch“ ohne Groß- und Kleinschreibung) wird zu `.recipe`, sonst zu `.task`.
- `.mail` wird zu `.mailTask`.
- `.image` und `.file` werden zu `.note`.
- `.text` mit 1 bis 3 kurzen Zeilen (je höchstens 40 Zeichen) wird zu `.shopping`, sonst zu `.note`.

- [ ] Tests zuerst:
  - `url_withText_usesTextAsTitle`
  - `url_withoutText_usesHost`
  - `emlFile_isMail`
  - `image_isImage`
  - `mixedFiles_firstDecides`
  - `whitespaceOnly_isNil`
  - `longText_titleIsFirstLineCut`
  - `recipeURL_suggestsRecipe`
  - `shortLines_suggestShopping`
  - `pdf_suggestsNote`
- [ ] Umsetzen, Pakettests grün, Commit `feat: classify shared content`.

## Task 2: `ShareInboxItem` und Ablage (TagwerkCore)

**Files:**
- Create: `…/Share/ShareInboxItem.swift`, `…/Share/ShareInbox.swift`
- Test: `ShareInboxTests.swift`

**`ShareInboxItem`** (Codable, `version: 1`):
- `id: UUID`, `createdAt: Date`, `target: ShareTarget`, `title: String`, `text: String?`, `url: URL?`
- `files: [ShareInboxFile]` mit `name`, `relativePath`, `typeIdentifier` und `byteCount`
- `mail: MailMessage?`
- `offeredCount: Int`, Standard 0

**`ShareTarget`:** `.task`, `.note`, `.shopping`, `.recipe`, `.mailTask`.

**`ShareInbox(directory: URL, now: () -> Date, fileManager:)`** mit diesen Funktionen:
- `write(_ item:, copying files: [URL])`: kopiert die Dateien nach `<dir>/<id>/`, schreibt `<dir>/<id>.json` atomar und begrenzt den Eingang auf 20 Einträge. Ist er voll, wird der älteste verworfen.
- `pending() -> [ShareInboxItem]`: Einträge nach `createdAt` sortiert. Älter als 14 Tage, unlesbar oder eine unbekannte Version wird gelöscht.
- `markOffered(id)` erhöht `offeredCount`.
- `remove(id)` löscht JSON und Ordner.
- `fileURL(for:in:)` liefert den Pfad einer Datei.
- Kein Logging von Titeln oder Text.

- [ ] Tests zuerst:
  - `writeThenPending_roundTrips`
  - `pending_sortsByCreation`
  - `oldItems_areDropped`
  - `unknownVersion_isDropped`
  - `full_dropsOldest`
  - `remove_deletesFiles`
  - `markOffered_increments`
  - `filesAreCopiedNotMoved`

  Alle mit temporärem Ordner.
- [ ] Commit `feat: add the share inbox`.

## Task 3: Mail-Regeln (TagwerkCore)

**Files:**
- Create: `…/Share/MailMessage.swift` (`MailMessageParser`, `MailLink`), `…/Share/MailTaskSuggestion.swift`
- Test: `MailMessageParserTests.swift`, `MailLinkTests.swift`, `MailTaskSuggestionTests.swift`

**`MailMessageParser.parse(Data) -> MailMessage?`**
- `MailMessage` enthält `subject`, `senderName`, `senderAddress`, `date`, `messageID` und `bodyText`.
- Die Kopfzeilen werden nach RFC 5322 gelesen: Folding auflösen, RFC 2047 Encoded-Words in `=?utf-8?B?` und `?Q?`, `Date` per RFC-2822-Formatter.
- Der Text kommt aus dem ersten Teil `text/plain`, sonst aus `text/html` ohne Tags.
- Transfer-Encoding `quoted-printable` und `base64` werden unterstützt, Multipart rekursiv bis Tiefe 3.
- Kein Absturz bei kaputten Daten, dann `nil` oder leere Felder.

**`MailLink.url(messageID:) -> URL?`**
- Ergibt `message://%3C<id>%3E`, die spitzen Klammern werden entfernt und neu gesetzt, prozentkodiert.
- Leer oder voller Leerzeichen ergibt `nil`.

**`MailTaskSuggestion`** (Codable):
- `title` mit höchstens 80 Zeichen, `summary` mit höchstens 400 Zeichen, `due` als ISO-Datum oder Datum mit Uhrzeit, oder `null`.
- `normalized(now:calendar:)` gibt `title` und `summary` getrimmt zurück. `due` fällt weg, wenn es in der Vergangenheit liegt (vor heute), mehr als 730 Tage entfernt ist oder sich nicht parsen lässt.
- Ein reines Datum wird zu `TaskDue` ganztägig. Leerer Titel ergibt `nil`.
- `MailTaskSuggestion.instructions(language:)` liefert die Anweisung für ChatGPT. Inhalt: nur JSON, Sprache der App, keine erfundenen Fristen, `due` nur bei einem ausdrücklichen Datum in der Mail.

**Tests zuerst:**
- `plainMail_parsesHeaders`
- `encodedSubject_isDecoded`
- `foldedHeader_isJoined`
- `multipartAlternative_prefersPlain`
- `htmlOnly_stripsTags`
- `quotedPrintable_isDecoded`
- `garbage_returnsNil`
- `messageLink_wrapsAndEncodes`
- `emptyMessageID_hasNoLink`
- `pastDue_isDropped`
- `farDue_isDropped`
- `dateOnly_isAllDay`
- `emptyTitle_isNil`
- `overlongFields_areCut`

Die Fixtures sind selbst geschriebene `.eml` als String-Literale mit erfundenen Adressen (`example.com`).

- [ ] Commit `feat: parse shared mails and suggestions`.

## Task 4: Target `TagwerkShare` (Erweiterung)

**Files:**
- Modify: `app/project.yml`: neues Target nach `TagwerkWidget`, außerdem `- target: TagwerkShare` in den Abhängigkeiten von `Tagwerk`. Nur hinzufügen.
- Create:
  - `app/TagwerkShare/Info.plist`
  - `app/TagwerkShare/TagwerkShare.entitlements`
  - `app/TagwerkShare/ShareViewController.swift`
  - `app/TagwerkShare/ShareView.swift`
  - `app/TagwerkShare/ShareExtractor.swift`
  - `app/TagwerkShare/Localizable.xcstrings`

**`project.yml`:**
- `type: app-extension`, `PRODUCT_BUNDLE_IDENTIFIER: $(TAGWERK_BUNDLE_ID).share`, `GENERATE_INFOPLIST_FILE: NO`.
- Entitlements nur App Group `group.$(TAGWERK_BUNDLE_ID)`. Info-Eintrag `TagwerkAppGroup` wie beim Widget.
- `NSExtension`:
  - `NSExtensionPointIdentifier: com.apple.share-services`
  - `NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController`
  - `NSExtensionAttributes.NSExtensionActivationRule` als Dictionary:
    - `NSExtensionActivationSupportsWebURLWithMaxCount: 1`
    - `NSExtensionActivationSupportsText: true`
    - `NSExtensionActivationSupportsImageWithMaxCount: 5`
    - `NSExtensionActivationSupportsFileWithMaxCount: 5`
    - `NSExtensionActivationSupportsAttachmentsWithMaxCount: 5`
  - Kein `TRUEPREDICATE`, das lehnt App Review ab und ist ohnehin schlechter Stil.

**`ShareExtractor`:**
- Liest `NSExtensionItem.attachments` (`NSItemProvider`) in `SharePart`.
- URL über `loadObject(ofClass: URL.self)`, Text über `String.self`.
- Dateien über `loadFileRepresentation(for:)`. Die Datei wird im Callback sofort in einen temporären Ordner kopiert, denn die URL gilt nur dort.
- Größe vor dem Kopieren prüfen, über 25 MB ergibt einen Fehler.
- `attributedContentText` des Items wird zusätzlicher Text, so liefert Safari den markierten Text.

**`ShareView`** (SwiftUI in `UIHostingController`):
- Kopf mit Vorschau: Titel, Host bzw. Dateiname, Bildminiatur.
- Ziel-Auswahl als Picker mit „Aufgabe“, „Notiz“, „Einkauf“, „Rezept“ und „Mail zu Aufgabe“. Den letzten Eintrag gibt es nur bei `.mail` oder Text.
- Titel-Feld und Text-Feld zum Prüfen, „Abbrechen“ und „In Tagwerk sichern“.
- Danach eine Bestätigung: „Gesichert. Öffne Tagwerk, um es zu übernehmen.“ Sie schließt sich nach 1,2 s und ruft `completeRequest`.
- Fehlt der App-Group-Container, erscheint ein Fehlertext statt eines Absturzes: „Tagwerk kann gerade nichts übernehmen.“

**`ShareViewController`:** `UIViewController`, bettet `ShareView` ein und reicht `extensionContext` weiter.

**Texte:** in `TagwerkShare/Localizable.xcstrings`, deutsch und englisch.

**Vorgehen:**
- [ ] `xcodegen` laufen lassen wie in `app/test-all.sh`. Build im eigenen Simulator, App-Tests grün.
- [ ] Im eigenen Simulator mit den T3-Gerätewerkzeugen prüfen. Das gilt nur, wenn das Briefing es erlaubt, sonst ist es ein offener Gerätetest. Zu prüfen ist, ob in Safari „Teilen → Tagwerk“ erscheint und einen Eintrag schreibt.
- [ ] Commit `feat: add the share extension`.

## Task 5: `ShareInboxModel` und Import in der App

**Files:**
- Create: `app/Tagwerk/Share/ShareInboxModel.swift`, `app/Tagwerk/Share/ShareImportSheet.swift`
- Modify:
  - `AppEnvironment`: `let shareInbox: ShareInboxModel`, eine Zeile plus Init.
  - `TagwerkApp.swift`: in `onChange(of: scenePhase)` bei `.active` ein Aufruf `environment.shareInbox.refresh()`.
  - `RootView`: genau eine `.sheet(item:)` und eine Bedingung in `onChange`.
- Test: `app/TagwerkTests/ShareInboxImporterTests.swift`

**`ShareInboxModel`** (`@MainActor @Observable`):
- `refresh()` liest `ShareInbox.pending()`, filtert Einträge mit `offeredCount >= 3` in `parked` und setzt `current`.
- `current` ist der erste Eintrag, wenn `setupCompleted` gilt und kein Eintrag gerade offen ist.
- `finish(id, kept:)` entfernt den Eintrag und setzt den nächsten.
- `dismissed(id)` ruft `markOffered` auf, `current` wird `nil` und erst beim nächsten `refresh` neu gesetzt.

**`RootView`:**
- `.sheet(item: shareItem, onDismiss: …)` zeigt `ShareImportSheet(item:)`.
- Die Bindung liefert nur dann einen Eintrag, wenn kein anderes Blatt offen ist, also dieselben Bedingungen wie `hadOpenSheet` in `openRouterTarget()`.

**`ShareImportSheet`** schaltet nach `target`:
- `.task`: `NewTaskSheet(model:, prefilledTitle:, prefilledNotes:, prefilledURL:)`. Die neuen Parameter haben Standardwerte (Task 6).
- `.note`: legt erst beim Bestätigen eine Notiz an. Text plus URL, Dateien über die Anhang-API aus P5. Ordner ist „Alle Notizen“.
- `.shopping`: das vorhandene Eingabeblatt der Einkaufsliste mit vorbefülltem Text, eine Zeile je Artikel über `ShoppingInputParser`.
- `.recipe`: der Rezept-Ablauf aus P5 (#150), mit URL, Text oder Bild vorbefüllt.
- `.mailTask`: `MailTaskSheet` (Task 7).

**Tests**, das Modell mit einem Fake-`ShareInbox` im temporären Ordner:
- `threeItems_areOfferedInOrder`
- `reactivation_doesNotOfferTheSameItemTwice`
- `dismissedItem_isOfferedAgainAtMostThreeTimes`
- `nothingBeforeSetup`
- `finish_removesFiles`

- [ ] Commit `feat: import shared items into the app`.

## Task 6: Vorbefüllung „Neue Aufgabe“ mit Link und Notizen

**Files:**
- Modify: `app/Tagwerk/Tasks/NewTaskSheet.swift`, nur der Init: `prefilledNotes: String? = nil`, `prefilledURL: URL? = nil`, `prefilledDue: TaskDue? = nil`.
- Test: in den vorhandenen Tests zu `NewTaskSheet`, falls es welche gibt. Sonst ein kleiner reiner Helfer `NewTaskPrefill.notes(text:url:)` in `TagwerkCore` mit Tests.

**Regeln:**
- Der Link kommt als eigene letzte Zeile in die Notizen, außer die Quelle hat ein URL-Feld (Erinnerungen haben `url` in EventKit). Prüfen, ob `TaskDraft` schon ein URL-Feld kennt. Wenn ja, dieses nutzen, wenn nein, nur die Notizen.
- `prefilledDue` setzt `hasDue`, `dueDate` und `hasTime`.

**Tests:**
- `notes_appendURLOnOwnLine`
- `notes_withoutText_isOnlyURL`
- `due_dateOnly_setsNoTime`

- [ ] Commit `feat: prefill new tasks from shared content`.

## Task 7: Mail zu Aufgabe (#166)

**Files:**
- Create:
  - `app/Tagwerk/Share/MailTaskModel.swift`
  - `app/Tagwerk/Share/MailTaskSheet.swift`
  - `app/Tagwerk/Share/MailSummaryConsentSheet.swift`, Muster `MealConsentSheet`
- Modify:
  - `AppSettings`: `mailSummaryConsent: Bool = false`
  - `Info.plist` über `project.yml`: `LSApplicationQueriesSchemes: [message]`, falls S3 es braucht
- Test: `app/TagwerkTests/MailTaskModelTests.swift`

**`MailTaskModel`:**
- Eingabe ist `MailMessage` oder reiner Text aus R1/R3.
- `title` ist der Betreff oder die erste Zeile.
- `notes` setzt sich aus der Zusammenfassung (falls geholt), „Von: Name“ und dem Link zur Mail (`MailLink`, falls Message-ID vorhanden) zusammen.
- `due` ist der Vorschlag.
- `summarize()`:
  - ohne Zustimmung: das Zustimmungsblatt öffnen, keinen Aufruf machen,
  - mit Zustimmung: genau ein Aufruf über `ResponseStreaming`, wie `MealEstimator`, mit Zeitlimit 30 s,
  - die Antwort wird über `MailTaskSuggestion` dekodiert und normalisiert.
- Danach Felder vorschlagen. Felder, die du schon geändert hast, werden nicht überschrieben.
- Fehlertexte wie bei der Mahlzeiten-Schätzung, also nicht angemeldet, Zeitüberschreitung, nicht erkannt.

**`MailTaskSheet`:**
- Vorschau-Kopf mit Betreff, Absender und Datum.
- Knopf „Mit ChatGPT zusammenfassen“, nur wenn `ai.isSignedIn`, sonst ein Hinweis mit Weg zur Anmeldung.
- Vorgeschlagene Felder: Titel, Notizen, Fälligkeit mit Schalter. Ein vorgeschlagener Wert trägt die Marke „Vorschlag“, bis du ihn änderst oder bestätigst.
- „Weiter“ öffnet `NewTaskSheet` mit Titel, Notizen, URL und Fälligkeit. Erst dort wird gespeichert, mit Quelle und Liste wie immer.

**Datenschutzhinweis im Zustimmungsblatt** (deutsch und englisch): „Für die Zusammenfassung sendet Tagwerk Betreff, Absendername und Text der Mail an ChatGPT (OpenAI), nur wenn du auf „Mit ChatGPT zusammenfassen“ tippst. Anhänge, Adressen und Empfänger werden nie gesendet.“

**Einstellungen:** eine Zeile „Mails von ChatGPT zusammenfassen“, an der Stelle, wo die anderen ChatGPT-Zustimmungen stehen. Prüfen, wo `mealEstimationConsent` liegt, und dazu passend einordnen. Nur hinzufügen.

**Tests** mit einem Fake-Responder:
- `withoutConsent_neverCallsTheResponder`
- `withConsent_callsOnce`
- `userEditedTitle_isNotOverwritten`
- `invalidAnswer_showsNotRecognized`
- `timeout_showsTimeout`
- `notesContainMailLinkWhenMessageIDPresent`
- `sentInput_excludesAddressesAndMessageID`: Der Fake prüft dabei den Inhalt der Eingabe.

- [ ] Commit `feat: turn a shared mail into a task`.

## Task 8: Rückfall aus der Zwischenablage (R3)

**Files:** Modify `MailTaskSheet` bzw. den Einstieg in „Aufgaben“, im vorhandenen Menü „+“ bzw. „⋯“ eine Zeile „Mail aus Zwischenablage“. Nur hinzufügen.

- Liest `UIPasteboard` erst beim Tippen. iOS fragt dann nach, es gibt kein Auslesen im Hintergrund.
- Text ergibt `MailTaskModel(text:)`.
- [ ] Test: `MailTaskModelTests.pastedText_usesFirstLineAsTitle`. Commit `feat: create a mail task from the clipboard`.

## Task 9: Geparkte Einträge sichtbar machen

**Files:** Modify `TaskListView`, eine Zeile über der Liste, nur wenn `shareInbox.parked` nicht leer ist: „Geteilt (n)“. Sie öffnet eine Liste der geparkten Einträge mit „Übernehmen“ und „Verwerfen“.

- [ ] Test: `parkedItems_areListedAndCanBeRemoved` im Modell. Commit `feat: list parked shared items`.

## Task 10: Sicherung, Suche und Datenschutz prüfen

- **Datensicherung (#158):** Der Eingang wird **nicht** gesichert, weil er ein Zwischenspeicher ist. `isExcludedFromBackup` ist gesetzt. Ein kurzer Satz im Abschnitt Datensicherung der Doku.
- **Suche:** Der Eingang ist nicht durchsuchbar.
- **Datenschutztext:** Den bestehenden ChatGPT-Datenschutzhinweis in den Einstellungen um den Mail-Punkt ergänzen, nur hinzufügen.
- [ ] `scripts/sync-strings.sh`, `scripts/check-strings.py`, `app/test-all.sh` grün. Commit `docs: note share inbox and mail summary privacy`.

## Task 11: Abschluss

- [ ] Protokoll am Ende dieses Plans:
  - Spike-Ergebnisse
  - Abweichungen
  - eigene Entscheidungen mit Optionen und Risiko
  - offene Gerätetests
- [ ] Simulator und DerivedData der Arbeitskopie löschen, wie im Briefing beschrieben.

---

## Designpunkte für #188

- **Teilen-Blatt der Erweiterung:**
  - Picker oder Kacheln für das Ziel.
  - Wie groß die Vorschau ist (Bild, Link-Karte).
  - Ob Titel und Text schon in der Erweiterung bearbeitbar sind oder erst in der App.
  - Wortlaut und Dauer der Bestätigung „Gesichert. Öffne Tagwerk …“.
- **Übernahme in der App:** Die Blätter kommen nacheinander automatisch beim Öffnen, oder es gibt nur eine Marke „Geteilt (n)“ und der Nutzer öffnet selbst. Dazu der Platz der Zeile „Geteilt (n)“.
- **Mail zu Aufgabe:**
  - Aussehen des Vorschau-Kopfs.
  - Marke „Vorschlag“ an KI-Feldern.
  - Platz und Wortlaut von „Mit ChatGPT zusammenfassen“.
  - Ob der Link zur Mail als Zeile in den Notizen oder als eigener Knopf in der Aufgabe erscheint.
- **Rezept-Erkennung:** Geteilte Links automatisch als Rezept vorschlagen (Schlagworte) oder immer „Aufgabe“ vorwählen.
- **Notiz aus Teilen:** Zielordner fest „Alle Notizen“ oder wählbar, auch „Brain Dump“.

## Gerätetests

1. **Signierung:** `scripts/install-dev.sh` mit der neuen Erweiterung. Klappt die Profilerstellung mit dem Personal Team? Bei einem Limit-Fehler die Meldung festhalten.
2. **Safari → Teilen → Tagwerk:** Seite als Aufgabe. Die App öffnen: „Neue Aufgabe“ mit Titel und Link erscheint, Speichern in Erinnerungen und GitHub funktioniert.
3. **Safari mit markiertem Text:** Der Text landet als Notiz.
4. **Fotos:** zwei Bilder als Notiz, beide als Anhang sichtbar. Ein Video über 25 MB wird mit Hinweis abgelehnt.
5. **Dateien:** PDF als Notiz, öffnen und teilen aus der Notiz.
6. **Rezept-Link** (z. B. eine Rezeptseite): Der Rezept-Ablauf aus #150 startet vorbefüllt.
7. **Mail:**
   - Gibt es in Apple Mail einen Teilen-Weg für eine ganze Nachricht? Welche Typen kommen an?
   - Sonst Rückfall R1, markierter Text.
   - Link zurück zur Mail öffnet genau diese Mail.
   - Ohne Zustimmung kein Netzaufruf, mit Zustimmung sinnvolle Zusammenfassung und Fälligkeit.
8. **Kalter Start:** drei Teilungen bei geschlossener App, danach die Blätter nacheinander, keines doppelt.
9. **Gesperrtes Gerät:** Nach dem Entsperren aus dem Sperrbildschirm-Teilen sichern, dann den Import prüfen (Datenschutzklasse).
10. **Englische Oberfläche:** Erweiterung und Blätter.

---

## Protokoll (Abschluss, 19.11.2026)

**Stand:** Branch `feat/p6-share-mail` auf `origin/main` 0c7dd3b. Alle drei P5-Bausteine (Notiz-Anhänge, Rezept-Ablauf, Ordner „Brain Dump“) lagen auf `main`; es gab keinen Rückfall. `app/test-all.sh` grün: TagwerkCore 978, App 1521 Tests, String-Kataloge in Ordnung.

**Spike-Ergebnisse:** siehe Nachtrag unter Task 0. S1 (Signierung) scheitert in dieser Sitzung schon an „No Accounts“, S2 (Mail-Typen) und S3 (`message:`-Link) sind ohne Gerät nicht entscheidbar.

**Abweichungen vom Plan, mit Grund**
- `SharePayload.availableTargets` ist enger als im Plan: Dateien bieten nur Notiz und Aufgabe, Bilder zusätzlich Rezept, Mails Mail zu Aufgabe, Aufgabe und Notiz. Grund: Einkauf aus einer PDF ergibt keinen Sinn; eine Mail wird nicht als Einkauf geteilt.
- Aufgabe aus einer Datei übernimmt die Datei nicht (Aufgaben haben keine Anhänge). Die Erweiterung sagt das vor dem Sichern („Dateien werden nur bei Notizen übernommen.“) und legt die Datei dann gar nicht erst ab.
- Eine geteilte `.eml` wird bereits in der Erweiterung gelesen (höchstens 2 MB) und nicht kopiert. Grund: Speichergrenze der Erweiterung und Datenschutz (der Anhang landet nie im Eingang).
- `ShareInboxModel` hat `appBecameActive()` und `requestRefresh()` statt eines `refresh()` aus `TagwerkApp`: Das Wurzelblatt prüft, ob ein anderes Blatt offen ist (`refresh(canPresent:)`), weil nur es das weiß. `finish(_:)` ohne `kept`, `accept(_:)` und `ShareInbox.resetOffers` kamen für „Übernehmen“ in der Liste „Geteilt (n)“ dazu.
- Weggewischt = Eingang ruht bis zum nächsten Aktivwerden (nicht nur der eine Eintrag), und Einträge, die noch nie angeboten wurden, kommen vor erneut angebotenen. Grund: Drei weggewischte Blätter sollen nicht sofort wieder erscheinen.
- „Mail aus Zwischenablage“ liegt im Menü am „+“ (langes Drücken; Tippen legt wie bisher eine Aufgabe an), weil es in „Aufgaben“ kein vorhandenes Menü gab.
- Die Einwilligung `mailSummaryConsent` steht in Einstellungen › KI und im Backup-DTO (optional, wie `shoppingRecipeConsent`).
- `Tagwerk/App/Color+Hex.swift` wird nicht in die Erweiterung eingebunden (nicht gebraucht). Die Erweiterung hängt nur an `TagwerkCore`.
- `LSApplicationQueriesSchemes` wurde nicht eingetragen (S3-Entscheidung).
- Commits sind gröber geschnitten als die Tasks: Task 5, 7, 8 und 9 stecken in einem App-Commit, Task 10 und die Strings in einem Doku-Commit. `app/test-all.sh` lief erst nach Task 9 vollständig; die Paketteile liefen je Task einzeln.
- Tests wurden zusammen mit der Umsetzung geschrieben, nicht strikt vorher.

**Eigene Entscheidungen (Optionen, Risiko)**
- Notiz aus Teilen liegt im Ordner „Alle Notizen“ (kein Ordner). Option: „Brain Dump“ oder wählbar (Designpunkt #188). Risiko gering.
- Rezept-Erkennung per Schlagwort („rezept“, „recipe“, „chefkoch“ in Host, Pfad oder Titel) nur als Vorauswahl; im Blatt der Erweiterung änderbar.
- `NewTaskSheet` bekam `prefilledNotes`, `prefilledURL`, `prefilledDue`, `onDiscard` mit Standardwerten. `TaskDraft` hat kein URL-Feld, der Link steht deshalb als letzte Zeile in den Notizen.
- Schlägt ein Anhang beim Übernehmen in die Notiz fehl, wird die Notiz mit den übrigen Teilen angelegt und der Fehler in einem Hinweis genannt (Option: nichts anlegen; Risiko: doppelte Notiz beim Wiederholen).
- Zeitlimit der Zusammenfassung 30 s; Fehlertexte wie bei der Mahlzeitenschätzung, plus „zu lange gebraucht“.
- Das Prompt nennt das heutige Datum und sagt, der Mailtext sei Inhalt und keine Anweisung (Schutz vor eingebetteten Anweisungen). Das Datum ist nicht Teil der Mail.
- Die Erweiterung loggt in DEBUG nur Typ-Kennungen und Größen (`os.Logger`, `privacy: .public` nur dafür).
- **Blatt-Koordination:** `RootView.hasOpenSheet` kennt nur die Blätter der Wurzelansicht. Deshalb prüft `PresentedSheet.isShown` zusätzlich, ob das Fenster etwas präsentiert (Blätter der Tabs wie „Neue Aufgabe“, Mahlzeit, Rezept, Kamera, Hinweise). Ist ein Eintrag nur dadurch blockiert, prüft `RootView` bis zu 40-mal im Abstand von 1,5 s erneut (`ShareInboxModel.refresh(canPresent:)` meldet das mit `true`). Ein `tagwerk://`-Link oder eine angetippte Mitteilung schließt ein offenes Teilen-Blatt zuerst (`dismissCurrent()`), der Eintrag bleibt im Eingang. Ob SwiftUI ein Wurzel-Blatt über einem Tab-Blatt verwerfen würde, wurde nicht geprüft; die Prüfung vermeidet die Lage.
- **Adressen:** Das Zustimmungsblatt verspricht, dass keine E-Mail-Adressen gesendet werden. Deshalb ersetzt `MailTaskSuggestion.redactingAddresses` jede Adresse im Betreff, Absendernamen und Text durch „[Adresse]“, bevor gekürzt wird. Die Notizen der Aufgabe enthalten nur den Absendernamen („Von: Name“), nie die Adresse, weil Notizen in ein Issue oder über den Assistenten (`get_task`) zu ChatGPT gelangen können. Der Datenschutztext sagt deshalb, der Link zur Mail gehöre nicht zur Zusammenfassung, und weist darauf hin, dass der Assistent die Notiz einer Aufgabe auf Nachfrage lesen kann.
- **Mail als Notiz:** Eine als Notiz abgelegte Mail enthält Betreff, „Von: Name“, den Mailtext und den Link zurück zur Mail, weil die `.eml` nicht im Eingang liegt.

**Risiko für den Merge (Hauptsitzung beachten):** `scripts/refresh-install.sh` baut stündlich `main` und `scripts/install-dev.sh` den Arbeitsstand; beide brauchen nach dem Merge ein Profil für `<Bundle-ID>.share` mit App Group. Scheitert das (keine Apple-ID, App-ID-Limit des kostenlosen Kontos), fällt `refresh-install.sh` auf den letzten guten Commit vor P6 zurück und endet mit Exit-Code 4 samt Mitteilung, und `install-dev.sh` scheitert, bis die Signierung geklärt ist. Den Merge deshalb mit Gerätetest 1 abstimmen.

**Offene Gerätetests:** die Liste „Gerätetests“ unten gilt unverändert (1 bis 10). Zusätzlich zu klären:
- Welche Typen liefert Mail auf iOS 27 (DEBUG-Log der Erweiterung, Konsole am Mac)?
- Öffnet `message://%3C<Message-ID>%3E` genau die Mail (S3)?
- Erscheint „Tagwerk“ in der Aktivierungsliste von Safari, Fotos, Dateien und Mail, und wie viel Speicher braucht die Erweiterung bei 25-MB-Dateien (Grenze etwa 120 MB)?
- Setzt ein Sperrbildschirm-Teilen den Eintrag (Datenschutzklasse `completeUntilFirstUserAuthentication`)?
