import Foundation
import TagwerkCore

/// Pure rules for turning GitHub project data into tasks.
public enum GitHubMapping {
    public static let statusField = "Status"
    public static let priorityField = "Priority"
    public static let dueField = "Due date"
    public static let estimateHoursField = "Estimate (h)"
    public static let estimateDaysField = "Estimate (MDs)"
    /// Name of the option that marks an item as finished (compared without regard to case).
    public static let doneStatus = "Done"
    /// Preferred option for reopened and new issues; projects without it fall back to `reopenOption(in:)`.
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

    /// Whether `status` is the "Done" option (case-insensitive). No status counts as not done.
    public static func isDone(_ status: String?) -> Bool {
        status?.caseInsensitiveCompare(doneStatus) == .orderedSame
    }

    /// Option names of the Status field of `project` in board order; empty without a Status field.
    public static func statusOptions(in project: ProjectInfo) -> [String] {
        project.field(named: statusField)?.orderedOptions.map(\.name) ?? []
    }

    /// The name of the "Done" option as the project spells it, or `nil` when it has none.
    public static func doneOption(in project: ProjectInfo) -> String? {
        statusOptions(in: project).first(where: isDone)
    }

    /// Status for reopened issues and new issues without a chosen status: "Ready" when the project has
    /// it, otherwise the first option in board order that is not "Done"; `nil` without such an option.
    public static func reopenOption(in project: ProjectInfo) -> String? {
        startOption(in: statusOptions(in: project))
    }

    /// The start stage of a board: "Ready" when it has it, otherwise the first stage that is not "Done".
    static func startOption(in options: [String]) -> String? {
        options.first { $0.caseInsensitiveCompare(reopenStatus) == .orderedSame }
            ?? options.first { !isDone($0) }
    }

    /// What a task row says about the progress of an issue.
    public enum ProgressStatus: Equatable, Sendable {
        /// One stage in work, or the same one in every project: "In Progress".
        case stage(String)
        /// Different stages in work: "2 Status".
        case several(Int)
    }

    /// The stage is "in work" when it comes after the start stage (`startOption`) in board order and is not
    /// "Done". Stages before the start stage ("Backlog" before "Ready") and stages without a value do not count.
    public static func isInProgress(_ status: SubContainerStatus) -> Bool {
        guard let current = status.current, !isDone(current),
              let currentIndex = status.options.firstIndex(where: { $0.caseInsensitiveCompare(current) == .orderedSame }),
              let start = startOption(in: status.options),
              let startIndex = status.options.firstIndex(of: start) else { return false }
        return currentIndex > startIndex
    }

    /// The progress to show in the task row, or `nil` when no project has the issue in work.
    public static func progressStatus(of statuses: [SubContainerStatus]) -> ProgressStatus? {
        var stages: [String] = []
        for status in statuses where isInProgress(status) {
            guard let current = status.current else { continue }
            if !stages.contains(where: { $0.caseInsensitiveCompare(current) == .orderedSame }) { stages.append(current) }
        }
        switch stages.count {
        case 0: return nil
        case 1: return .stage(stages[0])
        default: return .several(stages.count)
        }
    }

    /// The option of `project` spelled like `name` (case-insensitive), or `nil`.
    public static func statusOption(named name: String, in project: ProjectInfo) -> String? {
        statusOptions(in: project).first { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Shown when the issue is open, assigned to `login`, and not "Done" in at least one project.
    public static func isVisible(_ record: GitHubIssueRecord, login: String) -> Bool {
        record.isOpen
            && record.assignees.contains(login)
            && record.placements.contains { !isDone($0.status) }
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
        if projects.contains(where: { !statusOptions(in: $0).isEmpty }) { editable.insert(.status) }

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
            assignees: record.assignees,
            statuses: placements.map { placement in
                SubContainerStatus(subContainerID: placement.project.id, subContainerName: placement.project.title,
                                   current: placement.status, options: statusOptions(in: placement.project),
                                   isWritable: placement.project.canWrite)
            }
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
