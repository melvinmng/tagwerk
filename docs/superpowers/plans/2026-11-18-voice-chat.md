# Mit der KI sprechen – Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In allen Gesprächen mit der KI sprechen können:
- Diktat ins Eingabefeld (Mikrofon im Feld, Aufnahmeleiste mit mitlaufendem Text).
- Antworten vorlesen lassen (Knopf je Antwort, automatisch als Einstellung).
- Aktionskarten ansagen; bestätigt wird weiter per Tipp.
- Eine Seite „Sprache“ in den Einstellungen.
- Zustände für Berechtigung, Sprachpaket, kein Netz und Fehler.
- Als zweite Stufe ein Sprechmodus als halbhohes Blatt über dem Kalender.

Deutsch und Englisch werden beim Sprechen und beim Vorlesen unterstützt; die KI antwortet in der Sprache der letzten Nachricht.

**Architecture:** Erkennung und Vorlesen laufen auf dem iPhone, nicht über OpenAI:
- Erkennung: Apples `SpeechAnalyzer` mit `SpeechTranscriber`.
- Vorlesen: `AVSpeechSynthesizer`.

Beide hängen hinter Protokollen (`SpeechRecognizing`, `SpeechSpeaking`). So bleiben die Modelle mit Fakes testbar, und ein späterer ChatGPT-Weg kann ohne Umbau dazukommen. Die reine Logik liegt in `TagwerkCore/Voice/`:
- Text fürs Vorlesen aufbereiten
- Sprache erkennen
- Vorlese-Regel
- Ansage von Aktionskarten
- Zustandsautomat des Sprechmodus

Die App verbindet das in `VoiceInputModel` (Aufnahme), `VoiceOutputModel` (Vorlesen) und einem gemeinsamen Baustein `VoiceComposer` für die Eingabezeilen.

