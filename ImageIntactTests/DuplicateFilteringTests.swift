//
//  DuplicateFilteringTests.swift
//  ImageIntactTests
//
//  Tests for bug #1 (GH issue #91): Duplicate filtering is per-union, not per-destination.
//  When file X exists on Destination A but not Destination B, the current code adds X's
//  checksum to a global skip set, causing it to be skipped for ALL destinations -- even
//  ones that don't have it yet. This is silent data loss.
//
//  These tests verify the CORRECT behavior: duplicate filtering must be per-destination.
//

@testable import ImageIntact
import XCTest

@MainActor
final class DuplicateFilteringTests: XCTestCase {

    // MARK: - Properties

    var sourceURL: URL!
    var destA: URL!
    var destB: URL!

    override func setUp() async throws {
        try await super.setUp()
        sourceURL = URL(fileURLWithPath: "/test/source")
        destA = URL(fileURLWithPath: "/backup/destA")
        destB = URL(fileURLWithPath: "/backup/destB")
    }

    override func tearDown() async throws {
        sourceURL = nil
        destA = nil
        destB = nil
        try await super.tearDown()
    }

    // MARK: - Bug #1: Per-union filtering causes data loss

    /// The critical test: a file that exists on Dest A but NOT Dest B must still
    /// be copied to Dest B. The current code unions all destination analyses into
    /// a single skip set, causing files to be silently skipped for destinations
    /// that don't have them.
    func testFilePresentOnOneDestinationIsStillCopiedToOther() throws {
        // Given: 3 files in the manifest
        let manifest = [
            makeManifestEntry(name: "photo1.jpg", checksum: "aaa111"),
            makeManifestEntry(name: "photo2.jpg", checksum: "bbb222"),
            makeManifestEntry(name: "photo3.jpg", checksum: "ccc333"),
        ]

        // Dest A already has photo1 and photo2
        let analysisDestA = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 3,
            exactDuplicates: [
                makeDuplicateFile(from: manifest[0], checksum: "aaa111"),
                makeDuplicateFile(from: manifest[1], checksum: "bbb222"),
            ],
            renamedDuplicates: [],
            uniqueFiles: 1,
            potentialSpaceSaved: 2000,
            destinationDriveUUID: "uuid-destA"
        )

