import XCTest

final class ImageIntactUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
        continueAfterFailure = false
        
        app = XCUIApplication()
        
        // Enable UI test mode with test arguments
        app.launchArguments = ["--uitest"]
        
        // In UI tests it's important to set the initial state required for your tests before they run.
        // This is a good place to setup test data.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        app = nil
    }
    
    // MARK: - Happy Path Tests
    
    func testHappyPath_SelectSourceAndDestinations_RunBackup() throws {
        // Given: Launch app with test data
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath(),
            "--testDest1", createTestDestinationPath(1),
            "--testDest2", createTestDestinationPath(2)
        ])
        app.launch()
        
        // Wait for app to be ready
        let mainWindow = app.windows.firstMatch
        XCTAssertTrue(mainWindow.waitForExistence(timeout: 5))
        
        // When: Click Run Backup button
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        XCTAssertTrue(runBackupButton.isEnabled)
        runBackupButton.click()
        
        // Then: Wait for completion
        // Look for completion indicators (we'll need to add accessibility identifiers to the actual UI)
        let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 60), "Backup should complete within 60 seconds")
    }
    
    func testSelectSourceFolder_ViaButton() throws {
        app.launch()
        
        // Find and click source folder button
        let sourceFolderButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Source'")).firstMatch
        XCTAssertTrue(sourceFolderButton.waitForExistence(timeout: 5))
        
        // Note: We can't actually test NSOpenPanel interaction in UI tests
        // We'd need to use launch arguments to bypass the file picker
        // This test mainly verifies the button exists and is clickable
    }
    
    func testAddMultipleDestinations() throws {
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath()
        ])
        app.launch()
        
        // Add first destination
        let addDestinationButton = app.buttons["Add Destination"]
        if addDestinationButton.waitForExistence(timeout: 5) {
            addDestinationButton.click()
        }
        
        // Verify destination was added (would need proper accessibility identifiers)
        let destinationButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Destination'"))
        XCTAssertGreaterThanOrEqual(destinationButtons.count, 1)
    }
    
    // MARK: - Error Handling Tests
    
    func testErrorHandling_NoSourceSelected() throws {
        app.launch()
        
        // Try to run backup without source
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        XCTAssertFalse(runBackupButton.isEnabled, "Run Backup should be disabled without source")
    }
    
    func testErrorHandling_NoDestinationSelected() throws {
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath()
        ])
        app.launch()
        
        // Verify Run Backup is still disabled without destinations
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        XCTAssertFalse(runBackupButton.isEnabled, "Run Backup should be disabled without destinations")
    }
    
    // MARK: - Organization Feature Tests
    
    func testOrganizationSection_AppearsAfterSourceSelection() throws {
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath()
        ])
        app.launch()
        
        // Look for organization section
        let organizeAsField = app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS 'folder name'")).firstMatch
        XCTAssertTrue(organizeAsField.waitForExistence(timeout: 5), "Organization field should appear after source selection")
        
        // Verify it has a default value
        XCTAssertFalse(organizeAsField.value as? String ?? "" == "", "Organization field should have auto-generated name")
    }
    
    func testOrganizationName_CanBeCustomized() throws {
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath()
        ])
        app.launch()
        
        // Find organization field
        let organizeAsField = app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS 'folder name'")).firstMatch
        XCTAssertTrue(organizeAsField.waitForExistence(timeout: 5))
        
        // Clear and type custom name
        organizeAsField.click()
        organizeAsField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50)) // Clear existing
        organizeAsField.typeText("MyCustomBackup")
        
        // Verify the value changed
        XCTAssertEqual(organizeAsField.value as? String, "MyCustomBackup")
    }
    
    // MARK: - Preset Tests
    
    func testPresetSelection_OpensSheet() throws {
        app.launch()
        
        // Look for preset selection button
        let presetButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Select Preset'")).firstMatch
        if presetButton.waitForExistence(timeout: 5) {
            presetButton.click()
            
            // Verify sheet appears
            let presetSheet = app.sheets.firstMatch
            XCTAssertTrue(presetSheet.waitForExistence(timeout: 2), "Preset selection sheet should appear")
            
            // Cancel to close
            let cancelButton = app.sheets.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.click()
            }
        }
    }
    
    // MARK: - Progress Monitoring Tests
    
    func testProgressIndicators_AppearDuringBackup() throws {
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath(),
            "--testDest1", createTestDestinationPath(1)
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        runBackupButton.click()
        
        // Look for progress indicators
        let progressIndicator = app.progressIndicators.firstMatch
        XCTAssertTrue(progressIndicator.waitForExistence(timeout: 5), "Progress indicator should appear during backup")
        
        // Look for status text
        let statusTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Scanning' OR label CONTAINS 'Copying' OR label CONTAINS 'Verifying'"))
        XCTAssertGreaterThan(statusTexts.count, 0, "Status messages should appear during backup")
    }
    
    // MARK: - Cancellation Tests
    
    func testCancelBackup_StopsOperation() throws {
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSourcePath(),
            "--testDest1", createTestDestinationPath(1)
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        runBackupButton.click()
        
        // Wait for operation to start
        let progressIndicator = app.progressIndicators.firstMatch
        XCTAssertTrue(progressIndicator.waitForExistence(timeout: 5))
        
        // Press ESC to cancel (or look for cancel button)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        
        // Verify cancellation (would need proper status text)
        let cancelledText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'cancelled'")).firstMatch
        XCTAssertTrue(cancelledText.waitForExistence(timeout: 10), "Should show cancellation status")
    }
    
    // MARK: - Helper Methods
    
    private func createTestSourcePath() -> String {
        let testDir = NSTemporaryDirectory().appending("ImageIntactUITest_Source_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        
        // Create some test files
        for i in 1...5 {
            let filePath = "\(testDir)/test_photo_\(i).jpg"
            FileManager.default.createFile(atPath: filePath, contents: Data("test content \(i)".utf8))
        }
        
        return testDir
    }
    
    private func createTestDestinationPath(_ index: Int) -> String {
        let testDir = NSTemporaryDirectory().appending("ImageIntactUITest_Dest\(index)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        return testDir
    }
    
    // MARK: - Performance Tests
    
    func testLaunchPerformance() throws {
        if #available(macOS 10.15, iOS 13.0, tvOS 13.0, watchOS 7.0, *) {
            // This measures how long it takes to launch your application.
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}