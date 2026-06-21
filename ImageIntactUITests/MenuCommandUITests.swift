//
//  MenuCommandUITests.swift
//  ImageIntactUITests
//
//  Drives the SwiftUI `Commands` menu surface (app / File / Edit / Help and the
//  custom "ImageIntact" menu) and asserts each actionable command triggers its
//  effect. The menu tree is enumerated from ImageIntactApp.swift, not guessed.
//
//  Design + the full covered/excluded command list and menu-disambiguation
//  rationale: .planning/design/ui-test-suite.md
//  ("2026-06-20 - Menu-bar command coverage").
//
//  Key gotchas (see design doc):
//    - TWO menu-bar items are titled "ImageIntact": the bold app menu and the
//      custom CommandMenu("ImageIntact"). The app menu is element(boundBy: 1)
//      (Apple menu is 0); the custom menu is the one exposing the custom-only
//      "Verify Core Data Storage" item.
//    - Run Backup / Add Destination / Clear All / Select Source/Dest are each in
//      two menus, so a bare app.menuItems["X"] is ambiguous. Every item click is
//      scoped to its parent menu-bar item's descendants.
//    - Menu items only populate once their parent menu is opened.
//

import XCTest

final class MenuCommandUITests: ImageIntactUITestCase {

  // MARK: - Menu helpers

  /// The bold application menu (carries About + Preferences). Always the
  /// menu-bar item right after the Apple menu (index 0).
  private func appMenu(_ a: XCUIApplication) -> XCUIElement {
    a.menuBars.menuBarItems.element(boundBy: 1)
  }

  /// A top-level menu-bar item by title (File / Edit / Help). Unique titles.
  private func menu(_ a: XCUIApplication, _ title: String) -> XCUIElement {
    a.menuBars.menuBarItems[title]
  }

  /// Opens a menu-bar item so its items populate. Returns false (after dumping)
  /// if the item never appears.
  @discardableResult
  private func open(_ a: XCUIApplication, _ menuItem: XCUIElement, _ label: String) -> Bool {
    guard menuItem.waitForExistence(timeout: 10) else {
      dumpElementTree(a, label: "menu-missing-\(label)")
      return false
    }
    menuItem.click()
    return true
  }

  /// Opens `parent`, then clicks the descendant menu item titled `title`. Menu
  /// items report a degenerate (offscreen/zero) frame until their menu is open
  /// and rendered, so clicking before then throws an INFINITY-point exception;
  /// waiting until the item is genuinely hittable avoids that. Returns false
  /// (after a dump) if the item never becomes hittable.
  @discardableResult
  private func clickItem(
    _ a: XCUIApplication, in parent: XCUIElement, _ title: String, label: String
  ) -> Bool {
    guard open(a, parent, label) else { return false }
    let item = parent.menuItems[title]
    guard item.waitForExistence(timeout: 5), waitUntilHittable(item, timeout: 5) else {
      dumpElementTree(a, label: "menu-item-not-hittable-\(label)")
      return false
    }
    item.click()
    return true
  }

  /// The custom CommandMenu("ImageIntact") menu-bar item, disambiguated from the
  /// bold app menu (both titled "ImageIntact") by the custom-only "Verify Core
  /// Data Storage" command. The probe is SCOPED to each candidate's descendants:
  /// an unscoped `a.menuItems[...]` query matches app-wide and so resolves true
  /// for the wrong menu-bar item. Does not open the menu.
  private func customMenu(_ a: XCUIApplication) -> XCUIElement? {
    let candidates = a.menuBars.menuBarItems.matching(
      NSPredicate(format: "title == %@", "ImageIntact"))
    for i in 0..<candidates.count {
      let item = candidates.element(boundBy: i)
      if item.menuItems["Verify Core Data Storage"].exists { return item }
    }
    return nil
  }

  // MARK: - App menu: About

