//
//  BackupManagerRunBackupTests.swift
//  ImageIntactTests
//
//  TDD red-phase tests for BackupManager.runBackup alert extraction + bug fixes (AMUX-15).
//
//  These tests reference BackupAlertPresenting, PreflightSummary, NSAlertBackupPresenter,
//  and the new BackupManager init parameters (backupAlertPresenter, deferredCleanupDelayNanos)
//  — none of which exist yet. Compile failure here IS the red-phase signal.
//
//  NOTE: isProcessing is declared `var isProcessing = false` in BackupManager (not private(set)),
//  so it is directly settable via @testable import. sourceTotalBytes is a computed property
//  forwarding to sourceManager.sourceTotalBytes, which is an internal var — settable as
//  bm.sourceManager.sourceTotalBytes = N directly from the test target.
//
//  Design doc: .planning/design/backup-manager-run-backup-extraction.md
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupManagerRunBackupTests: BaseBackupManagerTestCase {

    // MARK: - Test fixtures

    var mockFileOps: MockFileOperations!
    var mockPresenter: MockBackupAlertPresenter!
    var mockDiskSpace: MockDiskSpaceChecker!

    // Saved preferences to restore in tearDown.
    private var savedShowPreflightSummary: Bool = false

    override func setUp() async throws {
        try await super.setUp()

        // Capture original state BEFORE resetting, so tearDown can restore it.
        savedShowPreflightSummary = PreferencesManager.shared.showPreflightSummary

        // Clear preferences state (bookmarks already cleared by base class).
        PreferencesManager.shared.resetToDefaults()

        mockFileOps = MockFileOperations()
        mockPresenter = MockBackupAlertPresenter()
        mockDiskSpace = MockDiskSpaceChecker()

        // Default: disk space check passes with no warnings or errors.
        mockDiskSpace.evaluationResult = (canProceed: true, warnings: [], errors: [])

        // New init params (don't exist yet — compile failure is expected in red phase).
        bm = BackupManager(
            fileOperations: mockFileOps,
            diskSpaceChecker: mockDiskSpace,
            backupAlertPresenter: mockPresenter
        )
    }

    override func tearDown() async throws {
        // Reset to defaults first, then restore the captured original value
        // last — so the restore is not immediately nullified by the reset call.
        PreferencesManager.shared.resetToDefaults()
        PreferencesManager.shared.showPreflightSummary = savedShowPreflightSummary

        mockPresenter = nil
        mockDiskSpace = nil
        mockFileOps = nil

        // Base class cancels any in-flight backup (reads self.bm before releasing it)
        // and restores bookmarks. bm is released naturally when the test instance deinits.
        try await super.tearDown()
    }

    // MARK: - Helpers

    private func makeURL(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    /// Set a source + one destination so runBackup can reach the disk-space check.
    private func setUpSourceAndDestination() {
        bm.setSource(makeURL("/Volumes/CardA/DCIM"))
        bm.setDestination(makeURL("/Volumes/BackupDrive"), at: 0)
    }

    // MARK: - Tests

    /// Low fix verification: isProcessing guard prevents re-entrant runBackup.
    /// With the guard in place, calling runBackup while already processing returns
    /// immediately — no presenter calls, isProcessing stays true (not reset to false).
    func testRunBackup_isProcessingGuard_earlyReturns() {
        setUpSourceAndDestination()
        bm.isProcessing = true

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 0,
                       "No presenter calls when runBackup is re-entered")
        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0)
        // isProcessing stays true — the guard returns before clearing it.
        XCTAssertTrue(bm.isProcessing,
                      "isProcessing should remain true when guard fires")
    }

    /// AMUX-207: canRunBackup must reflect the scan-in-progress state so the UI
    /// disables the Backup button while a scan is running. Without this, the UI
    /// and runBackup's actual gate would disagree.
    func testCanRunBackup_falseDuringScan() {
        bm.setSource(makeURL("/Volumes/CardA/DCIM"))
        bm.setDestination(makeURL("/Volumes/BackupDrive"), at: 0)
        bm.sourceManager.isScanning = true

        XCTAssertFalse(bm.canRunBackup(),
                       "canRunBackup must report false while source scan is in progress")
    }

    /// AMUX-207: source scan in progress → early return, no presenter calls.
    /// The scan resets sourceTotalBytes=0; without this guard the disk-space
    /// check trivially passes (requiredBytes=0) even if destinations are full.
    func testRunBackup_scanInProgress_logsAndReturns() {
        bm.setSource(makeURL("/Volumes/CardA/DCIM"))
        bm.setDestination(makeURL("/Volumes/BackupDrive"), at: 0)
        bm.sourceManager.isScanning = true

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0)
        XCTAssertFalse(bm.isProcessing)
    }

    /// AMUX-208: empty destinations → early return, no presenter calls.
    /// Mirrors the missing-source guard. Same shape as the AMUX-15 isProcessing guard.
    func testRunBackup_emptyDestinations_logsAndReturns() {
        bm.setSource(makeURL("/Volumes/CardA/DCIM"))
        // Intentionally do NOT call setDestination — destinationURLs stays []/[nil].

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 0,
                       "No presenter calls when destinations is empty")
        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0)
        XCTAssertFalse(bm.isProcessing,
                       "isProcessing must be false after early-return (empty destinations)")
    }

    /// Existing behavior preserved: no source → early return, no presenter calls.
    func testRunBackup_missingSource_logsAndReturns() {
        // No source set — sourceURL is nil.

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 0,
                       "No presenter calls when source is missing")
        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0)
        XCTAssertFalse(bm.isProcessing,
                       "isProcessing must be false after early-return (missing source)")
    }

    /// Insufficient space path: presenter receives the errors list; backup aborts.
    func testRunBackup_insufficientSpace_callsPresenterAndReturns() {
        setUpSourceAndDestination()
        mockDiskSpace.evaluationResult = (
            canProceed: false,
            warnings: [],
            errors: ["Insufficient space on BackupDrive: need 100 GB, only 10 GB available"]
        )

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 1,
                       "Presenter must be called exactly once for insufficient space")
        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls[0].count, 1,
                       "Errors array should contain the one error message")
        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 0,
                       "Low-space presenter must not be called when errors are present")
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0)
        XCTAssertFalse(bm.isProcessing,
                       "isProcessing must be false after insufficient-space early return")
    }

    /// Low space + user cancels: presenter fires once; backup aborts; preflight not called.
    func testRunBackup_lowSpace_proceedFalse_returns() {
        setUpSourceAndDestination()
        mockDiskSpace.evaluationResult = (
            canProceed: true,
            warnings: ["Warning: BackupDrive will have less than 10% free after backup"],
            errors: []
        )
        mockPresenter.lowSpaceReturnValue = false

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 1,
                       "Low-space presenter must be called once")
        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0,
                       "Preflight must NOT be called when user declines low-space warning")
        XCTAssertFalse(bm.isProcessing,
                       "isProcessing must be false after user cancels low-space warning")
    }

    /// Low space + user continues + preflight enabled: both low-space and preflight called.
    func testRunBackup_lowSpace_proceedTrue_proceedsToPreflight() {
        setUpSourceAndDestination()
        mockDiskSpace.evaluationResult = (
            canProceed: true,
            warnings: ["Warning: BackupDrive will have less than 10% free after backup"],
            errors: []
        )
        mockPresenter.lowSpaceReturnValue = true
        // Preflight must also be cancelled so runBackup doesn't try to launch the real backup.
        mockPresenter.preflightReturnValue = (proceed: false, showAgain: true)
        PreferencesManager.shared.showPreflightSummary = true

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 1,
                       "Low-space presenter must be called once")
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 1,
                       "Preflight presenter must be called once when user proceeds past low-space")
    }

    /// Preflight cancelled: presenter fires once; backup aborts.
    func testRunBackup_preflight_cancelled_returns() {
        setUpSourceAndDestination()
        mockPresenter.preflightReturnValue = (proceed: false, showAgain: true)
        PreferencesManager.shared.showPreflightSummary = true

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 1,
                       "Preflight presenter must be called once")
        XCTAssertFalse(bm.isProcessing,
                       "isProcessing must be false after user cancels preflight")
    }

    /// Preflight proceeds: isProcessing becomes true (backup started).
    func testRunBackup_preflight_proceedTrue_setsIsProcessing() {
        setUpSourceAndDestination()
        mockPresenter.preflightReturnValue = (proceed: true, showAgain: true)
        PreferencesManager.shared.showPreflightSummary = true

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 1)
        XCTAssertTrue(bm.isProcessing,
                      "isProcessing must be true after runBackup proceeds past preflight")
    }

    /// Suppression checkbox behavior: showAgain=false writes false to preferences.
    func testRunBackup_preflight_showAgainFalse_writesPreferenceFalse() {
        setUpSourceAndDestination()
        PreferencesManager.shared.showPreflightSummary = true
        // User unchecks "Show this summary before run" and clicks Start Backup.
        mockPresenter.preflightReturnValue = (proceed: true, showAgain: false)

        bm.runBackup()

        XCTAssertFalse(PreferencesManager.shared.showPreflightSummary,
                       "showPreflightSummary must be written back as false when showAgain=false")
    }

    /// High fix verification: disk-space gate uses sourceTotalBytes, not totalBytesToCopy.
    /// We inject sourceManager state directly (bypassing setSource / prepareSource) to avoid
    /// the synchronous reset: prepareSource clears sourceTotalBytes = 0 on every call, and
    /// in test mode the async scan is suppressed, so calling setSource after setting the
    /// bytes would zero them out with no scan to repopulate them.
    func testRunBackup_diskSpaceUsesSourceTotalBytes() {
        let expectedBytes: Int64 = 123_456_789

        // MockDiskSpaceChecker captures `lastRequiredBytes` natively.
        mockDiskSpace.evaluationResult = (canProceed: true, warnings: [], errors: [])
        // Cancel at preflight so the backup doesn't actually start.
        mockPresenter.preflightReturnValue = (proceed: false, showAgain: true)
        PreferencesManager.shared.showPreflightSummary = true

        // Inject source URL and byte count directly into sourceManager, bypassing
        // prepareSource (which would synchronously reset sourceTotalBytes = 0 and skip
        // the scan in test mode, leaving us with 0 bytes regardless of what we set before).
        bm.sourceManager.sourceURL = makeURL("/Volumes/CardA/DCIM")
        bm.sourceManager.sourceTotalBytes = expectedBytes
        bm.setDestination(makeURL("/Volumes/BackupDrive"), at: 0)

        bm.runBackup()

        XCTAssertEqual(mockDiskSpace.lastRequiredBytes, expectedBytes,
                       "runBackup must pass sourceTotalBytes (not totalBytesToCopy) to the disk-space checker")
    }

    /// Fix 3 (missing happy path): preflight disabled + disk space OK → backup starts,
    /// no alerts fire. Verifies that disabling the preflight summary skips the presenter
    /// entirely and proceeds directly to setting isProcessing = true.
    func testRunBackup_preflightDisabled_noWarnings_setsIsProcessingWithoutAlerts() {
        // Preflight disabled — the presenter should never be asked to show the summary.
        PreferencesManager.shared.showPreflightSummary = false

        // Disk space defaults (set in setUp): canProceed = true, no warnings, no errors.
        setUpSourceAndDestination()

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentInsufficientSpaceCalls.count, 0,
                       "Insufficient-space presenter must not fire when space is fine")
        XCTAssertEqual(mockPresenter.presentLowSpaceCalls.count, 0,
                       "Low-space presenter must not fire when there are no warnings")
        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 0,
                       "Preflight presenter must not fire when preflight is disabled")
        XCTAssertTrue(bm.isProcessing,
                      "Backup should start immediately when preflight is disabled and space is fine")
    }
}
