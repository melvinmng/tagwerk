import SwiftUI
import GitHubKit
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
                    .foregroundStyle(.secondaryText)
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
                    if let progress {
                        Text("·")
                        Image(systemName: "circle.lefthalf.filled").imageScale(.small)
                        Text(TaskRowText.statusText(progress))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondaryText)
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
        // One element per row (screen reader, Voice Control, audit): the circle, due date, priority and list were
        // separate elements. The circle stays a button for touch; "Erledigt" is an action of the row.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TaskRowText.accessibilityLabel(item: item, isRecurring: isRecurring, now: now, calendar: calendar))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text(isReadOnly ? "Nur lesbar, GitHub offline" : "Erledigt"), onComplete)
        .accessibilityIdentifier(AccessibilityID.Tasks.row(item.title))
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

    /// GitHub issues in work show the stage of their project (GH4c).
    private var progress: GitHubMapping.ProgressStatus? {
        item.id.source == .github ? GitHubMapping.progressStatus(of: item.statuses) : nil
    }

    private var dueColor: Color {
        switch section {
        case .overdue: .red
        case .today: .orange
        default: .secondary
        }
    }
}

/// The spoken text of a task row: title, due date, repeat, priority, list and project status, in this order.
enum TaskRowText {
    static func accessibilityLabel(item: TaskItem, isRecurring: Bool, now: Date, calendar: Calendar,
                                   locale: Locale = .current) -> String {
        var parts = [item.title]
        if let due = item.due {
            let dueText = DueText.text(due, now: now, calendar: calendar, locale: locale)
            parts.append(String(localized: "fällig \(dueText)"))
        }
        if isRecurring { parts.append(String(localized: "wiederkehrend")) }
        if let priority = item.priority { parts.append(String(localized: "Priorität \(priority.rawValue)")) }
        parts.append(item.container.name)
        if item.id.source == .github, let progress = GitHubMapping.progressStatus(of: item.statuses) {
            switch progress {
            case .stage(let name): parts.append(String(localized: "Status \(name)"))
            case .several: parts.append(statusText(progress))
            }
        }
        return parts.joined(separator: ", ")
    }

    /// The stage in work, or the count of different stages: "In Progress", "2 Status".
    static func statusText(_ status: GitHubMapping.ProgressStatus) -> String {
        switch status {
        case .stage(let name): name
        case .several(let count): String(localized: "\(count) Status")
        }
    }
}
