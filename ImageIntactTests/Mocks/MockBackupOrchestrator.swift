//
//  MockBackupOrchestrator.swift
//  ImageIntactTests
//
//  Subclass of BackupOrchestrator that records cancel() calls for
//  cancel-ordering verification in BackupManagerCancelTests.
//
//  BackupOrchestrator is declared `class BackupOrchestrator` (not final, not open).
//  With `@testable import ImageIntact`, internal classes are accessible from the
//  test target and can be subclassed. Subclass approach is used here per the design doc.
//
//  If this fails to compile (e.g. the compiler treats the class as effectively
//  non-subclassable across module boundaries), fall back to the approach documented
//  in the design doc §"MockBackupOrchestrator": add a test-only internal accessor
//  `var isCancelled: Bool { shouldCancel }` to BackupOrchestrator and use the real
//  orchestrator in the test.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md
//

import Foundation
@testable import ImageIntact

/// Test double for BackupOrchestrator that counts cancel() invocations.
/// Used to verify the Blocker fix: orchestrator.cancel() is called synchronously
/// before cleanupMemory() nils currentOrchestrator.
@MainActor
final class MockBackupOrchestrator: BackupOrchestrator {

    var cancelCallCount = 0

    override func cancel() {
        cancelCallCount += 1
        // We intentionally do NOT call super.cancel() — this mock records the call
        // for ordering assertions only. The real BackupOrchestrator.cancel() spawns
        // a MainActor Task and touches ProgressTracker, which we don't want to fire
        // in unit tests.
    }
}
