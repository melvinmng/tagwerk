import SwiftUI
import TagwerkCore

/// Texts and ordering of the "Zugewiesen" row for GitHub issues (new task sheet, editor, capsule, assistant card).
enum AssigneeSelection {
    /// Menu order: the signed-in user first, then case-insensitive alphabetical. `me` is always offered when
    /// known, also when GitHub does not list it; a listed spelling wins over the known one.
    static func ordered(candidates: [String], me: String?) -> [String] {
        var all = candidates
        if let me, !AssigneeRules.contains(candidates, me) { all.append(me) }
        return sorted(all, me: me)
    }

    /// `logins` without duplicates, `me` first, the others alphabetical; nobody is added.
    static func sorted(_ logins: [String], me: String?) -> [String] {
        var seen = Set<String>()
        let unique = logins.filter { seen.insert($0.lowercased()).inserted }
        let mine = unique.filter { isMe($0, me: me) }
        let others = unique.filter { !isMe($0, me: me) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return mine + others
    }

    /// People of the draft. Until the user chose, the default "Ich" travels as `nil`: the provider then assigns the
    /// signed-in user, also when the login was not known yet while the sheet was open. An explicit choice, even
    /// "Niemand", is sent as it is.
    static func draftAssignees(selected: [String], chosen: Bool) -> [String]? {
        chosen ? selected : nil
    }

    /// Collapsed value of the row: "Niemand", "Ich", "Ich, lea-m", from three people on the count.
    static func value(selected: [String], me: String?) -> String {
        switch selected.count {
        case 0: String(localized: "Niemand")
        case 1, 2: sorted(selected, me: me).map { isMe($0, me: me) ? String(localized: "Ich") : $0 }.joined(separator: ", ")
        default: String(localized: "\(selected.count) Personen")
        }
    }

    /// Menu label of one login: "Ich (login)" for the signed-in user, else the login.
    static func label(_ login: String, me: String?) -> String {
        isMe(login, me: me) ? String(localized: "Ich (\(login))") : login
    }

    /// Footer of the new task sheet: says before saving who gets the issue and whether it stays in the list.
    static func footer(selected: [String], me: String?) -> String {
        if selected.isEmpty {
            return String(localized: "Das Issue wird niemandem zugewiesen und erscheint danach nicht in deinen Aufgaben.")
        }
        let people = names(selected: sorted(selected, me: me), me: me, summarize: true)
        if let me, AssigneeRules.contains(selected, me) {
            return String(localized: "Das Issue wird \(people) zugewiesen.")
        }
        return String(localized: "Das Issue wird \(people) zugewiesen und erscheint danach nicht in deinen Aufgaben.")
    }

    /// The people as one list in the dative, the signed-in user as "dir" in front: "dir, lea-m und jonas-k".
    /// With `summarize`, three or more other people become a count ("dir und 3 weiteren Personen", "3 Personen").
    static func names(selected: [String], me: String?, summarize: Bool, language: VoiceLanguage = .app) -> String {
        func text(_ key: String.LocalizationValue) -> String { Localized.string(key, in: language, bundle: .main) }
        let includesMe = selected.contains { isMe($0, me: me) }
        let others = selected.filter { !isMe($0, me: me) }
        var parts: [String] = includesMe ? [text("dir")] : []
        if summarize, others.count >= 3 {
            parts.append(includesMe ? text("\(others.count) weiteren Personen") : text("\(others.count) Personen"))
        } else {
            parts += others
        }
        return parts.formatted(.list(type: .and).locale(language == .app ? .current : language.locale))
    }

    /// Title of the "Vergeben" capsule: "#151 an lea-m", "#151 an 3 Personen", "#151 ohne Zuweisung".
    static func capsuleTitle(number: Int?, assignees: [String]) -> String {
        let issue = number.map { "#\($0)" } ?? "Issue"
        switch assignees.count {
        case 0: return String(localized: "\(issue) ohne Zuweisung")
        case 1, 2: return String(localized: "\(issue) an \(assignees.formatted(.list(type: .and)))")
        default: return String(localized: "\(issue) an \(String(localized: "\(assignees.count) Personen"))")
        }
    }

    /// Title of the capsule for an issue without a Project: "#151 angelegt · ohne Project".
    static func noProjectTitle(number: Int?) -> String {
        let issue = number.map { "#\($0)" } ?? "Issue"
        return String(localized: "\(issue) angelegt · ohne Project")
    }

    static func noProjectAnnouncement(number: Int?) -> String {
        String(localized: "Angelegt: \(noProjectTitle(number: number)). Auf GitHub öffnen verfügbar.")
    }

    /// VoiceOver announcement of the "Vergeben" capsule.
    static func announcement(number: Int?, assignees: [String]) -> String {
        String(localized: "Vergeben: \(capsuleTitle(number: number, assignees: assignees)). Auf GitHub öffnen verfügbar.")
    }

    /// No further person can be chosen once the limit of GitHub is reached.
    static func canAdd(selectedCount: Int) -> Bool {
        selectedCount < AssigneeRules.maximum
    }

    static func isMe(_ login: String, me: String?) -> Bool {
        me.map { $0.lowercased() == login.lowercased() } ?? false
    }
}

/// Load state of the assignable people of one repository.
enum AssigneeLoad: Equatable {
    case idle
    case loading(repository: String)
    case loaded(repository: String, logins: [String])
    case failed(repository: String)

