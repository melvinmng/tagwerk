import SwiftUI
import TagwerkCore

/// One task in the list: completion circle, title, due date, container and priority.
struct TaskRow: View {
    let item: TaskItem
    let section: TaskSection
    let now: Date
    let calendar: Calendar
    var isReadOnly = false
    /// Repeating task (reminder or local): marked with ↻ (design §13.8).
    var isRecurring = false
    /// Title with highlighted passages (search); replaces the plain title, the issue number stays in front.
    var titleText: AttributedString?
    let onComplete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: isReadOnly ? "circle.dashed" : "circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .opacity(isReadOnly ? 0.45 : 1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isReadOnly ? "Nur lesbar, GitHub offline" : "Erledigt")

            VStack(alignment: .leading, spacing: 2) {
                titleLine
                HStack(spacing: 6) {
                    if isRecurring {
                        Image(systemName: "arrow.trianglehead.2.clockwise").accessibilityLabel("wiederkehrend")
                    }
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

    private var titleLine: Text {
        guard let titleText else { return Text(displayTitle) }
        return Text(issuePrefix) + Text(titleText)
    }

    /// "#42 " for GitHub issues, otherwise empty.
    private var issuePrefix: String {
        guard item.id.source == .github, let number = item.url?.lastPathComponent, Int(number) != nil else { return "" }
        return "#\(number) "
    }

    /// GitHub issues show their number, as in "#42 Login-Fehler beheben".
    private var displayTitle: String {
        guard item.id.source == .github, let number = item.url?.lastPathComponent, Int(number) != nil else { return item.title }
        return "#\(number) \(item.title)"
    }

    private var dueColor: Color {
        switch section {
        case .overdue: .red
        case .today: .orange
        default: .secondary
        }
    }
}
