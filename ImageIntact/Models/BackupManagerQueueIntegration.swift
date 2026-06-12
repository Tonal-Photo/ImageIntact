import Foundation

// MARK: - File Manifest Entry

public struct FileManifestEntry {
    public let relativePath: String
    public let sourceURL: URL
    public let checksum: String
    public let size: Int64
}

// MARK: - Queue-Based Backup Integration

extension BackupManager {
    /// Performs backup using the new smart queue system with BackupOrchestrator
    /// Each destination runs independently at its own speed
    @MainActor
    func performQueueBasedBackup(source: URL, destinations: [URL]) async {
        let backupID = UUID().uuidString.prefix(8)
        ApplicationLogger.shared.debug(
            "Starting backup \(backupID): \(source.lastPathComponent) → \(destinations.count) destination(s)",
            category: .backup
        )

        // Reset state
        resetBackupState()

        // Build manifest once for all preflight checks
        // This is more efficient than building it multiple times
        // NOTE: We must start security-scoped access here for the preflight manifest
        // The orchestrator will start it again for the actual backup (Apple allows nested calls)
        ApplicationLogger.shared.debug(
            "Building manifest for preflight checks - Source: \(source.path), Filter: \(fileTypeFilter.description)",
            category: .backup
        )

        state.statusMessage = "Analyzing source files..."

        // Start security access for preflight manifest building
        // This will be stopped after preflight checks, before orchestrator starts
        let preflightAccess = source.startAccessingSecurityScopedResource()
        // UI-test fixture paths live in the app container: start() returns
        // false (no bookmark scope) but access works. DEBUG-only escape.
        guard preflightAccess || UITestSeam.allowsUnscopedAccess(source) else {
            ApplicationLogger.shared.debug("Failed to access source folder for preflight checks", category: .backup)
            state.isProcessing = false
            state.statusMessage = "Cannot access source folder - permission denied"
            return
        }

        let manifestBuilder = ManifestBuilder()
        let preflightManifest = await manifestBuilder.build(
            source: source,
            shouldCancel: { [weak self] in self?.state.shouldCancel ?? true },
            filter: fileTypeFilter,
            includeSubdirectories: includeSubdirectories
        )

        guard let preflightManifest = preflightManifest else {
            // Stop access before returning
            if preflightAccess {
                source.stopAccessingSecurityScopedResource()
            }
            ApplicationLogger.shared.debug("Manifest build failed or was cancelled", category: .backup)
            state.isProcessing = false
            state.statusMessage = "Backup cancelled or failed"
            return
        }

        ApplicationLogger.shared.debug("Preflight manifest built: \(preflightManifest.count) files", category: .backup)
        if preflightManifest.count > 0 {
            let totalBytes = preflightManifest.reduce(0) { $0 + $1.size }
            ApplicationLogger.shared.debug("Total size: \(totalBytes) bytes (\(Double(totalBytes) / 1_000_000_000) GB)", category: .backup)
        }

        // Capture manifest build timestamp for staleness detection
        let manifestTimestamp = Date()

        // Yield control to UI after manifest building
        await Task.yield()

        // Check for migration if organization is enabled
        if !organizationName.isEmpty {
            await checkForMigration(
                source: source, destinations: destinations, manifest: preflightManifest
            )

            // If migration dialog is shown, wait for user decision
            if showMigrationDialog, !state.pendingMigrationPlans.isEmpty {
                ApplicationLogger.shared.debug("Waiting for migration decision", category: .backup)
                // Stop preflight security access before waiting for user
                if preflightAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                // The actual backup will be triggered after migration dialog closes
                state.isProcessing = false
                return
            }
        }

        // Check for duplicates before proceeding
        if enableDuplicateDetection {
            await checkForDuplicates(
                source: source, destinations: destinations, manifest: preflightManifest
            )

            // If duplicate dialog is shown, wait for user decision
            if showDuplicateWarning, state.duplicateAnalyses != nil {
                ApplicationLogger.shared.debug("Waiting for duplicate handling decision", category: .backup)
                // Stop preflight security access before waiting for user
                if preflightAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                // The actual backup will be triggered after duplicate dialog closes
                state.isProcessing = false
                return
            }
        }

        // Check for large backup before starting orchestrator
        ApplicationLogger.shared.debug("About to check for large backup \(backupID)", category: .backup)
        let shouldProceed = await checkForLargeBackupAndWait(
            source: source, destinations: destinations, manifest: preflightManifest
        )
        ApplicationLogger.shared.debug("Large backup check \(backupID) returned: \(shouldProceed)", category: .backup)

        if !shouldProceed {
            // User cancelled the large backup
            // Stop preflight security access
            ApplicationLogger.shared.debug("User cancelled backup \(backupID) - stopping", category: .backup)
            if preflightAccess {
                source.stopAccessingSecurityScopedResource()
            }
            state.isProcessing = false
            state.statusMessage = "Backup cancelled"
            return
        }

        // Preflight checks complete - stop our temporary security access
        // The orchestrator will start its own access
        ApplicationLogger.shared.debug("User confirmed backup \(backupID) - proceeding with orchestrator", category: .backup)
        if preflightAccess {
            source.stopAccessingSecurityScopedResource()
            ApplicationLogger.shared.debug("Stopped preflight security access, orchestrator will start its own", category: .backup)
        }

        // Validate manifest isn't stale (user didn't modify files during dialogs)
        let timeSinceManifest = Date().timeIntervalSince(manifestTimestamp)
        ApplicationLogger.shared.debug("Time since manifest built: \(Int(timeSinceManifest)) seconds", category: .backup)

        // If more than 5 minutes have passed, warn and rebuild
        if timeSinceManifest > 300 {
            ApplicationLogger.shared.debug("Manifest is stale (> 5 minutes old), should rebuild", category: .backup)
            // For now just log - in future could rebuild automatically
            // Not failing here because it's an edge case and rebuild would be disruptive
        }

        // Validate source and destinations are still accessible before proceeding
        guard validateLocationsAccessible(source: source, destinations: destinations) else {
            return
        }

        // Start statistics tracking
        statistics.startBackup(sourceFiles: sourceFileTypes, filter: fileTypeFilter)

        // Store the session ID that will be used by Core Data
        // (BackupOrchestrator will use this same ID)

        defer {
            state.isProcessing = false
            state.shouldCancel = false
            state.currentOrchestrator = nil
            state.duplicateAnalyses = nil // Clear duplicate analyses after backup

            // Schedule cleanup after a delay so UI can read the stats first
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds - give UI time to show stats
                self?.cleanupMemory()
                ApplicationLogger.shared.debug("Memory cleanup completed after UI update", category: .backup)
            }
        }

