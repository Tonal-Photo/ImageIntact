import Foundation

/// Coordinates the entire queue-based backup operation
@MainActor
class BackupCoordinator: ObservableObject {
    @Published var isRunning = false
    @Published var overallProgress: Double = 0.0
    @Published var statusMessage = ""
    @Published var destinationStatuses: [String: DestinationStatus] = [:]
    @Published var totalBytesToCopy: Int64 = 0
    @Published var totalBytesCopied: Int64 = 0
    @Published var currentSpeed: Double = 0.0  // MB/s
    
    private var destinationQueues: [DestinationQueue] = []
    private var manifest: [FileManifestEntry] = []
    private var shouldCancel = false
    private var collectedFailures: [(file: String, destination: String, error: String)] = []
    
    // Serial queue to protect dictionary access and prevent heap corruption
    private let statusUpdateQueue = DispatchQueue(label: "com.imageintact.statusUpdates", qos: .userInitiated)

    // Debug logging
    private func debugLog(_ message: String) {
        let timestamp = Date().timeIntervalSince1970
        let logMessage = "[\(String(format: "%.3f", timestamp))] \(message)"
        print(logMessage)

        // Also write to debug file
        let debugFile = FileManager.default.temporaryDirectory.appendingPathComponent("imageintact_progress_debug.txt")
        if let data = "\(logMessage)\n".data(using: .utf8) {
            if FileManager.default.fileExists(atPath: debugFile.path) {
                if let handle = try? FileHandle(forWritingTo: debugFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: debugFile)
                print("📝 Debug log file created at: \(debugFile.path)")
            }
        }
    }

    struct DestinationStatus {
        let name: String
        var completed: Int
        var total: Int
        var speed: String
        var eta: String?
        var isComplete: Bool
        var hasFailed: Bool
        var isVerifying: Bool
        var verifiedCount: Int
    }
    
    // MARK: - Main Entry Point
    
    private var backupStartTime: Date?
    private var totalBytesProcessed: Int64 = 0
    
