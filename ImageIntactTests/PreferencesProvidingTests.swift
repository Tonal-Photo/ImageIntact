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

    /// buildPreflightSummary must read excludeCacheFiles + skipHiddenFiles from
    /// the injected provider. We observe the preflight summary the mock
    /// presenter receives and verify the fields match what we set on `prefs`.
    func testBackupManager_runBackup_preflight_readsExcludeCacheAndSkipHiddenFromInjectedPreferences() {
        let prefs = InMemoryPreferencesProvider(
            showPreflightSummary: true,
            excludeCacheFiles: false,
            skipHiddenFiles: false
        )
        let mockDisk = MockDiskSpaceChecker()
        mockDisk.evaluationResult = (canProceed: true, warnings: [], errors: [])
        let mockPresenter = MockBackupAlertPresenter()
        // Cancel at preflight so the backup doesn't try to actually run.
        mockPresenter.preflightReturnValue = (proceed: false, showAgain: true)

        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            diskSpaceChecker: mockDisk,
            backupAlertPresenter: mockPresenter,
            preferences: prefs
        )

        bm.sourceManager.sourceURL = URL(fileURLWithPath: "/Volumes/CardA/DCIM")
        bm.setDestination(URL(fileURLWithPath: "/Volumes/BackupDrive"), at: 0)

        bm.runBackup()

        XCTAssertEqual(mockPresenter.presentPreflightCalls.count, 1,
                       "Preflight summary must be presented when showPreflightSummary=true")
        let summary = mockPresenter.presentPreflightCalls.first
        XCTAssertEqual(summary?.excludeCacheFiles, false,
                       "buildPreflightSummary must read excludeCacheFiles from preferences (set false on the injected provider)")
        XCTAssertEqual(summary?.skipHiddenFiles, false,
                       "buildPreflightSummary must read skipHiddenFiles from preferences (set false on the injected provider)")
    }

    /// runBackup with `restoreLastSession=false` must NOT call
    /// destinationManager.loadFromSession at init. We can't easily mock the
    /// destinationManager, but we can verify the observable result: with no
    /// bookmark keys set and restoreLastSession=false, init takes the
    /// `initializeEmpty()` branch and ends up with exactly one empty slot.
    /// With restoreLastSession=true and no bookmarks, init takes
    /// loadFromSession() — which also ends up with zero/empty items because
    /// there's nothing to load. Both branches converge to "no real
    /// destinations". The test asserts the convergent outcome, which is the
    /// only externally observable shape without a destinationManager mock.
    func testBackupManager_init_restoreLastSession_false_initializesEmpty() {
        // Clear any bookmark state from prior sessions (defensive — the test
        // base classes also do this, but PreferencesProvidingTests is a
        // plain XCTestCase).
        UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        for key in BookmarkManager.destinationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        let prefs = InMemoryPreferencesProvider(restoreLastSession: false)

        let bm = BackupManager(
            fileOperations: MockFileOperations(),
            preferences: prefs
        )

        // initializeEmpty() seeds exactly one empty DestinationItem.
        // If init had wrongly hardcoded `PreferencesManager.shared.restoreLastSession`,
        // it might still load from session — but with bookmarks cleared, the
        // observable result is identical. The strongest signal we can get
        // without a destinationManager mock is that the resulting state is
        // the "no destinations" shape.
        XCTAssertEqual(bm.destinationItems.count, 1,
                       "restoreLastSession=false must take the initializeEmpty branch with one empty slot")
        XCTAssertNil(bm.destinationItems.first?.url,
                     "initializeEmpty slot must have nil URL")
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
