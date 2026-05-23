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
            let sanitized = SmartFolderName.sanitize(organizationName)
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
    let destinationAlertPresenter: DestinationAlertPresenting
    let backupAlertPresenter: BackupAlertPresenting
    private let deferredCleanupDelayNanos: UInt64
    internal var deferredCleanupTask: Task<Void, Never>?
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
    var currentOrchestrator: BackupOrchestrating?

    // MARK: - Initialization

    init(
        fileOperations: FileOperationsProtocol? = nil,
        notificationService: NotificationProtocol? = nil,
        driveAnalyzer: DriveAnalyzerProtocol? = nil,
        diskSpaceChecker: DiskSpaceProtocol? = nil,
        duplicateDetector: DuplicateDetectorProtocol? = nil,
        destinationAlertPresenter: DestinationAlertPresenting? = nil,
        backupAlertPresenter: BackupAlertPresenting? = nil,
        deferredCleanupDelayNanos: UInt64 = 10_000_000_000
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
        self.destinationAlertPresenter = destinationAlertPresenter ?? NSAlertDestinationPresenter()
        self.backupAlertPresenter = backupAlertPresenter ?? NSAlertBackupPresenter()
        self.deferredCleanupDelayNanos = deferredCleanupDelayNanos

        // Create delegated managers
        self.sourceManager = SourceManager(fileOperations: resolvedFileOps)
        self.destinationManager = DestinationManager(
            fileOperations: resolvedFileOps,
            driveAnalyzer: resolvedDriveAnalyzer,
            diskSpaceChecker: resolvedDiskSpace
        )

        // Initialize organization name from last used (if user previously customized).
        // Wrap in SmartFolderName.sanitize because didSet doesn't fire during init.
        if let lastUsedName = PreferencesManager.shared.lastUsedOrganizationFolderName {
            organizationName = SmartFolderName.sanitize(lastUsedName)
        }

        // Check for UI test mode
        if BackupManager.isRunningTests, ProcessInfo.processInfo.arguments.contains("--uitest") {
            loadUITestPaths()
            return
        }

        // Restore last session if enabled
        if PreferencesManager.shared.restoreLastSession {
            destinationManager.loadFromSession()
            if let restoredURL = sourceManager.loadFromSession(), !BackupManager.isRunningTests {
                Task { [sourceManager] in
                    await sourceManager.scanSourceFolder(restoredURL)
                }
            }
        } else {
            destinationManager.initializeEmpty()
            logInfo("Initialized with single empty destination slot")
        }

        // Validate and analyze loaded destinations
        destinationManager.validateAndAnalyzeDestinations()
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
    /// UI-bound forwarder. Trash logic + state clear lives in `SourceManager`;
    /// BackupManager just stores the result string for its alert binding.
    func trashSourceFolder() {
        trashSourceResult = sourceManager.trashCurrentSource()
    }

    func addDestination() {
        destinationManager.addDestination()
    }

    func setSource(_ url: URL) {
        sourceManager.prepareSource(at: url)
        // Auto-generate organization name from source path (cross-concern: a
        // backup-orchestration field derived from a source URL).
        organizationName = SmartFolderName.from(url: url)
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
            destinationAlertPresenter.presentSameAsSourceAlert()
        } catch DestinationError.duplicateDestination(let idx) {
            destinationAlertPresenter.presentDuplicateDestinationAlert(existingIndex: idx)
        } catch DestinationError.sourceTagConflict(let tagURL) {
            guard destinationAlertPresenter.presentSourceTagConflictAlert() else { return }
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
        // The TestSourcePath / TestOrganizationName UserDefaults overrides are
        // for UI testing only. Wrap in #if DEBUG so a malicious local process
        // can't `defaults write` an arbitrary path into a Full-Disk-Access-
        // granted release build to coerce the app into reading protected files.
        #if DEBUG
        logInfo("Loading UI test paths")

        // Load test source path
        if let testSourcePath = UserDefaults.standard.string(forKey: "TestSourcePath") {
            let sourceURL = URL(fileURLWithPath: testSourcePath)
            self.sourceManager.sourceURL = sourceURL
            organizationName = SmartFolderName.from(url: sourceURL)
            logInfo("UI Test: Set source to \(testSourcePath)")
        }

        destinationManager.loadUITestDestinations()

        // Load test organization name if provided
        if let testOrgName = UserDefaults.standard.string(forKey: "TestOrganizationName") {
            organizationName = testOrgName
            logInfo("UI Test: Set organization name to \(testOrgName)")
        }

        // Clear source test values (destination keys cleared by DestinationManager)
        UserDefaults.standard.removeObject(forKey: "TestSourcePath")
        UserDefaults.standard.removeObject(forKey: "TestOrganizationName")
        #else
        // Release builds: never honor UI-test UserDefaults overrides.
        destinationManager.initializeEmpty()
        #endif
    }

    func canRunBackup() -> Bool {
        return sourceURL != nil && !destinationURLs.compactMap { $0 }.isEmpty && !isProcessing
    }

    func runBackup() {
        // Low fix: isProcessing guard — prevent re-entrant runBackup.
        guard !isProcessing else {
            logWarning("runBackup called while already processing — ignoring")
            return
        }

        guard let source = sourceURL else {
            logWarning("Missing source folder.")
            return
        }

        // AMUX-207: scan in progress means sourceTotalBytes is reset to 0;
        // disk-space check below would trivially pass (requiredBytes=0)
        // even if destinations are full. Bail until the scan completes.
        guard !sourceManager.isScanning else {
            logWarning("runBackup called while source scan is in progress — ignoring")
            return
        }

        let destinations = destinationURLs.compactMap { $0 }
        // AMUX-208: empty-destinations guard. UI gates this via canRunBackup(),
        // but runBackup itself didn't — a programmatic re-entry could fall through.
        guard !destinations.isEmpty else {
            logWarning("runBackup called with no destinations — ignoring")
            return
        }

        // Check disk space for all destinations.
        // High fix: use sourceTotalBytes (set at scan time) not totalBytesToCopy
        // (a progress var that is 0 or stale before the orchestrator runs).
        let spaceChecks = diskSpaceChecker.checkAllDestinations(
            destinations: destinations,
            requiredBytes: sourceTotalBytes
        )

        let (canProceed, warnings, errors) = diskSpaceChecker.evaluateSpaceChecks(spaceChecks)

        // Insufficient space: show alert and abort.
        if !canProceed {
            backupAlertPresenter.presentInsufficientSpaceAlert(errors: errors)
            return
        }

        // Low space warning: let user decide whether to proceed.
        if !warnings.isEmpty {
            guard backupAlertPresenter.presentLowSpaceWarning(warnings: warnings) else { return }
        }

        // Pre-flight summary (if enabled).
        if PreferencesManager.shared.showPreflightSummary {
            let summary = buildPreflightSummary(source: source, destinations: destinations)
            let (proceed, showAgain) = backupAlertPresenter.presentPreflightSummary(summary)
            guard proceed else { return }
            PreferencesManager.shared.showPreflightSummary = showAgain
        }

        // State setup — reset everything cleanupMemory's deferred task would have
        // cleared so we don't depend on its timing (High fix: state leak on rapid restart).
        isProcessing = true
        statusMessage = "Preparing backup..."
        failedFiles = []
        statistics.reset()
        progressTracker.resetAll()
        logEntries = []
        sessionID = UUID().uuidString
        shouldCancel = false
        debugLog = []

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

    /// Build the data snapshot the preflight presenter needs.
    /// Pure data construction — no UI. Pulled out so runBackup is easy to read
    /// and the summary construction is testable in isolation.
    private func buildPreflightSummary(source: URL, destinations: [URL]) -> PreflightSummary {
        // Filtered summary (when a file-type filter is active).
        let filteredSummary = getFilteredFilesSummary()

        // Non-filtered file count and type summary (used when no filter is active).
        let nonFilteredTotalFiles = sourceFileTypes.values.reduce(0, +)
        let nonFilteredTypeSummary: String? = sourceFileTypes.isEmpty ? nil : getFormattedFileTypeSummary()

        // Build destination tuples with optional drive device names.
        // Zip the raw parallel arrays before filtering nils so indices stay aligned:
        // compactMap on destinationURLs alone would shift the index into
        // destinationItems if any earlier slot is nil.
        let validPairs: [(URL, DestinationItem)] = zip(destinationURLs, destinationItems).compactMap { url, item in
            guard let url = url else { return nil }
            return (url, item)
        }
        let destTuples: [(name: String, deviceName: String?)] = validPairs.map { url, item in
            let deviceName = destinationDriveInfo[item.id]?.deviceName
            let resolvedDeviceName = (deviceName?.isEmpty == false) ? deviceName : nil
            return (name: url.lastPathComponent, deviceName: resolvedDeviceName)
        }

        return PreflightSummary(
            sourceName: source.lastPathComponent,
            sourcePath: source.path,
            filteredSummary: filteredSummary,
            fileTypeSummary: nonFilteredTypeSummary,
            totalFiles: nonFilteredTotalFiles,
            totalBytes: sourceTotalBytes,
            destinations: destTuples,
            excludeCacheFiles: PreferencesManager.shared.excludeCacheFiles,
            skipHiddenFiles: PreferencesManager.shared.skipHiddenFiles,
            fileTypeFilterActive: !fileTypeFilter.includedExtensions.isEmpty
        )
    }

    func cancelOperation() {
        guard !shouldCancel else { return } // Prevent multiple cancellations

        // Local strong ref keeps orchestrator alive through end of this function
        // even after cleanupMemory nils currentOrchestrator. (Medium fix: deallocation race)
        let orchestratorRef = currentOrchestrator
        shouldCancel = true
        statusMessage = "Cancelling backup..."

        // Clean up any pending large backup confirmation.
        // Resumes the continuation with false to unblock the waiting backup.
        if let continuation = largeBackupContinuation {
            ApplicationLogger.shared.warning("Cleaning up pending large backup continuation due to cancellation", category: .backup)
            continuation.resume(returning: false)
            largeBackupContinuation = nil
            showLargeBackupConfirmation = false
            largeBackupInfo = nil
        }

        // Synchronous immediate state clear (was inside a Task; the deferral broke the
        // new `guard !isProcessing` in runBackup on rapid cancel→backup). (Medium fix)
        for name in progressTracker.destinationProgress.keys {
            progressTracker.setDestinationProgress(0, for: name)
            progressTracker.setDestinationState("cancelled", for: name)
        }
        currentFileName = ""
        currentDestinationName = ""
        overallStatusText = ""
        currentPhase = .idle
        statusMessage = "Backup cancelled"
        progressTracker.resetAll()
        SleepPrevention.shared.stopPreventingSleep()

        // Blocker fix: cancel synchronously against retained ref BEFORE cleanupMemory
        // nils currentOrchestrator. Previously this was in a Task — cancel never reached
        // the orchestrator because cleanupMemory ran first and nil'd the reference.
        orchestratorRef?.cancel()

        // Flip the gating flag AFTER orchestrator cancel propagates. (Medium fix: ordering)
        isProcessing = false

        // Resource cleanup can stay async — not on the rapid-restart path.
        Task { [weak self] in
            await self?.resourceManager.cleanup()
        }

        cleanupMemory()
    }

    /// Force memory cleanup after backup completion or cancellation.
    func cleanupMemory() {
        // Immediate cleanup — clear large data structures.
        logEntries.removeAll(keepingCapacity: false)
        debugLog.removeAll(keepingCapacity: false)

        // DON'T clear failedFiles - needed for completion report
        // DON'T clear statistics - needed for completion report
        // DON'T clear progress data yet - UI may still need it
        // DON'T clear sourceFileTypes - needed for UI display

        // Clear orchestrator reference.
        currentOrchestrator = nil

        // Note: Core Data will manage its own memory.
        EventLogger.shared.resetContexts()

        // Low fix: removed two empty autoreleasepool {} calls (drained nothing).

        logInfo("Initial memory cleanup completed", category: .performance)

        // High fix: cancel any prior deferred task; capture session id; bail on mismatch.
        // Prevents a prior backup's deferred cleanup from wiping a new backup's state.
        deferredCleanupTask?.cancel()
        let capturedSessionID = sessionID
        let capturedDelayNanos = deferredCleanupDelayNanos
        deferredCleanupTask = Task { @MainActor [weak self] in
            // Bail early if self is already gone — no point sleeping for 10s
            // just to do nothing on wake (would leave a zombie task in the pool).
            guard self != nil else { return }
            try? await Task.sleep(for: .nanoseconds(Int(capturedDelayNanos)))
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            guard self.sessionID == capturedSessionID else {
                logInfo("Deferred cleanup bailed: session changed", category: .performance)
                return
            }

            self.failedFiles.removeAll(keepingCapacity: false)
            self.progressTracker.resetAll()
            self.progressTracker.destinationProgress.removeAll(keepingCapacity: false)
            self.progressTracker.destinationStates.removeAll(keepingCapacity: false)
            self.statistics.reset()
            self.statusMessage = ""
            self.overallStatusText = ""
            // Keep scanProgress - it shows the file type summary

            ChecksumBufferPool.shared.cleanupUnusedBuffers()
            logInfo("Deep memory cleanup completed", category: .performance)
        }
    }

    // MARK: - Source Tag Delegation

    func checkForSourceTag(at url: URL) -> Bool {
        sourceManager.checkForSourceTag(at: url)
    }

    // MARK: - Progress Forwarding

    func formattedETA() -> String {
        return progressTracker.formattedETA()
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