        // Create orchestrator with our components
        let orchestrator = BackupOrchestrator(
            progressTracker: progressTracker,
            resourceManager: resourceManager
        )

        // Set up callbacks
        orchestrator.onStatusUpdate = { [weak self] status in
            self?.state.statusMessage = status
        }

        orchestrator.onFailedFile = { [weak self] file, destination, error in
            self?.state.failedFiles.append((file: file, destination: destination, error: error))

            // Track in statistics
            if let fileURL = URL(string: file),
               let fileType = ImageFileType.from(fileExtension: fileURL.pathExtension)
            {
                self?.statistics.recordFileProcessed(
                    fileType: fileType,
                    size: 0,
                    destination: destination,
                    success: false
                )
            }
        }

        orchestrator.onPhaseChange = { [weak self] phase in
            self?.state.currentPhase = phase
        }

        // Store reference for cancellation
        state.currentOrchestrator = orchestrator

        // Build destination item IDs array for drive info lookup
        let destinationItemIDs = destinationItems.prefix(destinations.count).map { $0.id }

        // Perform the backup with file type filter and duplicate preferences
        // Pass the preflight manifest to avoid rebuilding it
        ApplicationLogger.shared.debug("Passing preflight manifest to orchestrator for backup \(backupID)", category: .backup)
        let failures = await orchestrator.performBackup(
            source: source,
            destinations: destinations,
            driveInfo: destinationDriveInfo,
            destinationItemIDs: destinationItemIDs,
            filter: fileTypeFilter,
            organizationName: organizationName,
            sessionID: state.sessionID,
            prebuiltManifest: preflightManifest,
            duplicateAnalyses: state.duplicateAnalyses,
            skipExactDuplicates: state.skipExactDuplicates,
            skipRenamedDuplicates: state.skipRenamedDuplicates
        )

        // Add any failures to our list (avoiding duplicates)
        for failure in failures {
            if !state.failedFiles.contains(where: {
                $0.file == failure.file && $0.destination == failure.destination
            }) {
                state.failedFiles.append(failure)
            }
        }

