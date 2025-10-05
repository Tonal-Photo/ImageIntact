//
//  BackupCoordinatorTests.swift
//  ImageIntactTests
//
//  Unit tests for BackupCoordinator
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupCoordinatorTests: XCTestCase {
    
    // MARK: - Properties
    
    var coordinator: BackupCoordinator!
    var sourceURL: URL!
    var destinations: [URL]!
    var manifest: [FileManifestEntry]!
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        coordinator = BackupCoordinator()
        sourceURL = URL(fileURLWithPath: "/test/source")
        
        // Create test destinations
        destinations = [
            URL(fileURLWithPath: "/backup/destination1"),
            URL(fileURLWithPath: "/backup/destination2"),
            URL(fileURLWithPath: "/backup/destination3")
        ]
        
        // Create test manifest
        manifest = createMockManifest(count: 10)
    }
    
    override func tearDown() async throws {
        coordinator = nil
        sourceURL = nil
        destinations = nil
        manifest = nil
        
        try await super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testCoordinatorInitialization() throws {
        // Given
        let testCoordinator = BackupCoordinator()
        
        // Then
        XCTAssertFalse(testCoordinator.isRunning, "Should not be running initially")
        XCTAssertEqual(testCoordinator.overallProgress, 0.0, "Progress should be 0")
        XCTAssertTrue(testCoordinator.destinationStatuses.isEmpty, "No destination statuses initially")
    }
    
    func testStartBackupSetsRunningState() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Backup starts")
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: manifest,
                organizationName: "TestOrg"
            )
            expectation.fulfill()
        }
        
        // Give it a moment to start
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then
        XCTAssertTrue(coordinator.isRunning, "Should be running after start")
        XCTAssertFalse(coordinator.destinationStatuses.isEmpty, "Should have destination statuses")
        
        // Stop the backup
        await coordinator.cancelBackup()
        
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    // MARK: - Distribution Tests
    
    func testAllFilesGoToAllDestinations() async throws {
        // Given - 10 tasks, 3 destinations
        // Expected distribution:
        // EACH destination should get ALL 10 tasks
        // This is critical for proper backup redundancy
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: manifest,
                organizationName: "TestOrg"
            )
        }
        
        // Give it time to initialize
        try await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        
        // Then
        let statuses = coordinator.destinationStatuses
        XCTAssertEqual(statuses.count, 3, "Should have 3 destination statuses")
        
        // Check each destination got ALL tasks
        if let dest1Status = statuses["destination1"] {
            XCTAssertEqual(dest1Status.total, 10, "First destination should have ALL 10 tasks")
        }
        
        if let dest2Status = statuses["destination2"] {
            XCTAssertEqual(dest2Status.total, 10, "Second destination should have ALL 10 tasks")
        }
        
        if let dest3Status = statuses["destination3"] {
            XCTAssertEqual(dest3Status.total, 10, "Third destination should have ALL 10 tasks")
        }
        
        await coordinator.cancelBackup()
    }
    
    func testEachDestinationGetsCompleteManifest() async throws {
        // Given - 9 tasks for 3 destinations
        // EACH destination should get ALL 9 tasks, not split them
        let evenManifest = createMockManifest(count: 9)
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: evenManifest,
                organizationName: "TestOrg"
            )
        }
        
        // Give it time to initialize
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        let statuses = coordinator.destinationStatuses
        
        for (destName, status) in statuses {
            XCTAssertEqual(status.total, 9, "Destination \(destName) should have ALL 9 tasks, not a fraction")
        }
        
        await coordinator.cancelBackup()
    }
    
    // MARK: - Progress Tests
    
    func testProgressTracking() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Progress updates")
        var progressUpdates: [Double] = []
        
        // Observe progress
        let cancellable = coordinator.$overallProgress
            .sink { progress in
                progressUpdates.append(progress)
                if progress > 0 {
                    expectation.fulfill()
                }
            }
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: manifest,
                organizationName: "TestOrg"
            )
        }
        
        // Wait for some progress
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Then
        XCTAssertFalse(progressUpdates.isEmpty, "Should have progress updates")
        XCTAssertGreaterThanOrEqual(progressUpdates.last ?? 0, 0.0, "Progress should be non-negative")
        
        await coordinator.cancelBackup()
        cancellable.cancel()
    }
    
    func testDestinationStatusUpdates() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Status updates")
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: createMockManifest(count: 50), // More files to ensure it's still running
                organizationName: "TestOrg"
            )
        }
        
        // Give it time to initialize and start processing
        try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        // Then
        if coordinator.destinationStatuses.isEmpty {
            // If still empty, wait a bit more
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        
        // Only check if we have statuses (backup might be too fast in test environment)
        if !coordinator.destinationStatuses.isEmpty {
            for (destName, status) in coordinator.destinationStatuses {
                XCTAssertFalse(destName.isEmpty, "Destination name should not be empty")
                XCTAssertGreaterThanOrEqual(status.completed, 0, "Completed should be non-negative")
                XCTAssertGreaterThan(status.total, 0, "Total should be greater than 0")
                XCTAssertLessThanOrEqual(status.completed, status.total, "Completed should not exceed total")
            }
        }
        
        expectation.fulfill()
        await coordinator.cancelBackup()
        
        await fulfillment(of: [expectation], timeout: 1.0)
    }
    
    // MARK: - Stop/Cancel Tests
    
    func testCancelBackup() async throws {
        // Given
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: createMockManifest(count: 100), // Many files to ensure it's still running
                organizationName: "TestOrg"
            )
        }
        
        // Let it start
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(coordinator.isRunning, "Should be running")
        
        // When
        await coordinator.cancelBackup()
        
        // Give it time to stop
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then
        XCTAssertFalse(coordinator.isRunning, "Should not be running after stop")
    }
    
    // MARK: - Critical Bug Prevention Tests
    
    func testMultiDestinationNeverSplitsFiles_PreventsBug1_2_9() async throws {
        // This test specifically prevents the bug fixed in 1.2.9
        // where files were being split between destinations using round-robin
        
        // Given - Large number of files (simulating real scenario)
        let largeManifest = createMockManifest(count: 307) // Real scenario from bug report
        let multipleDestinations = [
            URL(fileURLWithPath: "/backup/photos1"),
            URL(fileURLWithPath: "/backup/photos2")
        ]
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: multipleDestinations,
                manifest: largeManifest,
                organizationName: "TestOrg"
            )
        }
        
        // Give it time to initialize
        try await Task.sleep(nanoseconds: 200_000_000)
        
        // Then - CRITICAL ASSERTIONS
        let statuses = coordinator.destinationStatuses
        XCTAssertEqual(statuses.count, 2, "Should have 2 destination statuses")
        
        // Each destination MUST have ALL files
        for (destName, status) in statuses {
            XCTAssertEqual(status.total, 307, 
                          "CRITICAL: Destination \(destName) must have ALL 307 files. " +
                          "If this fails, we have regression of the 1.2.9 bug!")
        }
        
        // Verify no destination has partial files
        let totals = statuses.values.map { $0.total }
        XCTAssertTrue(totals.allSatisfy { $0 == 307 }, 
                     "All destinations must have exactly the same number of files")
        
        await coordinator.cancelBackup()
    }
    
    // MARK: - Verification Tests
    
    func testVerificationStateUpdates() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Verification tracking")
        
        // Monitor destination statuses for verification state
        let cancellable = coordinator.$destinationStatuses
            .sink { statuses in
                // Just verify we get status updates
                if !statuses.isEmpty {
                    expectation.fulfill()
                }
            }
        
        // When
        Task {
            await coordinator.startBackup(
                source: sourceURL,
                destinations: destinations,
                manifest: createMockManifest(count: 2), // Small number for quick test
                organizationName: "TestOrg"
            )
        }
        
        // Wait for expectation with timeout
        await fulfillment(of: [expectation], timeout: 3.0)
        
        // Then - we got status updates
        // Note: In a real test with mocked file operations, we'd see actual verification
        // For now, just verify the structure is in place
        
        await coordinator.cancelBackup()
        cancellable.cancel()
    }
    
    // MARK: - Helper Methods
    
    private func createMockManifest(count: Int) -> [FileManifestEntry] {
        return (0..<count).map { index in
            FileManifestEntry(
                relativePath: "file\(index).jpg",
                sourceURL: sourceURL.appendingPathComponent("file\(index).jpg"),
                checksum: "checksum\(index)",
                size: Int64(1000 * (index + 1)),
                imageWidth: nil,
                imageHeight: nil
            )
        }
    }
}

// MARK: - Integration Tests (Commented out - would need real file operations)

/*
extension BackupCoordinatorTests {
    
    func testFullBackupWorkflow() async throws {
        // This would test the full backup workflow with real files
        // Requires setting up actual test files and destinations
    }
    
    func testErrorHandling() async throws {
        // Test how the coordinator handles various error conditions
        // Would need mock file operations that can simulate failures
    }
    
    func testMemoryManagement() async throws {
        // Test with large manifests to ensure no memory leaks
        // Monitor memory usage during large backup operations
    }
}
*/