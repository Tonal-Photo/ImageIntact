//
//  MigrationUITests.swift
//  ImageIntactUITests
//
//  P0: the migration-confirmation sheet, end to end. With organization
//  enabled, files sitting at the destination ROOT that match the source by
//  checksum trigger an offer to move them into the organization folder —
//  a decision about user data (move, not copy), so every path is covered.
//
//  Fixtures: prefill=loose places byte-identical copies of the source files
//  at the destination root with no organization folder, which is exactly the
//  state BackupMigrationDetector.checkForMigrationNeeded looks for.
//

import XCTest

final class MigrationUITests: ImageIntactUITestCase {

  /// Launches with a migration-triggering destination and clicks Run Backup.
  /// Returns once the migration sheet's marker leaf is visible.
  @discardableResult
  private func launchToMigrationSheet() -> (XCUIApplication, MigrationSheet) {
    let a = launchApp(fixtures: "src=6,dests=1,prefill=loose", organization: "UITestOrg")
    let main = MainScreen(app: a)

    if !main.folderRow("source").waitForExistence(timeout: 10) {
      dumpElementTree(a, label: "migration-no-source-row")
      XCTFail("seam-selected source folder is not shown in the UI; element tree dumped")
    }
    XCTAssertTrue(waitUntilHittable(main.runBackupButton), "Run Backup never became clickable")
    main.runBackupButton.click()

    let migration = MigrationSheet(app: a)
    if !migration.marker.waitForExistence(timeout: 30) {
      dumpElementTree(a, label: "migration-no-sheet")
      XCTFail("migration sheet marker never appeared; element tree dumped")
    }
    return (a, migration)
  }

  func testMigrationSheet_AppearsWithLooseRootFiles_OfferingAllChoices() throws {
    let (_, migration) = launchToMigrationSheet()

    let info = pollValue(of: migration.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(info.contains("files=6"), "expected 6 migratable files in marker: \(info)")

    XCTAssertTrue(migration.button("Organize Files").exists, "Organize Files button missing")
    XCTAssertTrue(migration.button("Skip").exists, "Skip button missing")
    XCTAssertTrue(migration.button("Keep in Root").exists, "Keep in Root button missing")
  }

  func testOrganizeFiles_MigratesThenBackupCompletes() throws {
    let (a, migration) = launchToMigrationSheet()

    migration.button("Organize Files").click()

    // The sheet shows move progress, auto-dismisses ~1.5s after the move
    // finishes, and the backup continues into the (now organized) folder.
    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "migration-organize-no-completion")
      XCTFail("backup did not complete after Organize Files; element tree dumped")
      return
    }
    XCTAssertTrue(
      migration.marker.waitForNonExistence(timeout: 10),
      "migration sheet still present after completion")

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files in stats: \(stats)")
    // All 6 files were just MOVED into the organization folder, so the copy
    // layer finds every destination file already present with a matching
    // checksum — nothing should be re-copied.
    XCTAssertTrue(stats.contains("dest1:"), "expected per-destination stats: \(stats)")
  }

  func testSkipMigration_LeavesFilesInPlaceAndBackupCompletes() throws {
    let (a, migration) = launchToMigrationSheet()

    migration.button("Skip").click()

    // Skip declines the move but the backup itself must still run: files are
    // copied into the organization folder, loose root files stay where they
    // are, and the migration offer must not re-appear for this run.
    let completion = CompletionSheet(app: a)
    if !completion.marker.waitForExistence(timeout: 120) {
      dumpElementTree(a, label: "migration-skip-no-completion")
      XCTFail("backup did not complete after Skip; element tree dumped")
      return
    }

    let stats = pollValue(of: completion.marker, timeout: 10) { !$0.isEmpty }
    XCTAssertTrue(stats.contains("failed=0"), "backup reported failures: \(stats)")
    XCTAssertTrue(stats.contains("inSource=6"), "expected 6 source files in stats: \(stats)")
    XCTAssertTrue(
      stats.contains("dest1:c6/s0/f0"),
      "expected all 6 files copied fresh into the organization folder: \(stats)")
  }
}
