import Foundation

// MARK: - Forwarding Accessors
//
// Thin delegation layer split out of BackupManager.swift (AMUX-230, 500-line
// limit). Pure forwarding to state / sourceManager / destinationManager /
// progressTracker — no logic lives here.

extension BackupManager {
    // MARK: - Modal Presentation Flags

    // Forwarded to state so $backupManager.showX bindings keep working.
    var showCompletionReport: Bool { get { state.showCompletionReport } set { state.showCompletionReport = newValue } }
    var showMigrationDialog: Bool { get { state.showMigrationDialog } set { state.showMigrationDialog = newValue } }
    var showDuplicateWarning: Bool { get { state.showDuplicateWarning } set { state.showDuplicateWarning = newValue } }
    var showTrashConfirmation: Bool { get { state.showTrashConfirmation } set { state.showTrashConfirmation = newValue } }
    var showLargeBackupConfirmation: Bool { get { state.showLargeBackupConfirmation } set { state.showLargeBackupConfirmation = newValue } }

    // MARK: - Destination Forwarding (read-only)

    var destinationURLs: [URL?] { destinationManager.destinationURLs }
    var destinationItems: [DestinationItem] { destinationManager.destinationItems }
    var destinationDriveInfo: [UUID: DriveAnalyzer.DriveInfo] { destinationManager.destinationDriveInfo }

    // MARK: - Source Forwarding

    // Source-related properties are now on sourceManager
    // Convenience accessors for code that still reads these directly
    var sourceURL: URL? {
        get { sourceManager.sourceURL }
        set { sourceManager.sourceURL = newValue }
    }
    var sourceFileTypes: [ImageFileType: Int] {
        get { sourceManager.sourceFileTypes }
        set { sourceManager.sourceFileTypes = newValue }
    }
    var isScanning: Bool { sourceManager.isScanning }
    var scanProgress: String {
        get { sourceManager.scanProgress }
        set { sourceManager.scanProgress = newValue }
    }
    var sourceTotalBytes: Int64 { sourceManager.sourceTotalBytes }
    var fileTypeFilter: FileTypeFilter {
        get { sourceManager.fileTypeFilter }
        set { sourceManager.fileTypeFilter = newValue }
    }
    var includeSubdirectories: Bool {
        get { sourceManager.includeSubdirectories }
        set { sourceManager.includeSubdirectories = newValue }
    }
    var excludeCacheFiles: Bool {
        get { sourceManager.excludeCacheFiles }
        set { sourceManager.excludeCacheFiles = newValue }
    }

    // MARK: - Source Tag Delegation

    func checkForSourceTag(at url: URL) -> Bool {
        sourceManager.checkForSourceTag(at: url)
    }

    // MARK: - Progress Forwarding

    func formattedETA() -> String {
        return progressTracker.formattedETA()
    }

    @MainActor
    func initializeDestinations(_ destinations: [URL]) async {
        progressTracker.initializeDestinations(destinations)
    }

    @MainActor
    func incrementDestinationProgress(_ destinationName: String) {
        _ = progressTracker.incrementDestinationProgress(destinationName)
    }

    // MARK: - File Scanning (delegated to SourceManager)

    func getFormattedFileTypeSummary(groupRaw: Bool = false) -> String {
        sourceManager.getFormattedFileTypeSummary(groupRaw: groupRaw)
    }

    func getFilteredFilesSummary() -> (summary: String, willCopy: Int, total: Int)? {
        sourceManager.getFilteredFilesSummary()
    }

    func getDestinationEstimate(at index: Int) -> String? {
        destinationManager.getDestinationEstimate(at: index, sourceState: SourceEstimateState(
            sourceURL: sourceManager.sourceURL,
            sourceTotalBytes: sourceManager.sourceTotalBytes,
            sourceFileTypes: sourceManager.sourceFileTypes,
            isScanning: sourceManager.isScanning
        ))
    }
}
