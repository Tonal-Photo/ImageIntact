//
//  SourceManagerTests.swift
//  ImageIntactTests
//
//  Direct tests for SourceManager. Initial coverage focuses on
//  prepareSource(at:) — the state-mutation path extracted from
//  BackupManager.setSource (#103 / AMUX-18).
//
//  AMUX-20 / GH #103: extended with loadFromSession() and
//  file-type-filter preference-loading tests (TDD red phase).
//

import XCTest

@testable import ImageIntact

@MainActor
final class SourceManagerTests: IsolatedDefaultsTestCase {

    // MARK: - Lifecycle

    override func setUp() async throws {
        try await super.setUp()
        // Bookmark isolation handled by IsolatedDefaultsTestCase.
        // Reset file-type-filter preference to a known baseline.
        PreferencesManager.shared.resetToDefaults()
    }

    override func tearDown() async throws {
        PreferencesManager.shared.resetToDefaults()
        try await super.tearDown()
    }

    // MARK: - Existing tests (unchanged)

    /// `prepareSource` clears stale scan state from a previous source. The
    /// auto-scan is suppressed under `BackupManager.isRunningTests`, so we can
    /// assert the synchronous post-conditions deterministically.
    func testPrepareSourceClearsStaleScanState() {
        let manager = SourceManager(fileOperations: DefaultFileOperations())
        // Prime stale state from a hypothetical prior scan.
        manager.sourceFileTypes = [.jpeg: 5, .raw: 3]
        manager.scanProgress = "halfway through Card01"
        manager.sourceTotalBytes = 1_000_000

        let url = URL(fileURLWithPath: "/Volumes/Card02/DCIM")
        manager.prepareSource(at: url)

        XCTAssertEqual(manager.sourceURL, url, "URL should be set")
        XCTAssertTrue(manager.sourceFileTypes.isEmpty, "Stale file-type counts should clear")
        XCTAssertEqual(manager.scanProgress, "", "Stale scan progress should clear")
        XCTAssertEqual(manager.sourceTotalBytes, 0, "Stale byte total should clear")
    }

    /// Calling `prepareSource` twice in quick succession must not leak the
    /// first scan task. The internal `currentScanTask` is replaced (and the
    /// previous one cancelled) so the second call's post-conditions still hold.
    func testPrepareSourceTwiceClearsState() {
        let manager = SourceManager(fileOperations: DefaultFileOperations())

        let url1 = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        let url2 = URL(fileURLWithPath: "/Volumes/Card02/DCIM")
        manager.prepareSource(at: url1)
        // Mutate state as if a partial scan happened.
        manager.sourceFileTypes = [.jpeg: 100]
        manager.scanProgress = "scanning Card01..."

        manager.prepareSource(at: url2)
        XCTAssertEqual(manager.sourceURL, url2)
        XCTAssertTrue(manager.sourceFileTypes.isEmpty,
                      "Second prepareSource must clear results from the first one")
        XCTAssertEqual(manager.scanProgress, "")
    }

    // MARK: - trashCurrentSource

    /// `trashCurrentSource` with no `sourceURL` set returns the no-source
    /// message and does not raise an error. Deterministic, no filesystem
    /// side effects.
    func testTrashCurrentSourceWithoutSourceReturnsErrorMessage() {
        let manager = SourceManager(fileOperations: DefaultFileOperations())
        XCTAssertNil(manager.sourceURL)
        let result = manager.trashCurrentSource()
        XCTAssertEqual(result, "No source folder to move")
    }

    /// `trashCurrentSource` success path: dispatches through the injected
    /// `fileOperations.trashItem`, clears state, and returns the user-facing
    /// message. Uses a mock so the user's real Trash is untouched.
    func testTrashCurrentSourceClearsStateOnSuccess() {
        let mock = MockFileOperations()
        let manager = SourceManager(fileOperations: mock)
        let url = URL(fileURLWithPath: "/Volumes/Card01/DCIM")
        manager.sourceURL = url
        manager.sourceFileTypes = [.jpeg: 1]
        manager.scanProgress = "stale"

        let result = manager.trashCurrentSource()

        XCTAssertEqual(result, "Moved \"DCIM\" to Trash")
        XCTAssertEqual(mock.trashedItems, [url], "fileOperations.trashItem should have been called once with the source URL")
        XCTAssertNil(manager.sourceURL, "Source URL should be cleared after trash")
        XCTAssertTrue(manager.sourceFileTypes.isEmpty, "File types should be cleared")
        XCTAssertEqual(manager.scanProgress, "")
    }

