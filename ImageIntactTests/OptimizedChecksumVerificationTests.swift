//
//  OptimizedChecksumVerificationTests.swift
//  ImageIntactTests
//
//  AMUX-352 / gh#134: post-copy verification must bypass the page cache.
//  Locks the ChecksumReadPolicy routing and the no-cache streaming read path.
//

import CryptoKit
import XCTest

@testable import ImageIntact

final class OptimizedChecksumVerificationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("OptimizedChecksumVerificationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// Writes `bytes` of random data and returns the file URL plus an
    /// independently-computed CryptoKit reference hash.
    private func writeRandomFile(named name: String, bytes: Int) throws -> (url: URL, reference: String) {
        var data = Data(count: bytes)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            arc4random_buf(base, bytes)
        }
        let url = tempDir.appendingPathComponent(name)
        try data.write(to: url)
        let reference = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()
        return (url, reference)
    }

    // MARK: - Strategy routing (pure function)

    func testStandardPolicySmallFileUsesDirectMapped() {
        XCTAssertEqual(
            OptimizedChecksum.readStrategy(forFileSize: 5_000_000, policy: .standard),
            .directMapped)
    }

    func testStandardPolicyLargeFileStreamsWithCacheEnabled() {
        XCTAssertEqual(
            OptimizedChecksum.readStrategy(forFileSize: 50_000_000, policy: .standard),
            .streaming(noCache: false))
    }

    func testVerificationPolicySmallFileStreamsWithNoCache() {
        // The <10MB mmap shortcut must never apply to verification reads.
        XCTAssertEqual(
            OptimizedChecksum.readStrategy(forFileSize: 5_000_000, policy: .verification),
            .streaming(noCache: true))
    }

    func testVerificationPolicyLargeFileStreamsWithNoCache() {
        XCTAssertEqual(
            OptimizedChecksum.readStrategy(forFileSize: 50_000_000, policy: .verification),
            .streaming(noCache: true))
    }

    // MARK: - Correctness through the real no-cache read path

    func testVerificationChecksumMatchesReferenceForSmallFile() throws {
        let (url, reference) = try writeRandomFile(named: "small.bin", bytes: 1_000_000)
        let hash = try OptimizedChecksum.sha256(for: url, policy: .verification)
        XCTAssertEqual(hash, reference)
    }

    func testVerificationChecksumMatchesReferenceForMultiChunkFile() throws {
        // >10MB: exercises chunked no-cache reads across multiple buffer fills.
        let (url, reference) = try writeRandomFile(named: "large.bin", bytes: 12_000_000)
        let hash = try OptimizedChecksum.sha256(for: url, policy: .verification)
        XCTAssertEqual(hash, reference)
    }

    func testVerificationAndStandardPoliciesAgree() throws {
        let (url, _) = try writeRandomFile(named: "agree.bin", bytes: 2_000_000)
        let standard = try OptimizedChecksum.sha256(for: url, policy: .standard)
        let verification = try OptimizedChecksum.sha256(for: url, policy: .verification)
        XCTAssertEqual(standard, verification)
    }

    func testVerificationPolicyEmptyFileReturnsSentinel() throws {
        let url = tempDir.appendingPathComponent("empty.bin")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let hash = try OptimizedChecksum.sha256(for: url, policy: .verification)
        XCTAssertEqual(hash, "empty-file-0-bytes")
    }

    func testVerificationPolicyHonorsCancellation() throws {
        let (url, _) = try writeRandomFile(named: "cancel.bin", bytes: 12_000_000)
        XCTAssertThrowsError(
            try OptimizedChecksum.sha256(for: url, policy: .verification, shouldCancel: { true })
        ) { error in
            guard case ChecksumError.cancelled = error else {
                return XCTFail("Expected ChecksumError.cancelled, got \(error)")
            }
        }
    }
}
