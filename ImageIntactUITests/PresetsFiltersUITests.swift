//
//  PresetsFiltersUITests.swift
//  ImageIntactUITests
//
//  Drives backup-preset selection and file-type filtering through the UI
//  (BackupConfigurationView). A preset applies its configuration; a file-type
//  filter measurably reduces a seam-fixture backup, visible in the completion
//  stats. See .planning/design/ui-test-preferences.md.
//

import XCTest

final class PresetsFiltersUITests: ImageIntactUITestCase {

  /// Open a borderless SwiftUI `Menu`. Its surfacing on macOS is uncertain
  /// (menuButton vs popUpButton vs button); try the likely shapes and dump the
  /// tree on failure. The red dump tells green which to keep / whether an
  /// accessibilityIdentifier is needed.
  @discardableResult
  private func openMenu(_ a: XCUIApplication, labelContains s: String, dump: String) -> Bool {
    let pred = NSPredicate(format: "label CONTAINS %@", s)
    for q in [a.menuButtons, a.popUpButtons, a.buttons] {
      let el = q.matching(pred).firstMatch
      if el.waitForExistence(timeout: 2), el.isHittable {
        el.click()
        return true
      }
    }
    dumpElementTree(a, label: dump)
    return false
  }

  // MARK: - Presets

  func testPresetSheetOpensAndApplies() throws {
    let a = launchApp(fixtures: "src=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")

    if !openMenu(a, labelContains: "Presets", dump: "preset-menu-missing") {
      XCTFail("Presets menu not found; tree dumped")
      return
    }
    let selectItem = a.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Select Preset"))
      .firstMatch
    if !selectItem.waitForExistence(timeout: 5) {
      dumpElementTree(a, label: "preset-select-item-missing")
      XCTFail("'Select Preset…' menu item not found; tree dumped")
      return
    }
    selectItem.click()

    XCTAssertTrue(
      a.staticTexts["Select Backup Preset"].waitForExistence(timeout: 5),
      "preset selection sheet did not open")

    // PresetSelectionRow is a Button whose label contains the preset name.
    let row = a.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Daily Workflow")).firstMatch
    if !row.waitForExistence(timeout: 5) {
      dumpElementTree(a, label: "preset-row-missing")
      XCTFail("'Daily Workflow' preset row not found; tree dumped")
      return
    }
    row.click()

    let apply = a.sheets.buttons["Apply"].firstMatch
    XCTAssertTrue(waitUntilHittable(apply), "Apply button not hittable")
    apply.click()

    // Daily Workflow carries a Photos-Only file-type filter; applying it makes
    // the filter status read "Photos Only".
    XCTAssertTrue(
      a.staticTexts["Photos Only"].waitForExistence(timeout: 10),
      "applying 'Daily Workflow' did not set the Photos Only filter")
  }

  // MARK: - File-type filter

  /// Baseline: with no filter, a mixed source (4 photos + 2 videos) backs up
  /// all six files — the contrast that makes the filtered run measurable.
  func testUnfilteredBackupCopiesAllFileTypes() throws {
    let a = launchApp(fixtures: "src=4,videos=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")

    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup not clickable")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "unfiltered-no-completion")
      XCTFail("completion sheet never appeared; tree dumped")
      return
    }
    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files (4 jpg + 2 mov): \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c6/s0/f0"), "expected all 6 files copied unfiltered: \(stats)")
    completion.closeButton.click()
  }

  /// "Photos Only" excludes the two `.mov` videos, so only the 4 photos are
  /// backed up — the filtered count appears in the completion stats.
  func testPhotosOnlyFilterReducesBackup() throws {
    let a = launchApp(fixtures: "src=4,videos=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")

    if !openMenu(a, labelContains: "Filter", dump: "filter-menu-missing") {
      XCTFail("Filter menu not found; tree dumped")
      return
    }
    let photosOnly = a.menuItems["Photos Only"].firstMatch
    if !photosOnly.waitForExistence(timeout: 5) {
      dumpElementTree(a, label: "photos-only-item-missing")
      XCTFail("'Photos Only' menu item not found; tree dumped")
      return
    }
    photosOnly.click()

    // Filter status should reflect the selection before we run.
    XCTAssertTrue(
      a.staticTexts["Photos Only"].waitForExistence(timeout: 5),
      "filter status did not update to Photos Only")

    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup not clickable")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "filtered-no-completion")
      XCTFail("completion sheet never appeared; tree dumped")
      return
    }
    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(
      stats.contains("inSource=4"), "expected inSource=4 (2 videos filtered out): \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c4/s0/f0"), "expected only 4 photos copied: \(stats)")
    completion.closeButton.click()
  }
}