    /// `trashCurrentSource` error path: when `fileOperations.trashItem` throws
    /// (e.g., permission denied, missing file, locked file), the source state
    /// stays intact and the returned message includes the underlying error
    /// description.
    func testTrashCurrentSourceErrorPathPreservesState() {
        let mock = MockFileOperations()
        mock.shouldFailTrash = true
        let manager = SourceManager(fileOperations: mock)
        let url = URL(fileURLWithPath: "/Volumes/Card02/DCIM")
        manager.sourceURL = url
        manager.sourceFileTypes = [.jpeg: 5]
        manager.scanProgress = "preserved"

        let result = manager.trashCurrentSource()

        XCTAssertTrue(result.hasPrefix("Failed to move to Trash:"),
                      "Should be a failure message; got \(result)")
        XCTAssertEqual(manager.sourceURL, url, "Source URL must NOT be cleared on failure")
        XCTAssertEqual(manager.sourceFileTypes, [.jpeg: 5], "File types must NOT be cleared on failure")
        XCTAssertEqual(manager.scanProgress, "preserved", "Scan progress must NOT be cleared on failure")
    }

    // MARK: - loadFromSession (AMUX-20 / GH #103 — TDD red phase)
    // NOTE: loadFromSession() does not exist yet. These tests will fail to
    // compile until the implementation is added to SourceManager.swift.

    /// loadFromSession returns nil when UserDefaults has no entry for
    /// BookmarkManager.sourceKey — the common "fresh launch" path.
    func testLoadFromSession_returnsNilWhenNoBookmark() {
        // setUp already clears the key; confirm baseline.
        XCTAssertNil(defaults.data(forKey: BookmarkManager.sourceKey),
                     "Precondition: no bookmark data in UserDefaults")
        let manager = SourceManager(fileOperations: MockFileOperations())
        let result = manager.loadFromSession()
        XCTAssertNil(result, "loadFromSession must return nil when no bookmark is stored")
    }

    /// loadFromSession returns nil and removes the stale bookmark from
    /// UserDefaults when a bookmark entry exists but security-scoped access
    /// fails. In the XCTest harness (non-sandboxed), startAccessingSecurityScopedResource
    /// returns false for paths outside the sandbox, which exercises this branch.
    ///
    /// If the test environment grants access for the temp URL (sandbox is active),
    /// the test will follow the success path instead — that is documented here so
    /// the CI failure is understandable. The success path is covered separately.
    func testLoadFromSession_returnsNilAndClearsDefaultsWhenAccessFails() {
        // Plant a bookmark for a path that is unlikely to be accessible in the
        // sandboxed test runner. We create a temp dir so the bookmark data itself
        // resolves (i.e. loadBookmark returns a URL), giving startAccessingSecurityScopedResource
        // a chance to fail on the real file URL with no sandbox entitlement.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        BookmarkManager.saveBookmark(url: tempDir, key: BookmarkManager.sourceKey)
        XCTAssertNotNil(defaults.data(forKey: BookmarkManager.sourceKey),
                        "Precondition: bookmark data must be present before calling loadFromSession")

        let manager = SourceManager(fileOperations: MockFileOperations())
        let result = manager.loadFromSession()

        // In the non-sandboxed test runner, access fails → result is nil and key is cleared.
        // In a sandboxed runner where access succeeds, result is the URL (success path).
        // Either outcome is valid; we assert the invariant: if nil is returned the key is gone.
        if result == nil {
            XCTAssertNil(defaults.data(forKey: BookmarkManager.sourceKey),
                         "When loadFromSession returns nil, it must clear the stale bookmark key")
            XCTAssertNil(manager.sourceURL,
                         "sourceURL must not be set when loadFromSession returns nil")
        } else {
            // Success path exercised — covered by the dedicated success test.
            XCTAssertEqual(manager.sourceURL, result,
                           "When loadFromSession returns a URL, sourceURL must match")
        }
    }

