//
//  BackupManagerDecisionContinuationTests.swift
//  ImageIntactTests
//
//  gh#141 (AMUX-391): the migration-Skip and duplicate-Continue decision
//  continuations re-enter performQueueBasedBackup, which re-runs the same
//  preflight check with no memory of the decision just made — the sheet
//  re-presents forever and the backup never runs. With duplicate detection
//  enabled, Cancel is the only working exit.
//
//  These tests drive the real preflight: fixtures live under
//  temporaryDirectory/imageintact-uitest/ so the pipeline's security-scope
//  guards accept them via UITestSeam.allowsUnscopedAccess (the same
//  DEBUG-only marker-path escape the UI suite uses). The migration trigger
//  is the real BackupMigrationDetector (not injectable) against
//  byte-identical same-name files at the destination root; the duplicate
//  trigger is MockDuplicateDetector.shouldReturnDuplicates, which reports a
//  duplicate on EVERY pass — exactly the re-check condition that loops
//  today. Only per-run decision memory breaks the loop.
//
//  Design: .planning/design/backup-manager-queue-integration-decision-memory.md
//

import XCTest

@testable import ImageIntact

@MainActor
final class BackupManagerDecisionContinuationTests: BaseBackupManagerTestCase {

  private var fixtureRoot: URL!
  private var sourceDir: URL!
  private var destDir: URL!
  private var prefs: InMemoryPreferencesProvider!
  private var mockDuplicates: MockDuplicateDetector!