    func startBackup(source: URL, destinations: [URL], manifest: [FileManifestEntry], organizationName: String = "") async {
        guard !isRunning else { return }

        // Clear and announce debug log file location
        let debugFile = FileManager.default.temporaryDirectory.appendingPathComponent("imageintact_progress_debug.txt")
        try? FileManager.default.removeItem(at: debugFile)
        debugLog("🚀 Starting backup - Debug log at: \(debugFile.path)")
        print("📝 To view debug log, run in Terminal: tail -f '\(debugFile.path)'")

        isRunning = true
        shouldCancel = false
        self.manifest = manifest
        destinationQueues.removeAll()
        destinationStatuses.removeAll()
        
        // Track backup start
        backupStartTime = Date()
        totalBytesProcessed = manifest.reduce(0) { $0 + $1.size }
        AnalyticsManager.shared.trackEvent(.backupStarted, properties: [
            "file_count": "\(manifest.count)",
            "destination_count": "\(destinations.count)",
            "total_mb": "\(totalBytesProcessed / 1024 / 1024)"
        ])
        
        print("🎯 Starting queue-based backup with \(destinations.count) destinations")
        statusMessage = "Initializing smart backup system..."
        
        // Create tasks with smart priority
        let tasks = createFileTasks(from: manifest)
        
        // Each destination should get ALL tasks (not round-robin distribution!)
        var tasksByDestination: [Int: [FileTask]] = [:]
        for i in 0..<destinations.count {
            // Give each destination a copy of ALL tasks
            tasksByDestination[i] = tasks
        }
        
        // Debug: Print task distribution
        for (idx, destTasks) in tasksByDestination {
            print("📊 Destination \(idx) (\(destinations[idx].lastPathComponent)) will receive \(destTasks.count) tasks")
            if destTasks.count > 0 {
                let firstFew = destTasks.prefix(3).map { $0.relativePath }
                print("   First few tasks: \(firstFew)")
            }
        }
        
        // Create a queue for each destination with organization name
        // Use CancellableFileOperations for better cancellation support
        let cancellableOps = CancellableFileOperations()
        for (index, destination) in destinations.enumerated() {
            let queue = DestinationQueue(destination: destination, organizationName: organizationName, fileOperations: cancellableOps)
            let destName = destination.lastPathComponent  // Capture once
            
            print("🔍 Creating queue for destination \(index): \(destName)")
            
            // Set up callbacks before adding to array to avoid retain issues
            // Use destName consistently to avoid capturing destination in closures

            // Get task count before closures to avoid capturing tasksByDestination
            let destinationTaskCount = tasksByDestination[index]?.count ?? 0

            // Verification callback - use serial queue for dictionary access
            await queue.setVerificationCallback { @Sendable [weak self] isVerifying, verifiedCount async in
                guard let self = self else { return }
                // Use pre-computed task count
                await self.updateStatusSafely(destName: destName, isVerifying: isVerifying, verifiedCount: verifiedCount, totalFiles: destinationTaskCount)
            }

            // Progress callback - use serial queue for dictionary access
            await queue.setProgressCallback { @Sendable [weak self] completed, total async in
                guard let self = self else { return }
                await self.debugLog("📊 Progress callback from \(destName): \(completed)/\(total)")
                // Use serial queue to prevent concurrent dictionary access
                await self.updateProgressSafely(destName: destName, completed: completed, total: total)
            }
            
            // Now add queue to array
            destinationQueues.append(queue)
            
            // Get tasks for this destination
            let destinationTasks = tasksByDestination[index] ?? []
            
            print("🔍 About to add \(destinationTasks.count) tasks to \(destName)")
            if destinationTasks.count > 0 {
                let sample = destinationTasks.prefix(3).map { $0.relativePath }
                print("   Sample tasks for \(destName): \(sample)")
            }
            
            // Initialize status - no need for serial queue here as we're still in setup phase
            // and not yet running concurrent operations
            destinationStatuses[destName] = DestinationStatus(
                name: destName,
                completed: 0,
                total: destinationTasks.count,
                speed: "0 MB/s",
                eta: nil,
                isComplete: false,
                hasFailed: false,
                isVerifying: false,
                verifiedCount: 0
            )
            
            // Add tasks to queue
            await queue.addTasks(destinationTasks)
            print("🔍 Tasks added to \(destName)")
        }
        
        // Start all queues
        statusMessage = "Starting parallel backup to \(destinations.count) destinations..."
        
        await withTaskGroup(of: Void.self) { group in
            for queue in destinationQueues {
                group.addTask { [weak self, weak queue] in
                    guard let queue = queue else { return }
                    await queue.start()
                    
                    // Wait for completion
                    while await !queue.isComplete() {
                        // Check cancellation from main actor
                        let cancelled = await MainActor.run { [weak self] in
                            self?.shouldCancel ?? true
                        }
                        if cancelled { 
                            await queue.stop()
                            break 
                        }
                        try? await Task.sleep(nanoseconds: 100_000_000) // Check every 0.1s
                    }
                }
            }
            
            // Start monitoring task with weak self
            group.addTask { [weak self] in
                await self?.monitorProgress()
            }
            
            // Wait for all to complete
            await group.waitForAll()
        }
        
        // Final status
        await finalizeBackup()
        
        // Clean up all queues to prevent retain cycles
        await withTaskGroup(of: Void.self) { group in
            for queue in destinationQueues {
                group.addTask {
                    await queue.stop()
                }
            }
        }
        destinationQueues.removeAll()
        
        // Clear manifest to free memory
        self.manifest.removeAll(keepingCapacity: false)
        
        // Clear all tracking data
        self.destinationStatuses.removeAll(keepingCapacity: false)
        self.collectedFailures.removeAll(keepingCapacity: false)
        
        print("🎯 BackupCoordinator: Setting isRunning to false")
        isRunning = false
        print("🎯 BackupCoordinator: startBackup() complete")
    }
    
