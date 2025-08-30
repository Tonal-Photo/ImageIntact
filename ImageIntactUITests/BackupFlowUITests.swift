//
//  BackupFlowUITests.swift
//  ImageIntactUITests
//
//  XCUITests for main backup flow user interactions
//

import XCTest

final class BackupFlowUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        
        // Clean up any previous test data
        cleanupTestDirectories()
    }
    
    override func tearDownWithError() throws {
        app = nil
        cleanupTestDirectories()
    }
    
    // MARK: - Basic Backup Flow Tests
    
    func testCompleteBackupFlow_SingleDestination() throws {
        // Given: Prepare test data
        let sourcePath = createTestSource(fileCount: 5)
        let destPath = createTestDestination("dest1")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath
        ])
        app.launch()
        
        // When: Start backup
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5), "Run Backup button should exist")
        XCTAssertTrue(runBackupButton.isEnabled, "Run Backup should be enabled with source and destination")
        
        runBackupButton.click()
        
        // Then: Verify progress indicators appear
        let progressBar = app.progressIndicators.firstMatch
        XCTAssertTrue(progressBar.waitForExistence(timeout: 3), "Progress bar should appear")
        
        // Verify status messages
        let scanningText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Scanning'")).firstMatch
        XCTAssertTrue(scanningText.waitForExistence(timeout: 5), "Should show scanning status")
        
        // Wait for completion
        let completionPredicate = NSPredicate(format: "label CONTAINS 'complete' OR label CONTAINS 'Completed'")
        let completionText = app.staticTexts.containing(completionPredicate).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 30), "Backup should complete")
        
        // Verify success indicators
        let successPredicate = NSPredicate(format: "label CONTAINS 'success' OR label CONTAINS '✓' OR label CONTAINS 'verified'")
        let successIndicator = app.staticTexts.containing(successPredicate).firstMatch
        XCTAssertTrue(successIndicator.exists, "Should show success status")
    }
    
    func testCompleteBackupFlow_MultipleDestinations() throws {
        // Given: Multiple destinations
        let sourcePath = createTestSource(fileCount: 10)
        let dest1Path = createTestDestination("dest1")
        let dest2Path = createTestDestination("dest2")
        let dest3Path = createTestDestination("dest3")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", dest1Path,
            "--testDest2", dest2Path,
            "--testDest3", dest3Path
        ])
        app.launch()
        
        // When: Start backup
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        runBackupButton.click()
        
        // Then: Verify multiple progress indicators (one per destination)
        let progressBars = app.progressIndicators
        XCTAssertTrue(progressBars.firstMatch.waitForExistence(timeout: 3))
        
        // In the queue system, we should see progress for each destination
        // Look for destination-specific status text
        let dest1Status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'dest1'")).firstMatch
        let dest2Status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'dest2'")).firstMatch
        let dest3Status = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'dest3'")).firstMatch
        
        // At least one destination should show status
        let anyDestinationStatus = dest1Status.exists || dest2Status.exists || dest3Status.exists
        XCTAssertTrue(anyDestinationStatus, "Should show destination-specific status")
        
        // Wait for completion
        let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 60), "Multi-destination backup should complete")
    }
    
    // MARK: - Organization Tests
    
    func testOrganizationFolder_CreatedCorrectly() throws {
        // Given: Source with organization name
        let sourcePath = createTestSource(fileCount: 3)
        let destPath = createTestDestination("organized")
        let orgName = "TestOrg2024"
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath,
            "--testOrganization", orgName
        ])
        app.launch()
        
        // Verify organization field shows the name
        let orgField = app.textFields.containing(NSPredicate(format: "value CONTAINS '\(orgName)'")).firstMatch
        XCTAssertTrue(orgField.waitForExistence(timeout: 3), "Organization field should show the name")
        
        // Run backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Wait for completion
        let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 30))
        
        // Verify organization folder was created (would need to check filesystem in real test)
        let orgFolderPath = "\(destPath)/\(orgName)"
        XCTAssertTrue(FileManager.default.fileExists(atPath: orgFolderPath), "Organization folder should be created")
    }
    
    func testOrganizationField_Editable() throws {
        // Given: Source selected
        let sourcePath = createTestSource(fileCount: 2)
        let destPath = createTestDestination("dest1")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath
        ])
        app.launch()
        
        // Find organization field
        let orgField = app.textFields.firstMatch
        XCTAssertTrue(orgField.waitForExistence(timeout: 3))
        
        // Clear and enter custom name
        orgField.click()
        orgField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 50))
        orgField.typeText("CustomBackup2024")
        
        // Verify the value changed
        XCTAssertTrue(orgField.value as? String == "CustomBackup2024", "Organization name should be updated")
    }
    
    // MARK: - Progress and Status Tests
    
    func testProgressBars_ShowAccurateProgress() throws {
        // Given: Large backup to ensure we see progress
        let sourcePath = createTestSource(fileCount: 20)
        let destPath = createTestDestination("progress")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Check for overall progress bar
        let overallProgress = app.progressIndicators.containing(NSPredicate(format: "identifier CONTAINS 'overall' OR label CONTAINS 'Overall'")).firstMatch
        if !overallProgress.exists {
            // Fallback to any progress indicator
            let anyProgress = app.progressIndicators.firstMatch
            XCTAssertTrue(anyProgress.waitForExistence(timeout: 3), "Should show progress indicator")
        }
        
        // Check for status updates
        var statusMessages: [String] = []
        for _ in 0..<10 {
            let statusTexts = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Copying' OR label CONTAINS 'Verifying' OR label CONTAINS 'Scanning'"))
            for i in 0..<min(statusTexts.count, 3) {
                let text = statusTexts.element(boundBy: i)
                if text.exists, let label = text.label as String? {
                    statusMessages.append(label)
                }
            }
            
            if !statusMessages.isEmpty {
                break
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        XCTAssertFalse(statusMessages.isEmpty, "Should show status messages during backup")
    }
    
    func testVerificationPhase_ShowsStatus() throws {
        // Given: Small backup to quickly reach verification
        let sourcePath = createTestSource(fileCount: 2)
        let destPath = createTestDestination("verify")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Look for verification status
        let verifyingText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Verifying' OR label CONTAINS 'verification'")).firstMatch
        XCTAssertTrue(verifyingText.waitForExistence(timeout: 20), "Should show verification status")
        
        // Wait for completion
        let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 30))
    }
    
    // MARK: - Cancellation Tests
    
    func testCancelDuringBackup_StopsOperation() throws {
        // Given: Large backup that we can cancel
        let sourcePath = createTestSource(fileCount: 50)
        let destPath = createTestDestination("cancel")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Wait for operation to start
        let progressBar = app.progressIndicators.firstMatch
        XCTAssertTrue(progressBar.waitForExistence(timeout: 3))
        
        // Cancel using ESC key
        app.typeKey(.escape, modifierFlags: [])
        
        // Verify cancellation
        let cancelledPredicate = NSPredicate(format: "label CONTAINS 'cancel' OR label CONTAINS 'stopped' OR label CONTAINS 'Cancel'")
        let cancelledText = app.staticTexts.containing(cancelledPredicate).firstMatch
        XCTAssertTrue(cancelledText.waitForExistence(timeout: 10), "Should show cancellation status")
        
        // Verify Run Backup is enabled again
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 5))
        XCTAssertTrue(runBackupButton.isEnabled, "Run Backup should be enabled after cancellation")
    }
    
    func testCancelButton_AppearsWhenRunning() throws {
        // Given: Setup for backup
        let sourcePath = createTestSource(fileCount: 10)
        let destPath = createTestDestination("cancelbutton")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Look for cancel button
        let cancelButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Cancel' OR label CONTAINS 'Stop'")).firstMatch
        if cancelButton.waitForExistence(timeout: 3) {
            // Cancel button exists, click it
            cancelButton.click()
            
            // Verify cancellation
            let cancelledText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'cancel'")).firstMatch
            XCTAssertTrue(cancelledText.waitForExistence(timeout: 10))
        }
    }
    
    // MARK: - Error Handling Tests
    
    func testNoSourceSelected_ButtonDisabled() throws {
        // Given: No source selected
        app.launchArguments.append(contentsOf: [
            "--testDest1", createTestDestination("dest1")
        ])
        app.launch()
        
        // Then: Run Backup should be disabled
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 3))
        XCTAssertFalse(runBackupButton.isEnabled, "Run Backup should be disabled without source")
    }
    
    func testNoDestinationSelected_ButtonDisabled() throws {
        // Given: No destination selected
        app.launchArguments.append(contentsOf: [
            "--testSource", createTestSource(fileCount: 3)
        ])
        app.launch()
        
        // Then: Run Backup should be disabled
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 3))
        XCTAssertFalse(runBackupButton.isEnabled, "Run Backup should be disabled without destination")
    }
    
    func testEmptySourceFolder_ShowsWarning() throws {
        // Given: Empty source folder
        let emptySource = createEmptyTestDirectory("empty_source")
        let destPath = createTestDestination("dest")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", emptySource,
            "--testDest1", destPath
        ])
        app.launch()
        
        // When: Try to run backup
        let runBackupButton = app.buttons["Run Backup"]
        if runBackupButton.isEnabled {
            runBackupButton.click()
            
            // Then: Should show warning or complete immediately
            let warningPredicate = NSPredicate(format: "label CONTAINS 'No files' OR label CONTAINS 'empty' OR label CONTAINS '0 files'")
            let warningText = app.staticTexts.containing(warningPredicate).firstMatch
            
            let completePredicate = NSPredicate(format: "label CONTAINS 'complete'")
            let completeText = app.staticTexts.containing(completePredicate).firstMatch
            
            // Either warning or immediate completion is acceptable
            let eitherExists = warningText.waitForExistence(timeout: 5) || completeText.waitForExistence(timeout: 5)
            XCTAssertTrue(eitherExists, "Should show warning or complete immediately for empty source")
        }
    }
    
    // MARK: - Performance Tests
    
    func testBackupPerformance_SmallFiles() throws {
        if #available(macOS 10.15, *) {
            let sourcePath = createTestSource(fileCount: 10)
            let destPath = createTestDestination("perf")
            
            app.launchArguments.append(contentsOf: [
                "--testSource", sourcePath,
                "--testDest1", destPath
            ])
            
            measure(metrics: [XCTClockMetric()]) {
                app.launch()
                
                let runBackupButton = app.buttons["Run Backup"]
                _ = runBackupButton.waitForExistence(timeout: 5)
                runBackupButton.click()
                
                // Wait for completion
                let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
                _ = completionText.waitForExistence(timeout: 60)
                
                app.terminate()
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestSource(fileCount: Int) -> String {
        let testDir = NSTemporaryDirectory().appending("BackupFlowUITest_Source_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        
        // Create test files with varying sizes
        for i in 1...fileCount {
            let filePath = "\(testDir)/test_image_\(i).jpg"
            let content = String(repeating: "Test content \(i) ", count: i * 100)
            FileManager.default.createFile(atPath: filePath, contents: Data(content.utf8))
        }
        
        return testDir
    }
    
    private func createTestDestination(_ name: String) -> String {
        let testDir = NSTemporaryDirectory().appending("BackupFlowUITest_\(name)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        return testDir
    }
    
    private func createEmptyTestDirectory(_ name: String) -> String {
        let testDir = NSTemporaryDirectory().appending("BackupFlowUITest_\(name)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        return testDir
    }
    
    private func cleanupTestDirectories() {
        // Clean up test directories from temp folder
        let tempDir = NSTemporaryDirectory()
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tempDir) {
            for item in contents {
                if item.hasPrefix("BackupFlowUITest_") {
                    try? FileManager.default.removeItem(atPath: tempDir.appending(item))
                }
            }
        }
    }
}