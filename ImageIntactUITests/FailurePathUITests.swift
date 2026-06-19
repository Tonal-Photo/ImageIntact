//
//  FailurePathUITests.swift
//  ImageIntactUITests
//
//  P0 integrity: a backup with unreadable source files must surface the
//  failures honestly (failed>0) and still copy the readable ones — never
//  silently succeed with failed=0. AMUX-375.
//

import XCTest

final class FailurePathUITests: ImageIntactUITestCase {

  func testBackup_WithUnreadableSourceFiles_SurfacesFailedCount() throws {
    // 6 source files; 2 are chmod-000 (unreadable). The completion sheet must
    // report the 2 as failed and still copy the other 4.
    let a = launchApp(fixtures: "src=6,dests=1,failures=2")
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "failure-path-no-source-row")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return
    }
    XCTAssertTrue(main.folderRow("dest1").exists, "seam-selected destination is not shown")

    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "failure-path-no-completion")
      XCTFail("completion sheet never appeared; element tree dumped")
      return
    }

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertFalse(stats.isEmpty, "completion stats accessibility value is empty")

    // Integrity: the 2 unreadable files must be reported, not silently dropped.
    XCTAssertFalse(
      stats.contains("failed=0"),
      "backup silently succeeded despite 2 unreadable source files: \(stats)")
    XCTAssertTrue(
      stats.contains("failed=2"),
      "expected exactly 2 reported failures: \(stats)")
    XCTAssertTrue(
      stats.contains("inSource=6"),
      "expected all 6 source files accounted for: \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c4/s0/f2"),
      "expected dest1 to copy the 4 readable files and report the 2 unreadable as failed: \(stats)")
  }
}
