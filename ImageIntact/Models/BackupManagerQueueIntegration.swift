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
        print("🚀🚀🚀 [BACKUP \(backupID)] ENTRY: performQueueBasedBackup called")
        print("   - Source: \(source.path)")
        print("   - Destinations: \(destinations.count)")
        print("   - Thread: \(Thread.current)")
        print("   - isProcessing: \(isProcessing)")
        print("🚀 Starting QUEUE-BASED backup with orchestrator")

        // Reset state
        isProcessing = true
        shouldCancel = false
        statusMessage = "Preparing backup..."
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        debugLog = []

        // Build manifest once for all preflight checks
        // This is more efficient than building it multiple times
        // NOTE: We must start security-scoped access here for the preflight manifest
        // The orchestrator will start it again for the actual backup (Apple allows nested calls)
        print("🔨 Building manifest for preflight checks...")
        print("   - Source: \(source.path)")
        print("   - File type filter: \(fileTypeFilter.description)")

        statusMessage = "Analyzing source files..."

        // Start security access for preflight manifest building
        // This will be stopped after preflight checks, before orchestrator starts
        let preflightAccess = source.startAccessingSecurityScopedResource()
        guard preflightAccess else {
            print("❌ Failed to access source folder for preflight checks")
            isProcessing = false
            statusMessage = "Cannot access source folder - permission denied"
            return
        }

        let manifestBuilder = ManifestBuilder()
        let preflightManifest = await manifestBuilder.build(
            source: source,
            shouldCancel: { [weak self] in self?.shouldCancel ?? true },
            filter: fileTypeFilter
        )

        guard let preflightManifest = preflightManifest else {
            // Stop access before returning
            if preflightAccess {
                source.stopAccessingSecurityScopedResource()
            }
            print("❌ Manifest build failed or was cancelled")
            isProcessing = false
            statusMessage = "Backup cancelled or failed"
            return
        }

        print("📋 Preflight manifest built: \(preflightManifest.count) files")
        if preflightManifest.count > 0 {
            let totalBytes = preflightManifest.reduce(0) { $0 + $1.size }
            print("   - Total size: \(totalBytes) bytes (\(Double(totalBytes) / 1_000_000_000) GB)")
        }

        // Yield control to UI after manifest building
        await Task.yield()

        // Check for migration if organization is enabled
        if !organizationName.isEmpty {
            await checkForMigration(source: source, destinations: destinations, manifest: preflightManifest)

            // If migration dialog is shown, wait for user decision
            if showMigrationDialog && !pendingMigrationPlans.isEmpty {
                print("⏸️ Waiting for migration decision...")
                // Stop preflight security access before waiting for user
                if preflightAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                // The actual backup will be triggered after migration dialog closes
                isProcessing = false
                return
            }
        }

        // Check for duplicates before proceeding
        if enableDuplicateDetection {
            await checkForDuplicates(source: source, destinations: destinations, manifest: preflightManifest)

            // If duplicate dialog is shown, wait for user decision
            if showDuplicateWarning && duplicateAnalyses != nil {
                print("⏸️ Waiting for duplicate handling decision...")
                // Stop preflight security access before waiting for user
                if preflightAccess {
                    source.stopAccessingSecurityScopedResource()
                }
                // The actual backup will be triggered after duplicate dialog closes
                isProcessing = false
                return
            }
        }

        // Check for large backup before starting orchestrator
        print("🔍 [BACKUP \(backupID)] About to check for large backup...")
        let shouldProceed = await checkForLargeBackupAndWait(source: source, destinations: destinations, manifest: preflightManifest)
        print("🔍 [BACKUP \(backupID)] Large backup check returned: \(shouldProceed)")

        if !shouldProceed {
            // User cancelled the large backup
            // Stop preflight security access
            print("❌ [BACKUP \(backupID)] User cancelled - stopping")
            if preflightAccess {
                source.stopAccessingSecurityScopedResource()
            }
            isProcessing = false
            statusMessage = "Backup cancelled"
            return
        }

        // Preflight checks complete - stop our temporary security access
        // The orchestrator will start its own access
        print("✅ [BACKUP \(backupID)] User confirmed - proceeding with orchestrator")
        if preflightAccess {
            source.stopAccessingSecurityScopedResource()
            print("✅ Stopped preflight security access, orchestrator will start its own")
        }

        // Start statistics tracking
        statistics.startBackup(sourceFiles: sourceFileTypes, filter: fileTypeFilter)
        
        // Store the session ID that will be used by Core Data
        // (BackupOrchestrator will use this same ID)
        
        defer {
            isProcessing = false
            shouldCancel = false
            currentOrchestrator = nil
            duplicateAnalyses = nil  // Clear duplicate analyses after backup
            
            // Schedule cleanup after a delay so UI can read the stats first
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds - give UI time to show stats
                self?.cleanupMemory()
                print("✅ Memory cleanup completed after UI update")
            }
        }
        
        // Create orchestrator with our components
        let orchestrator = BackupOrchestrator(
            progressTracker: progressTracker,
            resourceManager: resourceManager
        )
        
        // Set up callbacks
        orchestrator.onStatusUpdate = { [weak self] status in
            self?.statusMessage = status
        }
        
        orchestrator.onFailedFile = { [weak self] file, destination, error in
            self?.failedFiles.append((file: file, destination: destination, error: error))
            
            // Track in statistics
            if let fileURL = URL(string: file),
               let fileType = ImageFileType.from(fileExtension: fileURL.pathExtension) {
                self?.statistics.recordFileProcessed(
                    fileType: fileType,
                    size: 0,
                    destination: destination,
                    success: false
                )
            }
        }
        
        orchestrator.onPhaseChange = { [weak self] phase in
            self?.currentPhase = phase
        }
        
        // Store reference for cancellation
        currentOrchestrator = orchestrator
        
        // Build destination item IDs array for drive info lookup
        let destinationItemIDs = destinationItems.prefix(destinations.count).map { $0.id }
        
        // Perform the backup with file type filter and duplicate preferences
        // Pass the preflight manifest to avoid rebuilding it
        print("✅ [BACKUP \(backupID)] Passing preflight manifest to orchestrator")
        let failures = await orchestrator.performBackup(
            source: source,
            destinations: destinations,
            driveInfo: destinationDriveInfo,
            destinationItemIDs: destinationItemIDs,
            filter: fileTypeFilter,
            organizationName: organizationName,
            sessionID: sessionID,
            prebuiltManifest: preflightManifest,
            duplicateAnalyses: duplicateAnalyses,
            skipExactDuplicates: skipExactDuplicates,
            skipRenamedDuplicates: skipRenamedDuplicates
        )
        
        // Add any failures to our list (avoiding duplicates)
        for failure in failures {
            if !failedFiles.contains(where: { $0.file == failure.file && $0.destination == failure.destination }) {
                failedFiles.append(failure)
            }
        }
        
        // Populate statistics based on results from progress tracker and orchestrator
        // Get actual data from what was tracked
        let totalFiles = progressTracker.totalFiles
        let processedFiles = progressTracker.processedFiles
        let failedCount = failures.count
        
        // Update overall stats from progress tracker
        // Use the actual manifest count for files processed, not the sum across destinations
        statistics.totalFilesProcessed = min(processedFiles, totalFiles)  // Cap at total files to avoid multiplication
        statistics.totalFilesFailed = failedCount
        statistics.totalFilesInSource = totalFiles
        
        // Debug logging to diagnose the issue
        print("📊 Statistics Debug:")
        print("   - progressTracker.sourceTotalBytes: \(progressTracker.sourceTotalBytes)")
        print("   - progressTracker.totalBytesCopied: \(progressTracker.totalBytesCopied)")
        print("   - progressTracker.totalBytesToCopy: \(progressTracker.totalBytesToCopy)")
        print("   - progressTracker.copySpeed: \(progressTracker.copySpeed)")
        
        // Fix: Use the actual total bytes from source, not the copied bytes which may be 0
        statistics.totalBytesProcessed = progressTracker.sourceTotalBytes > 0 ? progressTracker.sourceTotalBytes : progressTracker.totalBytesCopied
        
        print("   - statistics.totalBytesProcessed: \(statistics.totalBytesProcessed)")
        print("   - statistics.duration: \(statistics.duration ?? 0)")
        print("   - statistics.averageThroughput: \(statistics.averageThroughput)")
        
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
            let bytesPerDest = progressTracker.sourceTotalBytes > 0 ? progressTracker.sourceTotalBytes : (progressTracker.totalBytesCopied / Int64(max(1, destinationItems.count)))
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
        
        // Stop preventing sleep
        SleepPrevention.shared.stopPreventingSleep()
        
        // Show completion report if not cancelled
        if !shouldCancel {
            // Send notification if enabled
            if PreferencesManager.shared.showNotificationOnComplete {
                notificationService.sendBackupCompletionNotification(
                    filesCopied: progressTracker.processedFiles,
                    destinations: destinations.count,
                    duration: statistics.duration ?? 0
                )
            }
            
            // Small delay to ensure UI is ready
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 second
            showCompletionReport = true
        } else {
            // Clear the overall status text when cancelled
            overallStatusText = ""
            statusMessage = "Backup cancelled"
            
            // Still stop sleep prevention even if cancelled
            logInfo("Backup cancelled by user")
        }
    }
    
    /// Update our UI based on coordinator's status
    /// Already marked @MainActor to ensure thread safety
    @MainActor
    private func updateUIFromCoordinator(_ coordinator: BackupCoordinator) {
        // Debug: log update call
        print("🔄 updateUIFromCoordinator called")
        
        // Aggregate status from all destinations
        var fastestDestination: String?
        var fastestSpeed: Double = 0
        var allComplete = true
        var activeCount = 0
        
        // Update per-destination progress for UI
        var copyingCount = 0
        var verifyingDestinations: [String] = []
        
        for (name, status) in coordinator.destinationStatuses {
            // Update the destination progress for UI display
            // This is safe because we're already on @MainActor
            if status.isComplete {
                // Destination is fully complete
                progressTracker.setDestinationProgress(status.total, for: name)
                progressTracker.setDestinationState("complete", for: name)
                
                Task {
                    await progressState.setDestinationProgress(status.total, for: name)
                    await progressState.setDestinationState("complete", for: name)
                }
            } else if status.isVerifying {
                // Only show verification if the queue explicitly says it's verifying
                // Don't guess based on counts as that can be wrong during skipping
                
                // Debug log when entering verification
                let wasVerifying = destinationStates[name] == "verifying"
                if !wasVerifying {
                    print("🔵 UI UPDATE: \(name) entering verification phase (copied=\(status.completed), verified=\(status.verifiedCount), total=\(status.total), isVerifying=true)")
                } else {
                    print("🔵 UI UPDATE: \(name) still verifying (verified=\(status.verifiedCount)/\(status.total))")
                }
                
                // For verification, keep showing full progress (files are already copied)
                // This prevents the progress bar from resetting to 0 when verification starts
                progressTracker.setDestinationProgress(status.total, for: name)
                progressTracker.setDestinationState("verifying", for: name)
                verifyingDestinations.append(name)
                
                // Also update actor state for consistency
                Task {
                    await progressState.setDestinationProgress(status.total, for: name)
                    await progressState.setDestinationState("verifying", for: name)
                }
            } else {
                // Check if we're actually done (all files copied and verified)
                // Debug: Let's see what values we have
                if status.completed >= status.total && status.verifiedCount >= status.total {
                    // Destination is actually complete, just waiting for isComplete flag
                    progressTracker.setDestinationProgress(status.total, for: name)
                    progressTracker.setDestinationState("complete", for: name)
                    print("✅ UI Update: \(name) - Completed (copied=\(status.completed), verified=\(status.verifiedCount), total=\(status.total))")
                } else {
                    // Still copying (or something else)
                    progressTracker.setDestinationProgress(status.completed, for: name)
                    progressTracker.setDestinationState("copying", for: name)
                    print("🔄 UI Update: \(name) - \(status.completed)/\(status.total) files, verified=\(status.verifiedCount)")
                }
                
                Task {
                    if status.completed >= status.total && status.verifiedCount >= status.total {
                        await progressState.setDestinationProgress(status.total, for: name)
                        await progressState.setDestinationState("complete", for: name)
                    } else {
                        await progressState.setDestinationProgress(status.completed, for: name)
                        await progressState.setDestinationState("copying", for: name)
                    }
                }
            }
            
            // Parse speed (e.g., "45.2 MB/s" -> 45.2)
            if !status.isVerifying, let speedValue = parseSpeed(status.speed), speedValue > fastestSpeed {
                fastestSpeed = speedValue
                fastestDestination = name
            }
            
            // Count states more accurately
            if !status.isComplete {
                allComplete = false
                if status.isVerifying {
                    // Already added to verifyingDestinations
                } else if status.completed < status.total {
                    copyingCount += 1
                    activeCount += 1
                }
            }
        }
        
        // Update our status message
        let verifyingCount = verifyingDestinations.count
        let completeCount = coordinator.destinationStatuses.values.filter { $0.isComplete }.count
        
        if allComplete {
            statusMessage = "All destinations complete and verified!"
            currentPhase = .complete
        } else if copyingCount > 0 && verifyingCount > 0 {
            statusMessage = "\(copyingCount) copying, \(verifyingCount) verifying"
            // Set phase based on majority
            currentPhase = copyingCount > verifyingCount ? .copyingFiles : .verifyingDestinations
        } else if verifyingCount > 0 {
            let names = verifyingDestinations.joined(separator: ", ")
            statusMessage = "Verifying: \(names)"
            currentPhase = .verifyingDestinations
        } else if copyingCount > 0 {
            if let fastest = fastestDestination {
                statusMessage = "\(copyingCount) destination\(copyingCount == 1 ? "" : "s") copying - \(fastest) at \(formatSpeed(fastestSpeed))"
            } else {
                statusMessage = "\(copyingCount) destination\(copyingCount == 1 ? "" : "s") copying..."
            }
            currentPhase = .copyingFiles
        } else {
            statusMessage = "Processing..."
        }
        
        // Update progress tracker with coordinator data
        progressTracker.updateFromCoordinator(
            overallProgress: coordinator.overallProgress,
            totalBytes: coordinator.totalBytesToCopy,
            copiedBytes: coordinator.totalBytesCopied,
            speed: coordinator.currentSpeed
        )
        
        // Update ETA based on new byte counters
        updateETA()
        
        // Update processedFiles with the number of unique files processed
        // Use the maximum verified count from any destination (they should all be the same)
        // Don't sum them up or we'll count each file multiple times
        var maxVerified = 0
        for status in coordinator.destinationStatuses.values {
            maxVerified = max(maxVerified, status.verifiedCount)
        }
        progressTracker.processedFiles = maxVerified
        
        // For overall status text, show counts instead of phase
        if completeCount > 0 || copyingCount > 0 || verifyingCount > 0 {
            overallStatusText = buildOverallStatusText(
                copying: copyingCount,
                verifying: verifyingCount,
                complete: completeCount,
                total: coordinator.destinationStatuses.count
            )
        }
    }
    
    private func parseSpeed(_ speedString: String) -> Double? {
        // Parse "45.2 MB/s" -> 45.2
        let components = speedString.split(separator: " ")
        guard components.count >= 2 else { return nil }
        return Double(components[0])
    }
    
    private func formatSpeed(_ mbps: Double) -> String {
        return String(format: "%.1f MB/s", mbps)
    }
    
    private func formatTimeForQueue(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return String(format: "%.1f seconds", seconds)
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            let secs = Int(seconds.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(secs)s"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
    
    private func buildOverallStatusText(copying: Int, verifying: Int, complete: Int, total: Int) -> String {
        var parts: [String] = []
        
        if complete > 0 {
            parts.append("\(complete) complete")
        }
        if copying > 0 {
            parts.append("\(copying) copying")
        }
        if verifying > 0 {
            parts.append("\(verifying) verifying")
        }
        
        if parts.isEmpty {
            return "Processing \(total) destinations"
        }
        
        return parts.joined(separator: ", ")
    }
    
    // MARK: - Migration Support
    
    /// Check if migration is needed for organizing existing files
    @MainActor
    private func checkForMigration(source: URL, destinations: [URL], manifest: [FileManifestEntry]) async {
        print("🔍 Checking for migration opportunities...")

        // Check for cancellation
        guard !shouldCancel else {
            print("❌ Migration check cancelled")
            return
        }

        pendingMigrationPlans.removeAll()

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
                print("📦 Migration needed for \(destination.lastPathComponent): \(plan.fileCount) files")
                pendingMigrationPlans.append(plan)
            }
        }
        
        // Show migration dialog if needed
        if !pendingMigrationPlans.isEmpty {
            showMigrationDialog = true
        }
    }
    
    /// Continue backup after migration decision
    @MainActor
    func continueBackupAfterMigration() async {
        print("📦 Continuing backup after migration...")
        showMigrationDialog = false
        
        // Re-run the backup now that migration is handled
        if let source = sourceURL {
            let destinations = destinationItems.compactMap { $0.url }
            await performQueueBasedBackup(source: source, destinations: destinations)
        }
    }
    
    /// Check for duplicate files at destinations
    @MainActor
    private func checkForDuplicates(source: URL, destinations: [URL], manifest: [FileManifestEntry]) async {
        print("🔍 Checking for duplicate files...")

        // Check for cancellation
        guard !shouldCancel else {
            print("❌ Duplicate check cancelled")
            return
        }

        statusMessage = "Analyzing for duplicates..."
        
        // Perform duplicate analysis for all destinations
        let analyses = await duplicateDetector.preflightDuplicateCheck(
            manifest: manifest,
            destinations: destinations,
            organizationName: organizationName
        )
        
        // Check if any duplicates were found
        let totalDuplicates = analyses.values.reduce(0) { $0 + $1.totalDuplicates }
        
        if totalDuplicates > 0 {
            print("⚠️ Found \(totalDuplicates) duplicate files across destinations")
            duplicateAnalyses = analyses
            showDuplicateWarning = true
        } else {
            print("✅ No duplicates found")
            duplicateAnalyses = nil
            showDuplicateWarning = false
        }
    }
    
    /// Continue backup after duplicate handling decision
    @MainActor
    func continueBackupAfterDuplicateDecision(skipExact: Bool, skipRenamed: Bool) async {
        print("📦 Continuing backup with duplicate preferences...")
        showDuplicateWarning = false
        skipExactDuplicates = skipExact
        skipRenamedDuplicates = skipRenamed
        
        // Re-run the backup now that duplicate handling is decided
        if let source = sourceURL {
            let destinations = destinationItems.compactMap { $0.url }
            await performQueueBasedBackup(source: source, destinations: destinations)
        }
    }
    
    /// Cancel backup from duplicate warning
    @MainActor
    func cancelBackupFromDuplicateWarning() {
        print("❌ Backup cancelled by user from duplicate warning")
        showDuplicateWarning = false
        duplicateAnalyses = nil
        isProcessing = false
        statusMessage = "Backup cancelled"
    }

    // MARK: - Large Backup Confirmation

    /// Check if this is a large backup and wait for user confirmation if needed
    /// Returns true if backup should proceed, false if user cancelled
    @MainActor
    private func checkForLargeBackupAndWait(source: URL, destinations: [URL], manifest: [FileManifestEntry]) async -> Bool {
        print("🔍🔍🔍 LARGE BACKUP CHECK: Entry")
        print("   - Current continuation: \(largeBackupContinuation != nil ? "EXISTS" : "nil")")
        print("🔍 Starting large backup check...")
        print("   - confirmLargeBackups: \(PreferencesManager.shared.confirmLargeBackups)")
        print("   - skipLargeBackupWarning: \(PreferencesManager.shared.skipLargeBackupWarning)")

        // Skip if user disabled confirmations or already disabled warnings
        guard PreferencesManager.shared.confirmLargeBackups && !PreferencesManager.shared.skipLargeBackupWarning else {
            print("⏭️ Skipping large backup check (disabled in preferences)")
            return true  // Proceed with backup
        }

        print("🔍 Checking for large backup...")

        // Check for cancellation
        guard !shouldCancel else {
            print("❌ Large backup check cancelled")
            return false
        }

        statusMessage = "Analyzing backup size..."

        let fileThreshold = PreferencesManager.shared.largeBackupFileThreshold
        let sizeThresholdBytes = Int64(PreferencesManager.shared.largeBackupSizeThresholdGB * 1_000_000_000)

        let totalBytes = manifest.reduce(0) { $0 + $1.size }

        print("📊 Large backup analysis:")
        print("   - Manifest file count: \(manifest.count)")
        print("   - File threshold: \(fileThreshold)")
        print("   - Total bytes: \(totalBytes)")
        print("   - Size threshold (bytes): \(sizeThresholdBytes)")
        print("   - Size threshold (GB): \(PreferencesManager.shared.largeBackupSizeThresholdGB)")
        print("   - Exceeds file threshold: \(manifest.count > fileThreshold)")
        print("   - Exceeds size threshold: \(totalBytes > sizeThresholdBytes)")

        // Check if backup exceeds thresholds
        guard manifest.count > fileThreshold || totalBytes > sizeThresholdBytes else {
            print("✅ Backup is not large enough to require confirmation")
            return true  // Proceed with backup
        }

        print("⚠️ Large backup detected: \(manifest.count) files, \(totalBytes) bytes")

        // Calculate estimated time
        let estimatedSpeed = 50.0 // MB/s - conservative estimate
        let seconds = Double(totalBytes) / (estimatedSpeed * 1_000_000)
        let timeString = formatTime(seconds)

        largeBackupInfo = LargeBackupInfo(
            fileCount: manifest.count,
            totalBytes: totalBytes,
            destinationCount: destinations.count,
            estimatedTimePerDestination: timeString
        )
        showLargeBackupConfirmation = true
        print("✅ Large backup confirmation dialog shown")
        print("⏸️⏸️⏸️ CREATING CONTINUATION - about to wait for user response")

        // Wait for user response using CheckedContinuation
        let result = await withCheckedContinuation { continuation in
            print("📝 CONTINUATION CREATED - storing reference")
            largeBackupContinuation = continuation
        }

        print("▶️▶️▶️ CONTINUATION RESUMED - user responded with: \(result)")
        return result
    }

    /// User responded to large backup confirmation
    @MainActor
    func respondToLargeBackupConfirmation(shouldContinue: Bool, dontShowAgain: Bool) {
        print("👆👆👆 USER RESPONSE: shouldContinue=\(shouldContinue), dontShowAgain=\(dontShowAgain)")
        print("   - Continuation exists: \(largeBackupContinuation != nil)")
        print("   - Thread: \(Thread.current)")

        showLargeBackupConfirmation = false
        largeBackupInfo = nil

        if dontShowAgain {
            PreferencesManager.shared.skipLargeBackupWarning = true
        }

        // Resume the waiting backup process
        if let continuation = largeBackupContinuation {
            print("✅ RESUMING CONTINUATION with value: \(shouldContinue)")
            continuation.resume(returning: shouldContinue)
            largeBackupContinuation = nil
            print("✅ CONTINUATION RESUMED and cleared")
        } else {
            print("⚠️⚠️⚠️ WARNING: No continuation to resume!")
        }
    }
}