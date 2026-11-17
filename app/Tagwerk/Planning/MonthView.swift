import SwiftUI
import TagwerkCore

/// Month view (mockup c-A): load bar per day, deadline days filled red, deadline list below.
struct MonthView: View {
    @Bindable var model: PlanningModel
    let onSelectDay: (PlanDay) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
                ForEach(model.days) { plan in
                    Button { onSelectDay(plan.day) } label: { cell(plan) }
                        .buttonStyle(.plain)
                        .dropDestination(for: String.self) { keys, _ in
                            let ids = keys.compactMap(TaskID.init(key:))
                            Task { for id in ids { await model.assign(id, to: plan.day) } }
                            return !ids.isEmpty
                        }
                }
            }
            .padding(.horizontal)

            let deadlines = model.days.flatMap(\.deadlines)
            if !deadlines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Deadlines").font(.headline)
                    ForEach(deadlines) { deadline in
                        HStack {
                            Text(deadline.day.startDate(in: model.calendar).formatted(.dateTime.day().month()))
                                .font(.caption.monospacedDigit()).frame(width: 52, alignment: .leading)
                            Label(deadline.title, systemImage: deadline.kind == .epic ? "diamond.fill" : "flag.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
        }
        .safeAreaInset(edge: .bottom) { UnplannedTray(model: model) }
    }

    private func cell(_ plan: DayPlan) -> some View {
        let inMonth = plan.day.month == model.anchor.month
        let hasDeadline = !plan.deadlines.isEmpty
        return VStack(spacing: 4) {
            Text("\(plan.day.day)")
                .font(.callout.weight(plan.day == model.today ? .bold : .regular))
                .foregroundStyle(hasDeadline ? .white : (inMonth ? .primary : .secondary))
            CapacityBar(capacity: plan.capacity).frame(width: 28)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(hasDeadline ? Color.red.opacity(0.85) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(plan.day == model.today ? Color.accentColor : .clear, lineWidth: 2))
        .opacity(inMonth ? 1 : 0.45)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(plan.day.startDate(in: model.calendar).formatted(date: .complete, time: .omitted))
        .accessibilityValue((hasDeadline ? "Deadline, " : "") + CapacityText.summary(plan.capacity))
    }
}
