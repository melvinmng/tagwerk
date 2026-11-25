# Entscheidungen des Owners zu #319, #320, #331, #332 (2026-11-25)

Grundlage: `fable-plan.md`, `neon-plan.md` und die vier Mockups in diesem Ordner. Wo die Pläne sich widersprechen, gilt dieses Dokument.

## #319 Strichcode-Scan
- Einstieg Variante A: Scan-Symbol im Suchfeld von „Meine Lebensmittel“ und eigene Zeile „Strichcode scannen“ direkt über „Etikett fotografieren“.
- Scan-Knopf immer sichtbar, unabhängig von der Online-Suche.
- Zuerst lokal suchen (`FoodStore` nach Strichcode): Treffer öffnet direkt die Mengeneingabe, ohne Netz und ohne Einwilligung. Erst bei unbekanntem Code Open Food Facts, Einwilligung erst dann.
- Handeingabe der Ziffern als Ersatzweg (verweigerte Kamera, Simulator, UI-Tests). GTIN-Prüfziffer prüfen.

## #320 Wochenrückblick
- Variante A: Gewicht als kompakte Kennzahlen (7-Tage-Mittel, Trend 4 Wochen, Zielabstand) mit Link zu „Verlauf und Ziele“, keine Sparkline.
- Wochenveränderung = Differenz der 7-Tage-Mittel; gemeinsame reine Rechnung mit der Verlaufsseite (`WeightTrend`), damit beide nicht auseinanderlaufen.
- Eiweiß geht in die gemeinsame Gruppe „Nährwerte“ (Makros + Ballaststoffe/Zucker/weitere).
- Woche ohne Messung: Abschnitt bleibt mit Hinweis stehen.
- Neu: „Im Budget an x von y Tagen“, Ø Budget, Kohlenhydrate, Fett, Vergleich mit Zielen, Zeile „Ziele vom …“.

## #331 Suche
- Variante A: Repository- und Projekt-Auswahl als durchsuchbares Sheet, einheitlich in `NewTaskSheet`, `IssueTargetSheet`, `TaskProposalEditor`.
- Paging im selben PR: alle Repositories (eigene **und** aus Organisationen) und alle Projects, kein Abbruch nach 20/100.
- Einstellungssuche an beiden Orten: `.searchable` im Tab „Einstellungen“ und Abschnitt in der übergreifenden Suche.
- Repositories und Projects **erscheinen** als Treffer in der übergreifenden Suche; ein Tipp öffnet die Projektübersicht/Trendanalyse aus #332. Dieser Teil (C) wird erst nach #332 Stufe 1 umgesetzt.

## #332 Projektfortschritt
- Einstieg: Zeile „Projektfortschritt“ im Tab „Aufgaben“.
- Projekte = alle Quellen (GitHub Projects/Repositories, Erinnerungslisten, Lokal) mit Quellen-Filter.
- GitHub: **alle** Einträge eines Projects, nicht nur zugewiesene.
- Stufe 1: Übersicht erledigt/neu/offen, Wochendiagramm, Verlauf aus „angelegt“ und „erledigt“ (rückwirkend aus Anlage- und Schlussdatum). Das lokale Aktivitätsprotokoll (Statuswechsel, Verschiebungen) wird schon in Stufe 1 eingebaut und sammelt ab Einführung.
- Stufe 2: Zeit je Projekt (eingeplant/investiert). Stufe 3: Statusverlauf-Auswertung.
- Blocker: Ein Issue ist Blocker, wenn es über die native GitHub-Abhängigkeit als „Blocking“ markiert ist, d. h. andere („Blocked by“) Issues darauf verweisen (GraphQL `blocking` / `blockedBy`). Blockiert = `blockedBy` nicht leer oder Status *Blocked*. Kein Freitext.
- Trend „ruht“: Start mit 14 Tagen ohne Bewegung, nach zwei Wochen Nutzung am echten Bestand prüfen.
- Zeiträume: 4 Wochen, 3 Monate, 1 Jahr, frei.

## Reihenfolge
1. Parallel: #319, #320, #331 Teil A+B.
2. #332 Stufe 1 (nach Merge von #331 Teil A wegen `GitHubKit`).
3. #331 Teil C (Treffer öffnen #332), dann #332 Stufe 2/3.
