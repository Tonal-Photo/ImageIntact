//
//  BackupManagerQueueIntegrationSeamTests.swift
//  ImageIntactTests
//
//  The backup pipeline's security-scope guards treat a false return from
//  startAccessingSecurityScopedResource as fatal. UI-test fixtures live in
//  the app container where scoped access is unnecessary (start returns
//  false but reads/writes succeed) — UITestSeam.allowsUnscopedAccess is the
//  DEBUG-only escape those guards consult. See ui-test-suite.md.
//

import XCTest

@testable import ImageIntact

final class BackupManagerQueueIntegrationSeamTests: XCTestCase {

  func testAllowsUnscopedAccess_forMarkedFixturePaths() {
    let marked = FileManager.default.temporaryDirectory
      .appendingPathComponent("imageintact-uitest")
      .appendingPathComponent("source")
    XCTAssertTrue(UITestSeam.allowsUnscopedAccess(marked))
  }

  func testDeniesUnscopedAccess_forOrdinaryPaths() {
    XCTAssertFalse(UITestSeam.allowsUnscopedAccess(URL(fileURLWithPath: "/Users/someone/Photos")))
    XCTAssertFalse(UITestSeam.allowsUnscopedAccess(URL(fileURLWithPath: "/tmp")))
  }

  func testDeniesUnscopedAccess_forMarkerBuriedDeepInPath() {
    // The marker must be on the path or a close ancestor, not arbitrarily far
    // up — a repo cloned under a marked directory must not arm the escape.
    let deep = FileManager.default.temporaryDirectory
      .appendingPathComponent("imageintact-uitest/a/b/c/d/e")
    XCTAssertFalse(UITestSeam.allowsUnscopedAccess(deep))
  }
}
