//
//  BackupAlertPresenterTests.swift
//  ImageIntactTests
//
//  Tests for NSAlertBackupPresenter (AMUX-15).
//
//  NOTE: Modal presentation (NSAlert.runModal) cannot be tested in XCTest — the
//  runModal call blocks the run loop and hangs the test suite. This file only
//  verifies that the concrete presenter can be constructed and conforms to the
//  protocol. The three modal paths are verified manually after merge per the
//  manual test plan below.
//
//  NSAlertBackupPresenter and BackupAlertPresenting don't exist yet.
//  Compile failure here IS the red-phase signal.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupAlertPresenterTests: XCTestCase {

    /// Smoke test — NSAlertBackupPresenter can be constructed and assigned to
    /// the BackupAlertPresenting protocol type.
    func testNSAlertBackupPresenter_canBeConstructed() {
        let presenter: BackupAlertPresenting = NSAlertBackupPresenter()
        _ = presenter  // suppress unused-variable warning
    }
}

// MARK: - Manual test plan (post-merge, in the real app)
//
// 1. Insufficient space path:
//    - Set source to a folder whose size exceeds destination free space.
//    - Click "Run Backup".
//    - Expect: "Insufficient Disk Space" critical alert shows error messages.
//    - Click "OK" → backup does NOT start; isProcessing stays false.
//
// 2. Low disk space warning:
//    - Set source close to (but within) destination free space; ensure <10% free after backup.
//    - Click "Run Backup".
//    - Expect: "Low Disk Space Warning" alert with warnings + "Do you want to continue?".
//    - Click "Cancel" → backup does NOT start.
//    - Repeat, click "Continue" → preflight (if enabled) → backup starts.
//
// 3. Preflight summary (showPreflightSummary = true):
//    - Enable "Show backup summary before run" in Preferences.
//    - Click "Run Backup" with plenty of disk space.
//    - Expect: "Backup Summary" alert showing source, file count, size, destinations, settings.
//    - Uncheck "Show this summary before run", click "Start Backup".
//    - Expect: backup starts; next "Run Backup" skips preflight (preference written back).
//    - Repeat with checkbox on, click "Cancel" → backup does NOT start.
//
// 4. Cancel race fix (deferred cleanup):
//    - Start a backup, cancel it, immediately start a new backup within 10 seconds.
//    - Expect: the new backup's failedFiles/progressTracker/statistics are NOT wiped ~10s in.
//
// 5. Orchestrator cancel fix:
//    - Start a backup, cancel it.
//    - Expect: backup actually stops (no further file copy progress).
//    - Status shows "Backup cancelled" and isProcessing becomes false.
