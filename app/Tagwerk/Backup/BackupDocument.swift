import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// The password-encrypted backup (extension ".tagwerk"), exported in `project.yml`.
    static let tagwerkBackup = UTType(exportedAs: "de.tagwerk.backup", conformingTo: .data)
}

/// The file handed to the exporter of "Jetzt sichern": JSON or, with a password, the encrypted file.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .tagwerkBackup] }
    var data: Data
    /// The type of the file that is written: the encrypted file has its own.
    var contentType: UTType

    init(data: Data, encrypted: Bool = false) {
        self.data = data
        contentType = encrypted ? .tagwerkBackup : .json
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
        contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
