# Siri-Kurzbefehle reparieren (#178)

**Ziel:** Ursache finden, warum Siri auf dem iPhone keinen Tagwerk-Kurzbefehl erkennt, sondern eine Websuche startet, und sie beheben. Belegen, was am Build überprüfbar ist. Für Melvin eine kurze Checkliste für den Gerätetest erstellen. Siri lässt sich im Simulator nicht prüfen.

**Rahmen:** Keine Änderungen an `TODO.md`, kein `t3gh`. Keine Installation auf dem iPhone. Die macht Melvin.

## Bestand

- `TagwerkShortcuts: AppShortcutsProvider` in `app/Tagwerk/Intents/TagwerkIntents.swift:258-302`: 8 Kurzbefehle mit 24 Sätzen, alle mit `\(.applicationName)`.
- Katalog `app/Tagwerk/AppShortcuts.xcstrings` (Quellsprache de, 24 Schlüssel mit `${applicationName}` usw., alle mit `en`).
- Parameter über `ShoppingArticleEntity` (id = Name), `HabitEntity` und `WorkoutActivityOption`. `updateAppShortcutParameters()` in `TagwerkApp.swift:30` und `AppEnvironment.swift:687/690`.
- Kein `INAlternativeAppNames`, keine Siri-Einträge in `project.yml` oder `Info.plist`. Für App Intents nicht nötig.
- Protokoll und API-Grenzen: `docs/superpowers/2026-11-19-overnight-log.md`, Abschnitt „Siri Einkaufsliste“ (ab Zeile 280).
- Auf dem Gerät betrifft der Fehler mindestens alle Einkaufslisten-Sätze. Ob die Sätze aus Phase 4 („Wasser in Tagwerk erfassen“) funktionieren, ist unbekannt.

## Vorgehen

1. Plan nach `docs/superpowers/plans/2026-11-19-siri-shortcuts-fix.md` legen und committen.
2. **Build-Belege sammeln.** Gerätebuild ohne Installation wie in `scripts/install-dev.sh`, aber mit `-destination 'generic/platform=iOS'` und ohne Signierung (`CODE_SIGNING_ALLOWED=NO`), dazu ein Simulator-Build. Im erzeugten `Tagwerk.app` prüfen:
   - Gibt es `Metadata.appintents/` mit `extract.actionsdata`, und sind dort alle 8 Kurzbefehle mit ihren Sätzen enthalten?
   - Liegen die Sätze lokalisiert vor (`de.lproj/AppShortcuts.strings` oder das kompilierte Gegenstück aus dem `.xcstrings`)? Ist `AppShortcuts.xcstrings` überhaupt Ressource des App-Targets (`app/project.yml`)?
   - Meldet das Build-Log Warnungen von `appintentsmetadataprocessor` (z. B. ungültige Sätze, fehlende Übersetzung, zu viele Sätze, Satz ohne Parameter-Werte)?
   - Ergebnis jeweils mit Pfad und Auszug im Plan festhalten.
3. **Sätze prüfen und bereinigen.** Doppeldeutige oder sich überdeckende Sätze entfernen (z. B. „Einkaufsliste in Tagwerk“ neben „Einkaufsliste in Tagwerk zeigen“) und Sätze vermeiden, die Siri als allgemeine Anfrage deutet. Eher wenige, eindeutige Sätze je Kurzbefehl. Die Zahl der Sätze je Kurzbefehl begründen. Katalog und `CaptureSettingsView.swift:49-64` (angezeigte Satzliste) synchron halten.
4. **App-Name.** `INAlternativeAppNames` in den Info-Einstellungen über `project.yml` ergänzen (z. B. „Tag Werk“), mit Aussprache-Hinweis, falls sinnvoll. Vorher an Apples Dokumentation prüfen, ob App Shortcuts diese Namen nutzen, und das Ergebnis im Plan festhalten.
5. **Prüfhilfe in der App.** In „Siri & Kurzbefehle“ (`CaptureSettingsView`) einen `ShortcutsLink()` ergänzen, der die Tagwerk-Kurzbefehle in der App „Kurzbefehle“ öffnet. Optional einen `SiriTipView` für den wichtigsten Satz. So sieht Melvin sofort, ob die Kurzbefehle registriert sind.
6. **Weitere Ursachen, die nur am Gerät klärbar sind**, als Checkliste im Plan:
   - Erscheinen die Tagwerk-Kurzbefehle in der App „Kurzbefehle“, und laufen sie dort per Tipp?
   - Funktionieren die Sätze aus Phase 4 per Siri?
   - Einstellungen → Siri → Apps → Tagwerk: „Von dieser App lernen“ und „Bei Siri verwenden“ aktiv?
   - Siri-Sprache Deutsch, iPhone-Sprache Deutsch?
   - Nach einer Neuinstallation über `install-dev.sh` einmal die App öffnen, dann 1–2 Minuten warten.
   - Gilt die Einschränkung auch nach einem Neustart des iPhones?
