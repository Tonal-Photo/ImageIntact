//
//  ProgressTrackerTests.swift
//  ImageIntactTests
//
//  Direct tests for ProgressTracker. Previously, three tests in
//  UIStateManagementTests covered ProgressTracker indirectly via
//  BackupManager wrapper methods (resetProgress / updateCopySpeed /
//  updateProgress) — those wrappers were dead in production (only the
//  tests called them) and were removed in #103 / AMUX-16. The same
//  behaviors are now exercised on ProgressTracker directly.
//

import XCTest

@testable import ImageIntact

@MainActor
final class ProgressTrackerTests: XCTestCase {
    /// resetAll() clears every observable progress field and the destination dicts.
    func testResetAllClearsState() {
        let tracker = ProgressTracker()
        tracker.currentFileIndex = 10
        tracker.currentFileName = "test.jpg"
        tracker.currentDestinationName = "Backup Drive"
        tracker.copySpeed = 50.0
        tracker.totalBytesCopied = 1_000_000
        tracker.destinationProgress["Backup"] = 5

        tracker.resetAll()

        XCTAssertEqual(tracker.currentFileIndex, 0)
        XCTAssertEqual(tracker.currentFileName, "")
        XCTAssertEqual(tracker.currentDestinationName, "")
        XCTAssertEqual(tracker.copySpeed, 0.0)
        XCTAssertEqual(tracker.totalBytesCopied, 0)
        XCTAssertTrue(tracker.destinationProgress.isEmpty)
    }

    /// `updateFileProgress` recomputes copy speed from accumulated bytes and
    /// elapsed time. With non-zero `totalBytesCopied` and a non-zero elapsed
    /// interval, the resulting `copySpeed` is positive.
    func testUpdateFileProgressComputesNonZeroCopySpeed() async throws {
        let tracker = ProgressTracker()
        tracker.totalBytesCopied = 1_000_000

        // Force a non-zero elapsed interval so the speed denominator is > 0.
        try await Task.sleep(nanoseconds: 10_000_000) // 10 ms

        tracker.updateFileProgress(fileName: "x.jpg", destinationName: "Backup")

        XCTAssertGreaterThan(tracker.copySpeed, 0, "Speed should be > 0 when bytes have been copied within an elapsed interval")
    }

    /// `updateFileProgress` updates the file/destination tracking fields
    /// synchronously (ProgressTracker is `@MainActor`; no Task wrapping needed).
    func testUpdateFileProgressUpdatesFields() {
        let tracker = ProgressTracker()
        let before = tracker.currentFileIndex

        tracker.updateFileProgress(fileName: "test.jpg", destinationName: "Backup")

        XCTAssertEqual(tracker.currentFileIndex, before + 1, "File index should increment by 1")
        XCTAssertEqual(tracker.currentFileName, "test.jpg")
        XCTAssertEqual(tracker.currentDestinationName, "Backup")
    }
}
