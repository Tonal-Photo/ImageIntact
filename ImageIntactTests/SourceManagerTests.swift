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

    /// `trashCurrentSource` with a real temp folder: trashes the folder,
    /// clears the source URL/state, and returns the user-facing success
    /// message. Cleans up the trashed item to avoid littering the user's
    /// Trash. (Pattern mirrored from the pre-existing `TrashSourceTests`.)
    func testTrashCurrentSourceClearsStateOnSuccess() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceManagerTrashTest-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manager = SourceManager(fileOperations: DefaultFileOperations())
        manager.sourceURL = tempDir
        manager.sourceFileTypes = [.jpeg: 1]
        manager.scanProgress = "stale"

        let result = manager.trashCurrentSource()

        XCTAssertTrue(result.hasPrefix("Moved \""), "Should be a success message; got \(result)")
        XCTAssertNil(manager.sourceURL, "Source URL should be cleared after trash")
        XCTAssertTrue(manager.sourceFileTypes.isEmpty, "File types should be cleared")
        XCTAssertEqual(manager.scanProgress, "", "Scan progress should be cleared")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: tempDir.path),
            "Temp dir should no longer exist at original path"
        )

        // Best-effort cleanup of the trashed item to avoid littering ~/.Trash.
        // Walk the user's Trash and remove any matching folder.
        let trashURL = (try? FileManager.default.url(
            for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false
        )) ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash")
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: trashURL.path) {
            for entry in entries where entry.contains("SourceManagerTrashTest-") {
                try? FileManager.default.removeItem(at: trashURL.appendingPathComponent(entry))
            }
        }
    }
}
