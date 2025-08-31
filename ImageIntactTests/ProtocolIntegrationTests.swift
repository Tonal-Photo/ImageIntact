//
//  ProtocolIntegrationTests.swift
//  ImageIntactTests
//
//  Tests for new protocol implementations
//

import XCTest
@testable import ImageIntact

@MainActor
class ProtocolIntegrationTests: XCTestCase {
    
    // MARK: - Duplicate Detector Protocol Tests
    
    func testMockDuplicateDetectorImplementsProtocol() async {
        // Given
        let mockDetector = MockDuplicateDetector()
        mockDetector.shouldReturnDuplicates = true
        
        let manifest = [
            FileManifestEntry(
                relativePath: "test.jpg",
                sourceURL: URL(fileURLWithPath: "/test.jpg"),
                checksum: "abc123",
                size: 1024
            )
        ]
        
        // When
        let analysis = await mockDetector.analyzeForDuplicates(
            manifest: manifest,
            destination: URL(fileURLWithPath: "/dest"),
            organizationName: "TestOrg"
        )
        
        // Then
        XCTAssertEqual(mockDetector.analyzeCallCount, 1)
        XCTAssertEqual(analysis.exactDuplicates.count, 1)
        XCTAssertEqual(analysis.totalSourceFiles, 1)
    }
    
    func testBackupManagerAcceptsDuplicateDetectorProtocol() {
        // Given
        let mockDetector = MockDuplicateDetector()
        
        // When
        let backupManager = BackupManager(
            duplicateDetector: mockDetector
        )
        
        // Then
        XCTAssertTrue(backupManager.duplicateDetector is MockDuplicateDetector)
    }
    
    // MARK: - Error Handler Protocol Tests
    
    func testMockRetryHandlerImplementsProtocol() async {
        // Given
        let mockHandler = MockRetryHandler()
        await mockHandler.reset()  // Reset first
        
        var attempts = 0
        
        // When
        let result = try? await mockHandler.executeWithRetry(
            operation: "Test operation"
        ) {
            attempts += 1
            return "Success"
        }
        
        // Then
        let callCount = await mockHandler.executeCallCount
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(result, "Success")
    }
    
    func testMockErrorClassifierCategorization() {
        // Given
        MockErrorClassifier.mockCategory = .transient
        let error = NSError(domain: "Test", code: -1)
        
        // When
        let category = MockErrorClassifier.classify(error)
        let canRetry = MockErrorClassifier.isSafeToRetry(error)
        
        // Then
        XCTAssertEqual(category, .transient)
        XCTAssertTrue(canRetry)
        XCTAssertEqual(MockErrorClassifier.classifyCallCount, 1)
        
        // Cleanup
        MockErrorClassifier.reset()
    }
    
    // MARK: - Event Logger Protocol Tests
    
    func testMockEventLoggerImplementsProtocol() {
        // Given
        let mockLogger = MockEventLogger()
        let sourceURL = URL(fileURLWithPath: "/source")
        
        // When
        let sessionID = mockLogger.startSession(
            sourceURL: sourceURL,
            fileCount: 10,
            totalBytes: 1024,
            sessionID: nil
        )
        
        mockLogger.logEvent(
            type: .copy,
            severity: .info,
            file: URL(fileURLWithPath: "/test.jpg"),
            destination: URL(fileURLWithPath: "/dest/test.jpg"),
            fileSize: 1024,
            checksum: "abc123",
            error: nil,
            metadata: nil,
            duration: 1.5
        )
        
        mockLogger.completeSession(status: "completed")
        
        // Then
        XCTAssertEqual(mockLogger.startSessionCallCount, 1)
        XCTAssertEqual(mockLogger.logEventCallCount, 1)
        XCTAssertEqual(mockLogger.completeSessionCallCount, 1)
        XCTAssertEqual(mockLogger.loggedEvents.count, 1)
        XCTAssertEqual(mockLogger.loggedEvents.first?.type, .copy)
        XCTAssertNotNil(UUID(uuidString: sessionID))
    }
    
    // MARK: - Integration Tests
    
    func testBackupManagerWithAllMockProtocols() async {
        // Given
        let mockFileSystem = MockFileSystem()
        let mockHasher = MockHasher()
        let mockNotification = MockNotificationService()
        let mockDriveAnalyzer = MockDriveAnalyzer()
        let mockDiskSpace = MockDiskSpaceChecker()
        let mockDuplicateDetector = MockDuplicateDetector()
        
        // When
        let backupManager = BackupManager(
            fileSystem: mockFileSystem,
            hasher: mockHasher,
            notificationService: mockNotification,
            driveAnalyzer: mockDriveAnalyzer,
            diskSpaceChecker: mockDiskSpace,
            duplicateDetector: mockDuplicateDetector
        )
        
        // Then
        XCTAssertNotNil(backupManager)
        XCTAssertTrue(backupManager.fileSystem is MockFileSystem)
        XCTAssertTrue(backupManager.hasher is MockHasher)
        XCTAssertTrue(backupManager.notificationService is MockNotificationService)
        XCTAssertTrue(backupManager.driveAnalyzer is MockDriveAnalyzer)
        XCTAssertTrue(backupManager.diskSpaceChecker is MockDiskSpaceChecker)
        XCTAssertTrue(backupManager.duplicateDetector is MockDuplicateDetector)
    }
    
    func testDuplicateDetectorFilteringWithProtocol() {
        // Given
        let detector: DuplicateDetectorProtocol = MockDuplicateDetector()
        
        let manifest = [
            FileManifestEntry(
                relativePath: "keep.jpg",
                sourceURL: URL(fileURLWithPath: "/keep.jpg"),
                checksum: "keep123",
                size: 1024
            ),
            FileManifestEntry(
                relativePath: "skip.jpg",
                sourceURL: URL(fileURLWithPath: "/skip.jpg"),
                checksum: "skip456",
                size: 2048
            )
        ]
        
        let analysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 2,
            exactDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: manifest[1],
                    destinationPath: "/dest/skip.jpg",
                    checksum: "skip456",
                    isDifferentName: false,
                    existingOrganization: nil
                )
            ],
            renamedDuplicates: [],
            uniqueFiles: 1,
            potentialSpaceSaved: 2048,
            destinationDriveUUID: nil
        )
        
        // When
        let filtered = detector.filterManifest(
            manifest,
            excludingDuplicates: analysis,
            skipExact: true,
            skipRenamed: false
        )
        
        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered.first?.checksum, "keep123")
    }
}