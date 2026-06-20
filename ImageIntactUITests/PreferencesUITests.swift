//
//  PreferencesUITests.swift
//  ImageIntactUITests
//
//  Drives the Preferences sheet through the UI: opens from both entry points
//  (Cmd-, and the app menu), renders each of the four tabs, flips a
//  representative ENABLED+PERSISTED toggle per tab, and verifies persistence
//  across a relaunch that does NOT reset the defaults domain.
//  See .planning/design/ui-test-preferences.md.
//

import XCTest

final class PreferencesUITests: ImageIntactUITestCase {

  /// Representative ENABLED + PERSISTED toggle per tab. Verified against
  /// PreferencesView.swift; `enableConsoleLogging` (not "Verbose Logging",
  /// which is DebugSettings and resets on quit). Queried by the Toggle title
  /// first; a11y identifiers are added in green only where the red dump shows
  /// the title is ambiguous.
  private struct TabToggle {
    let tab: String
    let toggle: String
  }
  private let repToggles: [TabToggle] = [
    TabToggle(tab: "General", toggle: "Skip hidden files"),
    TabToggle(tab: "Performance", toggle: "Prevent sleep during backup"),
    TabToggle(tab: "Logging & Privacy", toggle: "Log to Console.app"),
    TabToggle(tab: "Advanced", toggle: "Show technical details during backup"),
  ]

  // MARK: - Element helpers

  private func closeButton(_ a: XCUIApplication) -> XCUIElement {
    a.sheets.buttons["Close"].firstMatch
  }

  /// Open Preferences via the standard ⌘, shortcut (posts ShowPreferences).
  private func openPrefsViaShortcut(_ a: XCUIApplication) {
    a.typeKey(",", modifierFlags: .command)
  }

  /// True if a checkBox/switch is on, tolerant of Int/String/Bool value shapes.
  private func isOn(_ el: XCUIElement) -> Bool {
    if let i = el.value as? Int { return i != 0 }
    if let b = el.value as? Bool { return b }
    if let s = el.value as? String { return s == "1" || s.lowercased() == "true" }
    return false
  }

  /// Select a Preferences tab. macOS SwiftUI TabView tab items surface
  /// unpredictably (button vs radioButton vs tabGroup child); try the likely
  /// shapes. The red dump confirms which; green narrows this.
  @discardableResult
  private func selectTab(_ a: XCUIApplication, _ name: String) -> Bool {
    let candidates = [
      a.sheets.radioButtons[name], a.sheets.buttons[name],
      a.radioButtons[name], a.buttons[name], a.tabGroups.buttons[name],
    ]
    for el in candidates where el.waitForExistence(timeout: 1) {
      if el.isHittable { el.click(); return true }
    }
    return false
  }

  private func toggle(_ a: XCUIApplication, _ title: String) -> XCUIElement {
    a.checkBoxes[title].firstMatch
  }

  // MARK: - Open from both entry points

