import SwiftUI
import TagwerkCore

/// One task in the list: completion circle, title, due date, container and priority.
struct TaskRow: View {
    let item: TaskItem
    let section: TaskSection
    let now: Date
    let calendar: Calendar
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Erledigt")

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                HStack(spacing: 6) {
                    if let due = item.due {
                        Text(DueText.text(due, now: now, calendar: calendar))
                            .foregroundStyle(dueColor)
                        Text("·")
                    }
                    Circle()
                        .fill(Color(hex: item.container.colorHex) ?? .accentColor)
                        .frame(width: 7, height: 7)
                    Text(item.container.name)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            if let priority = item.priority {
                Text(priority.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
        }
        .contentShape(Rectangle())
    }

    private var dueColor: Color {
        switch section {
        case .overdue: .red
        case .today: .orange
        default: .secondary
        }
    }
}