        // Populate statistics and handle completion
        populateStatistics(failures: failures, destinations: destinations)
        await handleBackupCompletion(destinations: destinations)
    }

    // MARK: - Backup State Management

    /// Reset all backup state at the start of a new backup
    @MainActor
    private func resetBackupState() {
        state.isProcessing = true
        state.shouldCancel = false
        state.statusMessage = "Preparing backup..."
        state.failedFiles = []
        state.sessionID = UUID().uuidString
        state.logEntries = []
        state.debugLog = []
    }

    /// Validate that all locations are still accessible before starting backup
    @MainActor
    private func validateLocationsAccessible(source: URL, destinations: [URL]) -> Bool {
        // Validate source is still accessible
        let validationAccess = source.startAccessingSecurityScopedResource()
        if !validationAccess && !UITestSeam.allowsUnscopedAccess(source) {
            ApplicationLogger.shared.debug("Source folder is no longer accessible - permission revoked or drive removed", category: .backup)
            state.isProcessing = false
            state.statusMessage = "Cannot access source folder - please check permissions and try again"
            return false
        }
        if validationAccess {
            source.stopAccessingSecurityScopedResource()
        }

        // Also validate all destinations are accessible
        for destination in destinations {
            let destAccess = destination.startAccessingSecurityScopedResource()
            if !destAccess && !UITestSeam.allowsUnscopedAccess(destination) {
                ApplicationLogger.shared.debug("Destination \(destination.lastPathComponent) is no longer accessible", category: .backup)
                state.isProcessing = false
                state.statusMessage =
                    "Cannot access destination '\(destination.lastPathComponent)' - please check connection and try again"
                return false
            }
            if destAccess {
                destination.stopAccessingSecurityScopedResource()
            }
        }

        ApplicationLogger.shared.debug("Validated all locations accessible before starting orchestrator", category: .backup)
        return true
    }

    /// Populate statistics from backup results
    @MainActor
    private func populateStatistics(
        failures: [(file: String, destination: String, error: String)],
        destinations _: [URL]
    ) {
        let totalFiles = progressTracker.totalFiles
        let processedFiles = progressTracker.processedFiles
        let failedCount = failures.count

        // Update overall stats from progress tracker
        // Use the actual manifest count for files processed, not the sum across destinations
        statistics.totalFilesProcessed = min(processedFiles, totalFiles)
        statistics.totalFilesFailed = failedCount
        statistics.totalFilesInSource = totalFiles

        // Debug logging to diagnose the issue
        ApplicationLogger.shared.debug(
            "Statistics Debug - sourceTotalBytes: \(sourceManager.sourceTotalBytes), totalBytesCopied: \(progressTracker.totalBytesCopied), totalBytesToCopy: \(progressTracker.totalBytesToCopy), copySpeed: \(progressTracker.copySpeed)",
            category: .backup
        )

        // Fix: Use the actual total bytes from source, not the copied bytes which may be 0
        statistics.totalBytesProcessed =
            sourceManager.sourceTotalBytes > 0
                ? sourceManager.sourceTotalBytes : progressTracker.totalBytesCopied

        ApplicationLogger.shared.debug(
            "Statistics - totalBytesProcessed: \(statistics.totalBytesProcessed), duration: \(statistics.duration ?? 0), averageThroughput: \(statistics.averageThroughput)",
            category: .backup
        )

        // Estimate file type breakdown from source scan
        for (fileType, count) in sourceFileTypes {
            if fileTypeFilter.shouldInclude(fileType: fileType) {
                var typeStats = FileTypeStatistics(fileType: fileType)
                typeStats.filesProcessed = count
                typeStats.totalBytes = Int64(count) * Int64(fileType.averageFileSize)
                statistics.fileTypeStats[fileType] = typeStats
            }
        }

        // Update destination stats from progress tracker
        for (destName, progress) in progressTracker.destinationProgress {
            let destFailures = failures.filter { $0.destination.contains(destName) }.count
            // Calculate actual bytes written per destination (divide by number of destinations)
            let bytesPerDest =
                sourceManager.sourceTotalBytes > 0
                    ? sourceManager.sourceTotalBytes
                    : (progressTracker.totalBytesCopied / Int64(max(1, destinationItems.count)))
            statistics.destinationStats[destName] = DestinationStatistics(
                destinationName: destName,
                filesCopied: progress - destFailures,
                filesSkipped: 0,
                filesFailed: destFailures,
                bytesWritten: bytesPerDest,
                timeElapsed: statistics.duration ?? 0,
                averageSpeed: progressTracker.copySpeed
            )
        }

        // Complete statistics and show report
        statistics.completeBackup()
    }

    // handleBackupCompletion lives in BackupManager+Completion.swift (AMUX-230).

    // MARK: - Migration Support

    /// Check if migration is needed for organizing existing files
    @MainActor
    private func checkForMigration(source: URL, destinations: [URL], manifest: [FileManifestEntry])
        async
    {
        ApplicationLogger.shared.debug("Checking for migration opportunities", category: .backup)

        // Check for cancellation
        guard !state.shouldCancel else {
            ApplicationLogger.shared.debug("Migration check cancelled", category: .backup)
            return
        }

        state.pendingMigrationPlans.removeAll()

        // Start security-scoped access for source
        let sourceAccessGranted = source.startAccessingSecurityScopedResource()
        defer {
            if sourceAccessGranted {
                source.stopAccessingSecurityScopedResource()
            }
        }

        let detector = BackupMigrationDetector()

        // Check each destination for migration needs
        for (_, destination) in destinations.enumerated() {
            if let plan = await detector.checkForMigrationNeeded(
                source: source,
                destination: destination,
                organizationName: organizationName,
                manifest: manifest
            ) {
                ApplicationLogger.shared.debug("Migration needed for \(destination.lastPathComponent): \(plan.fileCount) files", category: .backup)
                state.pendingMigrationPlans.append(plan)
            }
        }

        // Show migration dialog if needed
        if !state.pendingMigrationPlans.isEmpty {
            showMigrationDialog = true
        }
    }

    /// Continue backup after migration decision
    @MainActor
    func continueBackupAfterMigration() async {
        ApplicationLogger.shared.debug("Continuing backup after migration", category: .backup)
        showMigrationDialog = false

        // Re-run the backup now that migration is handled
        if let source = sourceURL {
            let destinations = destinationItems.compactMap { $0.url }
            await performQueueBasedBackup(source: source, destinations: destinations)
        }
    }

    /// Check for duplicate files at destinations
    @MainActor
    private func checkForDuplicates(source _: URL, destinations: [URL], manifest: [FileManifestEntry])
        async
    {
        ApplicationLogger.shared.debug("Checking for duplicate files", category: .backup)

        // Check for cancellation
        guard !state.shouldCancel else {
            ApplicationLogger.shared.debug("Duplicate check cancelled", category: .backup)
            return
        }

        state.statusMessage = "Analyzing for duplicates..."

        // Perform duplicate analysis for all destinations
        let analyses = await duplicateDetector.preflightDuplicateCheck(
            manifest: manifest,
            destinations: destinations,
            organizationName: organizationName
        )

        // Check if any duplicates were found
        let totalDuplicates = analyses.values.reduce(0) { $0 + $1.totalDuplicates }

        if totalDuplicates > 0 {
            ApplicationLogger.shared.debug("Found \(totalDuplicates) duplicate files across destinations", category: .backup)
            state.duplicateAnalyses = analyses
            showDuplicateWarning = true
        } else {
            ApplicationLogger.shared.debug("No duplicates found", category: .backup)
            state.duplicateAnalyses = nil
            showDuplicateWarning = false
        }
    }

    /// Continue backup after duplicate handling decision
    @MainActor
    func continueBackupAfterDuplicateDecision(skipExact: Bool, skipRenamed: Bool) async {
        ApplicationLogger.shared.debug("Continuing backup with duplicate preferences", category: .backup)
        showDuplicateWarning = false
        state.skipExactDuplicates = skipExact
        state.skipRenamedDuplicates = skipRenamed

        // Re-run the backup now that duplicate handling is decided
        if let source = sourceURL {
            let destinations = destinationItems.compactMap { $0.url }
            await performQueueBasedBackup(source: source, destinations: destinations)
        }
    }

    /// Cancel backup from duplicate warning
    @MainActor
    func cancelBackupFromDuplicateWarning() {
        ApplicationLogger.shared.debug("Backup cancelled by user from duplicate warning", category: .backup)
        showDuplicateWarning = false
        state.duplicateAnalyses = nil
        state.isProcessing = false
        state.statusMessage = "Backup cancelled"
    }

    // checkForLargeBackupAndWait + respondToLargeBackupConfirmation live in
    // BackupManager+LargeBackup.swift (AMUX-230).
}
