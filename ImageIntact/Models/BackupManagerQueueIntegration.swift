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
        print("🚀 Starting QUEUE-BASED backup with orchestrator")
        
        // Reset state
        isProcessing = true
        shouldCancel = false
        statusMessage = "Checking for existing backups..."
        failedFiles = []
        sessionID = UUID().uuidString
        logEntries = []
        debugLog = []
        
        // Check for migration if organization is enabled
        if !organizationName.isEmpty {
            await checkForMigration(source: source, destinations: destinations)
            
            // If migration dialog is shown, wait for user decision
            if showMigrationDialog && !pendingMigrationPlans.isEmpty {
                print("⏸️ Waiting for migration decision...")
                // The actual backup will be triggered after migration dialog closes
                isProcessing = false
                return
            }
        }
        
        // Start statistics tracking
        statistics.startBackup(sourceFiles: sourceFileTypes, filter: fileTypeFilter)
        
        // Store the session ID that will be used by Core Data
        // (BackupOrchestrator will use this same ID)
        
        defer {
            isProcessing = false
            shouldCancel = false
            currentOrchestrator = nil
            
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
        
        // Perform the backup with file type filter
        let failures = await orchestrator.performBackup(
            source: source,
            destinations: destinations,
            driveInfo: destinationDriveInfo,
            destinationItemIDs: destinationItemIDs,
            filter: fileTypeFilter,
            organizationName: organizationName,
            sessionID: sessionID
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
    private func checkForMigration(source: URL, destinations: [URL]) async {
        print("🔍 Checking for migration opportunities...")
        
        pendingMigrationPlans.removeAll()
        
        // Start security-scoped access for source
        let sourceAccessGranted = source.startAccessingSecurityScopedResource()
        defer {
            if sourceAccessGranted {
                source.stopAccessingSecurityScopedResource()
            }
        }
        
        // Build a quick manifest for checking
        let manifestBuilder = ManifestBuilder()
        guard let manifest = await manifestBuilder.build(
            source: source,
            shouldCancel: { false },
            filter: fileTypeFilter
        ) else {
            print("❌ Could not build manifest for migration check")
            return
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
}