//
//  ChecksumCancellationTests.swift
//  ImageIntactTests
//
//  Tests for checksum cancellation (GH issue #91 finding #3).
//  The shouldCancel closure must be evaluated on every chunk read,
//  not frozen at call time.
//

@testable import ImageIntact
import XCTest

final class ChecksumCancellationTests: XCTestCase {

    var tempFile: URL!

    override func setUp() async throws {
        try await super.setUp()
        // Create a temp file large enough for multiple chunk reads.
        // OptimizedChecksum uses 1MB chunks for files 10-100MB,
        // so 10MB gives us ~10 chunk reads.
        tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecksumCancelTest-\(UUID().uuidString).bin")
        let tenMB = Data(repeating: 0xAB, count: 10 * 1024 * 1024)
        try tenMB.write(to: tempFile)
    }

    override func tearDown() async throws {
        if let tempFile = tempFile {
            try? FileManager.default.removeItem(at: tempFile)
        }
        tempFile = nil
        try await super.tearDown()
    }

    // MARK: - Cancellation Tests

    /// Verify that passing a closure that returns true immediately causes cancellation.
    func testImmediateCancellationThrows() throws {
        XCTAssertThrowsError(
            try BackupManager.sha256ChecksumStatic(
                for: tempFile,
                shouldCancel: { true }
            )
        ) { error in
            // OptimizedChecksum throws ChecksumError.cancelled
            XCTAssertTrue(
                "\(error)".lowercased().contains("cancel"),
                "Error should indicate cancellation, got: \(error)"
            )
        }
    }

    /// Verify that a closure returning false allows the checksum to complete.
    func testNoCancellationCompletes() throws {
        let checksum = try BackupManager.sha256ChecksumStatic(
            for: tempFile,
            shouldCancel: { false }
        )
        XCTAssertFalse(checksum.isEmpty, "Should produce a valid checksum")
        XCTAssertFalse(checksum.hasPrefix("size:"), "Should be a real hash, not a fallback")
    }

    /// The critical test: a closure that changes from false to true mid-operation
    /// must cause cancellation. This is the bug — previously the Bool was frozen.
    func testMidOperationCancellationIsRespected() throws {
        var chunkCount = 0
        let cancelAfterChunks = 3

        // This closure will return false for the first 3 checks, then true.
        // With 10MB file and 1MB chunks, there are ~10 chunks.
        // If the closure is evaluated per-chunk (correct), it cancels after chunk 3.
        // If the closure is frozen (bug), it never cancels.
        let shouldCancel: @Sendable () -> Bool = {
            chunkCount += 1
            return chunkCount > cancelAfterChunks
        }

        XCTAssertThrowsError(
            try BackupManager.sha256ChecksumStatic(
                for: tempFile,
                shouldCancel: shouldCancel
            )
        ) { error in
            XCTAssertTrue(
                "\(error)".lowercased().contains("cancel"),
                "BUG #3: Mid-operation cancellation was not respected. The shouldCancel " +
                "closure must be evaluated on every chunk, not frozen at call time. " +
                "Got error: \(error)"
            )
        }
    }

    /// Verify the default parameter (no cancellation) works.
    func testDefaultNoCancellation() throws {
        let checksum = try BackupManager.sha256ChecksumStatic(
            for: tempFile,
            shouldCancel: { false }
        )
        XCTAssertFalse(checksum.isEmpty)
    }

    /// Verify OptimizedChecksum directly respects cancellation closures.
    func testOptimizedChecksumRespectsClosureCancellation() throws {
        var callCount = 0
        XCTAssertThrowsError(
            try OptimizedChecksum.sha256(for: tempFile, shouldCancel: {
                callCount += 1
                return callCount > 2
            })
        )
        XCTAssertGreaterThan(callCount, 1,
                             "shouldCancel closure should be called multiple times during checksumming")
    }
}
