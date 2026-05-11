//
//  MockDestinationAlertPresenter.swift
//  ImageIntactTests
//
//  Mock implementation of DestinationAlertPresenting for testing
//  BackupManager.setDestination error paths.
//

import Foundation
@testable import ImageIntact

/// Test double for DestinationAlertPresenting. Records all calls and returns
/// configurable values so tests can assert on which alert path fired without
/// triggering real NSAlert modals.
@MainActor
final class MockDestinationAlertPresenter: DestinationAlertPresenting {

    // MARK: - Call-count tracking

    var presentSameAsSourceAlertCallCount = 0
    var presentDuplicateDestinationAlertCalls: [Int] = []  // captured existingIndex values
    var presentSourceTagConflictAlertCallCount = 0

    // MARK: - Configurable return values

    /// Controls what presentSourceTagConflictAlert() returns. Default true = "Use This Folder".
    var sourceTagConflictReturnValue = true

    // MARK: - DestinationAlertPresenting

    func presentSameAsSourceAlert() {
        presentSameAsSourceAlertCallCount += 1
    }

    func presentDuplicateDestinationAlert(existingIndex: Int) {
        presentDuplicateDestinationAlertCalls.append(existingIndex)
    }

    func presentSourceTagConflictAlert() -> Bool {
        presentSourceTagConflictAlertCallCount += 1
        return sourceTagConflictReturnValue
    }
}
