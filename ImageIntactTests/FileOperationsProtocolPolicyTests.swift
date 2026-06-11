//
//  FileOperationsProtocolPolicyTests.swift
//  ImageIntactTests
//
//  AMUX-352 / gh#134: the policy-aware calculateChecksum gained a
//  protocol-extension default that forwards to the legacy 2-argument method,
//  so conformers written before ChecksumReadPolicy existed keep compiling and
//  behaving. This locks that compat shim.
//

import XCTest

@testable import ImageIntact

/// Conformer that only implements the legacy (pre-policy) protocol surface.
private final class LegacyOnlyFileOperations: FileOperationsProtocol {
    private(set) var legacyChecksumCalls: [URL] = []

    func copyItem(at source: URL, to destination: URL) async throws {}
    func fileExists(at url: URL) -> Bool { false }
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] { [:] }

    func calculateChecksum(
        for url: URL, shouldCancel: @Sendable @escaping () -> Bool
    ) async throws -> String {
        legacyChecksumCalls.append(url)
        return "legacy-checksum"
    }

    func startAccessingSecurityScopedResource(for url: URL) -> Bool { true }
    func stopAccessingSecurityScopedResource(for url: URL) {}
    func fileSize(at url: URL) -> Int64? { nil }
    func moveItem(at source: URL, to destination: URL) throws {}
    func setAttributes(_ attributes: [FileAttributeKey: Any], at url: URL) throws {}
    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws -> [URL] { [] }
    func createFile(at url: URL, contents data: Data?, attributes: [FileAttributeKey: Any]?) -> Bool { false }
    func trashItem(at url: URL) throws {}
}

final class FileOperationsProtocolPolicyTests: XCTestCase {
    func testDefaultPolicyVariantForwardsToLegacyMethod() async throws {
        let ops = LegacyOnlyFileOperations()
        let url = URL(fileURLWithPath: "/seam/photo.jpg")

        let result = try await ops.calculateChecksum(
            for: url, policy: .verification, shouldCancel: { false })

        XCTAssertEqual(result, "legacy-checksum")
        XCTAssertEqual(ops.legacyChecksumCalls, [url],
                       "default implementation must forward to the legacy method exactly once")
    }
}
