# Tagwerk – Phase 5 Design: Einkaufsliste und Notizen einbinden

Stand: 2026-11-19 · Status: **vom Nutzer am 2026-11-19 freigegeben**.

Baut auf:
- `2026-11-17-tagwerk-design.md`: §2 Anti-Ziele, §4 Rahmenbedingungen (kein CloudKit), §5 Phase 5, §6 „EventKit als Quelle der Wahrheit“, §7 Datenschutz.
- `2026-11-17-phase-2b-design.md`: §8.3 und §11.11 (Assistent: Lesen sofort, Schreiben nur nach Bestätigung).
- `2026-11-18-phase-3-design.md`: §6 (Einwilligung vor dem Schätzen, Muster `MealConsentSheet`).
- `2026-11-18-phase-4-design.md`: §5.5 (Deeplinks navigieren nur), §8 (App Intents, `IntentServices`).

Mockup: `../mockups/2026-11-19-phase-5-shopping-notes-mockups.html` (EO1–EO3, EO2b, EQ1–EQ3, EG1–EG3, NQ1–NQ3, EA1–EA3, ES1–ES3). Epic: GitHub #113.

Kennzeichnung in diesem Dokument: **[Code]** = im Quelltext dieses Standes nachgelesen, **[SDK]** = laut Mockup-Befund in den EventKit-Headern geprüft (hier nicht erneut geprüft), **[Annahme]** = nicht geprüft, **[Nutzer]** = Entscheidung vom 2026-11-19, **[Festlegung]** = meine Festlegung als Verfasser, siehe §9.

## 1. Absicht und Warum

Die Einkaufsliste liegt heute als gewöhnliche Liste in Apple Erinnerungen. Tagwerk liest sie wie jede andere Liste: Jeder Artikel steht unter „Aufgaben · Ohne Datum“ und im Aufgabenvorrat der Planung **[Code: `RemindersTaskProvider.swift:25–29`, `AppEnvironment.swift:75–77`]**. Das stört die Planung und macht die Liste im Laden unbrauchbar.

