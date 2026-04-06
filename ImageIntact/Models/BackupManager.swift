import AppKit
import CryptoKit
import Darwin
import SwiftUI

// MARK: - Backup Phase Enum

enum BackupPhase: Int, Comparable {
    case idle = 0
    case analyzingSource = 1
    case buildingManifest = 2
    case copyingFiles = 3
    case flushingToDisk = 4
    case verifyingDestinations = 5
    case complete = 6

    static func < (lhs: BackupPhase, rhs: BackupPhase) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

@Observable
@MainActor
class BackupManager {
    // MARK: - Test Mode

    static var isRunningTests: Bool {
        return ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    // MARK: - Dependencies (for testing)

    let fileOperations: FileOperationsProtocol
    let notificationService: NotificationProtocol
    let driveAnalyzer: DriveAnalyzerProtocol
    let diskSpaceChecker: DiskSpaceProtocol

    // MARK: - Delegated Managers

    let sourceManager: SourceManager
    let destinationManager: DestinationManager

    // MARK: - Destination Forwarding (read-only)

    var destinationURLs: [URL?] { destinationManager.destinationURLs }
    var destinationItems: [DestinationItem] { destinationManager.destinationItems }
    var destinationDriveInfo: [UUID: DriveAnalyzer.DriveInfo] { destinationManager.destinationDriveInfo }
    var isProcessing = false
    var statusMessage = ""
    var failedFiles: [(file: String, destination: String, error: String)] = []
    var sessionID = UUID().uuidString
    var shouldCancel = false
    var debugLog: [String] = []
    var hasWrittenDebugLog = false
    var lastDebugLogPath: URL?

    // Progress tracking delegated to ProgressTracker
    let progressTracker = ProgressTracker()

    // Statistics tracking for completion report
    let statistics = BackupStatistics()

    // Expose progress properties for compatibility
    var totalFiles: Int {
        get { progressTracker.totalFiles }
        set { progressTracker.totalFiles = newValue }
    }

    var processedFiles: Int {
        get { progressTracker.processedFiles }
        set { progressTracker.processedFiles = newValue }
    }

    var currentFile: String {
        get { progressTracker.currentFile }
        set { progressTracker.currentFile = newValue }
    }

    var currentFileIndex: Int {
        get { progressTracker.currentFileIndex }
        set { progressTracker.currentFileIndex = newValue }
    }

    var currentFileName: String {
        get { progressTracker.currentFileName }
        set { progressTracker.currentFileName = newValue }
    }

    var currentDestinationName: String {
        get { progressTracker.currentDestinationName }
        set { progressTracker.currentDestinationName = newValue }
    }

    var copySpeed: Double {
        get { progressTracker.copySpeed }
        set { progressTracker.copySpeed = newValue }
    }

    var totalBytesCopied: Int64 {
        get { progressTracker.totalBytesCopied }
        set { progressTracker.totalBytesCopied = newValue }
    }

    var totalBytesToCopy: Int64 {
        get { progressTracker.totalBytesToCopy }
        set { progressTracker.totalBytesToCopy = newValue }
    }

    var estimatedSecondsRemaining: TimeInterval? { progressTracker.estimatedSecondsRemaining }
    var destinationProgress: [String: Int] {
        return progressTracker.destinationProgress
    }

    var destinationStates: [String: String] {
        return progressTracker.destinationStates
    }

    var currentPhase: BackupPhase = .idle
    var phaseProgress: Double {
        return progressTracker.phaseProgress
    }

    var overallProgress: Double {
        return progressTracker.overallProgress
    }

    // Resource management
    let resourceManager = ResourceManager() // Made internal for extension access

    // Other UI state
    var overallStatusText: String = "" // For showing mixed states like "1 copying, 1 verifying"

    // Source-related properties are now on sourceManager
    // Convenience accessors for code that still reads these directly
    var sourceURL: URL? {
        get { sourceManager.sourceURL }
        set { sourceManager.sourceURL = newValue }
    }
    var sourceFileTypes: [ImageFileType: Int] {
        get { sourceManager.sourceFileTypes }
        set { sourceManager.sourceFileTypes = newValue }
    }
    var isScanning: Bool { sourceManager.isScanning }
    var scanProgress: String {
        get { sourceManager.scanProgress }
        set { sourceManager.scanProgress = newValue }
    }
    var sourceTotalBytes: Int64 { sourceManager.sourceTotalBytes }
    var fileTypeFilter: FileTypeFilter {
        get { sourceManager.fileTypeFilter }
        set { sourceManager.fileTypeFilter = newValue }
    }
    var includeSubdirectories: Bool {
        get { sourceManager.includeSubdirectories }
        set { sourceManager.includeSubdirectories = newValue }
    }
    var excludeCacheFiles: Bool {
        get { sourceManager.excludeCacheFiles }
        set { sourceManager.excludeCacheFiles = newValue }
    }

    // Backup organization
    // Custom folder name for organizing backups.
    // Sanitized on set to prevent filesystem issues from special characters.
    // See: GH issue #91, finding #8.
    var organizationName: String = "" {
        didSet {
            var cleaned = organizationName
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "\\", with: "_")
                .replacingOccurrences(of: ":", with: "_")  // macOS Finder path separator
                .replacingOccurrences(of: "\0", with: "")  // null bytes
                .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
            // APFS/HFS+ limit is 255 UTF-8 bytes, not characters.
            if cleaned.utf8.count > 255 {
                var truncated = ""
                for char in cleaned {
                    let next = truncated + String(char)
                    if next.utf8.count > 255 { break }
                    truncated = next
                }
                cleaned = truncated
            }
            let sanitized = cleaned
            if sanitized != organizationName {
                organizationName = sanitized
            }
        }
    }