  override func setUp() async throws {
    try await super.setUp()

    // <tmp>/imageintact-uitest/<uuid>/{src,dest1} — the marker must be the
    // path itself, parent, or grandparent for the seam to arm, so the unique
    // per-test dir sits directly under the marker.
    fixtureRoot = FileManager.default.temporaryDirectory
      .appendingPathComponent("imageintact-uitest", isDirectory: true)
      .appendingPathComponent("decision-\(UUID().uuidString.prefix(8))", isDirectory: true)
    sourceDir = fixtureRoot.appendingPathComponent("src", isDirectory: true)
    destDir = fixtureRoot.appendingPathComponent("dest1", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

    try Data(repeating: 0xA1, count: 1024).write(to: sourceDir.appendingPathComponent("one.jpg"))
    try Data(repeating: 0xB2, count: 2048).write(to: sourceDir.appendingPathComponent("two.jpg"))

    prefs = InMemoryPreferencesProvider(showNotificationOnComplete: false)
    mockDuplicates = MockDuplicateDetector()
  }

  override func tearDown() async throws {
    // Base tearDown cancels any in-flight backup before bm is released.
    try await super.tearDown()
    if let fixtureRoot {
      try? FileManager.default.removeItem(at: fixtureRoot)
    }
    mockDuplicates = nil
    prefs = nil
    destDir = nil
    sourceDir = nil
    fixtureRoot = nil
  }

  /// Builds the manager under test and points it at the fixture tree.
  /// `setSource` auto-derives organizationName from the path, so the desired
  /// value is applied AFTER it.
  private func makeManager(organization: String) -> BackupManager {
    let manager = BackupManager(
      duplicateDetector: mockDuplicates,
      backupAlertPresenter: MockBackupAlertPresenter(),
      preferences: prefs
    )
    manager.setSource(sourceDir)
    manager.setDestination(destDir, at: 0)
    manager.organizationName = organization
    return manager
  }

  /// Enters the backup the way `runBackup` does — source and destinations
  /// derived from the manager's own stored items, so the continuation's
  /// re-entry (which derives them the same way) produces IDENTICAL URLs.
  /// The orchestrator looks up `duplicateAnalyses[destination]` by URL key;
  /// a test-constructed URL can differ in standardization (/var vs
  /// /private/var) and silently miss that lookup.
  private func startBackup() async throws {
    let source = try XCTUnwrap(bm.sourceURL, "setSource must have stored the source URL")
    let destinations = bm.destinationItems.compactMap { $0.url }
    XCTAssertFalse(destinations.isEmpty, "setDestination must have stored the destination URL")
    await bm.performQueueBasedBackup(source: source, destinations: destinations)
  }

  /// Byte-identical, same-name copies at the destination ROOT with no
  /// organization folder — exactly what BackupMigrationDetector flags.
  private func prefillLooseRootFiles() throws {
    for name in ["one.jpg", "two.jpg"] {
      try FileManager.default.copyItem(
        at: sourceDir.appendingPathComponent(name),
        to: destDir.appendingPathComponent(name)
      )
    }
  }

  // MARK: - Migration Skip

  /// INTENDED: declining the move proceeds with the backup — files are copied
  /// into the organization folder, the offer does not re-appear for this run.
  /// ACTUAL (gh#141): the continuation re-enters the preflight, which
  /// re-detects the same loose root files and re-arms the dialog forever.
  func testSkipMigration_DoesNotRepresentDialog_AndBackupProceeds() async throws {
    try prefillLooseRootFiles()
    bm = makeManager(organization: "TestOrg")

    try await startBackup()

    // Sanity: a fresh run must arm the migration offer.
    XCTAssertTrue(bm.showMigrationDialog, "fresh run must detect loose root files and offer migration")
    XCTAssertFalse(bm.state.pendingMigrationPlans.isEmpty, "a migration plan must be pending")
    XCTAssertFalse(bm.state.isProcessing, "run must pause while waiting for the decision")

    await bm.continueBackupAfterMigration()

    XCTAssertFalse(
      bm.showMigrationDialog,
      "gh#141: the migration offer must NOT re-present after the user declined it")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destDir.appendingPathComponent("TestOrg/one.jpg").path),
      "backup must proceed after Skip — files copied into the organization folder")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destDir.appendingPathComponent("TestOrg/two.jpg").path),
      "backup must proceed after Skip — files copied into the organization folder")
    XCTAssertTrue(
      FileManager.default.fileExists(atPath: destDir.appendingPathComponent("one.jpg").path),
      "Skip leaves loose root files in place (declined the move)")
  }

  // MARK: - Duplicate Continue

  /// INTENDED: an explicit proceed decision runs the backup honoring the skip
  /// flags, with no re-analysis and no re-presented warning.
  /// ACTUAL (gh#141): the continuation re-enters the preflight, which re-runs
  /// the duplicate analysis (the mock reports duplicates every time, as the
  /// real Core-Data-backed detector does) and re-arms the warning forever.
  ///
  /// The mock analysis pins one.jpg's REAL checksum (the orchestrator filters
  /// per-destination manifests by checksum — `shouldReturnDuplicates`
  /// hard-codes "abc123", which matches nothing and filters nothing), so the
  /// post-decision copy result proves the selection was honored end to end.
  func testContinueAfterDuplicateDecision_DoesNotReanalyzeOrRepresentDialog() async throws {
    prefs.enableSmartDuplicateDetection = true
    let duplicateURL = sourceDir.appendingPathComponent("one.jpg")
    let duplicateChecksum = try ChecksumService.sha256(for: duplicateURL, shouldCancel: { false })
    mockDuplicates.mockAnalysis = DuplicateDetector.DuplicateAnalysis(
      totalSourceFiles: 2,
      exactDuplicates: [
        DuplicateDetector.DuplicateFile(
          sourceFile: FileManifestEntry(
            relativePath: "one.jpg",
            sourceURL: duplicateURL,
            checksum: duplicateChecksum,
            size: 1024
          ),
          destinationPath: destDir.appendingPathComponent("one.jpg").path,
          checksum: duplicateChecksum,
          isDifferentName: false,
          existingOrganization: nil
        )
      ],
      renamedDuplicates: [],
      uniqueFiles: 1,
      potentialSpaceSaved: 1024,
      destinationDriveUUID: nil
    )
    bm = makeManager(organization: "")  // no organization → migration check never arms

    try await startBackup()

    // Sanity: a fresh run must arm the duplicate warning.
    XCTAssertTrue(bm.showDuplicateWarning, "fresh run must surface the duplicate warning")
    XCTAssertNotNil(bm.state.duplicateAnalyses, "analyses must be retained for the decision")
    XCTAssertEqual(mockDuplicates.analyzeCallCount, 1, "one analysis per destination on the fresh run")
    XCTAssertFalse(bm.state.isProcessing, "run must pause while waiting for the decision")

    await bm.continueBackupAfterDuplicateDecision(skipExact: true, skipRenamed: false)

    XCTAssertFalse(
      bm.showDuplicateWarning,
      "gh#141: the duplicate warning must NOT re-present after an explicit proceed decision")
    XCTAssertEqual(
      mockDuplicates.analyzeCallCount, 1,
      "gh#141: the continuation must not re-run the duplicate analysis — the decision was made on the first pass")
    XCTAssertFalse(bm.state.isProcessing, "backup must have run to completion")
    // skipExact filters the flagged duplicate (one.jpg); the other file must
    // actually land at the destination root (no organization).
    let copied = try FileManager.default.contentsOfDirectory(atPath: destDir.path)
      .filter { $0.hasSuffix(".jpg") }
    XCTAssertEqual(
      copied, ["two.jpg"],
      "backup must proceed honoring the selection: one.jpg skipped, two.jpg copied")
  }

  // MARK: - Migration → Duplicate chain

  /// Decision memory is per-dialog, not global: skipping the migration offer
  /// must still surface the not-yet-seen duplicate warning, and the duplicate
  /// decision must then run the backup without re-presenting EITHER dialog.
  func testMigrationSkipThenDuplicateDecision_ChainPresentsEachDialogOnce() async throws {
    try prefillLooseRootFiles()
    prefs.enableSmartDuplicateDetection = true
    mockDuplicates.shouldReturnDuplicates = true
    bm = makeManager(organization: "TestOrg")

    try await startBackup()

    // Migration is checked first; the run pauses before duplicate analysis.
    XCTAssertTrue(bm.showMigrationDialog, "fresh run must offer migration first")
    XCTAssertFalse(bm.showDuplicateWarning, "duplicate analysis must not have run yet")
    XCTAssertEqual(mockDuplicates.analyzeCallCount, 0)

    await bm.continueBackupAfterMigration()

    XCTAssertFalse(
      bm.showMigrationDialog,
      "gh#141: the declined migration offer must not re-present")
    XCTAssertTrue(
      bm.showDuplicateWarning,
      "the duplicate warning has not been decided yet — the migration decision must not suppress it")
    XCTAssertEqual(mockDuplicates.analyzeCallCount, 1)

    await bm.continueBackupAfterDuplicateDecision(skipExact: false, skipRenamed: false)

    XCTAssertFalse(bm.showMigrationDialog, "no dialog may re-present after both decisions")
    XCTAssertFalse(bm.showDuplicateWarning, "no dialog may re-present after both decisions")
    XCTAssertEqual(mockDuplicates.analyzeCallCount, 1, "Copy All Anyway must not re-analyze")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destDir.appendingPathComponent("TestOrg/one.jpg").path),
      "backup must run to completion after the chain of decisions")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath: destDir.appendingPathComponent("TestOrg/two.jpg").path),
      "backup must run to completion after the chain of decisions")
  }
}
