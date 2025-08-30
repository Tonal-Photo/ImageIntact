//
//  DestinationQueueTests.swift
//  ImageIntactTests
//
//  Unit tests for DestinationQueue using mock implementations
//

import XCTest
@testable import ImageIntact

final class DestinationQueueTests: XCTestCase {
    
    // MARK: - Properties
    
    var mockFileOps: MockFileOperations!
    var mockChecksum: MockChecksumCalculator!
    var destinationURL: URL!
    var queue: DestinationQueue!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        mockFileOps = MockFileOperations()
        mockChecksum = MockChecksumCalculator()
        destinationURL = URL(fileURLWithPath: "/test/destination")
        
        // Create the queue with mock dependencies
        queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: mockFileOps
        )
    }
    
    override func tearDown() async throws {
        mockFileOps.reset()
        mockChecksum.reset()
        queue = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testQueueInitialization() async throws {
        // Given
        let testQueue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: mockFileOps
        )
        
        // Then - a queue with no tasks is considered complete
        let status = await testQueue.getStatus()
        XCTAssertEqual(status.total, 0, "New queue should have no tasks")
        XCTAssertEqual(status.completed, 0, "New queue should have no completed tasks")
    }
    
    func testAddingTasks() async throws {
        // Given
        let tasks = createMockFileTasks(count: 5)
        
        // When
        await queue.addTasks(tasks)
        
        // Then
        let status = await queue.getStatus()
        XCTAssertEqual(status.total, 5, "Queue should have 5 tasks")
        XCTAssertEqual(status.completed, 0, "No tasks should be completed yet")
    }
    
    // MARK: - File Copy Tests
    
    func testSuccessfulFileCopy() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/test.jpg")
        let destURL = destinationURL.appendingPathComponent("TestOrg/test.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "test.jpg", size: 1000, checksum: "abc123")]
        
        // Setup mock to succeed
        mockFileOps.mockFileSizes[sourceURL] = 1000
        mockFileOps.mockChecksums[sourceURL] = "abc123"
        // Set destination checksum for verification to pass
        mockFileOps.mockChecksums[destURL] = "abc123"
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        
        // Wait for completion
        await waitForQueueCompletion()
        
        // Then
        XCTAssertEqual(mockFileOps.copyCount, 1, "Should have copied 1 file")
        XCTAssertTrue(mockFileOps.verifyCopied(from: sourceURL, to: destURL))
        
        let status = await queue.getStatus()
        XCTAssertEqual(status.completed, 1, "Should have completed 1 task")
    }
    
    func testSkipExistingFileWithMatchingChecksum() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/existing.jpg")
        let destURL = destinationURL.appendingPathComponent("TestOrg/existing.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "existing.jpg", size: 2000, checksum: "xyz789")]
        
        // Setup mock - file already exists with same checksum
        mockFileOps.addMockFile(at: destURL, size: 2000, checksum: "xyz789")
        mockFileOps.mockChecksums[sourceURL] = "xyz789"
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then
        XCTAssertEqual(mockFileOps.copyCount, 0, "Should not copy file that already exists with matching checksum")
        
        let status = await queue.getStatus()
        XCTAssertEqual(status.completed, 1, "Should still mark as completed even if skipped")
    }
    
    func testReplaceFileWithMismatchedChecksum() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/mismatch.jpg")
        let destURL = destinationURL.appendingPathComponent("TestOrg/mismatch.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "mismatch.jpg", size: 3000, checksum: "new123")]
        
        // Setup mock - file exists with different checksum
        mockFileOps.addMockFile(at: destURL, size: 3000, checksum: "old456")
        mockFileOps.mockChecksums[sourceURL] = "new123"
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then
        XCTAssertEqual(mockFileOps.removalCount, 1, "Should remove existing file with wrong checksum")
        XCTAssertEqual(mockFileOps.copyCount, 1, "Should copy new file")
        XCTAssertTrue(mockFileOps.removedItems.contains(destURL), "Should have removed the destination file")
    }
    
    // MARK: - Error Handling Tests
    
    func testRetryOnCopyFailure() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/retry.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "retry.jpg", size: 4000, checksum: "retry123")]
        
        // Setup mock to fail first 3 times (matching DEFAULT_MAX_RETRIES), succeed on 4th
        mockFileOps.shouldFailCopy = true
        mockFileOps.mockChecksums[sourceURL] = "retry123"
        
        // Track copy attempts  
        var attemptCount = 0
        let originalCopyItem = mockFileOps.copyItem(at:to:)
        
        // Override copyItem to count attempts and eventually succeed
        // Note: DestinationQueue retries 3 times after initial failure = 4 total attempts
        mockFileOps = MockFileOperationsWithRetry()
        mockFileOps.mockChecksums[sourceURL] = "retry123"
        (mockFileOps as! MockFileOperationsWithRetry).failUntilAttempt = 3
        
        // Create queue with retry-aware mock
        queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: mockFileOps
        )
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then
        let retryMock = mockFileOps as! MockFileOperationsWithRetry
        XCTAssertEqual(retryMock.copyAttempts, 4, "Should retry up to 3 times after initial failure")
        
        let status = await queue.getStatus()
        XCTAssertEqual(status.completed, 1, "Should eventually complete after retries")
    }
    
    func testFailureAfterMaxRetries() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/fail.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "fail.jpg", size: 5000, checksum: "fail123")]
        
        // Setup mock to always fail
        mockFileOps.shouldFailCopy = true
        mockFileOps.mockChecksums[sourceURL] = "fail123"
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then - DestinationQueue retries DEFAULT_MAX_RETRIES (3) times
        // Total attempts = 1 initial + 3 retries = 4
        // But failedFiles should only show the unique file that failed
        let failedFiles = await queue.failedFiles
        let uniqueFailedFiles = Set(failedFiles.map { $0.file })
        XCTAssertEqual(uniqueFailedFiles.count, 1, "Should have 1 unique failed file after max retries")
        XCTAssertTrue(uniqueFailedFiles.contains("fail.jpg"), "Failed file should be fail.jpg")
    }
    
    // MARK: - Directory Creation Tests
    
    func testCreatesDirectoryStructure() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/nested/deep/file.jpg")
        let destURL = destinationURL.appendingPathComponent("TestOrg/nested/deep/file.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "nested/deep/file.jpg", size: 6000, checksum: "nested123")]
        
        // Setup mock checksums for verification
        mockFileOps.mockChecksums[sourceURL] = "nested123"
        mockFileOps.mockChecksums[destURL] = "nested123"
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then - check that directory creation was called
        // The exact directory depends on implementation, but we should see directory creation
        XCTAssertTrue(mockFileOps.createdDirectories.count > 0, "Should create directories")
        
        // Verify the file was copied to the right location
        let copiedToCorrectLocation = mockFileOps.copiedFiles.contains { copy in
            copy.destination.path.contains("TestOrg/nested/deep/file.jpg")
        }
        XCTAssertTrue(copiedToCorrectLocation, "Should copy file to nested directory structure")
    }
    
    // MARK: - Verification Tests
    
    func testSuccessfulVerification() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/verify.jpg")
        let destURL = destinationURL.appendingPathComponent("TestOrg/verify.jpg")
        let checksum = "verify123"
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "verify.jpg", size: 7000, checksum: checksum)]
        
        // Setup mock
        mockFileOps.mockChecksums[sourceURL] = checksum
        mockFileOps.mockChecksums[destURL] = checksum
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then
        let verifiedCount = await queue.verifiedFiles
        XCTAssertEqual(verifiedCount, 1, "Should verify 1 file")
        
        let isComplete = await queue.isComplete()
        XCTAssertTrue(isComplete, "Queue should be complete after verification")
    }
    
    func testVerificationFailureOnChecksumMismatch() async throws {
        // Given
        let sourceURL = URL(fileURLWithPath: "/source/badverify.jpg")
        let tasks = [createFileTask(sourceURL: sourceURL, relativePath: "badverify.jpg", size: 8000, checksum: "original123")]
        
        // Use a mock that simulates corruption during copy
        let corruptingMock = MockFileOperationsWithCorruption()
        corruptingMock.mockChecksums[sourceURL] = "original123"
        corruptingMock.corruptFile = "badverify.jpg"  // This file will be "corrupted"
        
        // Create queue with corrupting mock
        let corruptQueue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: corruptingMock
        )
        
        // When
        await corruptQueue.addTasks(tasks)
        await corruptQueue.start()
        
        // Wait for completion
        var isComplete = false
        for _ in 0..<50 {
            isComplete = await corruptQueue.isComplete()
            if isComplete { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        
        // Then
        let failedFiles = await corruptQueue.failedFiles
        XCTAssertEqual(failedFiles.count, 1, "Should have 1 failed verification")
        XCTAssertTrue(failedFiles.first?.error.lowercased().contains("checksum") ?? false,
                      "Error should mention checksum issue")
    }
    
    // MARK: - Progress Tracking Tests
    
    func testProgressUpdates() async throws {
        // Given
        let tasks = createMockFileTasks(count: 10)
        
        // Setup checksums for all files to pass verification
        for (index, task) in tasks.enumerated() {
            let destURL = destinationURL.appendingPathComponent("TestOrg/file\(index).jpg")
            mockFileOps.mockChecksums[task.sourceURL] = task.checksum
            mockFileOps.mockChecksums[destURL] = task.checksum
        }
        
        // Track progress using the queue's status
        var initialStatus = await queue.getStatus()
        
        // When
        await queue.addTasks(tasks)
        await queue.start()
        await waitForQueueCompletion()
        
        // Then
        let finalStatus = await queue.getStatus()
        XCTAssertEqual(finalStatus.completed, 10, "Should have completed all tasks")
        XCTAssertEqual(finalStatus.total, 10, "Total should be 10")
    }
    
    // MARK: - Cancellation Tests
    
    func testCancellation() async throws {
        // Given
        let tasks = createMockFileTasks(count: 10)  // Fewer tasks for more reliable test
        
        // Use a mock that simulates slow operations
        let slowMock = MockFileOperationsWithDelay()
        slowMock.delayPerOperation = 0.2  // 200ms per file
        
        // Setup checksums
        for task in tasks {
            slowMock.mockChecksums[task.sourceURL] = task.checksum
        }
        
        // Create queue with slow mock
        let slowQueue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: slowMock
        )
        
        // When
        await slowQueue.addTasks(tasks)
        await slowQueue.start()
        
        // Let it process for a short time
        try await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds - should process 1-2 files
        
        // Cancel
        await slowQueue.stop()
        
        // Give it a moment to stop
        try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 seconds
        
        // Then
        let status = await slowQueue.getStatus()
        XCTAssertLessThan(status.completed, 10, "Should not have completed all tasks")
        XCTAssertGreaterThan(status.completed, 0, "Should have completed at least one task")
    }
    
    // MARK: - Helper Methods
    
    private func createFileTask(
        sourceURL: URL,
        relativePath: String,
        size: Int64,
        checksum: String,
        priority: TaskPriority = .normal
    ) -> FileTask {
        let entry = FileManifestEntry(
            relativePath: relativePath,
            sourceURL: sourceURL,
            checksum: checksum,
            size: size
        )
        return FileTask(from: entry, priority: priority)
    }
    
    private func createMockFileTasks(count: Int) -> [FileTask] {
        return (0..<count).map { index in
            createFileTask(
                sourceURL: URL(fileURLWithPath: "/source/file\(index).jpg"),
                relativePath: "file\(index).jpg",
                size: Int64(1000 * (index + 1)),
                checksum: "checksum\(index)"
            )
        }
    }
    
    private func waitForQueueCompletion(timeout: TimeInterval = 5.0) async {
        let startTime = Date()
        while await !queue.isComplete() {
            if Date().timeIntervalSince(startTime) > timeout {
                XCTFail("Queue did not complete within timeout")
                break
            }
            try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second
        }
    }
}

