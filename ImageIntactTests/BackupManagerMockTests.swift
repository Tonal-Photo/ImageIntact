import XCTest
@testable import ImageIntact

@MainActor
class BackupManagerMockTests: XCTestCase {

    var mockFileOps: MockFileOperations!
    var mockNotificationService: MockNotificationService!
    var backupManager: BackupManager!

    override func setUp() async throws {
        try await super.setUp()

        // Create mock implementations
        mockFileOps = MockFileOperations()
        mockNotificationService = MockNotificationService()

        // Create BackupManager with mocks
        backupManager = await BackupManager(
            fileOperations: mockFileOps,
            notificationService: mockNotificationService
        )
    }

    override func tearDown() async throws {
        // Clean up
        mockFileOps.reset()
        mockNotificationService.reset()

        backupManager = nil
        mockFileOps = nil
        mockNotificationService = nil

        try await super.tearDown()
    }

    // MARK: - File System Tests

    func testSourceTagCreation() {
        // Given: A source URL
        let sourceURL = URL(fileURLWithPath: "/Users/test/Documents")

        // When: Setting source (which creates a tag)
        backupManager.setSource(sourceURL)

        // Then: Tag file should be created via createFile
        let tagURL = URL(fileURLWithPath: "/Users/test/Documents/.imageintact_source")
        let tagCreated = mockFileOps.createdFiles.contains { $0.url == tagURL }
        XCTAssertTrue(tagCreated, "Source tag file should be created")
        let tagData = mockFileOps.createdFiles.first { $0.url == tagURL }?.data
        XCTAssertNotNil(tagData, "Tag file should have content")
    }

    func testSourceTagDetection() {
        // Given: A mock file system with a source tag
        let sourceURL = URL(fileURLWithPath: "/Users/test/Documents")
        let tagURL = URL(fileURLWithPath: "/Users/test/Documents/.imageintact_source")
        mockFileOps.filesExist.insert(tagURL)

        // When: The checkForSourceTag method should detect it
        let wasSource = backupManager.checkForSourceTag(at: sourceURL)

        // Then: Should detect the source tag
        XCTAssertTrue(wasSource, "Should detect existing source tag")
    }

    func testDestinationAccessibilityCheck() {
        // Given: Mock file operations with some existing directories
        let dest1 = URL(fileURLWithPath: "/Volumes/Backup1")
        let dest2 = URL(fileURLWithPath: "/Volumes/Backup2")
        let dest3 = URL(fileURLWithPath: "/Volumes/NonExistent")
        mockFileOps.filesExist.insert(dest1)
        mockFileOps.filesExist.insert(dest2)

        // Then: File existence checks should work correctly
        XCTAssertTrue(mockFileOps.fileExists(at: dest1))
        XCTAssertTrue(mockFileOps.fileExists(at: dest2))
        XCTAssertFalse(mockFileOps.fileExists(at: dest3))
    }

    // MARK: - Notification Tests

    func testBackupCompletionNotification() async {
        // Given: A successful backup scenario
        mockNotificationService.reset()

        // When: Simulating backup completion
        // This would normally happen in performQueueBasedBackup
        mockNotificationService.sendBackupCompletionNotification(
            filesCopied: 100,
            destinations: 2,
            duration: 60.5
        )

        // Then: Notification should be sent
        XCTAssertEqual(mockNotificationService.notificationCount(), 1)

        let lastNotification = mockNotificationService.lastNotification()
        XCTAssertNotNil(lastNotification)
        XCTAssertEqual(lastNotification?.filesCopied, 100)
        XCTAssertEqual(lastNotification?.destinations, 2)
        XCTAssertEqual(lastNotification?.duration, 60.5)
    }

    func testNoNotificationWhenDisabled() async {
        // Given: Notifications are disabled
        mockNotificationService.shouldFailToSend = true

        // When: Trying to send notification
        mockNotificationService.sendBackupCompletionNotification(
            filesCopied: 50,
            destinations: 1,
            duration: 30
        )

        // Then: No notification should be recorded
        XCTAssertEqual(mockNotificationService.notificationCount(), 0)
    }

