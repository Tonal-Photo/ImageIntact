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

    // MARK: - AMUX-209: Extended control-character + path-traversal coverage

    /// Path traversal: a leading `..` is dot-stripped by the existing logic.
    func testParentDirReference_dotsStripped() {
        backupManager.organizationName = ".."
        XCTAssertEqual(backupManager.organizationName, "",
                       "Bare `..` collapses to empty after dot-stripping")
    }

    /// `../` collapses to `_` then leading dots are stripped.
    func testParentDirSlash_pathTraversalNeutralized() {
        backupManager.organizationName = "../foo"
        XCTAssertFalse(backupManager.organizationName.contains("/"),
                       "Slash in `../foo` must be replaced")
        XCTAssertFalse(backupManager.organizationName.hasPrefix("."),
                       "Leading dot in `../foo` must be stripped")
    }

    /// `..\\` is the Windows-style traversal; backslash gets replaced.
    func testParentDirBackslash_pathTraversalNeutralized() {
        backupManager.organizationName = "..\\foo"
        XCTAssertFalse(backupManager.organizationName.contains("\\"),
                       "Backslash in `..\\foo` must be replaced")
        XCTAssertFalse(backupManager.organizationName.hasPrefix("."),
                       "Leading dot in `..\\foo` must be stripped")
    }

    /// Tab character (\t) embedded mid-string should be stripped.
    func testTabCharacter_stripped() {
        backupManager.organizationName = "Photos\tBackup"
        XCTAssertFalse(backupManager.organizationName.contains("\t"),
                       "Embedded tab character should be stripped")
        XCTAssertEqual(backupManager.organizationName, "PhotosBackup",
                       "Tab strip should leave surrounding characters intact")
    }

    /// Carriage return (\r) embedded mid-string should be stripped.
    func testCarriageReturn_stripped() {
        backupManager.organizationName = "Photos\rBackup"
        XCTAssertFalse(backupManager.organizationName.contains("\r"),
                       "Embedded carriage return should be stripped")
        XCTAssertEqual(backupManager.organizationName, "PhotosBackup")
    }

    /// Newline (\n) embedded mid-string should be stripped.
    func testNewline_stripped() {
        backupManager.organizationName = "Photos\nBackup"
        XCTAssertFalse(backupManager.organizationName.contains("\n"),
                       "Embedded newline should be stripped")
        XCTAssertEqual(backupManager.organizationName, "PhotosBackup")
    }

    /// Arbitrary C0 control characters (0x01-0x1F) should be stripped.
    /// Examples: \u{01} (SOH), \u{07} (BEL), \u{1B} (ESC — terminal escape sequences are
    /// a real concern in directory listings since they can rewrite preceding output).
    func testC0ControlCharacters_stripped() {
        backupManager.organizationName = "Photos\u{01}\u{07}\u{1B}Backup"
        let cleaned = backupManager.organizationName
        XCTAssertFalse(cleaned.unicodeScalars.contains(where: { $0.value < 0x20 }),
                       "All C0 control characters (0x00-0x1F) should be stripped, got: \(cleaned.unicodeScalars.map { String($0.value, radix: 16) })")
        XCTAssertEqual(cleaned, "PhotosBackup")
    }

    /// DEL (0x7F) is a control character that should also be stripped.
    func testDelCharacter_stripped() {
        backupManager.organizationName = "Photos\u{7F}Backup"
        XCTAssertFalse(backupManager.organizationName.unicodeScalars.contains(where: { $0.value == 0x7F }),
                       "DEL (0x7F) should be stripped")
        XCTAssertEqual(backupManager.organizationName, "PhotosBackup")
    }

    /// International characters MUST be preserved — this is a photography app, users have
    /// "São Paulo", "München", "日本", "📷" in their folder names. An allowlist-only
    /// sanitizer would break legitimate workflows.
    func testInternationalCharacters_preserved() {
        let cases: [String] = ["São Paulo", "München 2024", "日本", "Москва", "🇯🇵 Travel"]
        for input in cases {
            backupManager.organizationName = input
            XCTAssertEqual(backupManager.organizationName, input,
                           "International characters in '\(input)' must be preserved")
        }
    }

    /// Family/profession emojis use Zero-Width Joiners (U+200D, Cf category) to
    /// glue scalar codepoints into a single rendered glyph. The sanitizer MUST
    /// preserve Cf so 👨‍👩‍👧‍👦 doesn't decompose to 👨👩👧👦.
    func testZeroWidthJoinerEmoji_preserved() {
        // Family: man, woman, girl, boy — 4 emoji joined by 3 ZWJs (U+200D).
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        backupManager.organizationName = "Trip \(family) 2024"
        XCTAssertEqual(backupManager.organizationName, "Trip \(family) 2024",
                       "ZWJ-glued family emoji must survive sanitization")
        XCTAssertTrue(backupManager.organizationName.unicodeScalars.contains(where: { $0.value == 0x200D }),
                      "Zero-Width Joiner (U+200D) must be preserved")
    }

    /// Right-to-Left language folder names rely on bidirectional control
    /// characters (also Cf category) for correct display. They must be preserved.
    func testRightToLeftText_preserved() {
        // Arabic "مرحبا" (Marhaba — hello). No control chars at the codepoint
        // level; this is purely a string-preservation test for the RTL script.
        backupManager.organizationName = "مرحبا 2024"
        XCTAssertEqual(backupManager.organizationName, "مرحبا 2024",
                       "Arabic text must survive sanitization")

        // Hebrew "שלום" (Shalom — hello).
        backupManager.organizationName = "שלום 2024"
        XCTAssertEqual(backupManager.organizationName, "שלום 2024",
                       "Hebrew text must survive sanitization")
    }

    /// Idempotence sanity check across the new cases.
    func testSanitize_idempotent_controlChars() {
        let inputs = ["Photos\u{01}", "Photos\tBackup", "..\u{1B}foo", "Photos\u{7F}"]
        for input in inputs {
            backupManager.organizationName = input
            let first = backupManager.organizationName
            backupManager.organizationName = first
            XCTAssertEqual(backupManager.organizationName, first,
                           "sanitize must be idempotent on input '\(input)'")
        }
    }
}
