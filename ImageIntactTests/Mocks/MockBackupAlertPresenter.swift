//
//  MockBackupAlertPresenter.swift
//  ImageIntactTests
//
//  Mock implementation of BackupAlertPresenting for testing
//  BackupManager.runBackup alert paths.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md
//

import Foundation
@testable import ImageIntact

/// Test double for BackupAlertPresenting. Records all calls and returns
/// configurable values so tests can assert on which alert path fired without
/// triggering real NSAlert modals.
@MainActor
final class MockBackupAlertPresenter: BackupAlertPresenting {

    // MARK: - Call recording

    /// Each element is the `errors` array passed to presentInsufficientSpaceAlert.
    var presentInsufficientSpaceCalls: [[String]] = []

    /// Each element is the `warnings` array passed to presentLowSpaceWarning.
    var presentLowSpaceCalls: [[String]] = []

    /// Each element is the PreflightSummary passed to presentPreflightSummary.
    var presentPreflightCalls: [PreflightSummary] = []

    // MARK: - Configurable return values

    /// Return value for presentLowSpaceWarning. Default true = "Continue".
    var lowSpaceReturnValue = true

    /// Return value for presentPreflightSummary. Default (true, true) = proceed + show again.
    var preflightReturnValue: (proceed: Bool, showAgain: Bool) = (true, true)

    // MARK: - BackupAlertPresenting

    func presentInsufficientSpaceAlert(errors: [String]) {
        presentInsufficientSpaceCalls.append(errors)
    }

    func presentLowSpaceWarning(warnings: [String]) -> Bool {
        presentLowSpaceCalls.append(warnings)
        return lowSpaceReturnValue
    }

    func presentPreflightSummary(_ summary: PreflightSummary) -> (proceed: Bool, showAgain: Bool) {
        presentPreflightCalls.append(summary)
        return preflightReturnValue
    }
}
