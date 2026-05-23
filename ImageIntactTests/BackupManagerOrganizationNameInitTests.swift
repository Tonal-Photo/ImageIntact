//
//  BackupManagerOrganizationNameInitTests.swift
//  ImageIntactTests
//
//  Tests for the BackupManager init organizationName sanitization fix (AMUX-15).
//
//  Low fix: organizationName = lastUsedName at init bypassed SmartFolderName.sanitize
//  because `didSet` doesn't fire during initialization. The fix wraps the assignment in
//  SmartFolderName.sanitize() directly.
//
//  AMUX-205: uses InMemoryPreferencesProvider instead of mutating
//  PreferencesManager.shared, so no save/restore boilerplate is needed.
//
//  Design doc: .planning/design/PreferencesProviding.md (and predecessor
//  backup-manager-run-backup-extraction.md §"Fixed init").
//

import XCTest
@testable import ImageIntact

@MainActor
final class BackupManagerOrganizationNameInitTests: BaseBackupManagerTestCase {

    // MARK: - Test fixtures

    var mockFileOps: MockFileOperations!

    override func setUp() async throws {
        try await super.setUp()

        mockFileOps = MockFileOperations()
        // Note: bm is not pre-assigned here — each test assigns self.bm with its own
        // BackupManager after loading the desired preference state. The base class
        // tearDown will cancel any in-flight backup via self.bm before releasing it.
    }

    override func tearDown() async throws {
        mockFileOps = nil
        // Base class cancels any in-flight backup via self.bm and restores bookmarks.
        try await super.tearDown()
    }

    // MARK: - Tests

    /// Low fix verification: organizationName loaded from preferences at init must be
    /// sanitized via SmartFolderName.sanitize (the didSet doesn't fire during init).
    ///
    /// "foo/bar" → sanitize replaces "/" with "_" → "foo_bar".
    /// We verify against SmartFolderName.sanitize("foo/bar"), not the literal "foo_bar",
    /// so the test is robust to future changes in the sanitize implementation.
    func testInit_organizationNameFromPrefs_isSanitized() {
        let dirtyName = "foo/bar"
        let prefs = InMemoryPreferencesProvider(lastUsedOrganizationFolderName: dirtyName)

        // Construct BackupManager — init reads lastUsedOrganizationFolderName from
        // the injected provider. Assigned to self.bm for tearDown's benefit.
        self.bm = BackupManager(fileOperations: mockFileOps, preferences: prefs)

        let expectedName = SmartFolderName.sanitize(dirtyName)
        XCTAssertEqual(bm.organizationName, expectedName,
                       "organizationName must be sanitized at init; got '\(bm.organizationName)' instead of '\(expectedName)'")
        XCTAssertNotEqual(bm.organizationName, dirtyName,
                          "organizationName must not equal the raw unsanitized value '\(dirtyName)'")
    }
}
