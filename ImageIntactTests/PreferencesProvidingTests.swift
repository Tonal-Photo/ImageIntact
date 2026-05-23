//
//  PreferencesProvidingTests.swift
//  ImageIntactTests
//
//  TDD red-phase tests for the PreferencesProviding protocol (AMUX-205).
//
//  These tests reference `PreferencesProviding` (not yet defined),
//  `InMemoryPreferencesProvider` (not yet defined), and the new
//  `BackupManager(preferences:)` init parameter (not yet added) — compile
//  failure here IS the red-phase signal.
//
//  Goal: BackupManager reads/writes its preferences through an injected
//  `PreferencesProviding`, never reaching into `UserDefaults.standard`. That
//  lets tests use a per-instance in-memory provider, eliminates shared-state
//  bleed across tests, and removes the bookmark capture/restore boilerplate
//  in BaseBackupManagerTestCase.
//

import XCTest
@testable import ImageIntact

@MainActor
final class PreferencesProvidingTests: XCTestCase {

    // MARK: - Protocol contract — read/write surface

    /// The in-memory provider holds and returns whatever was written to each
    /// settable property — no UserDefaults round-trip.
    func testInMemoryProvider_readWriteRoundTrip() {
        let prefs = InMemoryPreferencesProvider()

        prefs.showPreflightSummary = true
        XCTAssertTrue(prefs.showPreflightSummary)

        prefs.lastUsedOrganizationFolderName = "MyShoot"
        XCTAssertEqual(prefs.lastUsedOrganizationFolderName, "MyShoot")

        prefs.skipLargeBackupWarning = true
        XCTAssertTrue(prefs.skipLargeBackupWarning)
    }

    /// Constructor defaults match the production PreferencesManager defaults,
    /// so tests that don't override get realistic behavior.
    func testInMemoryProvider_defaultsMatchProductionDefaults() {
        let prefs = InMemoryPreferencesProvider()

        XCTAssertFalse(prefs.enableSmartDuplicateDetection)
        XCTAssertNil(prefs.lastUsedOrganizationFolderName)
        XCTAssertTrue(prefs.restoreLastSession)
        XCTAssertFalse(prefs.showPreflightSummary)
        XCTAssertTrue(prefs.excludeCacheFiles)
        XCTAssertTrue(prefs.skipHiddenFiles)
        XCTAssertTrue(prefs.showNotificationOnComplete)
        XCTAssertFalse(prefs.trashSourceAfterBackup)
        XCTAssertEqual(prefs.largeBackupFileThreshold, 1000)
        XCTAssertEqual(prefs.largeBackupSizeThresholdGB, 10.0)
        XCTAssertTrue(prefs.confirmLargeBackups)
        XCTAssertFalse(prefs.skipLargeBackupWarning)
    }

    /// `addRecentOrganizationFolderName` matches PreferencesManager semantics:
    /// most-recent first, no duplicates, capped at 10.
    func testInMemoryProvider_addRecentOrganizationFolderName_recentFirstNoDupes() {
        let prefs = InMemoryPreferencesProvider()

        prefs.addRecentOrganizationFolderName("Alpha")
        prefs.addRecentOrganizationFolderName("Beta")
        prefs.addRecentOrganizationFolderName("Alpha") // duplicate -> moves to top

        XCTAssertEqual(prefs.recentOrganizationFolderNames, ["Alpha", "Beta"])
    }

    /// Empty / whitespace-only names are ignored — matches PreferencesManager.
    func testInMemoryProvider_addRecentOrganizationFolderName_ignoresEmpty() {
        let prefs = InMemoryPreferencesProvider()

        prefs.addRecentOrganizationFolderName("")
        prefs.addRecentOrganizationFolderName("   ")

        XCTAssertTrue(prefs.recentOrganizationFolderNames.isEmpty)
    }

    // MARK: - BackupManager DI — uses injected preferences

    /// BackupManager(preferences:) reads `lastUsedOrganizationFolderName` from
    /// the injected provider at init time, not from PreferencesManager.shared.
    /// Red-phase signal: this init signature doesn't exist yet.
    func testBackupManager_init_readsLastUsedNameFromInjectedPreferences() {
        let prefs = InMemoryPreferencesProvider(lastUsedOrganizationFolderName: "InjectedShoot")

        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            preferences: prefs
        )

