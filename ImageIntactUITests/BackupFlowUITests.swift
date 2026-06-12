//
//  BackupFlowUITests.swift
//  ImageIntactUITests
//
//  P0: the core single-destination backup flow, end to end through the UI.
//

import XCTest

final class BackupFlowUITests: ImageIntactUITestCase {

  func testCoreBackupFlow_SingleDestination_CompletesWithFullStats() throws {
    let a = launchApp(fixtures: "src=6,dests=1")
    let main = MainScreen(app: a)

    // Seam-selected folders are visible in the UI before any interaction.
    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "core-flow-no-source-row")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return
    }
    XCTAssertTrue(main.folderRow("dest1").exists, "seam-selected destination is not shown")

    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    XCTAssertTrue(main.runBackupButton.isEnabled, "Run Backup should be enabled with source+dest set")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "core-flow-no-completion")
      XCTFail("completion sheet never appeared; element tree dumped")
      return
    }

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertFalse(stats.isEmpty, "completion stats accessibility value is empty")
    XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files in stats: \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c6/s0/f0"),
      "expected dest1 to copy all 6 files cleanly: \(stats)")

    XCTAssertTrue(waitUntilHittable(completion.closeButton), "Close button not clickable")
    completion.closeButton.click()
    XCTAssertTrue(
      completion.marker.waitForNonExistence(timeout: 10),
      "completion sheet did not dismiss")
  }

  func testRunBackup_DisabledWithoutAnySelection() throws {
    let a = launchApp(fixtures: nil)
    let main = MainScreen(app: a)

    XCTAssertTrue(main.runBackupButton.waitForExistence(timeout: 10))
    XCTAssertFalse(
      main.runBackupButton.isEnabled,
      "Run Backup must be disabled with no source and no destination")
  }

  func testClearAll_DisablesRunBackup() throws {
    let a = launchApp(fixtures: "src=2,dests=1")
    let main = MainScreen(app: a)

    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10))
    XCTAssertTrue(waitUntilHittable(main.runBackupButton))
    XCTAssertTrue(main.runBackupButton.isEnabled)

    XCTAssertTrue(waitUntilHittable(main.clearAllButton))
    main.clearAllButton.click()

    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, main.runBackupButton.isEnabled {
      Thread.sleep(forTimeInterval: 0.15)
    }
    XCTAssertFalse(main.runBackupButton.isEnabled, "Run Backup still enabled after Clear All")
  }
}
