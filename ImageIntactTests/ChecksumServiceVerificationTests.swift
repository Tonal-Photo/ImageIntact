//
//  ChecksumServiceVerificationTests.swift
//  ImageIntactTests
//
//  AMUX-352 / gh#134: the ChecksumReadPolicy must plumb through both
//  ChecksumService entry points without disturbing error mapping or the
//  default-policy back-compat surface.
//

import CryptoKit
import XCTest

@testable import ImageIntact

final class ChecksumServiceVerificationTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChecksumServiceVerificationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

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

    func testSyncVerificationPolicyMatchesReference() throws {
        let (url, reference) = try writeRandomFile(named: "sync.bin", bytes: 1_500_000)
        let hash = try ChecksumService.sha256(for: url, policy: .verification, shouldCancel: { false })
        XCTAssertEqual(hash, reference)
    }

    func testAsyncVerificationPolicyMatchesReference() async throws {
        let (url, reference) = try writeRandomFile(named: "async.bin", bytes: 1_500_000)
        let hash = try await ChecksumService.sha256Async(
            for: url, policy: .verification, shouldCancel: { false })
        XCTAssertEqual(hash, reference)
    }

    func testAsyncWithoutPolicyArgumentKeepsCompiling() async throws {
        // Back-compat: every existing call site omits `policy` and must not change.
        let (url, reference) = try writeRandomFile(named: "compat.bin", bytes: 200_000)
        let hash = try await ChecksumService.sha256Async(for: url, shouldCancel: { false })
        XCTAssertEqual(hash, reference)
    }

    func testVerificationPolicyPreservesFileNotFoundMapping() async {
        let missing = tempDir.appendingPathComponent("does-not-exist.bin")
        do {
            _ = try await ChecksumService.sha256Async(
                for: missing, policy: .verification, shouldCancel: { false })
            XCTFail("Expected ChecksumServiceError.fileNotFound")
        } catch ChecksumServiceError.fileNotFound {
            // expected — policy plumb must not bypass the typed error mapping
        } catch {
            XCTFail("Expected ChecksumServiceError.fileNotFound, got \(error)")
        }
    }
}