    // UI state for completion report
    var showCompletionReport = false

    // Migration state
    var showMigrationDialog = false
    var pendingMigrationPlans: [BackupMigrationDetector.MigrationPlan] = []

    // Duplicate detection state
    var enableDuplicateDetection: Bool {
        PreferencesManager.shared.enableSmartDuplicateDetection
    }

    var showDuplicateWarning = false
    var duplicateAnalyses: [URL: DuplicateDetector.DuplicateAnalysis]?
    let duplicateDetector: DuplicateDetectorProtocol
    var skipExactDuplicates = true
    var skipRenamedDuplicates = false

    // Trash source state
    var showTrashConfirmation = false
    var trashSourceResult: String? = nil

    // Large backup confirmation state
    var showLargeBackupConfirmation = false
    var largeBackupInfo: LargeBackupInfo?
    var largeBackupContinuation: CheckedContinuation<Bool, Never>?

    struct LargeBackupInfo {
        let fileCount: Int
        let totalBytes: Int64
        let destinationCount: Int
        let estimatedTimePerDestination: String
    }

    // MARK: - Constants (bookmark keys live in BookmarkManager)

    struct LogEntry {
        let timestamp: Date
        let sessionID: String
        let action: String
        let source: String
        let destination: String
        let checksum: String
        let algorithm: String
        let fileSize: Int64
        let reason: String
    }

    var logEntries: [LogEntry] = []
    private var currentOperation: DispatchWorkItem?
    var currentOrchestrator: BackupOrchestrator?

    // MARK: - Initialization

    init(
        fileOperations: FileOperationsProtocol? = nil,
        notificationService: NotificationProtocol? = nil,
        driveAnalyzer: DriveAnalyzerProtocol? = nil,
        diskSpaceChecker: DiskSpaceProtocol? = nil,
        duplicateDetector: DuplicateDetectorProtocol? = nil
    ) {
        // Use provided dependencies or create real implementations
        let resolvedFileOps = fileOperations ?? DefaultFileOperations()
        self.fileOperations = resolvedFileOps
        self.notificationService = notificationService ?? RealNotificationService()
        let resolvedDriveAnalyzer = driveAnalyzer ?? RealDriveAnalyzer()
        let resolvedDiskSpace = diskSpaceChecker ?? RealDiskSpaceChecker()
        self.driveAnalyzer = resolvedDriveAnalyzer
        self.diskSpaceChecker = resolvedDiskSpace
        self.duplicateDetector = duplicateDetector ?? DuplicateDetector()

        // Create delegated managers
        self.sourceManager = SourceManager(fileOperations: resolvedFileOps)
        self.destinationManager = DestinationManager(
            fileOperations: resolvedFileOps,
            driveAnalyzer: resolvedDriveAnalyzer,
            diskSpaceChecker: resolvedDiskSpace
        )

        // Initialize organization name from last used (if user previously customized)
        if let lastUsedName = PreferencesManager.shared.lastUsedOrganizationFolderName {
            organizationName = lastUsedName
        }

        // Check for UI test mode
        if BackupManager.isRunningTests, ProcessInfo.processInfo.arguments.contains("--uitest") {
            loadUITestPaths()
            return
        }

        // Initialize file type filter on source manager
        initializeFileTypeFilter()

        // Restore last session if enabled
        if PreferencesManager.shared.restoreLastSession {
            destinationManager.loadFromSession()
            loadSourceFromSession()
        } else {
            destinationManager.initializeEmpty()
            logInfo("Initialized with single empty destination slot")
        }

        // Validate and analyze loaded destinations
        destinationManager.validateAndAnalyzeDestinations()
    }

