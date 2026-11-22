import SwiftUI
import TagwerkCore

/// "Anderes …" of the start sheet: all 66 books in "Altes Testament" and "Neues Testament" with a search field that also
/// finds abbreviations ("Offb", "1 Kor").
struct BibleBookPicker: View {
    let selected: BibleBook
    let onSelect: (BibleBook) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var searchText = ""

    var body: some View {
        let books = BibleBooks.search(searchText)
        List {
            section("Altes Testament", books.filter(\.isOldTestament))
            section("Neues Testament", books.filter { !$0.isOldTestament })
            if books.isEmpty {
                Text("Kein Buch gefunden.").foregroundStyle(.secondaryText)
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Buch suchen")
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationTitle("Buch")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ books: [BibleBook]) -> some View {
        if !books.isEmpty {
            Section(title) {
                ForEach(books) { book in
                    Button {
                        onSelect(book)
                        dismiss()
                    } label: {
                        HStack {
                            Text(book.name(locale: locale))
                            Spacer()
                            if book == selected { Image(systemName: "checkmark").accessibilityHidden(true) }
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .tint(.primary)
                    .accessibilityAddTraits(book == selected ? .isSelected : [])
                }
            }
        }
    }
}