        // The expected value is sanitized in BackupManager.init via SmartFolderName.sanitize.
        // "InjectedShoot" has no special chars so it stays unchanged.
        XCTAssertEqual(bm.organizationName, "InjectedShoot")
    }

    /// BackupManager.enableDuplicateDetection forwards to the injected
    /// provider, not PreferencesManager.shared.
    func testBackupManager_enableDuplicateDetection_readsFromInjectedPreferences() {
        let prefs = InMemoryPreferencesProvider(enableSmartDuplicateDetection: true)

        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            preferences: prefs
        )

        XCTAssertTrue(bm.enableDuplicateDetection)

        prefs.enableSmartDuplicateDetection = false
        XCTAssertFalse(bm.enableDuplicateDetection,
                       "BackupManager must read live state from the injected provider")
    }

    /// PreferencesManager.shared conforms to PreferencesProviding so production
    /// code keeps working with the default init argument.
    func testPreferencesManagerShared_conformsToPreferencesProviding() {
        let prefs: PreferencesProviding = PreferencesManager.shared
        // Touch one property to force the existential to resolve at runtime.
        // Reading is harmless and doesn't mutate UserDefaults.
        _ = prefs.confirmLargeBackups
    }

    // MARK: - BackupManager DI — writes back through injected preferences

    /// `respondToLargeBackupConfirmation(dontShowAgain: true)` must write
    /// `skipLargeBackupWarning = true` to the injected provider, not to
    /// `PreferencesManager.shared`.
    func testBackupManager_respondToLargeBackup_dontShowAgain_writesToInjectedPreferences() {
        let prefs = InMemoryPreferencesProvider(skipLargeBackupWarning: false)
        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            preferences: prefs
        )

        bm.respondToLargeBackupConfirmation(shouldContinue: false, dontShowAgain: true)

        XCTAssertTrue(prefs.skipLargeBackupWarning,
                      "respondToLargeBackupConfirmation must persist dontShowAgain through preferences.skipLargeBackupWarning")
    }

    /// `respondToLargeBackupConfirmation(dontShowAgain: false)` must NOT
    /// touch `skipLargeBackupWarning`.
    func testBackupManager_respondToLargeBackup_dontShowAgainFalse_leavesSkipWarning() {
        let prefs = InMemoryPreferencesProvider(skipLargeBackupWarning: false)
        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            preferences: prefs
        )

        bm.respondToLargeBackupConfirmation(shouldContinue: true, dontShowAgain: false)

        XCTAssertFalse(prefs.skipLargeBackupWarning,
                       "respondToLargeBackupConfirmation must leave skipLargeBackupWarning unchanged when dontShowAgain=false")
    }

    /// runBackup must record the organizationName via the injected provider's
    /// `lastUsedOrganizationFolderName` and `addRecentOrganizationFolderName`.
    /// We can't drive runBackup to completion from a unit test (it spawns the
    /// async backup pipeline), but the persist-name block runs synchronously
    /// before that point, so a runBackup() call is enough to observe the writes.
    func testBackupManager_runBackup_recordsOrganizationNameInPreferences() {
        let prefs = InMemoryPreferencesProvider()
        let mockDisk = MockDiskSpaceChecker()
        mockDisk.evaluationResult = (canProceed: true, warnings: [], errors: [])
        let mockPresenter = MockBackupAlertPresenter()

        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            diskSpaceChecker: mockDisk,
            backupAlertPresenter: mockPresenter,
            preferences: prefs
        )

        // Set a source + destination so runBackup can reach the persist-name block.
        bm.sourceManager.sourceURL = URL(fileURLWithPath: "/Volumes/CardA/DCIM")
        bm.setDestination(URL(fileURLWithPath: "/Volumes/BackupDrive"), at: 0)
        bm.organizationName = "MyShoot"

        bm.runBackup()

        XCTAssertEqual(prefs.lastUsedOrganizationFolderName, "MyShoot",
                       "runBackup must persist organizationName via preferences.lastUsedOrganizationFolderName")
        XCTAssertEqual(prefs.recentOrganizationFolderNames.first, "MyShoot",
                       "runBackup must record organizationName via preferences.addRecentOrganizationFolderName")
    }

    /// runBackup with empty organizationName must NOT touch the recent list or
    /// `lastUsedOrganizationFolderName`.
    func testBackupManager_runBackup_emptyOrganizationName_leavesRecentEmpty() {
        let prefs = InMemoryPreferencesProvider(lastUsedOrganizationFolderName: "PriorValue")
        let mockDisk = MockDiskSpaceChecker()
        mockDisk.evaluationResult = (canProceed: true, warnings: [], errors: [])

        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            diskSpaceChecker: mockDisk,
            backupAlertPresenter: MockBackupAlertPresenter(),
            preferences: prefs
        )

        bm.sourceManager.sourceURL = URL(fileURLWithPath: "/Volumes/CardA/DCIM")
        bm.setDestination(URL(fileURLWithPath: "/Volumes/BackupDrive"), at: 0)
        bm.organizationName = ""

        bm.runBackup()

        XCTAssertEqual(prefs.lastUsedOrganizationFolderName, "PriorValue",
                       "runBackup with empty organizationName must not overwrite lastUsedOrganizationFolderName")
        XCTAssertTrue(prefs.recentOrganizationFolderNames.isEmpty,
                      "runBackup with empty organizationName must not call addRecentOrganizationFolderName")
    }
}