7. Tests: Wo sinnvoll, Unit-Tests für die Satzliste. Zum Beispiel muss jeder Satz `${applicationName}` enthalten, und jeder Satz im Code muss einen Katalogschlüssel mit `en` haben. Ein solcher Test existiert eventuell schon in `scripts/check-strings.py`, dann nicht doppeln.
8. `app/test-all.sh` grün.

## Abnahme

- Belegte Diagnose im Plan. Entweder eine gefundene Ursache im Build mit Behebung, oder der Nachweis, dass der Build korrekt ist, sodass die Ursache am Gerät oder in der Siri-Konfiguration liegt.
- Bereinigte Sätze, `ShortcutsLink` in den Einstellungen, Gerätetest-Checkliste.
- Ehrlich kennzeichnen, was nur am Gerät bestätigt werden kann.

## Für das Design-Sammelissue

- Platzierung und Aussehen von `ShortcutsLink` und `SiriTipView`.

## Stand

Stand: 2026-11-19, Branch `fix/siri-shortcuts`. Alle Aussagen zu Siri-Erkennung unten sind entweder am Build belegt (Abschnitt „Belege“) oder ausdrücklich als Hypothese oder Gerätetest gekennzeichnet.

### Diagnose

**Der Build ist korrekt. Im Build ließ sich keine Ursache für die fehlende Erkennung finden.** Die Ursache liegt damit am Gerät, in der Siri-Konfiguration oder in der Erkennung der gesprochenen Sätze, und lässt sich ohne iPhone nicht klären. Gefunden und behoben wurde nur, was am Build prüfbar war: Der Satzbestand war groß, teils überlappend und teils so allgemein, dass Siri ihn als normale Anfrage deuten kann (Hypothese, siehe unten). Er wurde deshalb auf 15 Sätze verkleinert.

#### Belege (Gerätebuild ohne Signierung, eigener DerivedData-Ordner `DerivedData-siri-check`)

Befehl (nach `xcodegen`, wie `scripts/install-dev.sh`, aber ohne Installation):
`xcodebuild -project app/Tagwerk.xcodeproj -scheme Tagwerk -destination 'generic/platform=iOS' -derivedDataPath "$HOME/Library/Developer/Tagwerk/DerivedData-siri-check" CODE_SIGNING_ALLOWED=NO build` → `BUILD SUCCEEDED`.

