import SwiftUI

/// The hits of the settings search, shown over the settings list while a text is typed. A tap opens the page or scrolls to the row.
struct SettingsSearchResults: View {
    let query: String
    let onSelect: (SettingsSearchHit) -> Void
    @Environment(\.dismissSearch) private var dismissSearch

    var body: some View {
        let hits = SettingsSearchIndex.hits(for: query)
        List {
            if !hits.isEmpty {
                Section {
                    ForEach(hits) { hit in
                        Button {
                            dismissSearch()
                            onSelect(hit)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(hit.title)
                                    if !hit.pathText.isEmpty {
                                        Text(hit.pathText).font(.caption).foregroundStyle(.secondaryText)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.secondaryText).accessibilityHidden(true)
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                        .tint(.primary)
                        .accessibilityLabel(hit.pathText.isEmpty ? hit.title : "\(hit.title), \(hit.pathText)")
                    }
                } header: {
                    Text("Einstellungen (\(hits.count))").foregroundStyle(.secondaryText)
                }
            }
        }
        .overlay {
            if hits.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .listStyle(.insetGrouped)
        .background(Color(.systemGroupedBackground))
    }
}
