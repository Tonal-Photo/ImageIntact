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
            try ChecksumService.sha256(
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
        let checksum = try ChecksumService.sha256(
            for: tempFile,
            shouldCancel: { false }
        )
        XCTAssertFalse(checksum.isEmpty, "Should produce a valid checksum")
        XCTAssertFalse(checksum.hasPrefix("size:"), "Should be a real hash, not a fallback")
    }

    /// The critical test: a closure that changes from false to true mid-operation
    /// must cause cancellation. This is the bug — previously the Bool was frozen.
    func testMidOperationCancellationIsRespected() throws {
        let counter = AtomicCounter()
        let cancelAfterChunks = 3

        XCTAssertThrowsError(
            try ChecksumService.sha256(
                for: tempFile,
                shouldCancel: { counter.increment() > cancelAfterChunks }
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
        let checksum = try ChecksumService.sha256(
            for: tempFile,
            shouldCancel: { false }
        )
        XCTAssertFalse(checksum.isEmpty)
    }

    /// Verify OptimizedChecksum directly respects cancellation closures.
    func testOptimizedChecksumRespectsClosureCancellation() throws {
        let counter = AtomicCounter()
        XCTAssertThrowsError(
            try OptimizedChecksum.sha256(for: tempFile, shouldCancel: {
                counter.increment() > 2
            })
        )
        XCTAssertGreaterThan(counter.value, 1,
                             "shouldCancel closure should be called multiple times during checksumming")
    }

    /// Async-bridge variant of testMidOperationCancellationIsRespected: confirms
    /// cancellation propagates correctly across the GCD boundary inside
    /// `ChecksumService.sha256Async`. The shouldCancel closure is captured by
    /// reference (via the AtomicCounter), so flipping its underlying state mid-
    /// operation reaches the work running on a GCD thread.
    func testSha256AsyncRespectsClosureCancellation() async throws {
        let counter = AtomicCounter()
        let cancelAfterChunks = 3
        let url = tempFile!

        do {
            _ = try await ChecksumService.sha256Async(
                for: url,
                shouldCancel: { counter.increment() > cancelAfterChunks }
            )
            XCTFail("sha256Async should have thrown a cancellation error")
        } catch let error as ChecksumError {
            guard case .cancelled = error else {
                XCTFail("Should throw ChecksumError.cancelled, got: \(error)")
                return
            }
        } catch {
            XCTFail("Expected ChecksumError.cancelled, got: \(type(of: error)) \(error)")
        }
    }

    /// Success path for the async wrapper: a complete read returns a 64-char hex SHA-256.
    func testSha256AsyncSuccessPath() async throws {
        let checksum = try await ChecksumService.sha256Async(
            for: tempFile, shouldCancel: { false }
        )
        XCTAssertEqual(checksum.count, 64, "Should be a 64-char hex SHA-256")
        XCTAssertFalse(checksum.hasPrefix("size:"), "Should be a real hash, not the legacy fallback sentinel")
    }

    /// Task cancellation bridge: cancelling the parent Task must propagate into
    /// the GCD work via `withTaskCancellationHandler` + the internal `CancelFlag`,
    /// causing `sha256Async` to throw a cancellation error even when the caller's
    /// own `shouldCancel` closure always returns false.
    ///
    /// File is sized large enough that the hash takes longer than the pre-cancel
    /// sleep on a fast SSD (300 MB ≈ 200-600ms on Apple Silicon, well above the
    /// 50ms sleep). If `OptimizedChecksum` ever gets an order-of-magnitude faster
    /// or this test starts flaking, bump the file size before assuming the bridge
    /// is broken.
    func testSha256AsyncRespectsTaskCancellation() async throws {
        let largeFile = testDirectory.appendingPathComponent("large-for-cancel.bin")
        let largeData = Data(repeating: 0xAB, count: 300_000_000) // 300 MB
        try largeData.write(to: largeFile)
        defer { try? FileManager.default.removeItem(at: largeFile) }

        let task = Task {
            // The user's shouldCancel always returns false; cancellation must come
            // exclusively from the Task.cancel() path below.
            try await ChecksumService.sha256Async(
                for: largeFile, shouldCancel: { false }
            )
        }

        // Give the GCD work a moment to start, then cancel.
        try await Task.sleep(nanoseconds: 50_000_000) // 50 ms
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Task.cancel() should have caused sha256Async to throw")
        } catch is _Concurrency.CancellationError {
            // Expected (AMUX-353): every Task-initiated cancellation — pre-entry
            // fail-fast, queued-then-cancelled, or mid-flight translation —
            // surfaces the stdlib CancellationError so TaskGroup parents see
            // cooperative cancellation, never a regular failure. Qualified:
            // ImageIntact's own CancellationError shadows the stdlib type.
        } catch {
            XCTFail("Task-initiated cancellation must surface _Concurrency.CancellationError, got: \(type(of: error)) \(error)")
        }
    }

    private var testDirectory: URL {
        // Use the same directory the tempFile lives in, for cleanup convenience.
        tempFile.deletingLastPathComponent()
    }
}

// MARK: - Thread-safe counter for @Sendable test closures

private final class AtomicCounter: @unchecked Sendable {
    private var _value = 0
    private let lock = NSLock()

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }

    /// Increments and returns the new value.
    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += 1
        return _value
    }
}