    func cancelBackup() {
        guard !shouldCancel else { return }  // Prevent multiple cancellations
        shouldCancel = true
        statusMessage = "Backup cancelled"
        
        // Track cancellation
        AnalyticsManager.shared.trackEvent(.backupCancelled)
        
        // Immediately clear all statuses to stop UI updates
        for (name, _) in destinationStatuses {
            destinationStatuses[name] = DestinationStatus(
                name: name,
                completed: 0,
                total: 0,
                speed: "Cancelled",
                eta: nil,
                isComplete: true,  // Mark as complete to stop monitoring
                hasFailed: false,
                isVerifying: false,
                verifiedCount: 0
            )
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            
            // Log cancellation
            print("🛑 CANCELLING: Stopping all destination queues immediately")
            
            // Stop all queues in parallel for faster cancellation
            await withTaskGroup(of: Void.self) { group in
                for queue in self.destinationQueues {
                    group.addTask {
                        await queue.stop()
                    }
                }
            }
            
            print("🛑 All queues stopped")
            
            // Clear queues to release memory
            self.destinationQueues.removeAll()
            // Clear manifest to free memory
            self.manifest.removeAll(keepingCapacity: false)
            // Clear all tracking data
            self.destinationStatuses.removeAll(keepingCapacity: false)
            self.collectedFailures.removeAll(keepingCapacity: false)
            // Only set isRunning to false after cleanup
            self.isRunning = false
        }
    }
    
    func getFailures() -> [(file: String, destination: String, error: String)] {
        return collectedFailures
    }
    
    // MARK: - Task Creation
    
    private func createFileTasks(from manifest: [FileManifestEntry]) -> [FileTask] {
        var tasks: [FileTask] = []
        
        for entry in manifest {
            let priority = determineTaskPriority(entry)
            let task = FileTask(from: entry, priority: priority)
            tasks.append(task)
        }
        
        print("📋 Created \(tasks.count) tasks:")
        print("   - High priority: \(tasks.filter { $0.priority == .high }.count)")
        print("   - Normal priority: \(tasks.filter { $0.priority == .normal }.count)")
        print("   - Low priority: \(tasks.filter { $0.priority == .low }.count)")
        
        return tasks
    }
    
    private func determineTaskPriority(_ entry: FileManifestEntry) -> TaskPriority {
        // Prioritize based on file size and type
        let sizeInMB = entry.size / (1024 * 1024)
        
        // Very small files (< 100KB) - highest priority for quick wins
        if entry.size < 100_000 {
            return .high
        }
        // Small files (< 10MB) - high priority
        else if sizeInMB < 10 {
            return .high
        }
        // Medium files (10MB - 100MB) - normal priority
        else if sizeInMB < 100 {
            return .normal
        }
        // Large files (100MB - 1GB) - lower priority
        else if sizeInMB < 1000 {
            return .low
        }
        // Huge files (> 1GB) - lowest priority
        else {
            return .low
        }
    }
    
    // MARK: - Thread-Safe Status Updates
    
