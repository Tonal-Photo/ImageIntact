//
//  SmartFolderNameTests.swift
//  ImageIntactTests
//
//  Direct tests for SmartFolderName, extracted from BackupManager
//  (#103 / AMUX-18). The original `extractSmartFolderName` was private;
//  these are equivalent assertions to the indirect coverage in
//  BackupOrganizationTests, now exercised on the pure helper directly.
//

import XCTest

@testable import ImageIntact

final class SmartFolderNameTests: XCTestCase {
    func testReturnsLastComponentForSimplePath() {
        let url = URL(fileURLWithPath: "/Users/me/Photos/Vacation")
        XCTAssertEqual(SmartFolderName.from(url: url), "Vacation")
    }

    func testReturnsVolumeNameForVolumePath() {
        let url = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        XCTAssertEqual(SmartFolderName.from(url: url), "Card01")
    }

    func testSkipsGenericFolderNames() {
        // The deepest non-generic component should be picked even if the
        // last component is generic.
        let url = URL(fileURLWithPath: "/Users/me/Vacation/Photos")
        XCTAssertEqual(SmartFolderName.from(url: url), "Vacation")
    }

    func testSkipsAllGenericNames() {
        // Generic at every level: photos, dcim, images, files, pictures, documents.
        // No single component is meaningful — function falls back to the last
        // component (which is still generic but at least non-empty).
        let url = URL(fileURLWithPath: "/Pictures/Photos/Images")
        // First non-generic walking backwards is the last component itself, but
        // every component is generic, so the fallback (lastPathComponent = "Images")
        // wins. Either "Images" or one of the other generics is acceptable —
        // we mainly want to assert no crash and a non-empty result.
        let result = SmartFolderName.from(url: url)
        XCTAssertFalse(result.isEmpty)
    }

    func testReplacesSpacesWithUnderscores() {
        let url = URL(fileURLWithPath: "/Users/me/My Photo Shoot")
        XCTAssertEqual(SmartFolderName.from(url: url), "My_Photo_Shoot")
    }

    func testCollapsesMultipleUnderscores() {
        let url = URL(fileURLWithPath: "/Users/me/My  Double  Spaces")
        // Two spaces → two underscores → collapsed to one.
        XCTAssertEqual(SmartFolderName.from(url: url), "My_Double_Spaces")
    }

    func testWalksBackwardsForMeaningfulName() {
        // ~/Pictures/2025/Q3/Clients/Johnson — last non-generic walking
        // backwards from the end is "Johnson".
        let url = URL(fileURLWithPath: "/Users/me/Pictures/2025/Q3/Clients/Johnson")
        XCTAssertEqual(SmartFolderName.from(url: url), "Johnson")
    }

    func testSkipsHiddenComponents() {
        // .hidden component should be skipped; previous component picked.
        let url = URL(fileURLWithPath: "/Users/me/Backups/.tmpdir")
        XCTAssertEqual(SmartFolderName.from(url: url), "Backups")
    }

    // MARK: - sanitize(_:) (AMUX-20 / GH #103 — TDD red phase)
    // NOTE: SmartFolderName.sanitize(_:) does not exist yet. These tests will
    // fail to compile until the static method is added to SmartFolderName.swift.

    /// Empty string → empty string.
    func testSanitize_emptyString() {
        XCTAssertEqual(SmartFolderName.sanitize(""), "")
    }

    /// Plain ASCII name without special characters → unchanged.
    func testSanitize_plainASCII_unchanged() {
        XCTAssertEqual(SmartFolderName.sanitize("MyFolder"), "MyFolder")
    }

    /// Forward slash → underscore.
    func testSanitize_forwardSlash_replacedWithUnderscore() {
        XCTAssertEqual(SmartFolderName.sanitize("foo/bar"), "foo_bar")
    }

    /// Backslash → underscore.
    func testSanitize_backslash_replacedWithUnderscore() {
        XCTAssertEqual(SmartFolderName.sanitize("foo\\bar"), "foo_bar")
    }

    /// Colon → underscore (macOS Finder path separator).
    func testSanitize_colon_replacedWithUnderscore() {
        XCTAssertEqual(SmartFolderName.sanitize("foo:bar"), "foo_bar")
    }

