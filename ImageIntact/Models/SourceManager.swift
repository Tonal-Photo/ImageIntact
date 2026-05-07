//
//  SourceManager.swift
//  ImageIntact
//
//  Owns all source-folder state: URL, file-type scan results, scanning status,
//  and source-tag management. Extracted from BackupManager to reduce its scope.
//

import Foundation

@MainActor
@Observable
class SourceManager {
    // MARK: - Source State

    var sourceURL: URL?
    var sourceFileTypes: [ImageFileType: Int] = [:]
    var isScanning = false
    var scanProgress: String = ""
    var includeSubdirectories: Bool = true {
        didSet {
            PreferencesManager.shared.includeSubdirectories = includeSubdirectories
            if let source = sourceURL, oldValue != includeSubdirectories {
                if !BackupManager.isRunningTests {
                    Task { [weak self] in
                        await self?.scanSourceFolder(source)
                    }
                }
            }
        }
    }
    var excludeCacheFiles = true
    var fileTypeFilter = FileTypeFilter()

    // Bytes tracked during scan
    var sourceTotalBytes: Int64 = 0

    // MARK: - Dependencies

    private let fileOperations: FileOperationsProtocol
    private var fileScanner: ImageFileScanner

    // MARK: - Initialization

    init(fileOperations: FileOperationsProtocol) {
        self.fileOperations = fileOperations
        self.fileScanner = ImageFileScanner()
        // Load preferences
        self.includeSubdirectories = PreferencesManager.shared.includeSubdirectories
        self.excludeCacheFiles = PreferencesManager.shared.excludeCacheFiles
    }

    // MARK: - File Scanning

    @MainActor
    func scanSourceFolder(_ url: URL) async {
        // Honor cooperative cancellation. If `prepareSource` was called again with
        // a new URL while a previous scan was in flight, that previous task gets
        // `cancel()`'d; this guard keeps it from clobbering the new task's state.
        guard !Task.isCancelled else { return }

        isScanning = true
        scanProgress = "Scanning for image files..."
        sourceFileTypes = [:]
        sourceTotalBytes = 0

        // Access the security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        // Check if we actually got access
        if !accessing {
            scanProgress = "\u{26A0}\u{FE0F} Cannot access folder - permission denied"
            isScanning = false
            logWarning("Failed to access security-scoped resource for: \(url.lastPathComponent)")

            // Clear the invalid bookmark
            if sourceURL == url {
                sourceURL = nil
                UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
            }
            return
        }

        do {
            let (results, totalBytes) = try await fileScanner.scanWithSize(directory: url) { progress in
                Task { @MainActor in
                    if progress.scanned % 100 == 0 {
                        self.scanProgress = "Scanned \(progress.scanned) files..."
                    }
                }
            }

            // Re-check cancellation right before publishing results — the inner
            // file scan can take seconds, plenty of time for a follow-up
            // `prepareSource` to have cancelled us. Without this guard, a stale
            // long-running scan would overwrite the new scan's state.
            guard !Task.isCancelled else {
                await MainActor.run { self.isScanning = false }
                return
            }

            await MainActor.run {
                self.sourceFileTypes = results
                self.sourceTotalBytes = totalBytes
                self.scanProgress = ImageFileScanner.formatScanResults(results, groupRaw: false)
                self.isScanning = false
            }
        } catch is CancellationError {
            // Cooperative cancellation propagated from inside the scanner.
            await MainActor.run { self.isScanning = false }
        } catch {
            await MainActor.run {
                self.scanProgress = "Scan failed: \(error.localizedDescription)"
                self.isScanning = false
            }
        }
    }

    // MARK: - File Type Summary

    func getFormattedFileTypeSummary(groupRaw: Bool = false) -> String {
        if sourceFileTypes.isEmpty {
            return isScanning ? scanProgress : ""
        }

        var result = ImageFileScanner.formatScanResults(sourceFileTypes, groupRaw: groupRaw)

        // Add total size if we have it from the scan
        if sourceTotalBytes > 0 {
            // Use 1000^3 to match macOS Finder display (metric GB)
            let gb = Double(sourceTotalBytes) / (1000 * 1000 * 1000)
            result += String(format: " \u{2022} %.1f GB", gb)
        }

        return result
    }