    // MARK: - Initialization Helpers

    /// Initialize the file type filter from user preferences
    private func initializeFileTypeFilter() {
        let filterPref = PreferencesManager.shared.defaultFileTypeFilter
        switch filterPref {
        case "photos":
            sourceManager.fileTypeFilter = .photosOnly
        case "raw":
            sourceManager.fileTypeFilter = .rawOnly
        case "videos":
            sourceManager.fileTypeFilter = .videosOnly
        default:
            sourceManager.fileTypeFilter = FileTypeFilter()
        }
    }

    /// Load source URL from saved bookmark and trigger scan
    private func loadSourceFromSession() {
        guard let savedSourceURL = BookmarkManager.loadBookmark(forKey: BookmarkManager.sourceKey) else { return }

        let canAccess = savedSourceURL.startAccessingSecurityScopedResource()
        if canAccess {
            savedSourceURL.stopAccessingSecurityScopedResource()
            sourceManager.sourceURL = savedSourceURL
            logInfo("Loaded source: \(savedSourceURL.lastPathComponent)")
            // Skip async scan in tests to avoid race conditions with tearDown
            if !BackupManager.isRunningTests {
                Task {
                    await sourceManager.scanSourceFolder(savedSourceURL)
                }
            }
        } else {
            logWarning("Saved source bookmark is invalid, clearing...")
            UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        }
    }

    // MARK: - Public Methods

    func clearAllSelections() {
        sourceManager.sourceURL = nil
        sourceManager.sourceFileTypes = [:]
        sourceManager.scanProgress = ""
        UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        destinationManager.clearAll()
    }

    /// Move the source folder to Trash after successful backup
    @MainActor
    func trashSourceFolder() {
        guard let source = sourceURL else {
            trashSourceResult = "No source folder to move"
            return
        }

        do {
            var trashedURL: NSURL?
            try FileManager.default.trashItem(at: source, resultingItemURL: &trashedURL)
            let name = source.lastPathComponent
            logInfo("Moved source folder to Trash: \(name)")
            trashSourceResult = "Moved \"\(name)\" to Trash"

            // Clear the source selection since the folder no longer exists
            sourceManager.sourceURL = nil
            sourceManager.sourceFileTypes = [:]
            sourceManager.scanProgress = ""
            UserDefaults.standard.removeObject(forKey: BookmarkManager.sourceKey)
        } catch {
            logWarning("Failed to move source to Trash: \(error.localizedDescription)")
            trashSourceResult = "Failed to move to Trash: \(error.localizedDescription)"
        }
    }

    func addDestination() {
        destinationManager.addDestination()
    }

    func setSource(_ url: URL) {
        sourceManager.sourceURL = url
        BookmarkManager.saveBookmark(url: url, key: BookmarkManager.sourceKey)
        sourceManager.tagSourceFolder(at: url)

        // Clear previous scan results
        sourceManager.sourceFileTypes = [:]
        sourceManager.scanProgress = ""
        sourceManager.sourceTotalBytes = 0

        // Auto-generate organization name from source path (stays on BackupManager - cross-concern)
        organizationName = extractSmartFolderName(from: url)

        // Start background scan for image files (skip in tests to avoid race conditions)
        if !BackupManager.isRunningTests {
            Task { [weak self] in
                await self?.sourceManager.scanSourceFolder(url)
            }
        }
    }

