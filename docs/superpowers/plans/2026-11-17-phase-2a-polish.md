# Phase 2a-Feinschliff – Implementation Plan

> Ausführung: native, testgetrieben, auf `feature/phase-2a` vor dem Merge. Grundlage: Geräteprüfung des Nutzers vom 2026-11-17 (Rückmeldungen im Thread), freigegeben am 2026-11-17.

**Goal:** Die Rückmeldungen aus der Geräteprüfung beheben, bevor Phase 2a gemergt wird.

**Spec:** `docs/superpowers/specs/2026-11-17-phase-2-design.md`. Gestaltung der Elemente in Task 7 nach `docs/superpowers/mockups/2026-11-17-phase-2a-polish-mockups.html`. **Freigegeben am 2026-11-17: 1A, 2A, 3A (Zahl ist eintippbar), 4A.**

## Global Constraints

Wie in Plan 2a und 2a-GitHub. Zusätzlich gilt: Ein Issue wird auf GitHub nie gelöscht.

## Tasks

1. **„Neu laden“ schließt das Sheet nicht mehr.** Zuerst die Ursache klären. Vermutung: Mehrere `Button` in einer Formularzeile lösen beim Antippen alle aus. Danach bleibt das Sheet offen und zeigt den neuen Stand.
2. **Löschen:** `TaskProvider.delete(id:expectedVersion:)`. Erinnerungen über EventKit `remove`, lokale Aufgaben über SwiftData, jeweils mit Versionsprüfung. GitHub löscht nicht, dort gibt es „Schließen als nicht geplant“ (`state_reason: not_planned`, Status „Done“). In der Oberfläche: Wischen nach links bietet „Löschen“ an, das Bearbeiten-Sheet bekommt „Aufgabe löschen“, beides mit Bestätigung.
3. **Vorauswahl beim Anlegen:** ＋ übernimmt den aktiven Filter (Erinnerungen, GitHub oder Lokal). Bei „Alle“ ist „Erinnerung“ vorgewählt. Ist die Quelle nicht verfügbar, wird „Lokal“ gewählt.
4. **Verschieben „Wochenende“:** Ziel ist der nächste Samstag nach heute. Am Samstag ist es der Samstag eine Woche später. Eine Uhrzeit bleibt erhalten.
5. **GitHub-Issue in mehreren Projects anlegen:** `TaskDraft.subContainerIDs` (Mehrfachauswahl). Nach der Repo-Wahl werden die Projects vorgewählt, die mit dem Repo verknüpft sind (`ProjectV2.repositories`). Die Zuordnung Repo → Projects und die Repo-Liste liegen lokal (SwiftData). Aktualisiert werden sie beim Start und danach höchstens alle 5 Minuten, sobald das Anlege-Sheet öffnet.
6. **Aufwand in Stunden:** Werte von 0,25 bis 24 h in 0,25er-Schritten, intern weiter in Minuten. Eingabe nach dem freigegebenen Mockup.
7. **Gestaltung nach den freigegebenen Mockups:** „Rückgängig“-Leiste, Konflikt-Banner, Aufwandsfeld, dezenter Offline-Hinweis.
