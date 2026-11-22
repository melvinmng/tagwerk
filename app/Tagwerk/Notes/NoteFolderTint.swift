import SwiftUI
import TagwerkCore

/// Colours of the folder symbols on the notes entry page. The routine folders have their own named colours (design NO2b);
/// every other folder keeps the accent colour. The values live in the colour catalog `Design/Colors.xcassets` with a
/// light and a dark value; `NoteFolderTintTests` holds each of them to 3:1 against the list backgrounds.
enum NoteFolderTint {
    /// Catalog names of the routine folder colours, also used by the contrast test.
    static let brainDumpName = "FolderBrainDump"
    static let morningName = "FolderMorning"
    static let eveningName = "FolderEvening"

    /// The catalog name of a role's colour; `nil` for the roles that use the accent colour.
    static func assetName(for role: NoteFolderRole?) -> String? {
        switch role {
        case .brainDump: brainDumpName
        case .morningRoutine: morningName
        case .eveningRoutine, .dreamLog: eveningName
        case .journal, .bibleStudy, .recipes, nil: nil
        }
    }

    static func color(for role: NoteFolderRole?) -> Color {
        assetName(for: role).map { Color($0) } ?? .accentColor
    }
}
