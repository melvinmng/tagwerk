import Foundation

/// What the backup page tells the user about the automatic backup (#188, DS1b). Pure: the page passes the facts in.
public enum BackupStatus: Sendable, Equatable {
    case backedUp(at: Date)
    /// Never backed up automatically, or the last backup is older than two intervals (`days` is 0 without a backup).
    case overdue(since: Date?, days: Int)
    case folderMissing
    case failed(message: String)
    case off

    /// The status for the given facts. Order of precedence: switch off, no folder, an error of the last run, age of the last backup.
    public static func status(autoEnabled: Bool, hasFolder: Bool, lastBackup: Date?, lastError: String?, now: Date) -> BackupStatus {
        guard autoEnabled else { return .off }
        guard hasFolder else { return .folderMissing }
        if let lastError { return .failed(message: lastError) }
        guard let lastBackup else { return .overdue(since: nil, days: 0) }
        let age = now.timeIntervalSince(lastBackup)
        // A last backup in the future (clock set back) is not reported as overdue.
        guard age >= 2 * BackupRules.automaticIntervalSeconds else { return .backedUp(at: lastBackup) }
        return .overdue(since: lastBackup, days: Int(age / BackupRules.automaticIntervalSeconds))
    }

    /// Whether the card is shown in the warning style (orange, with symbol and text).
    public var isWarning: Bool {
        switch self {
        case .backedUp, .off: false
        case .overdue, .folderMissing, .failed: true
        }
    }
}
