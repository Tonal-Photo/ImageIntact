//
//  DestinationQueueVerificationPolicyTests.swift
//  ImageIntactTests
//
//  AMUX-352 / gh#134: the post-copy verification loop must request
//  no-cache (.verification) reads — a cached verify hashes RAM, not the
//  destination medium. Seam test via MockFileOperations policy recording.
//

import XCTest

@testable import ImageIntact

final class DestinationQueueVerificationPolicyTests: XCTestCase {
    func testPostCopyVerificationRequestsVerificationPolicy() async throws {
        let mockFileOps = MockFileOperations()
        let destinationURL = URL(fileURLWithPath: "/test/destination")
        let queue = await DestinationQueue(
            destination: destinationURL,
            organizationName: "TestOrg",
            fileOperations: mockFileOps
        )

        let sourceURL = URL(fileURLWithPath: "/source/verify-policy.jpg")
        let checksum = "policy123"
        let entry = FileManifestEntry(
            relativePath: "verify-policy.jpg",
            sourceURL: sourceURL,
            checksum: checksum,
            size: 7000
        )
        mockFileOps.mockChecksums[sourceURL] = checksum

        await queue.addTasks([FileTask(from: entry, priority: .normal)])
        await queue.start()

        var isComplete = false
        for _ in 0 ..< 50 {
            isComplete = await queue.isComplete()
            if isComplete { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(isComplete, "Queue should complete copy + verification")

        let verifiedCount = await queue.verifiedFiles
        XCTAssertEqual(verifiedCount, 1, "Should verify 1 file")

        // The actual guarantee under test: the verify pass asked for
        // no-cache reads, and nothing in this fresh-copy scenario fell back
        // to a policy-less (cached) checksum call.
        XCTAssertFalse(mockFileOps.checksumPolicies.isEmpty,
                       "verification must flow through the policy-aware API")
        XCTAssertTrue(mockFileOps.checksumPolicies.allSatisfy { $0 == .verification },
                      "post-copy verification must use .verification (no-cache) reads")
        XCTAssertEqual(mockFileOps.checksumCalculations.count, mockFileOps.checksumPolicies.count,
                       "no checksum call in this scenario may bypass the policy-aware API")
    }
}
