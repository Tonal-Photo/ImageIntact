//
//  ProgressPublisherTests.swift
//  ImageIntactTests
//
//  Tests for the centralized progress publishing system
//

import XCTest
import Combine
@testable import ImageIntact

@MainActor
final class ProgressPublisherTests: XCTestCase {

    var publisher: ProgressPublisher!
    var cancellables: Set<AnyCancellable>!

    override func setUp() async throws {
        publisher = ProgressPublisher.shared
        publisher.reset()
        cancellables = []
    }

    override func tearDown() async throws {
        publisher.reset()
        cancellables = nil
    }

    // MARK: - Basic Functionality Tests

    func testInitialState() async {
        XCTAssertFalse(publisher.isBackupRunning)
        XCTAssertEqual(publisher.currentPhase, .idle)
        XCTAssertEqual(publisher.overallProgress, 0.0)
        XCTAssertTrue(publisher.destinations.isEmpty)
    }

    func testStartBackup() async {
        let destinations = ["dest1", "dest2", "dest3"]

        publisher.startBackup(totalFiles: 100, totalBytes: 1_000_000, destinationNames: destinations)

        XCTAssertTrue(publisher.isBackupRunning)
        XCTAssertEqual(publisher.totalFiles, 100)
        XCTAssertEqual(publisher.totalBytes, 1_000_000)
        XCTAssertEqual(publisher.destinations.count, 3)

        for name in destinations {
            let progress = publisher.destinations[name]
            XCTAssertNotNil(progress)
            XCTAssertEqual(progress?.filesTotal, 100)
            XCTAssertEqual(progress?.filesCompleted, 0)
            XCTAssertEqual(progress?.state, .idle)
        }
    }

    func testPhaseUpdates() async {
        let expectation = XCTestExpectation(description: "Phase update published")
        var receivedPhases: [BackupPhase] = []

        publisher.$currentPhase
            .dropFirst() // Skip initial value
            .sink { phase in
                receivedPhases.append(phase)
                if receivedPhases.count == 3 {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publisher.updatePhase(.analyzingSource)
        publisher.updatePhase(.copyingFiles)
        publisher.updatePhase(.complete)

        await fulfillment(of: [expectation], timeout: 1.0)

        XCTAssertEqual(receivedPhases, [.analyzingSource, .copyingFiles, .complete])
        XCTAssertFalse(publisher.isBackupRunning) // Should be false after complete
    }

    // MARK: - Destination Progress Tests

    func testDestinationProgressUpdate() async {
        publisher.startBackup(totalFiles: 10, totalBytes: 10000, destinationNames: ["dest1"])

        publisher.updateDestinationProgress(
            name: "dest1",
            filesCompleted: 5,
            bytesTransferred: 5000,
            state: .copying
        )

        let progress = publisher.destinations["dest1"]
        XCTAssertNotNil(progress)
        XCTAssertEqual(progress?.filesCompleted, 5)
        XCTAssertEqual(progress?.bytesTransferred, 5000)
        XCTAssertEqual(progress?.state, .copying)
    }

    func testFileCompletion() async {
        publisher.startBackup(totalFiles: 10, totalBytes: 10000, destinationNames: ["dest1", "dest2"])

        publisher.reportFileCompleted(destination: "dest1", fileName: "file1.txt", size: 1000)
        publisher.reportFileCompleted(destination: "dest1", fileName: "file2.txt", size: 1500)

        let progress = publisher.destinations["dest1"]
        XCTAssertEqual(progress?.filesCompleted, 2)
        XCTAssertEqual(progress?.bytesTransferred, 2500)
        XCTAssertEqual(publisher.processedFiles, 2)
    }

    func testOverallProgressCalculation() async {
        publisher.startBackup(totalFiles: 10, totalBytes: 10000, destinationNames: ["dest1", "dest2"])

        // Complete 50% of files on dest1
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: 5)
        // Complete 30% of files on dest2
        publisher.updateDestinationProgress(name: "dest2", filesCompleted: 3)

        // Overall progress should be average: (50% + 30%) / 2 = 40% of copying phase
        // Since copying is only 50% of total work, overall should be 20%
        XCTAssertEqual(publisher.overallProgress, 0.2, accuracy: 0.01)
    }

    // MARK: - Error Handling Tests

    func testErrorReporting() async {
        publisher.reportError(file: "bad.txt", destination: "dest1", error: "Permission denied")

        XCTAssertEqual(publisher.lastError, "Permission denied")
        XCTAssertEqual(publisher.failedFiles.count, 1)
        XCTAssertEqual(publisher.failedFiles.first?.file, "bad.txt")
        XCTAssertEqual(publisher.failedFiles.first?.destination, "dest1")
    }

    // MARK: - Concurrent Update Tests

    func testConcurrentUpdates() async {
        publisher.startBackup(totalFiles: 100, totalBytes: 100000, destinationNames: ["dest1", "dest2", "dest3"])

        // Simulate concurrent updates from multiple queues
        await withTaskGroup(of: Void.self) { group in
            for i in 1...10 {
                group.addTask { [publisher] in
                    await publisher?.updateDestinationProgress(name: "dest1", filesCompleted: i)
                }
                group.addTask { [publisher] in
                    await publisher?.updateDestinationProgress(name: "dest2", filesCompleted: i * 2)
                }
                group.addTask { [publisher] in
                    await publisher?.updateDestinationProgress(name: "dest3", filesCompleted: i * 3)
                }
            }
        }

        // Verify final state is consistent
        XCTAssertEqual(publisher.destinations["dest1"]?.filesCompleted, 10)
        XCTAssertEqual(publisher.destinations["dest2"]?.filesCompleted, 20)
        XCTAssertEqual(publisher.destinations["dest3"]?.filesCompleted, 30)
    }

    // MARK: - UI Update Tests

    func testUIUpdatesTriggered() async {
        let progressExpectation = XCTestExpectation(description: "Progress updates received")
        var progressUpdates: [Double] = []

        publisher.$overallProgress
            .dropFirst()
            .sink { progress in
                progressUpdates.append(progress)
                if progressUpdates.count >= 3 {
                    progressExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        publisher.startBackup(totalFiles: 10, totalBytes: 10000, destinationNames: ["dest1"])
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: 3)
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: 6)
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: 10)

        await fulfillment(of: [progressExpectation], timeout: 1.0)

        XCTAssertFalse(progressUpdates.isEmpty)
        XCTAssertTrue(progressUpdates.last! > progressUpdates.first!)
    }

