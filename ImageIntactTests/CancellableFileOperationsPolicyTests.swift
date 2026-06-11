//
//  CancellableFileOperationsPolicyTests.swift
//  ImageIntactTests
//
//  AMUX-352 / gh#134: CancellableFileOperations must forward the read policy
//  to ChecksumService rather than fall back to the policy-dropping compat shim.
//

import CryptoKit
import XCTest

@testable import ImageIntact

final class CancellableFileOperationsPolicyTests: XCTestCase {
    func testVerificationPolicyChecksumMatchesReference() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CancellableFileOperationsPolicyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        var data = Data(count: 300_000)
        data.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            arc4random_buf(base, 300_000)
        }
        let url = dir.appendingPathComponent("payload.bin")
        try data.write(to: url)
        let reference = SHA256.hash(data: data)
            .compactMap { String(format: "%02x", $0) }
            .joined()

        let hash = try await CancellableFileOperations().calculateChecksum(
            for: url, policy: .verification, shouldCancel: { false })
        XCTAssertEqual(hash, reference)
    }
}
