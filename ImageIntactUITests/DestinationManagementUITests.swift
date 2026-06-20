//
//  DestinationManagementUITests.swift
//  ImageIntactUITests
//
//  Drives the destination-row Add/Remove flow through the real UI, with NO
//  powerbox. Existing tests seam-inject destinations; this covers the buttons
//  that grow and shrink the destination list.
//
//  Design + the powerbox-free driver choice: .planning/design/ui-test-suite.md
//  ("2026-06-20 - Destination add/remove via UI buttons"). Key facts:
//    - Max destinations = 4 (DestinationManager.addDestination no-ops at 4).
//    - The in-panel "Add" button fires a .fileImporter powerbox (out of scope),
//      so adds go through the File-menu "Add Destination" item, which appends an
//      EMPTY row directly. Empty rows label as "Destination N".
//    - The FolderRow "Remove" button shows only on FILLED rows when count > 1.
//      FolderRow is shared by source + destinations, so destination Remove
//      buttons carry an accessibilityIdentifier ("dest.remove") to disambiguate
//      them from the source row's Remove button.
//

import XCTest

final class DestinationManagementUITests: ImageIntactUITestCase {

  /// The real cap enforced by DestinationManager.addDestination (count < 4).
  private let maxDestinations = 4

  // MARK: - Helpers

  /// Adds an empty destination row through the File-menu "Add Destination"
  /// item — the only powerbox-free way to grow the list. The in-panel "Add"
  /// button opens an NSOpenPanel and would hang the test.
  ///
  /// macOS menu items only populate/become hittable once their parent menu is
  /// opened (see PreferencesUITests), so open the File menu first, then click
  /// the item. "Add Destination" is duplicated in BOTH the File menu
  /// (CommandGroup(replacing: .newItem)) and the custom "ImageIntact" menu, so
  /// a bare `app.menuItems["Add Destination"]` is ambiguous ("multiple matching
  /// elements"). Scope the query to the File menu bar item's descendants.
  private func menuAddDestination(_ a: XCUIApplication) {
    let fileMenu = a.menuBars.menuBarItems["File"]
    XCTAssertTrue(fileMenu.waitForExistence(timeout: 10), "File menu bar item not found")
    fileMenu.click()

    let item = fileMenu.menuItems["Add Destination"]
    XCTAssertTrue(
      item.waitForExistence(timeout: 5), "File > Add Destination menu item missing")
    item.click()
  }

  /// An empty destination row surfaces as a button whose label is its title
  /// "Destination N" (FolderRow shows `selectedURL?.lastPathComponent ?? title`).
  private func emptyRow(_ a: XCUIApplication, _ index1Based: Int) -> XCUIElement {
    a.windows.buttons["Destination \(index1Based)"].firstMatch
  }

  /// Destination Remove buttons, scoped by their accessibilityIdentifier so the
  /// shared source-row Remove button never matches.
  private func destRemoveButtons(_ a: XCUIApplication) -> XCUIElementQuery {
    a.windows.buttons.matching(identifier: "dest.remove")
  }

  /// Clicks a destination Remove button reliably. It is a plain 11pt "Remove"
  /// text button (~42x14) hard against the window's right edge and the Run Backup
  /// button; XCUITest intermittently reports it "Not hittable" or lands a near-miss
  /// `.click()` that never fires `onClear`. A center-coordinate click hits the
  /// exact target and bypasses the flaky hittability gate.
  private func clickRemove(_ button: XCUIElement) {
    XCTAssertTrue(button.waitForExistence(timeout: 5), "destination Remove button not present")
    button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
  }

  // MARK: - Add grows rows, capped at the real max (4)

  func testAddDestination_GrowsRows_AndCapsAtMax() throws {
    // Start with one empty destination (no fixtures → single blank slot).
    let a = launchApp(fixtures: nil)
    let main = MainScreen(app: a)
    XCTAssertTrue(main.runBackupButton.waitForExistence(timeout: 10))

    // Row 1 is the initial empty slot; nothing beyond it yet.
    XCTAssertTrue(emptyRow(a, 1).exists, "initial empty destination row missing")
    XCTAssertFalse(emptyRow(a, 2).exists, "should start with exactly one destination row")

    // Menu-Add up to the cap; each add appends one empty "Destination N" row.
    for target in 2...maxDestinations {
      menuAddDestination(a)
      XCTAssertTrue(
        emptyRow(a, target).waitForExistence(timeout: 5),
        "menu Add did not grow to \(target) rows")
    }

    // At the cap, the in-panel "Add destination folder" button must be gone.
    XCTAssertFalse(
      a.buttons["Add destination folder"].exists,
      "in-panel Add button should be hidden at the \(maxDestinations)-destination cap")

    // A further menu-Add no-ops: no "Destination 5" row appears.
    menuAddDestination(a)
    XCTAssertFalse(
      emptyRow(a, maxDestinations + 1).waitForExistence(timeout: 3),
      "addDestination must cap at \(maxDestinations); a \(maxDestinations + 1)th row appeared")
  }