    /// Extracts a smart folder name from the source URL
    /// Examples:
    /// - ~/Downloads → "Downloads"
    /// - /Volumes/Card01/DCIM → "Card01"
    /// - ~/Pictures/2025/Q3/Clients/Johnson → "Johnson"
    /// - ~/Photos/My Photo Shoot → "My_Photo_Shoot"
    private func extractSmartFolderName(from url: URL) -> String {
        let pathComponents = url.pathComponents

        var folderName: String

        // If it's a volume, use the volume name
        if pathComponents.count > 2 && pathComponents[1] == "Volumes" {
            folderName = pathComponents[2] // Volume name
        } else {
            // Skip generic folder names
            let genericNames = ["files", "images", "photos", "pictures", "dcim", "documents"]

            // Work backwards through path components to find a meaningful name
            folderName = url.lastPathComponent // Fallback
            for component in pathComponents.reversed() {
                let lowercased = component.lowercased()
                // Skip empty, hidden, or generic names
                if !component.isEmpty && !component.hasPrefix(".") && !genericNames.contains(lowercased)
                    && component != "/"
                {
                    folderName = component
                    break
                }
            }
        }

        // Replace spaces with underscores and collapse multiple underscores
        return folderName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
    }

    func setDestination(_ url: URL, at index: Int) {
        let hasSourceTag = sourceManager.checkForSourceTag(at: url)
        do {
            try destinationManager.setDestination(
                url, at: index,
                sourceURL: sourceManager.sourceURL,
                hasSourceTag: hasSourceTag,
                totalBytesToCopy: totalBytesToCopy
            )
        } catch DestinationError.sameAsSource {
            if !BackupManager.isRunningTests {
                let alert = NSAlert()
                alert.messageText = "Invalid Destination"
                alert.informativeText = "The destination folder cannot be the same as the source folder."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch DestinationError.duplicateDestination(let idx) {
            if !BackupManager.isRunningTests {
                let alert = NSAlert()
                alert.messageText = "Duplicate Destination"
                alert.informativeText =
                    "This folder is already selected as destination #\(idx + 1). Please choose a different folder."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        } catch DestinationError.sourceTagConflict(let tagURL) {
            if !BackupManager.isRunningTests {
                let alert = NSAlert()
                alert.messageText = "Source Folder Selected"
                alert.informativeText =
                    "This folder was previously used as a source. Using it as a destination will remove the source tag. Do you want to continue?"
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Use This Folder")
                alert.addButton(withTitle: "Cancel")
                let response = alert.runModal()
                if response == .alertSecondButtonReturn { return }
            }
            sourceManager.removeSourceTag(at: tagURL)
            do {
                try destinationManager.setDestination(
                    url, at: index,
                    sourceURL: sourceManager.sourceURL,
                    hasSourceTag: false,
                    totalBytesToCopy: totalBytesToCopy
                )
            } catch {
                logWarning("Failed to set destination after source tag removal: \(error)")
            }
        } catch DestinationError.indexOutOfRange {
            logWarning("setDestination called with out-of-range index: \(index)")
        } catch {
            logWarning("Unexpected destination error: \(error)")
        }
    }

    func clearDestination(at index: Int) {
        destinationManager.clearDestination(at: index)
    }

    func removeDestination(at index: Int) {
        destinationManager.removeDestination(at: index)
    }

    // MARK: - UI Test Support

    private func loadUITestPaths() {
        logInfo("Loading UI test paths")

        // Load test source path
        if let testSourcePath = UserDefaults.standard.string(forKey: "TestSourcePath") {
            let sourceURL = URL(fileURLWithPath: testSourcePath)
            self.sourceManager.sourceURL = sourceURL
            organizationName = extractSmartFolderName(from: sourceURL)
            logInfo("UI Test: Set source to \(testSourcePath)")
        }

        // Delegate destination loading to DestinationManager
        #if DEBUG
        destinationManager.loadUITestDestinations()
        #else
        destinationManager.initializeEmpty()
        #endif

        // Load test organization name if provided
        if let testOrgName = UserDefaults.standard.string(forKey: "TestOrganizationName") {
            organizationName = testOrgName
            logInfo("UI Test: Set organization name to \(testOrgName)")
        }

        // Clear source test values (destination keys cleared by DestinationManager)
        UserDefaults.standard.removeObject(forKey: "TestSourcePath")
        UserDefaults.standard.removeObject(forKey: "TestOrganizationName")
    }

    func canRunBackup() -> Bool {
        return sourceURL != nil && !destinationURLs.compactMap { $0 }.isEmpty && !isProcessing
    }

    func runBackup() {
        guard let source = sourceURL else {
            logWarning("Missing source folder.")
            return
        }

        let destinations = destinationURLs.compactMap { $0 }

        // Check disk space for all destinations
        let spaceChecks = diskSpaceChecker.checkAllDestinations(
            destinations: destinations,
            requiredBytes: totalBytesToCopy
        )

        let (canProceed, warnings, errors) = diskSpaceChecker.evaluateSpaceChecks(spaceChecks)

        // If we have errors (insufficient space), show alert and abort
        if !canProceed {
            let alert = NSAlert()
            alert.messageText = "Insufficient Disk Space"
            alert.informativeText = errors.joined(separator: "\n\n")
            alert.alertStyle = .critical
            alert.addButton(withTitle: "OK")
            alert.runModal()
            return
        }

        // If we have warnings (< 10% free after backup), show alert with option to proceed
        if !warnings.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Low Disk Space Warning"
            alert.informativeText = warnings.joined(separator: "\n\n") + "\n\nDo you want to continue?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Continue")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if response != .alertFirstButtonReturn {
                return
            }
        }

        // Show pre-flight summary if enabled
        if PreferencesManager.shared.showPreflightSummary {
            let alert = NSAlert()
            alert.messageText = "Backup Summary"

            // Build the summary message
            var message = "Ready to start backup:\n\n"

            // Source info
            message += "📁 Source: \(source.lastPathComponent)\n"
            message += "   Path: \(source.path)\n\n"

            // File summary
            if let filteredSummary = getFilteredFilesSummary() {
                message += "📊 Files to backup:\n"
                if filteredSummary.willCopy != filteredSummary.total {
                    message += "   \(filteredSummary.willCopy) of \(filteredSummary.total) files (filtered)\n"
                    message += "   Types: \(filteredSummary.summary)\n\n"
                } else {
                    message += "   \(filteredSummary.total) files\n"
                    message += "   Types: \(filteredSummary.summary)\n\n"
                }
            } else if !sourceFileTypes.isEmpty {
                let totalFiles = sourceFileTypes.values.reduce(0, +)
                message += "📊 Files to backup: \(totalFiles)\n"
                message += "   Types: \(getFormattedFileTypeSummary())\n\n"
            }

            // Size info
            if sourceTotalBytes > 0 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                let sizeString = formatter.string(fromByteCount: sourceTotalBytes)
                message += "💾 Total size: \(sizeString)\n\n"
            }

            // Destination info
            message += "📍 Destination\(destinations.count > 1 ? "s" : ""):\n"
            for (index, dest) in destinations.enumerated() {
                message += "   \(index + 1). \(dest.lastPathComponent)"

                // Add drive info if available
                if index < destinationItems.count {
                    let itemID = destinationItems[index].id
                    if let driveInfo = destinationDriveInfo[itemID] {
                        if !driveInfo.deviceName.isEmpty {
                            message += " (\(driveInfo.deviceName))"
                        }
                    }
                }
                message += "\n"
            }

            // Settings info
            message += "\n⚙️ Settings:\n"
            if PreferencesManager.shared.excludeCacheFiles {
                message += "   • Cache files will be excluded\n"
            }
            if PreferencesManager.shared.skipHiddenFiles {
                message += "   • Hidden files will be skipped\n"
            }
            if !fileTypeFilter.includedExtensions.isEmpty {
                message += "   • File type filter is active\n"
            }

            alert.informativeText = message
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Start Backup")
            alert.addButton(withTitle: "Cancel")

            // Add "Show this summary before run" checkbox
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Show this summary before run"
            alert.suppressionButton?.state = .on // Checked by default

            let response = alert.runModal()

            // Update preference based on checkbox state
            // Note: suppression button logic is inverted - when unchecked, we disable the summary
            PreferencesManager.shared.showPreflightSummary = (alert.suppressionButton?.state == .on)

            if response != .alertFirstButtonReturn {
                return
            }
        }

        isProcessing = true
        statusMessage = "Preparing backup..."
        progressTracker.totalFiles = 0
        progressTracker.processedFiles = 0
        progressTracker.currentFile = ""
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        shouldCancel = false
        debugLog = []
        hasWrittenDebugLog = false

        // Save organization folder name to recent list and as last used
        if !organizationName.isEmpty {
            PreferencesManager.shared.addRecentOrganizationFolderName(organizationName)
            PreferencesManager.shared.lastUsedOrganizationFolderName = organizationName
        }

        // Start preventing sleep
        SleepPrevention.shared.startPreventingSleep(
            reason: "ImageIntact backup to \(destinations.count) destination(s)")

        // Use the new queue-based backup system for parallel destination processing
        Task { [weak self] in
            await self?.performQueueBasedBackup(source: source, destinations: destinations)
        }
    }

