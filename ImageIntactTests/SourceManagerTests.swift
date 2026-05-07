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
}
