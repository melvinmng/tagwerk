import RemindersKit
import SwiftUI

/// Multiple choice of calendars or reminder lists. `nil` selection means "use the default".
struct SourceSelectionView: View {
    let title: LocalizedStringKey
    let items: [ListInfo]
    let defaultSelection: Set<String>
    @Binding var selection: [String]?
    /// Entries that cannot be chosen here, with the note shown instead of the checkmark
    /// (the shopping list among the reminder lists).
    var lockedIDs: [String: LocalizedStringKey] = [:]

    var body: some View {
        List(items) { item in
            if let note = lockedIDs[item.id] {
                HStack {
                    Circle().fill(.secondary.opacity(0.5)).frame(width: 10, height: 10)
                    Text(item.title)
                    Spacer()
                    Text(note).font(.subheadline)
                }
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .combine)
            } else {
                Button {
                    toggle(item.id)
                } label: {
                    HStack {
                        Circle().fill(Color(hex: item.colorHex) ?? .accentColor).frame(width: 10, height: 10)
                        Text(item.title).foregroundStyle(.primary)
                        Spacer()
                        if current.contains(item.id) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("Keine Einträge", systemImage: "calendar",
                                       description: Text("Erlaube den Zugriff unter „Zugriff“."))
            }
        }
        .navigationTitle(title)
    }

    private var current: Set<String> {
        selection.map(Set.init) ?? defaultSelection
    }

    private func toggle(_ id: String) {
        var updated = current
        if updated.contains(id) { updated.remove(id) } else { updated.insert(id) }
        selection = updated.sorted()
    }
}
