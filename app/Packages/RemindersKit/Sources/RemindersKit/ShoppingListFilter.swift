import Foundation
import TagwerkCore

/// Rules for the reminder list that serves as the shopping list: it is removed from the lists
/// that feed tasks, it never receives a new task, and it can be suggested by its title.
public enum ShoppingListFilter {
    /// Title prefixes (trimmed, lowercased) that mark a list as a shopping list candidate.
    static let suggestionPrefixes = ["einkauf", "einkäufe", "lebensmittel", "groceries", "grocery", "shopping"]

    /// Lists that feed tasks. Without a shopping list, or when `shopping` is not in `all`: `selected` unchanged.
    /// Otherwise `(selected ?? all)` without the shopping list; an empty set means "no list", not "all".
    public static func taskListIDs(selected: Set<String>?, all: [String], shopping: String?) -> Set<String>? {
        guard let shopping, all.contains(shopping) else { return selected }
        var result = selected ?? Set(all)
        result.remove(shopping)
        return result
    }

    /// List for a new reminder. `requested` wins unless it is the shopping list. `nil` lets the store pick its default.
    /// If the store's default is the shopping list, the first other selected list by title is used.
    public static func listForNewReminder(requested: String?, defaultListID: String?, shopping: String?,
                                          selected: Set<String>?, lists: [ListInfo]) throws -> String? {
        if let requested, requested != shopping { return requested }
        guard let shopping, defaultListID == shopping else { return nil }
        let candidates = lists
            .filter { $0.id != shopping && (selected?.contains($0.id) ?? true) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard let fallback = candidates.first else {
            throw TaskWriteError.failed(String(localized: "Keine Erinnerungsliste gefunden", bundle: .module))
        }
        return fallback.id
    }

    /// The one writable list whose title looks like a shopping list; `nil` for zero or several candidates.
    public static func suggestedList(in lists: [ListInfo]) -> ListInfo? {
        let candidates = lists.filter { list in
            guard list.isWritable else { return false }
            let title = list.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return suggestionPrefixes.contains { title.hasPrefix($0) }
        }
        return candidates.count == 1 ? candidates[0] : nil
    }
}