    /// Null byte → removed entirely (not replaced).
    func testSanitize_nullByte_removed() {
        XCTAssertEqual(SmartFolderName.sanitize("foo\0bar"), "foobar")
    }

    /// Leading and trailing whitespace is trimmed.
    func testSanitize_whitespace_trimmed() {
        XCTAssertEqual(SmartFolderName.sanitize("  foo  "), "foo")
    }

    /// Leading dots are trimmed.
    func testSanitize_leadingDots_trimmed() {
        XCTAssertEqual(SmartFolderName.sanitize("...foo..."), "foo")
    }

    /// Combined dots and whitespace (e.g. ".  Foo  .") → "Foo".
    func testSanitize_dotsAndWhitespaceCombined_trimmed() {
        XCTAssertEqual(SmartFolderName.sanitize(".  Foo  ."), "Foo")
    }

    /// A 255-byte ASCII string is returned unchanged (on the boundary — no truncation).
    func testSanitize_exactly255ByteString_unchanged() {
        let input = String(repeating: "a", count: 255)
        XCTAssertEqual(input.utf8.count, 255, "Precondition: input must be exactly 255 UTF-8 bytes")
        let result = SmartFolderName.sanitize(input)
        XCTAssertEqual(result, input, "A 255-byte string must not be truncated")
        XCTAssertEqual(result.utf8.count, 255)
    }

    /// A 256-byte ASCII string is truncated to ≤ 255 bytes.
    func testSanitize_256ByteString_truncatedTo255() {
        let input = String(repeating: "a", count: 256)
        XCTAssertEqual(input.utf8.count, 256, "Precondition: input must be exactly 256 UTF-8 bytes")
        let result = SmartFolderName.sanitize(input)
        XCTAssertLessThanOrEqual(result.utf8.count, 255,
                                 "A 256-byte string must be truncated to ≤ 255 UTF-8 bytes")
    }

    /// When the truncation boundary falls inside a multi-byte UTF-8 character,
    /// the partial character is dropped entirely (no replacement characters).
    /// Input: 253 ASCII "a" chars (253 bytes) + "🍕" (4 bytes) = 257 bytes total.
    /// Expected: the pizza emoji is dropped; result is 253 "a"s.
    func testSanitize_truncation_doesNotSplitMultibyteCharacter() {
        let input = String(repeating: "a", count: 253) + "🍕"
        XCTAssertEqual(input.utf8.count, 257,
                       "Precondition: input must be 257 UTF-8 bytes (253 ASCII + 4-byte emoji)")
        let result = SmartFolderName.sanitize(input)
        XCTAssertLessThanOrEqual(result.utf8.count, 255,
                                 "Result must be ≤ 255 UTF-8 bytes")
        XCTAssertFalse(result.contains("\u{FFFD}"),
                       "Result must not contain the Unicode replacement character (partial decode)")
        // The emoji is 4 bytes — including it would exceed 255 — so it must be absent.
        XCTAssertFalse(result.contains("🍕"),
                       "Partial emoji at the truncation boundary must be dropped entirely")
        XCTAssertEqual(result, String(repeating: "a", count: 253),
                       "Result should be exactly the 253 ASCII characters before the emoji")
    }

    /// sanitize is idempotent: applying it twice yields the same result as once.
    func testSanitize_idempotent_slashInput() {
        let input = "foo/bar"
        XCTAssertEqual(SmartFolderName.sanitize(SmartFolderName.sanitize(input)),
                       SmartFolderName.sanitize(input),
                       "sanitize must be idempotent for slash-containing input")
    }

    func testSanitize_idempotent_dotsAndWhitespace() {
        let input = "  .test.  "
        XCTAssertEqual(SmartFolderName.sanitize(SmartFolderName.sanitize(input)),
                       SmartFolderName.sanitize(input),
                       "sanitize must be idempotent for dot/whitespace-padded input")
    }

    func testSanitize_idempotent_longString() {
        let input = String(repeating: "a", count: 300)
        XCTAssertEqual(SmartFolderName.sanitize(SmartFolderName.sanitize(input)),
                       SmartFolderName.sanitize(input),
                       "sanitize must be idempotent for a string that requires truncation")
    }
}
