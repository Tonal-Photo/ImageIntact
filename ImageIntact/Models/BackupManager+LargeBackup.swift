import Foundation

// MARK: - Large Backup Confirmation
//
// Split out of BackupManagerQueueIntegration.swift (AMUX-230, 500-line limit).

extension BackupManager {
    /// Check if this is a large backup and wait for user confirmation if needed.
    /// Returns true if backup should proceed, false if user cancelled.
    /// `internal` (not `private`) so tests can drive the early-return branches
    /// directly and assert which prefs reads gate which behavior (AMUX-205
    /// panel review round 4).
    @MainActor
    func checkForLargeBackupAndWait(
        source _: URL, destinations: [URL], manifest: [FileManifestEntry]
    ) async -> Bool {
        ApplicationLogger.shared.debug(
            "Checking for large backup (threshold: \(preferences.largeBackupFileThreshold) files / \(preferences.largeBackupSizeThresholdGB) GB)",
            category: .backup
        )

        // Skip if user disabled confirmations or already disabled warnings
        guard
            preferences.confirmLargeBackups
            && !preferences.skipLargeBackupWarning
        else {
            return true // Proceed with backup
        }

        // Check for cancellation
        guard !state.shouldCancel else { return false }

        state.statusMessage = "Analyzing backup size..."

        let fileThreshold = preferences.largeBackupFileThreshold
        let sizeThresholdBytes = Int64(
            preferences.largeBackupSizeThresholdGB * 1_000_000_000)
        let totalBytes = manifest.reduce(0) { $0 + $1.size }

        // Check if backup exceeds thresholds
        guard manifest.count > fileThreshold || totalBytes > sizeThresholdBytes else {
            return true // Proceed with backup
        }

        ApplicationLogger.shared.debug(
            "Large backup detected: \(manifest.count) files, \(String(format: "%.1f", Double(totalBytes) / 1_000_000_000)) GB",
            category: .backup
        )

        // Calculate estimated time
        let estimatedSpeed = 50.0 // MB/s - conservative estimate
        let seconds = Double(totalBytes) / (estimatedSpeed * 1_000_000)
        let timeString = TimeFormatter.formatDuration(seconds)

        state.largeBackupInfo = BackupState.LargeBackupInfo(
            fileCount: manifest.count,
            totalBytes: totalBytes,
            destinationCount: destinations.count,
            estimatedTimePerDestination: timeString
        )
        showLargeBackupConfirmation = true

        // Wait for user response using CheckedContinuation
        let result = await withCheckedContinuation { continuation in
            state.largeBackupContinuation = continuation
        }

        return result
    }

    /// User responded to large backup confirmation
    @MainActor
    func respondToLargeBackupConfirmation(shouldContinue: Bool, dontShowAgain: Bool) {
        showLargeBackupConfirmation = false
        state.largeBackupInfo = nil

        if dontShowAgain {
            preferences.skipLargeBackupWarning = true
        }

        // Resume the waiting backup process
        if let continuation = state.largeBackupContinuation {
            continuation.resume(returning: shouldContinue)
            state.largeBackupContinuation = nil
        } else {
            ApplicationLogger.shared.debug("No continuation to resume for large backup confirmation", category: .backup)
        }
    }
}