| Frage aus dem Plan | Befund | Fundstelle |
|---|---|---|
| Gibt es `Metadata.appintents/` mit `extract.actionsdata`? | Ja. `extract.actionsdata`, `root.ssu.yaml`, `version.json` (toolsVersion 27B52). | `Tagwerk.app/Metadata.appintents/` |
| Alle 8 Kurzbefehle mit Sätzen enthalten? | Ja. `autoShortcuts` hat 8 Einträge (`LogWaterIntent`, `LogMealIntent`, `LogWorkoutIntent`, `TodayOverviewIntent`, `AddToShoppingListIntent`, `AddShoppingArticleIntent`, `CheckHabitIntent`, `OpenShoppingListIntent`); Satzvorlagen im Original-Stand 23 (der Plan nennt 24, das war ein Zählfehler), nach der Bereinigung 15. Dazu 2 Entities, 2 Queries, 1 Enum, `autoShortcutProviderMangledName` gesetzt. | `extract.actionsdata` |
| Sätze lokalisiert (de und en)? | Ja. `root.ssu.yaml` enthält je Kurzbefehl einen Trainingskorpus für `locale: de` und `locale: en` (`{${+prefix} }Wasser in ${+applicationName} erfassen` …); Parameter heißen `${ShoppingArticleEntity}`, `${HabitEntity}`, `${WorkoutActivityOption}`; `+applicationName` = „Tagwerk“ in beiden Sprachen. `de.lproj/nlu.appintents` und `en.lproj/nlu.appintents` (NLU-Modelle) sind vorhanden. `en.lproj/AppShortcuts.strings` enthält alle englischen Sätze. Eine `de.lproj/AppShortcuts.strings` gibt es nicht; das ist erwartbar, weil die deutschen Sätze die Schlüssel (Quellsprache) sind und aus dem Code in den Korpus gehen. | `Tagwerk.app/Metadata.appintents/root.ssu.yaml`, `*.lproj/` |
| Ist `AppShortcuts.xcstrings` Ressource des App-Targets? | Ja: `sources: [Tagwerk]` in `app/project.yml` nimmt jede Datei unter `app/Tagwerk/` auf; im Build läuft `CompileXCStrings` für das Target und erzeugt `en.lproj/AppShortcuts.strings`. | Build-Log |
| Warnungen von `appintentsmetadataprocessor`? | Keine. Für das Target `Tagwerk` steht im Log nur `Starting App Intents metadata extraction` und `Writing Metadata.appintents`. Die Pakete und das Widget melden „Extracted no relevant App Intents symbols“ (erwartet: dort gibt es keine Intents). Es gibt keine Warnung zu Sätzen, Übersetzungen oder Parametern. Die übrigen Compiler-Warnungen im Log betreffen Voice-Code und `DayPanelText`, nicht Siri. | `xcodebuild`-Log |
| Info.plist | Kein Siri-Eintrag nötig und keiner vorhanden. `CFBundleDevelopmentRegion` = `de`. | `Tagwerk.app/Info.plist` |

Der Simulator-Build (`generic/platform=iOS Simulator` über `app/test-all.sh` und `scripts/sync-strings.sh`, eigener Simulator je Checkout) läuft mit demselben Quellstand; ein Unterschied bei den App-Intents-Metadaten ist nicht zu erwarten, wurde aber nicht einzeln verglichen.

### Prüfung gegen Apples Dokumentation

Geprüft am 2026-11-19 über Apples Dokumentationsdaten (`developer.apple.com/tutorials/data/documentation/...`) und die Entwicklerforen:

1. **App Shortcuts, Human Interface Guidelines** (`developer.apple.com/design/human-interface-guidelines/app-shortcuts`): höchstens 10 App Shortcuts je App (Tagwerk: 8); „Provide brief, memorable activation phrases and natural variants“, der App-Name muss enthalten sein; „Keep voice interactions simple“; höchstens ein Parameter je Satz; Siri soll bei fehlenden optionalen Angaben nachfragen; Tipps in der App zeigen, damit Nutzer die Sätze kennen (`SiriTipUIView`); als Prüfwerkzeug nennt die Seite nichts, Apple-DTS verweist darauf in den Foren (Punkt 5). Das Beispiel Keynote nennt zwei Sätze für eine Aktion. Daraus folgt: **höchstens zwei Sätze je Kurzbefehl, kurz, ohne Überlappung**. Wie viele Sätze Siri tatsächlich noch sauber unterscheidet, nennt Apple nicht.
2. **`ShortcutsLink`** (`documentation/appintents/shortcutslink`, iOS 16+): „A button that brings users to the current app’s App Shortcuts page in the Shortcuts app.“ Eingebaut.
3. **`SiriTipView`** (`documentation/appintents/siritipview`, iOS 16+): zeigt den gesprochenen Satz für einen Intent; „you must use the AppIntent in an AppShortcut. Otherwise this will display an empty view.“ Das macht ihn zur Prüfhilfe: Bleibt die Zeile leer, kennt das System den Kurzbefehl nicht (am Gerät zu bestätigen). Eingebaut mit `LogWaterIntent`.
4. **`INAlternativeAppNames`** (`documentation/sirikit/specifying-synonyms-for-your-app-name`): Der Schlüssel gehört zu SiriKit. Apple schreibt: „Siri recognizes alternative app names only for apps that include an Intents app extension with support for one or more intents.“ Höchstens drei Einträge je Lokalisierung, optional ein „sounds like“-Hinweis, Namen müssen vom App-Namen abgeleitet oder gebräuchlich sein. Tagwerk hat **keine Intents-Extension** (App Intents liegen im App-Target, die einzige Extension ist das Widget). Außerdem nennt die Doku zu `AppShortcutsProvider`, `AppShortcut`, `AppShortcutPhrase` und zu den App Shortcuts keinen Bezug zu diesem Schlüssel.
5. **Foren (Apple-DTS, Hinweise statt Spezifikation):** Thread 804784 („Siri AppIntent phrasing“): Ein zu langer Satz mit Parameter wurde nicht erkannt, Siri fragte stattdessen, ob ChatGPT antworten soll (also derselbe Fehlerweg wie bei Tagwerk, Websuche statt Kurzbefehl); DTS rät, `AppShortcuts.xcstrings` anzulegen (haben wir) und die Sätze mit **Product › App Shortcuts Preview** in Xcode zu prüfen; weicht das Gerät davon ab, soll man einen Bugreport mit Sysdiagnose einreichen. Thread 838210: Ein App-Name mit Akzent wurde in Sätzen nicht erkannt, DTS vermutet eine Schwäche bei der Normalisierung; „Tagwerk“ hat keine Sonderzeichen. Beide Threads sind Einzelfälle ohne bestätigte Ursache.

