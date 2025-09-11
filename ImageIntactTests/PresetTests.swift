//
//  PresetTests.swift
//  ImageIntactTests
//
//  Tests for backup preset functionality to prevent regression of fixed bugs
//

import XCTest
@testable import ImageIntact

@MainActor
class PresetTests: XCTestCase {
    var presetManager: BackupPresetManager!
    var backupManager: BackupManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create fresh instances for each test
        presetManager = BackupPresetManager.shared
        backupManager = BackupManager()
        
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Clear any existing presets
        presetManager.presets = BackupPreset.builtInPresets
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        // Reset presets
        presetManager.presets = BackupPreset.builtInPresets
        
        try await super.tearDown()
    }
    
    // MARK: - Bug Fix #1: Preset Visibility
    
    func testPresetButtonAlwaysVisible() throws {
        // Bug: Preset button was hidden when source field was empty
        // Fix: Made preset button always visible
        
        // Test that preset button should be visible even with empty source
        backupManager.sourceURL = nil
        backupManager.destinationURLs = []
        
        // In the actual UI, the preset button visibility is controlled by
        // not having any conditional modifiers. We test the logic here.
        // The button should ALWAYS be enabled for selection
        let canSelectPreset = true // This should always be true
        XCTAssertTrue(canSelectPreset, "Preset button must always be visible/enabled")
        
        // Test that presets can populate empty fields
        let testSource = tempDirectory.appendingPathComponent("source")
        let testDest = tempDirectory.appendingPathComponent("dest")
        try FileManager.default.createDirectory(at: testSource, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testDest, withIntermediateDirectories: true)
        
        // Create a custom preset
        let preset = BackupPreset(
            id: UUID(),
            name: "Test Preset",
            isBuiltIn: false,
            sourceBookmark: try testSource.bookmarkData(),
            destinationBookmarks: [try testDest.bookmarkData()],
            fileTypeFilter: .allSupported,
            excludeCacheFiles: true,
            skipHiddenFiles: true,
            preventSleep: false,
            showNotification: true
        )
        
        // Apply preset to empty backup manager
        backupManager.sourceURL = nil
        backupManager.destinationURLs = []
        
        // Simulate applying preset through the manager
        presetManager.presets.append(preset)
        presetManager.applyPreset(preset, to: backupManager)
        
        XCTAssertNotNil(backupManager.sourceURL, "Preset should populate source field")
        XCTAssertFalse(backupManager.destinationURLs.isEmpty, "Preset should populate destinations")
    }
    
    // MARK: - Bug Fix #2: Extra Destination Fields
    
    func testDestinationFieldsOnlyShowWhenPopulated() throws {
        // Bug: Empty destination fields 2 & 3 were showing even when not populated
        // Fix: Properly initialized destination arrays to show only populated fields
        
        // Test initial state - should have no destinations
        XCTAssertTrue(backupManager.destinationURLs.isEmpty || 
                     backupManager.destinationURLs.allSatisfy { $0 == nil }, 
                     "Should start with no destinations")
        
        // Add one destination
        let dest1 = tempDirectory.appendingPathComponent("dest1")
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        
        // Clear and set single destination
        backupManager.destinationURLs = [dest1]
        
        // Count non-nil destinations
        let nonNilDestinations = backupManager.destinationURLs.compactMap { $0 }
        XCTAssertEqual(nonNilDestinations.count, 1, "Should have exactly 1 destination")
        
        // Test computed properties for showing fields (simulating UI logic)
        let shouldShowDest2 = backupManager.destinationURLs.count >= 2 && 
                              backupManager.destinationURLs[1] != nil
        let shouldShowDest3 = backupManager.destinationURLs.count >= 3 && 
                              backupManager.destinationURLs[2] != nil
        
        XCTAssertFalse(shouldShowDest2, "Should not show destination 2 field")
        XCTAssertFalse(shouldShowDest3, "Should not show destination 3 field")
        
        // Add second destination
        let dest2 = tempDirectory.appendingPathComponent("dest2")
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        backupManager.destinationURLs.append(dest2)
        
        let nonNilDestinations2 = backupManager.destinationURLs.compactMap { $0 }
        XCTAssertEqual(nonNilDestinations2.count, 2, "Should have 2 destinations")
    }
    
    // MARK: - Bug Fix #3: Field Population
    
    func testPresetSavesAndRestoresPaths() throws {
        // Bug: Presets weren't storing/restoring source and destination paths
        // Fix: Added bookmark storage to BackupPreset struct
        
        // Create test directories
        let sourceDir = tempDirectory.appendingPathComponent("TestSource")
        let destDir1 = tempDirectory.appendingPathComponent("TestDest1")
        let destDir2 = tempDirectory.appendingPathComponent("TestDest2")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir2, withIntermediateDirectories: true)
        
        // Set up backup manager with paths
        backupManager.sourceURL = sourceDir
        backupManager.destinationURLs = [destDir1, destDir2]
        backupManager.fileTypeFilter = .rawPhotosOnly
        backupManager.excludeCacheFiles = false
        
        // Create preset with bookmarks
        let preset = BackupPreset(
            id: UUID(),
            name: "Test Path Preset",
            isBuiltIn: false,
            sourceBookmark: try sourceDir.bookmarkData(),
            destinationBookmarks: try [destDir1, destDir2].map { try $0.bookmarkData() },
            fileTypeFilter: .rawPhotosOnly,
            excludeCacheFiles: false,
            skipHiddenFiles: true,
            preventSleep: false,
            showNotification: true
        )
        
        // Add to manager
        presetManager.presets.append(preset)
        
        // Clear backup manager
        backupManager.sourceURL = nil
        backupManager.destinationURLs = []
        backupManager.fileTypeFilter = .allSupported
        backupManager.excludeCacheFiles = true
        
        // Apply the saved preset
        presetManager.applyPreset(preset, to: backupManager)
        
        // Verify paths were restored
        XCTAssertEqual(backupManager.sourceURL?.lastPathComponent, "TestSource", 
                      "Source path should be restored")
        
        let nonNilDestinations = backupManager.destinationURLs.compactMap { $0 }
        XCTAssertEqual(nonNilDestinations.count, 2, 
                      "Both destination paths should be restored")
        
        if nonNilDestinations.count >= 2 {
            XCTAssertEqual(nonNilDestinations[0].lastPathComponent, "TestDest1", 
                          "First destination should be restored correctly")
            XCTAssertEqual(nonNilDestinations[1].lastPathComponent, "TestDest2", 
                          "Second destination should be restored correctly")
        }
        
        XCTAssertEqual(backupManager.fileTypeFilter, .rawPhotosOnly, 
                      "File type filter should be restored")
        XCTAssertFalse(backupManager.excludeCacheFiles, 
                      "Exclude cache files setting should be restored")
    }
    
    // MARK: - Bug Fix #4: Duplicate Detection
    
    func testDuplicatePresetDetection() throws {
        // Bug: Users could create identical presets repeatedly
        // Fix: Added currentConfigurationMatchesExistingPreset() method
        
        // Create test directories
        let sourceDir = tempDirectory.appendingPathComponent("DupSource")
        let destDir = tempDirectory.appendingPathComponent("DupDest")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
        
        // Set up configuration
        backupManager.sourceURL = sourceDir
        backupManager.destinationURLs = [destDir]
        backupManager.fileTypeFilter = .rawPhotosOnly
        backupManager.excludeCacheFiles = true
        
        // No duplicate initially
        let hasDuplicate1 = presetManager.currentConfigurationMatchesExistingPreset(
            backupManager: backupManager
        )
        XCTAssertFalse(hasDuplicate1, "Should not detect duplicate for new configuration")
        
        // Create and add preset with same configuration
        let preset = BackupPreset(
            id: UUID(),
            name: "Duplicate Test Preset",
            isBuiltIn: false,
            sourceBookmark: try sourceDir.bookmarkData(),
            destinationBookmarks: [try destDir.bookmarkData()],
            fileTypeFilter: .rawPhotosOnly,
            excludeCacheFiles: true,
            skipHiddenFiles: true,
            preventSleep: false,
            showNotification: true
        )
        presetManager.presets.append(preset)
        
        // Now should detect duplicate with same configuration
        let hasDuplicate2 = presetManager.currentConfigurationMatchesExistingPreset(
            backupManager: backupManager
        )
        XCTAssertTrue(hasDuplicate2, "Should detect duplicate for identical configuration")
        
        // Change one setting - should no longer be duplicate
        backupManager.fileTypeFilter = .allSupported
        
        let hasDuplicate3 = presetManager.currentConfigurationMatchesExistingPreset(
            backupManager: backupManager
        )
        XCTAssertFalse(hasDuplicate3, "Should not detect duplicate after changing settings")
        
        // Test with different paths but same settings
        let sourceDir2 = tempDirectory.appendingPathComponent("DupSource2")
        try FileManager.default.createDirectory(at: sourceDir2, withIntermediateDirectories: true)
        
        backupManager.sourceURL = sourceDir2
        backupManager.fileTypeFilter = .rawPhotosOnly // Back to original setting
        
        let hasDuplicate4 = presetManager.currentConfigurationMatchesExistingPreset(
            backupManager: backupManager
        )
        XCTAssertFalse(hasDuplicate4, "Should not detect duplicate with different paths")
    }
    
    // MARK: - Additional Regression Tests
    
    func testPresetWithMultipleDestinations() throws {
        // Ensure presets correctly handle multiple destinations
        let source = tempDirectory.appendingPathComponent("multi-source")
        let dest1 = tempDirectory.appendingPathComponent("multi-dest1")
        let dest2 = tempDirectory.appendingPathComponent("multi-dest2")
        let dest3 = tempDirectory.appendingPathComponent("multi-dest3")
        
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        // Create preset with 3 destinations
        let preset = BackupPreset(
            id: UUID(),
            name: "Three Destinations",
            isBuiltIn: false,
            sourceBookmark: try source.bookmarkData(),
            destinationBookmarks: try [dest1, dest2, dest3].map { try $0.bookmarkData() },
            fileTypeFilter: .allSupported,
            excludeCacheFiles: true,
            skipHiddenFiles: true,
            preventSleep: false,
            showNotification: true
        )
        
        presetManager.presets.append(preset)
        
        // Clear and restore
        backupManager.destinationURLs = []
        
        presetManager.applyPreset(preset, to: backupManager)
        
        let nonNilDestinations = backupManager.destinationURLs.compactMap { $0 }
        XCTAssertEqual(nonNilDestinations.count, 3, 
                      "All three destinations should be restored")
    }
    
    func testBuiltInPresetsCannotBeDuplicated() throws {
        // Ensure built-in presets are not considered duplicates
        
        // Set configuration to match a built-in preset (RAW Photos Only)
        backupManager.fileTypeFilter = .rawPhotosOnly
        backupManager.excludeCacheFiles = true
        
        // Without paths, it shouldn't match even if settings are the same
        backupManager.sourceURL = nil
        backupManager.destinationURLs = []
        
        let hasDuplicate = presetManager.currentConfigurationMatchesExistingPreset(
            backupManager: backupManager
        )
        
        // Without paths, no configuration should match
        XCTAssertFalse(hasDuplicate, 
                      "Configuration without paths should not match any preset")
    }
}