import SwiftUI
import TagwerkCore

/// The sheet for one item of the share inbox (plan P6, task 5). It shows the sheet that fits the chosen target, filled in
/// from the item. Nothing is saved before the user confirms there; "Verwerfen" removes the item with its files.
struct ShareImportSheet: View {
    @Environment(AppEnvironment.self) private var environment
    let item: ShareInboxItem

    var body: some View {
        switch item.target {
        case .task:
            NewTaskSheet(model: environment.taskList, prefilledTitle: item.title, onCreated: finish,
                         prefilledNotes: Self.taskNotes(for: item), prefilledURL: item.url, onDiscard: finish)
        case .note:
            ShareNoteSheet(item: item, onFinished: finish)
        case .shopping:
            ShareShoppingSheet(item: item, onFinished: finish)
        case .recipe:
            RecipeSheet(model: environment.shopping, onFinished: { _ in finish() }, start: recipeStart, onDiscard: finish)
        case .mailTask:
            MailTaskFlow(model: environment.makeMailTaskModel(for: item), onFinished: finish, onDiscard: finish)
        }
    }

    private func finish() { environment.shareInbox.finish(item.id) }

    /// Notes of a task made from a shared item: the text without its title line; for a mail the sender and the link back.
    static func taskNotes(for item: ShareInboxItem) -> String? {
        if let mail = item.mail {
            var lines: [String] = []
            if let sender = mail.senderName { lines.append(String(localized: "Von: \(sender)")) }
            if let messageID = mail.messageID, let link = MailLink.url(messageID: messageID) { lines.append(link.absoluteString) }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        return NewTaskPrefill.sharedNotes(title: item.title, text: item.text)
    }

    /// A link wins over text, text over a photo.
    private var recipeStart: RecipeStart? {
        if let url = item.url { return .link(url.absoluteString) }
        if let text = item.text, !text.isEmpty { return .text(text) }
        // Every picture of the item, in order, as the pages of one recipe (the sheet takes the first few).
        let images = item.files.prefix(RecipePhotos.maximumCount).compactMap { file -> UIImage? in
            guard let url = environment.shareInbox.url(for: file, in: item), let data = try? Data(contentsOf: url) else { return nil }
            return UIImage(data: data)
        }
        return images.isEmpty ? nil : .photos(images)
    }
}