  // MARK: - Remove shrinks rows

  func testRemoveDestination_ShrinksRows() throws {
    // Two seam-filled destinations → both rows show a "Remove" button (count>1).
    let a = launchApp(fixtures: "src=6,dests=2")
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "remove-shrinks-no-source")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return
    }
    XCTAssertTrue(main.folderRow("dest1").exists, "seam dest1 row missing")
    XCTAssertTrue(main.folderRow("dest2").exists, "seam dest2 row missing")

    // Two filled destination rows → two destination Remove buttons.
    let removes = destRemoveButtons(a)
    XCTAssertTrue(
      removes.firstMatch.waitForExistence(timeout: 5),
      "no destination Remove button shown for filled rows")
    XCTAssertEqual(removes.count, 2, "expected a Remove button on each of the 2 filled rows")

    // Remove one filled destination. Exactly one of the two folder rows survives
    // (which one depends on AX ordering — assert the shrink, not the identity).
    clickRemove(removes.firstMatch)

    // With one filled row, count==1, so it no longer shows a Remove button.
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, destRemoveButtons(a).count > 0 {
      Thread.sleep(forTimeInterval: 0.15)
    }
    XCTAssertEqual(
      destRemoveButtons(a).count, 0,
      "the single remaining destination should not show a Remove button after shrink")

    // The list shrank from two folder rows to one.
    let dest1Present = main.folderRow("dest1").exists
    let dest2Present = main.folderRow("dest2").exists
    XCTAssertTrue(
      dest1Present != dest2Present,
      "exactly one of dest1/dest2 should remain after removing one (dest1=\(dest1Present), dest2=\(dest2Present))")
    XCTAssertTrue(
      main.runBackupButton.isEnabled,
      "Run Backup should stay enabled with one destination still selected")
  }

  // MARK: - Removing the last destination disables Run Backup

  func testRemoveLastDestination_DisablesRunBackup() throws {
    // One seam-filled destination → Run Backup enabled.
    let a = launchApp(fixtures: "src=6,dests=1")
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "remove-last-no-source")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return
    }
    XCTAssertTrue(main.folderRow("dest1").exists, "seam dest1 row missing")
    XCTAssertTrue(waitUntilHittable(main.runBackupButton))
    XCTAssertTrue(main.runBackupButton.isEnabled, "Run Backup should be enabled with one destination")

    // Menu-Add an empty row so the filled row keeps a Remove button (count>1)
    // while an empty survivor remains after removal.
    menuAddDestination(a)
    XCTAssertTrue(
      emptyRow(a, 2).waitForExistence(timeout: 5),
      "menu Add did not create a second (empty) destination row")

    // Exactly one destination Remove button — on the filled row (the empty
    // row has none).
    let removes = destRemoveButtons(a)
    XCTAssertTrue(removes.firstMatch.waitForExistence(timeout: 5), "filled row has no Remove button")
    XCTAssertEqual(removes.count, 1, "only the filled row should show a Remove button")
    clickRemove(removes.firstMatch)

    // Discriminator: confirm the filled row was actually removed (vs. a wrong-row
    // removal leaving dest1, which would correctly keep Run Backup enabled).
    let dest1Gone = main.folderRow("dest1").waitForNonExistence(timeout: 10)
    if !dest1Gone { dumpElementTree(a, label: "remove-last-dest1-not-removed") }
    XCTAssertTrue(dest1Gone, "dest1 (filled) row should be gone after clicking its Remove")

    // The empty survivor leaves zero usable destinations, so canRunBackup() is
    // false → Run Backup disabled.
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline, main.runBackupButton.isEnabled {
      Thread.sleep(forTimeInterval: 0.15)
    }
    XCTAssertFalse(
      main.runBackupButton.isEnabled,
      "Run Backup must be disabled once no destination is selected")
  }

  // MARK: - Backup after a UI-driven add still completes green

  func testBackupAfterUIAdd_StillCompletesGreen() throws {
    // One seam-filled destination + a UI-added empty row. The empty row is
    // compactMapped out of preflight, so the backup completes cleanly on dest1.
    let a = launchApp(fixtures: "src=6,dests=1")
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "backup-after-add-no-source")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
      return
    }
    XCTAssertTrue(main.folderRow("dest1").exists, "seam dest1 row missing")

    menuAddDestination(a)
    XCTAssertTrue(
      emptyRow(a, 2).waitForExistence(timeout: 5),
      "menu Add did not create a second (empty) destination row")

    XCTAssertTrue(waitUntilHittable(main.runBackupButton))
    XCTAssertTrue(
      main.runBackupButton.isEnabled,
      "Run Backup should be enabled — one destination is still selected")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "backup-after-add-no-completion")
      XCTFail("completion sheet never appeared after UI-driven add; element tree dumped")
      return
    }

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertFalse(stats.isEmpty, "completion stats accessibility value is empty")
    XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files in stats: \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c6/s0/f0"),
      "expected dest1 to copy all 6 files cleanly after a UI add: \(stats)")
  }
}