Phase 5 löst beides:
- Die **Einkaufsliste** bekommt eine eigene Seite: ansehen, abhaken, ergänzen, nach Kategorien geordnet, auch per Diktat, Siri und Assistent. Sie fällt dafür aus Aufgaben, Planung, Wochenrückblick und Mitteilungen heraus.
- **Notizen** bekommen einen eigenen, lokalen Speicher. Ihn nutzt später auch die Gedanken-Notiz aus Phase 7 (#143).

Quelle der Wahrheit für Artikel bleibt Apple Erinnerungen. Tagwerk speichert nur, was EventKit nicht kennt: Kategorien und die Zuordnung Artikelname → Kategorie.

## 2. Ziele, Nicht-Ziele, Anti-Ziele

**Ziele**
- Eine gewählte Erinnerungsliste ist „die Einkaufsliste“. Vorschlag am Listennamen, einmal bestätigen; änderbar in den Einstellungen.
- Diese Liste erscheint nicht mehr in: Aufgaben, Planung (auch nicht in der Erkennung wiederkehrender Erinnerungen), Wochenrückblick, Listenauswahl für neue Aufgaben, Tagwerk-Mitteilungen, Aufgabenvorrat des Assistenten.
- Einstieg über zwei Karten oben in „Aufgaben“ (Einkaufsliste, Notizen); beide öffnen eine eigene Seite.
- Einkaufsseite: Abschnitte nach eigenen Kategorien, Abhaken, Wiederöffnen, Menge, Eingabezeile mit Diktat.
- Automatische Zuordnung über ein mitgeliefertes Wörterbuch (offline). Zusätzlich ein Knopf „Mit ChatGPT sortieren“, der Vorschläge zur Bestätigung liefert.
- Kategorien verwalten: anlegen, umbenennen, umsortieren, löschen; Artikel von Hand in eine andere Kategorie legen.
- Lokaler Notizspeicher `NoteRecord` mit Liste, Schnellerfassung und Editor.
- Assistent: Einkaufsliste lesen, Artikel hinzufügen und abhaken über eine Sammelkarte.
- Siri-Kurzbefehl „Auf die Einkaufsliste“ und Deeplink `tagwerk://shopping`.
- Englische Texte.

**Nicht-Ziele (Phase 5)**
- Widget für die Einkaufsliste (ES3, zurückgestellt **[Nutzer]**).
- Fünfter Tab (Querschnittsentscheidung: Tab-Leiste bleibt Planen, Aufgaben, Erfassen, Einstellungen).
- Apples Abschnitte lesen oder schreiben. EventKit legt sie nicht offen **[SDK]**.
- Mehrere Einkaufslisten, Läden mit eigener Reihenfolge, Preise, Rezepte, Vorratshaltung.
- Fälligkeit, Priorität, Aufwand oder Wiederholung an Artikeln anzeigen oder bearbeiten.
- Eintrag in „Planen“ („Einkaufen: 7 Artikel“).
- Notiz-Funktionen für den Assistenten; Notizen an ChatGPT senden (kommt frühestens mit #143 und eigener Zustimmung).
- iCloud-Abgleich der Notizen; Zugriff auf Apple Notizen; Anhänge, Formatierung, Ordner oder Tags in Notizen.
- Abgleich der Kategorien zwischen Geräten oder zurück nach Erinnerungen.

**Anti-Ziele**
- Tagwerk wird zur zweiten Quelle für Artikel (Hauptdesign §2). Deshalb gibt es keine lokale Kopie der Artikel; lokal liegen nur Kategorien und Zuordnungen.
- Artikelnamen oder Notiztext verlassen das Gerät ohne bewusste Aktion. ChatGPT bekommt Artikelnamen nur auf Tippen (Sortieren) oder wenn der Nutzer den Assistenten nach der Liste fragt; Notiztext in Phase 5 nie.
- Einkaufsartikel tauchen an irgendeiner Stelle wieder als Aufgabe auf (Planung, Mitteilung, Rückblick, Assistent).
- Der Assistent hakt über die Einkaufsfunktion Erinnerungen ab, die nicht in der Einkaufsliste stehen.
- Abhaken löscht. Ein versehentlich abgehakter Artikel muss sich wieder öffnen lassen.
- Datenverlust durch Schema-Änderung: Es kommen nur neue Modelle und Felder mit Standardwert hinzu; der Store bleibt an seinem Ort (Phase 4 §12).

## 3. Einschränkungen

| Nr. | Einschränkung | Beleg | Folge |
|---|---|---|---|
| E1 | `EKCalendar` hat keinen Listentyp; `EKReminder` hat keine Abschnitte, Unteraufgaben oder Tags | **[SDK]** (iPhoneOS 27.2, laut Mockup) | Einkaufsliste nur am Namen zu raten; Kategorien liegen in Tagwerk |
| E2 | Gelesen werden nur offene Erinnerungen; erledigte kennt Tagwerk nur als Datum | **[Code: `EventKitGateway.swift:65–78`, `:80–96`]** | Neue Lesefunktion für erledigte Artikel nötig |
| E3 | `ReminderRecord` trägt kein Anlage- und kein Erledigungsdatum | **[Code: `ReminderRecord.swift:5–30`]** | Zwei neue Felder für Reihenfolge und „letzte 7 Tage“ |
| E4 | Die Planung liest alle Listen, um wiederkehrende Erinnerungen zu erkennen | **[Code: `PlanningModel.swift:232–233`, `:302–303`, `:1597–1603`]** | Dort gesondert ausschließen; die Listenwahl greift an dieser Stelle nicht |
| E5 | `containers()` liefert alle Listen ungefiltert; neue Erinnerungen ohne Liste gehen in Apples Standardliste | **[Code: `RemindersTaskProvider.swift:36–39`, `EventKitGateway.swift:141`]** | Einkaufsliste aus der Auswahl nehmen; Rückfall, falls sie Apples Standardliste ist |
| E6 | Einstellungen sind ein SwiftData-Objekt; neue Felder brauchen Standardwert oder Optional | **[Code: `AppSettings.swift:5–8`]** | Alle neuen Felder mit Standardwert |
| E7 | Ein Store, kein iCloud; `LocalTask.id` ist `@Attribute(.unique)` | **[Code: `ModelContainerFactory.swift:5–22`, `LocalTask.swift:9`]**; CloudKit mit kostenlosem Account nicht verfügbar (Hauptdesign §4) | Notizen bleiben lokal; `NoteRecord` ohne eindeutiges Feld |
| E8 | Schreibende Assistenten-Funktionen laufen erst nach „Bestätigen“ | **[Code: `AppTools.swift:8–13`, `:33`, `ChatView.swift:266–286`]** | EA2 bleibt bei dieser Regel |
| E9 | Für den Chat gibt es keine eigene Einwilligung; die Anmeldung bei ChatGPT genügt. Für Mahlzeiten gibt es eine einmalige Einwilligung mit Schalter | **[Code: `Settings/AISettingsView.swift:214–226`, `MealConsentSheet.swift`, `MealSheet.swift:71–72, 413`, `CaptureSettingsView.swift:31`]** | „Mit ChatGPT sortieren“ folgt dem Mahlzeiten-Muster |
| E10 | Bei einem Hintergrundstart durch einen Intent läuft `RootView.task` nicht | Phase 4 §8 | Der Kurzbefehl darf nur Gateway, Einstellungen und Kategorien brauchen |
| E11 | Apple Notizen hat keine dokumentierte Schnittstelle für andere Apps | **[Annahme]** aus Websuche im Mockup, nicht aus Apple-Dokumentation | Eigener Speicher (NQ1) |

Nicht geprüft und deshalb im Spike (§10): Verhalten geteilter Listen, EventKit-Schreiben aus dem Hintergrund-Intent, automatische Einsortierung in Apples Liste.

## 4. Ansätze

Sechs Entscheidungen, je mit den Varianten des Mockups. Empfehlung = Empfehlung des Mockups.

| Nr. | Frage | Varianten und Abwägung | Entscheidung |
|---|---|---|---|
| EO | Ort in der App | **EO1** eigener Tab: ein Tipp, aber fünfter Tab, konkurriert mit Suche und Routinen. **EO2** Karten oben in „Aufgaben“: keine Änderung an der Tab-Leiste, zwei Tipps, mischt Notizen unter Aufgaben. **EO3** in „Erfassen“: der Tab ist an einen Tag gebunden, eine Einkaufsliste hat keinen Tag | **EO2 [Nutzer]**, wie empfohlen |
| EQ | Welche Liste, wie fällt sie heraus | **EQ1** Vorschlag am Namen, einmal bestätigen, Rückfallweg in den Einstellungen. **EQ2** nur Einstellungen: am wenigsten Code, aber bis dahin stehen Artikel zwischen den Aufgaben. **EQ3** eigene Liste anlegen: eindeutig, aber zweite Liste neben der bestehenden, Siri trifft weiter die alte | **EQ1 [Nutzer]**, wie empfohlen; die Zeile aus EQ2 gehört dazu |
| EG | Abschnitte | **EG1** flach: kleinster Umfang, im Laden unpraktisch. **EG2** eigene Kategorien mit Wörterbuch: offline, vorhersehbar, Einteilung lebt nur in Tagwerk. **EG3** ChatGPT sortiert: kennt Ungewöhnliches, braucht Netz und Anmeldung, Namen verlassen das Gerät | **EG2 mit Zusätzen [Nutzer]**, siehe unten |
| NQ | Quelle der Notizen | **NQ1** eigener Speicher: sofort, offline, kein Abgleich. **NQ2** Kurzbefehl-Brücke zu Apple Notizen: Einrichtung von Hand, ungeprüft. **NQ3** Erinnerungsliste: iCloud geschenkt, aber zweckfremd und nicht lokal | **NQ1 [Nutzer]**, wie empfohlen, gemeinsam mit Phase 7 |
| EA | Rechte des Assistenten | **EA1** nur lesen: verfehlt „ergänzen per Assistent“. **EA2** lesen, hinzufügen, abhaken mit einer Sammelkarte. **EA3** ohne Bestätigung mit „Widerrufen“: erste Ausnahme von der Schreibregel | **EA2 [Nutzer]**, wie empfohlen |
| ES | Schnelles Hinzufügen | **ES1** Eingabezeile mit Diktat plus Kurzbefehl. **ES3** zusätzlich Widget: rund 5 h mehr, doppelt zum Widget von Erinnerungen | **ES1 [Nutzer]**, wie empfohlen |

**Abweichung von der Empfehlung (EG).** Das Mockup empfahl EG2 allein und stellte EG3 „höchstens später“ in Aussicht. Der Nutzer hat EG2 gewählt und zwei Dinge ergänzt (Wortlaut: „EG2 mit einem Button, um zusätzlich von ChatGPT sortieren zu lassen; dabei muss auch die Möglichkeit offen sein, Kategorien anzulegen/zu verändern/zu löschen“):
1. ein Knopf „Mit ChatGPT sortieren“, also EG3 als Zusatz auf Tippen statt als Grundlage;
2. vollständige Verwaltung der Kategorien.

Folge für die Abwägung: Die Nachteile von EG3 (Netz, Wartezeit, Namen verlassen das Gerät) treffen nur noch den, der den Knopf drückt. Die Liste bleibt ohne Netz vollständig benutzbar. Dafür wächst der Umfang um Einwilligung, Ergebnisblatt und Kategorienverwaltung (§11, Pakete 4 und 8, zusammen etwa 12 h).

Der Halbsatz „dabei … Kategorien anzulegen/zu verändern/zu löschen“ lässt zwei Lesarten zu: (a) der Nutzer verwaltet Kategorien selbst, (b) auch ChatGPT darf beim Sortieren Kategorien vorschlagen. Das Dokument setzt (a) vollständig um und von (b) nur das Anlegen: ChatGPT darf neue Kategorien **vorschlagen**, der Nutzer bestätigt sie. Umbenennen und Löschen durch ChatGPT gibt es nicht (§9 Nr. 9).

## 5. Design im Detail

### 5.1 Datenmodell

**Neue Felder in `AppSettings`** (alle mit Standardwert, E6)

| Feld | Standard | Bedeutung |
|---|---|---|
| `shoppingListID: String?` | `nil` | Kennung der Erinnerungsliste, die als Einkaufsliste dient; `nil` = keine |
| `shoppingSuggestionDismissed: Bool` | `false` | Die Vorschlagskarte EQ1 wurde mit „Nicht jetzt“ beantwortet |
| `shoppingCategoriesSeeded: Bool` | `false` | Die Standardkategorien wurden einmal angelegt (verhindert erneutes Anlegen nach dem Löschen) |
| `shoppingSortConsent: Bool` | `false` | Einmalige Einwilligung für „Mit ChatGPT sortieren“; der Schalter in den Einstellungen bindet daran |

`selectedReminderListIDs` bleibt unverändert. Die Einkaufsliste wird beim Lesen abgezogen, nicht aus der Auswahl gelöscht. Stellt der Nutzer die Einkaufsliste auf „Keine“, erscheint die Liste wieder unter den Aufgaben, sofern sie dort gewählt war.

**Neue SwiftData-Modelle** (in `ModelContainerFactory.schema`, alle Attribute mit Standardwert, kein `@Attribute(.unique)`, keine Beziehungen)

```
ShoppingCategory {
  id: UUID = UUID()
  name: String = ""
  sortIndex: Int = 0
  builtinKey: String? = nil      // z. B. "produce"; nil bei eigenen Kategorien
  createdAt: Date = .now
}

ShoppingAssignment {             // gelernte Zuordnung Artikelname → Kategorie
  nameKey: String = ""           // normalisierter Artikelname, siehe Regel R2
  categoryID: UUID? = nil
  sourceRaw: String = "manual"   // "manual" | "ai"
  updatedAt: Date = .now
}

NoteRecord {
  id: UUID = UUID()
  text: String = ""
  createdAt: Date = .now
  updatedAt: Date = .now
  kindRaw: String = "free"       // "free" | "morning" | "evening"
  dayKey: String? = nil          // "YYYY-MM-DD", nur bei morning/evening
  isPinned: Bool = false
  wasDictated: Bool = false
  processedAt: Date? = nil       // Phase 7: wann aus der Notiz Vorschläge wurden
}
```

- Eindeutigkeit von `ShoppingAssignment.nameKey` und `NoteRecord.id` sichert der Code (vor dem Einfügen suchen), nicht das Schema.
- `NoteRecord` hat keinen eigenen Titel. Titel = erste Zeile des Textes, höchstens 60 Zeichen; der Rest ist die Vorschau.
- `kindRaw` ist das „Herkunft/Art“-Feld für Phase 7: `free` = eigene Notiz (Phase 5), `morning` = Tagesstart, `evening` = Tagesabschluss. Phase 5 schreibt nur `free`, **zeigt aber alle Arten**.
- Artikel werden **nicht** gespeichert. Es gibt kein Modell für sie.

**Erweiterungen in `RemindersKit`**

| Ort | Änderung |
|---|---|
| `ReminderRecord` | neue Felder `createdAt: Date?` (aus `EKCalendarItem.creationDate`) und `completedAt: Date?` (aus `EKReminder.completionDate`), im `init` mit Standard `nil` |
| `ListInfo` | neues Feld `isWritable: Bool` (aus `allowsContentModifications`), im `init` mit Standard `true` |
| `ReminderStore` | neue Funktion `completedReminders(in: DateInterval, listIDs: Set<String>) async -> [ReminderRecord]`; Standard-Implementierung im Protokoll liefert `[]`, `FakeReminderStore` bekommt eine echte |
| `RemindersTaskProvider` | neuer Parameter `excludedListID: @MainActor () -> String?`; wirkt in `openTasks()`, `containers()` und `create(_:)` |
| neu: `ShoppingListFilter` (reine Logik) | `taskListIDs(selected: Set<String>?, all: [String], shopping: String?) -> Set<String>?`: ohne Einkaufsliste unverändert; sonst `(selected ?? all)` ohne die Einkaufsliste. Eine leere Menge heißt „keine Liste“, nicht „alle“ (`openReminders` liefert dann `[]`, **[Code: `EventKitGateway.swift:69`]**) |

**Reiner Typ für die Oberfläche** (`TagwerkCore`)

```
ShoppingItem {
  id: String            // Kennung der Erinnerung
  name: String          // Titel der Erinnerung
  quantity: String?     // erste Zeile des Notizfelds
  isCompleted: Bool
  completedAt: Date?
  createdAt: Date?
  hasLongNotes: Bool    // Notizfeld hat mehr als eine Zeile
}
```

**`ShoppingModel`** (App, `@Observable`, eine Instanz in `AppEnvironment`) ist die einzige Stelle, die Artikel liest und schreibt. Seite, Karte in „Aufgaben“, Assistent, Kurzbefehl und später die Suche nutzen sie.
- Offene Artikel: `openReminders(in: [shoppingListID])`; erledigte: `completedReminders(in:listIDs:)` für die letzten 7 Tage.
- Geladen wird beim Start nach der Einrichtung, zusammen mit jedem Neuladen der Aufgaben und bei Meldungen aus `EventKitGateway.changes`. So stimmt der Zähler der Karte, ohne dass die Seite offen war.
- Geschrieben wird über `ReminderStore.create`, `save` und `delete`, nicht über `TaskListModel`.

### 5.2 Regeln (reine Logik, testbar ohne EventKit)

**R1 Ausschluss.** Ist `shoppingListID` gesetzt, wird diese Liste an sechs Stellen abgezogen:

| Stelle | Heute | Änderung |
|---|---|---|
| Aufgaben | `AppEnvironment.swift:75–77` | Listenmenge über `ShoppingListFilter` |
| Wochenrückblick, erledigte Erinnerungen | `AppEnvironment.swift:343` | dieselbe Listenmenge |
| Planung, wiederkehrende Erinnerungen | `PlanningModel.swift:232`, `:302` | Ergebnis von `openReminders(in: nil)` um Einträge mit `listID == shoppingListID` kürzen |
| Listenauswahl neue Aufgabe und Editor | `RemindersTaskProvider.swift:36–39` | `containers()` ohne die Einkaufsliste |
| Neue Erinnerung ohne Liste | `EventKitGateway.swift:141` | Ist Apples Standardliste die Einkaufsliste, nimmt `create(_:)` die erste gewählte andere Liste (nach Titel sortiert); gibt es keine, Fehler „Keine Erinnerungsliste gefunden“ |
| Einstellungen › Erinnerungslisten | `SettingsView.swift:42–49`, `SourceSelectionView.swift` | Zeile grau, nicht wählbar, Vermerk „Einkaufsliste“; die Zählung „3 von 3“ rechnet ohne sie |

Mitteilungen, Widget-Snapshot, Abendplanung und `list_tasks` des Assistenten lesen `taskList.items` und folgen damit von selbst **[Code: `NotificationScheduler.swift:128`; für die anderen aus dem Aufbau abgeleitet, nicht einzeln getestet]**. Je ein Test sichert Mitteilungen und Planung ab. Tageszuordnungen und Aufwände zu Artikeln, die vorher als Aufgabe geführt wurden, räumt `pruneAssignments` wie bei gelöschten Aufgaben **[Code: `PlanningModel.swift:230`]**.

Ein Wechsel von `shoppingListID` löst zentral in `AppEnvironment` aus: Aufgaben neu laden, Planung neu laden, Mitteilungen neu planen, Snapshot schreiben. Heute hängt das Neuladen nur an der Einstellungsseite **[Code: `SettingsView.swift:117–119`]**; die Vorschlagskarte ändert das Feld aber von „Aufgaben“ aus.

**R2 Namensschlüssel** (`ShoppingName.key`): Kleinbuchstaben, Leerraum außen entfernt und innen zusammengezogen, Diakritika gefaltet (`ä` → `a`). Keine Einzahl-/Mehrzahl-Angleichung. Der Schlüssel dient dem Dublettenvergleich, dem Wiederöffnen und der gelernten Zuordnung.

**R3 Eingabe zerlegen** (`ShoppingInputParser.parse(_:) -> [ParsedItem]`):
1. Trennen an `,` `;` Zeilenumbruch sowie an ` und ` / ` and `.
2. Führende Menge abtrennen: Ziffern oder Zahlwort (ein/eine bis zwölf, one bis twelve), optional gefolgt von einer Einheit (g, kg, ml, l, Stück, Packung(en), Dose(n), Flasche(n), Glas, Becher, Bund, Tüte(n), Kasten; pack(s), can(s), bottle(s), bag(s)). Beispiele: „2 Zwiebeln“ → Menge „2“, Name „Zwiebeln“; „500 g Hackfleisch“ → „500 g“; „zwei Packungen Hafermilch“ → „2 Packungen“.
3. Name: erster Buchstabe groß, höchstens 80 Zeichen; leere Teile entfallen.
4. Höchstens 20 Artikel je Eingabe; weitere werden nicht angelegt, die Oberfläche meldet es.

Die Trennung an „und“ zerlegt auch „Salz und Pfeffer“ (gewollt) und „Fisch und Chips“ (ungewollt). Dagegen steht die Vorschau in §5.4.

**R4 Hinzufügen** (`ShoppingModel.add(_:)`), je Artikel in dieser Reihenfolge:
1. Steht ein **offener** Artikel mit gleichem Schlüssel auf der Liste: nichts anlegen. Ist eine Menge angegeben, ersetzt sie die bisherige (nur wenn das Notizfeld höchstens eine Zeile hat). Ergebnis „steht schon drauf“.
2. Sonst, gibt es einen **erledigten** Artikel mit gleichem Schlüssel aus den letzten 7 Tagen: den jüngsten wieder öffnen, Menge setzen wie in 1. Ergebnis „wieder geöffnet“.
3. Sonst neue Erinnerung in der Einkaufsliste: Titel = Name, Notiz = Menge, ohne Fälligkeit, Priorität 0, ohne Wiederholung.

**R5 Abhaken und Wiederöffnen.** Abhaken setzt `isCompleted = true` über `ReminderStore.save` (nie löschen). Wiederöffnen setzt es zurück. „Erledigt“ zeigt Artikel mit `completedAt` in den letzten 7 Tagen (7 × 24 h ab jetzt), jüngste zuerst.

**R6 Kategorie eines Artikels** (`ShoppingClassifier`), erste zutreffende Regel:
1. Gelernte Zuordnung (`ShoppingAssignment`) zum Schlüssel, wenn ihre Kategorie noch existiert.
2. Wörterbuch liefert einen `builtinKey`, und eine Kategorie mit diesem `builtinKey` existiert.
3. „Sonstiges“.

Wörterbuch-Treffer, längster Treffer gewinnt: (a) ganzer Schlüssel, (b) ein einzelnes Wort des Namens, (c) der Name endet auf einen Wörterbuchbegriff mit mindestens 4 Zeichen („Hafermilch“ → „milch“, „Vollkornbrot“ → „brot“). Regel (c) erzeugt absehbar Fehltreffer („Sonnenmilch“ → Kühlregal); sie sind von Hand korrigierbar und bleiben dann korrigiert.

**R7 „Sonstiges“** ist keine gespeicherte Kategorie, sondern der feste letzte Abschnitt für alles ohne Zuordnung. Er lässt sich nicht umbenennen, verschieben oder löschen und erscheint nur, wenn er Artikel enthält.

**R8 Reihenfolge.** Abschnitte nach `sortIndex`, „Sonstiges“ zuletzt, leere Abschnitte fehlen. Innerhalb eines Abschnitts nach `createdAt` aufsteigend, bei Gleichstand oder fehlendem Datum nach Titel. Tagwerk verlässt sich damit nicht auf die Reihenfolge, in der EventKit liefert.

**R9 Kategorie löschen.** Alle `ShoppingAssignment` auf diese Kategorie werden gelöscht. Die betroffenen Artikel werden danach neu eingeordnet wie frisch angelegte (R6): über das Wörterbuch, sonst „Sonstiges“. War die gelöschte Kategorie eine Standardkategorie, zeigt ihr Wörterbuchteil ins Leere, ihre Artikel landen also unter „Sonstiges“. Die Erinnerungen selbst bleiben unberührt. Die Rückfrage nennt die Zahl der offenen Artikel: „‚Kühlregal‘ löschen? 3 Artikel werden neu einsortiert, meist unter ‚Sonstiges‘.“

**R10 Kategorienamen:** 1–30 Zeichen nach dem Kürzen von Leerraum, eindeutig ohne Beachtung der Großschreibung, nicht „Sonstiges“/„Other“. Höchstens 30 Kategorien.

**R11 Vorschlag der Liste** (`ShoppingListSuggestion`): Kandidaten sind beschreibbare Erinnerungslisten, deren Titel (Kleinbuchstaben, gekürzt) mit „einkauf“, „einkäufe“, „lebensmittel“, „groceries“, „grocery“ oder „shopping“ beginnt. Die Karte erscheint nur bei **genau einem** Kandidaten, Vollzugriff auf Erinnerungen, abgeschlossener Einrichtung, `shoppingListID == nil` und `shoppingSuggestionDismissed == false`.

**R12 Standardkategorien.** Beim ersten Öffnen der Einkaufsseite oder der Kategorienverwaltung (`shoppingCategoriesSeeded == false`) legt Tagwerk zehn Kategorien an, Namen in der App-Sprache dieses Augenblicks; danach sind sie Nutzerdaten und werden nicht nachübersetzt.

| `builtinKey` | Deutsch | Englisch |
|---|---|---|
| `produce` | Obst & Gemüse | Fruit & Vegetables |
| `bakery` | Brot & Backwaren | Bread & Bakery |
| `chilled` | Kühlregal | Dairy & Chilled |
| `meat` | Fleisch & Fisch | Meat & Fish |
| `frozen` | Tiefkühl | Frozen |
| `pantry` | Vorrat & Konserven | Pantry |
| `snacks` | Frühstück & Süßes | Breakfast & Sweets |
| `drinks` | Getränke | Drinks |
| `household` | Haushalt | Household |
| `care` | Drogerie | Personal Care |

**Wörterbuch:** `ShoppingDictionary.json` als Ressource in `TagwerkCore`, Form `{ "produce": ["banane", "bananen", "apfel", …], … }`, Begriffe bereits als Schlüssel nach R2, deutsch und englisch in einer Datei, unabhängig von der App-Sprache. Zielumfang 400–600 Begriffe. Ein Test prüft: jeder Begriff nur in einer Kategorie, jeder `builtinKey` aus der Tabelle oben.

### 5.3 Einstieg in „Aufgaben“ (Mockup EO2, EQ1)

Ein neuer Abschnitt steht in `TaskListView` über den Aufgabenabschnitten und unter Filter und Quellenhinweisen **[Code: `TaskListView.swift:31–60`]**. Er ist unabhängig vom Quellenfilter sichtbar und im Auswahlmodus („Auswählen“) ausgeblendet. Die Zeilen sind nicht auswählbar.

**Zeile „Einkaufsliste“**, je nach Zustand:

| Zustand | Anzeige |
|---|---|
| Kein Vollzugriff auf Erinnerungen | Zeile fehlt |
| Vorschlag nach R11 | Vorschlagskarte EQ1 statt der Zeile |
| Keine Liste gewählt | „Einkaufsliste einrichten ›“, öffnet die Einstellungsseite aus §5.7 |
| Gewählte Liste existiert nicht mehr | wie oben, mit Unterzeile „Die bisherige Liste gibt es nicht mehr.“ |
| Liste gewählt, Artikel offen | „Einkaufsliste“ · Unterzeile „Hafermilch, Bananen, Eier und 4 weitere“ (erste drei nach R8) · rechts „7 offen ›“ |
| Liste gewählt, nichts offen | Unterzeile „Nichts offen“ |

**Vorschlagskarte (EQ1):** „Liste ‚Einkauf‘ als Einkaufsliste verwenden?“ · „Sie erscheint dann hier als eigene Liste und nicht mehr unter den Aufgaben. 7 offene Erinnerungen.“ (Zahl aus einer eigenen Abfrage dieser Liste, weil sie nicht unter den gewählten Aufgabenlisten sein muss) · Knöpfe „Verwenden“, „Andere Liste …“ (öffnet die Auswahl aus §5.7), „Nicht jetzt“ (setzt `shoppingSuggestionDismissed`). Abweichung vom Mockup: Die Karte nennt nur die offenen Erinnerungen, nicht „9 Erinnerungen, davon 7 offen“; die Gesamtzahl bräuchte eine zusätzliche Abfrage ohne Nutzen.

**Zeile „Notizen“:** immer sichtbar. Unterzeile „zuletzt: ‚Ideen Hausarbeit‘ · heute 08:12“ (Titel der zuletzt geänderten Notiz), rechts die Anzahl; ohne Notizen „Noch keine Notizen“.

Beide Zeilen schieben ihre Seite in den `NavigationStack` von „Aufgaben“. Der Stack bekommt dafür einen Pfad, damit der Deeplink die Einkaufsseite öffnen kann (§5.9).

### 5.4 Einkaufsseite (Mockup EO2b, EG2, ES1)

- **Kopf:** Titel „Einkaufsliste“, Unterzeile „7 offen · Liste ‚Einkauf‘ in Erinnerungen“. Oben rechts ein Menü „⋯“ (statt des „＋“ im Mockup, denn hinzugefügt wird unten) und der Assistenten-Knopf.
- **Menü „⋯“:** „Mit ChatGPT sortieren“, „Kategorien verwalten“, „Erledigte entfernen“.
- **Abschnitte** nach R8. Zeile: Kreis, Name, darunter die Menge in Sekundärfarbe.
  - Tipp auf den Kreis: abhaken (R5), haptische Rückmeldung; die Zeile wandert nach „Erledigt“.
  - Tipp auf die Zeile: Blatt „Artikel“ mit Name, Menge, Kategorie-Auswahl und „Löschen“. Hat das Notizfeld mehrere Zeilen (`hasLongNotes`), ist die Menge nur lesbar, mit dem Hinweis „Längere Notiz, in Erinnerungen bearbeiten“. Umbenennen auf einen Namen, der schon offen auf der Liste steht, ist erlaubt; zusammengeführt wird nicht.
  - Gedrückt halten: Menü „Kategorie“ (alle Kategorien, Haken an der aktuellen, „Sonstiges“, „Neue Kategorie …“), „Bearbeiten“, „Löschen“. Die Wahl speichert ein `ShoppingAssignment` mit `manual` für den Namensschlüssel und gilt damit für jeden künftigen Artikel dieses Namens.
  - Wischen nach links: „Löschen“ (entfernt die Erinnerung, wie bei Aufgaben ohne Rückfrage).
- **„Erledigt · n“:** eingeklappter Abschnitt am Ende (R5). Tipp auf den Kreis öffnet wieder. Der Abschnitt ist zugleich der Widerruf für versehentliches Abhaken; eine eigene „Widerrufen“-Leiste gibt es nicht.
- **„Erledigte entfernen“:** löscht nach Rückfrage („12 erledigte Artikel endgültig löschen?“) genau die Artikel, die unter „Erledigt“ stehen, also die der letzten 7 Tage. Ältere bleiben in Erinnerungen.
- **Sonstiges-Abschnitt:** Stehen dort Artikel und ist ChatGPT angemeldet, zeigt die Abschnittszeile rechts „✦ Sortieren“ (gleiche Aktion wie im Menü).
- **Eingabezeile (ES1):** unten angeheftet, Feld „Artikel hinzufügen“, Mikrofon (nur bei `voiceInputEnabled`), Senden-Knopf sobald Text da ist.
  - Erkennt R3 genau einen Artikel und wurde getippt: Return oder Senden legt ihn sofort an.
  - Erkennt R3 mehrere Artikel oder kam der Text aus dem Diktat: Über der Zeile erscheinen Marken („＋ Kaffee“, „＋ Reis“, „＋ 2 Zwiebeln“). Ein Tipp auf eine Marke entfernt sie. Erst Senden legt an. Nach dem Diktat wird also nie ohne Tippen gespeichert.
  - Rückmeldung nach dem Anlegen als kurze Zeile über dem Feld: „3 hinzugefügt“, „Eier steht schon drauf“, „Kaffee wieder geöffnet“.
  - Diktat nutzt `VoiceInputModel` über `VoiceInputFactory` wie im Essen-Blatt **[Code: `VoiceComposer.swift:5–16`, `MealSheet.swift:122`]**, also die vorhandene einmalige Erklärung und Sprachwahl. Kein neuer Schalter.
- **Aktualisierung:** beim Erscheinen, per Ziehen und bei jeder Meldung aus `EventKitGateway.changes` (entprellt).
- **Zustände:**
  - leer: „Die Liste ist leer. Füge unten Artikel hinzu.“
  - Zugriff entzogen: Hinweis mit Knopf zu den iOS-Einstellungen
  - Liste verschwunden: Hinweis mit Knopf „Andere Liste wählen“
  - Schreibfehler: Meldung über dem Feld mit dem Text des `TaskWriteError`
- **Ohne Netz** funktioniert alles außer „Mit ChatGPT sortieren“.

### 5.5 Kategorien verwalten und „Mit ChatGPT sortieren“ (kein Mockup-Bild)

Für beide Bildschirme gibt es im Mockup kein Bild, weil sie erst durch die Zusätze des Nutzers entstanden sind. Maßgeblich ist diese Beschreibung.

**Seite „Kategorien“** (erreichbar über das Menü der Einkaufsseite und über Einstellungen › Einkaufsliste):
- Liste aller Kategorien in ihrer Reihenfolge mit der Zahl offener Artikel.
- Dauerhaft im Bearbeitungsmodus: Griff zum Umsortieren, Wischen zum Löschen (Rückfrage nach R9), Tipp auf den Namen zum Umbenennen (Dialog mit Textfeld, Regeln R10).
- Letzte Zeile „Kategorie hinzufügen“; eine neue Kategorie landet am Ende.
- Darunter fest und grau „Sonstiges · für alles ohne Kategorie“.
- Fußknopf „Standardkategorien wiederherstellen“: legt fehlende Standardkategorien am Ende wieder an, ändert vorhandene und eigene nicht.
- Eine umbenannte Standardkategorie behält ihren `builtinKey`; das Wörterbuch ordnet ihr weiter zu.

**„Neue Kategorie …“ im Zeilenmenü** fragt nur den Namen ab, legt die Kategorie am Ende an und ordnet den Artikel sofort zu.

**Mit ChatGPT sortieren**
1. **Voraussetzungen:** bei ChatGPT angemeldet (sonst ist der Menüpunkt ausgegraut mit der Unterzeile „Anmeldung unter Einstellungen › KI“, und „✦ Sortieren“ fehlt) und Netz.
2. **Einwilligung:** Beim ersten Tippen erscheint `ShoppingSortConsentSheet` nach dem Muster von `MealConsentSheet` (großes Blatt, nicht wegwischbar, „Einverstanden und sortieren“ / „Nicht jetzt“). Inhalt:
   - „Zum Sortieren sendet Tagwerk die Namen deiner offenen Artikel und die Namen deiner Kategorien an ChatGPT (OpenAI), über das Konto, mit dem du angemeldet bist.“
   - **Gesendet wird:** Artikelnamen und Kategorienamen. In einer geteilten Liste auch Artikel, die andere eingetragen haben.
   - **Nicht gesendet werden:** Mengen, erledigte Artikel, Aufgaben, Termine, Notizen, Daten aus Health.
   - **Nur auf dein Tippen:** Ohne „Sortieren“ verlässt nichts das iPhone.
   - „Du kannst das in den Einstellungen unter ‚Einkaufsliste‘ widerrufen.“
   
   Zustimmung setzt `shoppingSortConsent = true`. Ist der Schalter aus, erscheint das Blatt beim nächsten Tippen wieder.
3. **Anfrage** (`ShoppingSorter`, gebaut wie `MealEstimator`: Einwilligung wird geprüft, bevor irgendetwas OpenAI erreicht, 30 s Zeitgrenze, keine Werkzeuge, JSON-Schema `shopping_sort`):
   - Eingabe: Namen aller offenen Artikel **ohne** Zuordnung mit `manual`, höchstens 60, dazu alle Kategorienamen und „Sonstiges“. Von Hand zugeordnete Artikel werden weder gesendet noch geändert.
   - Ausgabe: `{ "assignments": [{ "item": String, "category": String }], "new_categories": [String] }`, höchstens 3 neue Kategorien.
   - Prüfung: unbekannte Artikel werden verworfen; eine Kategorie muss existieren, „Sonstiges“ sein oder in `new_categories` stehen; neue Namen müssen R10 erfüllen.
4. **Ergebnisblatt „Vorschlag von ChatGPT“:** zeigt nur Änderungen gegenüber dem Ist-Zustand, je Zeile „Sojasauce · Sonstiges → Vorrat & Konserven“ mit Haken (an). Darüber, falls vorhanden, „Neue Kategorie ‚Tierbedarf‘ anlegen“ mit Haken (an); wird sie abgewählt, fallen ihre Artikel aus dem Vorschlag. Knöpfe „Verwerfen“ und „Übernehmen“.
   - „Übernehmen“ legt die gewählten Kategorien am Ende an und speichert je Artikel ein `ShoppingAssignment` mit `ai`.
   - Ohne Änderungen: „ChatGPT schlägt keine andere Einteilung vor.“
5. **Fehler:** Texte nach dem Muster von `MealEstimator.Failure` (keine Verbindung, Anmeldung abgelaufen, Nutzungsgrenze, fehlgeschlagen). Ein Teil- oder Spätergebnis wird nie übernommen.
6. Nichts geschieht im Hintergrund, und Sortieren schreibt nie in Erinnerungen.

### 5.6 Notizen (Mockup NQ1)

- **Liste:** Karten mit Titel (erste Zeile, fett), Vorschau (zwei Zeilen) und Fußzeile. Angeheftete zuerst (📌), dann nach `updatedAt` absteigend.
  - Fußzeile bei `free`: Datum relativ („heute 08:12“, „Dienstag“, „12. Nov.“), bei Diktat mit „· diktiert“.
  - Fußzeile bei Gedanken-Notizen: Herkunft und Tag, „Tagesabschluss · 18.11.“ bzw. „Tagesstart · 18.11.“ (Tag aus `dayKey`). Ihr Titel ist ebenfalls die erste Textzeile.
  - Filter „Alle · Gedanken · Eigene“ als Segmentleiste, nur sichtbar, sobald mindestens eine Gedanken-Notiz existiert. In Phase 5 gibt es keine, der Filter ist aber gebaut und getestet.
- **Schnellerfassung:** Eingabezeile unten „Neue Notiz“ mit Mikrofon. Senden legt eine Notiz `free` an und leert das Feld; Diktat setzt `wasDictated`. Mehrzeilige Eingabe ist möglich.
- **Editor:** Tipp auf eine Karte schiebt eine Seite mit einem Textfeld über die ganze Fläche. Gespeichert wird automatisch (entprellt 0,5 s und beim Verlassen), `updatedAt` nur bei geändertem Text. Eine Notiz ohne Text wird beim Verlassen gelöscht. Menü oben rechts: „Anheften“/„Lösen“, „Löschen“. Bei Gedanken-Notizen ist der Text bearbeitbar, Art und Tag sind es nicht.
- **Wischen in der Liste:** links „Löschen“ (mit Rückfrage, weil es keinen Papierkorb gibt), rechts „Anheften“.
- **Fußnote unter der Liste:** „Notizen liegen nur auf diesem iPhone. Sie werden nicht an ChatGPT gesendet.“ Phase 7 passt den zweiten Satz an, sobald dort eine Zustimmung existiert.
- **Leerer Zustand:** „Noch keine Notizen. Schreib oder diktiere unten die erste.“
- **Zugriff:** `NoteStore` (Anlegen, Ändern, Löschen, Abfragen nach Art und Tag) ist die einzige Stelle, die `NoteRecord` schreibt; Phase 7 nutzt denselben Typ.

### 5.7 Einstellungen (Mockup EQ2)

- **Einstellungen › Quellen:** neue Zeile „Einkaufsliste“ unter „Erinnerungslisten“, Wert = Listentitel oder „Keine“.
- **Seite „Einkaufsliste“:**
  1. Einfachauswahl aller beschreibbaren Erinnerungslisten (Farbpunkt, Titel) plus „Keine“. Nicht beschreibbare Listen fehlen.
  2. Fußtext: „Die gewählte Liste erscheint als Einkaufsliste. Ihre Einträge stehen nicht mehr unter ‚Aufgaben‘, werden nicht eingeplant, zählen nicht im Wochenrückblick und lösen keine Tagwerk-Mitteilungen aus. In der App ‚Erinnerungen‘ ändert sich nichts.“
  3. Abschnitt „Kategorien“: Zeile „Kategorien verwalten“ mit Anzahl.
  4. Abschnitt „ChatGPT“: Schalter „Mit ChatGPT sortieren“ (`shoppingSortConsent`). Fußtext: „Sendet auf dein Tippen die Namen der offenen Artikel und deiner Kategorien an ChatGPT. Fragst du den Assistenten nach der Einkaufsliste, gehen die Artikelnamen ebenfalls an ChatGPT.“
- **Einstellungen › Erinnerungslisten:** Die Einkaufsliste ist grau mit dem Vermerk „Einkaufsliste“ (R1).
- **Einstellungen › Erfassen › Siri & Kurzbefehle:** die zwei neuen Sätze aus §5.9 ergänzen **[Code: `CaptureSettingsView.swift:58–60`]**.

### 5.8 Assistent (Mockup EA2)

Zwei neue Funktionen in `AppTools`; `list_shopping` kommt in `readTools`.

| Funktion | Art | Parameter | Antwort |
|---|---|---|---|
| `list_shopping` | lesen | `include_completed: boolean` | `{"ok":true,"list":"Einkauf","open":[{"id","name","quantity","category"}],"completed":[{"id","name"}]}`; höchstens 100 offene; `completed` nur auf Wunsch und nur letzte 7 Tage |
| `update_shopping` | schreiben, „Needs confirmation“ | `add: [{name: string, quantity: string\|null}]`, `check_off: [string]` (Kennungen aus `list_shopping`); je höchstens 30 | `{"ok":true,"added":[…],"reopened":[…],"already_on_list":[…],"checked_off":[…],"not_found":[…]}` |

- Schemas nach dem bestehenden Muster: `strict`, alle Felder erforderlich, optionale als `null` **[Code: `AppTools+Definitions.swift:4–29`]**.
- `add` läuft über R4, also ohne Dubletten und mit Wiederöffnen.
- `check_off` prüft jede Kennung: Die Erinnerung muss existieren **und** in der Einkaufsliste liegen, sonst landet sie in `not_found`. So kann die Funktion keine fremde Erinnerung abhaken (Anti-Ziel).
- Teilfehler brechen nicht ab; die Antwort nennt, was geklappt hat.
- Ohne gewählte Liste oder ohne Zugriff: `{"error":"Es ist keine Einkaufsliste eingerichtet. Einstellungen › Einkaufsliste."}`.
- **Sammelkarte** (`AssistantModel.describe`, **[Code: `AssistantModel.swift:411`]**): Titel „Einkaufsliste ändern“, Änderung „＋ Kaffee · ＋ Reis · ＋ Zwiebeln · ✓ Eier“. Eine Karte für alle Änderungen eines Aufrufs. Im Sprachmodus wird sie wie die übrigen Karten angesagt.
- **Systemhinweis** (`AssistantModel.instructions()`, `:349`): ein Satz, dass Einkaufsartikel nicht in `list_tasks` stehen und über die beiden Funktionen laufen; Artikel nie über `create_task` anlegen.
- **Datenschutz:** Ruft das Modell `list_shopping` auf, gehen Artikelnamen, Mengen und Kategorienamen an ChatGPT. Das entspricht dem heutigen Umgang mit Aufgabentiteln im Chat (keine eigene Einwilligung, E9) und steht im Fußtext der Einstellungen (§5.7).
- **Keine Notiz-Funktionen.** Der Assistent kann Notizen weder lesen noch anlegen.

### 5.9 Kurzbefehle, Deeplink, Mitteilungen (Mockup ES2)

| Intent | Modus | Wirkung |
|---|---|---|
| `AddToShoppingListIntent`, Titel „Auf die Einkaufsliste“, Parameter „Artikel“ (Text; fehlt er, fragt Siri „Was soll auf die Liste?“) | Hintergrund | zerlegt nach R3, legt nach R4 an; Antwort „3 Artikel hinzugefügt: Kaffee, Reis, Zwiebeln.“ bzw. „Eier steht schon auf der Liste.“ |
| `OpenShoppingListIntent`, Titel „Einkaufsliste zeigen“ | Vordergrund | öffnet `tagwerk://shopping` |

- Sätze: „Auf die Einkaufsliste in ‹App›“, „Zur Einkaufsliste in ‹App› hinzufügen“, „Einkaufsliste in ‹App› ergänzen“; „Einkaufsliste in ‹App› zeigen“. Jeder Satz enthält `\(.applicationName)`; der Artikeltext steht nicht im Satz, weil dort nur Enum-Parameter erlaubt sind (Phase 4 §8).
- `IntentServices.addToShopping(text:)` braucht nur Gateway, Einstellungen und R3/R4, keine geladene Aufgabenliste (E10). Kein KI-Aufruf, kein Netz.
- Ohne gewählte Liste: „Wähle zuerst in Tagwerk unter Einstellungen › Einkaufsliste eine Liste.“ Ohne Zugriff: „Tagwerk hat keinen Zugriff auf Erinnerungen.“
- Die Antwort nennt nur, was der Nutzer eben gesagt hat, und keine weiteren Artikel. Deshalb verlangt der Intent kein entsperrtes Gerät.
- **Deeplink:** neuer Fall `AppRoute.shopping = "shopping"`. `RootView` wählt den Tab „Aufgaben“ und schiebt die Einkaufsseite; ohne gewählte Liste die Einstellungsseite. Der Link navigiert nur (Phase 4 §5.5); Parameter werden nicht ausgewertet.
- **Mitteilungen:** keine neuen. Artikel der Einkaufsliste lösen keine Tagwerk-Mitteilungen aus (R1). Erinnert Apple selbst an einen Artikel mit Alarm, bleibt das unverändert.
- **Widget:** keine Änderung; der Snapshot enthält keine Einkaufsartikel.

### 5.10 Lokalisierung (EN)

Quellsprache der Kataloge ist Deutsch **[Code: `Tagwerk/Localizable.xcstrings`, `sourceLanguage: de`]**. Alle neuen Texte bekommen eine englische Fassung: App-Texte in `Tagwerk/Localizable.xcstrings`, Sätze der Kurzbefehle in `AppShortcuts.xcstrings`, Texte aus den Paketen in deren Katalogen.

| Deutsch | Englisch |
|---|---|
| Einkaufsliste | Shopping List |
| Notizen | Notes |
| Einkaufsliste einrichten | Set up shopping list |
| Liste „%@“ als Einkaufsliste verwenden? | Use the list “%@” as your shopping list? |
| Verwenden · Andere Liste … · Nicht jetzt | Use · Another List … · Not Now |
| %lld offen | %lld open |
| Artikel hinzufügen | Add item |
| Erledigt · %lld | Completed · %lld |
| Erledigte entfernen | Remove Completed |
| Sonstiges | Other |
| Kategorien verwalten | Manage Categories |
| Mit ChatGPT sortieren | Sort with ChatGPT |
| Vorschlag von ChatGPT | Suggestion from ChatGPT |
| Übernehmen · Verwerfen | Apply · Discard |
| Neue Notiz | New note |
| Tagesstart · Tagesabschluss | Morning · Evening |
| Auf die Einkaufsliste | Add to Shopping List |
| Einkaufsliste zeigen | Show Shopping List |
| Einkaufsliste ändern (Sammelkarte) | Change shopping list |

Mehrzahlformen („1 Artikel“ / „3 Artikel“, „1 item“ / „3 items“) über die Plural-Varianten des Katalogs. Das Wörterbuch ist zweisprachig und hängt nicht an der App-Sprache; R3 kennt deutsche und englische Trenn- und Zahlwörter gleichzeitig.

## 6. Abhängigkeiten zu den anderen drei Vorhaben

Reihenfolge der Umsetzung: (1) #136 Issue-Zuweisung, (2) **Phase 5**, (3) Suche, (4) Phase 7 Routinen (#140).

| Vorhaben | Abhängigkeit | Was Phase 5 liefert oder braucht |
|---|---|---|
| #136 Issue-Zuweisung (vorher) | Keine fachliche. Beide ändern `TaskListView` und `TaskListModel` | Phase 5 setzt auf dem gemergten Stand von #136 auf und fügt nur den Abschnitt am Listenkopf und den Navigationspfad hinzu |
| Suche (danach) | Die Suche zeigt Einkaufsartikel als eigenen Abschnitt ganz unten (QK3) | Phase 5 liefert `shoppingListID`, das Lesen offener Artikel über `ShoppingModel` und das Sprungziel `AppRoute.shopping`. Ob die Suche auch Notizen durchsucht und ob die beiden Karten bei aktiver Suche verschwinden, legt die Such-Spec fest; `NoteStore` ist dafür abfragbar |
| Phase 7 Routinen, Gedanken-Notiz #143 (danach) | Gemeinsamer Speicher | Phase 5 legt `NoteRecord` samt `kindRaw`, `dayKey`, `processedAt` an und zeigt Gedanken-Notizen in der Liste mit „Tagesabschluss · 18.11.“ und Filter. Phase 7 schreibt `morning`/`evening`, baut Erfassung, Zustimmung und Verarbeitung und darf nur Felder mit Standardwert ergänzen. Zeigt Phase 7 zusätzlich „2 Aufgaben daraus“ in der Karte, ergänzt sie die Fußzeile |
| Alle drei | Tab-Leiste | Kein neuer Tab; Phase 5 fügt in „Planen“ und „Aufgaben“ keinen Knopf oben rechts hinzu (Annahme der Such-Planung) |

## 7. Geprüft, abgeleitet, angenommen

**Geprüft im Quelltext (dieser Stand):** alle mit **[Code]** markierten Stellen, darunter die sechs Ausschlussstellen aus R1, das Schema, die Muster für Einwilligung, Assistenten-Funktionen, Intents und Routen.

**Aus dem Mockup übernommen, hier nicht erneut geprüft:** die Aussagen zu den EventKit-Headern (**[SDK]**) und zu Apple Notizen (E11).

**Abgeleitet, nicht getestet:** dass Mitteilungen, Widget und `list_tasks` der Aufgabenliste folgen; dass verwaiste Tageszuordnungen aufgeräumt werden.

**Annahmen (ungeprüft):**
- `EKCalendarItem.creationDate` und `EKReminder.completionDate` sind für Artikel gefüllt, auch wenn sie auf einem anderen Gerät angelegt oder abgehakt wurden.
- Ein Hintergrund-Intent darf über EventKit schreiben, auch bei gesperrtem Gerät.
- Geteilte Listen lassen sich wie eigene schreiben.
- `NoteRecord` ist so, wie es angelegt ist, später mit CloudKit verträglich (alle Attribute mit Standardwert, nichts eindeutig, keine Beziehungen). Das stützt sich auf Dokumentationswissen, nicht auf einen Versuch. Ein späterer Abgleich braucht voraussichtlich einen getrennten Store nur für Notizen und damit einen einmaligen Umzug.
- Das Wörterbuch mit 400–600 Begriffen deckt einen üblichen Einkauf weitgehend ab. Dafür gibt es keinen Beleg; die Trefferquote zeigt sich erst im Alltag.

## 8. Tests

- `TagwerkCore`: `ShoppingInputParser` (Trennung, Mengen, Grenzen), `ShoppingName.key`, `ShoppingClassifier` (Reihenfolge R6, Endungstreffer, gelöschte Kategorie), Wörterbuch-Konsistenz, `AppRoute.shopping`.
- `RemindersKit`: `ShoppingListFilter` (alle Fälle inkl. leerer Menge), `containers()` ohne Einkaufsliste, Rückfall der Standardliste.
- App: `ShoppingModel` (R4, R5, „Erledigte entfernen“ nur letzte 7 Tage), Kategorien (R9, R10, Wiederherstellen), `ShoppingSorter` (keine Anfrage ohne Einwilligung, Prüfung der Antwort, Fehlerfälle), `NoteStore`, `AppTools` (`check_off` lehnt fremde Erinnerungen ab), `IntentServices.addToShopping`, Planung und Mitteilungen ohne Einkaufsartikel, Wochenrückblick ohne Einkaufsliste.

## 9. Festlegungen des Verfassers („meine Festlegungen“)

Diese Punkte hat der Nutzer nicht entschieden. Nr. 1–6 stammen vom vorigen Planer (Mockup „Kleinere Festlegungen“) und sind übernommen; Nr. 7–22 sind in diesem Dokument neu.

1. Artikel haben nur Name und Menge. Die Menge steht im Notizfeld der Erinnerung (erste Zeile).
2. Abhaken setzt erledigt, löscht nicht. Erledigte der letzten 7 Tage stehen eingeklappt unter „Erledigt“.
3. Ein Name, der einem kürzlich erledigten Artikel gleicht, öffnet diesen wieder; ein schon offener wird nicht doppelt angelegt.
4. Kein Eintrag in „Planen“.
5. Deeplink `tagwerk://shopping`.
6. `NoteRecord` ist für späteren iCloud-Abgleich vorbereitet, liegt aber im bestehenden Store.
7. **Zuordnung je Artikelname, nicht je Erinnerung.** „Spülmittel → Haushalt“ gilt für jedes künftige Spülmittel und auch für Artikel, die in Erinnerungen angelegt wurden.
8. **„Sonstiges“ ist fest** und keine verwaltbare Kategorie (R7). Artikel einer gelöschten Kategorie werden neu einsortiert, meist nach „Sonstiges“ (R9).
9. **ChatGPT darf neue Kategorien vorschlagen** (höchstens 3, einzeln abwählbar), aber keine umbenennen oder löschen. Begründung: deckt beide Lesarten des Nutzerwunsches ab, ohne dass ChatGPT etwas zerstören kann.
10. **ChatGPT sortiert nur Artikel ohne Handzuordnung.** Eine Entscheidung des Nutzers wird nie überschrieben und auch nicht gesendet.
11. **Eigene einmalige Einwilligung** für das Sortieren mit Schalter in den Einstellungen (Muster Mahlzeiten). Für den Assistenten gibt es keine zusätzliche Einwilligung (wie bei Aufgaben), nur den Hinweis im Fußtext.
12. **Zehn Standardkategorien** nach R12, Namen beim Anlegen in der App-Sprache, danach nicht mehr übersetzt.
13. **Reihenfolge im Abschnitt nach Anlagedatum** (R8), unabhängig von EventKit.
14. **Mehrere Artikel und Diktat immer mit Vorschau;** ein einzelner getippter Artikel ohne.
15. **Vorschlagskarte nur bei genau einem passenden Listennamen** (R11). Bei mehreren Treffern wird nicht geraten.
16. **Nur beschreibbare Listen** können Einkaufsliste sein.
17. **„Erledigte entfernen“ löscht nur die sichtbaren** (letzte 7 Tage), nach Rückfrage.
18. **Die Zeile „Einkaufsliste einrichten“ bleibt** nach „Nicht jetzt“ sichtbar; einen Schalter zum Ausblenden der beiden Karten gibt es nicht.
19. **Zweiter Kurzbefehl „Einkaufsliste zeigen“** zusätzlich zum entschiedenen „Auf die Einkaufsliste“ (Mockup ES2 nennt den Satz; Aufwand unter 1 h).
20. **Ist Apples Standardliste die Einkaufsliste,** gehen neue Aufgaben ohne Listenwahl in die erste andere gewählte Liste.
21. **Notizen:** Titel ist die erste Zeile; Schnellerfassung in der Liste; automatisches Speichern; Löschen mit Rückfrage; Gedanken-Notizen sind in der Liste sichtbar, ihr Text bearbeitbar; Filter erst ab der ersten Gedanken-Notiz.
22. **Einkaufsseite oben rechts „⋯“ statt „＋“** (Abweichung von EO2b), weil unten hinzugefügt wird und das Menü Platz für Sortieren und Verwalten braucht.

## 10. Offene Punkte / Spikes am Gerät

**Spike vor dem Plan (etwa 2 h, Wegwerf-Code oder Debug-Seite):**

| Nr. | Frage | Folge des Ergebnisses |
|---|---|---|
| S1 | Werden über EventKit angelegte Artikel in Apples Liste vom Typ „Einkaufsliste“ automatisch einsortiert? | Keine für den Bau. Falls nein: Hinweis in der Doku, dass neue Artikel in Erinnerungen unsortiert erscheinen |
| S2 | Sind `creationDate` und `completionDate` gefüllt, auch für Artikel von anderen Geräten? | Falls `creationDate` fehlt: R8 fällt auf den Titel zurück (schon vorgesehen). Falls `completionDate` fehlt: „Erledigt“ nimmt ersatzweise das Änderungsdatum |
| S3 | Geteilte Liste: anlegen, abhaken, löschen möglich? Wie schnell kommen fremde Änderungen an? | Falls nicht beschreibbar: greift Nr. 16, die Liste ist nicht wählbar. Falls Löschen fremder Artikel scheitert: Fehlermeldung genügt |
| S4 | Schreibt `AddToShoppingListIntent` im Hintergrund, auch bei gesperrtem Gerät? | Falls nein: Intent in den Vordergrund-Modus, Antwort bleibt gleich |
| S5 | Dauer von `predicateForCompletedReminders` über 7 Tage in einer lang genutzten Liste | Falls spürbar: „Erledigt“ erst beim Aufklappen laden |

**Geräte-Checkliste nach dem Bau:** Diktat in der Eingabezeile, Siri erkennt die deutschen Sätze, Kaltstart über `tagwerk://shopping`, Abhaken in Erinnerungen erscheint ohne Neustart in Tagwerk, Mitteilungen enthalten keinen Artikel, Wörterbuch-Trefferquote an der echten Liste.

**Offen, aber nicht blockierend:** Trefferquote des Wörterbuchs (Nachpflege nach den ersten Wochen); ob „Mit ChatGPT sortieren“ in der Praxis genutzt wird.

**Dem Umsetzenden überlassen:** Ordnerstruktur, Testaufbau, Symbole und Farben im Rahmen des Mockups, genauer Wortlaut des ChatGPT-Auftrags, Inhalt des Wörterbuchs, Demo-Daten, Kontext des Assistenten-Knopfs auf den neuen Seiten.

## 11. Aufgabenschnitt

Schätzungen in Stunden, ohne Review-Schleifen. Sie sind Erfahrungswerte aus den bisherigen Phasen, keine Messung.

| Nr. | Paket | Inhalt | h |
|---|---|---|---|
| 0 | Spike am Gerät | S1–S5 aus §10, Ergebnis als Nachtrag in dieses Dokument | 2 |
| 1 | Ausschluss | Felder in `AppSettings`, `ShoppingListFilter`, sechs Stellen aus R1, zentrales Neuladen, Tests für Planung, Mitteilungen, Rückblick | 4 |
| 2 | RemindersKit | `createdAt`, `completedAt`, `isWritable`, `completedReminders`, Rückfall der Standardliste, Fake erweitern | 3 |
| 3 | Kernlogik | `ShoppingInputParser`, `ShoppingName`, `ShoppingClassifier`, Wörterbuch (Datei und Inhalt), Tests | 6 |
| 4 | Kategorien | Modelle, Standardkategorien, Speicher, Seite „Kategorien“ (anlegen, umbenennen, umsortieren, löschen, wiederherstellen), Tests | 6 |
| 5 | `ShoppingModel` | Laden, R4, R5, Bearbeiten, Löschen, „Erledigte entfernen“, Reaktion auf EventKit-Änderungen, Tests | 5 |
| 6 | Einkaufsseite | Abschnitte, Zeilen, Menüs, Blatt „Artikel“, „Erledigt“, Eingabezeile mit Diktat und Marken, Zustände | 8 |
| 7 | Einstieg und Einstellungen | Karten in „Aufgaben“, Vorschlagskarte, Navigationspfad, Seite „Einkaufsliste“, Vermerk in „Erinnerungslisten“ | 5 |
| 8 | ChatGPT-Sortierung | `ShoppingSorter`, Einwilligungsblatt, Ergebnisblatt, neue Kategorien, Fehlerfälle, Tests | 6 |
| 9 | Notizen | `NoteRecord`, `NoteStore`, Liste mit Filter und Herkunftszeile, Schnellerfassung, Editor, Tests | 7 |
| 10 | Assistent | `list_shopping`, `update_shopping`, Sammelkarte, Ansage, Systemhinweis, Tests | 4 |
| 11 | Kurzbefehle und Deeplink | zwei Intents, `IntentServices`, `AppRoute.shopping`, Sätze, Tests | 3 |
| 12 | Abschluss | englische Texte, Demo-Daten, Geräte-Checkliste, Nachtrag „Abweichungen bei der Umsetzung“ | 3 |
| | **Summe** | | **62** |

Reihenfolge: 0 → 1, 2 → 3 → 4, 5 → 6, 7 → 8, 10, 11 → 12. Paket 9 (Notizen) hängt an nichts davon und kann jederzeit nach Paket 1 laufen. Ein erster nutzbarer Stand (Liste raus aus den Aufgaben, flache Einkaufsseite) entsteht nach den Paketen 1, 2, 5 und Teilen von 6 und 7.

## Nachtrag: Spike 0 (Stand 2026-11-19)

Der Spike am Gerät (S1–S5) ist **nicht durchgeführt**. Gebaut wurde mit den Annahmen aus §7; keine davon ist damit belegt.

| Nr. | Stand | Angenommene Vorgabe | Folge, falls die Annahme nicht hält |
|---|---|---|---|
| S1 | offen | keine (ohne Einfluss auf den Bau) | Hinweis, dass neue Artikel in Erinnerungen unsortiert erscheinen |
| S2 | offen | `creationDate` und `completionDate` sind gefüllt | `completedAt = completionDate ?? lastModifiedDate` in `EventKitGateway.record(_:)` |
| S3 | offen | geteilte Listen lassen sich schreiben | keine Änderung nötig (Fehlermeldung genügt) |
| S4 | offen | der Hintergrund-Intent darf schreiben | `AddToShoppingListIntent.supportedModes = .foreground(.immediate)` |
| S5 | offen | erledigte Artikel lassen sich schnell lesen | „Erledigt“ erst beim Aufklappen laden |

## Nachtrag: Abweichungen bei der Umsetzung (Stand 2026-11-19)

Umgesetzt sind die Tasks 2–17 des Plans. Die Regeln R1–R12 und §5.3–§5.10 sind unverändert; abgewichen wurde nur an den folgenden Stellen.

**Aus dem Plan (A1–A6):**
- A1: `ReminderStore.defaultListID()` legt Apples Standardliste offen (Standard `nil`).
- A2: `ShoppingModel` liest `EventKitGateway.changes` nicht selbst; `AppEnvironment.startObservingChanges()` lädt es mit. Eine eigene Entprellung gibt es nicht.
- A3: `AppEnvironment.init` nimmt einen `reminderStore` entgegen (Standard: das Gateway).
- A4: Eine Zuordnung ohne Kategorie bedeutet „Sonstiges“ und schlägt das Wörterbuch. Das gilt für Handzuordnungen und für übernommene Vorschläge von ChatGPT.
- A5: `ShoppingInputParser.parseAll(_:)` meldet zusätzlich die Zahl der weggelassenen Artikel.
- A6: `setShoppingList(_:)` plant Mitteilungen und Snapshot ausdrücklich neu.

**Zusätzlich bei der Umsetzung:**
- R2: Die Faltung macht aus „ß“ ein „ss“ (Verhalten von Foundation). „Äpfel“ und „Apfel“ erhalten denselben Schlüssel, weil „ä“ zu „a“ wird; Einzahl und Mehrzahl werden weiterhin nicht angeglichen.
- R3: Eine Zahl mit Einheit, aber ohne Namen („500 g“) bleibt ein Name. Ein Teil, der nur aus „und“/„and“ besteht, entfällt.
- §5.1: Ein Notizfeld gilt als „lang“, sobald nach der ersten Zeile noch Text folgt, auch wenn die erste Zeile leer ist.
- §5.4: Die Unterzeile „7 offen · Liste ‚Einkauf‘ in Erinnerungen“ steht als erste Zeile der Liste, nicht im Navigationskopf. Marken entstehen laufend aus dem Feldinhalt; „Senden“ legt genau die gezeigten Marken an. Der Pfeil in der Aufnahmeleiste füllt nur das Feld.
- §5.5: Eine von ChatGPT vorgeschlagene neue Kategorie erscheint nur, wenn ihr mindestens ein Artikel zugeordnet wird. Je Artikel zählt der erste Eintrag der Antwort, auch wenn er ungültig ist.
- §5.6: Der Pfeil in der Aufnahmeleiste der Notizen speichert die diktierte Notiz sofort (er ist das Tippen des Nutzers).
- §5.7: Die Zeile „Erinnerungslisten“ zeigt jetzt immer „n von m“ (vorher „Alle“, wenn alles gewählt war).
- §5.8: Die Sammelkarte nennt eine angegebene Menge („＋ 2 Zwiebeln“). Die Antwort von `update_shopping` enthält `failed` und `failure` nur, wenn ein Schreibvorgang scheiterte.
- §5.9: Die Antwort des Kurzbefehls zählt wieder geöffnete Artikel als hinzugefügt.
- §5.10: „Übernehmen“ heißt im Ergebnisblatt englisch „Apply“ (eigener Schlüssel, weil derselbe deutsche Text an anderer Stelle „Accept“ bedeutet). „Nicht jetzt“ bleibt beim vorhandenen „Not now“. „Lösen“ heißt bei Notizen englisch „Unpin“.
- Wörterbuch: 581 Begriffe. Die Trefferquote ist nicht gemessen.

**Geräte-Checkliste (Plan, Task 17, Schritt 4):** nicht durchgeführt; alle acht Punkte sind offen.