    func cancelOperation() {
        guard !shouldCancel else { return } // Prevent multiple cancellations
        shouldCancel = true
        statusMessage = "Cancelling backup..."

        // Clean up any pending large backup confirmation
        // This resumes the continuation with false to unblock the waiting backup
        if let continuation = largeBackupContinuation {
            ApplicationLogger.shared.warning("Cleaning up pending large backup continuation due to cancellation", category: .backup)
            continuation.resume(returning: false)
            largeBackupContinuation = nil
            showLargeBackupConfirmation = false
            largeBackupInfo = nil
        }

        // Immediately clear all progress indicators
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            // Force clear all destination progress immediately
            for name in self.progressTracker.destinationProgress.keys {
                self.progressTracker.setDestinationProgress(0, for: name)
                self.progressTracker.setDestinationState("cancelled", for: name)
            }

            // Clear file name displays
            self.currentFileName = ""
            self.currentDestinationName = ""
            self.overallStatusText = "" // Clear this so UI doesn't show "1 destination copying"

            // Force UI update
            self.isProcessing = false
            self.currentPhase = .idle
            self.statusMessage = "Backup cancelled"

            // Clear progress tracker immediately - this resets all the computed values
            self.progressTracker.resetAll()

            // Stop sleep prevention
            SleepPrevention.shared.stopPreventingSleep()
        }

