//
//  MultiDestinationUITests.swift
//  ImageIntactUITests
//
//  P1: parallel backup to two destinations, verified through the
//  per-destination breakdown in the completion stats.
//

import XCTest

final class MultiDestinationUITests: ImageIntactUITestCase {

  func testBackup_TwoDestinations_BothCompleteCleanly() throws {
    let a = launchApp(fixtures: "src=6,dests=2")
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "multi-dest-no-source-row")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return
    }
    XCTAssertTrue(main.folderRow("dest1").exists)
    XCTAssertTrue(main.folderRow("dest2").exists)

    XCTAssertTrue(waitUntilHittable(main.runBackupButton))
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 180) {
      dumpElementTree(a, label: "multi-dest-no-completion")
      XCTFail("completion sheet never appeared for 2-destination backup")
      return
    }

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("failed=0"), "multi-destination backup reported failures: \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c6/s0/f0"), "dest1 did not copy all 6 files cleanly: \(stats)")
    XCTAssertTrue(
      stats.contains("dest2:c6/s0/f0"), "dest2 did not copy all 6 files cleanly: \(stats)")
  }
}
