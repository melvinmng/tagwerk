import Foundation
import TagwerkCore
import WidgetKit

/// The App Group shared with the widget extension; the identifier comes from Info.plist, never from code.
enum AppGroup {
    static var identifier: String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: WidgetSnapshot.appGroupInfoKey) as? String,
              value.hasPrefix("group."), !value.contains("$(") else { return nil }
        return value
    }

    /// `<container>/Library/Application Support`; `nil` when the group is missing (e.g. unsigned builds).
    static var snapshotDirectory: URL? {
        guard let identifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier) else { return nil }
        return container.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    }
}

/// Writes the widget snapshot file (phase 4 design §4.1). Logs nothing: the file holds titles and nutrition values.
@MainActor
final class WidgetSnapshotWriter {
    let directory: URL?
    private let reload: () -> Void
    private var lastFingerprint: Data?

    init(directory: URL?, reload: @escaping () -> Void) {
        self.directory = directory
        self.reload = reload
    }

    /// The real writer: the App Group container and WidgetKit's reload.
    static func live() -> WidgetSnapshotWriter {
        WidgetSnapshotWriter(directory: AppGroup.snapshotDirectory, reload: { WidgetCenter.shared.reloadAllTimelines() })
    }

    /// The file as it is now; `nil` when missing, unreadable or of an unknown version.
    func current() -> WidgetSnapshot? {
        WidgetSnapshot.load(from: directory)
    }

    /// Writes atomically and reloads the widgets only when the content (without the creation time) changed,
    /// to spare the reload budget. Without a container nothing happens.
    func write(_ snapshot: WidgetSnapshot) {
        guard var directory, let data = try? snapshot.encoded() else { return }
        let fingerprint = snapshot.contentFingerprint()
        let previous = lastFingerprint ?? current()?.contentFingerprint()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? directory.setResourceValues(values)
            // Readable after the first unlock, so the widget renders while the device is locked.
            try data.write(to: directory.appending(path: WidgetSnapshot.fileName),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            return
        }
        lastFingerprint = fingerprint
        if fingerprint != previous { reload() }
    }
}
