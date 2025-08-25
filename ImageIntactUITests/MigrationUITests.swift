import XCTest

final class MigrationUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    func testMigrationDialog_AppearsWhenNeeded() throws {
        // Setup: Create source and destination with existing files
        let sourcePath = createTestSourceWithFiles()
        let destPath = createTestDestinationWithExistingFiles()
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath,
            "--testOrganization", "TestOrg"
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        runBackupButton.click()
        
        // Look for migration dialog
        let migrationSheet = app.sheets.containing(NSPredicate(format: "label CONTAINS 'Organize Existing Files'")).firstMatch
        XCTAssertTrue(migrationSheet.waitForExistence(timeout: 10), "Migration dialog should appear")
        
        // Verify dialog shows file count
        let fileCountText = migrationSheet.staticTexts.matching(NSPredicate(format: "label MATCHES '.*\\d+ file.*'")).firstMatch
        XCTAssertTrue(fileCountText.exists, "Should show number of files to migrate")
    }
    
    func testMigrationDialog_MigrateButton() throws {
        let sourcePath = createTestSourceWithFiles()
        let destPath = createTestDestinationWithExistingFiles()
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath,
            "--testOrganization", "TestOrg"
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Wait for migration dialog
        let migrationSheet = app.sheets.firstMatch
        XCTAssertTrue(migrationSheet.waitForExistence(timeout: 10))
        
        // Click Migrate button
        let migrateButton = migrationSheet.buttons["Migrate Files"]
        XCTAssertTrue(migrateButton.exists)
        migrateButton.click()
        
        // Verify migration progress appears
        let migrationProgress = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Migrating'")).firstMatch
        XCTAssertTrue(migrationProgress.waitForExistence(timeout: 5), "Should show migration progress")
        
        // Wait for backup to continue
        let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 60), "Backup should complete after migration")
    }
    
    func testMigrationDialog_SkipButton() throws {
        let sourcePath = createTestSourceWithFiles()
        let destPath = createTestDestinationWithExistingFiles()
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath,
            "--testOrganization", "TestOrg"
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Wait for migration dialog
        let migrationSheet = app.sheets.firstMatch
        XCTAssertTrue(migrationSheet.waitForExistence(timeout: 10))
        
        // Click Skip button
        let skipButton = migrationSheet.buttons["Skip Migration"]
        XCTAssertTrue(skipButton.exists)
        skipButton.click()
        
        // Verify backup continues without migration
        let copyingText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Copying'")).firstMatch
        XCTAssertTrue(copyingText.waitForExistence(timeout: 5), "Should proceed with copying after skip")
    }
    
    func testNoMigrationDialog_WhenOrganizationEmpty() throws {
        let sourcePath = createTestSourceWithFiles()
        let destPath = createTestDestinationWithExistingFiles()
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath,
            "--testOrganization", "" // Empty organization name
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Verify no migration dialog appears
        let migrationSheet = app.sheets.firstMatch
        XCTAssertFalse(migrationSheet.waitForExistence(timeout: 3), "Migration dialog should not appear with empty organization")
        
        // Verify backup proceeds directly
        let copyingText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Copying'")).firstMatch
        XCTAssertTrue(copyingText.waitForExistence(timeout: 5), "Should start copying immediately")
    }
    
    // MARK: - Helper Methods
    
    private func createTestSourceWithFiles() -> String {
        let testDir = NSTemporaryDirectory().appending("MigrationUITest_Source_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        
        // Create test files
        for i in 1...3 {
            let filePath = "\(testDir)/photo_\(i).jpg"
            FileManager.default.createFile(atPath: filePath, contents: Data("source content \(i)".utf8))
        }
        
        return testDir
    }
    
    private func createTestDestinationWithExistingFiles() -> String {
        let testDir = NSTemporaryDirectory().appending("MigrationUITest_Dest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        
        // Create matching files at destination (simulating previous backup)
        for i in 1...3 {
            let filePath = "\(testDir)/photo_\(i).jpg"
            FileManager.default.createFile(atPath: filePath, contents: Data("source content \(i)".utf8))
        }
        
        return testDir
    }
}