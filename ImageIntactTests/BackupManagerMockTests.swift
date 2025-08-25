import XCTest
@testable import ImageIntact

@MainActor
class BackupManagerMockTests: XCTestCase {
    
    var mockFileSystem: MockFileSystem!
    var mockHasher: MockHasher!
    var mockNotificationService: MockNotificationService!
    var backupManager: BackupManager!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create mock implementations
        mockFileSystem = MockFileSystem()
        mockHasher = MockHasher()
        mockNotificationService = MockNotificationService()
        
        // Create BackupManager with mocks
        backupManager = await BackupManager(
            fileSystem: mockFileSystem,
            hasher: mockHasher,
            notificationService: mockNotificationService
        )
    }
    
    override func tearDown() async throws {
        // Clean up
        mockFileSystem.reset()
        mockHasher.reset()
        mockNotificationService.reset()
        
        backupManager = nil
        mockFileSystem = nil
        mockHasher = nil
        mockNotificationService = nil
        
        try await super.tearDown()
    }
    
    // MARK: - File System Tests
    
    func testSourceTagCreation() {
        // Given: A source URL
        let sourceURL = URL(fileURLWithPath: "/Users/test/Documents")
        
        // When: Setting source (which creates a tag)
        backupManager.setSource(sourceURL)
        
        // Then: Tag file should be created in mock file system
        let tagPath = "/Users/test/Documents/.imageintact_source"
        XCTAssertTrue(mockFileSystem.files.contains(tagPath), "Source tag file should be created")
        XCTAssertNotNil(mockFileSystem.fileContents[tagPath], "Tag file should have content")
    }
    
    func testSourceTagDetection() {
        // Given: A mock file system with a source tag
        let sourceURL = URL(fileURLWithPath: "/Users/test/Documents")
        let tagPath = "/Users/test/Documents/.imageintact_source"
        mockFileSystem.addTestFile(at: tagPath, contents: Data("source tag".utf8))
        
        // When: Setting a destination that was previously a source
        // The checkForSourceTag method should detect it
        let wasSource = backupManager.checkForSourceTag(at: sourceURL)
        
        // Then: Should detect the source tag
        XCTAssertTrue(wasSource, "Should detect existing source tag")
    }
    
    func testDestinationAccessibilityCheck() {
        // Given: Mock file system with some existing directories
        mockFileSystem.addTestDirectory(at: "/Volumes/Backup1")
        mockFileSystem.addTestDirectory(at: "/Volumes/Backup2")
        
        // When: Adding destinations
        let dest1 = URL(fileURLWithPath: "/Volumes/Backup1")
        let dest2 = URL(fileURLWithPath: "/Volumes/Backup2")
        let dest3 = URL(fileURLWithPath: "/Volumes/NonExistent")
        
        // Then: File system checks should work correctly
        XCTAssertTrue(mockFileSystem.fileExists(at: dest1))
        XCTAssertTrue(mockFileSystem.fileExists(at: dest2))
        XCTAssertFalse(mockFileSystem.fileExists(at: dest3))
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
        mockFileSystem.addTestFile(at: "/tmp/test.txt", contents: Data("test".utf8))
        
        // Set up mock hasher to return known hash for "test"
        mockHasher.setMockHash("9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", for: testFile)
        
        // When: Computing hash
        let hash = try await mockHasher.sha256(for: testFile, shouldCancel: { false })
        
        // Then: Should return expected hash
        XCTAssertEqual(hash, "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08")
        XCTAssertEqual(mockHasher.callCount, 1)
    }
    
    func testHashingCancellation() async {
        // Given: A file to hash
        let testFile = URL(fileURLWithPath: "/tmp/large.bin")
        
        // When: Hashing with cancellation
        do {
            _ = try await mockHasher.sha256(for: testFile, shouldCancel: { true })
            XCTFail("Should have thrown cancellation error")
        } catch {
            // Then: Should throw error
            XCTAssertTrue(error.localizedDescription.contains("cancelled"))
        }
    }
    
    // MARK: - Integration Tests with Mocks
    
    func testSourceSelectionWithMocks() {
        // Given: A mock file system with prepared structure
        let sourceURL = URL(fileURLWithPath: "/Users/test/Photos")
        mockFileSystem.addTestDirectory(at: "/Users/test/Photos")
        mockFileSystem.addTestFile(at: "/Users/test/Photos/photo1.jpg", size: 1024)
        mockFileSystem.addTestFile(at: "/Users/test/Photos/photo2.jpg", size: 2048)
        
        // When: Setting source
        backupManager.setSource(sourceURL)
        
        // Then: Source should be set and tag created
        XCTAssertEqual(backupManager.sourceURL, sourceURL)
        XCTAssertTrue(mockFileSystem.files.contains("/Users/test/Photos/.imageintact_source"))
        // "Photos" is a generic name, so it will extract "test" from the parent
        XCTAssertEqual(backupManager.organizationName, "test")
    }
    
    func testFileSystemErrorHandling() {
        // Given: Mock file system configured to fail
        mockFileSystem.shouldFailCreate = true
        
        // When: Trying to create source tag
        let sourceURL = URL(fileURLWithPath: "/Users/test/FailTest")
        backupManager.setSource(sourceURL)
        
        // Then: Should handle error gracefully
        // Tag creation will fail but source should still be set
        XCTAssertEqual(backupManager.sourceURL, sourceURL)
        XCTAssertFalse(mockFileSystem.files.contains("/Users/test/FailTest/.imageintact_source"))
    }
    
    // MARK: - Performance Tests with Mocks
    
    func testMockPerformanceVsReal() {
        // Mocks should be much faster than real file system
        
        // Test with mocks
        let mockStartTime = Date()
        for i in 0..<100 {
            let path = "/test/file\(i).txt"
            mockFileSystem.addTestFile(at: path)
            _ = mockFileSystem.fileExists(atPath: path)
        }
        let mockDuration = Date().timeIntervalSince(mockStartTime)
        
        // Mocks should complete in milliseconds
        XCTAssertLessThan(mockDuration, 0.1, "Mock operations should be very fast")
    }
}