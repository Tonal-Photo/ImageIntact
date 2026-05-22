//
//  BackupAlertPresenter.swift
//  ImageIntact
//
//  Protocol, data-transfer struct, and AppKit implementation for presenting
//  BackupManager.runBackup preflight alerts.
//  Extracted from BackupManager.runBackup (AMUX-15, GH #103) to remove
//  NSAlert calls from the model layer and enable dependency injection in tests.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md
//

import AppKit
import Foundation

// MARK: - PreflightSummary

/// Snapshot of the BackupManager state needed to render the preflight summary
/// alert. Passed into the presenter so the presenter stays a pure UI adapter
/// and BackupManager owns the data assembly.
struct PreflightSummary {
    let sourceName: String
    let sourcePath: String
    /// nil when no file-type filter active; otherwise the formatted summary.
    let filteredSummary: (summary: String, willCopy: Int, total: Int)?
    /// Formatted file-type summary string (used when no filter is active). nil otherwise.
    let fileTypeSummary: String?
    /// Total file count for the non-filtered path. 0 when filter is active.
    let totalFiles: Int
    /// Source total bytes; 0 to omit the size line.
    let totalBytes: Int64
    /// Destinations as (displayName, deviceName?) tuples.
    let destinations: [(name: String, deviceName: String?)]
    let excludeCacheFiles: Bool
    let skipHiddenFiles: Bool
    let fileTypeFilterActive: Bool
}

// MARK: - Protocol

/// Presents user-facing alerts for `BackupManager.runBackup` preflight.
/// Injected as a dependency so tests can substitute a mock and the model
/// layer stays free of AppKit calls.
@MainActor
protocol BackupAlertPresenting {
    /// "Insufficient Disk Space" critical alert. No user response needed (the
    /// backup aborts regardless).
    func presentInsufficientSpaceAlert(errors: [String])

    /// "Low Disk Space Warning" alert. Returns whether the caller should
    /// proceed with the backup. `true` = user clicked "Continue".
    func presentLowSpaceWarning(warnings: [String]) -> Bool

    /// "Backup Summary" preflight alert with a suppression checkbox.
    /// Returns `(proceed, showAgain)`:
    /// - `proceed`: `true` = user clicked "Start Backup".
    /// - `showAgain`: state of the suppression checkbox after the user
    ///   dismissed the alert. Caller writes this back to the preference.
    func presentPreflightSummary(_ summary: PreflightSummary) -> (proceed: Bool, showAgain: Bool)
}

// MARK: - NSAlert implementation

@MainActor
struct NSAlertBackupPresenter: BackupAlertPresenting {

    func presentInsufficientSpaceAlert(errors: [String]) {
        let alert = NSAlert()
        alert.messageText = "Insufficient Disk Space"
        alert.informativeText = errors.joined(separator: "\n\n")
        alert.alertStyle = .critical
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentLowSpaceWarning(warnings: [String]) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Low Disk Space Warning"
        alert.informativeText = warnings.joined(separator: "\n\n") + "\n\nDo you want to continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }

    func presentPreflightSummary(_ summary: PreflightSummary) -> (proceed: Bool, showAgain: Bool) {
        let alert = NSAlert()
        alert.messageText = "Backup Summary"

        // Build the summary message — mirrors the inline construction
        // previously in BackupManager.runBackup (lines 438-497 before AMUX-15).
        var message = "Ready to start backup:\n\n"

        // Source info
        message += "📁 Source: \(summary.sourceName)\n"
        message += "   Path: \(summary.sourcePath)\n\n"

        // File summary
        if let filteredSummary = summary.filteredSummary {
            message += "📊 Files to backup:\n"
            if filteredSummary.willCopy != filteredSummary.total {
                message += "   \(filteredSummary.willCopy) of \(filteredSummary.total) files (filtered)\n"
            } else {
                message += "   \(filteredSummary.total) files\n"
            }
            message += "   Types: \(filteredSummary.summary)\n\n"
        } else if summary.totalFiles > 0, let fileTypeSummary = summary.fileTypeSummary {
            message += "📊 Files to backup: \(summary.totalFiles)\n"
            message += "   Types: \(fileTypeSummary)\n\n"
        }

        // Size info
        if summary.totalBytes > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: summary.totalBytes)
            message += "💾 Total size: \(sizeString)\n\n"
        }

        // Destination info
        message += "📍 Destination\(summary.destinations.count > 1 ? "s" : ""):\n"
        for (index, dest) in summary.destinations.enumerated() {
            message += "   \(index + 1). \(dest.name)"
            if let deviceName = dest.deviceName, !deviceName.isEmpty {
                message += " (\(deviceName))"
            }
            message += "\n"
        }

        // Settings info
        message += "\n⚙️ Settings:\n"
        if summary.excludeCacheFiles {
            message += "   • Cache files will be excluded\n"
        }
        if summary.skipHiddenFiles {
            message += "   • Hidden files will be skipped\n"
        }
        if summary.fileTypeFilterActive {
            message += "   • File type filter is active\n"
        }

        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Start Backup")
        alert.addButton(withTitle: "Cancel")

        // Add "Show this summary before run" checkbox (on by default)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Show this summary before run"
        alert.suppressionButton?.state = .on

        let response = alert.runModal()

        return (
            proceed: response == .alertFirstButtonReturn,
            showAgain: alert.suppressionButton?.state == .on
        )
    }
}
