//
//  OpenPanelBackupUITests.swift
//  ImageIntactUITests
//
//  The production-faithful complement to the seam-based backup tests: select
//  the source and destination through the REAL NSOpenPanel (powerbox), with
//  fixtures generated in the RUNNER's container so the runner can independently
//  byte-verify the copied destination after the backup completes - ground
//  truth instead of trusting the app's own completion stats. AMUX-371.
//
//  Driving patterns ported from Palomino (FolderTests): Go-To-Folder is a sheet
//  ON the panel, and the path is pasted via the pasteboard + Cmd-V (the
//  out-of-process panel drops char-by-char typing) with the clipboard saved and
//  restored. The one departure: ImageIntact opens the picker app-modally, so it
//  surfaces as app.dialogs["open-panel"], not the app.windows["open-panel"] that
//  Palomino's modeless begin{} picker produces.
//

import AppKit
import XCTest

final class OpenPanelBackupUITests: ImageIntactUITestCase {

    func testBackup_ViaOpenPanel_RunnerByteVerifiesDestination() throws {
        // Fixtures live in the RUNNER's container (NSTemporaryDirectory here is
        // the runner's tmp). The sandboxed app cannot read them until the
        // open-panel selection grants access - the real sandbox UX, and the
        // reason the copied bytes end up somewhere the runner can read back.
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("imageintact-uitest-powerbox-\(UUID().uuidString)")
        let sourceDir = root.appendingPathComponent("source")
        let destDir = root.appendingPathComponent("dest1")

        let sourceFiles = try FixtureFactory.generateImages(into: sourceDir, count: 6)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        // Clean up through a teardown block, not defer: with continueAfterFailure
        // false a failed assertion halts the test via an Objective-C exception
        // that bypasses Swift defer, which would leak the fixture tree. Teardown
        // blocks still run. Only ever remove the marked root.
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        // Save and restore the clipboard at the test level (same reason: a defer
        // in the paste helper would be skipped on a mid-helper failure). The UI
        // plan is serial (TestPlans/UI.xctestplan), so there is no parallel-test
        // race on the global pasteboard.
        let savedClipboard = NSPasteboard.general.string(forType: .string)
        addTeardownBlock {
            NSPasteboard.general.clearContents()
            if let savedClipboard { NSPasteboard.general.setString(savedClipboard, forType: .string) }
        }

        let a = launchApp(fixtures: nil, hasSeenWelcome: true)
        let main = MainScreen(app: a)

        // Source: drive the real open panel from the unselected picker row.
        let sourcePicker = main.folderRow("Select Source Folder")
        if !sourcePicker.waitForExistence(timeout: 10) {
            dumpElementTree(a, label: "powerbox-no-source-picker")
            XCTFail("source picker button not shown; element tree dumped")
            return
        }
        selectFolderViaOpenPanel(opening: sourcePicker, to: sourceDir.path)
        // The real setSource path runs an async scan; wait for the row to flip
        // to the selected folder's name before driving the destination.
        XCTAssertTrue(
            main.folderRow("source").waitForExistence(timeout: 30),
            "source folder was not selected via the open panel")

        // Destination: drive the real open panel from the blank Destination 1 row.
        let destPicker = main.folderRow("Destination 1")
        if !destPicker.waitForExistence(timeout: 10) {
            dumpElementTree(a, label: "powerbox-no-dest-picker")
            XCTFail("destination picker button not shown; element tree dumped")
            return
        }
        selectFolderViaOpenPanel(opening: destPicker, to: destDir.path)
        XCTAssertTrue(
            main.folderRow("dest1").waitForExistence(timeout: 30),
            "destination folder was not selected via the open panel")

        // Run the backup through the real button.
        XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
        XCTAssertTrue(
            main.runBackupButton.isEnabled, "Run Backup should be enabled with source + dest set")
        main.runBackupButton.click()

        let completion = CompletionSheet(app: a)
        if !completion.marker.waitForExistence(timeout: 120) {
            dumpElementTree(a, label: "powerbox-no-completion")
            XCTFail("completion sheet never appeared; element tree dumped")
            return
        }
        let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
        XCTAssertFalse(stats.isEmpty, "completion stats accessibility value is empty")
        XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
        XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files in stats: \(stats)")

        // Ground truth: the runner independently recomputes the checksums of the
        // copied files and matches them against the source fixtures. The
        // container-fixture tests cannot do this (the runner cannot read the app
        // container); here both trees live in the runner's container.
        try assertDestinationMatchesSource(sourceFiles: sourceFiles, destRoot: destDir)
    }

