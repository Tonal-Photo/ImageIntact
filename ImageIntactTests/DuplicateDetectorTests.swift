//
//  DuplicateDetectorTests.swift
//  ImageIntactTests
//
//  Tests for duplicate file detection functionality
//

import XCTest
@testable import ImageIntact

@MainActor
class DuplicateDetectorTests: XCTestCase {
    
    var detector: DuplicateDetector!
    var tempDir: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        detector = DuplicateDetector()
        
        // Create temp directory for test files
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        if FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        detector = nil
        try await super.tearDown()
    }
    
    // MARK: - Test Duplicate Analysis
    
    func testEmptyManifestReturnsNoDuplicates() async {
        // Given
        let manifest: [FileManifestEntry] = []
        let destination = tempDir!
        
        // When
        let analysis = await detector.analyzeForDuplicates(
            manifest: manifest,
            destination: destination
        )
        
        // Then
        XCTAssertEqual(analysis.totalSourceFiles, 0)
        XCTAssertEqual(analysis.exactDuplicates.count, 0)
        XCTAssertEqual(analysis.renamedDuplicates.count, 0)
        XCTAssertEqual(analysis.uniqueFiles, 0)
        XCTAssertEqual(analysis.potentialSpaceSaved, 0)
    }
    
    func testManifestWithUniqueFilesReturnsNoDuplicates() async {
        // Given
        let manifest = [
            FileManifestEntry(
                relativePath: "photo1.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo1.jpg"),
                checksum: "abc123",
                size: 1024
            ),
            FileManifestEntry(
                relativePath: "photo2.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo2.jpg"),
                checksum: "def456",
                size: 2048
            )
        ]
        let destination = tempDir!
        
        // When
        let analysis = await detector.analyzeForDuplicates(
            manifest: manifest,
            destination: destination
        )
        
        // Then
        XCTAssertEqual(analysis.totalSourceFiles, 2)
        XCTAssertEqual(analysis.exactDuplicates.count, 0)
        XCTAssertEqual(analysis.renamedDuplicates.count, 0)
        XCTAssertEqual(analysis.uniqueFiles, 2)
        XCTAssertEqual(analysis.potentialSpaceSaved, 0)
    }
    
    // MARK: - Test Manifest Filtering
    
    func testFilterManifestRemovesExactDuplicates() {
        // Given
        let manifest = [
            FileManifestEntry(
                relativePath: "photo1.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo1.jpg"),
                checksum: "abc123",
                size: 1024
            ),
            FileManifestEntry(
                relativePath: "photo2.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo2.jpg"),
                checksum: "def456",
                size: 2048
            )
        ]
        
        let analysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 2,
            exactDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: manifest[0],
                    destinationPath: "/dest/photo1.jpg",
                    checksum: "abc123",
                    isDifferentName: false,
                    existingOrganization: nil
                )
            ],
            renamedDuplicates: [],
            uniqueFiles: 1,
            potentialSpaceSaved: 1024,
            destinationDriveUUID: nil
        )
        
        // When
        let filtered = detector.filterManifest(
            manifest,
            excludingDuplicates: analysis,
            skipExact: true,
            skipRenamed: false
        )
        
        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].checksum, "def456")
    }
    
    func testFilterManifestRemovesRenamedDuplicates() {
        // Given
        let manifest = [
            FileManifestEntry(
                relativePath: "photo1.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo1.jpg"),
                checksum: "abc123",
                size: 1024
            ),
            FileManifestEntry(
                relativePath: "photo2.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo2.jpg"),
                checksum: "def456",
                size: 2048
            )
        ]
        
        let analysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 2,
            exactDuplicates: [],
            renamedDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: manifest[1],
                    destinationPath: "/dest/renamed.jpg",
                    checksum: "def456",
                    isDifferentName: true,
                    existingOrganization: nil
                )
            ],
            uniqueFiles: 1,
            potentialSpaceSaved: 2048,
            destinationDriveUUID: nil
        )
        
        // When
        let filtered = detector.filterManifest(
            manifest,
            excludingDuplicates: analysis,
            skipExact: false,
            skipRenamed: true
        )
        
        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].checksum, "abc123")
    }
    
    func testFilterManifestRemovesBothDuplicateTypes() {
        // Given
        let manifest = [
            FileManifestEntry(
                relativePath: "photo1.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo1.jpg"),
                checksum: "abc123",
                size: 1024
            ),
            FileManifestEntry(
                relativePath: "photo2.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo2.jpg"),
                checksum: "def456",
                size: 2048
            ),
            FileManifestEntry(
                relativePath: "photo3.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo3.jpg"),
                checksum: "ghi789",
                size: 3072
            )
        ]
        
        let analysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 3,
            exactDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: manifest[0],
                    destinationPath: "/dest/photo1.jpg",
                    checksum: "abc123",
                    isDifferentName: false,
                    existingOrganization: nil
                )
            ],
            renamedDuplicates: [
                DuplicateDetector.DuplicateFile(
                    sourceFile: manifest[1],
                    destinationPath: "/dest/renamed.jpg",
                    checksum: "def456",
                    isDifferentName: true,
                    existingOrganization: nil
                )
            ],
            uniqueFiles: 1,
            potentialSpaceSaved: 3072,
            destinationDriveUUID: nil
        )
        
        // When
        let filtered = detector.filterManifest(
            manifest,
            excludingDuplicates: analysis,
            skipExact: true,
            skipRenamed: true
        )
        
        // Then
        XCTAssertEqual(filtered.count, 1)
        XCTAssertEqual(filtered[0].checksum, "ghi789")
    }
    
    // MARK: - Test Analysis Summary
    
    func testFormatAnalysisSummaryGeneratesCorrectString() {
        // Given
        let analysis = DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: 100,
            exactDuplicates: Array(repeating: DuplicateDetector.DuplicateFile(
                sourceFile: FileManifestEntry(
                    relativePath: "test.jpg",
                    sourceURL: URL(fileURLWithPath: "/test.jpg"),
                    checksum: "test",
                    size: 1024 * 1024
                ),
                destinationPath: "/dest/test.jpg",
                checksum: "test",
                isDifferentName: false,
                existingOrganization: nil
            ), count: 25),
            renamedDuplicates: Array(repeating: DuplicateDetector.DuplicateFile(
                sourceFile: FileManifestEntry(
                    relativePath: "test2.jpg",
                    sourceURL: URL(fileURLWithPath: "/test2.jpg"),
                    checksum: "test2",
                    size: 1024 * 1024
                ),
                destinationPath: "/dest/renamed.jpg",
                checksum: "test2",
                isDifferentName: true,
                existingOrganization: nil
            ), count: 15),
            uniqueFiles: 60,
            potentialSpaceSaved: 40 * 1024 * 1024,
            destinationDriveUUID: nil
        )
        
        // When
        let summary = detector.formatAnalysisSummary(analysis)
        
        // Then
        XCTAssertTrue(summary.contains("Total files: 100"))
        XCTAssertTrue(summary.contains("Exact duplicates: 25"))
        XCTAssertTrue(summary.contains("Renamed duplicates: 15"))
        XCTAssertTrue(summary.contains("Unique files: 60"))
        XCTAssertTrue(summary.contains("40 MB"))
        XCTAssertTrue(summary.contains("40.0%"))
    }
    
    // MARK: - Test Preflight Check
    
    func testPreflightDuplicateCheckProcessesMultipleDestinations() async {
        // Given
        let manifest = [
            FileManifestEntry(
                relativePath: "photo1.jpg",
                sourceURL: URL(fileURLWithPath: "/source/photo1.jpg"),
                checksum: "abc123",
                size: 1024
            )
        ]
        
        let dest1 = tempDir.appendingPathComponent("dest1")
        let dest2 = tempDir.appendingPathComponent("dest2")
        try! FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try! FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        
        // When
        let results = await detector.preflightDuplicateCheck(
            manifest: manifest,
            destinations: [dest1, dest2],
            organizationName: "TestOrg"
        )
        
        // Then
        XCTAssertEqual(results.count, 2)
        XCTAssertNotNil(results[dest1])
        XCTAssertNotNil(results[dest2])
        XCTAssertEqual(results[dest1]?.totalSourceFiles, 1)
        XCTAssertEqual(results[dest2]?.totalSourceFiles, 1)
    }
}