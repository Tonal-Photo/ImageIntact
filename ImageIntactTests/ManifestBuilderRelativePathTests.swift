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

    // MARK: - stripCanonicalPrefix

    /// Sanity test: a urlPath under the prefix gets correctly stripped.
    func testStripPrefix_validPrefix_strips() {
        let stripped = ManifestBuilder.stripCanonicalPrefix(
            "/Volumes/SourceDrive/",
            from: "/Volumes/SourceDrive/photos/raw1.nef"
        )
        XCTAssertEqual(stripped, "photos/raw1.nef")
    }

    /// Repeated source-name segment inside the path: the prefix-only strip
    /// preserves repeats that `replacingOccurrences` would mangle.
    func testStripPrefix_repeatedNameInPath_preservesRepeat() {
        let stripped = ManifestBuilder.stripCanonicalPrefix(
            "/private/var/folders/abc/T/SourceRoot/",
            from: "/private/var/folders/abc/T/SourceRoot/SourceRoot/file.jpg"
        )
        XCTAssertEqual(stripped, "SourceRoot/file.jpg",
                       "Repeated source-name as a child directory must NOT be stripped twice")
    }

    /// Root-source case: prefix is `/` (not `//`), and a normal absolute
    /// child path strips its leading `/` correctly.
    /// Regression test for the root-directory bug flagged in round 2 review.
    func testStripPrefix_rootSourcePrefix_stripsOnlyLeadingSlash() {
        XCTAssertEqual(
            ManifestBuilder.stripCanonicalPrefix("/", from: "/Applications/Foo.app"),
            "Applications/Foo.app",
            "Root prefix `/` must strip only the leading slash, not match `//`"
        )
    }

    /// URL outside the source tree: stripCanonicalPrefix returns nil so the
    /// caller can skip rather than store an absolute path as a "relative"
    /// manifest entry. Direct unit test for the safety branch in build().
    func testStripPrefix_pathOutsideSourceTree_returnsNil() {
        XCTAssertNil(
            ManifestBuilder.stripCanonicalPrefix(
                "/Volumes/SourceDrive/",
                from: "/Volumes/OtherDrive/photos/raw1.nef"
            ),
            "Paths that don't start with the source prefix must return nil so build() can skip them"
        )
    }

    /// Edge case: empty prefix would match every string. The contract is
    /// "must end with `/` or be just `/`" — exercise both legitimate forms
    /// to lock in the expected behavior.
    func testStripPrefix_exactMatch_returnsEmptyString() {
        // A url that matches the prefix exactly (no child path) yields an
        // empty relativePath. This shouldn't happen in normal enumeration
        // (the source itself isn't yielded as a child) but the function's
        // behavior should be predictable.
        XCTAssertEqual(
            ManifestBuilder.stripCanonicalPrefix("/foo/bar/", from: "/foo/bar/"),
            ""
        )
    }

    // MARK: - build end-to-end: symlinked subdirectory pointing outside source

    /// Integration test for the safety branch in `build()`: when a symbolic
    /// link inside the source points at content outside the source tree,
    /// the manifest must NOT include the linked target file. With the
    /// `FileManager` enumerator's default options (no `.followsSymlinks`),
    /// the symlink is itself yielded as a symbolic-link entry and skipped
    /// via the existing `isSymbolicLink` guard — verifying this behavior
    /// end-to-end protects against future regressions if someone adds
    /// `.followsSymlinks` to the enumerator options.
    func testBuild_symlinkInsideSource_pointingOutsideTree_isSkipped() async throws {
        let source = tempDir.appendingPathComponent("source")
        let external = tempDir.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)

        // Real file inside the source — should be in the manifest.
        try Data([0xFF]).write(to: source.appendingPathComponent("inside.jpg"))
        // Real file outside the source — should NOT appear in the manifest.
        try Data([0xFF]).write(to: external.appendingPathComponent("outside.jpg"))

        // Symlink inside source pointing to the external dir.
        let link = source.appendingPathComponent("escape_link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)

        let manifest = await ManifestBuilder().build(
            source: source,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: true
        )

        XCTAssertNotNil(manifest)
        let paths = manifest?.map { $0.relativePath } ?? []
        XCTAssertEqual(paths, ["inside.jpg"],
                       "Manifest must contain only the in-tree file; the symlinked external content must be skipped")
        XCTAssertFalse(paths.contains("outside.jpg"),
                       "outside.jpg must not appear in the manifest under any normalization of the link target")
        XCTAssertFalse(paths.contains(where: { $0.contains("external") }),
                       "No manifest entry may reference the external/ tree")
    }
}
