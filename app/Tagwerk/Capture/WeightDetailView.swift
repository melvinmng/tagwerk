import SwiftUI
import TagwerkCore

/// The weight (decisions KG3a and KG4b): chart with points, 7-day mean and goal line, the figures below it and the list of the
/// measurements with their source. Own entries are edited with a tap and deleted from their context menu, like the entries of the day.
struct WeightDetailView: View {
    @Bindable var model: TrendModel
    @State private var sheet: WeightSheetTarget?

    private struct WeightSheetTarget: Identifiable {
        let weight: WeightValue?
        var id: String { weight.map { $0.id.uuidString } ?? "new" }
    }

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: Binding(get: { model.weightPeriod }, set: { model.selectWeightPeriod($0) })) {
                    Text("Woche").tag(WeightPeriod.week)
                    Text("Monat").tag(WeightPeriod.month)
                    Text("3 Monate").tag(WeightPeriod.threeMonths)
                    Text("Jahr").tag(WeightPeriod.year)
                }
                .pickerStyle(.segmented)
                headline
                WeightChart(measurements: model.visibleMeasurements, meanLine: model.meanLine, targets: model.targetSegments,
                            period: model.weightPeriod, calendar: model.calendar, summary: model.weightSummary)
                if model.showsBodyFat { BodyFatChart(measurements: model.visibleMeasurements, calendar: model.calendar) }
            } footer: {
                Text("Punkte sind einzelne Messungen, die Linie ist der Mittelwert der letzten sieben Tage, gestrichelt das Zielgewicht. Das Gewicht schwankt von Tag zu Tag stärker, als es sich durch Fett verändert; der Mittelwert zeigt den Verlauf.")
            }
            figures
            if model.offersBodyAccess {
                Section {
                    Button("Gewicht aus Health lesen") { Task { await model.capture.allowBodyAccess(); await model.reload() } }
                } footer: {
                    Text("Tagwerk liest dann Messungen anderer Apps, zum Beispiel einer Waage. iOS teilt Tagwerk nicht mit, ob du das Lesen erlaubt hast; ohne Erlaubnis sieht es so aus, als gäbe es keine fremden Messungen.")
                }
            }
            measurementSection
        }
        .navigationTitle("Gewicht")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { sheet = WeightSheetTarget(weight: nil) } label: { Label("Gewicht erfassen", systemImage: "plus") }
            }
        }
        .sheet(item: $sheet) { target in
            WeightSheet(model: model.capture, existing: target.weight) { Task { await model.reload() } }
        }
        .safeAreaInset(edge: .bottom) {
            // Deleting here must be undoable here: the capsule of the tab lies behind this page.
            if let notice = model.capture.undo, case .restore = notice.action {
                UndoCapsule(title: notice.text, caption: "Gelöscht", symbol: "trash.circle.fill", duration: HealthMirror.undoWindow,
                            onUndo: { Task { await model.capture.undoLast(); await model.reload() } },
                            onExpire: { model.capture.clearUndo(notice) })
                    .id(notice.id)
            }
        }
        .task { await model.reload() }
    }

    @ViewBuilder
    private var headline: some View {
        if let mean = model.summary.mean {
            VStack(alignment: .leading, spacing: 2) {
                Text(WeightFormat.kilograms(mean)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("7-Tage-Mittel · heute").font(.subheadline).foregroundStyle(.secondaryText)
            }
            .accessibilityElement(children: .combine)
        } else if let latest = model.summary.latest {
            VStack(alignment: .leading, spacing: 2) {
                Text(WeightFormat.kilograms(latest.kilograms)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("Für ein 7-Tage-Mittel fehlen Messungen: es braucht mindestens drei in sieben Tagen.")
                    .font(.subheadline).foregroundStyle(.secondaryText)
            }
        } else {
            Text("Noch keine Messung.").foregroundStyle(.secondaryText)
        }
    }

    /// Target, change since the start, the trend of the last four weeks, the distance to the target and the projection.
    private var figures: some View {
        let summary = model.summary
        return Section {
            if let target = model.plan.targetWeightKg { figure("Ziel", WeightFormat.kilograms(target)) }
            figure("Seit Start", summary.sinceStart.map { WeightFormat.change($0) })
            figure("Trend · 4 Wochen", summary.trendPerWeek.map { WeightFormat.changePerWeek($0) })
            if let remaining = summary.remainingToTarget {
                figure(remaining <= 0 ? "Über dem Ziel" : "Unter dem Ziel", WeightFormat.distance(remaining))
            }
            if let projection = summary.projection {
                Text(WeightFormat.projection(projection, calendar: model.calendar)).font(.subheadline)
                Text("Eine gerade Fortschreibung des Trends, keine Vorhersage. Der tatsächliche Verlauf flacht meist ab.")
                    .font(.footnote).foregroundStyle(.secondaryText)
            }
            if let pace = model.paceLimit {
                Label {
                    Text(WeightFormat.paceHint(trend: pace.trend, limit: pace.limit))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.subheadline)
            }
        } header: {
            Text("Kennzahlen")
        } footer: {
            Text("„Seit Start“ vergleicht das heutige Mittel mit dem ersten Mittel, das es gibt. Tagwerk gibt keine medizinische Beratung.")
        }
    }

    private func figure(_ title: LocalizedStringKey, _ value: String?) -> some View {
        LabeledContent {
            Text(value ?? "–").monospacedDigit()
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    private var measurementSection: some View {
        Section {
            if model.measurementList.isEmpty {
                Text("Keine Messungen in diesem Zeitraum.").foregroundStyle(.secondaryText)
            }
            ForEach(model.measurementList) { measurement in
                if measurement.isOwn {
                    Button {
                        sheet = WeightSheetTarget(weight: WeightValue(id: measurement.id, date: measurement.date,
                                                                      kilograms: measurement.kilograms, bodyFatPercent: measurement.bodyFatPercent))
                    } label: { row(measurement) }
                        .tint(.primary)
                        .contextMenu {
                            Button(role: .destructive) {
                                Task { await model.capture.delete(measurement.id); await model.reload() }
                            } label: { Label("Löschen", systemImage: "trash") }
                        }
                } else {
                    row(measurement)
                }
            }
        } header: {
            Text("Messungen")
        } footer: {
            if model.measurementList.contains(where: { !$0.isOwn }) {
                Text("Messungen anderer Apps änderst oder löschst du in der App, die sie geschrieben hat.")
            }
        }
    }

    /// "18. Nov. 2026, 07:05" in the time zone of the app's calendar.
    private var measurementStyle: Date.FormatStyle {
        var style = Date.FormatStyle(date: .abbreviated, time: .shortened)
        style.timeZone = model.calendar.timeZone
        return style
    }

    private func row(_ measurement: WeightMeasurement) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(measurement.date.formatted(measurementStyle))
                Text(measurement.sourceName ?? String(localized: "Tagwerk")).font(.caption).foregroundStyle(.secondaryText)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(WeightFormat.kilograms(measurement.kilograms)).monospacedDigit()
                if model.settings.bodyFatEnabled, let fat = measurement.bodyFatPercent {
                    Text(WeightFormat.bodyFat(fat)).font(.caption).foregroundStyle(.secondaryText).monospacedDigit()
                }
            }
        }
    }
}
