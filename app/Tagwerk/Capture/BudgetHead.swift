import SwiftUI
import TagwerkCore

/// The budget of the day head (decision BU4b): the line "Ziel + Aktiv − Gegessen = Noch" and the budget bar. The line is one
/// element for VoiceOver with a spoken sentence; a tap on it opens the breakdown of the active energy.
struct BudgetHead: View {
    let budget: EnergyBudget
    /// The permission for the active energy was not asked yet: the line offers "In Health erlauben".
    let offersAllow: Bool
    let onShowActive: () -> Void
    let onAllow: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private struct Term: Identifiable {
        let id: String
        let label: LocalizedStringKey
        let value: String
        var isOver = false
        var opensBreakdown = false
    }

    var body: some View {
        let equation = IntakeFormat.budgetEquation(budget)
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onShowActive) {
                line(terms(equation))
            }
            // Borderless: only the line reacts, not the whole summary row.
            .buttonStyle(.borderless)
            .tint(.primary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(equation.spoken)
            .accessibilityHint("Zeigt, woraus die Aktivität besteht")
            .accessibilityIdentifier(AccessibilityID.Capture.budgetLine)
            BudgetBar(budget: budget).accessibilityHidden(true)
            footnote
        }
    }

    private func terms(_ equation: BudgetEquation) -> [Term] {
        var result = [Term(id: "goal", label: "Ziel", value: equation.goal)]
        if let active = equation.active {
            result.append(Term(id: "active", label: "+ Aktiv", value: active, opensBreakdown: true))
        }
        result.append(Term(id: "eaten", label: "− Gegessen", value: equation.eaten))
        result.append(Term(id: "remaining", label: equation.isOver ? "= Über" : "= Noch", value: equation.remaining, isOver: equation.isOver))
        return result
    }

    /// One row of terms when they fit, two rows next, one term per row at the largest text sizes.
    @ViewBuilder
    private func line(_ terms: [Term]) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) { ForEach(terms) { cell($0) } }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) { ForEach(terms.prefix(2)) { cell($0) } }
                HStack(alignment: .top, spacing: 12) { ForEach(terms.dropFirst(2)) { cell($0) } }
            }
            VStack(alignment: .leading, spacing: 4) { ForEach(terms) { row($0) } }
        }
    }

    private func cell(_ term: Term) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(term.label).font(.caption).foregroundStyle(.secondaryText)
                if term.opensBreakdown {
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.tertiary)
                }
            }
            Text(term.value)
                .font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(term.isOver ? Color.orangeText : Color.primary)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(_ term: Term) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(term.label).font(.subheadline).foregroundStyle(.secondaryText)
            Spacer()
            Text(term.value).font(.title3.weight(.semibold)).monospacedDigit()
                .foregroundStyle(term.isOver ? Color.orangeText : Color.primary)
        }
    }

    /// "In Health erlauben" while the active energy was not asked; a note when Health gives no value.
    @ViewBuilder
    private var footnote: some View {
        if offersAllow {
            Button(action: onAllow) {
                Text("Aktivität in Health erlauben \(Image(systemName: "chevron.right"))")
                    .font(.subheadline.weight(.medium))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Aktivität in Health erlauben")
            .accessibilityIdentifier(AccessibilityID.Capture.allowActiveEnergy)
        } else if budget.creditPercent > 0, !budget.active.isFromHealth {
            Text(budget.active.unsyncedOwnKcal > 0
                 ? "Health liefert keine Aktivität. Es zählen nur Trainings aus Tagwerk."
                 : "Health liefert keine Aktivität.")
                .font(.caption).foregroundStyle(.secondaryText)
        }
    }
}

/// The budget as a bar: what was eaten, a mark at the base goal and, hatched, what the activity added (decision BU4b).
private struct BudgetBar: View {
    let budget: EnergyBudget

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            // Over the budget the bar scales to what was eaten, so the excess stays visible.
            let scale = max(Double(budget.budget), budget.eatenKcal, 1)
            let eatenWidth = width * min(1, budget.eatenKcal / scale)
            let baseX = width * min(1, Double(budget.base) / scale)
            let budgetX = width * min(1, Double(budget.budget) / scale)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.18))
                if budget.credited > 0 {
                    Hatch(color: .green.opacity(0.5))
                        .frame(width: max(0, budgetX - baseX))
                        .offset(x: baseX)
                }
                Capsule().fill(budget.isOver ? Color.orange : Color.green).frame(width: eatenWidth)
                if budget.credited > 0 {
                    Rectangle().fill(Color.primary.opacity(0.7)).frame(width: 2).offset(x: max(0, baseX - 1))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

/// Diagonal stripes for the part of the budget that comes from activity.
private struct Hatch: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            var x = -size.height
            while x < size.width {
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                context.stroke(path, with: .color(color), lineWidth: 1.5)
                x += 5
            }
        }
    }
}
