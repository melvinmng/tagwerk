import Foundation

/// What the share sheet says below the title. Cases only; the extension owns the wording and its translation.
public enum ShareHint: Equatable, Sendable {
    /// "Text und Link gehen mit. In Tagwerk wählst du, ob die Zutaten auf die Einkaufsliste kommen."
    case recipeChoiceLater
    /// "Text und Link gehen mit."
    case textAndLink
    /// "Jede Zeile wird ein Artikel."
    case linesBecomeItems
    /// "Tagwerk zeigt dir die Mail und schlägt eine Aufgabe vor."
    case mailContinuesInApp
    /// "Dateien werden nur bei Notizen und Rezepten übernommen."
    case filesDropped
}

/// Rules for the texts of the share sheet that can be tested without the extension (it has no test target).
public enum ShareSheetText {
    /// The hints for the chosen target, in display order. Files are taken over only by notes and recipes; a mail file is the
    /// mail itself, so it is never reported as dropped.
    public static func hints(target: ShareTarget, hasFiles: Bool, hasText: Bool, hasURL: Bool) -> [ShareHint] {
        var hints: [ShareHint] = []
        switch target {
        case .recipe:
            hints.append(.recipeChoiceLater)
        case .task, .note:
            if hasText || hasURL { hints.append(.textAndLink) }
        case .shopping:
            hints.append(.linesBecomeItems)
        case .mailTask:
            hints.append(.mailContinuesInApp)
        }
        if hasFiles, target == .task || target == .shopping { hints.append(.filesDropped) }
        return hints
    }

    /// SF Symbol of a target tile.
    public static func symbol(for target: ShareTarget) -> String {
        switch target {
        case .task: "checklist"
        case .note: "square.and.pencil"
        case .shopping: "cart"
        case .recipe: "fork.knife"
        case .mailTask: "envelope"
        }
    }
}