        // Cancel orchestrator
        Task { @MainActor [weak self] in
            self?.currentOrchestrator?.cancel()
        }

        // Cancel any pending operation
        currentOperation?.cancel()

        // Clean up resources
        Task { [weak self] in
            await self?.resourceManager.cleanup()
        }

        // Force memory cleanup
        cleanupMemory()
    }

    /// Force memory cleanup after backup completion or cancellation
    func cleanupMemory() {
        // Clear large data structures
        logEntries.removeAll(keepingCapacity: false)
        debugLog.removeAll(keepingCapacity: false)

        // DON'T clear failedFiles - needed for completion report
        // DON'T clear statistics - needed for completion report
        // DON'T clear progress data yet - UI may still need it
        // DON'T clear sourceFileTypes - needed for UI display

        // Note: We keep sourceFileTypes since it's needed for the UI
        // It will be refreshed when a new source is selected

        // Don't clear destination info - keep it for UI display
        // destinationDriveInfo.removeAll(keepingCapacity: false)

        // Clear orchestrator reference
        currentOrchestrator = nil
        currentOperation = nil

        // Note: Core Data will manage its own memory
        EventLogger.shared.resetContexts()

        // Force cleanup with autorelease pool
        autoreleasepool {}

        logInfo("Initial memory cleanup completed", category: .performance)

        // Schedule deep cleanup after UI has shown stats
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds

            guard let self = self else { return }

            // Now clear the rest
            self.failedFiles.removeAll(keepingCapacity: false)
            self.progressTracker.resetAll()
            self.progressTracker.destinationProgress.removeAll(keepingCapacity: false)
            self.progressTracker.destinationStates.removeAll(keepingCapacity: false)
            self.statistics.reset()
            self.statusMessage = ""
            self.overallStatusText = ""
            // Keep scanProgress - it shows the file type summary

            // Clean up checksum buffer pool
            ChecksumBufferPool.shared.cleanupUnusedBuffers()

            autoreleasepool {}
            logInfo("Deep memory cleanup completed", category: .performance)
        }
    }

    // MARK: - Debug Logging

    @MainActor
    private func writeDebugLog() {
        // Implementation for debug logging - placeholder for now
        logInfo("Debug log: \(failedFiles.count) failed files")
    }

    // MARK: - Source Tag Delegation

    func checkForSourceTag(at url: URL) -> Bool {
        sourceManager.checkForSourceTag(at: url)
    }

    // MARK: - Simple Progress Updates

    @MainActor
    func updateProgress(fileName: String, destinationName: String) {
        Task {
            // Update through ProgressTracker
            progressTracker.updateFileProgress(fileName: fileName, destinationName: destinationName)
        }
    }

    @MainActor
    func updateCopySpeed(bytesAdded: Int64) {
        progressTracker.totalBytesCopied += bytesAdded
        let elapsed = Date().timeIntervalSince(progressTracker.copyStartTime)
        if elapsed > 0 {
            progressTracker.copySpeed = Double(progressTracker.totalBytesCopied) / (1024 * 1024) / elapsed
            // ETA update is handled by ProgressTracker internally
        }
    }

    @MainActor
    func updateETA() {
        // Delegate to ProgressTracker - kept for compatibility
        // The actual ETA calculation happens in ProgressTracker
    }

    func formattedETA() -> String {
        return progressTracker.formattedETA()
    }

    @MainActor
    func resetProgress() {
        progressTracker.resetAll()
    }

    @MainActor
    func initializeDestinations(_ destinations: [URL]) async {
        progressTracker.initializeDestinations(destinations)
    }

    @MainActor
    func incrementDestinationProgress(_ destinationName: String) {
        _ = progressTracker.incrementDestinationProgress(destinationName)
    }

    // MARK: - File Scanning (delegated to SourceManager)

    func getFormattedFileTypeSummary(groupRaw: Bool = false) -> String {
        sourceManager.getFormattedFileTypeSummary(groupRaw: groupRaw)
    }

    func getFilteredFilesSummary() -> (summary: String, willCopy: Int, total: Int)? {
        sourceManager.getFilteredFilesSummary()
    }

    func getDestinationEstimate(at index: Int) -> String? {
        destinationManager.getDestinationEstimate(at: index, sourceState: SourceEstimateState(
            sourceURL: sourceManager.sourceURL,
            sourceTotalBytes: sourceManager.sourceTotalBytes,
            sourceFileTypes: sourceManager.sourceFileTypes,
            isScanning: sourceManager.isScanning
        ))
    }
}

