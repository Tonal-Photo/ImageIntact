import Foundation

// MARK: - Preflight Summary
//
// Split out of BackupManager.swift (AMUX-230, 500-line limit).

extension BackupManager {
    /// Build the data snapshot the preflight presenter needs.
    /// Pure data construction — no UI. Pulled out so runBackup is easy to read
    /// and the summary construction is testable in isolation.
    /// `internal` (not `private`) only because extensions in a separate file
    /// can't see private members; only runBackup should call this.
    func buildPreflightSummary(source: URL, destinations: [URL]) -> PreflightSummary {
        // Filtered summary (when a file-type filter is active).
        let filteredSummary = getFilteredFilesSummary()

        // Non-filtered file count and type summary (used when no filter is active).
        let nonFilteredTotalFiles = sourceFileTypes.values.reduce(0, +)
        let nonFilteredTypeSummary: String? = sourceFileTypes.isEmpty ? nil : getFormattedFileTypeSummary()

        // Build destination tuples with optional drive device names.
        // Zip the raw parallel arrays before filtering nils so indices stay aligned:
        // compactMap on destinationURLs alone would shift the index into
        // destinationItems if any earlier slot is nil.
        let validPairs: [(URL, DestinationItem)] = zip(destinationURLs, destinationItems).compactMap { url, item in
            guard let url = url else { return nil }
            return (url, item)
        }
        let destTuples: [(name: String, deviceName: String?)] = validPairs.map { url, item in
            let deviceName = destinationDriveInfo[item.id]?.deviceName
            let resolvedDeviceName = (deviceName?.isEmpty == false) ? deviceName : nil
            return (name: url.lastPathComponent, deviceName: resolvedDeviceName)
        }

        return PreflightSummary(
            sourceName: source.lastPathComponent,
            sourcePath: source.path,
            filteredSummary: filteredSummary,
            fileTypeSummary: nonFilteredTypeSummary,
            totalFiles: nonFilteredTotalFiles,
            totalBytes: sourceTotalBytes,
            destinations: destTuples,
            excludeCacheFiles: preferences.excludeCacheFiles,
            skipHiddenFiles: preferences.skipHiddenFiles,
            fileTypeFilterActive: !fileTypeFilter.includedExtensions.isEmpty
        )
    }
}
