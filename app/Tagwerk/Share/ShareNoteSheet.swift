import SwiftUI
import TagwerkCore
import UniformTypeIdentifiers

/// A shared item as a note: text and link, pictures and files as attachments. The note is created when the user taps
/// "Sichern"; before that nothing is stored.
struct ShareNoteSheet: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    let item: ShareInboxItem
    let onFinished: () -> Void

    @State private var text: String
    @State private var failedNames: [String] = []
    @State private var showsFailures = false

    init(item: ShareInboxItem, onFinished: @escaping () -> Void) {
        self.item = item
        self.onFinished = onFinished
        _text = State(initialValue: Self.initialText(for: item))
    }

    /// Title, text without the title line, and the link; the attachments are added when saving.
    static func initialText(for item: ShareInboxItem) -> String {
        if let mail = item.mail {
            // A mail has no text of its own in the item; the note gets the readable text and the link back.
            let sender = mail.senderName.map { String(localized: "Von: \($0)") }
            let link = mail.messageID.flatMap { MailLink.url(messageID: $0) }?.absoluteString
            return [item.title, sender, mail.bodyText, link].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        guard let url = item.url else {
            return [item.title, NewTaskPrefill.sharedNotes(title: item.title, text: item.text)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        // The link is a line of its own, "[Seitentitel](https://…)", instead of the raw address. When its text is the title
        // of the item already (a plain page share), the title line would only repeat it.
        let linkTitle = Self.linkTitle(for: item)
        let link = NewTaskPrefill.markdownLink(title: linkTitle, url: url)
        let title = linkTitle == item.title ? nil : item.title
        return [title, NewTaskPrefill.sharedNotes(title: item.title, text: item.text), link]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    /// The text of the link: the title of the page if Safari told it. Otherwise the title of the item, but only when it is
    /// the page title that was shared as text (no text, or text equal to the title); a selection is no page title, then the
    /// host stands there (`nil`).
    static func linkTitle(for item: ShareInboxItem) -> String? {
        if let pageTitle = item.pageTitle, !pageTitle.isEmpty { return pageTitle }
        guard let text = item.text, !text.isEmpty else { return item.title }
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == item.title ? item.title : nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .keyboardDoneButton()
                }
                if !item.files.isEmpty {
                    Section("Anhänge") {
                        ForEach(item.files, id: \.relativePath) { file in
                            Label(file.name, systemImage: UTType(file.typeIdentifier)?.conforms(to: .image) == true ? "photo" : "doc")
                        }
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Neue Notiz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Verwerfen", role: .destructive) {
                        onFinished()
                        dismiss()
                    }
                }
            }
            .alert("Nicht alles konnte angehängt werden", isPresented: $showsFailures) {
                Button("OK") {
                    onFinished()
                    dismiss()
                }
            } message: {
                Text(failedNames.joined(separator: ", "))
            }
        }
    }

    private func save() {
        let store = environment.notes
        let note = store.createBlank()
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var failed: [String] = []
        for file in item.files {
            guard let url = environment.shareInbox.url(for: file, in: item), let attachments = store.attachments else {
                failed.append(file.name)
                continue
            }
            do {
                let isImage = UTType(file.typeIdentifier)?.conforms(to: .image) == true
                if isImage, let data = try? Data(contentsOf: url) {
                    let record = try attachments.addImage(data: data, to: note.id)
                    body += "\n\n" + MarkdownText.reference(for: record.id, name: String(localized: "Bild"), isImage: true)
                } else {
                    let record = try attachments.addFile(at: url, to: note.id)
                    body += "\n\n" + MarkdownText.reference(for: record.id, name: record.fileName, isImage: false)
                }
            } catch {
                failed.append(file.name)
            }
        }
        store.updateText(note.id, text: body)
        store.save()
        if failed.isEmpty {
            onFinished()
            dismiss()
        } else {
            failedNames = failed
            showsFailures = true
        }
    }
}
