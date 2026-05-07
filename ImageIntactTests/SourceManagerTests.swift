//
//  SourceManagerTests.swift
//  ImageIntactTests
//
//  Direct tests for SourceManager. Initial coverage focuses on
//  prepareSource(at:) — the state-mutation path extracted from
//  BackupManager.setSource (#103 / AMUX-18).
//

import XCTest

@testable import ImageIntact

@MainActor
final class SourceManagerTests: XCTestCase {
    /// `prepareSource` clears stale scan state from a previous source. The
    /// auto-scan is suppressed under `BackupManager.isRunningTests`, so we can
    /// assert the synchronous post-conditions deterministically.
    func testPrepareSourceClearsStaleScanState() {
        let manager = SourceManager(fileOperations: DefaultFileOperations())
        // Prime stale state from a hypothetical prior scan.
        manager.sourceFileTypes = [.jpeg: 5, .raw: 3]
        manager.scanProgress = "halfway through Card01"
        manager.sourceTotalBytes = 1_000_000

        let url = URL(fileURLWithPath: "/Volumes/Card02/DCIM")
        manager.prepareSource(at: url)

        XCTAssertEqual(manager.sourceURL, url, "URL should be set")
        XCTAssertTrue(manager.sourceFileTypes.isEmpty, "Stale file-type counts should clear")
        XCTAssertEqual(manager.scanProgress, "", "Stale scan progress should clear")
        XCTAssertEqual(manager.sourceTotalBytes, 0, "Stale byte total should clear")
    }

    /// Calling `prepareSource` twice in quick succession must not leak the
    /// first scan task. The internal `currentScanTask` is replaced (and the
    /// previous one cancelled) so the second call's post-conditions still hold.
    func testPrepareSourceTwiceClearsState() {
        let manager = SourceManager(fileOperations: DefaultFileOperations())

        let url1 = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        let url2 = URL(fileURLWithPath: "/Volumes/Card02/DCIM")
        manager.prepareSource(at: url1)
        // Mutate state as if a partial scan happened.
        manager.sourceFileTypes = [.jpeg: 100]
        manager.scanProgress = "scanning Card01..."

        manager.prepareSource(at: url2)
        XCTAssertEqual(manager.sourceURL, url2)
        XCTAssertTrue(manager.sourceFileTypes.isEmpty,
                      "Second prepareSource must clear results from the first one")
        XCTAssertEqual(manager.scanProgress, "")
    }

    // MARK: - trashCurrentSource

    /// `trashCurrentSource` with no `sourceURL` set returns the no-source
    /// message and does not raise an error. Deterministic, no filesystem
    /// side effects.
    func testTrashCurrentSourceWithoutSourceReturnsErrorMessage() {
        let manager = SourceManager(fileOperations: DefaultFileOperations())
        XCTAssertNil(manager.sourceURL)
        let result = manager.trashCurrentSource()
        XCTAssertEqual(result, "No source folder to move")
    }

    /// `trashCurrentSource` success path: dispatches through the injected
    /// `fileOperations.trashItem`, clears state, and returns the user-facing
    /// message. Uses a mock so the user's real Trash is untouched.
    func testTrashCurrentSourceClearsStateOnSuccess() {
        let mock = MockFileOperations()
        let manager = SourceManager(fileOperations: mock)
        let url = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        manager.sourceURL = url
        manager.sourceFileTypes = [.jpeg: 1]
        manager.scanProgress = "stale"

        let result = manager.trashCurrentSource()

        XCTAssertEqual(result, "Moved \"DCIM\" to Trash")
        XCTAssertEqual(mock.trashedItems, [url], "fileOperations.trashItem should have been called once with the source URL")
        XCTAssertNil(manager.sourceURL, "Source URL should be cleared after trash")
        XCTAssertTrue(manager.sourceFileTypes.isEmpty, "File types should be cleared")
        XCTAssertEqual(manager.scanProgress, "")
    }

    /// `trashCurrentSource` error path: when `fileOperations.trashItem` throws
    /// (e.g., permission denied, missing file, locked file), the source state
    /// stays intact and the returned message includes the underlying error
    /// description.
    func testTrashCurrentSourceErrorPathPreservesState() {
        let mock = MockFileOperations()
        mock.shouldFailTrash = true
        let manager = SourceManager(fileOperations: mock)
        let url = URL(fileURLWithPath: "/Volumes/Card02/DCIM")
        manager.sourceURL = url
        manager.sourceFileTypes = [.jpeg: 5]
        manager.scanProgress = "preserved"

        let result = manager.trashCurrentSource()

        XCTAssertTrue(result.hasPrefix("Failed to move to Trash:"),
                      "Should be a failure message; got \(result)")
        XCTAssertEqual(manager.sourceURL, url, "Source URL must NOT be cleared on failure")
        XCTAssertEqual(manager.sourceFileTypes, [.jpeg: 5], "File types must NOT be cleared on failure")
        XCTAssertEqual(manager.scanProgress, "preserved", "Scan progress must NOT be cleared on failure")
    }
}
