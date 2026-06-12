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
    // layer skips the writes (matching checksums). The copied/skipped split
    // is deliberately NOT pinned: copy-time skips are untallied today
    // (gh#142), so the cN/sN values don't reflect what happened. Tighten to
    // the exact dest1 string when gh#142 lands.
    XCTAssertTrue(stats.contains("dest1:"), "expected per-destination stats: \(stats)")
  }

  func testKeepInRoot_DismissesWithoutRunningBackup() throws {
    let (a, migration) = launchToMigrationSheet()

    migration.button("Keep in Root").click()

    XCTAssertTrue(
      migration.marker.waitForNonExistence(timeout: 10),
      "migration sheet did not dismiss after Keep in Root")

    // Keep in Root only declines the offer — nothing may be copied or
    // moved. 6 tiny fixture files copy in ~2s, so 8s of silence is
    // conclusive.
    let completion = CompletionSheet(app: a)
    XCTAssertFalse(
      completion.marker.waitForExistence(timeout: 8),
      "completion sheet appeared — backup ran despite Keep in Root")

    let main = MainScreen(app: a)
    XCTAssertTrue(
      waitUntilHittable(main.runBackupButton), "Run Backup not clickable after Keep in Root")
    XCTAssertTrue(main.runBackupButton.isEnabled, "Run Backup disabled after Keep in Root")
  }

  func testSkipMigration_LeavesFilesInPlaceAndBackupCompletes() throws {
    let (a, migration) = launchToMigrationSheet()

    migration.button("Skip").click()

    // INTENDED: Skip declines the move but the backup still runs — files are
    // copied into the organization folder, loose root files stay where they
    // are, and the migration offer does not re-appear for this run.
    //
    // ACTUAL (gh#141): continueBackupAfterMigration re-enters the preflight,
    // which re-detects the same loose root files (no decline-memory) and
    // re-presents the dialog forever; the backup never runs. Verified
    // 2026-06-12: the element dump at timeout shows sheet.migration present
    // again. The strict XCTExpectFailure fails this test loudly the day
    // gh#141 is fixed — delete the wrapper then; the intended assertions
    // below take over unchanged.
    XCTExpectFailure("gh#141: Skip re-presents the migration dialog; backup never continues") {
      let completion = CompletionSheet(app: a)
      guard completion.marker.waitForExistence(timeout: 45) else {
        XCTFail("backup did not complete after Skip")
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
}
