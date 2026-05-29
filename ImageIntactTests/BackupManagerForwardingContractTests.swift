//
//  BackupManagerForwardingContractTests.swift
//  ImageIntactTests
//
//  AMUX-202 — progress-forwarding contract guard (#103 decomposition).
//
//  BackupManager used to expose ~14 computed properties that merely forwarded
//  to `progressTracker.X` (totalFiles, processedFiles, currentFile, ...).
//  AMUX-202 removed those forwards so Views and tests read
//  `bm.progressTracker.X` directly. ProgressTracker is @Observable, so SwiftUI
//  re-render behavior is unchanged. This test locks the removal in: it scans
//  the BackupManager.swift source and fails if any forward reappears.
//
//  Why a source scan rather than the Mirror(reflecting:) check the ticket
//  originally specified: Swift's Mirror reflects *stored* properties only —
//  computed forwards never appear in `Mirror.children`, so a "not present in
//  the mirror" assertion is vacuously true both before and after removal and
//  can never go red. Scanning the source is the honest red→green guard.
//

import XCTest

final class BackupManagerForwardingContractTests: XCTestCase {

    /// Progress properties that must live on ProgressTracker only — never as
    /// forwarding declarations on BackupManager.
    private static let forbiddenForwards = [
        "totalFiles", "processedFiles", "currentFile", "currentFileIndex",
        "currentFileName", "currentDestinationName", "copySpeed",
        "totalBytesCopied", "totalBytesToCopy", "estimatedSecondsRemaining",
        "destinationProgress", "destinationStates", "phaseProgress", "overallProgress",
    ]

    /// Locate BackupManager.swift relative to this test file's compile-time path:
    /// <repo>/ImageIntactTests/BackupManagerForwardingContractTests.swift
    ///   -> <repo>/ImageIntact/Models/BackupManager.swift
    private func backupManagerSource(file: StaticString = #filePath) throws -> String {
        let testFileURL = URL(fileURLWithPath: "\(file)")
        let repoRoot = testFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let bmURL = repoRoot
            .appendingPathComponent("ImageIntact")
            .appendingPathComponent("Models")
            .appendingPathComponent("BackupManager.swift")
        return try String(contentsOf: bmURL, encoding: .utf8)
    }

    func testBackupManagerDoesNotForwardProgressProperties() throws {
        let source = try backupManagerSource()
        var offenders: [String] = []
        for name in Self.forbiddenForwards {
            // Matches a property declaration `var <name>:` — the forward shape.
            // The trailing `\s*:` keeps `currentFile` from matching
            // `currentFileName` / `currentFileIndex`.
            let pattern = "\\bvar\\s+\(name)\\s*:"
            if source.range(of: pattern, options: .regularExpression) != nil {
                offenders.append(name)
            }
        }
        XCTAssertTrue(
            offenders.isEmpty,
            "BackupManager must not re-declare progress forwards — read "
                + "bm.progressTracker.X directly instead. Found forward(s): "
                + offenders.joined(separator: ", ")
        )
    }
}