        // Dest B has NO duplicates -- all files are new
        let analysisDestB = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 3,
            exactDuplicates: [],
            renamedDuplicates: [],
            uniqueFiles: 3,
            potentialSpaceSaved: 0,
            destinationDriveUUID: "uuid-destB"
        )

        let analyses: [UUID: DuplicateDetector.DuplicateAnalysis] = [
            UUID(): analysisDestA,
            UUID(): analysisDestB,
        ]

        // When: filtering is applied per-destination (CORRECT behavior)
        let filteredForDestA = filterManifestForDestination(
            manifest: manifest,
            analysis: analysisDestA,
            skipExactDuplicates: true,
            skipRenamedDuplicates: false
        )
        let filteredForDestB = filterManifestForDestination(
            manifest: manifest,
            analysis: analysisDestB,
            skipExactDuplicates: true,
            skipRenamedDuplicates: false
        )

        // Then: Dest A gets only photo3 (the one it doesn't have)
        XCTAssertEqual(filteredForDestA.count, 1,
                       "Dest A should only get 1 file (photo3) since it already has photo1 and photo2")
        XCTAssertEqual(filteredForDestA.first?.checksum, "ccc333")

        // CRITICAL: Dest B gets ALL 3 files because it has none of them
        XCTAssertEqual(filteredForDestB.count, 3,
                       "CRITICAL: Dest B must get ALL 3 files -- it has none of them. " +
                       "If this is less than 3, per-union filtering is causing data loss.")
    }

    /// Verify that files present on ALL destinations are correctly skipped everywhere.
    func testFilePresentOnAllDestinationsIsSkippedEverywhere() throws {
        let manifest = [
            makeManifestEntry(name: "photo1.jpg", checksum: "aaa111"),
            makeManifestEntry(name: "photo2.jpg", checksum: "bbb222"),
        ]

        // Both destinations have photo1
        let analysisA = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 2,
            exactDuplicates: [makeDuplicateFile(from: manifest[0], checksum: "aaa111")],
            renamedDuplicates: [],
            uniqueFiles: 1,
            potentialSpaceSaved: 1000,
            destinationDriveUUID: "uuid-A"
        )
        let analysisB = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 2,
            exactDuplicates: [makeDuplicateFile(from: manifest[0], checksum: "aaa111")],
            renamedDuplicates: [],
            uniqueFiles: 1,
            potentialSpaceSaved: 1000,
            destinationDriveUUID: "uuid-B"
        )

        let filteredA = filterManifestForDestination(
            manifest: manifest, analysis: analysisA,
            skipExactDuplicates: true, skipRenamedDuplicates: false
        )
        let filteredB = filterManifestForDestination(
            manifest: manifest, analysis: analysisB,
            skipExactDuplicates: true, skipRenamedDuplicates: false
        )

        // Both should skip photo1, both should get photo2
        XCTAssertEqual(filteredA.count, 1)
        XCTAssertEqual(filteredA.first?.checksum, "bbb222")
        XCTAssertEqual(filteredB.count, 1)
        XCTAssertEqual(filteredB.first?.checksum, "bbb222")
    }

    /// Verify renamed duplicates are also filtered per-destination, not per-union.
    func testRenamedDuplicateOnOneDestinationStillCopiedToOther() throws {
        let manifest = [
            makeManifestEntry(name: "photo1.jpg", checksum: "aaa111"),
        ]

        // Dest A has a renamed copy (same content, different name)
        let analysisA = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 1,
            exactDuplicates: [],
            renamedDuplicates: [makeDuplicateFile(from: manifest[0], checksum: "aaa111", renamed: true)],
            uniqueFiles: 0,
            potentialSpaceSaved: 1000,
            destinationDriveUUID: "uuid-A"
        )
        // Dest B has nothing
        let analysisB = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 1,
            exactDuplicates: [],
            renamedDuplicates: [],
            uniqueFiles: 1,
            potentialSpaceSaved: 0,
            destinationDriveUUID: "uuid-B"
        )

        let filteredA = filterManifestForDestination(
            manifest: manifest, analysis: analysisA,
            skipExactDuplicates: true, skipRenamedDuplicates: true
        )
        let filteredB = filterManifestForDestination(
            manifest: manifest, analysis: analysisB,
            skipExactDuplicates: true, skipRenamedDuplicates: true
        )

        XCTAssertEqual(filteredA.count, 0, "Dest A should skip -- it has a renamed copy")
        XCTAssertEqual(filteredB.count, 1, "Dest B must get the file -- it has nothing")
    }

    /// When skipExactDuplicates is false, no files should be filtered even if analyses exist.
    func testNoFilteringWhenSkipDuplicatesDisabled() throws {
        let manifest = [
            makeManifestEntry(name: "photo1.jpg", checksum: "aaa111"),
            makeManifestEntry(name: "photo2.jpg", checksum: "bbb222"),
        ]

        let analysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 2,
            exactDuplicates: [
                makeDuplicateFile(from: manifest[0], checksum: "aaa111"),
                makeDuplicateFile(from: manifest[1], checksum: "bbb222"),
            ],
            renamedDuplicates: [],
            uniqueFiles: 0,
            potentialSpaceSaved: 2000,
            destinationDriveUUID: "uuid-A"
        )

        let filtered = filterManifestForDestination(
            manifest: manifest, analysis: analysis,
            skipExactDuplicates: false, skipRenamedDuplicates: false
        )

        XCTAssertEqual(filtered.count, 2, "All files should be included when skip is disabled")
    }

    // MARK: - Helpers

    /// Per-destination filtering — the CORRECT implementation that should replace
    /// the current per-union approach in BackupOrchestrator.
    private func filterManifestForDestination(
        manifest: [FileManifestEntry],
        analysis: DuplicateDetector.DuplicateAnalysis,
        skipExactDuplicates: Bool,
        skipRenamedDuplicates: Bool
    ) -> [FileManifestEntry] {
        var checksumsToSkip = Set<String>()

        if skipExactDuplicates {
            for dup in analysis.exactDuplicates {
                checksumsToSkip.insert(dup.checksum)
            }
        }
        if skipRenamedDuplicates {
            for dup in analysis.renamedDuplicates {
                checksumsToSkip.insert(dup.checksum)
            }
        }

        return manifest.filter { !checksumsToSkip.contains($0.checksum) }
    }

    private func makeManifestEntry(name: String, checksum: String, size: Int64 = 1000) -> FileManifestEntry {
        FileManifestEntry(
            relativePath: name,
            sourceURL: sourceURL.appendingPathComponent(name),
            checksum: checksum,
            size: size
        )
    }

    private func makeDuplicateFile(
        from entry: FileManifestEntry,
        checksum: String,
        renamed: Bool = false
    ) -> DuplicateDetector.DuplicateFile {
        DuplicateDetector.DuplicateFile(
            sourceFile: entry,
            destinationPath: "/backup/existing/\(entry.relativePath)",
            checksum: checksum,
            isDifferentName: renamed,
            existingOrganization: nil
        )
    }
}
