import XCTest

@testable import ImageIntact

class OrganizationFolderTests: XCTestCase {
    override func setUp() {
        super.setUp()
        // Clear any stored folder names before each test
        PreferencesManager.shared.recentOrganizationFolderNames = []
        PreferencesManager.shared.lastUsedOrganizationFolderName = nil
    }

    override func tearDown() {
        // Clean up after tests
        PreferencesManager.shared.recentOrganizationFolderNames = []
        PreferencesManager.shared.lastUsedOrganizationFolderName = nil
        super.tearDown()
    }

    // MARK: - Underscore Replacement Tests

    @MainActor
    func testDefaultFolderNameUsesUnderscores() async {
        let backupManager = BackupManager()
        let testURL = URL(fileURLWithPath: "/Users/test/Photos/My Photo Shoot")
        backupManager.setSource(testURL)

        // The organization name should have underscores instead of spaces
        XCTAssertEqual(backupManager.organizationName, "My_Photo_Shoot")
    }

    @MainActor
    func testFolderNameWithMultipleSpaces() async {
        let backupManager = BackupManager()
        let testURL = URL(fileURLWithPath: "/Users/test/Photos/Wedding  John  Jane")
        backupManager.setSource(testURL)

        // Multiple spaces should be collapsed to single underscores
        XCTAssertEqual(backupManager.organizationName, "Wedding_John_Jane")
    }

    @MainActor
    func testFolderNameWithNoSpaces() async {
        let backupManager = BackupManager()
        let testURL = URL(fileURLWithPath: "/Users/test/Photos/WeddingShoot")
        backupManager.setSource(testURL)

        // No spaces means no underscores added
        XCTAssertEqual(backupManager.organizationName, "WeddingShoot")
    }

    // MARK: - Recent Folder Names Storage Tests

    func testRecentFolderNamesDefaultsToEmpty() {
        XCTAssertTrue(PreferencesManager.shared.recentOrganizationFolderNames.isEmpty)
    }

    func testAddingRecentFolderName() {
        PreferencesManager.shared.addRecentOrganizationFolderName("Test_Folder")

        XCTAssertEqual(PreferencesManager.shared.recentOrganizationFolderNames.count, 1)
        XCTAssertEqual(PreferencesManager.shared.recentOrganizationFolderNames.first, "Test_Folder")
    }

    func testRecentFolderNamesLimitedToTen() {
        // Add 12 folder names
        for i in 1 ... 12 {
            PreferencesManager.shared.addRecentOrganizationFolderName("Folder_\(i)")
        }

        // Should only keep the most recent 10
        XCTAssertEqual(PreferencesManager.shared.recentOrganizationFolderNames.count, 10)
        // Most recent should be first
        XCTAssertEqual(PreferencesManager.shared.recentOrganizationFolderNames.first, "Folder_12")
        // Oldest should be Folder_3 (Folder_1 and Folder_2 were dropped)
        XCTAssertEqual(PreferencesManager.shared.recentOrganizationFolderNames.last, "Folder_3")
    }

    func testRecentFolderNamesInReverseChronologicalOrder() {
        PreferencesManager.shared.addRecentOrganizationFolderName("First")
        PreferencesManager.shared.addRecentOrganizationFolderName("Second")
        PreferencesManager.shared.addRecentOrganizationFolderName("Third")

        let names = PreferencesManager.shared.recentOrganizationFolderNames
        XCTAssertEqual(names[0], "Third")
        XCTAssertEqual(names[1], "Second")
        XCTAssertEqual(names[2], "First")
    }

    func testDuplicateFolderNameMovesToTop() {
        PreferencesManager.shared.addRecentOrganizationFolderName("First")
        PreferencesManager.shared.addRecentOrganizationFolderName("Second")
        PreferencesManager.shared.addRecentOrganizationFolderName("Third")

        // Add "First" again - should move to top, not duplicate
        PreferencesManager.shared.addRecentOrganizationFolderName("First")

        let names = PreferencesManager.shared.recentOrganizationFolderNames
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(names[0], "First")
        XCTAssertEqual(names[1], "Third")
        XCTAssertEqual(names[2], "Second")
    }

    func testEmptyFolderNameNotAdded() {
        PreferencesManager.shared.addRecentOrganizationFolderName("")

        XCTAssertTrue(PreferencesManager.shared.recentOrganizationFolderNames.isEmpty)
    }

    func testWhitespaceOnlyFolderNameNotAdded() {
        PreferencesManager.shared.addRecentOrganizationFolderName("   ")

        XCTAssertTrue(PreferencesManager.shared.recentOrganizationFolderNames.isEmpty)
    }

    // MARK: - Last Used Folder Name Tests

    func testLastUsedFolderNameDefaultsToNil() {
        XCTAssertNil(PreferencesManager.shared.lastUsedOrganizationFolderName)
    }

    func testLastUsedFolderNamePersistence() {
        PreferencesManager.shared.lastUsedOrganizationFolderName = "My_Project"

        XCTAssertEqual(PreferencesManager.shared.lastUsedOrganizationFolderName, "My_Project")
    }

    // MARK: - App Start Behavior Tests

    @MainActor
    func testAppStartWithBlankFieldUsesDefaultSuggestion() async {
        // Simulate blank last used (user never customized)
        PreferencesManager.shared.lastUsedOrganizationFolderName = nil

        let backupManager = BackupManager()
        let testURL = URL(fileURLWithPath: "/Users/test/Photos/Wedding_Shoot")
        backupManager.setSource(testURL)

        // Should use the default derived from source
        XCTAssertEqual(backupManager.organizationName, "Wedding_Shoot")
    }

    @MainActor
    func testAppStartWithUserGeneratedNameUsesLastUsed() async {
        // Simulate user previously set a custom name
        PreferencesManager.shared.lastUsedOrganizationFolderName = "My_Custom_Backup"

        let backupManager = BackupManager()

        // Without a source, the last used should be restored
        XCTAssertEqual(backupManager.organizationName, "My_Custom_Backup")
    }
}
