//
//  PreferencesObservationTests.swift
//  ImageIntactTests
//
//  Tests that prove the View-redraw path works — the exact class of bug that escaped
//  PreferencesTests.swift before the @Observable refactor (those tests only verified
//  UserDefaults storage, never that @AppStorage-in-class fired observation).
//

import XCTest
import Observation
@testable import ImageIntact

final class PreferencesObservationTests: XCTestCase {

    /// Suites created in this test case. `tearDown` removes them all.
    private var createdSuiteNames: [String] = []

    override func tearDown() {
        for name in createdSuiteNames {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        createdSuiteNames.removeAll()
        PreferencesManager._isAppleSiliconOverride = nil
        super.tearDown()
    }

    /// Spin up an isolated UserDefaults suite. Teardown is centralized.
    private func makePrefs() -> PreferencesManager {
        makePrefsWithSuiteName().prefs
    }

    private func makePrefsWithSuiteName() -> (prefs: PreferencesManager, suiteName: String) {
        let suiteName = "test.PreferencesObservation.\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let suite = UserDefaults(suiteName: suiteName)!
        return (PreferencesManager(defaults: suite), suiteName)
    }

    // MARK: - Observation fires on mutation (the original bug)

    func testTrashSourceAfterBackup_firesOnMutation() {
        let prefs = makePrefs()
        let initial = prefs.trashSourceAfterBackup
        let expectation = expectation(description: "observation fires")
        withObservationTracking {
            _ = prefs.trashSourceAfterBackup
        } onChange: {
            expectation.fulfill()
        }
        prefs.trashSourceAfterBackup = !initial
        wait(for: [expectation], timeout: 1.0)
    }

    func testIncludeSubdirectories_firesOnMutation() {
        let prefs = makePrefs()
        let initial = prefs.includeSubdirectories
        let expectation = expectation(description: "observation fires")
        withObservationTracking {
            _ = prefs.includeSubdirectories
        } onChange: { expectation.fulfill() }
        prefs.includeSubdirectories = !initial
        wait(for: [expectation], timeout: 1.0)
    }

    func testRestoreLastSession_firesOnMutation() {
        let prefs = makePrefs()
        let initial = prefs.restoreLastSession
        let expectation = expectation(description: "observation fires")
        withObservationTracking {
            _ = prefs.restoreLastSession
        } onChange: { expectation.fulfill() }
        prefs.restoreLastSession = !initial
        wait(for: [expectation], timeout: 1.0)
    }

    func testEnableVisionFramework_firesOnMutation() {
        let prefs = makePrefs()
        PreferencesManager._isAppleSiliconOverride = true   // deterministic default
        let initial = prefs.enableVisionFramework
        let expectation = expectation(description: "observation fires")
        withObservationTracking {
            _ = prefs.enableVisionFramework
        } onChange: { expectation.fulfill() }
        prefs.enableVisionFramework = !initial
        wait(for: [expectation], timeout: 1.0)
    }

    func testNetworkCopyTimeout_firesOnMutation() {
        let prefs = makePrefs()
        let expectation = expectation(description: "observation fires")
        withObservationTracking {
            _ = prefs.networkCopyTimeout
        } onChange: { expectation.fulfill() }
        prefs.networkCopyTimeout = 120
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Equality guard: no observation when value unchanged

    func testTrashSourceAfterBackup_doesNotFireWhenUnchanged() {
        let prefs = makePrefs()
        let initial = prefs.trashSourceAfterBackup
        let expectation = expectation(description: "observation must not fire")
        expectation.isInverted = true
        withObservationTracking {
            _ = prefs.trashSourceAfterBackup
        } onChange: { expectation.fulfill() }
        prefs.trashSourceAfterBackup = initial
        wait(for: [expectation], timeout: 0.2)
    }

    func testNetworkCopyTimeout_doesNotFireWhenUnchanged() {
        let prefs = makePrefs()
        prefs.networkCopyTimeout = 120
        let expectation = expectation(description: "observation must not fire")
        expectation.isInverted = true
        withObservationTracking {
            _ = prefs.networkCopyTimeout
        } onChange: { expectation.fulfill() }
        prefs.networkCopyTimeout = 120
        wait(for: [expectation], timeout: 0.2)
    }

    // MARK: - Clamping

    func testNetworkCopyTimeout_clampsInSetter() {
        let prefs = makePrefs()
        prefs.networkCopyTimeout = 99_999
        XCTAssertEqual(prefs.defaults.integer(forKey: PreferencesManager.Keys.networkCopyTimeout.rawValue), 3600,
                       "Setter must clamp before writing to disk")
        prefs.networkCopyTimeout = -10
        XCTAssertEqual(prefs.defaults.integer(forKey: PreferencesManager.Keys.networkCopyTimeout.rawValue), 1,
                       "Setter must clamp negative values to min")
    }

    func testNetworkCopyTimeout_clampsInGetter() {
        let prefs = makePrefs()
        // Externally inject an out-of-range value bypassing the setter.
        prefs.defaults.set(99_999, forKey: PreferencesManager.Keys.networkCopyTimeout.rawValue)
        XCTAssertEqual(prefs.networkCopyTimeout, 3600,
                       "Getter must sanitize externally-injected out-of-range values")
    }

    func testDefaultFileTypeFilter_clampsInvalidValueToAll() {
        let prefs = makePrefs()
        prefs.defaults.set("garbage", forKey: PreferencesManager.Keys.defaultFileTypeFilter.rawValue)
        XCTAssertEqual(prefs.defaultFileTypeFilter, "all")
    }

    // MARK: - enableVisionFramework (custom property)

    func testEnableVisionFramework_defaultOnAppleSilicon() {
        let prefs = makePrefs()
        PreferencesManager._isAppleSiliconOverride = true
        XCTAssertTrue(prefs.enableVisionFramework)
    }

    func testEnableVisionFramework_defaultOnIntel() {
        let prefs = makePrefs()
        PreferencesManager._isAppleSiliconOverride = false
        XCTAssertFalse(prefs.enableVisionFramework)
    }

    func testEnableVisionFramework_userOverrideBeatsCapability() {
        let prefs = makePrefs()
        PreferencesManager._isAppleSiliconOverride = false   // Intel default = false
        prefs.enableVisionFramework = true
        XCTAssertTrue(prefs.enableVisionFramework, "Explicit override wins")
    }

    @MainActor
    func testResetClearsEnableVisionFrameworkOverride() {
        let prefs = makePrefs()
        PreferencesManager._isAppleSiliconOverride = true
        prefs.enableVisionFramework = false   // explicit override
        XCTAssertFalse(prefs.enableVisionFramework)
        prefs.resetToDefaults()
        XCTAssertTrue(prefs.enableVisionFramework, "After reset, should fall back to Apple Silicon default")
    }

    // MARK: - Reset coverage (the Round 6/8 blocker check)

    @MainActor
    func testResetToDefaults_clearsEveryKeyInKeysEnum() {
        let (prefs, suiteName) = makePrefsWithSuiteName()
        // Seed every key with a non-default marker so removal is detectable.
        for key in PreferencesManager.Keys.allCases {
            prefs.defaults.set("test-marker", forKey: key.rawValue)
        }
        prefs.resetToDefaults()
        // Check the persistent domain directly — `object(forKey:)` would return the registered
        // default (not nil) for keys with registered defaults, making the assertion useless.
        let persisted = UserDefaults.standard.persistentDomain(forName: suiteName) ?? [:]
        for key in PreferencesManager.Keys.allCases {
            XCTAssertNil(persisted[key.rawValue],
                         "resetToDefaults did not clear '\(key.rawValue)' from the persistent domain — add a `withMutation(...)` line in resetToDefaults when adding new preferences")
        }
    }

    @MainActor
    func testResetToDefaults_firesObservationForTrashSourceAfterBackup() {
        let prefs = makePrefs()
        prefs.trashSourceAfterBackup = true
        let expectation = expectation(description: "reset fires observation")
        withObservationTracking {
            _ = prefs.trashSourceAfterBackup
        } onChange: { expectation.fulfill() }
        prefs.resetToDefaults()
        wait(for: [expectation], timeout: 1.0)
    }

    // MARK: - Path blocklist

    func testPathBlocklist_rejectsSshTildePath() {
        XCTAssertTrue(PreferencesManager.isSensitivePath("~/.ssh"))
        XCTAssertTrue(PreferencesManager.isSensitivePath("~/.ssh/id_rsa"))
    }

    func testPathBlocklist_rejectsKeychainsPath() {
        XCTAssertTrue(PreferencesManager.isSensitivePath("/Users/foo/Library/Keychains/login.keychain"))
    }

    func testPathBlocklist_rejectsLexicalTraversal() {
        XCTAssertTrue(PreferencesManager.isSensitivePath("/Users/Shared/../../private/etc/passwd"))
        XCTAssertTrue(PreferencesManager.isSensitivePath("/private/var/./db/foo"))
    }

    func testPathBlocklist_rejectsCaseVariants() {
        XCTAssertTrue(PreferencesManager.isSensitivePath("/Users/foo/.SSH"))
        XCTAssertTrue(PreferencesManager.isSensitivePath("/USERS/FOO/Library/KEYCHAINS"))
    }

    func testPathBlocklist_rejectsURLSchemes() {
        XCTAssertTrue(PreferencesManager.isSensitivePath("file://etc/passwd"))
        XCTAssertTrue(PreferencesManager.isSensitivePath("smb://host/share"))
    }

    func testPathBlocklist_rejectsNullByte() {
        XCTAssertTrue(PreferencesManager.isSensitivePath("/Users/foo/\0/.ssh"))
    }

    func testPathBlocklist_acceptsSshLookalikeWithoutFalsePositive() {
        XCTAssertFalse(PreferencesManager.isSensitivePath("/Users/foo/.ssh-backups"),
                       "Boundary-aware match must not flag unrelated folders starting with .ssh")
    }

    func testPathBlocklist_acceptsLegitimatePaths() {
        XCTAssertFalse(PreferencesManager.isSensitivePath("/Users/foo/Pictures"))
        XCTAssertFalse(PreferencesManager.isSensitivePath("/Volumes/External/Backups"))
        XCTAssertFalse(PreferencesManager.isSensitivePath("~/Pictures/2026"))
    }

    func testDefaultSourcePath_setterRejectsBlockedPath() {
        let prefs = makePrefs()
        prefs.defaultSourcePath = "~/.ssh"
        XCTAssertEqual(prefs.defaultSourcePath, "", "Blocked path must not be stored")
    }

    // MARK: - Folder name sanitization

    func testSanitizeFolderName_rejectsPathTraversal() {
        XCTAssertNil(PreferencesManager.sanitizeFolderName("foo/bar"))
        XCTAssertNil(PreferencesManager.sanitizeFolderName("../etc/passwd"))
        XCTAssertNil(PreferencesManager.sanitizeFolderName("foo\\bar"))
    }

    func testSanitizeFolderName_rejectsLeadingDotAndTilde() {
        XCTAssertNil(PreferencesManager.sanitizeFolderName("."))
        XCTAssertNil(PreferencesManager.sanitizeFolderName(".."))
        XCTAssertNil(PreferencesManager.sanitizeFolderName(".hidden"))
        XCTAssertNil(PreferencesManager.sanitizeFolderName("~Desktop"))
    }

    func testSanitizeFolderName_acceptsLegitimateNames() {
        XCTAssertEqual(PreferencesManager.sanitizeFolderName("R&D Notes"), "R&D Notes")
        XCTAssertEqual(PreferencesManager.sanitizeFolderName("100$ Budget"), "100$ Budget")
        XCTAssertEqual(PreferencesManager.sanitizeFolderName("Backup 10:30"), "Backup 10:30")
        XCTAssertEqual(PreferencesManager.sanitizeFolderName("Vacation 2026"), "Vacation 2026")
    }

    func testSanitizeFolderName_rejectsNullAndControlChars() {
        XCTAssertNil(PreferencesManager.sanitizeFolderName("foo\0bar"))
        XCTAssertNil(PreferencesManager.sanitizeFolderName("foo\u{07}bar"))
    }

    @MainActor
    func testAddRecentOrganizationFolderName_returnsFalseOnRejectedName() {
        let prefs = makePrefs()
        XCTAssertFalse(prefs.addRecentOrganizationFolderName("../etc/passwd"))
        XCTAssertFalse(prefs.addRecentOrganizationFolderName("~/Desktop"))
        XCTAssertTrue(prefs.addRecentOrganizationFolderName("R&D Notes"))
        XCTAssertTrue(prefs.addRecentOrganizationFolderName("100$ Budget"))
        XCTAssertEqual(prefs.recentOrganizationFolderNames, ["100$ Budget", "R&D Notes"])
    }

    @MainActor
    func testRecentOrganizationFolderNames_deduplicatesAndMovesToTop() {
        let prefs = makePrefs()
        prefs.addRecentOrganizationFolderName("A")
        prefs.addRecentOrganizationFolderName("B")
        prefs.addRecentOrganizationFolderName("A")   // re-add
        XCTAssertEqual(prefs.recentOrganizationFolderNames, ["A", "B"])
    }

    @MainActor
    func testRecentOrganizationFolderNames_trimsToTen() {
        let prefs = makePrefs()
        for i in 0..<15 {
            prefs.addRecentOrganizationFolderName("Folder \(i)")
        }
        XCTAssertEqual(prefs.recentOrganizationFolderNames.count, 10)
        XCTAssertEqual(prefs.recentOrganizationFolderNames.first, "Folder 14",
                       "Most recent at top")
    }

    // MARK: - Legacy JSON migration

    func testLegacyMigration_migratesValidJSON() {
        let suiteName = "test.LegacyMigration.\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let suite = UserDefaults(suiteName: suiteName)!
        // Seed legacy key BEFORE constructing PreferencesManager
        suite.set("[\"A\", \"B\", \"C\"]", forKey: PreferencesManager.legacyRecentOrganizationFolderNamesJSONKey)

        let prefs = PreferencesManager(defaults: suite)

        // Legacy key cleaned up
        XCTAssertNil(suite.string(forKey: PreferencesManager.legacyRecentOrganizationFolderNamesJSONKey))
        // Native key populated
        let migrated = suite.stringArray(forKey: PreferencesManager.Keys.recentOrganizationFolderNames.rawValue)
        XCTAssertEqual(migrated, ["A", "B", "C"])
        _ = prefs   // silence unused warning
    }

    func testLegacyMigration_discardsMalformedJSON() {
        let suiteName = "test.LegacyMigration.\(UUID().uuidString)"
        createdSuiteNames.append(suiteName)
        let suite = UserDefaults(suiteName: suiteName)!
        suite.set("not valid json {{{", forKey: PreferencesManager.legacyRecentOrganizationFolderNamesJSONKey)

        let prefs = PreferencesManager(defaults: suite)

        // Legacy key cleaned up (migration is always idempotent)
        XCTAssertNil(suite.string(forKey: PreferencesManager.legacyRecentOrganizationFolderNamesJSONKey))
        // Native key remains unset (register default doesn't populate arrays)
        XCTAssertNil(suite.stringArray(forKey: PreferencesManager.Keys.recentOrganizationFolderNames.rawValue))
        _ = prefs
    }

    @MainActor
    func testExternalInjection_pathTraversalFilteredFromStringArray() {
        let prefs = makePrefs()
        // External process writes bad entries to the native key
        prefs.defaults.set(["../etc", "foo/bar", "~/Desktop", "ValidName"],
                           forKey: PreferencesManager.Keys.recentOrganizationFolderNames.rawValue)
        XCTAssertEqual(prefs.recentOrganizationFolderNames, ["ValidName"])
    }
}
