import Foundation

/// The subset of `PreferencesManager` that `BackupManager` depends on.
///
/// BackupManager reads (and in a few cases writes) these preferences. Injecting
/// a `PreferencesProviding` instead of touching `PreferencesManager.shared`
/// directly lets tests use a per-instance in-memory provider — no shared
/// `UserDefaults` mutation, no cross-test bleed.
///
/// Class-only (`AnyObject`) so writes to `var` properties are visible to all
/// holders, matching the reference-semantics behavior of `PreferencesManager.shared`.
protocol PreferencesProviding: AnyObject {
    /// Smart duplicate detection toggle (BackupManager.enableDuplicateDetection).
    var enableSmartDuplicateDetection: Bool { get }

    /// Last user-entered organization folder name. Read at BackupManager init
    /// (to restore the previous session's name) and written when a backup starts
    /// with a non-empty `organizationName`.
    var lastUsedOrganizationFolderName: String? { get set }

    /// Whether to restore the previous session's source + destinations at startup.
    var restoreLastSession: Bool { get }

    /// Whether to show the pre-flight summary alert before a backup. May be
    /// written back as `false` if the user opts out from the alert itself.
    var showPreflightSummary: Bool { get set }

    /// Whether to exclude image-editor cache files from manifests.
    var excludeCacheFiles: Bool { get }

    /// Whether to skip OS hidden / metadata files from manifests.
    var skipHiddenFiles: Bool { get }

    /// Whether to send a system notification on backup completion.
    var showNotificationOnComplete: Bool { get }

    /// Whether to offer "move source to Trash" after a successful backup.
    var trashSourceAfterBackup: Bool { get }

    /// File-count threshold above which a backup counts as "large" (warning gate).
    var largeBackupFileThreshold: Int { get }

    /// Total-size threshold (GB) above which a backup counts as "large".
    var largeBackupSizeThresholdGB: Double { get }

    /// Whether to gate large backups behind a confirmation alert.
    var confirmLargeBackups: Bool { get }

    /// Suppresses the large-backup warning. Written when the user picks
    /// "don't show again" from the confirmation.
    var skipLargeBackupWarning: Bool { get set }

    /// Records the supplied folder name as recently-used. Most-recent first;
    /// duplicates move to the top; caller-side cap of 10 entries.
    func addRecentOrganizationFolderName(_ name: String)
}
