import XCTest
@testable import ImageIntact

/// AMUX-201: BackupState extracts transient per-run state out of BackupManager.
/// These tests pin the container's defaults and the BackupManager ownership +
/// modal-flag forwarding contract.
@MainActor
final class BackupStateTests: XCTestCase {

    func testDefaults() {
        let s = BackupState()
        XCTAssertFalse(s.isProcessing)
        XCTAssertEqual(s.statusMessage, "")
        XCTAssertEqual(s.currentPhase, .idle)
        XCTAssertTrue(s.skipExactDuplicates)
        XCTAssertFalse(s.skipRenamedDuplicates)
        XCTAssertFalse(s.showMigrationDialog)
        XCTAssertFalse(s.showCompletionReport)
        XCTAssertFalse(s.showDuplicateWarning)
        XCTAssertFalse(s.showTrashConfirmation)
        XCTAssertFalse(s.showLargeBackupConfirmation)
        XCTAssertNil(s.duplicateAnalyses)
        XCTAssertNil(s.largeBackupInfo)
        XCTAssertNil(s.largeBackupContinuation)
        XCTAssertNil(s.trashSourceResult)
        XCTAssertTrue(s.failedFiles.isEmpty)
        XCTAssertTrue(s.logEntries.isEmpty)
        XCTAssertTrue(s.debugLog.isEmpty)
        XCTAssertTrue(s.pendingMigrationPlans.isEmpty)
        XCTAssertFalse(s.sessionID.isEmpty)
    }

    func testBackupManagerOwnsBackupState() {
        // The migrated vars are reachable through bm.state.X.
        let bm = BackupManager()
        bm.state.isProcessing = true
        XCTAssertTrue(bm.state.isProcessing)
        bm.state.statusMessage = "working"
        XCTAssertEqual(bm.state.statusMessage, "working")
    }

    func testModalFlagForwardingRoundTrips() {
        // The 5 modal flags keep get/set forwarding computeds on BackupManager
        // so existing `$backupManager.showX` sheet/alert bindings keep working.
        // Verify both directions stay wired to the same state storage.
        let bm = BackupManager()
        bm.showMigrationDialog = true
        XCTAssertTrue(bm.state.showMigrationDialog, "bm.showX setter must write state")
        bm.state.showCompletionReport = true
        XCTAssertTrue(bm.showCompletionReport, "bm.showX getter must read state")
    }

    func testNestedTypesLiveOnBackupState() {
        let info = BackupState.LargeBackupInfo(
            fileCount: 10, totalBytes: 1024, destinationCount: 2,
            estimatedTimePerDestination: "1m"
        )
        XCTAssertEqual(info.fileCount, 10)
        let entry = BackupState.LogEntry(
            timestamp: Date(), sessionID: "s", action: "copy", source: "a",
            destination: "b", checksum: "c", algorithm: "sha256",
            fileSize: 1, reason: "r"
        )
        XCTAssertEqual(entry.algorithm, "sha256")
    }
}