  func testAppMenu_About_ShowsAboutPanel() throws {
    let a = launchApp(fixtures: nil)
    // "About ImageIntact" is the first item of the bold app menu. Scope the
    // click to that menu — an app-wide query resolves a degenerate-frame item.
    guard clickItem(a, in: appMenu(a), "About ImageIntact", label: "about") else {
      return XCTFail("About item not clickable in the app menu")
    }

    // The standard About panel (orderFrontStandardAboutPanel:) opens as a Dialog
    // carrying a "Version x" static text. Assert that version text so the pass
    // is specific to the About panel, not any incidental dialog.
    let aboutVersion = a.dialogs.staticTexts.matching(
      NSPredicate(format: "value BEGINSWITH %@", "Version")).firstMatch
    if !aboutVersion.waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "about-no-panel")
      XCTFail("About panel (version text) did not appear after the menu click")
      return
    }
    a.typeKey("w", modifierFlags: .command)  // close the panel
  }

  // MARK: - App menu: Preferences

  func testAppMenu_Preferences_OpensPreferences() throws {
    let a = launchApp(fixtures: nil)
    guard open(a, appMenu(a), "app") else {
      return XCTFail("application menu not found")
    }
    let prefs = a.menuItems.matching(
      NSPredicate(format: "title BEGINSWITH %@ OR title BEGINSWITH %@", "Preferences", "Settings")
    ).firstMatch
    XCTAssertTrue(prefs.waitForExistence(timeout: 5), "Preferences item missing from the app menu")
    prefs.click()

    let close = a.sheets.buttons["Close"].firstMatch
    XCTAssertTrue(close.waitForExistence(timeout: 10), "Preferences sheet did not open")
    close.click()
  }

  // MARK: - File menu: Add Destination

  func testFileMenu_AddDestination_GrowsDestinationRows() throws {
    let a = launchApp(fixtures: nil)
    let main = MainScreen(app: a)
    XCTAssertTrue(main.runBackupButton.waitForExistence(timeout: 10))
    XCTAssertFalse(
      a.windows.buttons["Destination 2"].exists, "should start with one destination row")

    guard open(a, menu(a, "File"), "file") else { return XCTFail("File menu not found") }
    let add = menu(a, "File").menuItems["Add Destination"]
    XCTAssertTrue(add.waitForExistence(timeout: 5), "File > Add Destination missing")
    add.click()

    XCTAssertTrue(
      a.windows.buttons["Destination 2"].waitForExistence(timeout: 5),
      "File > Add Destination did not add a second destination row")
  }

  // MARK: - File menu: Run Backup

  func testFileMenu_RunBackup_StartsBackup() throws {
    let a = launchApp(fixtures: "src=6,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source missing")

    guard open(a, menu(a, "File"), "file") else { return XCTFail("File menu not found") }
    let run = menu(a, "File").menuItems["Run Backup"]
    XCTAssertTrue(run.waitForExistence(timeout: 5), "File > Run Backup missing")
    run.click()

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "file-runbackup-no-completion")
      XCTFail("File > Run Backup did not reach a completion sheet")
    }
  }

  // MARK: - File menu: Select Source Folder opens the open panel

  func testFileMenu_SelectSource_OpensOpenPanel() throws {
    let a = launchApp(fixtures: nil)
    XCTAssertTrue(MainScreen(app: a).runBackupButton.waitForExistence(timeout: 10))

    guard open(a, menu(a, "File"), "file") else { return XCTFail("File menu not found") }
    let select = menu(a, "File").menuItems["Select Source Folder"]
    XCTAssertTrue(select.waitForExistence(timeout: 5), "File > Select Source Folder missing")
    select.click()

    // App-modal NSOpenPanel surfaces as a Dialog with the system id "open-panel"
    // (see OpenPanelBackupUITests). We only prove the command opens it, then
    // cancel — folder selection itself is AMUX-371's coverage.
    let panel = a.dialogs["open-panel"]
    if !panel.waitForExistence(timeout: 15) {
      dumpElementTree(a, label: "select-source-no-panel")
      XCTFail("Select Source Folder did not open the open panel")
      return
    }
    panel.buttons["Cancel"].click()
  }

  // MARK: - File menu: Select First Destination opens the open panel

  func testFileMenu_SelectDestination_OpensOpenPanel() throws {
    // Handler opens the panel only when destinationURLs is non-empty, so seed
    // one seam destination.
    let a = launchApp(fixtures: "src=6,dests=1")
    XCTAssertTrue(
      MainScreen(app: a).folderRow("dest1").waitForExistence(timeout: 10), "seam dest1 missing")

    guard open(a, menu(a, "File"), "file") else { return XCTFail("File menu not found") }
    let select = menu(a, "File").menuItems["Select First Destination"]
    XCTAssertTrue(select.waitForExistence(timeout: 5), "File > Select First Destination missing")
    select.click()

    let panel = a.dialogs["open-panel"]
    if !panel.waitForExistence(timeout: 15) {
      dumpElementTree(a, label: "select-dest-no-panel")
      XCTFail("Select First Destination did not open the open panel")
      return
    }
    panel.buttons["Cancel"].click()
  }

  // MARK: - Edit menu: Clear All Selections

  func testEditMenu_ClearAll_ClearsSelections() throws {
    let a = launchApp(fixtures: "src=6,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source missing")
    XCTAssertTrue(main.folderRow("dest1").exists, "seam dest1 missing")

    guard open(a, menu(a, "Edit"), "edit") else { return XCTFail("Edit menu not found") }
    let clear = menu(a, "Edit").menuItems["Clear All Selections"]
    XCTAssertTrue(clear.waitForExistence(timeout: 5), "Edit > Clear All Selections missing")
    clear.click()

    XCTAssertTrue(
      main.folderRow("source").waitForNonExistence(timeout: 10),
      "source row should clear after Clear All Selections")
    XCTAssertFalse(main.folderRow("dest1").exists, "dest1 row should clear after Clear All")
  }

  // MARK: - Help menu: ImageIntact Help

  func testHelpMenu_Help_OpensHelpWindow() throws {
    let a = launchApp(fixtures: nil)
    XCTAssertTrue(MainScreen(app: a).runBackupButton.waitForExistence(timeout: 10))

    guard clickItem(a, in: menu(a, "Help"), "ImageIntact Help", label: "help") else {
      return XCTFail("Help > ImageIntact Help not clickable")
    }

    // HelpWindowManager opens an NSWindow whose NSWindow.title is "ImageIntact
    // Help", but HelpWindowView shows its default "What's New" section, so the
    // displayed window title is version-dependent ("What's New – Version x").
    // Identify the window by its unique "Search Help" field instead.
    let helpSearch = a.searchFields.matching(
      NSPredicate(format: "placeholderValue == %@", "Search Help")).firstMatch
    if !helpSearch.waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "help-no-window")
      XCTFail("Help window (Search Help field) did not appear")
      return
    }
    a.typeKey("w", modifierFlags: .command)  // close the help window
  }

  // MARK: - Custom ImageIntact menu: Run Backup matches the button/File command

  func testImageIntactMenu_RunBackup_StartsBackup() throws {
    let a = launchApp(fixtures: "src=6,dests=1")
    let main = MainScreen(app: a)
    XCTAssertTrue(main.folderRow("source").waitForExistence(timeout: 10), "seam source missing")

    guard let menuItem = customMenu(a) else {
      dumpElementTree(a, label: "custom-menu-not-found")
      XCTFail("custom ImageIntact menu (with Verify Core Data Storage) not found")
      return
    }
    guard clickItem(a, in: menuItem, "Run Backup", label: "custom-run") else {
      return XCTFail("ImageIntact > Run Backup not clickable")
    }

    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "custom-runbackup-no-completion")
      XCTFail("ImageIntact > Run Backup did not reach a completion sheet")
    }
  }
}
