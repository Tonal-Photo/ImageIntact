@testable import ImageIntact
import XCTest

/// Tests for subdirectory traversal feature
/// When enabled (default): scan all files in source folder and all subdirectories
/// When disabled: only scan files in the top-level source folder
class SubdirectoryTraversalTests: XCTestCase {
    var tempDir: URL!
    var sourceDir: URL!

    override func setUp() async throws {
        try await super.setUp()

        // Create temp directory structure for tests
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SubdirTest_\(UUID().uuidString)")
        sourceDir = tempDir.appendingPathComponent("Source")

        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        // Create test file structure:
        // Source/
        //   root1.jpg
        //   root2.jpg
        //   SubfolderA/
        //     nested1.jpg
        //     nested2.jpg
        //   SubfolderB/
        //     deep/
        //       deep1.jpg

        // Root level files
        try createTestImage(at: sourceDir.appendingPathComponent("root1.jpg"))
        try createTestImage(at: sourceDir.appendingPathComponent("root2.jpg"))

        // Subfolder A with files
        let subfolderA = sourceDir.appendingPathComponent("SubfolderA")
        try FileManager.default.createDirectory(at: subfolderA, withIntermediateDirectories: true)
        try createTestImage(at: subfolderA.appendingPathComponent("nested1.jpg"))
        try createTestImage(at: subfolderA.appendingPathComponent("nested2.jpg"))

        // Subfolder B with deep nesting
        let deepFolder = sourceDir.appendingPathComponent("SubfolderB/deep")
        try FileManager.default.createDirectory(at: deepFolder, withIntermediateDirectories: true)
        try createTestImage(at: deepFolder.appendingPathComponent("deep1.jpg"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    private func createTestImage(at url: URL) throws {
        // Create minimal valid JPEG data
        let jpegData = Data([
            0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01,
            0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xFF, 0xD9,
        ])
        try jpegData.write(to: url)
    }

    // MARK: - Preference Tests

    func testIncludeSubdirectoriesDefaultValue() {
        // Default should be true for backwards compatibility
        let prefs = PreferencesManager.shared

        // Reset to default by removing the key
        UserDefaults.standard.removeObject(forKey: "includeSubdirectories")

        XCTAssertTrue(
            prefs.includeSubdirectories,
            "Default value should be true to maintain backwards compatibility"
        )
    }

    func testIncludeSubdirectoriesPersistence() {
        let prefs = PreferencesManager.shared

        // Set to false
        prefs.includeSubdirectories = false
        XCTAssertFalse(prefs.includeSubdirectories)

        // Set to true
        prefs.includeSubdirectories = true
        XCTAssertTrue(prefs.includeSubdirectories)
    }

    // MARK: - ManifestBuilder Tests

    func testManifestBuilderIncludesSubdirectoriesByDefault() async throws {
        let builder = ManifestBuilder()

        let manifest = await builder.build(
            source: sourceDir,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: true
        )

        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.count, 5, "Should find all 5 files when including subdirectories")

        // Verify we have files from different levels
        let paths = manifest?.map { $0.relativePath } ?? []
        XCTAssertTrue(paths.contains("root1.jpg"))
        XCTAssertTrue(paths.contains("root2.jpg"))
        XCTAssertTrue(paths.contains("SubfolderA/nested1.jpg"))
        XCTAssertTrue(paths.contains("SubfolderA/nested2.jpg"))
        XCTAssertTrue(paths.contains("SubfolderB/deep/deep1.jpg"))
    }

    func testManifestBuilderExcludesSubdirectories() async throws {
        let builder = ManifestBuilder()

        let manifest = await builder.build(
            source: sourceDir,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: false
        )

        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.count, 2, "Should only find 2 root-level files when excluding subdirectories")

        // Verify we only have root level files
        let paths = manifest?.map { $0.relativePath } ?? []
        XCTAssertTrue(paths.contains("root1.jpg"))
        XCTAssertTrue(paths.contains("root2.jpg"))
        XCTAssertFalse(paths.contains { $0.contains("/") }, "Should not contain any nested paths")
    }

    func testManifestBuilderWithEmptySubdirectories() async throws {
        // Create an empty subdirectory
        let emptySubfolder = sourceDir.appendingPathComponent("EmptyFolder")
        try FileManager.default.createDirectory(at: emptySubfolder, withIntermediateDirectories: true)

        let builder = ManifestBuilder()

        // With subdirectories - should still work, just ignore empty folder
        let manifestWithSubs = await builder.build(
            source: sourceDir,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: true
        )
        XCTAssertEqual(manifestWithSubs?.count, 5)

        // Without subdirectories - should only get root files
        let manifestWithoutSubs = await builder.build(
            source: sourceDir,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: false
        )
        XCTAssertEqual(manifestWithoutSubs?.count, 2)
    }

    // MARK: - BackupManager Integration Tests

    @MainActor
    func testBackupManagerIncludeSubdirectoriesProperty() async throws {
        let backupManager = BackupManager()

        // Default should match preference
        let defaultValue = PreferencesManager.shared.includeSubdirectories
        XCTAssertEqual(backupManager.includeSubdirectories, defaultValue)

        // Should be able to toggle
        backupManager.includeSubdirectories = false
        XCTAssertFalse(backupManager.includeSubdirectories)

        backupManager.includeSubdirectories = true
        XCTAssertTrue(backupManager.includeSubdirectories)
    }

    @MainActor
    func testBackupManagerPersistsPreferenceOnToggle() async throws {
        let backupManager = BackupManager()
        backupManager.sourceURL = sourceDir

        // Set to true and verify preference is updated
        backupManager.includeSubdirectories = true
        XCTAssertTrue(
            PreferencesManager.shared.includeSubdirectories,
            "Preference should be updated when property is set to true"
        )

        // Toggle to false and verify preference is updated
        backupManager.includeSubdirectories = false
        XCTAssertFalse(
            PreferencesManager.shared.includeSubdirectories,
            "Preference should be updated when property is set to false"
        )

        // Verify the property correctly reflects the change
        XCTAssertFalse(backupManager.includeSubdirectories)
    }

    // MARK: - Edge Cases

    func testShallowScanWithOnlySubdirectories() async throws {
        // Create a source with only files in subdirectories, none at root
        let emptyRootSource = tempDir.appendingPathComponent("EmptyRootSource")
        try FileManager.default.createDirectory(at: emptyRootSource, withIntermediateDirectories: true)

        let subfolder = emptyRootSource.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: subfolder, withIntermediateDirectories: true)
        try createTestImage(at: subfolder.appendingPathComponent("nested.jpg"))

        let builder = ManifestBuilder()

        // With subdirectories - should find the nested file
        let manifestWithSubs = await builder.build(
            source: emptyRootSource,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: true
        )
        XCTAssertEqual(manifestWithSubs?.count, 1)

        // Without subdirectories - should find nothing
        let manifestWithoutSubs = await builder.build(
            source: emptyRootSource,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: false
        )
        XCTAssertEqual(manifestWithoutSubs?.count, 0, "Should find no files when only subdirectories contain files")
    }

    func testShallowScanPreservesFileTypeFiltering() async throws {
        // Create mixed file types at root
        try createTestImage(at: sourceDir.appendingPathComponent("photo.jpg"))
        try Data("not an image".utf8).write(to: sourceDir.appendingPathComponent("document.txt"))

        let builder = ManifestBuilder()

        let manifest = await builder.build(
            source: sourceDir,
            shouldCancel: { false },
            filter: FileTypeFilter(),
            includeSubdirectories: false
        )

        // Should only include supported image files, not txt
        let paths = manifest?.map { $0.relativePath } ?? []
        XCTAssertFalse(paths.contains("document.txt"), "Should not include non-image files")
        XCTAssertTrue(paths.contains("photo.jpg") || paths.contains("root1.jpg"))
    }
}
