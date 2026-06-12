//
//  DuplicateWarningUITests.swift
//  ImageIntactUITests
//
//  P0: the duplicate-warning sheet, end to end. With smart duplicate
//  detection enabled, source files already present at the destination
//  surface a skip/copy/cancel decision — the path where ImageIntact chooses
//  NOT to write user data, so the skip accounting must be visible in the
//  completion stats.
//
//  Fixtures: prefill=exact places byte-identical copies of the source files
//  inside the destination's organization folder, which the preflight
//  duplicate check reports as exact duplicates. Detection is off by default
//  and is enabled per-launch through the UserDefaults argument domain.
//

import XCTest

final class DuplicateWarningUITests: ImageIntactUITestCase {

  /// Launches with exact duplicates prefilled at the destination and clicks
  /// Run Backup. Returns once the duplicate sheet's marker leaf is visible.
  @discardableResult
  private func launchToDuplicateSheet() -> (XCUIApplication, DuplicateSheet) {
    let a = launchApp(
      fixtures: "src=6,dests=1,prefill=exact",
      organization: "UITestOrg",
      extraArgs: ["-enableSmartDuplicateDetection", "YES"])
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "duplicate-no-source-row")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
    }
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    main.runBackupButton.click()

    let duplicate = DuplicateSheet(app: a)
    if !duplicate.marker.waitForExistence(timeout: 30) {
      dumpElementTree(a, label: "duplicate-no-sheet")
      XCTFail("duplicate warning sheet marker never appeared; element tree dumped")
    }
    return (a, duplicate)
  }

  func testDuplicateSheet_AppearsWithExactDuplicates_OfferingAllChoices() throws {
    let (_, duplicate) = launchToDuplicateSheet()

    let info = pollValue(of: duplicate.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(info.contains("exact=6"), "expected 6 exact duplicates in marker: \(info)")
    XCTAssertTrue(info.contains("renamed=0"), "expected no renamed duplicates in marker: \(info)")

    XCTAssertTrue(
      duplicate.button("Continue with Selection").exists, "Continue with Selection button missing")
    XCTAssertTrue(duplicate.button("Copy All Anyway").exists, "Copy All Anyway button missing")
    XCTAssertTrue(duplicate.button("Cancel Backup").exists, "Cancel Backup button missing")
  }

  func testContinueWithSelection_SkipsExactDuplicates_StatsShowSkips() throws {
    let (a, duplicate) = launchToDuplicateSheet()

    // "Skip exact duplicates" defaults ON, so Continue with Selection must
    // proceed with the backup while skipping every prefilled duplicate.
    duplicate.button("Continue with Selection").click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "duplicate-continue-no-completion")
      XCTFail("backup did not complete after Continue with Selection; element tree dumped")
      return
    }
    XCTAssertTrue(
      duplicate.marker.waitForNonExistence(timeout: 10),
      "duplicate sheet still present after completion")

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files in stats: \(stats)")
    XCTAssertTrue(
      stats.contains("skipped=6"),
      "all 6 exact duplicates should be reported as skipped: \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c0/s6/f0"),
      "dest1 should skip all 6 duplicates and copy nothing: \(stats)")
  }

  func testCancelBackup_PerformsNoCopy() throws {
    let (a, duplicate) = launchToDuplicateSheet()

    duplicate.button("Cancel Backup").click()

    XCTAssertTrue(
      duplicate.marker.waitForNonExistence(timeout: 10),
      "duplicate sheet did not dismiss after Cancel Backup")

    // No backup may run after cancel: the completion sheet must not appear.
    // 6 tiny fixture files copy in ~2s, so 8s of silence is conclusive.
    let completion = CompletionSheet(app: a)
    XCTAssertFalse(
      completion.marker.waitForExistence(timeout: 8),
      "completion sheet appeared — backup ran despite Cancel Backup")

    // The app must return to an idle, re-runnable state.
    let main = MainScreen(app: a)
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup not clickable after cancel")
    XCTAssertTrue(main.runBackupButton.isEnabled, "Run Backup disabled after cancel")
  }
}