    // MARK: - Open-panel driving (Palomino pattern)

    /// Drives the real NSOpenPanel end to end: click the picker to open the
    /// panel, Go-To-Folder (Cmd-Shift-G), paste the path through the pasteboard
    /// (the out-of-process panel drops char-by-char typing), confirm the sheet,
    /// then Open. Saves and restores the clipboard.
    private func selectFolderViaOpenPanel(opening button: XCUIElement, to path: String) {
        // The path is pasted from the pasteboard (the out-of-process panel drops
        // char-by-char typing); the caller saves and restores the clipboard.
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(path, forType: .string)

        button.click()

        // ImageIntact opens the picker app-modally (NSOpenPanel.runModal), so it
        // surfaces as a Dialog carrying the system identifier "open-panel" - not
        // a Window, which is what a modeless begin{} panel (Palomino) would be.
        // Verified against the xcresult UI hierarchy.
        let panel = app.dialogs["open-panel"]
        XCTAssertTrue(panel.waitForExistence(timeout: 15), "open panel did not appear")

        // Go-To-Folder is a sheet ON the panel.
        panel.typeKey("g", modifierFlags: [.command, .shift])
        let gotoSheet = panel.sheets.firstMatch
        XCTAssertTrue(gotoSheet.waitForExistence(timeout: 5), "Go-to-Folder sheet did not appear")
        let field = gotoSheet.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Go-to-Folder field did not appear")
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey("v", modifierFlags: .command)
        // Confirm the Go-To-Folder sheet, which navigates the panel to the path.
        panel.typeKey(.return, modifierFlags: [])
        // The navigation has no observable completion signal; give it a moment to
        // settle so Open selects the navigated folder rather than the prior one.
        Thread.sleep(forTimeInterval: 1)

        // Confirm the panel via the Open button once it is present (waiting for it
        // rather than checking immediately avoids a swallowed Return if the sheet
        // is still animating out). Match on existence, not hittability: modal
        // panel buttons misreport isHittable on macOS.
        let openButton = panel.buttons["Open"]
        if openButton.waitForExistence(timeout: 5) {
            openButton.click()
        } else {
            panel.typeKey(.return, modifierFlags: [])
        }
        _ = panel.waitForNonExistence(timeout: 10)
    }

    // MARK: - Runner-side byte verification

    /// Walks the destination tree, maps every copied JPEG by name to its
    /// SHA-256, and asserts each source fixture appears with byte-identical
    /// content. Matching by content (not a hard-coded path) keeps the assertion
    /// robust to the app's organization-folder layout and any sidecar files it
    /// writes alongside the copies.
    private func assertDestinationMatchesSource(sourceFiles: [URL], destRoot: URL) throws {
        let fm = FileManager.default
        var destByName: [String: String] = [:]
        let keys: [URLResourceKey] = [.isRegularFileKey]
        if let enumerator = fm.enumerator(at: destRoot, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "jpg" {
                destByName[url.lastPathComponent] = try FixtureFactory.sha256(of: url)
            }
        }
        XCTAssertEqual(
            destByName.count, sourceFiles.count,
            "expected \(sourceFiles.count) copied JPEGs in the destination, found \(destByName.count)")
        for src in sourceFiles {
            let name = src.lastPathComponent
            let srcSum = try FixtureFactory.sha256(of: src)
            XCTAssertEqual(
                destByName[name], srcSum,
                "destination copy of \(name) is missing or byte-differs from the source fixture")
        }
    }
}
