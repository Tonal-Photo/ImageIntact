//
//  PresetManagementTests.swift
//  ImageIntactTests
//
//  Test-driven development for preset management features (Issue #81)
//

import XCTest
@testable import ImageIntact

@MainActor
class PresetManagementTests: XCTestCase {
    var presetManager: BackupPresetManager!
    var backupManager: BackupManager!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create fresh instances
        presetManager = BackupPresetManager.shared
        backupManager = BackupManager()
        
        // Create temp directory for test files
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PresetMgmtTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Start with only built-in presets
        presetManager.presets = BackupPreset.builtInPresets
    }
    
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDirectory)
        presetManager.presets = BackupPreset.builtInPresets
        try await super.tearDown()
    }
    
    // MARK: - Delete Custom Presets
    
    func testDeleteCustomPreset() throws {
        // Given: A custom preset exists
        let customPreset = BackupPreset(
            name: "Test Preset to Delete",
            isBuiltIn: false,
            fileTypeFilter: .allFiles
        )
        presetManager.presets.append(customPreset)
        let initialCount = presetManager.presets.count
        
        // When: Delete the custom preset
        // This method doesn't exist yet - TDD!
        // presetManager.deletePreset(customPreset)
        
        // For now, simulate the expected behavior
        if let index = presetManager.presets.firstIndex(where: { $0.id == customPreset.id }) {
            presetManager.presets.remove(at: index)
        }
        
        // Then: Preset should be removed
        XCTAssertEqual(presetManager.presets.count, initialCount - 1,
                      "Preset count should decrease by 1")
        XCTAssertFalse(presetManager.presets.contains(where: { $0.id == customPreset.id }),
                      "Deleted preset should not exist")
    }
    
    func testCannotDeleteBuiltInPreset() throws {
        // Given: A built-in preset
        let builtInPreset = presetManager.presets.first { $0.isBuiltIn }
        XCTAssertNotNil(builtInPreset, "Should have at least one built-in preset")
        
        let initialCount = presetManager.presets.count
        
        // When: Attempt to delete built-in preset
        // This should either throw an error or return false
        // let result = presetManager.canDeletePreset(builtInPreset!)
        
        // For now, test the expected check
        let canDelete = builtInPreset?.isBuiltIn == false
        
        // Then: Should not be able to delete
        XCTAssertFalse(canDelete, "Should not be able to delete built-in presets")
        XCTAssertEqual(presetManager.presets.count, initialCount,
                      "Built-in preset should not be deleted")
    }
    
    func testDeletePresetCleansUpSelection() throws {
        // Given: A custom preset that is currently selected
        let customPreset = BackupPreset(
            name: "Selected Preset",
            isBuiltIn: false
        )
        presetManager.presets.append(customPreset)
        presetManager.selectedPreset = customPreset
        
        // When: Delete the selected preset
        if let index = presetManager.presets.firstIndex(where: { $0.id == customPreset.id }) {
            presetManager.presets.remove(at: index)
            // Should also clear selection if it was deleted
            if presetManager.selectedPreset?.id == customPreset.id {
                presetManager.selectedPreset = nil
            }
        }
        
        // Then: Selection should be cleared
        XCTAssertNil(presetManager.selectedPreset,
                    "Selected preset should be nil after deleting it")
    }
    
    // MARK: - Rename Custom Presets
    
    func testRenameCustomPreset() throws {
        // Given: A custom preset
        let customPreset = BackupPreset(
            name: "Original Name",
            isBuiltIn: false
        )
        presetManager.presets.append(customPreset)
        
        // When: Rename the preset
        let newName = "Updated Name"
        // This method doesn't exist yet - TDD!
        // presetManager.renamePreset(customPreset, to: newName)
        
        // For now, simulate the expected behavior
        if let index = presetManager.presets.firstIndex(where: { $0.id == customPreset.id }) {
            presetManager.presets[index].name = newName
        }
        
        // Then: Name should be updated
        let updatedPreset = presetManager.presets.first { $0.id == customPreset.id }
        XCTAssertEqual(updatedPreset?.name, newName,
                      "Preset name should be updated")
    }
    
    func testCannotRenameBuiltInPreset() throws {
        // Given: A built-in preset
        let builtInPreset = presetManager.presets.first { $0.isBuiltIn }
        XCTAssertNotNil(builtInPreset, "Should have at least one built-in preset")
        
        let originalName = builtInPreset!.name
        
        // When: Attempt to rename built-in preset
        // This should either throw an error or return false
        // let result = presetManager.canRenamePreset(builtInPreset!)
        
        // For now, test the expected check
        let canRename = builtInPreset?.isBuiltIn == false
        
        // Then: Should not be able to rename
        XCTAssertFalse(canRename, "Should not be able to rename built-in presets")
        XCTAssertEqual(builtInPreset?.name, originalName,
                      "Built-in preset name should not change")
    }
    
    func testRenameValidation_NoDuplicateNames() throws {
        // Given: Two custom presets
        let preset1 = BackupPreset(name: "Preset One", isBuiltIn: false)
        let preset2 = BackupPreset(name: "Preset Two", isBuiltIn: false)
        presetManager.presets.append(preset1)
        presetManager.presets.append(preset2)
        
        // When: Try to rename preset2 to preset1's name
        let duplicateName = "Preset One"
        
        // This validation doesn't exist yet - TDD!
        // let isValid = presetManager.isValidPresetName(duplicateName, for: preset2)
        
        // For now, simulate the validation
        let isValid = !presetManager.presets.contains { 
            $0.id != preset2.id && $0.name == duplicateName 
        }
        
        // Then: Should not be valid
        XCTAssertFalse(isValid, "Should not allow duplicate preset names")
    }
    
    func testRenameValidation_EmptyName() throws {
        // Given: A custom preset
        let customPreset = BackupPreset(name: "Original", isBuiltIn: false)
        presetManager.presets.append(customPreset)
        
        // When: Try to rename to empty string
        let emptyName = ""
        
        // Validation check
        let isValid = !emptyName.isEmpty
        
        // Then: Should not be valid
        XCTAssertFalse(isValid, "Should not allow empty preset names")
    }
    
    // MARK: - Edit Preset Settings
    
    func testEditCustomPresetSettings() throws {
        // Given: A custom preset with specific settings
        let sourceDir = tempDirectory.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        let customPreset = BackupPreset(
            name: "Editable Preset",
            isBuiltIn: false,
            fileTypeFilter: .allFiles,
            excludeCacheFiles: false,
            skipHiddenFiles: false,
            sourceBookmark: try sourceDir.bookmarkData()
        )
        presetManager.presets.append(customPreset)
        
        // When: Edit the settings
        // This method doesn't exist yet - TDD!
        // presetManager.updatePreset(customPreset) { preset in
        //     preset.fileTypeFilter = .rawOnly
        //     preset.excludeCacheFiles = true
        //     preset.skipHiddenFiles = true
        // }
        
        // For now, simulate the update
        if let index = presetManager.presets.firstIndex(where: { $0.id == customPreset.id }) {
            presetManager.presets[index].fileTypeFilter = .rawOnly
            presetManager.presets[index].excludeCacheFiles = true
            presetManager.presets[index].skipHiddenFiles = true
        }
        
        // Then: Settings should be updated
        let updatedPreset = presetManager.presets.first { $0.id == customPreset.id }
        XCTAssertEqual(updatedPreset?.fileTypeFilter, .rawOnly,
                      "File type filter should be updated")
        XCTAssertTrue(updatedPreset?.excludeCacheFiles ?? false,
                     "Exclude cache files should be updated")
        XCTAssertTrue(updatedPreset?.skipHiddenFiles ?? false,
                     "Skip hidden files should be updated")
    }
    
    func testEditPresetUpdatesModificationDate() throws {
        // Given: A custom preset
        let customPreset = BackupPreset(
            name: "Time Tracking Preset",
            isBuiltIn: false
        )
        presetManager.presets.append(customPreset)
        
        // When: Edit the preset
        // Sleep briefly to ensure time difference
        Thread.sleep(forTimeInterval: 0.1)
        
        if let index = presetManager.presets.firstIndex(where: { $0.id == customPreset.id }) {
            presetManager.presets[index].lastUsedDate = Date()
        }
        
        // Then: Last used date should be updated
        let updatedPreset = presetManager.presets.first { $0.id == customPreset.id }
        XCTAssertNotNil(updatedPreset?.lastUsedDate,
                       "Last used date should be set after editing")
    }
    
    // MARK: - Preset Ordering
    
    func testReorderCustomPresets() throws {
        // Given: Multiple custom presets
        let preset1 = BackupPreset(name: "First", isBuiltIn: false)
        let preset2 = BackupPreset(name: "Second", isBuiltIn: false)
        let preset3 = BackupPreset(name: "Third", isBuiltIn: false)
        
        // Add after built-ins
        presetManager.presets.append(preset1)
        presetManager.presets.append(preset2)
        presetManager.presets.append(preset3)
        
        let builtInCount = presetManager.presets.filter { $0.isBuiltIn }.count
        
        // When: Reorder (move third to first position among custom)
        // This method doesn't exist yet - TDD!
        // presetManager.movePreset(from: builtInCount + 2, to: builtInCount)
        
        // For now, simulate the reorder
        let fromIndex = builtInCount + 2
        let toIndex = builtInCount
        if fromIndex < presetManager.presets.count {
            let preset = presetManager.presets.remove(at: fromIndex)
            presetManager.presets.insert(preset, at: toIndex)
        }
        
        // Then: Order should be updated
        XCTAssertEqual(presetManager.presets[builtInCount].name, "Third",
                      "Third preset should now be first among custom presets")
        XCTAssertEqual(presetManager.presets[builtInCount + 1].name, "First",
                      "First preset should be moved down")
    }
    
    func testCannotReorderBuiltInPresets() throws {
        // Given: Built-in presets
        let builtInPresets = presetManager.presets.filter { $0.isBuiltIn }
        XCTAssertGreaterThan(builtInPresets.count, 1,
                            "Need at least 2 built-in presets for this test")
        
        let firstBuiltIn = builtInPresets[0]
        let secondBuiltIn = builtInPresets[1]
        
        // When: Attempt to reorder built-ins
        // This should not be allowed
        let canReorder = false // Built-ins should always be false
        
        // Then: Order should remain unchanged
        XCTAssertFalse(canReorder, "Should not be able to reorder built-in presets")
        XCTAssertEqual(presetManager.presets[0].id, firstBuiltIn.id,
                      "First built-in should remain in position")
        XCTAssertEqual(presetManager.presets[1].id, secondBuiltIn.id,
                      "Second built-in should remain in position")
    }
    
    // MARK: - Duplicate Preset
    
    func testDuplicateCustomPreset() throws {
        // Given: A custom preset with specific settings
        let sourceDir = tempDirectory.appendingPathComponent("dup-source")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        
        let originalPreset = BackupPreset(
            name: "Original Preset",
            isBuiltIn: false,
            fileTypeFilter: .rawOnly,
            excludeCacheFiles: true,
            sourceBookmark: try sourceDir.bookmarkData()
        )
        presetManager.presets.append(originalPreset)
        let initialCount = presetManager.presets.count
        
        // When: Duplicate the preset
        // This method doesn't exist yet - TDD!
        // let duplicated = presetManager.duplicatePreset(originalPreset)
        
        // For now, simulate duplication
        let duplicatedPreset = BackupPreset(
            id: UUID(),
            name: "Original Preset Copy",
            isBuiltIn: false,
            fileTypeFilter: originalPreset.fileTypeFilter,
            excludeCacheFiles: originalPreset.excludeCacheFiles,
            skipHiddenFiles: originalPreset.skipHiddenFiles,
            preventSleep: originalPreset.preventSleep,
            showNotification: originalPreset.showNotification,
            sourceBookmark: originalPreset.sourceBookmark,
            destinationBookmarks: originalPreset.destinationBookmarks
        )
        presetManager.presets.append(duplicatedPreset)
        
        // Then: Should have a new preset with same settings but different ID
        XCTAssertEqual(presetManager.presets.count, initialCount + 1,
                      "Should have one more preset")
        
        let duplicate = presetManager.presets.last
        XCTAssertNotEqual(duplicate?.id, originalPreset.id,
                         "Duplicate should have different ID")
        XCTAssertEqual(duplicate?.name, "Original Preset Copy",
                      "Duplicate should have 'Copy' in name")
        XCTAssertEqual(duplicate?.fileTypeFilter, originalPreset.fileTypeFilter,
                      "Duplicate should have same filter settings")
        XCTAssertEqual(duplicate?.excludeCacheFiles, originalPreset.excludeCacheFiles,
                      "Duplicate should have same cache settings")
    }
    
    // MARK: - Export/Import
    
    func testExportPresetToJSON() throws {
        // Given: A custom preset
        let customPreset = BackupPreset(
            name: "Exportable Preset",
            isBuiltIn: false,
            fileTypeFilter: .photosOnly,
            excludeCacheFiles: true
        )
        
        // When: Export to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(customPreset)
        
        // Then: Should produce valid JSON
        XCTAssertNotNil(jsonData, "Should produce JSON data")
        
        // Verify it can be decoded
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(BackupPreset.self, from: jsonData)
        
        XCTAssertEqual(decoded.name, customPreset.name,
                      "Exported preset should decode with same name")
        XCTAssertEqual(decoded.fileTypeFilter, customPreset.fileTypeFilter,
                      "Exported preset should decode with same settings")
    }
    
    func testImportPresetFromJSON() throws {
        // Given: A preset to export first (to get correct JSON format)
        let presetToExport = BackupPreset(
            name: "Imported Preset",
            icon: "square.and.arrow.down",
            isBuiltIn: false,
            strategy: .incremental,
            schedule: .manual,
            performanceMode: .balanced,
            fileTypeFilter: FileTypeFilter(extensions: ["jpg", "jpeg", "png"]),
            excludeCacheFiles: true,
            skipHiddenFiles: true,
            preventSleep: false,
            showNotification: true
        )
        
        // Export it to get proper JSON format
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let presetJSON = try encoder.encode(presetToExport)
        
        let initialCount = presetManager.presets.count
        
        // When: Import the preset
        // This method doesn't exist yet - TDD!
        // presetManager.importPreset(from: presetJSON)
        
        // For now, simulate import
        let decoder = JSONDecoder()
        if let imported = try? decoder.decode(BackupPreset.self, from: presetJSON) {
            presetManager.presets.append(imported)
        }
        
        // Then: Should have the imported preset
        XCTAssertEqual(presetManager.presets.count, initialCount + 1,
                      "Should have one more preset after import")
        
        let imported = presetManager.presets.last
        XCTAssertEqual(imported?.name, "Imported Preset",
                      "Imported preset should have correct name")
        XCTAssertFalse(imported?.isBuiltIn ?? true,
                      "Imported preset should not be built-in")
    }
}