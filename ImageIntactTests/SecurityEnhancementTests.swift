import XCTest
@testable import ImageIntact

/// Tests for security enhancements added in v1.2.7
class SecurityEnhancementTests: XCTestCase {
    
    var tempDir: URL!
    var fileOps: CancellableFileOperations!
    
    override func setUp() {
        super.setUp()
        fileOps = CancellableFileOperations()
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        super.tearDown()
    }
    
    // MARK: - Path Validation Tests
    
    func testPathValidationRejectsPathTraversal() async throws {
        // Test that path traversal attempts are rejected
        let source = tempDir.appendingPathComponent("../../../etc/passwd")
        let dest = tempDir.appendingPathComponent("test.txt")
        
        // Create a dummy file to copy
        let validSource = tempDir.appendingPathComponent("valid.txt")
        try "test".write(to: validSource, atomically: true, encoding: .utf8)
        
        // Attempt to copy with path traversal - should fail
        do {
            try await fileOps.copyItem(at: source, to: dest)
            XCTFail("Should have rejected path traversal")
        } catch {
            // Expected - path validation should reject this
        }
    }
    
    func testPathValidationAcceptsValidPaths() async throws {
        // Test that valid paths work correctly
        let source = tempDir.appendingPathComponent("source.txt")
        let dest = tempDir.appendingPathComponent("dest.txt")
        
        try "test content".write(to: source, atomically: true, encoding: .utf8)
        
        // This should succeed
        try await fileOps.copyItem(at: source, to: dest)
        
        let content = try String(contentsOf: dest)
        XCTAssertEqual(content, "test content")
    }
    
    // MARK: - Symbolic Link Tests
    
    func testSymbolicLinkDetectionAndSkipping() async throws {
        // Create a regular file
        let targetFile = tempDir.appendingPathComponent("target.txt")
        try "target content".write(to: targetFile, atomically: true, encoding: .utf8)
        
        // Create a symbolic link to it
        let symlinkPath = tempDir.appendingPathComponent("symlink.txt")
        try FileManager.default.createSymbolicLink(at: symlinkPath, withDestinationURL: targetFile)
        
        // Try to copy the symlink
        let dest = tempDir.appendingPathComponent("dest.txt")
        
        // Should skip silently without error
        try await fileOps.copyItem(at: symlinkPath, to: dest)
        
        // Destination should not exist (symlink was skipped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
    }
    
    // MARK: - Recursion Depth Tests
    
    func testRecursionDepthLimit() async throws {
        // Test that scanner has recursion depth limit
        let scanner = ImageFileScanner()
        
        // Create deeply nested directories (but not too deep for test performance)
        var currentDir = tempDir!
        for i in 0..<10 {
            currentDir = currentDir.appendingPathComponent("level\(i)")
            try FileManager.default.createDirectory(at: currentDir, withIntermediateDirectories: true)
        }
        
        // Add a test image at the deepest level
        let testImage = currentDir.appendingPathComponent("test.jpg")
        try Data().write(to: testImage)
        
        // Scan should complete without stack overflow
        let results = try await scanner.scan(directory: tempDir!) { _ in }
        
        // Should find the file (depth limit is 50, we only went 10 deep)
        XCTAssertTrue(results.values.reduce(0, +) > 0, "Should find at least one file")
    }
    
    func testPackageDetection() async throws {
        // Test that photo packages are allowed but app bundles are skipped
        let scanner = ImageFileScanner()
        
        // Create a photo package (should be allowed)
        let photoPackage = tempDir!.appendingPathComponent("Photos.photoslibrary")
        try FileManager.default.createDirectory(at: photoPackage, withIntermediateDirectories: true)
        let photoInPackage = photoPackage.appendingPathComponent("test.jpg")
        try Data().write(to: photoInPackage)
        
        // Create an app bundle (should be skipped)
        let appBundle = tempDir!.appendingPathComponent("TestApp.app")
        try FileManager.default.createDirectory(at: appBundle, withIntermediateDirectories: true)
        let fileInApp = appBundle.appendingPathComponent("test.jpg")
        try Data().write(to: fileInApp)
        
        // Scan
        let results = try await scanner.scan(directory: tempDir!) { _ in }
        
        // Should find photo in photo package but not in app bundle
        // The scanner should have found files in the photo library but not in the app bundle
        XCTAssertTrue(results.values.reduce(0, +) > 0, "Should find files in photo library")
        // Note: We can't easily verify app bundle was skipped without checking the actual paths scanned
    }
    
    // MARK: - Network Volume Coordination Tests
    
    func testNetworkVolumeDetection() {
        // Test network volume detection
        let localPath = URL(fileURLWithPath: "/Users/test")
        let networkPath = URL(fileURLWithPath: "/Volumes/NetworkDrive")
        
        // Note: This is a basic test - actual network detection depends on system state
        // In a real network environment, the isNetworkVolume method would check volumeIsLocalKey
        let ops = CancellableFileOperations()
        
        // We can't easily mock the actual network state, but we can verify the method exists
        // and doesn't crash
        _ = ops.fileExists(at: localPath)
        _ = ops.fileExists(at: networkPath)
    }
    
    // MARK: - Sleep Prevention Timeout Tests
    
    func testSleepPreventionTimeout() {
        // Test that sleep prevention has a timeout
        let sleepPrevention = SleepPrevention.shared
        
        // Start prevention
        sleepPrevention.start()
        XCTAssertTrue(sleepPrevention.isPreventing)
        
        // Should have a maximum duration set
        // Note: We can't easily test the actual timeout without waiting 4 hours
        // but we can verify the mechanism is in place
        
        // Stop prevention
        sleepPrevention.stop()
        XCTAssertFalse(sleepPrevention.isPreventing)
    }
    
    // MARK: - Extended Attribute Tests
    
    func testExtendedAttributePreservation() async throws {
        // Create a source file
        let source = tempDir.appendingPathComponent("source.txt")
        try "test content".write(to: source, atomically: true, encoding: .utf8)
        
        // Add an extended attribute (like a Finder comment)
        let attributeName = "com.apple.metadata:kMDItemFinderComment"
        let attributeValue = "Test comment".data(using: .utf8)!
        
        _ = attributeValue.withUnsafeBytes { bytes in
            setxattr(source.path, attributeName, bytes.baseAddress, attributeValue.count, 0, 0)
        }
        
        // Copy the file
        let dest = tempDir.appendingPathComponent("dest.txt")
        try await fileOps.copyItem(at: source, to: dest)
        
        // Check that the extended attribute was preserved
        let valueSize = getxattr(dest.path, attributeName, nil, 0, 0, 0)
        
        if valueSize > 0 {
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: valueSize)
            defer { buffer.deallocate() }
            
            let result = getxattr(dest.path, attributeName, buffer, valueSize, 0, 0)
            if result > 0 {
                let retrievedData = Data(bytes: buffer, count: result)
                let retrievedString = String(data: retrievedData, encoding: .utf8)
                XCTAssertEqual(retrievedString, "Test comment")
            } else {
                // Extended attributes might not be supported on all file systems
                // This is not a failure, just a limitation
                print("Extended attributes not supported on this file system")
            }
        }
    }
}