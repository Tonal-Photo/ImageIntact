//
//  MockBackupOrchestrator.swift
//  ImageIntactTests
//
//  Implements BackupOrchestrating (the minimal protocol BackupManager needs).
//  Records cancel() invocations for cancel-ordering verification in
//  BackupManagerCancelTests.
//
//  AMUX-204 (PR #122): converted from a subclass of BackupOrchestrator to a
//  direct protocol implementation. The subclass approach was an anti-pattern
//  (Fragile Base Class, awkward ProgressTracker/ResourceManager init dance,
//  recurring panel-review item) — implementing the protocol directly removes
//  all of that.
//

import Foundation
@testable import ImageIntact

/// Records `cancel()` invocations for the cancellation-ordering tests.
@MainActor
final class MockBackupOrchestrator: BackupOrchestrating {

    var cancelCallCount = 0

    func cancel() {
        cancelCallCount += 1
    }
}
