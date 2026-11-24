import Foundation

/// Pure rules of the data backup (#158): the file name, which files in a folder are Tagwerk's own, how many are kept, when a
/// new automatic backup is due and whether a file can be read.
public enum BackupRules {
    public static let format = "tagwerk-backup"
    /// The version of the file layout this app writes and reads. A higher version in a file is refused.
    /// Version 2 added the attachments of notes; files of version 1 stay readable.
    public static let schemaVersion = 2
    /// Automatic backups at most this often.
    public static let automaticIntervalSeconds: TimeInterval = 24 * 60 * 60
    /// Automatic backups kept in the folder.
    public static let keptFiles = 7
    public static let fileExtension = "json"
    /// The extension of a password-encrypted backup, so nobody takes the file for JSON.
    public static let encryptedFileExtension = "tagwerk"

    /// "Tagwerk-Sicherung-2026-11-19-1423.json" (".tagwerk" when `encrypted`), in the time zone of `calendar`.
    public static func fileName(for date: Date, calendar: Calendar, encrypted: Bool = false) -> String {
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return String(format: "Tagwerk-Sicherung-%04d-%02d-%02d-%02d%02d.%@", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1,
                      parts.hour ?? 0, parts.minute ?? 0, encrypted ? encryptedFileExtension : fileExtension)
    }

    /// The name of the safety copy made before a restore. It does not follow the pattern of `isOwnFile`, so the clean-up of
    /// automatic backups never touches it.
    public static func safetyCopyName(for date: Date, calendar: Calendar, encrypted: Bool = false) -> String {
        "Tagwerk-Vor-Wiederherstellung-" + fileName(for: date, calendar: calendar, encrypted: encrypted).dropFirst("Tagwerk-Sicherung-".count)
    }

    /// Whether a file name is exactly the pattern of `fileName(for:calendar:encrypted:)`, with either extension. Only such files are
    /// ever deleted.
    public static func isOwnFile(_ name: String) -> Bool {
        name.range(of: #"^Tagwerk-Sicherung-\d{4}-\d{2}-\d{2}-\d{4}\.(json|tagwerk)$"#, options: .regularExpression) != nil
    }

    /// The own files that go when only the newest `keeping` stay, counted across both extensions. The names sort by their time
    /// stamp; files that do not follow the pattern are never listed.
    public static func filesToDelete(names: [String], keeping: Int = keptFiles) -> [String] {
        let own = names.filter(isOwnFile).sorted { stamp($0) == stamp($1) ? $0 > $1 : stamp($0) > stamp($1) }
        return Array(own.dropFirst(max(0, keeping)))
    }

    /// "2026-11-19-1423" of an own file name.
    private static func stamp(_ name: String, prefix: String = "Tagwerk-Sicherung-") -> Substring {
        name.dropFirst(prefix.count).prefix(15)
    }

    // MARK: Safety copies

    /// Safety copies kept: the newest three, none older than `safetyCopyRetentionDays`.
    public static let keptSafetyCopies = 3
    public static let safetyCopyRetentionDays = 30

    /// Whether a file name is exactly the pattern of `safetyCopyName(for:calendar:encrypted:)`, with either extension.
    public static func isSafetyCopy(_ name: String) -> Bool {
        name.range(of: #"^Tagwerk-Vor-Wiederherstellung-\d{4}-\d{2}-\d{2}-\d{4}\.(json|tagwerk)$"#, options: .regularExpression) != nil
    }

    /// The minute a safety copy was made, read from its name in the time zone of `calendar`; `nil` for other names.
    public static func safetyCopyDate(_ name: String, calendar: Calendar) -> Date? {
        guard isSafetyCopy(name) else { return nil }
        let digits = name.dropFirst("Tagwerk-Vor-Wiederherstellung-".count).prefix(15).split(separator: "-").compactMap { Int($0) }
        guard digits.count == 4, digits[3] / 100 < 24, digits[3] % 100 < 60 else { return nil }
        return calendar.date(from: DateComponents(year: digits[0], month: digits[1], day: digits[2], hour: digits[3] / 100, minute: digits[3] % 100))
    }

    /// Days a safety copy stays: 30 for a new one, 0 once it is due for deletion. A date in the future (clock set back) counts as new.
    public static func safetyCopyDaysLeft(createdAt: Date, now: Date) -> Int {
        let age = max(0, now.timeIntervalSince(createdAt))
        let left = Double(safetyCopyRetentionDays) - age / 86_400
        return max(0, Int(left.rounded(.up)))
    }

    /// The safety copies to delete: everything beyond the newest `keptSafetyCopies` and everything that has stayed its 30 days.
    /// Names that are not safety copies are never listed.
    public static func safetyCopiesToDelete(names: [String], now: Date, calendar: Calendar) -> [String] {
        let prefix = "Tagwerk-Vor-Wiederherstellung-"
        let newestFirst: (String, String) -> Bool = { lhs, rhs in
            let (left, right) = (stamp(lhs, prefix: prefix), stamp(rhs, prefix: prefix))
            return left == right ? lhs > rhs : left > right
        }
        let copies = Set(names.filter(isSafetyCopy)).sorted(by: newestFirst)
        return copies.enumerated().compactMap { index, name in
            let expired = safetyCopyDate(name, calendar: calendar).map { safetyCopyDaysLeft(createdAt: $0, now: now) == 0 } ?? false
            return index >= keptSafetyCopies || expired ? name : nil
        }
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
