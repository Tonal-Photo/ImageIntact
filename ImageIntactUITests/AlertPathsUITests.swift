//
//  AlertPathsUITests.swift
//  ImageIntactUITests
//
//  Covers the two confirmation-alert flows around a backup run:
//   - Large-backup alert (Continue / Cancel / Don't-Show-Again-&-Continue),
//     triggered by lowering the file threshold so the 6 tiny fixtures trip it.
//   - Move-source-to-Trash (Keep / Move to Trash), shown after a clean backup
//     when the "Move source to Trash after backup" preference is on.
//
//  SwiftUI `.alert` surfaces as `app.sheets`; alert buttons are scoped to the
//  sheet element (a bare `app.buttons` can resolve to the Touch Bar copy).
//  See .planning/design/ui-test-alert-paths.md.
//

import XCTest

final class AlertPathsUITests: ImageIntactUITestCase {

  /// The seam's source fixture dir inside the (sandboxed) app container. The
  /// UI-test runner is not sandboxed, so it can stat this path directly — the
  /// observable for the Move-to-Trash path (the runner cannot see the Trash).
  private var containerSourceDir: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
      "Library/Containers/com.tonalphoto.tech.ImageIntact/Data/tmp/imageintact-uitest/source")
  }

  private func waitForGone(_ url: URL, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if !FileManager.default.fileExists(atPath: url.path) { return true }
      Thread.sleep(forTimeInterval: 0.2)
    }
    return !FileManager.default.fileExists(atPath: url.path)
  }

  // MARK: - Large-backup alert

  /// Lower the file threshold to 3 so the 6 fixtures (> 3) trip the alert.
  private func launchToLargeBackupAlert() -> (XCUIApplication, XCUIElement) {
    let a = launchApp(
      fixtures: "src=6,dests=1", extraArgs: ["-largeBackupFileThreshold", "3"])
    let main = MainScreen(app: a)
    if !main.folderRow("source").waitForExistence(timeout: 12) {
      dumpElementTree(a, label: "alert-large-no-source")
      XCTFail("seam-selected source folder is not shown; element tree dumped")
    }
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    main.runBackupButton.click()

    let continueBtn = a.sheets.buttons["Continue"]
    if !continueBtn.waitForExistence(timeout: 25) {
      dumpElementTree(a, label: "alert-large-no-alert")
      XCTFail("large-backup confirmation alert never appeared; element tree dumped")
    }
    return (a, continueBtn)
  }

  func testLargeBackup_Continue_ProceedsToCompletion() throws {
    let (a, continueBtn) = launchToLargeBackupAlert()
    continueBtn.click()

    let completion = a.staticTexts["sheet.completion"].firstMatch
    XCTAssertTrue(
      completion.waitForExistence(timeout: 60), "backup did not complete after Continue")
    let stats = pollValue(of: completion, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files: \(stats)")
  }

  func testLargeBackup_Cancel_AbortsBackup() throws {
    let (a, _) = launchToLargeBackupAlert()
    let cancelBtn = a.sheets.buttons["Cancel"]
    XCTAssertTrue(cancelBtn.waitForExistence(timeout: 5), "Cancel button missing from alert")
    cancelBtn.click()

    // No backup may run after Cancel: the completion sheet must not appear.
    XCTAssertFalse(
      a.staticTexts["sheet.completion"].firstMatch.waitForExistence(timeout: 8),
      "completion sheet appeared — backup ran despite Cancel")

    let main = MainScreen(app: a)
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup not clickable after Cancel")
    XCTAssertTrue(main.runBackupButton.isEnabled, "Run Backup disabled after Cancel")
  }

  func testLargeBackup_DontShowAgain_SuppressesOnSecondRunSameLaunch() throws {
    let (a, _) = launchToLargeBackupAlert()
    let dontShow = a.sheets.buttons["Don't Show Again & Continue"]
    XCTAssertTrue(dontShow.waitForExistence(timeout: 5), "Don't Show Again button missing")
    dontShow.click()

    let completion = CompletionSheet(app: a)
    XCTAssertTrue(
      completion.marker.waitForExistence(timeout: 60), "first backup did not complete")
    XCTAssertTrue(waitUntilHittable(completion.closeButton), "Close button not clickable")
    completion.closeButton.click()
    XCTAssertTrue(
      completion.marker.waitForNonExistence(timeout: 10), "completion sheet did not dismiss")

    // Second run in the SAME launch: the warning was suppressed, so the alert
    // must NOT reappear and the backup must complete directly.
    let main = MainScreen(app: a)
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup not clickable for second run")
    main.runBackupButton.click()

    XCTAssertFalse(
      a.sheets.buttons["Don't Show Again & Continue"].waitForExistence(timeout: 6),
      "large-backup alert reappeared after Don't Show Again")
    XCTAssertTrue(
      completion.marker.waitForExistence(timeout: 60), "second backup did not complete")
  }

  // MARK: - Move-source-to-Trash

  /// Default threshold (no large-backup alert); trash-after-backup enabled, so
  /// the trash confirmation appears once the clean backup completes.
  private func launchToTrashConfirmation() -> (XCUIApplication, XCUIElement) {
    let a = launchApp(
      fixtures: "src=6,dests=1", extraArgs: ["-trashSourceAfterBackup", "YES"])
    let main = MainScreen(app: a)
    if !main.folderRow("source").waitForExistence(timeout: 12) {
      dumpElementTree(a, label: "alert-trash-no-source")
      XCTFail("seam-selected source folder is not shown; element tree dumped")
    }
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    main.runBackupButton.click()

    // The completion sheet presents first; the trash `.alert` is deferred behind
    // it (a `.sheet` and an `.alert` can't present at once). Dismiss completion
    // to reveal the trash prompt — this mirrors the real flow: see the report,
    // close it, then get asked whether to trash the source.
    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 60) {
      dumpElementTree(a, label: "alert-trash-no-completion")
      XCTFail("backup did not complete before the trash prompt; element tree dumped")
    }
    XCTAssertTrue(waitUntilHittable(completion.closeButton), "completion Close not clickable")
    completion.closeButton.click()

    let moveBtn = a.sheets.buttons["Move to Trash"]
    if !moveBtn.waitForExistence(timeout: 15) {
      dumpElementTree(a, label: "alert-trash-no-confirmation")
      XCTFail("trash confirmation alert never appeared after closing completion; tree dumped")
    }
    return (a, moveBtn)
  }

  func testTrashSource_Keep_LeavesSourceInPlace() throws {
    let (a, _) = launchToTrashConfirmation()
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: containerSourceDir.path),
      "source fixture dir missing before the trash decision")

    let keep = a.sheets.buttons["Keep"]
    XCTAssertTrue(keep.waitForExistence(timeout: 5), "Keep button missing from trash alert")
    keep.click()

    // Keep must leave the source in place.
    XCTAssertFalse(
      waitForGone(containerSourceDir, timeout: 5),
      "source fixture dir was removed despite choosing Keep")
  }

  func testTrashSource_MoveToTrash_RemovesSourceDir() throws {
    let (_, moveBtn) = launchToTrashConfirmation()
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: containerSourceDir.path),
      "source fixture dir missing before Move to Trash")

    moveBtn.click()

    // Move-to-Trash must remove the source dir from the container (it is moved
    // to the Trash, which the runner cannot inspect — absence is the observable).
    XCTAssertTrue(
      waitForGone(containerSourceDir, timeout: 20),
      "source fixture dir still present after Move to Trash")
  }
}