// MARK: - Backup Operations Extension

extension BackupManager {
    // Static checksum calculation method used by all backup engines
    // Now uses native Swift SHA-256 for maximum reliability with all file types
    nonisolated static func sha256ChecksumStatic(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool, isNetworkVolume _: Bool = false
    ) throws -> String {
        // First check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "ImageIntact", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(fileURL.lastPathComponent)"]
            )
        }

        // Special handling for files that might be in iCloud and not downloaded
        let resourceValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = resourceValues?.ubiquitousItemDownloadingStatus {
            // Status can be: .current, .downloaded, .notDownloaded
            if status == .notDownloaded {
                logWarning("File is in iCloud but not downloaded locally: \(fileURL.lastPathComponent)")
                throw NSError(
                    domain: "ImageIntact", code: 7,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "File is in iCloud but not downloaded: \(fileURL.lastPathComponent)",
                    ]
                )
            }
        }

        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw NSError(
                domain: "ImageIntact", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File is not readable: \(fileURL.lastPathComponent)"]
            )
        }

        // Use native Swift checksum as primary method for reliability
        return try calculateNativeChecksum(for: fileURL, shouldCancel: shouldCancel)
    }

    // Native Swift checksum using CryptoKit - now with optimized implementation
    private nonisolated static func calculateNativeChecksum(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool = { false }
    ) throws -> String {
        // Use the optimized checksum implementation for better performance
        do {
            return try OptimizedChecksum.sha256(for: fileURL, shouldCancel: shouldCancel)
        } catch let checksumError as ChecksumError {
            // Never swallow ChecksumError (includes .cancelled) — rethrow immediately
            throw checksumError
        } catch is CancellationError {
            // Never swallow Swift Task cancellation either
            throw ChecksumError.cancelled
        } catch {
            // Fall back to size-based checksum if file can't be read
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? Int64
            {
                let sizeHash = String(format: "%016x", size)
                return "size:\(sizeHash)"
            }
            throw error
        }
    }

}
