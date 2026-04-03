//
//  OrganizationNameSanitizationTests.swift
//  ImageIntactTests
//
//  Tests for organization name sanitization (GH issue #91 finding #8).
//  Raw TextField input was used in path construction without validation.
//

@testable import ImageIntact
import XCTest

@MainActor
final class OrganizationNameSanitizationTests: XCTestCase {

    var backupManager: BackupManager!

    override func setUp() async throws {
        try await super.setUp()
        backupManager = BackupManager()
    }

    override func tearDown() async throws {
        backupManager = nil
        try await super.tearDown()
    }

    func testSlashesReplacedWithUnderscore() {
        backupManager.organizationName = "Photos/2024"
        XCTAssertEqual(backupManager.organizationName, "Photos_2024",
                       "Forward slashes should be replaced to prevent path splitting")
    }

    func testBackslashesReplacedWithUnderscore() {
        backupManager.organizationName = "Photos\\Backup"
        XCTAssertEqual(backupManager.organizationName, "Photos_Backup")
    }

    func testLeadingDotsStripped() {
        backupManager.organizationName = ".hidden_folder"
        XCTAssertEqual(backupManager.organizationName, "hidden_folder",
                       "Leading dots should be stripped to prevent hidden directories")
    }

    func testTrailingDotsStripped() {
        backupManager.organizationName = "folder."
        XCTAssertEqual(backupManager.organizationName, "folder",
                       "Trailing dots should be stripped")
    }

    func testLengthLimitedTo255Bytes() {
        let longName = String(repeating: "a", count: 300)
        backupManager.organizationName = longName
        XCTAssertLessThanOrEqual(backupManager.organizationName.utf8.count, 255,
                                 "Name should be truncated to 255 UTF-8 bytes (APFS/HFS+ limit)")
    }

    func testMultiByteCharactersRespectByteLimit() {
        // Each emoji is 4 UTF-8 bytes, so 64 emojis = 256 bytes (over limit)
        let emojiName = String(repeating: "📷", count: 64)
        backupManager.organizationName = emojiName
        XCTAssertLessThanOrEqual(backupManager.organizationName.utf8.count, 255,
                                 "Multi-byte characters must respect 255 byte limit, not character limit")
        XCTAssertGreaterThan(backupManager.organizationName.count, 0, "Should not be empty")
    }

    func testNormalNameUnchanged() {
        backupManager.organizationName = "My Photos 2024"
        XCTAssertEqual(backupManager.organizationName, "My Photos 2024")
    }

    func testEmptyNameAllowed() {
        backupManager.organizationName = ""
        XCTAssertEqual(backupManager.organizationName, "")
    }

    func testMultipleSpecialCharacters() {
        backupManager.organizationName = "../../../etc/passwd"
        XCTAssertFalse(backupManager.organizationName.contains("/"),
                       "Path traversal attempts should be neutralized")
        XCTAssertFalse(backupManager.organizationName.hasPrefix("."),
                       "Leading dots from traversal should be stripped")
    }

    func testColonReplacedWithUnderscore() {
        backupManager.organizationName = "Photos:2024"
        XCTAssertEqual(backupManager.organizationName, "Photos_2024",
                       "Colons should be replaced (macOS Finder path separator)")
    }

    func testNullBytesStripped() {
        backupManager.organizationName = "Photos\0Backup"
        XCTAssertFalse(backupManager.organizationName.contains("\0"),
                       "Null bytes should be stripped")
    }
}
