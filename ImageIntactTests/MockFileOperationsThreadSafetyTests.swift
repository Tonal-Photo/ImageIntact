//
//  MockFileOperationsThreadSafetyTests.swift
//  ImageIntactTests
//
//  AMUX-232: deflake RetryCountTests.testIsCompleteNotPrematureWithRetries.
//
//  Root cause (captured crash report ImageIntact-2026-05-29-103654.ips):
//  DestinationQueue spawns multiple workers whose `await fileOperations.X` calls
//  run on the generic executor (the mock's methods are nonisolated), so two
//  workers mutate MockFileOperations' shared `filesExist: Set<URL>` (and its
//  tracking arrays/dicts) in parallel. Concurrent Set mutation corrupts its
//  storage; a later `Set.contains` dispatches into freed memory and aborts with
//  EXC_CRASH (SIGABRT, doesNotRecognizeSelector) — observed as a 0.000s
//  "failure" of testIsCompleteNotPrematureWithRetries under full-suite parallel
//  execution (~1/5).
//
//  This test reproduces that race deterministically by hammering the mock's
//  synchronous filesExist-touching methods from many threads via
//  concurrentPerform (guaranteed real parallelism). Against the unsynchronized
//  mock it corrupts/aborts the test process (red); once the mock guards its
//  state with a lock it runs clean (green).
//

@testable import ImageIntact
import XCTest

final class MockFileOperationsThreadSafetyTests: XCTestCase {

    /// Concurrent insert/contains/remove on the mock's shared `filesExist` Set
    /// (the exact pattern DestinationQueue's parallel workers produce) must not
    /// corrupt its backing storage or crash.
    func testConcurrentFilesExistAccessIsThreadSafe() {
        let mock = MockFileOperations()

        // 8 threads × 2000 iterations of interleaved insert/contains/remove on
        // the shared Set. On an unsynchronized Set this reliably corrupts the
        // internal storage and aborts the process.
        DispatchQueue.concurrentPerform(iterations: 8) { thread in
            for i in 0..<2000 {
                let url = URL(fileURLWithPath: "/race/\(thread)/\(i).dat")
                _ = mock.fileExists(at: url)
                try? mock.createDirectory(at: url, withIntermediateDirectories: false)
                _ = mock.fileExists(at: url)
                _ = mock.createFile(at: url, contents: nil, attributes: nil)
                try? mock.removeItem(at: url)
            }
        }

        // Reaching here without aborting means the mock survived concurrent
        // access. (State is intentionally not asserted — the inserts and removes
        // race by design; the contract under test is "no corruption/crash".)
        XCTAssertTrue(true, "MockFileOperations survived concurrent filesExist access")
    }
}
