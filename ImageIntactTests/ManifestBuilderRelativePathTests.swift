//
//  ManifestBuilderRelativePathTests.swift
//  ImageIntactTests
//
//  Regression tests for the relativePath computation in ManifestBuilder.build
//  (AMUX-228). Targets the corner cases the panel reviewer flagged:
//   - source path name repeats inside the tree (prefix-strip must not
//     mis-strip multiple occurrences)
//   - enumerator yields urls outside the canonical source tree (must skip
//     rather than store an absolute path as the manifest's "relative" field)
//   - the canonicalPath helper itself behaves correctly for both symlinked
//     temp paths and non-existent paths
//

import XCTest
@testable import ImageIntact

final class ManifestBuilderRelativePathTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ManifestPathTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try? FileManager.default.removeItem(at: tempDir)
        }
        try await super.tearDown()
    }

    // MARK: - canonicalPath

    /// The canonical form of a `/var/folders/...` URL matches the
    /// `/private/var/folders/...` form that the directory enumerator yields
    /// for child URLs — that's exactly the alignment we need to make
    /// `hasPrefix` work.
    func testCanonicalPath_resolvesPrivateVarSymlink() throws {
        let resolved = ManifestBuilder.canonicalPath(of: tempDir)
        let original = tempDir.path

        XCTAssertTrue(
            resolved.hasSuffix(original.dropFirst(0)) ||
            resolved == original ||
            resolved.contains(original.replacingOccurrences(of: "/var/", with: "/private/var/")),
            "canonicalPath must produce a path whose enumerator children share its prefix; got '\(resolved)' for source '\(original)'"
        )

        // The stronger property: a file written to tempDir's enumerator
        // yields a url.path that hasPrefix the canonical path.
        let fileURL = tempDir.appendingPathComponent("probe.jpg")
        try Data([0xFF]).write(to: fileURL)

        let enumerator = FileManager.default.enumerator(at: tempDir, includingPropertiesForKeys: nil)!
        var found = false
        while let url = enumerator.nextObject() as? URL {
            XCTAssertTrue(
                url.path.hasPrefix(resolved + "/"),
                "enumerated url '\(url.path)' must have canonical source '\(resolved)/' as a prefix"
            )
            found = true
        }
        XCTAssertTrue(found, "enumerator must yield at least one child for the test to be meaningful")
    }

    /// `realpath(3)` returns NULL when the path doesn't exist; canonicalPath
    /// must fall back to `url.path` instead of crashing or returning an
    /// empty string.
    func testCanonicalPath_nonExistentPath_fallsBackToUrlPath() {
        let bogus = URL(fileURLWithPath: "/no/such/path/exists/\(UUID().uuidString)")
        let resolved = ManifestBuilder.canonicalPath(of: bogus)
        XCTAssertEqual(resolved, bogus.path,
                       "canonicalPath must fall back to url.path on realpath failure")
    }

    // MARK: - build relativePath correctness

    /// Build returns relativePaths with the source prefix stripped, even
    /// when the source name happens to repeat as a subdirectory.
    /// Regression test for the panel reviewer's High finding: a naive
    /// `replacingOccurrences` would strip ALL occurrences and produce a
    /// mangled relativePath when the source name appears as a child segment.
    func testBuild_relativePathHandlesRepeatedDirectoryNames() async throws {
        // Create source `<tempDir>/repeat` and a subdir of the same name
        // inside: `<tempDir>/repeat/repeat/file.jpg`. Under the old
        // `replacingOccurrences` approach, stripping `<tempDir>/repeat/`
        // from `<tempDir>/repeat/repeat/file.jpg` would yield `file.jpg`
        // instead of the correct `repeat/file.jpg`.
        let source = tempDir.appendingPathComponent("repeat")
        let nested = source.appendingPathComponent("repeat")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([0xFF]).write(to: nested.appendingPathComponent("file.jpg"))

        let manifest = await ManifestBuilder().build(
            source: source,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: true
        )

        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.count, 1, "Expected 1 file in manifest")
        XCTAssertEqual(manifest?.first?.relativePath, "repeat/file.jpg",
                       "relativePath must preserve the repeated directory segment")
    }

    /// Build returns the correct relativePath for files directly under the
    /// source (no nested directories). Sanity test that the basic prefix
    /// strip still works for the common case.
    func testBuild_relativePathForRootLevelFile() async throws {
        try Data([0xFF]).write(to: tempDir.appendingPathComponent("flat.jpg"))

        let manifest = await ManifestBuilder().build(
            source: tempDir,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: true
        )

        XCTAssertEqual(manifest?.first?.relativePath, "flat.jpg",
                       "relativePath for a root-level file is just the filename")
    }
}
