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

  /// The borderless preset/filter `Menu`s surface as `.menuButton` whose
  /// `title` is the label text ("Presets"/"Filter") — the `identifier` is the
  /// SF Symbol, so match on title (confirmed via the element dump).
  private func menuButton(_ a: XCUIApplication, title: String) -> XCUIElement {
    a.menuButtons.matching(NSPredicate(format: "title == %@", title)).firstMatch
  }

  /// Open a borderless menu by its title; dump the tree on failure.
  @discardableResult
  private func openMenu(_ a: XCUIApplication, title: String, dump: String) -> Bool {
    let menu = menuButton(a, title: title)
    if menu.waitForExistence(timeout: 10), menu.isHittable {
      menu.click()
      return true
    }
    dumpElementTree(a, label: dump)
    return false
  }

  /// A menu item matched by exact title (SwiftUI `Button` menu items expose the
  /// title, not a label).
  private func menuItem(_ a: XCUIApplication, title: String) -> XCUIElement {
    a.menuItems.matching(NSPredicate(format: "title == %@", title)).firstMatch
  }

  // MARK: - Presets

  func testPresetSheetOpensAndApplies() throws {
    let a = launchApp(fixtures: "src=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")

    if !openMenu(a, title: "Presets", dump: "preset-menu-missing") {
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

    // PresetSelectionRow is a Button whose label contains the preset name; its
    // existence also proves the sheet opened.
    let row = a.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Daily Workflow")).firstMatch
    if !row.waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "preset-row-missing")
      XCTFail("'Daily Workflow' preset row not found; tree dumped")
      return
    }
    row.click()

    let apply = a.sheets.buttons["Apply"].firstMatch
    XCTAssertTrue(waitUntilHittable(apply), "Apply button not hittable")
    apply.click()

    // Applying selects the preset, so the Presets menu now reads its name.
    XCTAssertTrue(
      menuButton(a, title: "Daily Workflow").waitForExistence(timeout: 10),
      "applying 'Daily Workflow' did not update the selected preset")
  }

  // MARK: - File-type filter

  /// Baseline: with no filter, a mixed source (4 photos + 2 videos) backs up
  /// all six files — the contrast that makes the filtered run measurable.
  func testUnfilteredBackupCopiesAllFileTypes() throws {
    let a = launchApp(fixtures: "src=4,videos=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")
    XCTAssertTrue(main.folderRow("dest1").waitForExistence(timeout: 10), "seam dest not shown")

    XCTAssertTrue(
      waitUntilHittable(main.runBackupButton, timeout: 20), "Run Backup not clickable")
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
  /// backed up — the filtered count appears in the completion stats (4, not 6).
  func testPhotosOnlyFilterReducesBackup() throws {
    let a = launchApp(fixtures: "src=4,videos=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")
    XCTAssertTrue(main.folderRow("dest1").waitForExistence(timeout: 10), "seam dest not shown")

    if !openMenu(a, title: "Filter", dump: "filter-menu-missing") {
      XCTFail("Filter menu not found; tree dumped")
      return
    }
    let photosOnly = menuItem(a, title: "Photos Only")
    if !photosOnly.waitForExistence(timeout: 5) {
      dumpElementTree(a, label: "photos-only-item-missing")
      XCTFail("'Photos Only' menu item not found; tree dumped")
      return
    }
    photosOnly.click()

    XCTAssertTrue(
      waitUntilHittable(main.runBackupButton, timeout: 20), "Run Backup not clickable")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "filtered-no-completion")
      XCTFail("completion sheet never appeared; tree dumped")
      return
    }
    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    // 4 photos kept, 2 videos excluded — the filtered count, vs 6 unfiltered.
    XCTAssertTrue(
      stats.contains("inSource=4"), "expected inSource=4 (2 videos filtered out): \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c4/s0/f0"), "expected only 4 photos copied: \(stats)")
    completion.closeButton.click()
  }

  /// "Videos Only" is the inverse: it keeps only the 2 `.mov` files. Together
  /// with the Photos-Only run this proves the filter SELECTS by type rather
  /// than globally dropping videos.
  func testVideosOnlyFilterSelectsOnlyVideos() throws {
    let a = launchApp(fixtures: "src=4,videos=2,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source not shown")
    XCTAssertTrue(main.folderRow("dest1").waitForExistence(timeout: 10), "seam dest not shown")

    if !openMenu(a, title: "Filter", dump: "filter-menu-missing-videos") {
      XCTFail("Filter menu not found; tree dumped")
      return
    }
    let videosOnly = menuItem(a, title: "Videos Only")
    if !videosOnly.waitForExistence(timeout: 5) {
      dumpElementTree(a, label: "videos-only-item-missing")
      XCTFail("'Videos Only' menu item not found; tree dumped")
      return
    }
    videosOnly.click()

    XCTAssertTrue(
      waitUntilHittable(main.runBackupButton, timeout: 20), "Run Backup not clickable")
    main.runBackupButton.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "videos-filtered-no-completion")
      XCTFail("completion sheet never appeared; tree dumped")
      return
    }
    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(
      stats.contains("inSource=2"), "expected inSource=2 (4 photos filtered out): \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c2/s0/f0"), "expected only 2 videos copied: \(stats)")
    completion.closeButton.click()
  }
}
