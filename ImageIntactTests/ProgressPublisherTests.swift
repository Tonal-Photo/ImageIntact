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
}