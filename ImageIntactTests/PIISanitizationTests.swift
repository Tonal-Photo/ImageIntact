//
//  PIISanitizationTests.swift
//  ImageIntactTests
//
//  Tests for Personally Identifiable Information (PII) sanitization in bug reports
//

import XCTest
@testable import ImageIntact

class PIISanitizationTests: XCTestCase {
    
    var sanitizer: PIISanitizer!
    
    override func setUp() {
        super.setUp()
        sanitizer = PIISanitizer()
    }
    
    override func tearDown() {
        sanitizer = nil
        super.tearDown()
    }
    
    // MARK: - Username Sanitization
    
    func testSanitizeUsername() {
        let input = "/Users/johndoe/Documents/Photos/wedding.jpg"
        let expected = "/Users/[USER]/Documents/Photos/[FILENAME].jpg"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, expected)
    }
    
    func testSanitizeMultipleUsernames() {
        let input = """
        Source: /Users/alice/Pictures/
        Destination: /Users/bob/Backup/
        Error: /Users/charlie/Desktop/photo.raw
        """
        let result = sanitizer.sanitize(input)
        XCTAssertFalse(result.contains("alice"))
        XCTAssertFalse(result.contains("bob"))
        XCTAssertFalse(result.contains("charlie"))
        XCTAssertTrue(result.contains("/Users/[USER]/"))
    }
    
    // MARK: - Volume Name Sanitization
    
    func testSanitizeVolumeName() {
        let input = "/Volumes/Johns-Backup-Drive/Photos/image.nef"
        let expected = "/Volumes/[VOLUME]/Photos/[FILENAME].nef"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, expected)
    }
    
    func testSanitizeMultipleVolumes() {
        let input = """
        Copying from /Volumes/SD-Card-1/DCIM/
        Copying to /Volumes/External-SSD/Backups/
        Also to /Volumes/Network-Drive/Archive/
        """
        let result = sanitizer.sanitize(input)
        XCTAssertFalse(result.contains("SD-Card-1"))
        XCTAssertFalse(result.contains("External-SSD"))
        XCTAssertFalse(result.contains("Network-Drive"))
        XCTAssertTrue(result.contains("/Volumes/[VOLUME]/"))
    }
    
    // MARK: - Filename Sanitization
    
    func testSanitizeFilename() {
        let input = "Processing Smith-Wedding-001.NEF"
        let expected = "Processing [FILENAME].NEF"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, expected)
    }
    
    func testPreserveFileExtensions() {
        let testCases = [
            ("photo.jpg", "[FILENAME].jpg"),
            ("document.pdf", "[FILENAME].pdf"),
            ("RAW_001.nef", "[FILENAME].nef"),
            ("video.mov", "[FILENAME].mov"),
            ("sidecar.xmp", "[FILENAME].xmp")
        ]
        
        for (input, expected) in testCases {
            let result = sanitizer.sanitize(input)
            XCTAssertEqual(result, expected, "Failed for \(input)")
        }
    }
    
    func testSanitizeFilenamesInPaths() {
        let input = "/Users/john/Photos/2024-01-15_Wedding/DSC_001.NEF"
        let result = sanitizer.sanitize(input)
        XCTAssertFalse(result.contains("2024-01-15_Wedding"))
        XCTAssertFalse(result.contains("DSC_001"))
        XCTAssertTrue(result.contains("[DIRECTORY]"))
        XCTAssertTrue(result.contains("[FILENAME].NEF"))
    }
    
    // MARK: - Network Path Sanitization
    
    func testSanitizeIPAddress() {
        let input = "Connecting to //192.168.1.100/SharedPhotos"
        let expected = "Connecting to //[NETWORK]/SharedPhotos"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, expected)
    }
    
    func testSanitizeHostname() {
        let input = "Mounting smb://macmini.local/Backup"
        let expected = "Mounting smb://[NETWORK]/Backup"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, expected)
    }
    
    // MARK: - Email Sanitization
    
    func testSanitizeEmail() {
        let input = "User email: john.doe@example.com reported this issue"
        let expected = "User email: [EMAIL] reported this issue"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, expected)
    }
    
    // MARK: - Preserve Important Information
    
    func testPreserveErrorMessages() {
        let input = "Error: Checksum mismatch detected for file"
        let result = sanitizer.sanitize(input)
        XCTAssertTrue(result.contains("Checksum mismatch"))
        XCTAssertTrue(result.contains("Error:"))
    }
    
    func testPreserveFileCountsAndSizes() {
        let input = "Found 1,234 files totaling 45.6 GB"
        let result = sanitizer.sanitize(input)
        XCTAssertTrue(result.contains("1,234"))
        XCTAssertTrue(result.contains("45.6 GB"))
    }
    
    func testPreserveTimestamps() {
        let input = "2024-01-15T14:30:45Z - Backup started"
        let result = sanitizer.sanitize(input)
        XCTAssertTrue(result.contains("2024-01-15T14:30:45Z"))
        XCTAssertTrue(result.contains("Backup started"))
    }
    
    func testPreserveFileTypes() {
        let input = "Processing: 500 NEF files, 500 XMP files, 100 JPG files"
        let result = sanitizer.sanitize(input)
        XCTAssertTrue(result.contains("500 NEF"))
        XCTAssertTrue(result.contains("500 XMP"))
        XCTAssertTrue(result.contains("100 JPG"))
    }
    
    // MARK: - Complex Log Sanitization
    
    func testSanitizeCompleteLogEntry() {
        let input = """
        2024-01-15T10:30:00Z [INFO] Backup started
        Source: /Users/johndoe/Pictures/Wedding2024/
        Destination 1: /Volumes/Backup-Drive/Photos/
        Destination 2: //192.168.1.50/NetworkBackup/
        
        Processing files:
        - Copied: /Users/johndoe/Pictures/Wedding2024/DSC_0001.NEF (24.5 MB)
        - Copied: /Users/johndoe/Pictures/Wedding2024/DSC_0001.XMP (4 KB)
        - Error: /Users/johndoe/Pictures/Wedding2024/DSC_0002.NEF - Checksum mismatch
        
        Summary: 2 files copied, 1 error
        Contact: user@example.com for issues
        """
        
        let result = sanitizer.sanitize(input)
        
        // Check PII is removed
        XCTAssertFalse(result.contains("johndoe"))
        XCTAssertFalse(result.contains("Wedding2024"))
        XCTAssertFalse(result.contains("Backup-Drive"))
        XCTAssertFalse(result.contains("192.168.1.50"))
        XCTAssertFalse(result.contains("DSC_0001"))
        XCTAssertFalse(result.contains("DSC_0002"))
        XCTAssertFalse(result.contains("user@example.com"))
        
        // Check important info is preserved
        XCTAssertTrue(result.contains("2024-01-15T10:30:00Z"))
        XCTAssertTrue(result.contains("[INFO]"))
        XCTAssertTrue(result.contains("Backup started"))
        XCTAssertTrue(result.contains("24.5 MB"))
        XCTAssertTrue(result.contains("4 KB"))
        XCTAssertTrue(result.contains("Checksum mismatch"))
        XCTAssertTrue(result.contains("2 files copied, 1 error"))
        XCTAssertTrue(result.contains(".NEF"))
        XCTAssertTrue(result.contains(".XMP"))
    }
    
    // MARK: - Edge Cases
    
    func testEmptyString() {
        let result = sanitizer.sanitize("")
        XCTAssertEqual(result, "")
    }
    
    func testNilHandling() {
        let result = sanitizer.sanitizeOptional(nil)
        XCTAssertNil(result)
    }
    
    func testNoSensitiveData() {
        let input = "Backup completed successfully with 0 errors"
        let result = sanitizer.sanitize(input)
        XCTAssertEqual(result, input, "Should not modify logs without PII")
    }
    
    func testWindowsPaths() {
        let input = "C:\\Users\\johndoe\\Documents\\photo.jpg"
        let result = sanitizer.sanitize(input)
        XCTAssertFalse(result.contains("johndoe"))
        XCTAssertTrue(result.contains("[USER]"))
    }
    
    // MARK: - Performance
    
    func testSanitizationPerformance() {
        let longLog = String(repeating: "/Users/testuser/Documents/photo.jpg\n", count: 1000)
        
        measure {
            _ = sanitizer.sanitize(longLog)
        }
    }
    
    // MARK: - Sanitization Report
    
    func testGenerateSanitizationReport() {
        let input = """
        /Users/alice/Photos/image.jpg
        /Volumes/Backup/archive.nef
        user@email.com
        """
        
        let result = sanitizer.sanitizeWithReport(input)
        
        XCTAssertNotNil(result.sanitizedText)
        XCTAssertNotNil(result.report)
        
        // Check report contains what was removed
        XCTAssertTrue(result.report.contains("1 username"))
        XCTAssertTrue(result.report.contains("1 volume"))
        XCTAssertTrue(result.report.contains("1 email"))
        XCTAssertTrue(result.report.contains("2 filenames"))
    }
}