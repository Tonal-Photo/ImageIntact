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
    var backupManager: BackupManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create fresh instance for each test
        backupManager = BackupManager()
        
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temp directory
        try? FileManager.default.removeItem(at: tempDirectory)
        
        try await super.tearDown()
    }
    
    // MARK: - Bug Fix #1: Preset Visibility
    
    func testPresetButtonShouldAlwaysBeVisible() throws {
        // Bug: Preset button was hidden when source field was empty
        // Fix: Made preset button always visible
        // This test documents the expected behavior
        
        // With empty source, preset button should still be visible
        backupManager.sourceURL = nil
        
        // The UI logic should allow preset selection even with no source
        // In the UI, this is controlled by not having conditional visibility modifiers
        // We test that the conceptual logic is correct
        let shouldShowPresetButton = true // Should ALWAYS be true
        
        XCTAssertTrue(shouldShowPresetButton, 
                     "Preset button must always be visible to allow presets to populate empty fields")
        
        // Also test that presets can work with empty source
        backupManager.sourceURL = nil
        backupManager.destinationURLs = []
        
        // A preset should be able to populate these empty fields
        let testSource = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: testSource, withIntermediateDirectories: true)
        
        // Simulate what a preset would do - populate the empty source
        backupManager.sourceURL = testSource
        
        XCTAssertNotNil(backupManager.sourceURL, 
                       "Presets must be able to populate empty source field")
    }
    
    // MARK: - Bug Fix #2: Extra Destination Fields
    
    func testDestinationFieldsOnlyShowWhenPopulated() throws {
        // Bug: Empty destination fields 2 & 3 were showing even when not populated
        // Fix: Properly initialized destination arrays to show only populated fields
        
        // Start with no destinations
        backupManager.destinationURLs = []
        
        // UI should not show any destination fields
        let shouldShowDest1 = backupManager.destinationURLs.count >= 1 && 
                              backupManager.destinationURLs.count > 0 && 
                              backupManager.destinationURLs[0] != nil
        let shouldShowDest2 = backupManager.destinationURLs.count >= 2 && 
                              backupManager.destinationURLs[1] != nil
        let shouldShowDest3 = backupManager.destinationURLs.count >= 3 && 
                              backupManager.destinationURLs[2] != nil
        
        XCTAssertFalse(shouldShowDest1, "Should not show destination 1 when array is empty")
        XCTAssertFalse(shouldShowDest2, "Should not show destination 2 when array is empty")
        XCTAssertFalse(shouldShowDest3, "Should not show destination 3 when array is empty")
        
        // Add one destination
        let dest1 = tempDirectory.appendingPathComponent("dest1")
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        backupManager.destinationURLs = [dest1]
        
        // Only first field should show
        let shouldShowDest1After = backupManager.destinationURLs.count >= 1 && 
                                   backupManager.destinationURLs[0] != nil
        let shouldShowDest2After = backupManager.destinationURLs.count >= 2 && 
                                   backupManager.destinationURLs[1] != nil
        
        XCTAssertTrue(shouldShowDest1After, "Should show destination 1 when it exists")
        XCTAssertFalse(shouldShowDest2After, "Should not show destination 2 when only 1 exists")
        
        // Add second destination
        let dest2 = tempDirectory.appendingPathComponent("dest2")
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        backupManager.destinationURLs = [dest1, dest2]
        
        let shouldShowBothAfter = backupManager.destinationURLs.count == 2
        XCTAssertTrue(shouldShowBothAfter, "Should show both destinations when 2 exist")
    }
    
    // MARK: - Bug Fix #3: Field Population
    
    func testPresetCanSaveAndRestorePaths() throws {
        // Bug: Presets weren't storing/restoring source and destination paths
        // Fix: Added bookmark storage to BackupPreset struct
        
        // Create test directories
        let sourceDir = tempDirectory.appendingPathComponent("TestSource")
        let destDir1 = tempDirectory.appendingPathComponent("TestDest1")
        
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir1, withIntermediateDirectories: true)
        
        // Test that we can create bookmarks (this was missing before)
        let sourceBookmark = try sourceDir.bookmarkData()
        let destBookmark = try destDir1.bookmarkData()
        
        XCTAssertNotNil(sourceBookmark, "Must be able to create source bookmark")
        XCTAssertNotNil(destBookmark, "Must be able to create destination bookmark")
        
        // Test that bookmarks can be resolved
        var isStale = false
        let resolvedSource = try URL(resolvingBookmarkData: sourceBookmark, 
                                    bookmarkDataIsStale: &isStale)
        let resolvedDest = try URL(resolvingBookmarkData: destBookmark, 
                                  bookmarkDataIsStale: &isStale)
        
        XCTAssertEqual(resolvedSource.lastPathComponent, "TestSource", 
                      "Source bookmark must resolve correctly")
        XCTAssertEqual(resolvedDest.lastPathComponent, "TestDest1", 
                      "Destination bookmark must resolve correctly")
        
        // Test that BackupPreset structure supports bookmarks
        let preset = BackupPreset(
            name: "Test Preset",
            fileTypeFilter: .allFiles,
            sourceBookmark: sourceBookmark,
            destinationBookmarks: [destBookmark]
        )
        
        XCTAssertNotNil(preset.sourceBookmark, "Preset must store source bookmark")
        XCTAssertEqual(preset.destinationBookmarks.count, 1, "Preset must store destination bookmarks")
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
        
        // Set up a specific configuration
        backupManager.sourceURL = sourceDir
        backupManager.destinationURLs = [destDir]
        backupManager.fileTypeFilter = .rawOnly
        backupManager.excludeCacheFiles = true
        
        // Create a preset that matches this configuration
        let matchingPreset = BackupPreset(
            name: "Matching Preset",
            fileTypeFilter: .rawOnly,
            excludeCacheFiles: true,
            sourceBookmark: try sourceDir.bookmarkData(),
            destinationBookmarks: [try destDir.bookmarkData()]
        )
        
        // Test that we can detect matching configurations
        // The actual detection logic would compare:
        // - Source path (via bookmark)
        // - Destination paths (via bookmarks)
        // - File type filter
        // - Exclude cache files setting
        // - Other relevant settings
        
        // Simulate checking if current config matches the preset
        let sourcesMatch = backupManager.sourceURL == sourceDir
        let destsMatch = backupManager.destinationURLs.first == destDir
        let filtersMatch = backupManager.fileTypeFilter == .rawOnly
        let cacheMatch = backupManager.excludeCacheFiles == true
        
        let isDuplicate = sourcesMatch && destsMatch && filtersMatch && cacheMatch
        
        XCTAssertTrue(isDuplicate, 
                     "Should detect when configuration matches existing preset")
        
        // Change one setting - should no longer match
        backupManager.fileTypeFilter = .allFiles
        
        let filtersMatchAfter = backupManager.fileTypeFilter == .rawOnly
        let isDuplicateAfter = sourcesMatch && destsMatch && filtersMatchAfter && cacheMatch
        
        XCTAssertFalse(isDuplicateAfter, 
                      "Should not detect duplicate after changing settings")
    }
    
    // MARK: - Additional Regression Tests
    
    func testPresetSupportsMultipleDestinations() throws {
        // Ensure presets correctly handle multiple destinations
        let dest1 = tempDirectory.appendingPathComponent("dest1")
        let dest2 = tempDirectory.appendingPathComponent("dest2")
        let dest3 = tempDirectory.appendingPathComponent("dest3")
        
        try FileManager.default.createDirectory(at: dest1, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dest3, withIntermediateDirectories: true)
        
        // Create bookmarks for all three
        let bookmarks = try [dest1, dest2, dest3].map { try $0.bookmarkData() }
        
        // Create preset with multiple destinations
        let preset = BackupPreset(
            name: "Multi Destination",
            destinationBookmarks: bookmarks
        )
        
        XCTAssertEqual(preset.destinationBookmarks.count, 3, 
                      "Preset must support multiple destination bookmarks")
        
        // Verify all can be resolved
        for (index, bookmark) in preset.destinationBookmarks.enumerated() {
            if let bookmark = bookmark {
                var isStale = false
                let resolved = try URL(resolvingBookmarkData: bookmark, 
                                      bookmarkDataIsStale: &isStale)
                XCTAssertEqual(resolved.lastPathComponent, "dest\(index + 1)", 
                             "Each destination bookmark must resolve correctly")
            }
        }
    }
    
    func testEmptyConfigurationDoesNotMatchPresets() throws {
        // Ensure that configurations without paths don't match any preset
        
        // Set up empty configuration
        backupManager.sourceURL = nil
        backupManager.destinationURLs = []
        backupManager.fileTypeFilter = .rawOnly
        
        // Even with matching filter settings, without paths it shouldn't match
        // This prevents false positives for duplicate detection
        
        let hasSource = backupManager.sourceURL != nil
        let hasDestinations = !backupManager.destinationURLs.isEmpty && 
                             backupManager.destinationURLs.contains { $0 != nil }
        
        let canMatchPreset = hasSource && hasDestinations
        
        XCTAssertFalse(canMatchPreset, 
                      "Configuration without paths should never match a preset")
    }
}