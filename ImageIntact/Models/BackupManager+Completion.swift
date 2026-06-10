import Foundation

// MARK: - Backup Completion
//
// Split out of BackupManagerQueueIntegration.swift (AMUX-230, 500-line limit).

extension BackupManager {
    /// Handle backup completion (notifications and UI).
    /// `internal` (not `private`) so tests can drive it directly with mocked
    /// `preferences` / `notificationService` and assert which prefs reads gate
    /// which side effects (AMUX-205 panel review round 4).
    @MainActor
    func handleBackupCompletion(destinations: [URL]) async {
        // Stop preventing sleep
        SleepPrevention.shared.stopPreventingSleep()

        // Show completion report if not cancelled
        if !state.shouldCancel {
            // Send notification if enabled
            if preferences.showNotificationOnComplete {
                notificationService.sendBackupCompletionNotification(
                    filesCopied: progressTracker.processedFiles,
                    destinations: destinations.count,
                    duration: statistics.duration ?? 0
                )
            }

            // Small delay to ensure UI is ready
            try? await Task.sleep(nanoseconds: 100_000_000)
            showCompletionReport = true

            // Offer to trash source if enabled and backup was fully successful
            if preferences.trashSourceAfterBackup
                && state.failedFiles.isEmpty
                && sourceURL != nil
            {
                showTrashConfirmation = true
            }
        } else {
            // Clear the overall status text when cancelled
            state.overallStatusText = ""
            state.statusMessage = "Backup cancelled"

            // Still stop sleep prevention even if cancelled
            logInfo("Backup cancelled by user")
        }
    }
}
