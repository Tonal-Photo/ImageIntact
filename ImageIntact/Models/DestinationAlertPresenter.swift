//
//  DestinationAlertPresenter.swift
//  ImageIntact
//
//  Protocol and AppKit implementation for presenting DestinationError alerts.
//  Extracted from BackupManager.setDestination (AMUX-19, GH #103) to remove
//  NSAlert calls from the model layer and enable dependency injection in tests.
//
//  Design doc: .planning/design/backup-manager-destination-forwarding.md
//

import AppKit

/// Presents user-facing alerts for `DestinationError` cases caught by
/// `BackupManager.setDestination`. Injected as a dependency so tests can
/// substitute a mock and the model layer stays free of AppKit calls.
@MainActor
protocol DestinationAlertPresenting {
    /// "Invalid Destination — same as source" alert. No user response needed.
    func presentSameAsSourceAlert()

    /// "Duplicate Destination" alert mentioning the existing index. No user response needed.
    func presentDuplicateDestinationAlert(existingIndex: Int)

    /// "Source Folder Selected" alert. Returns whether the caller should
    /// proceed with removing the source tag and retrying `setDestination`.
    /// `true` = user clicked "Use This Folder"; `false` = user cancelled.
    func presentSourceTagConflictAlert() -> Bool
}

@MainActor
struct NSAlertDestinationPresenter: DestinationAlertPresenting {
    func presentSameAsSourceAlert() {
        let alert = NSAlert()
        alert.messageText = "Invalid Destination"
        alert.informativeText = "The destination folder cannot be the same as the source folder."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentDuplicateDestinationAlert(existingIndex: Int) {
        let alert = NSAlert()
        alert.messageText = "Duplicate Destination"
        alert.informativeText =
            "This folder is already selected as destination #\(existingIndex + 1). Please choose a different folder."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    func presentSourceTagConflictAlert() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Source Folder Selected"
        alert.informativeText =
            "This folder was previously used as a source. Using it as a destination will remove the source tag. Do you want to continue?"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Use This Folder")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        return response == .alertFirstButtonReturn
    }
}
