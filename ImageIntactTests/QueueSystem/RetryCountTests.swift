//
//  RetryCountTests.swift
//  ImageIntactTests
//
//  Tests for bug #2 (GH issue #91): Failed files appended on every retry attempt,
//  inflating the failure count. This breaks isComplete() which uses failedFiles.count
//  to determine when all files have been processed.
//
//  The bug: DestinationQueue.processFileTask appends to failedFiles on EVERY failure,
//  including retries. A file that fails 3 times before exhausting retries gets 3 entries
//  in failedFiles instead of 1. This makes (verifiedFiles + failedFiles.count) >= totalFiles
//  true too early, causing the queue to declare itself complete before all files are processed.
//

@testable import ImageIntact
import XCTest

final class RetryCountTests: XCTestCase {

    // MARK: - Properties

    var mockFileOps: MockFileOperationsWithRetry!
    var destinationURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        mockFileOps = MockFileOperationsWithRetry()
        destinationURL = URL(fileURLWithPath: "/test/destination")
    }

    override func tearDown() async throws {
        mockFileOps = nil
        destinationURL = nil
        try await super.tearDown()
    }

    // MARK: - Bug #2: Retry-inflated failure count

    /// A file that fails all retry attempts should appear exactly ONCE in failedFiles.
    /// The current bug appends on every attempt, so 3 retries = 3 entries.
    func testFileFailingAllRetriesCountsAsOneFailure() async throws {
        // Given: a queue with a mock that always fails
        let alwaysFailMock = MockFileOperations()
        alwaysFailMock.shouldFailCopy = true

        let queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: alwaysFailMock
        )

        let sourceURL = URL(fileURLWithPath: "/source/failfile.jpg")
        alwaysFailMock.mockChecksums[sourceURL] = "fail123"
        let task = createFileTask(
            sourceURL: sourceURL,
            relativePath: "failfile.jpg",
            checksum: "fail123"
        )

        // When
        await queue.addTasks([task])
        await queue.start()
        await waitForCompletion(queue: queue)

        // Then: EXACTLY 1 entry in failedFiles, not 3 (one per retry attempt)
        let failedFiles = await queue.failedFiles
        XCTAssertEqual(failedFiles.count, 1,
                       "BUG #2: failedFiles should have exactly 1 entry for a file that " +
                       "failed all retries. Got \(failedFiles.count) -- retries are being " +
                       "counted as separate failures, inflating the count.")

        XCTAssertEqual(failedFiles.first?.file, "failfile.jpg")
    }

    /// A file that fails once then succeeds on retry should NOT appear in failedFiles at all.
    func testFileSucceedingOnRetryHasNoFailureEntry() async throws {
        // Given: mock that fails first attempt then succeeds
        let retryMock = MockFileOperationsWithRetry()
        retryMock.failUntilAttempt = 1 // Fail first attempt, succeed after

        let queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: retryMock
        )

        let sourceURL = URL(fileURLWithPath: "/source/retryfile.jpg")
        let destURL = destinationURL.appendingPathComponent("TestOrg/retryfile.jpg")
        retryMock.mockChecksums[sourceURL] = "retry123"
        retryMock.mockChecksums[destURL] = "retry123"
        let task = createFileTask(
            sourceURL: sourceURL,
            relativePath: "retryfile.jpg",
            checksum: "retry123"
        )

        // When
        await queue.addTasks([task])
        await queue.start()
        await waitForCompletion(queue: queue)

        // Then: NO entries in failedFiles -- the file ultimately succeeded
        let failedFiles = await queue.failedFiles
        let failedRetryFiles = failedFiles.filter { $0.file == "retryfile.jpg" }
        XCTAssertEqual(failedRetryFiles.count, 0,
                       "BUG #2: A file that succeeds on retry should have ZERO entries " +
                       "in failedFiles. Got \(failedRetryFiles.count) -- intermediate " +
                       "failures are leaking into the final count.")
    }

    /// isComplete() must not return true prematurely due to inflated failedFiles.count.
    /// With 5 files where 2 fail all retries, isComplete should only be true after
    /// all 5 files have been fully processed (3 verified + 2 failed).
    func testIsCompleteNotPrematureWithRetries() async throws {
        // Given: mock that fails specific files
        let selectiveFailMock = SelectiveFailMockFileOperations()
        selectiveFailMock.failingFiles = Set(["fail1.jpg", "fail2.jpg"])

        let queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: selectiveFailMock
        )

        var tasks: [FileTask] = []
        for i in 0..<5 {
            let name = i < 2 ? "fail\(i + 1).jpg" : "good\(i + 1).jpg"
            let sourceURL = URL(fileURLWithPath: "/source/\(name)")
            let destURL = destinationURL.appendingPathComponent("TestOrg/\(name)")
            let checksum = "checksum\(i)"
            selectiveFailMock.mockChecksums[sourceURL] = checksum
            selectiveFailMock.mockChecksums[destURL] = checksum
            tasks.append(createFileTask(sourceURL: sourceURL, relativePath: name, checksum: checksum))
        }

        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForCompletion(queue: queue, timeout: 10.0)

        // Then
        let failedFiles = await queue.failedFiles
        let verifiedFiles = await queue.verifiedFiles
        let isComplete = await queue.isComplete()

        // Should have exactly 2 unique failures
        let uniqueFailedPaths = Set(failedFiles.map { $0.file })
        XCTAssertEqual(uniqueFailedPaths.count, 2,
                       "Should have exactly 2 unique failed files, got \(uniqueFailedPaths.count)")

        // failedFiles.count should equal unique failure count (no inflation)
        XCTAssertEqual(failedFiles.count, uniqueFailedPaths.count,
                       "BUG #2: failedFiles.count (\(failedFiles.count)) should equal " +
                       "unique failures (\(uniqueFailedPaths.count)). Inflation detected.")

        // isComplete should be true only after all files fully processed
        XCTAssertTrue(isComplete,
                      "Queue should be complete: \(verifiedFiles) verified + " +
                      "\(failedFiles.count) failed should >= 5 total")
    }

    /// With many files and some retries, the total (verified + failed) should never
    /// exceed totalFiles. This guards against the inflation causing overcounting.
    func testVerifiedPlusFailedNeverExceedsTotalFiles() async throws {
        let alwaysFailMock = MockFileOperations()
        alwaysFailMock.shouldFailCopy = true

        let queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: alwaysFailMock
        )

        let totalFileCount = 10
        var tasks: [FileTask] = []
        for i in 0..<totalFileCount {
            let sourceURL = URL(fileURLWithPath: "/source/file\(i).jpg")
            alwaysFailMock.mockChecksums[sourceURL] = "checksum\(i)"
            tasks.append(createFileTask(
                sourceURL: sourceURL,
                relativePath: "file\(i).jpg",
                checksum: "checksum\(i)"
            ))
        }

        await queue.addTasks(tasks)
        await queue.start()
        await waitForCompletion(queue: queue, timeout: 15.0)

        let failedFiles = await queue.failedFiles
        let verifiedFiles = await queue.verifiedFiles

        XCTAssertLessThanOrEqual(
            verifiedFiles + failedFiles.count, totalFileCount,
            "BUG #2: verified (\(verifiedFiles)) + failed (\(failedFiles.count)) = " +
            "\(verifiedFiles + failedFiles.count), which exceeds total (\(totalFileCount)). " +
            "Retry inflation is causing overcounting.")
    }

    // MARK: - Helpers

    private func createFileTask(sourceURL: URL, relativePath: String, checksum: String) -> FileTask {
        let entry = FileManifestEntry(
            relativePath: relativePath,
            sourceURL: sourceURL,
            checksum: checksum,
            size: 1000
        )
        return FileTask(from: entry, priority: .normal)
    }

    private func waitForCompletion(queue: DestinationQueue, timeout: TimeInterval = 5.0) async {
        let startTime = Date()
        while await !queue.isComplete() {
            if Date().timeIntervalSince(startTime) > timeout {
                XCTFail("Queue did not complete within \(timeout)s timeout")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
}

// MARK: - Selective Failure Mock

/// Mock that fails specific files (by relativePath) but succeeds for others.
class SelectiveFailMockFileOperations: MockFileOperations {
    var failingFiles: Set<String> = []

    override func copyItem(at source: URL, to destination: URL) async throws {
        let filename = source.lastPathComponent
        if failingFiles.contains(filename) {
            throw MockError.copyFailed
        }
        try await super.copyItem(at: source, to: destination)
    }
}
