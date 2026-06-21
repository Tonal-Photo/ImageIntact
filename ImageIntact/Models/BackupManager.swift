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
    let preferences: PreferencesProviding

    // MARK: - Delegated Managers

    let sourceManager: SourceManager
    let destinationManager: DestinationManager

    // MARK: - Transient Run State (AMUX-201)

    // Transient per-run backup state extracted into BackupState (#103 decomposition).
    let state = BackupState()

    // Modal-presentation flags, destination/source forwarding, and delegated
    // scanning/progress accessors live in BackupManager+Forwarding.swift (AMUX-230).

    // Progress tracking delegated to ProgressTracker.
    // AMUX-206: `var` (not `let`) so runBackup can swap in a fresh instance per
    // session. A cancelled run's orchestrator may still be spinning down and
    // writing late; pointing the new run at a fresh tracker routes those writes
    // to an orphaned instance instead of corrupting the new run's state.
    var progressTracker = ProgressTracker()

    // Statistics tracking for completion report
    let statistics = BackupStatistics()

    // Progress state lives on `progressTracker` — read `progressTracker.X`
    // directly (see #103).

    // Resource management
    let resourceManager = ResourceManager() // Made internal for extension access

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

    // Duplicate detection state
    var enableDuplicateDetection: Bool {
        preferences.enableSmartDuplicateDetection
    }

    let duplicateDetector: DuplicateDetectorProtocol
    let destinationAlertPresenter: DestinationAlertPresenting
    let backupAlertPresenter: BackupAlertPresenting
    private let deferredCleanupDelayNanos: UInt64
    internal var deferredCleanupTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        fileOperations: FileOperationsProtocol? = nil,
        notificationService: NotificationProtocol? = nil,
        driveAnalyzer: DriveAnalyzerProtocol? = nil,
        diskSpaceChecker: DiskSpaceProtocol? = nil,
        duplicateDetector: DuplicateDetectorProtocol? = nil,
        destinationAlertPresenter: DestinationAlertPresenting? = nil,
        backupAlertPresenter: BackupAlertPresenting? = nil,
        preferences: PreferencesProviding = PreferencesManager.shared,
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
        self.preferences = preferences
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
        if let lastUsedName = preferences.lastUsedOrganizationFolderName {
            organizationName = SmartFolderName.sanitize(lastUsedName)
        }

        // Check for UI test mode. Gated on the argument alone (not
        // isRunningTests): XCTestConfigurationFilePath exists in the XCUITest
        // RUNNER process, never in the app process it launches, so requiring
        // it meant this branch could never fire under UI tests. DEBUG-only —
        // release builds never honor the seam.
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--uitest") {
                loadUITestPaths()
                return
            }
        #endif

        // Restore last session if enabled
        if preferences.restoreLastSession {
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
        BookmarkManager.clearBookmark(forKey: BookmarkManager.sourceKey)
        destinationManager.clearAll()
    }

    /// Move the source folder to Trash after successful backup
    @MainActor
    /// UI-bound forwarder. Trash logic + state clear lives in `SourceManager`;
    /// BackupManager just stores the result string for its alert binding.
    func trashSourceFolder() {
        state.trashSourceResult = sourceManager.trashCurrentSource()
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
                totalBytesToCopy: progressTracker.totalBytesToCopy
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
                    totalBytesToCopy: progressTracker.totalBytesToCopy
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

    // loadUITestPaths lives in BackupManager+UITestSupport.swift (AMUX-230).

    func canRunBackup() -> Bool {
        return sourceURL != nil
            && !destinationURLs.compactMap { $0 }.isEmpty
            && !state.isProcessing
            && !sourceManager.isScanning
    }

    func runBackup() {
        // Low fix: isProcessing guard — prevent re-entrant runBackup.
        guard !state.isProcessing else {
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
        if preferences.showPreflightSummary {
            let summary = buildPreflightSummary(source: source, destinations: destinations)
            let (proceed, showAgain) = backupAlertPresenter.presentPreflightSummary(summary)
            guard proceed else { return }
            preferences.showPreflightSummary = showAgain
        }

        // State setup — reset everything cleanupMemory's deferred task would have
        // cleared so we don't depend on its timing (High fix: state leak on rapid restart).
        state.isProcessing = true
        state.statusMessage = "Preparing backup..."
        state.failedFiles = []
        statistics.reset()
        // AMUX-206: assign a FRESH tracker rather than resetAll() the shared one,
        // so a cancelled run's still-spinning-down orchestrator writes to an
        // orphaned instance and never this new run's state. A fresh instance is
        // already in reset state, so this subsumes the prior resetAll() call.
        progressTracker = ProgressTracker()
        state.logEntries = []
        state.sessionID = UUID().uuidString
        state.shouldCancel = false
        state.debugLog = []
        // A fresh run must not inherit the prior run's duplicate decision:
        // the analyses describe the old run's manifest and the skip flags
        // belong to a dialog not yet answered this run. Cleared here (not in
        // resetBackupState) because continuation re-entries bypass runBackup
        // and need both to survive (gh#141). Values are BackupState defaults.
        state.duplicateAnalyses = nil
        state.skipExactDuplicates = true
        state.skipRenamedDuplicates = false

        // Save organization folder name to recent list and as last used
        if !organizationName.isEmpty {
            preferences.addRecentOrganizationFolderName(organizationName)
            preferences.lastUsedOrganizationFolderName = organizationName
        }

        // Start preventing sleep
        SleepPrevention.shared.startPreventingSleep(
            reason: "ImageIntact backup to \(destinations.count) destination(s)")

        // Use the new queue-based backup system for parallel destination processing
        Task { [weak self] in
            await self?.performQueueBasedBackup(source: source, destinations: destinations)
        }
    }

    // buildPreflightSummary lives in BackupManager+Preflight.swift (AMUX-230).

    func cancelOperation() {
        guard !state.shouldCancel else { return } // Prevent multiple cancellations

        // Local strong ref keeps orchestrator alive through end of this function
        // even after cleanupMemory nils currentOrchestrator. (Medium fix: deallocation race)
        let orchestratorRef = state.currentOrchestrator
        state.shouldCancel = true
        state.statusMessage = "Cancelling backup..."

        // Clean up any pending large backup confirmation.
        // Resumes the continuation with false to unblock the waiting backup.
        if let continuation = state.largeBackupContinuation {
            ApplicationLogger.shared.warning("Cleaning up pending large backup continuation due to cancellation", category: .backup)
            continuation.resume(returning: false)
            state.largeBackupContinuation = nil
            showLargeBackupConfirmation = false
            state.largeBackupInfo = nil
        }

        // Synchronous immediate state clear (was inside a Task; the deferral broke the
        // new `guard !isProcessing` in runBackup on rapid cancel→backup). (Medium fix)
        for name in progressTracker.destinationProgress.keys {
            progressTracker.setDestinationProgress(0, for: name)
            progressTracker.setDestinationState("cancelled", for: name)
        }
        progressTracker.currentFileName = ""
        progressTracker.currentDestinationName = ""
        state.overallStatusText = ""
        state.currentPhase = .idle
        state.statusMessage = "Backup cancelled"
        // AMUX-210: use markAsCancelled() instead of resetAll(). resetAll wipes
        // destinationStates, which would flash-and-disappear the "cancelled" badges
        // we just set above. markAsCancelled clears transient metrics (counts,
        // bytes, speed, ETA) but preserves the destinationProgress/States dicts.
        progressTracker.markAsCancelled()
        SleepPrevention.shared.stopPreventingSleep()

        // Blocker fix: cancel synchronously against retained ref BEFORE cleanupMemory
        // nils currentOrchestrator. Previously this was in a Task — cancel never reached
        // the orchestrator because cleanupMemory ran first and nil'd the reference.
        orchestratorRef?.cancel()

        // Flip the gating flag AFTER orchestrator cancel propagates. (Medium fix: ordering)
        state.isProcessing = false

        // Resource cleanup can stay async — not on the rapid-restart path.
        Task { [weak self] in
            await self?.resourceManager.cleanup()
        }

        cleanupMemory()
    }

    /// Force memory cleanup after backup completion or cancellation.
    ///
    /// - Parameter expectedSessionID: when non-nil, the session this cleanup was
    ///   scheduled for. If a newer backup has since replaced `state.sessionID`, the
    ///   call bails entirely — a prior backup's deferred cleanup must not wipe the
    ///   live run's progressTracker/statistics mid-copy (AMUX-488). `nil` (the
    ///   synchronous `cancelOperation` caller) always runs.
    func cleanupMemory(expectedSessionID: String? = nil) {
        // AMUX-488: re-check the pinned session HERE, at execution time, because the
        // QueueIntegration defer delays this call ~3s — long enough for a rerun to
        // start and install its own session. If this cleanup belongs to a superseded
        // backup, bail before touching any shared state (including the deferred
        // resetAll that would zero the live run's global completion counters).
        if let expectedSessionID, state.sessionID != expectedSessionID {
            logInfo("cleanupMemory skipped: session changed (\(expectedSessionID) no longer current)", category: .performance)
            return
        }

        // Immediate cleanup — clear large data structures.
        state.logEntries.removeAll(keepingCapacity: false)
        state.debugLog.removeAll(keepingCapacity: false)

        // DON'T clear failedFiles - needed for completion report
        // DON'T clear statistics - needed for completion report
        // DON'T clear progress data yet - UI may still need it
        // DON'T clear sourceFileTypes - needed for UI display

        // Clear orchestrator reference.
        state.currentOrchestrator = nil

        // Note: Core Data will manage its own memory.
        EventLogger.shared.resetContexts()

        // Low fix: removed two empty autoreleasepool {} calls (drained nothing).

        logInfo("Initial memory cleanup completed", category: .performance)

        // High fix: cancel any prior deferred task; capture session id; bail on mismatch.
        // Prevents a prior backup's deferred cleanup from wiping a new backup's state.
        deferredCleanupTask?.cancel()
        let capturedSessionID = state.sessionID
        let capturedDelayNanos = deferredCleanupDelayNanos
        deferredCleanupTask = Task { @MainActor [weak self] in
            // Bail early if self is already gone — no point sleeping for 10s
            // just to do nothing on wake (would leave a zombie task in the pool).
            guard self != nil else { return }
            try? await Task.sleep(for: .nanoseconds(Int(capturedDelayNanos)))
            guard !Task.isCancelled else { return }
            guard let self = self else { return }
            guard self.state.sessionID == capturedSessionID else {
                logInfo("Deferred cleanup bailed: session changed", category: .performance)
                return
            }

            self.state.failedFiles.removeAll(keepingCapacity: false)
            self.progressTracker.resetAll()
            self.progressTracker.destinationProgress.removeAll(keepingCapacity: false)
            self.progressTracker.destinationStates.removeAll(keepingCapacity: false)
            self.statistics.reset()
            self.state.statusMessage = ""
            self.state.overallStatusText = ""
            // Keep scanProgress - it shows the file type summary

            ChecksumBufferPool.shared.cleanupUnusedBuffers()
            logInfo("Deep memory cleanup completed", category: .performance)
        }
    }

    // Source-tag, progress, and file-scanning delegation live in
    // BackupManager+Forwarding.swift (AMUX-230).
}
