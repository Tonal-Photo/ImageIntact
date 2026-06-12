//
//  Screens.swift
//  ImageIntactUITests
//
//  Screen objects. Element-type reality on macOS SwiftUI: .sheet AND .alert
//  both surface as app.sheets; values land on leaf StaticTexts; alert buttons
//  must be scoped to the sheet element (bare app.buttons can resolve to the
//  Touch Bar copy, which cannot be clicked).
//

import XCTest

struct MainScreen {
  let app: XCUIApplication

  /// The Run Backup button carries accessibilityLabel "Start backup process",
  /// which replaces its title in the accessibility tree.
  var runBackupButton: XCUIElement {
    let byLabel = app.buttons["Start backup process"]
    return byLabel.exists ? byLabel : app.buttons["Run Backup"]
  }

  var clearAllButton: XCUIElement {
    let byLabel = app.buttons["Clear all selected folders"]
    return byLabel.exists ? byLabel : app.buttons["Clear All"]
  }

  /// A selected folder surfaces as the FolderRow button's label (the Text
  /// lives INSIDE the button, so it is not a standalone staticText).
  func folderRow(_ name: String) -> XCUIElement {
    app.windows.buttons[name].firstMatch
  }
}

struct CompletionSheet {
  let app: XCUIApplication

  /// Leaf Text "Backup Complete" carrying the machine-readable stats value:
  /// processed=N;skipped=N;failed=N;inSource=N;dests=dest1:cN/sN/fN,...
  var marker: XCUIElement { app.staticTexts["sheet.completion"].firstMatch }

  var stats: String { (marker.value as? String) ?? "" }

  var closeButton: XCUIElement { app.sheets.buttons["Close"].firstMatch }
}

struct WelcomeSheet {
  let app: XCUIApplication

  var title: XCUIElement { app.staticTexts["Welcome to ImageIntact"].firstMatch }
  var getStartedButton: XCUIElement {
    let scoped = app.sheets.buttons["Get Started"]
    return scoped.exists ? scoped.firstMatch : app.buttons["Get Started"].firstMatch
  }
}

struct MigrationSheet {
  let app: XCUIApplication

  /// Leaf Text "Organize Existing Backup?" carrying the machine-readable
  /// plan summary: files=N;dest=<name>
  var marker: XCUIElement { app.staticTexts["sheet.migration"].firstMatch }

  var sheet: XCUIElement { app.sheets.firstMatch }
  func button(_ label: String) -> XCUIElement { app.sheets.buttons[label].firstMatch }
}

struct DuplicateSheet {
  let app: XCUIApplication

  /// Leaf Text "Duplicate Files Detected" carrying the machine-readable
  /// analysis summary: exact=N;renamed=N
  var marker: XCUIElement { app.staticTexts["sheet.duplicate"].firstMatch }

  func button(_ label: String) -> XCUIElement { app.sheets.buttons[label].firstMatch }
}