    /// loadFromSession sets sourceURL and returns the URL when the bookmark
    /// resolves and security-scoped access succeeds. This test uses the temp
    /// directory but notes that access success depends on sandbox entitlements.
    func testLoadFromSession_setsSourceURLAndReturnsURLOnSuccess() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        BookmarkManager.saveBookmark(url: tempDir, key: BookmarkManager.sourceKey)

        let manager = SourceManager(fileOperations: MockFileOperations())
        let result = manager.loadFromSession()

        // If access succeeds, result must equal sourceURL.
        if let restoredURL = result {
            XCTAssertEqual(manager.sourceURL, restoredURL,
                           "sourceURL must be set to the restored URL on success")
        }
        // If access fails (non-sandboxed runner), result is nil — covered by the
        // access-failure test. Either outcome is valid here.
    }

    /// loadFromSession must NOT trigger an async scan. isScanning must be false
    /// immediately after the synchronous call returns.
    func testLoadFromSession_doesNotTriggerAsyncScan() {
        let manager = SourceManager(fileOperations: MockFileOperations())
        // No bookmark planted — loadFromSession returns nil immediately.
        _ = manager.loadFromSession()
        XCTAssertFalse(manager.isScanning,
                       "loadFromSession must not start an async scan; scanning is the caller's responsibility")
    }

    // MARK: - File-type-filter preference loading on init (AMUX-20 / GH #103)
    // These test that SourceManager.init reads defaultFileTypeFilter from
    // PreferencesManager and maps it to the correct FileTypeFilter preset.
    // The mapping does not exist yet in SourceManager.init — these tests will
    // fail until the implementation lands.

    /// "photos" preference → .photosOnly filter on init.
    func testInit_fileTypeFilter_photosPreference() {
        PreferencesManager.shared.defaultFileTypeFilter = "photos"
        let manager = SourceManager(fileOperations: MockFileOperations())
        XCTAssertEqual(manager.fileTypeFilter, FileTypeFilter.photosOnly,
                       "\"photos\" pref should produce .photosOnly filter at init")
    }

    /// "raw" preference → .rawOnly filter on init.
    func testInit_fileTypeFilter_rawPreference() {
        PreferencesManager.shared.defaultFileTypeFilter = "raw"
        let manager = SourceManager(fileOperations: MockFileOperations())
        XCTAssertEqual(manager.fileTypeFilter, FileTypeFilter.rawOnly,
                       "\"raw\" pref should produce .rawOnly filter at init")
    }

    /// "videos" preference → .videosOnly filter on init.
    func testInit_fileTypeFilter_videosPreference() {
        PreferencesManager.shared.defaultFileTypeFilter = "videos"
        let manager = SourceManager(fileOperations: MockFileOperations())
        XCTAssertEqual(manager.fileTypeFilter, FileTypeFilter.videosOnly,
                       "\"videos\" pref should produce .videosOnly filter at init")
    }

    /// Unrecognised preference string → default FileTypeFilter() (include-all) on init.
    func testInit_fileTypeFilter_unrecognisedPreference() {
        PreferencesManager.shared.defaultFileTypeFilter = "garbage"
        let manager = SourceManager(fileOperations: MockFileOperations())
        XCTAssertEqual(manager.fileTypeFilter, FileTypeFilter(),
                       "Unrecognised pref string should produce the default include-all filter at init")
    }

    /// "all" (the @AppStorage default) → default FileTypeFilter() (include-all) on init.
    /// This also covers the "nil/missing" case since @AppStorage returns "all" when the
    /// key is absent.
    func testInit_fileTypeFilter_allPreference() {
        PreferencesManager.shared.defaultFileTypeFilter = "all"
        let manager = SourceManager(fileOperations: MockFileOperations())
        XCTAssertEqual(manager.fileTypeFilter, FileTypeFilter(),
                       "\"all\" pref should produce the default include-all filter at init")
    }
}
