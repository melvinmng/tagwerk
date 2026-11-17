import SwiftUI
import TagwerkCore

/// Important deadlines of the coming days (mockup a); hidden when there are none.
struct DeadlineCard: View {
    let deadlines: [ImportantDeadline]
    let today: PlanDay
    let calendar: Calendar

    var body: some View {
        if !deadlines.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("Deadlines", systemImage: "flag.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.red)
                ForEach(deadlines) { deadline in
                    HStack(alignment: .firstTextBaseline) {
                        Image(systemName: deadline.kind == .epic ? "diamond.fill" : "flag.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(deadline.title).font(.subheadline.weight(.semibold))
                            Text(kindText(deadline)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(relative(deadline.day)).font(.caption.weight(.semibold)).foregroundStyle(.red)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(12)
            .background(Color.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
    }

    private func kindText(_ deadline: ImportantDeadline) -> String {
        let time = deadline.time.map { ", " + $0.formatted(date: .omitted, time: .shortened) } ?? ""
        switch deadline.kind {
        case .priorityOne: return "P1" + time
        case .epic: return "Epic" + time
        case .deadlineCalendar: return "Kalender" + time
        }
    }

    private func relative(_ day: PlanDay) -> String {
        let days = calendar.dateComponents([.day], from: today.startDate(in: calendar), to: day.startDate(in: calendar)).day ?? 0
        switch days {
        case ..<0: return "überfällig"
        case 0: return "heute"
        case 1: return "morgen"
        default: return "in \(days) Tagen"
        }
    }
}