**Ergebnis zu Plan-Schritt 4 (App-Name):** Für App Shortcuts ist `INAlternativeAppNames` nicht dokumentiert, und für SiriKit gilt es laut Apple nur mit Intents-Extension. Zusätzlich ein Build-Versuch: Mit `INAlternativeAppNames` (zuerst als Klartext „Tag Werk“, dann lokalisiert über `InfoPlist.xcstrings`, jeweils nach sauberem Neubau mit gelaufenem `appintentsmetadataprocessor`) steht der Schlüssel in der `Info.plist`, aber `+applicationName` in `root.ssu.yaml` bleibt unverändert „Tagwerk“. Der Metadatenprozessor übernimmt die Synonyme also nicht. Ob Siri zur Laufzeit den Schlüssel dennoch liest, ist nur am Gerät feststellbar. **Entscheidung: nicht eingebaut**, weil Apple ihn für diese App-Form ausschließt und der Build ihn nicht aufnimmt; ein wirkungsloser Schlüssel würde nur eine Scheinsicherheit erzeugen. Er bleibt als gezielter Gerätetest in der Checkliste (Schritt 8).

### Was geändert wurde

1. **Sätze bereinigt** (`app/Tagwerk/Intents/TagwerkIntents.swift`, `app/Tagwerk/AppShortcuts.xcstrings`): von 23 auf 15 Sätze. Entfernt wurden:
   - „Wasser mit Tagwerk erfassen“ (unnatürliche Präposition, Dublette zu „in“),
   - „Einkaufsliste in Tagwerk“ (Präfix von „Einkaufsliste in Tagwerk zeigen“, derselbe Wortlaut führt zu zwei Kurzbefehlen),
   - „Einkaufsliste in Tagwerk ergänzen“ (Paraphrase von „Zur Einkaufsliste in Tagwerk hinzufügen“),
   - „Füge etwas zur Einkaufsliste in Tagwerk hinzu“ (fast gleich „Füge ${Artikel} zur Einkaufsliste in Tagwerk hinzu“, nur mit „etwas“ statt Artikel),
   - „Ich brauche etwas aus dem Laden in Tagwerk“, „Neuer Artikel in Tagwerk“, „Etwas auf die Einkaufsliste in Tagwerk setzen“ (allgemeine oder lange Formulierungen, die Siri eher als normale Anfrage deutet; Hypothese, nicht belegt),
   - „Setz ${Artikel} auf die Einkaufsliste in Tagwerk“ (dritte Variante mit Artikel).

   Bestand je Kurzbefehl (jeweils begründet mit „höchstens zwei Varianten“ aus der HIG, kurz und ohne Überlappung): Wasser 2 („Wasser in …“, „Trinken in …“), Mahlzeit 2 („Mahlzeit in …“, „Essen in …“), Training 2 („Training in …“, „${Aktivität} in …“), Heute 2, Einkaufsliste ohne Artikel 2 („Auf die Einkaufsliste in …“, „Zur Einkaufsliste in … hinzufügen“), Artikel 2 („Füge ${Artikel} zur Einkaufsliste in … hinzu“, „${Artikel} auf die Einkaufsliste in …“), Gewohnheit 2, Einkaufsliste zeigen 1. Zusammen 15. Ob die kleinere Menge die Erkennung verbessert, belegt nichts; es ist eine begründete Verkleinerung des Risikos, keine Behebung einer nachgewiesenen Ursache.
