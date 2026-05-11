//
//  BackupManagerSetDestinationTests.swift
//  ImageIntactTests
//
//  TDD red-phase tests for the destination-forwarding alert extraction (AMUX-19).
//  These tests reference DestinationAlertPresenting, NSAlertDestinationPresenter,
//  and the destinationAlertPresenter init parameter on BackupManager — none of
//  which exist yet. Compile failure here IS the red-phase signal.
//
//  Design doc: .planning/design/backup-manager-destination-forwarding.md
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupManagerSetDestinationTests: XCTestCase {

    // MARK: - Helpers

    var mockFileOps: MockFileOperations!
    var mockPresenter: MockDestinationAlertPresenter!
    var backupManager: BackupManager!

    override func setUp() async throws {
        try await super.setUp()

        // Clear bookmark and preferences state so init doesn't restore stale data.
        UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        for key in BookmarkManager.destinationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        PreferencesManager.shared.resetToDefaults()

        mockFileOps = MockFileOperations()
        mockPresenter = MockDestinationAlertPresenter()

        // New init param (doesn't exist yet — compile failure is expected).
        backupManager = BackupManager(
            fileOperations: mockFileOps,
            destinationAlertPresenter: mockPresenter
        )
    }

    override func tearDown() async throws {
        UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        for key in BookmarkManager.destinationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        PreferencesManager.shared.resetToDefaults()

        backupManager = nil
        mockPresenter = nil
        mockFileOps = nil

        try await super.tearDown()
    }

    private func makeURL(_ path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    // MARK: - Tests

    /// sameAsSource error → presenter's sameAsSource method called exactly once.
    func testSetDestination_sameAsSource_callsPresenter() {
        let url = makeURL("/Volumes/CardA/DCIM")
        backupManager.setSource(url)

        backupManager.setDestination(url, at: 0)

        XCTAssertEqual(mockPresenter.presentSameAsSourceAlertCallCount, 1,
                       "sameAsSource should call presenter exactly once")
        XCTAssertEqual(mockPresenter.presentDuplicateDestinationAlertCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentSourceTagConflictAlertCallCount, 0)
    }

    /// duplicateDestination error → presenter called with the index of the existing destination.
    func testSetDestination_duplicateDestination_callsPresenterWithIndex() {
        let source = makeURL("/Volumes/Source/DCIM")
        let dest = makeURL("/Volumes/BackupB")

        // A source that differs from B (no sameAsSource error).
        backupManager.setSource(source)

        // Set slot 0 to B.
        backupManager.setDestination(dest, at: 0)

        // Add a second slot, then set it to B (duplicate of slot 0).
        backupManager.addDestination()
        backupManager.setDestination(dest, at: 1)

        XCTAssertEqual(mockPresenter.presentDuplicateDestinationAlertCalls, [0],
                       "duplicateDestination should call presenter with existingIndex 0")
        XCTAssertEqual(mockPresenter.presentSameAsSourceAlertCallCount, 0)
        XCTAssertEqual(mockPresenter.presentSourceTagConflictAlertCallCount, 0)
    }

    /// sourceTagConflict + presenter returns true → tag removed, destination set.
    func testSetDestination_sourceTagConflict_proceedTrue_retriesAndSetsDestination() {
        let dest = makeURL("/Volumes/WasPreviouslySource")
        let tagFile = dest.appendingPathComponent(".imageintact_source")

        // Plant the source-tag file so checkForSourceTag returns true.
        mockFileOps.filesExist.insert(tagFile)
        mockPresenter.sourceTagConflictReturnValue = true

        backupManager.setDestination(dest, at: 0)

        XCTAssertEqual(mockPresenter.presentSourceTagConflictAlertCallCount, 1,
                       "sourceTagConflict should call presenter once")
        XCTAssertTrue(mockFileOps.removedItems.contains(tagFile),
                      "Source tag should be removed when user proceeds")
        XCTAssertEqual(backupManager.destinationItems[0].url, dest,
                       "Destination should be set after source tag removal")
    }

    /// sourceTagConflict + presenter returns false → tag NOT removed, destination NOT set.
    func testSetDestination_sourceTagConflict_proceedFalse_doesNothing() {
        let dest = makeURL("/Volumes/WasPreviouslySource")
        let tagFile = dest.appendingPathComponent(".imageintact_source")

        mockFileOps.filesExist.insert(tagFile)
        mockPresenter.sourceTagConflictReturnValue = false

        backupManager.setDestination(dest, at: 0)

        XCTAssertEqual(mockPresenter.presentSourceTagConflictAlertCallCount, 1,
                       "sourceTagConflict should call presenter once even when cancelled")
        XCTAssertFalse(mockFileOps.removedItems.contains(tagFile),
                       "Source tag should NOT be removed when user cancels")
        XCTAssertNil(backupManager.destinationItems[0].url,
                     "Destination should NOT be set when user cancels")
    }

    /// Out-of-range index → no presenter calls, no crash.
    func testSetDestination_indexOutOfRange_logsWithoutAlert() {
        let url = makeURL("/Volumes/SomeFolder")

        backupManager.setDestination(url, at: 999)

        XCTAssertEqual(mockPresenter.presentSameAsSourceAlertCallCount, 0)
        XCTAssertEqual(mockPresenter.presentDuplicateDestinationAlertCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentSourceTagConflictAlertCallCount, 0)
    }

    /// Happy path — distinct URLs with no source tag → presenter never called, destination set.
    func testSetDestination_success_doesNotCallPresenter() {
        let source = makeURL("/Volumes/CardA/DCIM")
        let dest = makeURL("/Volumes/BackupDrive")

        backupManager.setSource(source)
        backupManager.setDestination(dest, at: 0)

        XCTAssertEqual(mockPresenter.presentSameAsSourceAlertCallCount, 0)
        XCTAssertEqual(mockPresenter.presentDuplicateDestinationAlertCalls.count, 0)
        XCTAssertEqual(mockPresenter.presentSourceTagConflictAlertCallCount, 0)
        XCTAssertEqual(backupManager.destinationItems[0].url, dest,
                       "Destination should be set on happy path")
    }
}
