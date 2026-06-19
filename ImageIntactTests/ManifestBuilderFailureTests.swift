//
//  ManifestBuilderFailureTests.swift
//  ImageIntactTests
//
//  An unreadable source file must be reported in the build result's failures
//  and excluded from the manifest — so the backup pipeline can surface it as
//  failed>0 instead of silently dropping it. AMUX-375 / S4-11.
//

import XCTest

@testable import ImageIntact

@MainActor
final class ManifestBuilderFailureTests: XCTestCase {
  var testDirectory: URL!
  var manifestBuilder: ManifestBuilder!

  override func setUp() async throws {
    try await super.setUp()
    testDirectory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ManifestFailureTests_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: testDirectory, withIntermediateDirectories: true)
    manifestBuilder = ManifestBuilder()
  }

  override func tearDown() async throws {
    if FileManager.default.fileExists(atPath: testDirectory.path) {
      // Restore perms so the 000 fixture file can be removed.
      if let en = FileManager.default.enumerator(at: testDirectory, includingPropertiesForKeys: nil)
      {
        for case let url as URL in en {
          try? FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: url.path)
        }
      }
      try FileManager.default.removeItem(at: testDirectory)
    }
    try await super.tearDown()
  }

  func testBuild_reportsUnreadableSourceFileAndExcludesItFromManifest() async throws {
    try Data("readable".utf8).write(to: testDirectory.appendingPathComponent("ok.jpg"))
    let locked = testDirectory.appendingPathComponent("locked.jpg")
    try Data("nope".utf8).write(to: locked)
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)

    let result = await manifestBuilder.buildReportingFailures(
      source: testDirectory, shouldCancel: { false })

    let names = (result?.entries ?? []).map {
      URL(fileURLWithPath: $0.relativePath).lastPathComponent
    }
    XCTAssertEqual(names, ["ok.jpg"], "unreadable file must be excluded from the manifest")
    XCTAssertEqual(
      result?.failures.map(\.file), ["locked.jpg"], "unreadable file must be reported in failures")
  }

  func testBuild_noFailures_leavesBuildFailuresEmpty() async throws {
    try Data("a".utf8).write(to: testDirectory.appendingPathComponent("a.jpg"))
    try Data("b".utf8).write(to: testDirectory.appendingPathComponent("b.jpg"))

    let result = await manifestBuilder.buildReportingFailures(
      source: testDirectory, shouldCancel: { false })

    XCTAssertEqual(result?.entries.count, 2)
    XCTAssertEqual(result?.failures.isEmpty, true, "a clean build must report no failures")
  }
}
