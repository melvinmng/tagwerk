import Foundation

/// Pure rules of the data backup (#158): the file name, which files in a folder are Tagwerk's own, how many are kept, when a
/// new automatic backup is due and whether a file can be read.
public enum BackupRules {
    public static let format = "tagwerk-backup"
    /// The version of the file layout this app writes and reads. A higher version in a file is refused.
    public static let schemaVersion = 1
    /// Automatic backups at most this often.
    public static let automaticIntervalSeconds: TimeInterval = 24 * 60 * 60
    /// Automatic backups kept in the folder.
    public static let keptFiles = 7
    public static let fileExtension = "json"

    /// "Tagwerk-Sicherung-2026-11-19-1423.json", in the time zone of `calendar`.
    public static func fileName(for date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "Tagwerk-Sicherung-%04d-%02d-%02d-%02d%02d.json", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
                      parts.hour ?? 0, parts.minute ?? 0)
    }

    /// The name of the safety copy made before a restore. It does not follow the pattern of `isOwnFile`, so the clean-up of
    /// automatic backups never touches it.
    public static func safetyCopyName(for date: Date, calendar: Calendar) -> String {
        "Tagwerk-Vor-Wiederherstellung-" + fileName(for: date, calendar: calendar).dropFirst("Tagwerk-Sicherung-".count)
    }

    /// Whether a file name is exactly the pattern of `fileName(for:calendar:)`. Only such files are ever deleted.
    public static func isOwnFile(_ name: String) -> Bool {
        name.range(of: #"^Tagwerk-Sicherung-\d{4}-\d{2}-\d{2}-\d{4}\.json$"#, options: .regularExpression) != nil
    }

    /// The own files that go when only the newest `keeping` stay. The names sort by their time stamp; files that do not follow
    /// the pattern are never listed.
    public static func filesToDelete(names: [String], keeping: Int = keptFiles) -> [String] {
        let own = names.filter(isOwnFile).sorted(by: >)
        return Array(own.dropFirst(max(0, keeping)))
    }

    /// Whether an automatic backup is due: never made, or the last one is at least a day old (a clock set back counts as due).
    public static func isDue(lastBackup: Date?, now: Date) -> Bool {
        guard let lastBackup else { return true }
        let age = now.timeIntervalSince(lastBackup)
        return age >= automaticIntervalSeconds || age < 0
    }

    public enum Compatibility: Equatable, Sendable {
        case readable
        case notABackup
        /// The file was written by a newer version of the app than this one.
        case newerVersion(Int)
    }

    public static func compatibility(format: String, schemaVersion: Int) -> Compatibility {
        guard format == Self.format else { return .notABackup }
        return schemaVersion > Self.schemaVersion ? .newerVersion(schemaVersion) : .readable
    }
}