// MARK: - Specialized Mock Classes for Testing

/// Mock that fails until a certain number of attempts
class MockFileOperationsWithRetry: MockFileOperations {
    var copyAttempts = 0
    var failUntilAttempt = 3
    
    override func copyItem(at source: URL, to destination: URL) async throws {
        copyAttempts += 1
        
        if copyAttempts <= failUntilAttempt {
            throw MockError.copyFailed
        }
        
        // Success after the specified number of failures
        try await super.copyItem(at: source, to: destination)
    }
}

/// Mock that adds delays to simulate slow operations
class MockFileOperationsWithDelay: MockFileOperations {
    var delayPerOperation: TimeInterval = 0.1
    
    override func copyItem(at source: URL, to destination: URL) async throws {
        // Add delay
        try await Task.sleep(nanoseconds: UInt64(delayPerOperation * 1_000_000_000))
        
        // Then perform the copy
        try await super.copyItem(at: source, to: destination)
    }
}

/// Mock that simulates file corruption after copy
class MockFileOperationsWithCorruption: MockFileOperations {
    var corruptFile: String?
    
    override func calculateChecksum(for url: URL, shouldCancel: () -> Bool) async throws -> String {
        // If this is the corrupted file's destination, return a different checksum
        if let corruptFile = corruptFile,
           url.path.contains(corruptFile) && url.path.contains("TestOrg") {
            // Return a corrupted checksum for the destination
            return "corrupted_checksum_456"
        }
        
        // Otherwise use normal behavior
        return try await super.calculateChecksum(for: url, shouldCancel: shouldCancel)
    }
}