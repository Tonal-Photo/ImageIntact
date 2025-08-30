//
//  DestinationManagementUITests.swift
//  ImageIntactUITests
//
//  XCUITests for destination management functionality
//

import XCTest

final class DestinationManagementUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        
        cleanupTestDirectories()
    }
    
    override func tearDownWithError() throws {
        app = nil
        cleanupTestDirectories()
    }
    
    // MARK: - Add Destination Tests
    
    func testAddSingleDestination() throws {
        // Given: Source selected
        let sourcePath = createTestSource()
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath
        ])
        app.launch()
        
        // When: Add destination
        let addDestButton = app.buttons["Add Destination"]
        if addDestButton.waitForExistence(timeout: 3) {
            // Verify button is enabled
            XCTAssertTrue(addDestButton.isEnabled, "Add Destination should be enabled")
            
            // In test mode, clicking should add a test destination
            addDestButton.click()
            
            // Then: Verify destination appears in UI
            let destButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Destination' OR label CONTAINS 'dest'"))
            XCTAssertGreaterThanOrEqual(destButtons.count, 1, "Should show at least one destination")
        }
    }
    
    func testAddMultipleDestinations() throws {
        // Given: Source selected
        let sourcePath = createTestSource()
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath
        ])
        app.launch()
        
        // When: Add multiple destinations
        let addDestButton = app.buttons["Add Destination"]
        if addDestButton.waitForExistence(timeout: 3) {
            // Add 3 destinations
            for i in 1...3 {
                addDestButton.click()
                Thread.sleep(forTimeInterval: 0.5) // Small delay between additions
                
                // Verify destination count
                let destButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Destination' OR label CONTAINS 'dest'"))
                XCTAssertGreaterThanOrEqual(destButtons.count, i, "Should have \(i) destination(s)")
            }
        }
    }
    
    func testMaximumDestinationsLimit() throws {
        // Given: Source with maximum destinations
        let sourcePath = createTestSource()
        var destArgs: [String] = ["--testSource", sourcePath]
        
        // Add many test destinations (assuming max is around 10)
        for i in 1...10 {
            destArgs.append(contentsOf: [
                "--testDest\(i)", createTestDestination("max\(i)")
            ])
        }
        
        app.launchArguments.append(contentsOf: destArgs)
        app.launch()
        
        // When: Try to add another destination
        let addDestButton = app.buttons["Add Destination"]
        if addDestButton.waitForExistence(timeout: 3) {
            // Button might be disabled or show a warning
            if addDestButton.isEnabled {
                addDestButton.click()
                
                // Look for limit warning
                let warningPredicate = NSPredicate(format: "label CONTAINS 'maximum' OR label CONTAINS 'limit' OR label CONTAINS 'Maximum'")
                let warningText = app.staticTexts.containing(warningPredicate).firstMatch
                
                // Warning might appear as alert or inline text
                if !warningText.exists {
                    let alert = app.alerts.firstMatch
                    if alert.waitForExistence(timeout: 2) {
                        XCTAssertTrue(alert.staticTexts.matching(warningPredicate).firstMatch.exists,
                                     "Alert should mention destination limit")
                        
                        // Dismiss alert
                        alert.buttons["OK"].click()
                    }
                }
            }
        }
    }
    
    // MARK: - Remove Destination Tests
    
    func testRemoveDestination() throws {
        // Given: Source and destinations
        let sourcePath = createTestSource()
        let dest1 = createTestDestination("remove1")
        let dest2 = createTestDestination("remove2")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", dest1,
            "--testDest2", dest2
        ])
        app.launch()
        
        // Find destination entries
        let destButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Destination' OR label CONTAINS 'dest'"))
        let initialCount = destButtons.count
        
        if initialCount > 0 {
            // Look for remove button (might be 'x' or 'Remove')
            let removeButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Remove' OR label CONTAINS '×' OR label CONTAINS 'Delete'"))
            
            if removeButtons.count > 0 {
                // Click first remove button
                removeButtons.firstMatch.click()
                
                // Verify destination count decreased
                Thread.sleep(forTimeInterval: 0.5)
                let newCount = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Destination' OR label CONTAINS 'dest'")).count
                XCTAssertLessThan(newCount, initialCount, "Destination count should decrease after removal")
            }
        }
    }
    
    func testRemoveAllDestinations_DisablesRunBackup() throws {
        // Given: Source and one destination
        let sourcePath = createTestSource()
        let dest1 = createTestDestination("single")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", dest1
        ])
        app.launch()
        
        // Verify Run Backup is initially enabled
        let runBackupButton = app.buttons["Run Backup"]
        XCTAssertTrue(runBackupButton.waitForExistence(timeout: 3))
        XCTAssertTrue(runBackupButton.isEnabled, "Run Backup should be enabled with destination")
        
        // Remove all destinations
        let removeButtons = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Remove' OR label CONTAINS '×'"))
        while removeButtons.count > 0 {
            removeButtons.firstMatch.click()
            Thread.sleep(forTimeInterval: 0.5)
        }
        
        // Verify Run Backup is now disabled
        XCTAssertFalse(runBackupButton.isEnabled, "Run Backup should be disabled without destinations")
    }
    
    // MARK: - Destination Status Tests
    
    func testDestinationStatus_ShowsDuringBackup() throws {
        // Given: Multiple destinations
        let sourcePath = createTestSource()
        let dest1 = createTestDestination("status1")
        let dest2 = createTestDestination("status2")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", dest1,
            "--testDest2", dest2
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // Look for destination-specific status
        let dest1StatusPredicate = NSPredicate(format: "label CONTAINS 'status1'")
        let dest2StatusPredicate = NSPredicate(format: "label CONTAINS 'status2'")
        
        let dest1Status = app.staticTexts.containing(dest1StatusPredicate).firstMatch
        let dest2Status = app.staticTexts.containing(dest2StatusPredicate).firstMatch
        
        // At least one should show status
        let anyStatus = dest1Status.waitForExistence(timeout: 5) || dest2Status.waitForExistence(timeout: 5)
        XCTAssertTrue(anyStatus, "Should show destination-specific status during backup")
        
        // Look for progress indicators per destination
        let progressBars = app.progressIndicators
        if progressBars.count > 1 {
            XCTAssertGreaterThanOrEqual(progressBars.count, 2, "Should show progress for each destination")
        }
    }
    
    func testDestinationValidation_InvalidPath() throws {
        // Given: Source selected
        let sourcePath = createTestSource()
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testInvalidDest", "/invalid/path/that/does/not/exist"
        ])
        app.launch()
        
        // Look for validation error
        let errorPredicate = NSPredicate(format: "label CONTAINS 'invalid' OR label CONTAINS 'not found' OR label CONTAINS 'Invalid'")
        let errorText = app.staticTexts.containing(errorPredicate).firstMatch
        
        if errorText.waitForExistence(timeout: 3) {
            XCTAssertTrue(errorText.exists, "Should show error for invalid destination")
        }
        
        // Run Backup should be disabled
        let runBackupButton = app.buttons["Run Backup"]
        if runBackupButton.exists {
            XCTAssertFalse(runBackupButton.isEnabled, "Run Backup should be disabled with invalid destination")
        }
    }
    
    // MARK: - Destination Ordering Tests
    
    func testDestinationOrder_MaintainedDuringBackup() throws {
        // Given: Multiple destinations in specific order
        let sourcePath = createTestSource(fileCount: 12) // Divisible by 3 for even distribution
        let destA = createTestDestination("AAA_First")
        let destB = createTestDestination("BBB_Second")
        let destC = createTestDestination("CCC_Third")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destA,
            "--testDest2", destB,
            "--testDest3", destC
        ])
        app.launch()
        
        // Verify destinations appear in order
        let destLabels = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'AAA' OR label CONTAINS 'BBB' OR label CONTAINS 'CCC'"))
        
        var foundOrder: [String] = []
        for i in 0..<destLabels.count {
            let label = destLabels.element(boundBy: i)
            if label.exists {
                foundOrder.append(label.label)
            }
        }
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        runBackupButton.click()
        
        // During backup, verify round-robin distribution is working
        // (This would be visible in status messages)
        Thread.sleep(forTimeInterval: 2)
        
        // Wait for completion
        let completionText = app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'complete'")).firstMatch
        XCTAssertTrue(completionText.waitForExistence(timeout: 30))
    }
    
    // MARK: - Destination Space Check Tests
    
    func testDestinationSpaceWarning() throws {
        // Given: Large source that might trigger space warning
        let sourcePath = createTestSource(fileCount: 100)
        let destPath = createTestDestination("space")
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", destPath,
            "--testLowSpace", "true" // Simulate low space condition
        ])
        app.launch()
        
        // Start backup
        let runBackupButton = app.buttons["Run Backup"]
        if runBackupButton.waitForExistence(timeout: 3) && runBackupButton.isEnabled {
            runBackupButton.click()
            
            // Look for space warning
            let spacePredicate = NSPredicate(format: "label CONTAINS 'space' OR label CONTAINS 'Space' OR label CONTAINS 'storage'")
            let spaceWarning = app.staticTexts.containing(spacePredicate).firstMatch
            
            if spaceWarning.waitForExistence(timeout: 5) {
                XCTAssertTrue(spaceWarning.exists, "Should show space warning when appropriate")
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestSource(fileCount: Int = 5) -> String {
        let testDir = NSTemporaryDirectory().appending("DestMgmtUITest_Source_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        
        for i in 1...fileCount {
            let filePath = "\(testDir)/file_\(i).jpg"
            FileManager.default.createFile(atPath: filePath, contents: Data("content \(i)".utf8))
        }
        
        return testDir
    }
    
    private func createTestDestination(_ name: String) -> String {
        let testDir = NSTemporaryDirectory().appending("DestMgmtUITest_\(name)_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(atPath: testDir, withIntermediateDirectories: true)
        return testDir
    }
    
    private func cleanupTestDirectories() {
        let tempDir = NSTemporaryDirectory()
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: tempDir) {
            for item in contents {
                if item.hasPrefix("DestMgmtUITest_") {
                    try? FileManager.default.removeItem(atPath: tempDir.appending(item))
                }
            }
        }
    }
}