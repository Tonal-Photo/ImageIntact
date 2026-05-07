//
//  BatchFileProcessorTests.swift
//  ImageIntactTests
//
//  Regression tests for BatchFileProcessor.batchCalculateChecksums:
//  - Per-file error tolerance (#107, AMUX-17): one bad file no longer
//    aborts the whole batch.
//  - Result-typed contract (#108 item 7, PR #113): each processed file gets
//    a `.success(hash)` or `.failure(error)` entry, so callers can produce
//    specific diagnostics instead of inferring failure from a missing key.
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

    /// All files in the batch are readable: every URL gets a `.success(hash)` entry.
    func testAllReadableFiles() async throws {
        let urls = try makeFiles(["a.txt", "b.txt", "c.txt"], readable: true)
        let result = try await processor.batchCalculateChecksums(urls, shouldCancel: { false })
        XCTAssertEqual(result.count, urls.count, "Every readable file should produce a result")
        for url in urls {
            guard let entry = result[url] else {
                XCTFail("Missing result for \(url.lastPathComponent)")
                continue
            }
            switch entry {
            case .success(let hash):
                XCTAssertEqual(hash.count, 64, "Should be a 64-char hex SHA-256")
                XCTAssertFalse(hash.hasPrefix("size:"), "Should not be the legacy size: sentinel")
            case .failure(let error):
                XCTFail("\(url.lastPathComponent) should have succeeded, got: \(error)")
            }
        }
    }

    /// Mixed readable + unreadable files: readable ones produce `.success`,
    /// unreadable ones produce `.failure(ChecksumServiceError.unreadable)`.
    /// The batch does NOT throw — callers iterate Result entries to handle
    /// per-file outcomes uniformly.
    func testUnreadableFileSurfacesAsFailureEntry() async throws {
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
            result.count, readable.count + unreadable.count,
            "Every processed file should have a Result entry (success or failure)"
        )
        for url in readable {
            switch result[url] {
            case .success(let hash):
                XCTAssertEqual(hash.count, 64, "Readable file should produce a real SHA-256")
            case .failure(let error):
                XCTFail("Readable file \(url.lastPathComponent) should have succeeded, got: \(error)")
            case nil:
                XCTFail("Readable file \(url.lastPathComponent) should have a Result entry")
            }
        }
        for url in unreadable {
            switch result[url] {
            case .success:
                XCTFail("Unreadable file \(url.lastPathComponent) should not have produced a hash")
            case .failure(let error):
                guard let serviceError = error as? ChecksumServiceError,
                      case .unreadable(let failedURL) = serviceError
                else {
                    XCTFail("Expected ChecksumServiceError.unreadable for \(url.lastPathComponent), got: \(error)")
                    continue
                }
                XCTAssertEqual(failedURL, url, "Failure entry should carry the offending URL")
            case nil:
                XCTFail("Unreadable file \(url.lastPathComponent) should appear as a .failure entry, not be omitted")
            }
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
