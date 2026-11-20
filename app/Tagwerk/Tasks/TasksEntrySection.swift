import RemindersKit
import SwiftUI
import TagwerkCore

/// What the shopping row at the head of "Aufgaben" shows.
enum ShoppingEntryState: Equatable {
    /// No full access to Reminders: the row is missing.
    case hidden
    /// Exactly one list looks like a shopping list and nothing was chosen or declined yet.
    case suggestion(listID: String, title: String)
    /// "Einkaufsliste einrichten"; with a hint when the chosen list no longer exists.
    case setup(previousListMissing: Bool)
    case list(subtitle: String, openCount: Int)

    /// `lists` are all reminder lists.
    @MainActor
    static func make(access: AccessState, setupCompleted: Bool, lists: [ListInfo], settings: AppSettings,
                     model: ShoppingModel) -> ShoppingEntryState {
        guard access == .fullAccess else { return .hidden }
        if let chosen = settings.shoppingListID {
            guard lists.contains(where: { $0.id == chosen }) else { return .setup(previousListMissing: true) }
            return .list(subtitle: subtitle(openNames: model.openItems.map(\.name)), openCount: model.openItems.count)
        }
        if setupCompleted, !settings.shoppingSuggestionDismissed, let suggested = ShoppingListFilter.suggestedList(in: lists) {
            return .suggestion(listID: suggested.id, title: suggested.title)
        }
        return .setup(previousListMissing: false)
    }

    /// The first three names, e.g. "Hafermilch, Bananen, Eier und 4 weitere".
    static func subtitle(openNames: [String]) -> String {
        guard !openNames.isEmpty else { return String(localized: "Nichts offen") }
        let shown = openNames.prefix(3).joined(separator: ", ")
        let rest = openNames.count - 3
        return rest > 0 ? shown + " " + String(localized: "und \(rest) weitere") : shown
    }
}

/// "2 von 3" for the reminder lists that feed tasks; the shopping list is not counted.
enum ReminderListSummary {
    static func text(selected: [String]?, lists: [ListInfo], shopping: String?) -> String {
        let available = lists.map(\.id).filter { $0 != shopping }
        guard !available.isEmpty else { return "–" }
        let count = selected.map { Set($0).intersection(available).count } ?? available.count
        return String(localized: "\(count) von \(available.count)")
    }
}

/// The section at the head of "Aufgaben": the shopping list and the notes, each opening its own page.
struct TasksEntrySection: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Open reminders of the suggested list, read once for the suggestion card.
    @State private var suggestedOpenCount: Int?

    var body: some View {
        Section {
            shoppingRow
            notesRow
        }
    }

    private var entryState: ShoppingEntryState {
        let store = environment.reminderStore
        let access = store.accessState
        return ShoppingEntryState.make(access: access, setupCompleted: environment.settings.setupCompleted,
                                       lists: access == .fullAccess ? store.lists() : [],
                                       settings: environment.settings, model: environment.shopping)
    }

    @ViewBuilder private var shoppingRow: some View {
        switch entryState {
        case .hidden:
            EmptyView()
        case .suggestion(let listID, let title):
            suggestionCard(listID: listID, title: title)
        case .setup(let previousListMissing):
            Button {
                environment.tasksPath.append(.shoppingSettings)
            } label: {
                entryLabel(symbol: "cart", title: "Einkaufsliste einrichten",
                           subtitle: previousListMissing ? String(localized: "Die bisherige Liste gibt es nicht mehr.") : nil,
                           trailing: nil)
            }
        case .list(let subtitle, let openCount):
            Button {
                environment.tasksPath.append(.shopping)
            } label: {
                entryLabel(symbol: "cart", title: "Einkaufsliste", subtitle: subtitle,
                           trailing: openCount > 0 ? String(localized: "\(openCount) offen") : nil)
            }
        }
    }

    private var notesRow: some View {
        Button {
            environment.tasksPath.append(.notes)
        } label: {
            let notes = environment.notes
            entryLabel(symbol: "note.text", title: "Notizen",
                       subtitle: NotesListView.entrySubtitle(latest: notes.latest, now: .now, calendar: environment.planning.calendar),
                       trailing: notes.count > 0 ? "\(notes.count)" : nil)
        }
    }

    private func entryLabel(symbol: String, title: LocalizedStringKey, subtitle: String?, trailing: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).foregroundStyle(.tint).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                }
            }
            Spacer(minLength: 8)
            if let trailing {
                Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func suggestionCard(listID: String, title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Liste „\(title)“ als Einkaufsliste verwenden?", systemImage: "cart").font(.headline)
            Text(Self.suggestionText(openCount: suggestedOpenCount)).font(.subheadline).foregroundStyle(.secondary)
            HStack {
                Button("Verwenden") { Task { await environment.setShoppingList(listID) } }
                    .buttonStyle(.borderedProminent)
                Button("Andere Liste …") { environment.tasksPath.append(.shoppingSettings) }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Nicht jetzt") { environment.settings.shoppingSuggestionDismissed = true }
                    .buttonStyle(.borderless)
            }
            .font(.subheadline)
        }
        .padding(.vertical, 4)
        .task(id: listID) {
            // Its own query: the suggested list need not be among the lists chosen for tasks.
            suggestedOpenCount = await environment.reminderStore.openReminders(in: [listID]).count
        }
    }

    /// The explanation of the suggestion card; the count follows once it is known.
    static func suggestionText(openCount: Int?) -> String {
        let explanation = String(localized: "Sie erscheint dann hier als eigene Liste und nicht mehr unter den Aufgaben.")
        guard let openCount else { return explanation }
        return explanation + " " + String(localized: "\(openCount) offene Erinnerungen.")
    }
}
