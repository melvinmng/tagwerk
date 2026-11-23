import SwiftUI
import TagwerkCore

/// "Verlauf und Ziele" (decision OR1a): the intake charts per period, the means of protein, fibre and water against the goals, and
/// the way to the weight. `planning` is the place for the entries of the goal planning (strand G): they come below the weight, so this
/// page needs no change when they arrive.
struct TrendView<Planning: View>: View {
    @Bindable var model: TrendModel
    @ViewBuilder var planning: () -> Planning

    var body: some View {
        List {
            Section {
                Picker("Zeitraum", selection: Binding(get: { model.period }, set: { period in Task { await model.select(period) } })) {
                    Text("Woche").tag(TrendPeriod.week)
                    Text("Monat").tag(TrendPeriod.month)
                    Text("Jahr").tag(TrendPeriod.year)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier(AccessibilityID.Trend.period)
            }
            Section {
                intakeHead
                IntakeChart(buckets: model.buckets, period: model.period, calendar: model.calendar, summary: model.intakeSummary)
            } footer: {
                Text("Mittel über die Tage mit Einträgen. Tage ohne Einträge sind Lücken, nicht null. Das Budget ist das Tagesbudget des jeweiligen Tages.")
            }
            Section {
                meanRow("Eiweiß", value: model.means.protein.map { IntakeFormat.grams($0, estimated: true) },
                        goal: model.plan.proteinGrams.map { IntakeFormat.grams(Double($0), estimated: false) })
                meanRow("Ballaststoffe", value: model.means.fiber.map { IntakeFormat.grams($0, estimated: true) },
                        goal: model.plan.fiberGrams.map { IntakeFormat.grams(Double($0), estimated: false) })
                meanRow("Wasser", value: model.means.water.map { IntakeFormat.liters(Int($0.rounded())) },
                        goal: IntakeFormat.liters(model.plan.waterMilliliters))
            } header: {
                Text("Tagesmittel")
            }
            Section {
                NavigationLink {
                    WeightDetailView(model: model)
                } label: {
                    weightRow
                }
                .accessibilityIdentifier(AccessibilityID.Trend.weightRow)
            }
            planning()
        }
        .navigationTitle("Verlauf und Ziele")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.reload() }
        .refreshable { await model.reload() }
    }

    @ViewBuilder
    private var intakeHead: some View {
        if let mean = model.intakeMean {
            VStack(alignment: .leading, spacing: 2) {
                Text(IntakeFormat.kcal(mean.eaten, estimated: true)).font(.title2.weight(.semibold)).monospacedDigit()
                Text("Tagesmittel · Budget \(IntakeFormat.grouped(Int(mean.budget.rounded())))")
                    .font(.subheadline).foregroundStyle(.secondaryText)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("Keine Einträge in diesem Zeitraum.").foregroundStyle(.secondaryText)
        }
    }

    private func meanRow(_ title: LocalizedStringKey, value: String?, goal: String?) -> some View {
        LabeledContent {
            Text(Self.meanText(value: value, goal: goal)).monospacedDigit()
        } label: {
            Text(title)
        }
        .accessibilityElement(children: .combine)
    }

    /// "118 g / 140 g"; without a goal only the value; a dash without a value (a day mean is never 0 when nothing is known).
    static func meanText(value: String?, goal: String?) -> String {
        guard let value else { return "–" }
        guard let goal else { return value }
        return "\(value) / \(goal)"
    }

    private var weightRow: some View {
        HStack {
            Label("Gewicht", systemImage: "scalemass")
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let mean = model.summary.mean {
                    Text(WeightFormat.kilograms(mean)).monospacedDigit()
                } else if let latest = model.summary.latest {
                    Text(WeightFormat.kilograms(latest.kilograms)).monospacedDigit()
                } else {
                    Text("–").foregroundStyle(.secondaryText)
                }
                if let trend = model.summary.trendPerWeek {
                    Text(WeightFormat.changePerWeek(trend)).font(.caption).foregroundStyle(.secondaryText).monospacedDigit()
                }
            }
        }
    }
}

extension TrendView where Planning == EmptyView {
    init(model: TrendModel) { self.init(model: model, planning: { EmptyView() }) }
}