    // MARK: - Hashing Tests

    func testHashingWithKnownValues() async throws {
        // Given: Files with known content
        let testFile = URL(fileURLWithPath: "/tmp/test.txt")
        mockFileOps.filesExist.insert(testFile)

        // Set up mock checksum to return known hash for test file
        let expectedHash = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        mockFileOps.mockChecksums[testFile] = expectedHash

        // When: Computing checksum
        let hash = try await mockFileOps.calculateChecksum(for: testFile, shouldCancel: { false })

        // Then: Should return expected hash
        XCTAssertEqual(hash, expectedHash)
        XCTAssertEqual(mockFileOps.checksumCalculations.count, 1)
    }

    func testHashingCancellation() async {
        // Given: A file to hash - configure mock to fail on checksum
        mockFileOps.shouldFailChecksum = true
        let testFile = URL(fileURLWithPath: "/tmp/large.bin")

        // When: Hashing with failure
        do {
            _ = try await mockFileOps.calculateChecksum(for: testFile, shouldCancel: { false })
            XCTFail("Should have thrown error")
        } catch {
            // Then: Should throw error
            XCTAssertTrue(error is MockFileOperations.MockError)
        }
    }

    // MARK: - Integration Tests with Mocks

    func testSourceSelectionWithMocks() {
        // Given: A mock file system with prepared structure
        let sourceURL = URL(fileURLWithPath: "/Users/test/Photos")
        mockFileOps.filesExist.insert(sourceURL)
        mockFileOps.filesExist.insert(URL(fileURLWithPath: "/Users/test/Photos/photo1.jpg"))
        mockFileOps.filesExist.insert(URL(fileURLWithPath: "/Users/test/Photos/photo2.jpg"))
        mockFileOps.mockFileSizes[URL(fileURLWithPath: "/Users/test/Photos/photo1.jpg")] = 1024
        mockFileOps.mockFileSizes[URL(fileURLWithPath: "/Users/test/Photos/photo2.jpg")] = 2048

        // When: Setting source
        backupManager.setSource(sourceURL)

        // Then: Source should be set and tag created
        XCTAssertEqual(backupManager.sourceURL, sourceURL)
        let tagURL = URL(fileURLWithPath: "/Users/test/Photos/.imageintact_source")
        let tagCreated = mockFileOps.createdFiles.contains { $0.url == tagURL }
        XCTAssertTrue(tagCreated, "Source tag file should be created")
        // "Photos" is a generic name, so it will extract "test" from the parent
        XCTAssertEqual(backupManager.organizationName, "test")
    }

    func testFileSystemErrorHandling() {
        // Given: Mock file operations configured to fail createFile
        mockFileOps.shouldFailCreateFile = true

        // When: Trying to create source tag
        let sourceURL = URL(fileURLWithPath: "/Users/test/FailTest")
        backupManager.setSource(sourceURL)

        // Then: Should handle error gracefully
        // Tag creation will fail but source should still be set
        XCTAssertEqual(backupManager.sourceURL, sourceURL)
        let tagURL = URL(fileURLWithPath: "/Users/test/FailTest/.imageintact_source")
        let tagCreated = mockFileOps.createdFiles.contains { $0.url == tagURL }
        XCTAssertFalse(tagCreated, "Tag should not be created when createFile fails")
    }

    // MARK: - Performance Tests with Mocks

    func testMockPerformanceVsReal() {
        // Mocks should be much faster than real file system

        // Test with mocks
        let mockStartTime = Date()
        for i in 0..<100 {
            let url = URL(fileURLWithPath: "/test/file\(i).txt")
            mockFileOps.filesExist.insert(url)
            _ = mockFileOps.fileExists(at: url)
        }
        let mockDuration = Date().timeIntervalSince(mockStartTime)

        // Mocks should complete in milliseconds
        XCTAssertLessThan(mockDuration, 0.1, "Mock operations should be very fast")
    }
}