2. **Prüfung der Sätze** (`scripts/check-strings.py`, läuft in `app/test-all.sh` als Stufe „string catalogs“): Sätze aus `TagwerkIntents.swift` und Katalogschlüssel müssen sich in beide Richtungen decken (fehlender oder verwaister Schlüssel, doppelter Satz), und jeder in „Siri & Kurzbefehle“ angezeigte Satz muss ein echter Satz sein (Parameter als Platzhalter, „Tagwerk“ für den App-Namen). Das bestehende Prüfen, dass jeder Satz `${applicationName}` enthält und `en` übersetzt ist, blieb. Die Prüfung wurde mit je einer absichtlichen Abweichung in Code und Einstellungsliste rot gesehen (Exit 1) und danach grün.
3. **Einstellungen › Erfassen › „Siri & Kurzbefehle“** (`CaptureSettingsView.swift`): `SiriTipView` für „Wasser erfassen“ (oben, schließbar) und `ShortcutsLink()` (unter der Satzliste); Fußtext um den Hinweis ergänzt, bei Nichterkennung in der App „Kurzbefehle“ zu prüfen und den Satz über „Tippen für Siri“ zu probieren (Katalog und `scripts/translations/en.json` nachgezogen). Die angezeigte Satzliste war schon synchron zu den bleibenden Sätzen.
4. **Test** (`AppShortcutsTests`): der Provider liefert 8 Kurzbefehle, höchstens 10. Mehr ist mit Swift Testing nicht sinnvoll, weil `AppShortcut` seine Sätze nicht herausgibt; die Sätze prüft Punkt 2.

### Testergebnis

`app/test-all.sh` nach dem letzten Code-Commit (`0a9f306`), alle Stufen grün einschließlich „string catalogs“ (`check-strings.py --require-english` samt neuem Satz-Abgleich, `sync-strings.sh --check`): AIKit 98, GitHubKit 139, HealthBridge 11, RemindersKit 87, TagwerkCore 646, App 1160 Tests bestanden. Letzte Zeile: `ALL TESTS PASSED`. Der Merge von `origin/main` war ohne Änderung („Already up to date“). Der temporäre Ordner `DerivedData-siri-check` ist gelöscht.

### Abweichungen vom Plan

- **Plan nennt 24 Sätze, es waren 23** (Zählfehler im Plan). Im Bestand oben vermerkt.
- **Kein `INAlternativeAppNames`** (Schritt 4), mit Begründung und Build-Versuch oben. Gerätetest bleibt offen.
- **Schritt 7:** Der Test der Satzliste liegt im Python-Skript, nicht in Swift. Das Skript prüfte nur den App-Namen und die englische Übersetzung, nicht den Abgleich von Code und Katalog; dieser fehlte und der Katalog wird von Hand gepflegt (`sync-strings.sh` fasst ihn nicht an). Ein Abgleich gegen `extract.actionsdata` des Builds wäre genauer, bräuchte aber einen Build in der Prüfstufe; der Quelltext-Abgleich genügt, weil der Prozessor Katalog und Code ohnehin zusammenführt (belegt im Build, siehe oben).
- **`SiriTipView` ist eingebaut** (im Plan „optional“): Er ist die einzige Stelle, an der die App selbst anzeigt, ob das System den Kurzbefehl kennt.
- **Der Simulator-Build** lief nur über `test-all.sh`/`sync-strings.sh`; die Metadaten daraus wurden nicht einzeln ausgewertet.

### Hypothesen, die sich ohne Gerät nicht prüfen lassen

- **Systemeigene Einkaufslistenbefehle:** „Füge Milch zur Einkaufsliste hinzu“ ist ein vollständiger Befehl der Erinnerungen-App. Möglicherweise setzt sich Siris eigene Auswertung bei den Einkaufssätzen gegen „… in Tagwerk“ durch. Dagegen spricht, dass der App-Name Pflichtbestandteil jedes Satzes ist; belegt ist nichts.
- **Erkennung des Wortes „Tagwerk“** beim Sprechen (ein oder zwei Wörter, andere Schreibweise). Apple nennt dafür keinen Mechanismus für App Shortcuts.
- **Reaktion auf zu viele oder zu ähnliche Sätze:** der Forenfall (804784) spricht dafür, dass lange Sätze mit Parameter in die allgemeine Anfrage (ChatGPT) fallen.
- **Zeitverzögerung** bis das System neu installierte App Shortcuts kennt.

### Checkliste für den Gerätetest (Melvin)