    /// Adopts a result only when it belongs to the repository that is still selected; a late answer
    /// for a repository the user left meanwhile is discarded.
    func adopting(_ logins: [String]?, for repository: String, selected: String?) -> AssigneeLoad {
        guard repository == selected else { return self }
        return logins.map { .loaded(repository: repository, logins: $0) } ?? .failed(repository: repository)
    }

    /// The loaded logins when they belong to `repository`, else none.
    func logins(for repository: String?) -> [String] {
        if case .loaded(let loaded, let logins) = self, loaded == repository { return logins }
        return []
    }
}

/// The "Zugewiesen" row: a menu with toggles that stays open while choosing, like the project row.
struct AssigneeSelectionRow: View {
    /// Logins offered, already ordered.
    let candidates: [String]
    let me: String?
    /// Drives the disabled hint rows while loading and after a failed load.
    let load: AssigneeLoad
    @Binding var selection: Set<String>
    var isEnabled = true
    /// Nothing was chosen yet: the draft goes to the signed-in user, even if the login is not known yet.
    var showsDefaultMe = false

    private var selected: [String] { candidates.filter(selection.contains) }

    var body: some View {
        Menu {
            Section("Mehrere möglich · höchstens 10") {
                ForEach(candidates, id: \.self) { login in
                    Toggle(AssigneeSelection.label(login, me: me), isOn: Binding(
                        get: { selection.contains(login) },
                        set: { isOn in
                            if isOn { selection.insert(login) } else { selection.remove(login) }
                        }))
                        .disabled(!selection.contains(login) && !AssigneeSelection.canAdd(selectedCount: selection.count))
                }
                switch load {
                case .loading:
                    Button("Personen werden geladen …") {}.disabled(true)
                case .failed:
                    Button("Personen konnten nicht geladen werden") {}.disabled(true)
                case .idle, .loaded:
                    EmptyView()
                }
            }
        } label: {
            LabeledContent {
                HStack(spacing: 4) {
                    Text(showsDefaultMe ? String(localized: "Ich") : AssigneeSelection.value(selected: selected, me: me))
                    Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                }
                .lineLimit(1)
                .foregroundStyle(.secondary)
            } label: {
                Text("Zugewiesen").foregroundStyle(.primary)
            }
            .contentShape(Rectangle())
        }
        .menuActionDismissBehavior(.disabled)
        .disabled(!isEnabled)
        .accessibilityLabel("Zugewiesen")
        .accessibilityValue(showsDefaultMe ? String(localized: "Ich") : selected.isEmpty ? String(localized: "Niemand")
            : selected.map { AssigneeSelection.isMe($0, me: me) ? String(localized: "Ich") : $0 }.formatted(.list(type: .and)))
        .accessibilityHint("Mehrfachauswahl")
    }
}
