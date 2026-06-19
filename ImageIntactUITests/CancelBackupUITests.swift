//
//  CancelBackupUITests.swift
//  ImageIntactUITests
//
//  Proves the Cancel button stops a running backup mid-copy and returns the UI
//  to a runnable state. Six tiny fixtures back up in ~2-3s — too fast to cancel
//  mid-copy — so a DEBUG-only per-file copy throttle (--testCopyDelayMs) holds
//  the backup in the copy phase. Each test first asserts the throttle is in
//  effect (no completion within `throttleProofSeconds`, which an unthrottled
//  run always beats), which is exactly what fails before the throttle seam
//  exists. See .planning/design/ui-test-cancel-backup.md.
//

import XCTest

final class CancelBackupUITests: ImageIntactUITestCase {

  /// Per-file copy delay (ms). Six fixtures across at most four workers spend
  /// >= ceil(6/4) * 4000ms = 8s in the copy phase — comfortably longer than the
  /// proof window below, and far longer than an unthrottled ~2-3s backup.
  private let copyDelayMs = "4000"

  /// If the completion sheet appears within this many seconds of starting, the
  /// backup was not throttled (an unthrottled six-fixture backup finishes in
  /// ~2-3s). The throttle keeps the copy phase open for >= 8s, so this window
  /// passes only when the seam is active.
  private let throttleProofSeconds: TimeInterval = 5

  func testCancelDuringCopy_StopsRun_RunReenables_NoCompletionSheet_FollowupGreen() throws {
    let a = launchApp(
      fixtures: "src=6,dests=1",
      extraArgs: ["--testCopyDelayMs", copyDelayMs])
    let main = MainScreen(app: a)

    XCTAssertTrue(
      main.folderRow("source").waitForExistence(timeout: 10),
      "seam-selected source folder is not shown")
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    XCTAssertTrue(main.runBackupButton.isEnabled, "Run Backup should be enabled with source+dest set")
    main.runBackupButton.click()

    // Throttle proof: the backup must still be running after the proof window.
    // Without the copy throttle the six fixtures finish in ~2-3s and the sheet
    // appears here — the Red failure (run completes before it can be cancelled).
    let completion = CompletionSheet(app: a)
    XCTAssertFalse(
      completion.marker.waitForExistence(timeout: throttleProofSeconds),
      "completion sheet appeared within \(throttleProofSeconds)s — copy throttle not active, cannot cancel mid-copy")

    // The copy-phase cancel button exists ONLY while files are copying
    // (isProcessing && totalFiles > 0); with the throttle holding the copy
    // phase open it is present and we are provably mid-copy.
    let cancel = a.buttons["backup.cancel.copying"].firstMatch
    if !cancel.waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "cancel-no-copy-phase")
      XCTFail("copy-phase cancel button never appeared")
      return
    }
    cancel.click()

    // PRIMARY signal: cancelOperation() flips isProcessing=false synchronously,
    // re-enabling Run Backup. A broken cancel leaves it disabled (run still in
    // flight, or a completion sheet still up).
    XCTAssertTrue(
      pollUntil(timeout: 15) { main.runBackupButton.isEnabled },
      "Run Backup did not re-enable after cancel")

    // CORROBORATION: cancelling means no completion sheet appears.
    XCTAssertFalse(
      completion.marker.exists,
      "completion sheet appeared despite cancel: \(completion.stats)")

    // The same fixtures must back up green on a follow-up run. Partial files
    // from the cancelled run may remain at the destination, so assert the
    // re-runnable-to-green contract (no failures, all six still in source)
    // rather than pinning copy/skip counts.
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup not clickable for follow-up")
    main.runBackupButton.click()
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "cancel-followup-no-completion")
      XCTFail("follow-up backup produced no completion sheet")
      return
    }
    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("failed=0"), "follow-up backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "follow-up expected 6 source files: \(stats)")
  }

  /// The Escape key is deliberately NOT a cancel path: ContentView suppresses
  /// onExitCommand. Pressing it mid-copy must do nothing — the backup runs to
  /// completion.
  func testEscapeKeyDuringCopy_DoesNotCancelBackup() throws {
    let a = launchApp(
      fixtures: "src=6,dests=1",
      extraArgs: ["--testCopyDelayMs", copyDelayMs])
    let main = MainScreen(app: a)

    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10))
    XCTAssertTrue(waitUntilHittable(main.runBackupButton))
    main.runBackupButton.click()

    // Throttle proof (same as above): be provably mid-copy before pressing Escape.
    let completion = CompletionSheet(app: a)
    XCTAssertFalse(
      completion.marker.waitForExistence(timeout: throttleProofSeconds),
      "completion sheet appeared within \(throttleProofSeconds)s — copy throttle not active")
    let cancel = a.buttons["backup.cancel.copying"].firstMatch
    XCTAssertTrue(cancel.waitForExistence(timeout: 10), "copy phase not reached before pressing Escape")

    // Escape must NOT cancel — the backup keeps copying and completes.
    a.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])

    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "escape-no-completion")
      XCTFail("backup did not complete — Escape may have cancelled it")
      return
    }
    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files: \(stats)")
  }

  // MARK: - Helpers

  /// Poll a boolean condition on the live UI until it holds or the deadline
  /// passes. Mirrors the base class's deadline-loop approach (XCTNSPredicate on
  /// element state hits a stale-snapshot bug).
  private func pollUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() { return true }
      Thread.sleep(forTimeInterval: 0.15)
    }
    return condition()
  }
}
