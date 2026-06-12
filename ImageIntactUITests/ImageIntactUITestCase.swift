//
//  ImageIntactUITestCase.swift
//  ImageIntactUITests
//
//  Base class for the ImageIntact UI suite. Encodes the macOS XCUITest
//  gotchas learned on the Palomino suite — see .planning/design/ui-test-suite.md.
//

import XCTest

class ImageIntactUITestCase: XCTestCase {
  var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    addUIInterruptionMonitor(withDescription: "system dialog") { alert in
      for label in ["OK", "Allow", "Close", "Cancel"] where alert.buttons[label].exists {
        alert.buttons[label].click()
        return true
      }
      return false
    }
  }

  override func tearDownWithError() throws {
    if let app, app.state != .notRunning { app.terminate() }
    Thread.sleep(forTimeInterval: 0.5)
  }

  /// Launches the app hermetically: state reset happens in-app at init
  /// (--uitest-reset wipes the persisted defaults domain + fixture tree),
  /// then fixtures are generated per `fixtures`, all before the first frame.
  ///
  /// - Parameters:
  ///   - fixtures: `--testAutoFixtures` spec (e.g. "src=6,dests=2,prefill=exact"),
  ///     or nil for no fixtures (empty source/destination state).
  ///   - hasSeenWelcome: injected via the UserDefaults ARGUMENT domain, which
  ///     overrides the (just-wiped) persisted value without writing anything.
  ///   - organization: passed as --testOrganization when non-nil.
  @discardableResult
  func launchApp(
    fixtures: String? = nil,
    hasSeenWelcome: Bool = true,
    organization: String? = nil,
    extraArgs: [String] = [],
    extraEnv: [String: String] = [:]
  ) -> XCUIApplication {
    let a = XCUIApplication()
    // A session that ends with zero windows is otherwise "restored" as zero
    // windows on every later launch with no default-window fallback — one bad
    // launch poisons the rest of the suite. Ignore persisted UI state.
    a.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
    a.launchArguments += ["--uitest", "--uitest-reset"]
    if let fixtures {
      a.launchArguments += ["--testAutoFixtures", fixtures]
    }
    a.launchArguments += ["-hasSeenWelcome", hasSeenWelcome ? "YES" : "NO"]
    if let organization {
      a.launchArguments += ["--testOrganization", organization]
    }
    a.launchArguments += extraArgs
    a.launchEnvironment["TZ"] = "UTC"
    extraEnv.forEach { a.launchEnvironment[$0.key] = $0.value }
    a.launch()
    app = a
    return a
  }

  // MARK: - Polling helpers
  //
  // XCTNSPredicateExpectation on element values hits a stale-snapshot bug
  // (never sees updates) — poll live reads in a deadline loop instead.

  @discardableResult
  func pollValue(
    of element: XCUIElement,
    timeout: TimeInterval,
    until predicate: (String) -> Bool
  ) -> String {
    let deadline = Date().addingTimeInterval(timeout)
    var last = ""
    while Date() < deadline {
      if element.exists {
        last = (element.value as? String) ?? ""
        if predicate(last) { return last }
      }
      Thread.sleep(forTimeInterval: 0.15)
    }
    return last
  }

  func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if element.exists && element.isHittable { return true }
      Thread.sleep(forTimeInterval: 0.15)
    }
    return false
  }

  /// Ground truth when an element can't be found: dump the full element tree
  /// to the runner's tmp (readable on the host at
  /// ~/Library/Containers/<bundle>.xctrunner/Data/tmp/).
  func dumpElementTree(_ a: XCUIApplication, label: String) {
    let path = (NSTemporaryDirectory() as NSString)
      .appendingPathComponent("imageintact-uitests-\(label)-dump.txt")
    try? a.debugDescription.write(toFile: path, atomically: true, encoding: .utf8)
  }
}