Reihenfolge so gewählt, dass jeder Schritt eine Ursache ausschließt. Notiere, bei welchem Schritt es bricht.

0. Neuinstallation mit `scripts/install-dev.sh`, App einmal öffnen, 1–2 Minuten warten.
1. **Registrierung:** In der App „Kurzbefehle“ oben „Tagwerk“ suchen (oder im Tab „Kurzbefehle“ nach Apps); alle Tagwerk-Kurzbefehle sichtbar? Tippen führt sie aus? Auch Spotlight: „Tagwerk“ suchen, erscheinen unter der App Schnellaktionen? Ja heißt: Registrierung und Metadaten sind in Ordnung.
2. **In Tagwerk:** Einstellungen › Erfassen › „Siri & Kurzbefehle“: Zeigt die Siri-Tipp-Zeile den Satz „Wasser in Tagwerk erfassen“ (bleibt sie leer, kennt das System den Kurzbefehl nicht)? Öffnet „Kurzbefehle“ den Tagwerk-Bereich?
3. **Getippter Satz:** iOS-Einstellungen › Bedienungshilfen › Siri › „Tippen für Siri“ einschalten, Siri rufen, **„Wasser in Tagwerk erfassen“ tippen**, danach **„Auf die Einkaufsliste in Tagwerk“** tippen. Das umgeht die Spracherkennung des App-Namens. Klappt getippt, aber nicht gesprochen, liegt es an der Erkennung von „Tagwerk“ beim Sprechen.
4. **Gesprochen, Sätze aus Phase 4** („Wasser in Tagwerk erfassen“, „Mahlzeit in Tagwerk erfassen“, „Training in Tagwerk erfassen“, „Was steht heute in Tagwerk an“, „Gewohnheit in Tagwerk abhaken“), dann die Einkaufssätze („Auf die Einkaufsliste in Tagwerk“, „Füge Milch zur Einkaufsliste in Tagwerk hinzu“, „Einkaufsliste in Tagwerk zeigen“). Funktionieren nur die Phase-4-Sätze, betrifft es die Einkaufssätze (Hypothese Systembefehl) und nicht den App-Namen.
5. **Siri-Einstellungen:** Einstellungen › Siri (bzw. „Apple Intelligence & Siri“) › Apps › Tagwerk: „Von dieser App lernen“ und „Bei Siri verwenden“ (Name je nach iOS-Version) aktiv?
6. **Sprache:** Siri-Sprache und iPhone-Sprache beide Deutsch? Auf Englisch prüfen („Log water in Tagwerk“), ob es dort geht.
7. **Neustart** des iPhones, dann Schritt 3 und 4 wiederholen.
8. **Nur wenn getippt klappt und gesprochen nicht:** In `app/project.yml` unter `info.properties` testweise `INAlternativeAppNames` mit einem Eintrag ergänzen, z. B. `[{INAlternativeAppName: Tag Werk}]`, neu installieren und erneut sprechen. Apple schließt den Schlüssel für Apps ohne Intents-Extension aus; ein Erfolg wäre also überraschend und sollte gemeldet werden.
9. **Auf dem Mac:** Xcode öffnen, Scheme „Tagwerk“, **Product › App Shortcuts Preview**: Werden die 15 Sätze angezeigt, und finden getippte Varianten den richtigen Kurzbefehl? Das ist das von Apple-DTS empfohlene Prüfwerkzeug und prüft die Satzzuordnung ohne Sprache. Nicht Teil dieses Auftrags, weil es Xcode am Bildschirm braucht.

Auswertung: Schritt 1 schlägt fehl → Registrierung (dann Build, Signierung oder Siri-Einstellung prüfen). 1 ok, 3 getippt geht, 4 gesprochen nicht → Spracherkennung des App-Namens. 3 getippt geht nicht, 9 geht → Siri-Konfiguration oder System; 3 und 9 gehen nicht → Satz oder Vorlage, dann Sysdiagnose und Bugreport laut DTS. Nur die Einkaufssätze fallen aus → Konflikt mit dem systemeigenen Einkaufslistenbefehl.

### Für das Design-Sammelissue

- Platzierung und Aussehen von `ShortcutsLink` (jetzt letzte Zeile der Satzliste) und `SiriTipView` (jetzt erste Zeile, ohne Zeilenhintergrund, schließbar; er verschwindet nach Schließen bis zum nächsten Öffnen der Seite).
