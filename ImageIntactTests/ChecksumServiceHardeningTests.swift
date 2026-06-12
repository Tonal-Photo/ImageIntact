//
//  ChecksumServiceHardeningTests.swift
//  ImageIntactTests
//
//  AMUX-353 / gh#111 items 1+2: sha256Async must bound its own concurrency
//  (shared OperationQueue) and fail fast when the caller is already cancelled.
//

import CryptoKit
import XCTest

@testable import ImageIntact

final class ChecksumServiceHardeningTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecksumServiceHardeningTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func writeRandomFile(named name: String, bytes: Int) throws -> (url: URL, reference: String) {
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            arc4random_buf(base, bytes)
        }
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        let reference = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return (url, reference)
    }

    // MARK: - Item 1: bounded concurrency via shared OperationQueue

    func testIoQueueBoundsConcurrencyToActiveProcessorCount() {
        XCTAssertEqual(
            ChecksumService.ioQueue.maxConcurrentOperationCount,
            ProcessInfo.processInfo.activeProcessorCount,
            "the service must bound its own concurrency, not rely on callers")
    }

    func testIoQueueHasStableName() {
        // Locked so the worker threads stay identifiable in Instruments/spindump.
        XCTAssertEqual(ChecksumService.ioQueue.name, "com.imageintact.checksum.io")
    }

    func testSaturatingTheBoundCompletesAllChecksumsCorrectly() async throws {
        // 4x the bound: excess operations must queue (not spawn threads) and
        // every result must match its own file's reference hash.
        let count = max(8, ProcessInfo.processInfo.activeProcessorCount * 4)
        var files: [(url: URL, reference: String)] = []
        for i in 0 ..< count {
            files.append(try writeRandomFile(named: "sat-\(i).bin", bytes: 200_000))
        }

        let results = try await withThrowingTaskGroup(of: (Int, String).self) { group in
            for (index, file) in files.enumerated() {
                group.addTask {
                    (index, try await ChecksumService.sha256Async(
                        for: file.url, shouldCancel: { false }))
                }
            }
            var collected = [Int: String]()
            for try await (index, hash) in group {
                collected[index] = hash
            }
            return collected
        }

        XCTAssertEqual(results.count, count)
        for (index, file) in files.enumerated() {
            XCTAssertEqual(results[index], file.reference,
                           "hash mismatch for concurrent file \(index)")
        }
    }

    func testCancellingQueuedOperationResumesPromptly() async throws {
        let (url, _) = try writeRandomFile(named: "queued-cancel.bin", bytes: 100_000)

        // Saturate every slot of the shared queue with operations blocked on a
        // semaphore, so the checksum below must wait in the queue.
        let gate = DispatchSemaphore(value: 0)
        let slots = ChecksumService.ioQueue.maxConcurrentOperationCount
        for _ in 0 ..< slots {
            ChecksumService.ioQueue.addOperation { gate.wait() }
        }
        // Watchdog: if prompt cancellation regresses, drain the gate after 5s
        // so this test FAILS on the elapsed-time assert instead of hanging the
        // suite forever on `task.value`.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            for _ in 0 ..< slots { gate.signal() }
        }
        defer {
            watchdog.cancel()
            for _ in 0 ..< slots { gate.signal() }  // drain (extra signals are harmless)
        }

        let task = Task {
            try await ChecksumService.sha256Async(for: url, shouldCancel: { false })
        }
        // Let the task enqueue its operation behind the blockers, then cancel
        // while it is queued. (If cancel wins the race and lands pre-entry,
        // the fail-fast path also yields a prompt CancellationError — the
        // assertions below hold either way.)
        try await Task.sleep(nanoseconds: 100_000_000)
        let cancelledAt = Date()
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("queued-then-cancelled checksum must throw")
        } catch is _Concurrency.CancellationError {
            let elapsed = Date().timeIntervalSince(cancelledAt)
            XCTAssertLessThan(
                elapsed, 1.0,
                "cancelling a queued operation must resume the caller promptly, "
                    + "not wait for a queue slot (took \(elapsed)s)")
        } catch {
            XCTFail("Expected CancellationError, got \(type(of: error)): \(error)")
        }
    }

    // MARK: - Item 2: fail fast when already cancelled

    func testAlreadyCancelledCallerFailsFastWithCancellationError() async throws {
        let (url, _) = try writeRandomFile(named: "cancelled-entry.bin", bytes: 100_000)

        // Deterministic: the task cancels ITSELF before calling, so sha256Async
        // is always entered with an already-cancelled task (no scheduling race).
        let task = Task { () -> String in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChecksumService.sha256Async(for: url, shouldCancel: { false })
        }

        do {
            _ = try await task.value
            XCTFail("sha256Async must throw when entered already cancelled")
        } catch is _Concurrency.CancellationError {
            // expected: fail-fast pre-dispatch (gh#111 item 2) preserves
            // structured-concurrency semantics for TaskGroup parents.
            // Qualified: ImageIntact declares its own CancellationError
            // (BatchFileProcessor.swift) that shadows the stdlib type here.
        } catch {
            XCTFail("Expected CancellationError (fail-fast, pre-dispatch), got \(type(of: error)): \(error)")
        }
    }
}