    private func updateStatusSafely(destName: String, isVerifying: Bool, verifiedCount: Int, totalFiles: Int) async {
        await withCheckedContinuation { continuation in
            statusUpdateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    if var status = self.destinationStatuses[destName] {
                        status.isVerifying = isVerifying
                        status.verifiedCount = verifiedCount
                        self.destinationStatuses[destName] = status
                        self.updateOverallProgress(totalFiles: totalFiles)
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func updateProgressSafely(destName: String, completed: Int, total: Int) async {
        await withCheckedContinuation { continuation in
            statusUpdateQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    if var status = self.destinationStatuses[destName] {
                        let oldCompleted = status.completed
                        status.completed = completed
                        self.destinationStatuses[destName] = status
                        self.debugLog("📊 Progress update: \(destName) - \(completed)/\(total) (was \(oldCompleted))")
                        self.updateOverallProgress(totalFiles: total)
                    } else {
                        self.debugLog("⚠️ No status found for destination: \(destName)")
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Progress Monitoring
    
    private func parseSpeed(_ speedString: String) -> Double? {
        // Parse strings like "45.2 MB/s" to return 45.2
        let components = speedString.components(separatedBy: " ")
        guard components.count >= 2,
              let value = Double(components[0]) else {
            return nil
        }
        return value
    }
    
    private func monitorProgress() async {
        // Keep monitoring until all queues are truly complete (including verification)
        var allQueuesActuallyComplete = false
        while !allQueuesActuallyComplete && !shouldCancel {
            // Update status for each destination
            var allQueuesComplete = true
            var totalTransferred: Int64 = 0
            var totalBytesAllDestinations: Int64 = 0
            var combinedSpeed: Double = 0.0
            
            for queue in destinationQueues {
                let status = await queue.getStatus()
                let destination = queue.destination
                let verifiedFiles = await queue.getVerifiedCount()
                let isVerifying = await queue.getIsVerifying()
                let queueComplete = await queue.isComplete()
                let bytesInfo = await queue.getBytesInfo()
                
                if !queueComplete {
                    allQueuesComplete = false
                }
                
                // Accumulate bytes for all destinations
                totalTransferred += bytesInfo.transferred
                totalBytesAllDestinations += bytesInfo.total
                
                // Parse speed and accumulate
                if let speedValue = parseSpeed(status.speed) {
                    combinedSpeed += speedValue
                }
                
                // Debug log to check if verifiedFiles is being read correctly
                if verifiedFiles > 0 || isVerifying {
                    print("📊 Coordinator: \(destination.lastPathComponent) - completed=\(status.completed)/\(status.total), verified=\(verifiedFiles), isVerifying=\(isVerifying), isComplete=\(queueComplete)")
                }
                
                // Use serial queue for safe dictionary update
                let destName = destination.lastPathComponent
                await withCheckedContinuation { continuation in
                    statusUpdateQueue.async { [weak self] in
                        guard let self = self else {
                            continuation.resume()
                            return
                        }
                        Task { @MainActor in
                            self.destinationStatuses[destName] = DestinationStatus(
                                name: destName,
                                completed: status.completed,
                                total: status.total,
                                speed: status.speed,
                                eta: status.eta,
                                isComplete: queueComplete,
                                hasFailed: false,
                                isVerifying: isVerifying,
                                verifiedCount: verifiedFiles
                            )
                            continuation.resume()
                        }
                    }
                }
            }
            
            // Update the byte tracking for ETA calculations
            await MainActor.run {
                self.totalBytesToCopy = totalBytesAllDestinations
                self.totalBytesCopied = totalTransferred
                self.currentSpeed = combinedSpeed
                
                // Debug logging for ETA
                print("📊 ETA Debug - totalBytes: \(totalBytesAllDestinations), transferred: \(totalTransferred), speed: \(combinedSpeed) MB/s")
            }
            
            // Calculate overall progress (include both copying and verification)
            // Calculate overall progress as average of all destinations
            // This ensures we don't show 100% until ALL destinations are complete
            var totalProgress = 0.0
            var destinationCount = 0
            
            for status in destinationStatuses.values {
                // Each destination has 'total' files to copy and 'total' files to verify
                let destinationTotal = status.total * 2  // *2 for copy + verify phases
                let destinationCompleted = status.completed + status.verifiedCount
                
                if destinationTotal > 0 {
                    let destinationProgress = Double(destinationCompleted) / Double(destinationTotal)
                    totalProgress += destinationProgress
                    destinationCount += 1
                }
            }
            
            let calculatedProgress = destinationCount > 0 ? totalProgress / Double(destinationCount) : 0.0
            // Sanitize to 0-1 range to prevent UI issues
            overallProgress = max(0.0, min(1.0, calculatedProgress))
            
            // Update status message
            let activeCount = destinationStatuses.values.filter { !$0.isComplete }.count
            if activeCount > 0 {
                statusMessage = "\(activeCount) destination\(activeCount == 1 ? "" : "s") still copying..."
            } else if destinationStatuses.values.allSatisfy({ $0.isComplete }) {
                statusMessage = "All destinations complete!"
            }
            
            // Update the flag to check if we should exit
            allQueuesActuallyComplete = allQueuesComplete
            
            // Exit early if all queues are complete
            if allQueuesComplete {
                print("📊 BackupCoordinator: All queues complete (including verification), exiting monitorProgress")
            }
            
            try? await Task.sleep(nanoseconds: 250_000_000) // Update every 0.25s for smoother progress
        }
        print("📊 BackupCoordinator: monitorProgress() finished")
    }
    
    @MainActor
    private func updateOverallProgress(totalFiles: Int) {
        // Calculate overall progress as average of all destinations
        // This ensures we don't show 100% until ALL destinations are complete
        var totalProgress = 0.0
        var destinationCount = 0
        var debugInfo = ""
        
        for (name, status) in destinationStatuses {
            // Each destination has 'total' files to copy and 'total' files to verify
            let destinationTotal = status.total * 2  // *2 for copy + verify phases
            let destinationCompleted = status.completed + status.verifiedCount
            
            if destinationTotal > 0 {
                let destinationProgress = Double(destinationCompleted) / Double(destinationTotal)
                totalProgress += destinationProgress
                destinationCount += 1
                debugInfo += "\(name): \(destinationCompleted)/\(destinationTotal), "
            }
        }
        
        let avgProgress = destinationCount > 0 ? totalProgress / Double(destinationCount) : 0.0
        overallProgress = max(0.0, min(1.0, avgProgress))
        
        print("📊 Overall progress update: \(String(format: "%.1f%%", overallProgress * 100)) [\(debugInfo)]")
    }
    
    
    // MARK: - Finalization
    
    private func finalizeBackup() async {
        // Collect results from all queues
        var totalCompleted = 0
        var totalFailed = 0
        var allFailures: [(destination: String, failures: [(file: String, error: String)])] = []
        
        for queue in destinationQueues {
            let destination = queue.destination
            let completed = await queue.completedFiles
            let failures = await queue.failedFiles
            
            totalCompleted += completed
            totalFailed += failures.count
            
            if !failures.isEmpty {
                allFailures.append((destination: destination.lastPathComponent, failures: failures))
                // Store failures for external access
                for failure in failures {
                    collectedFailures.append((
                        file: failure.file,
                        destination: destination.lastPathComponent,
                        error: failure.error
                    ))
                }
            }
        }
        
        // Track backup completion
        let duration = backupStartTime.map { Date().timeIntervalSince($0) } ?? 0
        let success = totalFailed == 0
        AnalyticsManager.shared.trackBackup(
            fileCount: totalCompleted,
            totalBytes: totalBytesProcessed,
            destinationCount: destinationQueues.count,
            duration: duration,
            success: success
        )
        
        // Generate final status message
        if totalFailed == 0 {
            statusMessage = "✅ Backup complete! \(totalCompleted) files copied to \(destinationQueues.count) destinations"
        } else {
            statusMessage = "⚠️ Backup complete with \(totalFailed) errors"
            
            // Log failures
            for (destination, failures) in allFailures {
                print("Failures for \(destination):")
                for failure in failures {
                    print("  - \(failure.file): \(failure.error)")
                }
            }
        }
    }
    
    // MARK: - Work Stealing (Future Enhancement)
    
    func enableWorkStealing() {
        // Future enhancement: Implement work stealing between queues
        // This would allow fast destinations to help slow ones complete
        // their work, improving overall backup completion time
        logInfo("Work stealing not yet implemented - planned for future release")
    }
}