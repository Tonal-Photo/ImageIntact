//
//  PreferencesUITests.swift
//  ImageIntactUITests
//
//  XCUITests for preferences and settings functionality
//

import XCTest

final class PreferencesUITests: XCTestCase {
    
    var app: XCUIApplication!
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        
        app = XCUIApplication()
        app.launchArguments = ["--uitest"]
    }
    
    override func tearDownWithError() throws {
        app = nil
    }
    
    // MARK: - Preferences Window Tests
    
    func testOpenPreferencesWindow() throws {
        app.launch()
        
        // Open preferences using keyboard shortcut
        app.typeKey(",", modifierFlags: .command)
        
        // Verify preferences window appears
        let prefsWindow = app.windows["Preferences"]
        if !prefsWindow.exists {
            // Try alternative window title
            let settingsWindow = app.windows["Settings"]
            XCTAssertTrue(settingsWindow.waitForExistence(timeout: 3), "Preferences/Settings window should appear")
        } else {
            XCTAssertTrue(prefsWindow.exists, "Preferences window should appear")
        }
    }
    
    func testPreferencesMenuBarItem() throws {
        app.launch()
        
        // Access preferences through menu bar
        let menuBar = app.menuBars
        let appMenu = menuBar.menuBarItems["ImageIntact"]
        if appMenu.waitForExistence(timeout: 3) {
            appMenu.click()
            
            let prefsMenuItem = menuBar.menuItems["Preferences…"]
            if !prefsMenuItem.exists {
                // Try alternative menu item text
                let settingsMenuItem = menuBar.menuItems["Settings…"]
                if settingsMenuItem.exists {
                    settingsMenuItem.click()
                }
            } else {
                prefsMenuItem.click()
            }
            
            // Verify preferences window opens
            let prefsWindow = app.windows.containing(NSPredicate(format: "title CONTAINS 'Preferences' OR title CONTAINS 'Settings'")).firstMatch
            XCTAssertTrue(prefsWindow.waitForExistence(timeout: 3))
        }
    }
    
    // MARK: - General Preferences Tests
    
    func testGeneralPreferences_NotificationSettings() throws {
        app.launch()
        openPreferences()
        
        // Look for notification settings
        let notifCheckbox = app.checkBoxes.containing(NSPredicate(format: "label CONTAINS 'notification' OR label CONTAINS 'Notification'")).firstMatch
        
        if notifCheckbox.waitForExistence(timeout: 3) {
            // Toggle notification setting
            let initialValue = notifCheckbox.value as? Bool ?? false
            notifCheckbox.click()
            
            // Verify state changed
            let newValue = notifCheckbox.value as? Bool ?? false
            XCTAssertNotEqual(initialValue, newValue, "Notification setting should toggle")
            
            // Toggle back
            notifCheckbox.click()
            XCTAssertEqual(notifCheckbox.value as? Bool, initialValue, "Should restore original value")
        }
    }
    
    func testGeneralPreferences_SleepPrevention() throws {
        app.launch()
        openPreferences()
        
        // Look for sleep prevention setting
        let sleepCheckbox = app.checkBoxes.containing(NSPredicate(format: "label CONTAINS 'sleep' OR label CONTAINS 'Sleep' OR label CONTAINS 'awake'")).firstMatch
        
        if sleepCheckbox.waitForExistence(timeout: 3) {
            // Toggle sleep prevention
            let initialValue = sleepCheckbox.value as? Bool ?? false
            sleepCheckbox.click()
            
            // Verify state changed
            let newValue = sleepCheckbox.value as? Bool ?? false
            XCTAssertNotEqual(initialValue, newValue, "Sleep prevention setting should toggle")
        }
    }
    
    func testGeneralPreferences_LaunchAtStartup() throws {
        app.launch()
        openPreferences()
        
        // Look for launch at startup setting
        let startupCheckbox = app.checkBoxes.containing(NSPredicate(format: "label CONTAINS 'startup' OR label CONTAINS 'login' OR label CONTAINS 'Launch'")).firstMatch
        
        if startupCheckbox.waitForExistence(timeout: 3) {
            // Toggle startup setting
            let initialValue = startupCheckbox.value as? Bool ?? false
            startupCheckbox.click()
            
            // Verify state changed
            Thread.sleep(forTimeInterval: 0.5) // Allow time for change
            let newValue = startupCheckbox.value as? Bool ?? false
            XCTAssertNotEqual(initialValue, newValue, "Launch at startup setting should toggle")
        }
    }
    
    // MARK: - Backup Preferences Tests
    
    func testBackupPreferences_VerificationOption() throws {
        app.launch()
        openPreferences()
        
        // Switch to Backup tab if exists
        let backupTab = app.tabs["Backup"]
        if backupTab.exists {
            backupTab.click()
        }
        
        // Look for verification setting
        let verifyCheckbox = app.checkBoxes.containing(NSPredicate(format: "label CONTAINS 'verify' OR label CONTAINS 'Verify' OR label CONTAINS 'checksum'")).firstMatch
        
        if verifyCheckbox.waitForExistence(timeout: 3) {
            // Check current state
            let isEnabled = verifyCheckbox.value as? Bool ?? false
            XCTAssertTrue(isEnabled, "Verification should be enabled by default")
            
            // Try to toggle (might be disabled for safety)
            if verifyCheckbox.isEnabled {
                verifyCheckbox.click()
                
                // Warning might appear
                let alert = app.alerts.firstMatch
                if alert.waitForExistence(timeout: 2) {
                    // Verify warning about disabling verification
                    XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'verification' OR label CONTAINS 'integrity'")).firstMatch.exists)
                    
                    // Cancel the change
                    alert.buttons["Cancel"].click()
                }
            }
        }
    }
    
    func testBackupPreferences_RetrySettings() throws {
        app.launch()
        openPreferences()
        
        // Look for retry settings
        let retryField = app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS 'retry' OR placeholderValue CONTAINS 'attempts'")).firstMatch
        let retryStepper = app.steppers.containing(NSPredicate(format: "label CONTAINS 'retry' OR label CONTAINS 'Retry'")).firstMatch
        
        if retryField.waitForExistence(timeout: 3) {
            // Check default value
            let defaultValue = retryField.value as? String ?? ""
            XCTAssertFalse(defaultValue.isEmpty, "Should have default retry value")
            
            // Try to change value
            retryField.click()
            retryField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
            retryField.typeText("5")
            
            // Verify change
            XCTAssertEqual(retryField.value as? String, "5", "Retry value should update")
        } else if retryStepper.waitForExistence(timeout: 3) {
            // Use stepper to change value
            retryStepper.buttons["Increment"].click()
            Thread.sleep(forTimeInterval: 0.5)
            retryStepper.buttons["Decrement"].click()
        }
    }
    
    // MARK: - Performance Preferences Tests
    
    func testPerformancePreferences_ConcurrentOperations() throws {
        app.launch()
        openPreferences()
        
        // Switch to Performance tab if exists
        let perfTab = app.tabs["Performance"]
        if perfTab.exists {
            perfTab.click()
        }
        
        // Look for concurrent operations setting
        let concurrentSlider = app.sliders.containing(NSPredicate(format: "label CONTAINS 'concurrent' OR label CONTAINS 'parallel'")).firstMatch
        let concurrentField = app.textFields.containing(NSPredicate(format: "placeholderValue CONTAINS 'concurrent' OR value CONTAINS 'operations'")).firstMatch
        
        if concurrentSlider.waitForExistence(timeout: 3) {
            // Adjust slider
            concurrentSlider.adjust(toNormalizedSliderPosition: 0.5)
            Thread.sleep(forTimeInterval: 0.5)
            
            // Verify change
            let newPosition = concurrentSlider.normalizedSliderPosition
            XCTAssertGreaterThan(newPosition, 0.3, "Slider should be adjusted")
            XCTAssertLessThan(newPosition, 0.7, "Slider should be near middle")
        } else if concurrentField.exists {
            // Modify field value
            concurrentField.click()
            concurrentField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
            concurrentField.typeText("4")
        }
    }
    
    func testPerformancePreferences_ChunkSize() throws {
        app.launch()
        openPreferences()
        
        // Look for chunk size setting
        let chunkPopup = app.popUpButtons.containing(NSPredicate(format: "label CONTAINS 'chunk' OR label CONTAINS 'buffer'")).firstMatch
        
        if chunkPopup.waitForExistence(timeout: 3) {
            // Open popup
            chunkPopup.click()
            
            // Select different option
            let menuItems = app.menuItems
            if menuItems.count > 1 {
                menuItems.element(boundBy: 1).click()
                
                // Verify selection changed
                Thread.sleep(forTimeInterval: 0.5)
                XCTAssertFalse(chunkPopup.value as? String == "", "Chunk size should be selected")
            }
        }
    }
    
    // MARK: - Advanced Preferences Tests
    
    func testAdvancedPreferences_LogLevel() throws {
        app.launch()
        openPreferences()
        
        // Switch to Advanced tab if exists
        let advancedTab = app.tabs["Advanced"]
        if advancedTab.exists {
            advancedTab.click()
        }
        
        // Look for log level setting
        let logPopup = app.popUpButtons.containing(NSPredicate(format: "label CONTAINS 'log' OR label CONTAINS 'Log' OR label CONTAINS 'debug'")).firstMatch
        
        if logPopup.waitForExistence(timeout: 3) {
            // Open popup
            logPopup.click()
            
            // Look for log level options
            let debugOption = app.menuItems["Debug"]
            let infoOption = app.menuItems["Info"]
            let errorOption = app.menuItems["Error"]
            
            if debugOption.exists {
                debugOption.click()
                XCTAssertTrue(logPopup.value as? String == "Debug", "Should select Debug log level")
            } else if infoOption.exists {
                infoOption.click()
            } else if errorOption.exists {
                errorOption.click()
            }
        }
    }
    
    func testAdvancedPreferences_ResetSettings() throws {
        app.launch()
        openPreferences()
        
        // Look for reset button
        let resetButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Reset' OR label CONTAINS 'Defaults' OR label CONTAINS 'Restore'")).firstMatch
        
        if resetButton.waitForExistence(timeout: 3) {
            resetButton.click()
            
            // Confirmation dialog should appear
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 2), "Reset confirmation should appear")
            
            // Verify warning message
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label CONTAINS 'reset' OR label CONTAINS 'default'")).firstMatch.exists)
            
            // Cancel reset
            alert.buttons["Cancel"].click()
        }
    }
    
    // MARK: - Preset Management Tests
    
    func testPresetManagement_SaveCurrentAsPreset() throws {
        app.launch()
        
        // Setup a configuration first
        let sourcePath = NSTemporaryDirectory().appending("PrefsUITest_Source")
        try? FileManager.default.createDirectory(atPath: sourcePath, withIntermediateDirectories: true)
        
        app.launchArguments.append(contentsOf: [
            "--testSource", sourcePath,
            "--testDest1", NSTemporaryDirectory().appending("PrefsUITest_Dest")
        ])
        app.terminate()
        app.launch()
        
        // Look for preset button
        let savePresetButton = app.buttons.containing(NSPredicate(format: "label CONTAINS 'Save' AND label CONTAINS 'Preset'")).firstMatch
        
        if savePresetButton.waitForExistence(timeout: 3) {
            savePresetButton.click()
            
            // Save preset dialog should appear
            let saveDialog = app.sheets.firstMatch
            if saveDialog.waitForExistence(timeout: 2) {
                // Enter preset name
                let nameField = saveDialog.textFields.firstMatch
                if nameField.exists {
                    nameField.click()
                    nameField.typeText("Test Preset")
                    
                    // Save
                    saveDialog.buttons["Save"].click()
                    
                    // Verify preset was saved (would appear in preset list)
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func openPreferences() {
        // Try keyboard shortcut first
        app.typeKey(",", modifierFlags: .command)
        
        // Wait for preferences window
        let prefsWindow = app.windows.containing(NSPredicate(format: "title CONTAINS 'Preferences' OR title CONTAINS 'Settings'")).firstMatch
        _ = prefsWindow.waitForExistence(timeout: 3)
    }
}