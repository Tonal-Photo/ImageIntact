//
//  BatchFileProcessorTests.swift
//  ImageIntactTests
//
//  Regression tests for BatchFileProcessor.batchCalculateChecksums per-file
//  error tolerance (PR #107, AMUX-17). Before the size-fallback removal, an
//  unreadable file in a batch returned a fake "size:" sentinel and the batch
//  continued. After the removal, that masking is gone — we instead skip the
//  failing file and continue, so callers like ManifestBuilder still get
//  checksums for every file that *can* be hashed.
//

import XCTest

@testable import ImageIntact

final class BatchFileProcessorTests: XCTestCase {
    var testDirectory: URL!
    var processor: BatchFileProcessor!

    override func setUp() async throws {
        testDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("BatchFileProcessorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: testDirectory, withIntermediateDirectories: true
        )
        processor = BatchFileProcessor()
    }

    override func tearDown() async throws {
        // Restore any locked-down permissions so the temp dir can be removed.
        if let entries = try? FileManager.default.contentsOfDirectory(
            atPath: testDirectory.path
        ) {
            for entry in entries {
                let path = testDirectory.appendingPathComponent(entry).path
                try? FileManager.default.setAttributes(
                    [.posixPermissions: 0o644], ofItemAtPath: path
                )
            }
        }
        try? FileManager.default.removeItem(at: testDirectory)
    }

    /// All files in the batch are readable: every URL gets a real checksum.
    func testAllReadableFiles() async throws {
        let urls = try makeFiles(["a.txt", "b.txt", "c.txt"], readable: true)
        let result = try await processor.batchCalculateChecksums(urls, shouldCancel: { false })
        XCTAssertEqual(result.count, urls.count, "Every readable file should produce a checksum")
        for url in urls {
            XCTAssertNotNil(result[url], "Missing checksum for \(url.lastPathComponent)")
            XCTAssertEqual(result[url]?.count, 64, "Should be a 64-char hex SHA-256")
            XCTAssertFalse(
                result[url]?.hasPrefix("size:") ?? true,
                "Should not be the legacy size: sentinel"
            )
        }
    }

    /// Mixed readable + unreadable files: readable ones produce checksums,
    /// unreadable ones are omitted from the result dict (caller's missing-key
    /// path takes over). Crucially, the batch does NOT throw.
    func testUnreadableFileIsSkippedNotThrown() async throws {
        let readable = try makeFiles(["good1.txt", "good2.txt"], readable: true)
        let unreadable = try makeFiles(["bad.txt"], readable: false)

        // Skip when running with elevated privileges (root bypasses POSIX permissions).
        guard !FileManager.default.isReadableFile(atPath: unreadable[0].path) else {
            throw XCTSkip("Running as root or equivalent; 0o000 does not block reads")
        }

        let result = try await processor.batchCalculateChecksums(
            readable + unreadable, shouldCancel: { false }
        )
        XCTAssertEqual(
            result.count, readable.count,
            "Only readable files should appear in the result dict"
        )
        for url in readable {
            XCTAssertNotNil(result[url], "Readable file \(url.lastPathComponent) should have a checksum")
        }
        for url in unreadable {
            XCTAssertNil(
                result[url],
                "Unreadable file \(url.lastPathComponent) should be omitted (not given a fake hash)"
            )
        }
    }

    // MARK: - Helpers

    private func makeFiles(_ names: [String], readable: Bool) throws -> [URL] {
        var urls: [URL] = []
        for name in names {
            let url = testDirectory.appendingPathComponent(name)
            try Data("contents-of-\(name)".utf8).write(to: url)
            if !readable {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o000], ofItemAtPath: url.path
                )
            }
            urls.append(url)
        }
        return urls
    }
}