  func testPreferencesOpensFromKeyboardShortcut() throws {
    let a = launchApp(fixtures: nil)
    openPrefsViaShortcut(a)
    if !closeButton(a).waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "prefs-shortcut-no-close")
      XCTFail("Preferences sheet (Close button) did not appear after ⌘,; tree dumped")
      return
    }
    // Explore: one dump of the open sheet maps tabs + toggle surfacing.
    dumpElementTree(a, label: "prefs-open-general")
    closeButton(a).click()
    XCTAssertTrue(
      closeButton(a).waitForNonExistence(timeout: 10), "Preferences sheet did not dismiss")
  }

  func testPreferencesOpensFromAppMenu() throws {
    let a = launchApp(fixtures: nil)
    // The bold application menu is the menu-bar item right after the Apple menu.
    let appMenu = a.menuBars.menuBarItems.element(boundBy: 1)
    if !appMenu.waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "appmenu-missing")
      XCTFail("application menu bar item not found; tree dumped")
      return
    }
    appMenu.click()
    // Trailing "..." may render as the ellipsis glyph; match by prefix.
    let prefsItem = a.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Preferences"))
      .firstMatch
    if !prefsItem.waitForExistence(timeout: 5) {
      dumpElementTree(a, label: "appmenu-no-prefs-item")
      XCTFail("'Preferences…' item not found in the app menu; tree dumped")
      return
    }
    prefsItem.click()
    XCTAssertTrue(
      closeButton(a).waitForExistence(timeout: 10),
      "Preferences sheet did not open from the app menu")
    closeButton(a).click()
  }

  // MARK: - Each tab renders + representative toggle flips

  func testEachTabRendersAndRepresentativeToggleFlips() throws {
    let a = launchApp(fixtures: nil)
    openPrefsViaShortcut(a)
    XCTAssertTrue(closeButton(a).waitForExistence(timeout: 10), "Preferences did not open")

    for rt in repToggles {
      if !selectTab(a, rt.tab) {
        dumpElementTree(a, label: "tab-select-\(rt.tab.replacingOccurrences(of: " ", with: "_"))")
        XCTFail("could not select Preferences tab '\(rt.tab)'; tree dumped")
        return
      }
      let cb = toggle(a, rt.toggle)
      if !cb.waitForExistence(timeout: 5) {
        dumpElementTree(a, label: "toggle-\(rt.toggle.replacingOccurrences(of: " ", with: "_"))")
        XCTFail("toggle '\(rt.toggle)' not found on tab '\(rt.tab)'; tree dumped")
        return
      }
      let before = isOn(cb)
      cb.click()
      let deadline = Date().addingTimeInterval(5)
      while Date() < deadline, isOn(cb) == before { Thread.sleep(forTimeInterval: 0.1) }
      XCTAssertNotEqual(isOn(cb), before, "toggle '\(rt.toggle)' on '\(rt.tab)' did not flip")
    }
    closeButton(a).click()
  }

  // MARK: - Persistence across relaunch (without reset)

  func testRepresentativeTogglesPersistAcrossRelaunch() throws {
    let a = launchApp(fixtures: nil)
    openPrefsViaShortcut(a)
    XCTAssertTrue(closeButton(a).waitForExistence(timeout: 10), "Preferences did not open")

    var expected: [String: Bool] = [:]
    for rt in repToggles {
      XCTAssertTrue(selectTab(a, rt.tab), "could not select tab '\(rt.tab)'")
      let cb = toggle(a, rt.toggle)
      XCTAssertTrue(cb.waitForExistence(timeout: 5), "toggle '\(rt.toggle)' not found")
      let before = isOn(cb)
      cb.click()
      let deadline = Date().addingTimeInterval(5)
      while Date() < deadline, isOn(cb) == before { Thread.sleep(forTimeInterval: 0.1) }
      expected[rt.toggle] = !before
    }
    closeButton(a).click()
    // Let @AppStorage flush, then terminate cleanly so the write persists.
    Thread.sleep(forTimeInterval: 1.0)
    a.terminate()
    _ = a.wait(for: .notRunning, timeout: 10)

    // Relaunch WITHOUT --uitest-reset: the persisted (application-domain)
    // toggle values must survive. -hasSeenWelcome via the ARGUMENT domain keeps
    // the welcome sheet out of the way without masking the persisted toggles.
    let b = XCUIApplication()
    b.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "--uitest", "-hasSeenWelcome", "YES"]
    b.launchEnvironment["TZ"] = "UTC"
    b.launch()
    app = b  // tearDown terminates `app`

    b.typeKey(",", modifierFlags: .command)
    if !closeButton(b).waitForExistence(timeout: 10) {
      dumpElementTree(b, label: "prefs-reopen-after-relaunch")
      XCTFail("Preferences did not reopen after relaunch; tree dumped")
      return
    }
    for rt in repToggles {
      XCTAssertTrue(selectTab(b, rt.tab), "could not reselect tab '\(rt.tab)'")
      let cb = toggle(b, rt.toggle)
      XCTAssertTrue(cb.waitForExistence(timeout: 5), "toggle '\(rt.toggle)' missing after relaunch")
      XCTAssertEqual(
        isOn(cb), expected[rt.toggle],
        "toggle '\(rt.toggle)' did not persist across relaunch")
    }
    closeButton(b).click()
  }
}
