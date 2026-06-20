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

  // The UI-test runner is sandboxed to its own .xctrunner container, so it
  // cannot stat the app's source dir or the Trash. The observable for the
  // Move-to-Trash path is instead the UI: SourceManager.trashCurrentSource()
  // sets sourceURL = nil ONLY on a successful trash, so the source folder row
  // disappears iff the source was actually moved to the Trash.

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
    let main = MainScreen(app: a)

    let keep = a.sheets.buttons["Keep"]
    XCTAssertTrue(keep.waitForExistence(timeout: 5), "Keep button missing from trash alert")
    keep.click()

    // Keep does not trash, so the source selection (and its folder row) remains.
    XCTAssertTrue(
      main.folderRow("source").waitForExistence(timeout: 8),
      "source folder row vanished despite choosing Keep")
  }

  func testTrashSource_MoveToTrash_RemovesSourceDir() throws {
    let (a, moveBtn) = launchToTrashConfirmation()
    let main = MainScreen(app: a)

    // Source is still selected at the decision point.
    XCTAssertTrue(main.folderRow("source").exists, "source folder row missing before Move to Trash")

    moveBtn.click()

    // A successful trash clears the source selection
    // (SourceManager.trashCurrentSource sets sourceURL = nil only on success),
    // so the source folder row disappears — the runner-observable proxy for
    // "source moved to the Trash" (the sandboxed runner cannot stat the app
    // container or the Trash directly).
    XCTAssertTrue(
      main.folderRow("source").waitForNonExistence(timeout: 15),
      "source folder row still present after Move to Trash (trash did not take)")
  }
}
