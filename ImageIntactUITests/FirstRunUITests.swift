//
//  FirstRunUITests.swift
//  ImageIntactUITests
//
//  P2: welcome sheet gating on first run.
//

import XCTest

final class FirstRunUITests: ImageIntactUITestCase {

  func testFirstRun_ShowsWelcome_AndGetStartedDismissesIt() throws {
    let a = launchApp(fixtures: nil, hasSeenWelcome: false)
    let welcome = WelcomeSheet(app: a)

    // checkFirstRun presents after a deliberate 0.5s delay.
    XCTAssertTrue(
      welcome.title.waitForExistence(timeout: 15),
      "welcome sheet did not appear on first run")

    if !welcome.getStartedButton.waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "welcome-no-get-started")
      XCTFail("Get Started button not found; element tree dumped")
      return
    }

    // The 650pt sheet's bottom row sits in the Dock zone on a 1050pt
    // display, so pointer clicks at the button's coordinates hit the Dock.
    // Get Started is the sheet's default action — dismiss via Return,
    // targeted AT the sheet element (never bare app.typeKey).
    app.sheets.firstMatch.typeKey(.enter, modifierFlags: [])
    XCTAssertTrue(
      welcome.title.waitForNonExistence(timeout: 10),
      "welcome sheet did not dismiss after Get Started")
  }

  func testReturningUser_NoWelcomeSheet() throws {
    let a = launchApp(fixtures: nil, hasSeenWelcome: true)
    let welcome = WelcomeSheet(app: a)
    let main = MainScreen(app: a)

    XCTAssertTrue(main.runBackupButton.waitForExistence(timeout: 10), "main window did not appear")
    // The welcome popup fires 0.5s after appear when it fires at all; give it
    // 3s to prove a negative without dragging the suite.
    Thread.sleep(forTimeInterval: 3)
    XCTAssertFalse(welcome.title.exists, "welcome sheet shown for a returning user")
  }
}