    // MARK: - Cancellation Tests

    func testCancellation() async {
        publisher.startBackup(totalFiles: 100, totalBytes: 100000, destinationNames: ["dest1", "dest2"])
        publisher.updatePhase(.copyingFiles)
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: 50, state: .copying)

        publisher.cancelBackup()

        XCTAssertFalse(publisher.isBackupRunning)
        XCTAssertEqual(publisher.currentPhase, .idle)
        XCTAssertEqual(publisher.destinations["dest1"]?.state, .cancelled)
        XCTAssertEqual(publisher.destinations["dest2"]?.state, .cancelled)
    }

    // MARK: - Reset Tests

    func testReset() async {
        publisher.startBackup(totalFiles: 100, totalBytes: 100000, destinationNames: ["dest1"])
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: 50)
        publisher.reportError(error: "Test error")

        publisher.reset()

        XCTAssertFalse(publisher.isBackupRunning)
        XCTAssertEqual(publisher.currentPhase, .idle)
        XCTAssertEqual(publisher.overallProgress, 0.0)
        XCTAssertTrue(publisher.destinations.isEmpty)
        XCTAssertNil(publisher.lastError)
        XCTAssertTrue(publisher.failedFiles.isEmpty)
    }

    // MARK: - Helper Method Tests

    func testFormatters() {
        XCTAssertEqual(ProgressPublisher.formatBytes(1024), "1 KB")
        XCTAssertEqual(ProgressPublisher.formatBytes(1_048_576), "1 MB")

        XCTAssertEqual(ProgressPublisher.formatSpeed(1.5), "1.5 MB/s")
        XCTAssertEqual(ProgressPublisher.formatSpeed(0.0), "0.0 MB/s")

        XCTAssertEqual(ProgressPublisher.formatETA(30), "Less than a minute")
        XCTAssertEqual(ProgressPublisher.formatETA(90), "1 minute")
        XCTAssertEqual(ProgressPublisher.formatETA(3700), "1h 1m")
    }

    // MARK: - Error Boundary Tests

    func testFailedFilesArrayLimit() async {
        // Test that failedFiles array is limited to prevent unbounded growth
        let maxErrors = 1100 // More than the limit of 1000

        for i in 1...maxErrors {
            publisher.reportError(
                file: "file\(i).txt",
                destination: "dest1",
                error: "Error \(i)"
            )
        }

        // Should only keep last 1000 errors
        XCTAssertEqual(publisher.failedFiles.count, 1000)
        // First 100 errors should have been removed
        XCTAssertEqual(publisher.failedFiles.first?.file, "file101.txt")
        XCTAssertEqual(publisher.failedFiles.last?.file, "file1100.txt")
    }

    func testEmptyDestinationsDivisionByZero() async {
        // Test that updateOverallProgress doesn't crash with empty destinations
        publisher.startBackup(totalFiles: 100, totalBytes: 10000, destinationNames: [])

        // This should not crash
        publisher.updateDestinationProgress(name: "non-existent", filesCompleted: 10)

        XCTAssertEqual(publisher.overallProgress, 0.0)
        XCTAssertTrue(publisher.destinations.isEmpty)
    }

    func testNegativeValues() async {
        // Test that negative values don't break calculations
        publisher.startBackup(totalFiles: -10, totalBytes: -1000, destinationNames: ["dest1"])

        XCTAssertEqual(publisher.totalFiles, -10)
        XCTAssertEqual(publisher.totalBytes, -1000)

        // Should handle negative gracefully
        publisher.updateDestinationProgress(name: "dest1", filesCompleted: -5, bytesTransferred: -500)

        let progress = publisher.destinations["dest1"]
        XCTAssertEqual(progress?.filesCompleted, -5)
        XCTAssertEqual(progress?.bytesTransferred, -500)
    }

    func testExtremellyLargeValues() async {
        // Test with extremely large values
        let largeFiles = Int.max / 2
        let largeBytes = Int64.max / 2

        publisher.startBackup(
            totalFiles: largeFiles,
            totalBytes: largeBytes,
            destinationNames: ["dest1"]
        )

        publisher.reportFileCompleted(
            destination: "dest1",
            fileName: "huge.file",
            size: largeBytes
        )

        XCTAssertEqual(publisher.destinations["dest1"]?.bytesTransferred, largeBytes)
        XCTAssertEqual(publisher.transferredBytes, largeBytes)
    }

    func testRapidStateChanges() async {
        // Test rapid state changes don't cause issues
        publisher.startBackup(totalFiles: 10, totalBytes: 1000, destinationNames: ["dest1"])

        for _ in 1...100 {
            publisher.updatePhase(.analyzingSource)
            publisher.updatePhase(.copyingFiles)
            publisher.updatePhase(.verifyingDestinations)
            publisher.updatePhase(.complete)
            publisher.updatePhase(.idle)
        }

        // Should end in idle state
        XCTAssertEqual(publisher.currentPhase, .idle)
        XCTAssertFalse(publisher.isBackupRunning)
    }

    func testConcurrentErrorReporting() async {
        // Test concurrent error reporting doesn't corrupt state
        publisher.startBackup(totalFiles: 100, totalBytes: 10000, destinationNames: ["dest1"])

        await withTaskGroup(of: Void.self) { group in
            for i in 1...200 {
                group.addTask { [publisher] in
                    await publisher?.reportError(
                        file: "file\(i).txt",
                        destination: "dest1",
                        error: "Concurrent error \(i)"
                    )
                }
            }
        }

        // Should have exactly 200 errors (or 1000 if limit reached)
        XCTAssertLessThanOrEqual(publisher.failedFiles.count, 1000)
        XCTAssertGreaterThan(publisher.failedFiles.count, 0)
    }

    func testVerificationProgressWithNoFiles() async {
        // Test verification with no files to verify
        publisher.startBackup(totalFiles: 0, totalBytes: 0, destinationNames: ["dest1"])

        publisher.updateDestinationProgress(
            name: "dest1",
            state: .verifying,
            isVerifying: true,
            verifiedCount: 10
        )

        // Should handle gracefully even with filesTotal = 0
        XCTAssertEqual(publisher.destinations["dest1"]?.verifiedCount, 10)
        XCTAssertEqual(publisher.destinations["dest1"]?.filesTotal, 0)
    }

    func testNetworkOperationEdgeCases() async {
        // Test network operation with extreme values
        publisher.updateNetworkOperation(
            inProgress: true,
            message: String(repeating: "A", count: 10000), // Very long message
            retryAttempt: Int.max,
            maxAttempts: Int.max
        )

        XCTAssertTrue(publisher.networkOperationInProgress)
        XCTAssertEqual(publisher.networkRetryAttempt, Int.max)
        XCTAssertEqual(publisher.networkRetryMaxAttempts, Int.max)
    }

    func testAnalysisProgressOverflow() async {
        // Test analysis progress with more analyzed than total
        publisher.updateAnalysisProgress(current: 150, total: 100)

        XCTAssertEqual(publisher.analyzedImages, 150)
        XCTAssertEqual(publisher.totalImagesToAnalyze, 100)
        XCTAssertFalse(publisher.isAnalyzing) // Should be false when current >= total
    }

    func testCompleteBackupWithoutStart() async {
        // Test completing backup without starting it
        publisher.completeBackup()

        XCTAssertFalse(publisher.isBackupRunning)
        XCTAssertEqual(publisher.currentPhase, .complete)
        XCTAssertTrue(publisher.destinations.isEmpty)
    }
}