    /// Get a summary of what files will be copied with the current filter
    func getFilteredFilesSummary() -> (summary: String, willCopy: Int, total: Int)? {
        guard !sourceFileTypes.isEmpty else { return nil }

        var filteredTypes: [ImageFileType: Int] = [:]
        var totalFiltered = 0
        var totalFiles = 0

        // Calculate totals
        for (type, count) in sourceFileTypes {
            totalFiles += count

            // Check if this type will be included with current filter
            if fileTypeFilter.shouldInclude(fileType: type) {
                filteredTypes[type] = count
                totalFiltered += count
            }
        }

        // If no filter is active, all files will be copied
        if fileTypeFilter.includedExtensions.isEmpty {
            return (getFormattedFileTypeSummary(), totalFiles, totalFiles)
        }

        // Format the filtered summary
        let filteredSummary = ImageFileScanner.formatScanResults(filteredTypes, groupRaw: false)

        return (filteredSummary, totalFiltered, totalFiles)
    }

    // MARK: - Source URL Management

    /// Tracks the most recent scan task spawned by `prepareSource(at:)` so it can
    /// be cancelled if a new source URL is selected before the previous scan
    /// finishes. Prevents two concurrent scans from racing each other into
    /// `sourceFileTypes` / `scanProgress`.
    private var currentScanTask: Task<Void, Never>?

    /// Prepares a new source URL: persists the security-scoped bookmark, tags the
    /// folder for source detection, clears stale scan state, and (unless we're in
    /// test mode) kicks off an asynchronous scan for image files. If a scan from a
    /// previous `prepareSource` call is still in flight it is cancelled before the
    /// new one starts.
    ///
    /// Extracted from `BackupManager.setSource` (#103 / AMUX-18). The cross-cutting
    /// piece — auto-generating an organization name from the URL — stays at the
    /// `BackupManager` layer because it's a backup-orchestration concern, not a
    /// source-state concern.
    ///
    /// - Note: Named `prepareSource` rather than `setURL` because the method has
    ///   significant side effects (bookmark, tag, scan) beyond a simple property
    ///   set, and naming should reflect that.
    func prepareSource(at url: URL) {
        sourceURL = url
        BookmarkManager.saveBookmark(url: url, key: BookmarkManager.sourceKey)
        tagSourceFolder(at: url)

        // Clear previous scan results
        sourceFileTypes = [:]
        scanProgress = ""
        sourceTotalBytes = 0

        // Cancel any in-flight scan from a previous prepareSource call before
        // starting a new one. Same-source-twice is also a no-op via cancellation,
        // not a no-op via short-circuit, so the second call always reflects the
        // user's latest intent.
        currentScanTask?.cancel()
        currentScanTask = nil

        // Start background scan for image files (skip in tests to avoid race conditions)
        if !BackupManager.isRunningTests {
            currentScanTask = Task { [weak self] in
                await self?.scanSourceFolder(url)
            }
        }
    }

    /// Moves the current source folder to the macOS Trash and clears all
    /// source-related state. Returns a human-readable result message suitable
    /// for surfacing in the UI.
    ///
    /// Extracted from `BackupManager.trashSourceFolder` (#103 / AMUX-22). The
    /// caller (BackupManager) stores the returned string in `trashSourceResult`
    /// for its existing alert binding.
    ///
    /// Goes through `fileOperations.trashItem` rather than `FileManager.default`
    /// so tests can inject a mock and assert on cleanup behavior without
    /// actually touching the user's real Trash.
    @discardableResult
    func trashCurrentSource() -> String {
        guard let source = sourceURL else {
            return "No source folder to move"
        }

        do {
            try fileOperations.trashItem(at: source)
            let name = source.lastPathComponent
            logInfo("Moved source folder to Trash: \(name)")

            // Clear the source selection since the folder no longer exists.
            sourceURL = nil
            sourceFileTypes = [:]
            scanProgress = ""
            UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)

            return "Moved \"\(name)\" to Trash"
        } catch {
            logWarning("Failed to move source to Trash: \(error.localizedDescription)")
            return "Failed to move to Trash: \(error.localizedDescription)"
        }
    }

    // MARK: - Source Tagging

    func tagSourceFolder(at url: URL) {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        let tagContent = """
        {
            "source_id": "\(UUID().uuidString)",
            "tagged_date": "\(Date().ISO8601Format())",
            "app_version": "1.1.0"
        }
        """

        let success = fileOperations.createFile(
            at: tagFile,
            contents: Data(tagContent.utf8),
            attributes: [.extensionHidden: true]
        )
        if !success {
            logError("Failed to tag source folder")
        }
    }

    func checkForSourceTag(at url: URL) -> Bool {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        return fileOperations.fileExists(at: tagFile)
    }

    func removeSourceTag(at url: URL) {
        let tagFile = url.appendingPathComponent(".imageintact_source")
        do {
            try fileOperations.removeItem(at: tagFile)
            logInfo("Removed source tag from: \(url.path)")
        } catch {
            logError("Failed to remove source tag: \(error)")
        }
    }
}
