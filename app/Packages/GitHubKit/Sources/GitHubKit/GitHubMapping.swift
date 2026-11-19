import Foundation
import TagwerkCore

/// Pure rules for turning GitHub project data into tasks.
public enum GitHubMapping {
    public static let statusField = "Status"
    public static let priorityField = "Priority"
    public static let dueField = "Due date"
    public static let estimateHoursField = "Estimate (h)"
    public static let estimateDaysField = "Estimate (MDs)"
    public static let doneStatus = "Done"
    public static let reopenStatus = "Ready"
    /// Label that marks an epic (convention of t3gh).
    public static let epicLabel = "epic"
    /// A person-day ("MD") counts as 8 hours.
    static let minutesPerDay = 8 * 60

    public static func estimateMinutes(fieldName: String, value: Double) -> Int? {
        switch fieldName {
        case estimateHoursField: Int((value * 60).rounded())
        case estimateDaysField: Int((value * Double(minutesPerDay)).rounded())
        default: nil
        }
    }

    public static func fieldValue(fromMinutes minutes: Int, fieldName: String) -> Double {
        fieldName == estimateDaysField ? Double(minutes) / Double(minutesPerDay) : Double(minutes) / 60
    }

    /// Name of the estimate field of a project, if it has one.
    public static func estimateFieldName(in project: ProjectInfo) -> String? {
        [estimateHoursField, estimateDaysField].first { project.field(named: $0) != nil }
    }

    /// Reads "P1" … "P5" at the start of an option name such as "P2 (High)".
    public static func priority(fromOption name: String) -> Priority? {
        guard name.count >= 2, name.first == "P", let digit = Int(String(name[name.index(after: name.startIndex)])) else {
            return nil
        }
        return Priority(rawValue: digit)
    }

    /// Name of the option that represents `priority` in `project`.
    public static func priorityOption(_ priority: Priority, in project: ProjectInfo) -> String? {
        project.field(named: priorityField)?.options.keys.sorted().first { self.priority(fromOption: $0) == priority }
    }

    /// Shown when the issue is open, assigned to `login`, and not "Done" in at least one project.
    public static func isVisible(_ record: GitHubIssueRecord, login: String) -> Bool {
        record.isOpen
            && record.assignees.contains(login)
            && record.placements.contains { $0.status != doneStatus }
    }

    public static func taskItem(_ record: GitHubIssueRecord) -> TaskItem {
        let placements = record.placements.sorted { $0.project.number < $1.project.number }
        let due = placements.compactMap(\.due).min { lhs, rhs in
            (lhs.year, lhs.month, lhs.day, lhs.hour ?? 0, lhs.minute ?? 0) < (rhs.year, rhs.month, rhs.day, rhs.hour ?? 0, rhs.minute ?? 0)
        }
        var editable: Set<TaskField> = [.title, .notes, .labels, .assignees]
        // Only projects the login may change count for editing (readable foreign boards may be read-only).
        let projects = placements.map(\.project).filter(\.canWrite)
        if projects.contains(where: { $0.field(named: dueField) != nil }) { editable.insert(.due) }
        if projects.contains(where: { $0.field(named: priorityField) != nil }) { editable.insert(.priority) }
        if projects.contains(where: { estimateFieldName(in: $0) != nil }) { editable.insert(.estimate) }

        return TaskItem(
            id: TaskID(source: .github, rawValue: record.issueID),
            title: record.title,
            notes: record.body,
            due: due,
            priority: placements.compactMap(\.priority).min(),
            estimateMinutes: placements.lazy.compactMap(\.estimateMinutes).first,
            isCompleted: !record.isOpen,
            container: TaskContainer(id: record.repository, name: record.repository, colorHex: nil),
            url: record.url,
            version: version(record),
            editableFields: editable,
            subContainers: placements.filter(\.project.canWrite)
                .map { TaskContainer(id: $0.project.id, name: $0.project.title, colorHex: nil) },
            labels: record.labels,
            epic: record.parent.map {
                EpicInfo(id: $0.id, number: $0.number, title: $0.title, due: $0.due, isEpic: $0.labels.contains(epicLabel))
            },
            isEpic: record.labels.contains(epicLabel),
            assignees: record.assignees
        )
    }

    /// Changes whenever the issue or any of its project items changes.
    static func version(_ record: GitHubIssueRecord) -> String {
        let formatter = ISO8601DateFormatter()
        let items = record.placements.sorted { $0.itemID < $1.itemID }.map { formatter.string(from: $0.itemUpdatedAt) }
        return ([formatter.string(from: record.updatedAt)] + items).joined(separator: "|")
    }

    /// Projects selected by default: those holding at least one visible issue (design §12.1).
    public static func defaultSelectedProjectIDs(projects: [ProjectInfo], visibleIssues: [GitHubIssueRecord]) -> Set<String> {
        let used = Set(visibleIssues.flatMap { $0.placements.map(\.project.id) })
        return Set(projects.map(\.id)).intersection(used)
    }
}
