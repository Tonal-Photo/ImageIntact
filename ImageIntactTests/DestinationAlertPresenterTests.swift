//
//  DestinationAlertPresenterTests.swift
//  ImageIntactTests
//
//  Tests for NSAlertDestinationPresenter (AMUX-19).
//
//  NOTE: Modal presentation (NSAlert.runModal) cannot be tested in XCTest — the
//  runModal call blocks the run loop and hangs the test suite. This file only
//  verifies that the concrete presenter can be constructed and conforms to the
//  protocol. The three modal paths (sameAsSource, duplicateDestination,
//  sourceTagConflict) are verified manually after merge per the manual test plan
//  in .planning/design/backup-manager-destination-forwarding.md §Manual test plan.
//

import XCTest
@testable import ImageIntact

@MainActor
final class DestinationAlertPresenterTests: XCTestCase {

    /// Smoke test — NSAlertDestinationPresenter can be constructed and conforms
    /// to DestinationAlertPresenting. Both types don't exist yet; compile failure
    /// here is the red-phase signal.
    func testNSAlertDestinationPresenter_canBeConstructed() {
        let presenter: DestinationAlertPresenting = NSAlertDestinationPresenter()
        _ = presenter  // suppress unused-variable warning
    }
}