**Tech Stack:** Swift 6, SwiftUI (iOS 27), Speech (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`), AVFoundation (`AVAudioEngine`, `AVAudioSession`, `AVSpeechSynthesizer`), NaturalLanguage (`NLLanguageRecognizer`), SwiftData, Swift Testing.

**Quellen:**
- Mockups `docs/superpowers/mockups/2026-11-18-voice-chat-mockups.html`, freigegeben: SP1a, SP2a, SP3a, SP4a, SP5a, SP6a/b, SP7a, SP8a–f.
- Antworten des Nutzers vom 2026-11-18 (unten).
- Datenschutz §8.4 aus `docs/superpowers/specs/2026-11-17-phase-2b-design.md`.

## Entscheidungen (Nutzer, 2026-11-18)

1. **Weg A:** Erkennung und Vorlesen auf dem iPhone. ChatGPT-Sprache über die App-Anmeldung ist derzeit gesperrt:
   - `/v1/audio/*` und `/v1/realtime/calls` antworten 401 `no_matching_rule`.
   - Realtime-Sitzungen lassen sich anlegen, scheitern aber an `missing_compute_residency_info`.

   Die Seite „Sprachdienste prüfen“ (Einstellungen › KI) bleibt, um das später erneut zu prüfen.
2. **Optionen:** SP1a, SP2a, SP3 nach Empfehlung, SP4a, SP5a, SP6 nach Empfehlung, SP7a, SP8 nach Empfehlung.
3. **Sprachen:** Deutsch und Englisch.
   - Die Erkennung nimmt die eingestellte Sprache, Vorgabe „Automatisch“ = Sprache des iPhones. Ein Sprachchip in der Aufnahmeleiste wechselt für diese Aufnahme.
   - Das Vorlesen erkennt die Sprache der Antwort und nimmt die Stimme dieser Sprache.
4. **Sprache der KI:** Die KI antwortet in der Sprache, in der der Nutzer gerade schreibt oder spricht.
5. **App-Oberfläche auf Englisch:** eigener PR, nicht in diesem Plan.
6. **Mitlaufender Text:** wie SP1a. Die Antwort „ohne Live-Text“ bezog sich auf die ChatGPT-Erkennung, die nur am Ende liefert; Apple erkennt live. **Vorläufig, Bestätigung offen.**
7. **Offene Fragen der Mockups, vorläufig nach Empfehlung entschieden:**
   - Gesprochene Nachrichten tragen im Verlauf ein kleines Mikrofon.
   - Automatisches Vorlesen schweigt bei stummem Gerät; der Knopf „Vorlesen“ spricht immer.
   - Im Vorschlagsblatt nur Diktat, kein Vorlesen.
   - Der Sprechmodus läuft nicht im Hintergrund.
8. **Abweichung vom Mockup:** Das Feld „Was hast du gegessen?“ im Mahlzeiten-Blatt bekommt das kompakte Mikrofon wie das Vorschlagsblatt (SP6b). Es ist eine Eingabe an die KI, kein reines Textfeld. **Vorläufig.**

## Änderungen nach dem Fable-Review (2026-11-18) – gehen den Tasks unten vor

1. **Neuer Task 0: Spike am Gerät, vor Task 3.** Ein Abschnitt „Erkennung testen“ auf der Seite „Sprachdienste“ (Einstellungen › KI) zeigt am Gerät:
   - `SpeechTranscriber.isAvailable` und `DictationTranscriber.isAvailable`.
   - `supportedLocale(equivalentTo:)` für de-DE und en-US.
   - `AssetInventory.status` je Sprache; Paket laden mit Fortschritt.
   - Mikrofon-Berechtigung, Status der Spracherkennungs-Berechtigung (nur anzeigen, nicht anfragen).
   - Eine Probeaufnahme (Tipp zum Starten und Stoppen) mit `SpeechTranscriber` und `DictationTranscriber` im Vergleich, Text live.

   Ergebnis entscheidet: Transcriber-Klasse und ob die Abfrage „Spracherkennung“ nötig ist. **Die Spracherkennungs-Abfrage wird nicht vorsorglich gestellt**, ihr Systemtext widerspräche SP8a.
2. **Umwandlung** über `AnalyzerInputConverter` (`convert(_:at:)`, `flush()`), nicht über einen eigenen `AVAudioConverter`.
3. **Stopp-Ablauf** (Task 3):
   - `stop()`: `flush()`, Eingabestrom beenden, `finalizeAndFinishThroughEndOfInput()`, `results` bis zum Ende lesen, dann `.finished`.
   - `cancel()`: `cancelAndFinishNow()`.
   - Volatil/endgültig über `result.isFinal`.
   - `finish()`/`send()` warten auf `.finished` (Test `send_waitsForFinalText`).
4. **Sprachpaket** vollständig:
   - `AssetInventory.reserve(locale:)` unter Beachtung von `maximumReservedLocales`.
   - `status(forModules:)` inklusive `.unsupported`.
   - `assetInstallationRequest == nil` heißt „schon da“.
   - „Automatisch“ bei iPhone-Sprache außer de/en → Deutsch.
   - Sprachchip zeigt die andere Sprache nur an, wenn ihr Paket da oder ladbar ist.
5. **`ReadAloudPolicy` ohne `silenced`.** Der Stumm-Modus wirkt allein über `.ambient`. Die Kapsel zeigt beim automatischen Vorlesen trotzdem „Liest vor · Stopp“ (iOS meldet den Stummschalter nicht).
6. **Ein Besitzer der Audio-Session** hinter `VoiceAudioSession` (Protokoll, Fake):
   - Aufnahme `.record` (Stufe 1); `.playAndRecord` mit `.defaultToSpeaker`, `.allowBluetoothHFP` erst in Stufe 2.
   - Ausdrückliches Vorlesen `.playback` mit `.duckOthers`, automatisches `.ambient`; danach `setActive(false, .notifyOthersOnDeactivation)`.
   - Unterbrechung, Routenwechsel, `AVAudioEngineConfigurationChange` und Hintergrund beenden die Aufnahme (Text bleibt).
   - Der Tap-Block der Engine ist nicht MainActor-isoliert.
7. **Stabiler Schlüssel für „gesprochen“:** der Index der Nutzernachricht in `history` ist nicht stabil genug. Gespeichert wird die Anzahl der `InputItem`s vor der Nachricht plus deren Text-Hash. Beim Laden zählt nur ein Treffer beider; „Verlauf löschen“ leert die Liste.
8. **Fälle ergänzt:**
   - Blatt schließen verwirft die Aufnahme und stoppt das Vorlesen.
   - Kein automatisches Vorlesen bei geschlossenem Blatt.
   - Nach „Bestätigen“ wird „Ausgeführt“ gesagt, wenn vorgelesen wird.
   - „Vorlesen nicht möglich“ als Hinweiszeile.
   - Gerät ohne Unterstützung: kein Mikrofon, Hinweis in den Einstellungen.
   - Paket ohne Netz: „Sprachpaket fehlt · lädt, sobald du online bist“.
   - Eingeschränkt (Bildschirmzeit): „durch Einschränkungen gesperrt“.
9. **Reihenfolge:** Die `AppSettings`-Felder (Task 8, Tabelle) kommen als Task 2b vor Task 3; die Seite selbst bleibt in Task 8.
10. **Demo:** `FakeSpeechRecognizer` wird mit `-TagwerkDemoVoice` auch in der App nutzbar (liefert einen festen Satz stückweise), damit Simulator-Screenshots nicht von der Erkennung im Simulator abhängen.
11. **Aufnahme als reiner Automat** in `TagwerkCore/Voice/DictationMachine.swift` (Zustände, 60 s, 8 s Stille = 8 s ohne Textänderung, 4 s Hinweis, Entwurf wiederherstellen); `VoiceInputModel` nur noch Verdrahtung mit injizierter Uhr.
12. **Weitere Seams:** `VoicePermissionsProviding`, VoiceOver-Status als Closure, Stimmenliste und Ende-/Abbruch-Ereignisse in `SpeechSpeaking`.
13. **Eine Utterance je Satz;** die Markierung bezieht sich auf den Satz im Ausgangstext.
14. **`SpokenText` schlank:** Markdown, Emoji/✦, Prioritäten und Zeitspannen-Striche. Die Uhrzeit-Umrechnung „16:00 → 4 PM“ entfällt, bis am Gerät gehört ist, was die Stimme selbst macht.
15. **`voiceAnnounceActions`** gehört in Stufe 1 in den Abschnitt „Vorlesen“ („Änderungen ansagen“).
16. **Pegel** auf etwa 10 Hz gedrosselt.
17. **Mahlzeiten-Blatt** (Entscheidung 8) erst nach Bestätigung durch den Nutzer; nicht in PR 1.

## Lieferung in zwei PRs

- **PR 1, Stufe 1:** Tasks 1–9 (Diktat, Vorlesen, Ansagen, Einstellungen, Zustände, Sprache der KI).
- **PR 2, Stufe 2:** Tasks 10–12 (Sprechmodus).

## File Structure

**TagwerkCore** (`app/Packages/TagwerkCore/Sources/TagwerkCore/Voice/`):
- `SpokenText.swift` – macht aus Antworttext sprechbaren Text:
  - Markdown, Emoji und ✦ entfernen.
  - Kürzel ausschreiben: „P2“ → „Priorität zwei“ / „priority two“.
  - Uhrzeiten: „16:00“ → „16 Uhr“, „16:30“ → „16 Uhr 30“ / „4 PM“, „4:30 PM“.
  - Zeitspannen: „16:00–16:30“ → „16 Uhr bis 16 Uhr 30“.
  - Sätze für die Satzmarkierung aufteilen.
- `VoiceLanguage.swift` – `enum VoiceLanguage { german, english }`:
  - aus Locale ableiten,
  - Text erkennen (`NLLanguageRecognizer`, nur de/en; Vorgabe bei Unsicherheit: Sprache der App).
- `ReadAloudPolicy.swift` – `never` / `afterSpoken` / `always`; entscheidet, ob eine neue Antwort automatisch gelesen wird.
- `ActionAnnouncement.swift` – Ansagesatz je Aktionskarte und Sammelsatz für mehrere, in de/en.
- `VoiceModeMachine.swift` (Stufe 2) – Zustandsautomat des Sprechmodus.

**App** (`app/Tagwerk/Voice/`, neu):
- `SpeechRecognizing.swift` – Protokoll und `AppleSpeechRecognizer`:
  - `AVAudioEngine` → `SpeechAnalyzer`,
  - liefert volatile und endgültige Ergebnisse, Pegel und Ende.
- `SpeechSpeaking.swift` – Protokoll und `SystemSpeaker` (`AVSpeechSynthesizer`, Satz-Callbacks).
- `VoicePermissions.swift` – Mikrofon (`AVAudioApplication`), Spracherkennung (`SFSpeechRecognizer`, nur falls auf dem Gerät nötig), Sprachpaket (`AssetInventory`).
- `VoiceInputModel.swift` – Aufnahme-Zustand:
  - idle / explaining / recording(text, volatile, elapsed, level) / unavailable(reason) / notice(text),
  - Höchstdauer 60 s, Stopp nach 8 s Stille,
  - ✕ / Fertig / Senden.
- `VoiceOutputModel.swift` – eine Wiedergabe zur Zeit, aktueller Satz, Stopp, Stimmenwahl je Sprache.
- `VoiceComposer.swift` – Mikrofon im Feld und Aufnahmeleiste (volle Form SP1a, kompakte Form SP6b), Hinweiszeilen SP8.
- `ReadAloudButton.swift` – Kapsel „Vorlesen“ / „Liest vor · Stopp“.
- `VoiceSettingsView.swift` – SP7a.
- `VoiceModeSheet.swift` (Stufe 2) – SP5a.

**Geändert:**
- `ChatView.swift` – Composer, Vorlesen, Markierung „gesprochen“.
- `SuggestionViews.swift` – `SuggestionConversation` mit kompaktem Composer.
- `MealSheet.swift`
- `AssistantModel.swift` – gesprochene Nachrichten, automatisches Vorlesen, Ansage.
- `AIPlanner+Revision.swift` und `AssistantModel` (Anweisung zur Sprache).
- `AppSettings.swift`
- `AISettingsView.swift` – Zeile „Sprache“.
- `ChatStore.swift` – gesprochene Nachrichten speichern.
- `project.yml` – `NSMicrophoneUsageDescription`, `NSSpeechRecognitionUsageDescription`.
- `AppEnvironment.swift` – Voice-Modelle.

**Tests:**
- `app/Packages/TagwerkCore/Tests/TagwerkCoreTests/` – SpokenText, VoiceLanguage, ReadAloudPolicy, ActionAnnouncement, VoiceModeMachine.
- `app/TagwerkTests/` – VoiceInputModel, VoiceOutputModel, AssistantModel (gesprochen, Vorlesen, Ansage), ChatStore, Settings.
- Fakes in `TagwerkTests/Fakes/`: `FakeSpeechRecognizer`, `FakeSpeaker`, `FakeVoicePermissions`.

---

## Task 1: Sprechbarer Text und Sprache (TagwerkCore)

**Files:**
- Create: `TagwerkCore/Voice/SpokenText.swift`, `VoiceLanguage.swift`
- Test: `TagwerkCoreTests/SpokenTextTests.swift`, `VoiceLanguageTests.swift`

- [ ] **Step 1: Failing tests**
  - `spoken_stripsMarkdownAndSymbols`: „**Heute** ✦ drei Termine“ → „Heute drei Termine“.
  - `spoken_priority_de` / `_en`: „P2“ → „Priorität zwei“ / „priority two“; „P10“ bleibt.
  - `spoken_time_de`: „um 16:00“ → „um 16 Uhr“, „16:30“ → „16 Uhr 30“, „09:05“ → „9 Uhr 5“.
  - `spoken_time_en`: „at 16:00“ → „at 4 PM“, „09:30“ → „9:30 AM“.
  - `spoken_range`: „16:00–16:30“ / „16:00 bis 16:30“ → „16 Uhr bis 16 Uhr 30“.
  - `spoken_sentences`: drei Sätze mit Bereichen im Ausgangstext, für die Markierung.
  - `language_detectsGermanAndEnglish`, `language_shortTextFallsBack`, `language_fromLocale`.
- [ ] **Step 2:** Tests rot (`app/test-all.sh` oder Paketschema).
- [ ] **Step 3:** Implementieren (reine Funktionen, keine Abhängigkeit außer Foundation/NaturalLanguage).
- [ ] **Step 4:** Tests grün, Commit `feat: prepare answers for speech in German and English`.

## Task 2: Vorlese-Regel und Ansagen (TagwerkCore)

**Files:**
- Create: `Voice/ReadAloudPolicy.swift`, `Voice/ActionAnnouncement.swift`
- Test: `ReadAloudPolicyTests.swift`, `ActionAnnouncementTests.swift`

- [ ] **Step 1: Failing tests**
  - `policy_never_neverSpeaks`, `policy_afterSpoken_onlyWhenLastUserMessageWasSpoken`, `policy_always_speaksUnlessMuted` (automatisches Vorlesen schweigt bei `silenced == true`), `policy_explicitTap_alwaysSpeaks`.
  - `announce_single_de`: Titel „Zeitblock anlegen“, Änderung „Mail an Prüfungsamt · Mi 18. Nov. · 16:00 bis 16:30“ → „Ich schlage vor: Zeitblock anlegen, Mail an Prüfungsamt, Mittwoch 18. November, 16 Uhr bis 16 Uhr 30. Bitte bestätige auf dem Bildschirm.“ (über SpokenText).
  - `announce_multiple_de`: „Drei Änderungen warten auf deine Bestätigung.“
  - `announce_en` jeweils englisch.
- [ ] **Step 2–4:** rot, implementieren, grün. Commit `feat: decide when to read answers aloud and announce action cards`.

## Task 3: Erkennung und Berechtigungen (App)

**Files:**
- Create: `Voice/SpeechRecognizing.swift`, `Voice/VoicePermissions.swift`, `TagwerkTests/Fakes/FakeSpeechRecognizer.swift`, `FakeVoicePermissions.swift`
- Modify: `project.yml` (Usage-Texte de, Inhalt wie SP8a: Umwandlung auf dem iPhone, Ton verlässt das Gerät nicht)

Protokoll:

```swift
protocol SpeechRecognizing: AnyObject, Sendable {
    /// Starts recording in `language`; events arrive until `.finished` or `.failed`.
    func start(language: VoiceLanguage) async throws -> AsyncStream<RecognitionEvent>
    func stop() async          // finalize: remaining audio becomes final text
    func cancel() async        // discard
}
enum RecognitionEvent: Equatable, Sendable {
    case text(final: String, volatile: String)
    case level(Float)          // 0...1
    case finished
    case failed(RecognitionFailure)   // .interrupted, .noSpeech, .unavailable, .assetMissing
}
```

- `AppleSpeechRecognizer`:
  - `SpeechTranscriber(locale:, transcriptionOptions: [], reportingOptions: [.volatileResults], attributeOptions: [])`.
  - `SpeechAnalyzer.bestAvailableAudioFormat`; Umwandlung mit `AVAudioConverter`; `AnalyzerInput` aus einem `AsyncStream`.
  - Audio-Session `.playAndRecord`, `.spokenAudio`; Pegel aus RMS.
  - Unterbrechung (Anruf, Route) → `.failed(.interrupted)`.
- `VoicePermissions`: Status Mikrofon / Spracherkennung / Sprachpaket je Sprache; `request()`; `installAsset(language)` mit Fortschritt (`AssetInventory.assetInstallationRequest`).
- Ob `SFSpeechRecognizer.requestAuthorization` für `SpeechAnalyzer` nötig ist, wird am Gerät geprüft. Bis dahin werden beide angefragt (SP8a nennt beide).
- [ ] **Step 1:** Keine Unit-Tests für die Apple-Klassen selbst (Hardware). Testbar sind die Umwandlung der Ergebnisse (`final` + `volatile` zusammensetzen) und die Pegelberechnung als statische Funktionen (`recognizer_joinsFinalAndVolatile`, `level_rmsToUnitRange`).
- [ ] **Step 2–4:** rot, implementieren, grün. Gerät: Prüfliste unten. Commit `feat: recognize speech on the device in German and English`.

## Task 4: Aufnahme-Modell (App)

**Files:**
- Create: `Voice/VoiceInputModel.swift`
- Test: `TagwerkTests/VoiceInputModelTests.swift`

Verhalten (SP1a, SP2a, SP8):
- `tapMicrophone()`:
  - erstes Mal und noch nie erklärt → `.explaining` (SP8a);
  - Berechtigung abgelehnt → `.unavailable(.permissionDenied)` (SP8b);
  - Sprachpaket fehlt → `.preparing(progress)`, danach automatisch Aufnahme (SP8c);
  - sonst `.recording`.
- Während der Aufnahme: `text` = bisheriger Feldinhalt + Leerzeichen + erkannter Text (SP1a: Tipp hängt an).
- `finish()` legt den Text ins Feld (Binding) und beendet. `send()` beendet und gibt den Text an `onSend`. `cancel()` verwirft und stellt den Feldinhalt von vorher wieder her.
- Automatisches Ende nach 60 s oder 8 s ohne neuen Text → wie `finish()`.
- Leeres Ergebnis → `.notice(.nothingHeard)`, verschwindet nach 4 s (SP8e).
- Unterbrechung → bisheriger Text ins Feld, `.notice(.interrupted)`.
- `isEnabled == false`, wenn nicht angemeldet (SP8f) oder Spracheingabe aus.
- Senden während die KI antwortet: Aufnahme erlaubt, ↑ gesperrt (SP8f).
- Sprachchip: wechselt die Sprache und startet die Aufnahme neu; der bisher erkannte Text bleibt.

- [ ] **Step 1: Failing tests** (Fake-Recognizer mit steuerbaren Ereignissen, Fake-Uhr):
  - `firstTap_explainsBeforeAsking`, `explanationContinue_requestsPermissions_thenRecords`, `explanationNotNow_staysIdle`
  - `denied_showsUnavailable`
  - `assetMissing_installsThenRecords`
  - `recording_appendsToExistingDraft`
  - `finish_putsTextIntoDraft`, `send_callsOnSendWithText`, `cancel_restoresDraft`
  - `silence8s_finishes`, `max60s_finishes`
  - `emptyResult_showsNothingHeard_thenClears`
  - `interrupted_keepsTextAndShowsNotice`
  - `notSignedIn_disabled`, `busy_recordsButSendDisabled`
  - `languageChip_restartsKeepingText`
  - `spokenFlag_setWhenSentFromRecording_orAfterDictation` (eine Nachricht gilt als gesprochen, wenn ihr Text aus einer Aufnahme stammt)
- [ ] **Step 2–4:** rot, implementieren, grün. Commit `feat: record dictation into the message field`.

## Task 5: Vorlesen (App)

**Files:**
- Create: `Voice/SpeechSpeaking.swift`, `Voice/VoiceOutputModel.swift`, `Voice/ReadAloudButton.swift`, `Fakes/FakeSpeaker.swift`
- Test: `VoiceOutputModelTests.swift`

- `SystemSpeaker`:
  - `AVSpeechSynthesizer`, Stimme je Sprache aus den Einstellungen; sonst die beste installierte (Premium > Enhanced > Default) für `de-DE` / `en-US`.
  - Rate aus den Einstellungen.
  - Satzbereiche über `willSpeakRangeOfSpeechString`.
  - Audio-Session: `.playback` bei ausdrücklichem Tipp (spricht auch im Stumm-Modus), `.ambient` bei automatischem Vorlesen (schweigt im Stumm-Modus).
- `VoiceOutputModel`:
  - `speak(id, text, explicit:)` erkennt die Sprache, bereitet den Text auf (SpokenText) und stoppt eine laufende Wiedergabe.
  - `speakingID`, `currentSentence`, `stop()`.
  - Stoppt bei Mikrofon-Tipp, beim Senden einer neuen Nachricht und beim Schließen des Blatts (SP3a).
  - Spricht nicht, solange VoiceOver läuft und der Tipp nicht ausdrücklich war (Mockup: VoiceOver und Vorlesen nicht gleichzeitig).
- `ReadAloudButton`: Kapsel „Vorlesen“ / „Liest vor · Stopp“; in der laufenden Antwort wird der aktuelle Satz hinterlegt.
- [ ] **Step 1: Failing tests:** `speak_detectsLanguageAndPreparesText`, `speak_stopsPrevious`, `stop_clearsState`, `micTap_stopsSpeech`, `autoSpeak_usesAmbient_explicitUsesPlayback`, `voiceOver_suppressesAutomatic`
- [ ] **Step 2–4:** rot, implementieren, grün. Commit `feat: read answers aloud with the system voice`.

## Task 6: Composer in den Gesprächen (App)

**Files:**
- Create: `Voice/VoiceComposer.swift`
- Modify:
  - `ChatView.swift` (Composer, Kapsel „Vorlesen“ unter jeder Antwort, Mikrofon-Marke an gesprochenen Nachrichten)
  - `SuggestionViews.swift` (`SuggestionConversation`, kompakt, ohne „Fertig“, Tipp in die Zeile beendet)
  - `MealSheet.swift` (kompakt)

Details:
- Mikrofon im Feld rechts, unsichtbar auf 44 pt vergrößert.
- Aufnahmeleiste mit rotem Rand, Laufzeit, Pegel, Text (volatile grau), ✕, ■ Fertig, ↑, Sprachchip „DE“/„EN“.
- Barrierefreiheit: Beschriftungen „Sprechen“, „Aufnahme verwerfen“, „Aufnahme beenden“, „Senden“, „Vorlesen“.
- Im Vorschlagsblatt weichen Kurzantworten und Entscheidungsleiste während der Aufnahme, wie beim Tippen (`isTyping`).
- [ ] **Step 1:** UI selbst wird am Simulator geprüft (Screenshots gegen SP1a, SP3a, SP6a/b, SP8). Unit-Tests decken die Modelle ab (Task 4, 5). Snapshot nicht nötig.
- [ ] **Step 2:** Einbauen, Simulator mit Demo-Daten (`-TagwerkDemoData -TagwerkDemoAI`). Der Simulator hat ein Mikrofon über den Mac; ein Fake-Erkenner für die Demo ist nicht nötig.
- [ ] **Step 3:** Commit `feat: talk to the assistant, in task chats and on suggestions`.

## Task 7: Gesprochene Nachrichten, automatisches Vorlesen, Ansage (App)

**Files:**
- Modify: `AssistantModel.swift`, `ChatStore.swift` (`spokenData: Data` mit Standardwert), `ChatView.swift`
- Test: `AssistantModelTests.swift`, `ChatStoreTests` (falls vorhanden, sonst in AssistantModelTests)

Verhalten:
- `send(_ text: String, spoken: Bool)` merkt sich die ID der Nutzernachricht als gesprochen und speichert sie.
- Nach einer abgeschlossenen Antwort fragt das Modell `ReadAloudPolicy`; bei Ja liest `VoiceOutputModel` die Antwort automatisch.
- Neue Aktionskarten werden angesagt (SP4a), wenn vorgelesen wird (automatisch oder im Sprechmodus). Die Karte selbst ändert sich nicht.
- [ ] **Step 1: Failing tests:**
  - `sendSpoken_marksMessageAndPersists`
  - `autoRead_never_doesNotSpeak`, `autoRead_afterSpoken_speaksOnlyAfterSpoken`, `autoRead_always_speaks`
  - `newActionCard_isAnnouncedWhenReading`, `multipleCards_announcedTogether`
  - `clear_dropsSpokenMarks`
- [ ] **Step 2–4:** rot, implementieren, grün. Commit `feat: mark spoken messages, read answers automatically, announce changes`.

## Task 8: Einstellungen „Sprache“ (App)

**Files:**
- Create: `Voice/VoiceSettingsView.swift`
- Modify: `AppSettings.swift`, `AISettingsView.swift`
- Test: `CaptureSettingsTests`-Muster → `VoiceSettingsTests.swift`

Neue Felder in `AppSettings`, alle mit Standardwert:

| Feld | Standardwert |
|---|---|
| `voiceInputEnabled` | `true` |
| `voiceExplained` | `false` |
| `voiceRecognitionLanguage` | `"auto"` |
| `voiceReadAloud` | `"never"` |
| `voiceGermanVoiceID` | `nil` |
| `voiceEnglishVoiceID` | `nil` |
| `voiceRate` | `0.5` |
| `voiceModePause` | `2` (Stufe 2) |
| `voiceModeSilenceEnd` | `30` (Stufe 2) |
| `voiceAnnounceActions` | `true` |

Seite (SP7a):
- **Spracheingabe:** Schalter; Status Mikrofon, Spracherkennung, Sprachpaket Deutsch, Sprachpaket Englisch; „Nicht erlaubt“ öffnet die iOS-Einstellungen.
- **Erkennung in:** Automatisch / Deutsch / English.
- **Vorlesen:** Antworten vorlesen; Stimme Deutsch, Stimme Englisch (Liste der installierten Stimmen); Tempo; Probe hören.
- **Datenschutzhinweis:** Umwandlung auf dem Gerät, kein Ton an OpenAI.
- Abschnitt „Sprechmodus“ erst mit Stufe 2.
- In „KI“ eine Zeile „Sprache · Mikrofon an, Vorlesen nie ›“.

- [ ] **Step 1: Failing tests:** `defaults`, `recognitionLanguage_autoFollowsLocale`, `summaryLine_text`
- [ ] **Step 2–4:** rot, implementieren, grün. Commit `feat: add voice settings`.

## Task 9: Sprache der KI-Antworten

**Files:**
- Modify:
  - `AssistantModel.swift`: Anweisung „Antworte knapp in der Sprache der letzten Nachricht des Nutzers (Deutsch oder Englisch).“
  - `AIPlanner+Revision.swift`: `reply` in der Sprache des Kommentars.
  - `AIPlanner.swift`: Begründungen bleiben Deutsch, solange die App-Oberfläche Deutsch ist. Das gilt bis zum PR „App auf Englisch“.
- Test: bestehende Tests, die den Anweisungstext prüfen, anpassen; `instructions_answerInUsersLanguage`.
- [ ] Commit `feat: answer in the language the user writes or speaks`.

**Ende Stufe 1:**
- `app/test-all.sh` grün.
- Simulator-Screenshots.
- Fable-Review des Branches, Befunde beheben.
- iPhone-Installation.
- Gerätetest durch den Nutzer.
- PR 1 (`file-pr`), nach Freigabe mergen.

---

## Task 10: Zustandsautomat Sprechmodus (TagwerkCore, Stufe 2)

**Files:**
- Create: `Voice/VoiceModeMachine.swift`
- Test: `VoiceModeMachineTests.swift`

Zustände:
- `listening(text)`
- `countdown(text, remaining)`
- `sending`
- `waiting`
- `speaking`
- `awaitingConfirmation`
- `paused(reason)` mit `silence`, `offline`, `interrupted`
- `ended`

Ereignisse:
- `heard(text)`, `silence(seconds)`, `tick`
- `doNotSend`, `answerStarted`, `answerFinished(hasPendingCard:)`
- `cardResolved`, `failed(offline:)`, `interrupt`, `end`, `background`

Regeln:
- 2 s Pause startet den Countdown; „Nicht senden“ legt den Text ins Feld und wechselt in den normalen Chat.
- Während `speaking` ist das Mikrofon aus.
- Mit offener Karte geht es nach `awaitingConfirmation`, weiterhören erst nach `cardResolved`.
- 30 s Stille → `paused(.silence)`.
- Hintergrund, Anruf oder Sperre → `ended`.
- Kein Senden aus `paused` oder `ended`.

- [ ] Tests für jede Regel, dann Implementierung. Commit `feat: add the voice mode state machine`.

## Task 11: Sprechmodus-Blatt (App, Stufe 2)

**Files:**
- Create: `Voice/VoiceModeSheet.swift`, `Voice/VoiceModeController.swift`
- Modify: `ChatView.swift` (Einstieg: bei leerem Feld wird ↑ zum Pegel-Knopf), `RootView`/Präsentation des Chats (Höhenstufen `.medium`/`.large`, Kalender bis zur halben Höhe bedienbar wie beim Vorschlagsblatt)
- Test: `VoiceModeControllerTests.swift` (Fakes für Erkenner, Sprecher, Assistent)

Verhalten (SP5a):
- Kopf „✦ Sprechmodus · Kontext · Beenden“, Zustandszeile, letzter Wortwechsel, Knöpfe „Pause“ / „Unterbrechen“, „Tippen“, „Verlauf“.
- Ton nach dem Vorlesen, dann wieder zuhören.
- Einmaliger Hinweis beim ersten Start.
- Kein Netz → Ansage „Keine Verbindung“, `paused(.offline)`.

- [ ] Tests: `loop_listenSendSpeakListen`, `pendingCard_pausesListening`, `doNotSend_movesTextToDraft`, `background_ends`, `offline_pauses`
- [ ] Commit `feat: add the voice mode sheet`.

## Task 12: Einstellungen Sprechmodus, Abschluss Stufe 2

- `VoiceSettingsView`, Abschnitt „Sprechmodus“: Senden nach Pause (1, 2, 3 s), Endet nach Stille (15, 30, 60 s), Änderungen ansagen.
- `test-all.sh`, Simulator, Fable-Review, iPhone, PR 2.

---

## Geräte-Prüfliste (Nutzer)

- Erste Aufnahme: Erklärung, dann die iOS-Abfragen; Text läuft mit; Deutsch und Englisch (Sprachchip).
- Sprachpaket Englisch laden lassen (Einstellungen › KI › Sprache).
- Anruf oder Siri während der Aufnahme → Text bleibt, Hinweis.
- Vorlesen mit Stummschalter an/aus: Knopf spricht, automatisch schweigt.
- Premium-Stimme in iOS laden → erscheint unter „Stimme“.
- Aktionskarte bei „Antworten vorlesen: Immer“ wird angesagt, bestätigt nur per Tipp.
- Prüfen, ob die Abfrage „Spracherkennung“ für `SpeechAnalyzer` überhaupt nötig ist; wenn nicht, wird sie entfernt.
- Stufe 2: Sprechmodus mit Kopfhörern und ohne; Echo (hört Tagwerk sich selbst?).
