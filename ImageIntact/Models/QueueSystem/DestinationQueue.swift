import Darwin
import Foundation

/// Manages the backup queue for a single destination
actor DestinationQueue {
    let destination: URL
    let organizationName: String // Folder name for organizing backups
    let queue: PriorityQueue
    let throughputMonitor: ThroughputMonitor
    private let batchProcessor = BatchFileProcessor()
    private let fileOperations: FileOperationsProtocol

    private var activeWorkers: Set<UUID> = []
    private var workerTasks: [Task<Void, Never>] = []
    private var isRunning = false
    private var shouldCancel = false

    // Progress tracking
    private(set) var totalFiles: Int = 0
    private(set) var completedFiles: Int = 0
    private var successfullyCopiedFiles: Set<String> = []
    private(set) var failedFiles: [(file: String, error: String)] = []
    private(set) var bytesTransferred: Int64 = 0
    private(set) var totalBytes: Int64 = 0
    private(set) var verifiedFiles: Int = 0
    private(set) var isVerifying = false

    // Store the tasks assigned to this destination for verification
    private var assignedTasks: [FileTask] = []

    // Callbacks for UI updates (needs to be set from async context)
    private var onProgress: ((Int, Int) async -> Void)?
    private var onStatusUpdate: ((String) async -> Void)?
    private var onVerificationStateChange: ((Bool, Int) async -> Void)?

    // Throttling for progress updates
    private var lastProgressUpdate = Date()
    private let progressUpdateInterval: TimeInterval = 0.1 // Update at most 10 times per second

    func setProgressCallback(_ callback: @escaping (Int, Int) async -> Void) {
        onProgress = callback
    }

    func setStatusCallback(_ callback: @escaping (String) async -> Void) {
        onStatusUpdate = callback
    }

    func setVerificationCallback(_ callback: @escaping (Bool, Int) async -> Void) {
        onVerificationStateChange = callback
    }

    // Worker configuration with resource limits
    private var currentWorkerCount: Int = 2
    private let minWorkers = 1
    private let maxWorkers = 4 // Reduced from 8 to prevent resource exhaustion
    private let maxMemoryUsageMB = 750 // Increased from 500MB - more appropriate for modern systems

    init(
        destination: URL, organizationName: String = "",
        fileOperations: FileOperationsProtocol = DefaultFileOperations.shared
    ) {
        self.destination = destination
        self.organizationName = organizationName
        queue = PriorityQueue()
        throughputMonitor = ThroughputMonitor()
        self.fileOperations = fileOperations
    }

    // MARK: - Queue Management

    func addTasks(_ tasks: [FileTask]) async {
        await queue.enqueueMultiple(tasks)
        totalFiles += tasks.count
        totalBytes += tasks.reduce(0) { $0 + $1.size }
        // Store the tasks assigned to this destination
        assignedTasks = tasks
        ApplicationLogger.shared.debug("\(destination.lastPathComponent) assigned \(tasks.count) tasks", category: .backup)
        if tasks.count > 0 {
            let firstFew = tasks.prefix(3).map { $0.relativePath }
            ApplicationLogger.shared.debug("First few: \(firstFew)", category: .backup)
        }
    }

    func start() async {
        guard !isRunning else { return }

        isRunning = true
        shouldCancel = false
        await throughputMonitor.start()

        ApplicationLogger.shared.debug("Starting queue for \(destination.lastPathComponent) with \(await queue.count) files", category: .backup)

        // Start initial workers
        for _ in 0 ..< currentWorkerCount {
            let task = Task {
                await runWorker()
            }
            workerTasks.append(task)
        }

        // Start adaptive worker manager
        let managerTask = Task {
            await manageWorkerCount()
        }
        workerTasks.append(managerTask)

        // Start verification monitor - it will use assignedTasks member variable
        let verifyTask = Task {
            await startVerificationWhenCopyingComplete()
        }
        workerTasks.append(verifyTask)
    }

    func stop() {
        shouldCancel = true
        isRunning = false

        ApplicationLogger.shared.debug("DestinationQueue.stop() called for \(destination.lastPathComponent)", category: .backup)

        // Cancel all worker tasks immediately
        for task in workerTasks {
            task.cancel()
        }
        workerTasks.removeAll()

        // Clear the queue to prevent further processing
        Task {
            await queue.clear()
        }

        // Clear callbacks to prevent retain cycles
        onProgress = nil
        onStatusUpdate = nil
        onVerificationStateChange = nil

        ApplicationLogger.shared.debug("DestinationQueue stopped for \(destination.lastPathComponent)", category: .backup)
    }

    // MARK: - Worker Management

    private func runWorker() async {
        let workerId = UUID()
        activeWorkers.insert(workerId)
        defer {
            activeWorkers.remove(workerId)
            // Clean up any resources used by this worker
            ApplicationLogger.shared.debug("Worker \(workerId.uuidString.prefix(8)) cleaned up", category: .backup)
        }

        ApplicationLogger.shared.debug("Worker \(workerId.uuidString.prefix(8)) started for \(destination.lastPathComponent)", category: .backup)

        while !shouldCancel, isRunning {
            // Check for cancellation before dequeue
            if shouldCancel {
                ApplicationLogger.shared.debug("Worker \(workerId.uuidString.prefix(8)) cancelled before dequeue", category: .backup)
                break
            }

            // Get next task from queue
            guard let task = await queue.dequeue() else {
                // No more tasks, worker can exit
                break
            }

            // Check for cancellation after dequeue
            if shouldCancel {
                ApplicationLogger.shared.debug("Worker \(workerId.uuidString.prefix(8)) cancelled after dequeue", category: .backup)
                // Don't re-queue when cancelled, just exit
                break
            }

            // Process the task
            let result = await processFileTask(task)

            // Handle result
            switch result {
            case .success:
                completedFiles += 1
                successfullyCopiedFiles.insert(task.relativePath)
                bytesTransferred += task.size
                await throughputMonitor.recordTransfer(bytes: task.size)

                // Report progress update
                if let progressCallback = onProgress {
                    await progressCallback(completedFiles, totalFiles)
                }

            case let .skipped(reason):
                completedFiles += 1
                // Add to successfully copied files if it was skipped because it already exists
                if reason.contains("Already exists") {
                    successfullyCopiedFiles.insert(task.relativePath)
                }

                // Report progress update
                if let progressCallback = onProgress {
                    await progressCallback(completedFiles, totalFiles)
                }

            case let .failed(error):
                ApplicationLogger.shared.debug("Failed \(task.relativePath): \(error)", category: .backup)
                failedFiles.append((file: task.relativePath, error: error.localizedDescription))

                // Retry logic
                if task.attemptCount < 3 {
                    var retryTask = task
                    retryTask.attemptCount += 1
                    retryTask.lastError = error
                    await queue.enqueue(retryTask)
                } else {
                    completedFiles += 1 // Count as completed even if failed

                    // Report progress update
                    if let progressCallback = onProgress {
                        await progressCallback(completedFiles, totalFiles)
                    }
                }

            case .cancelled:
                // Don't re-queue cancelled tasks, just exit the worker
                ApplicationLogger.shared.debug("Task cancelled for \(task.relativePath)", category: .backup)
            }

            // Update progress with throttling to prevent overwhelming the UI
            let currentCompleted = completedFiles
            let currentTotal = totalFiles
            let now = Date()

            // Only update if enough time has passed or if we're done
            if now.timeIntervalSince(lastProgressUpdate) >= progressUpdateInterval
                || currentCompleted >= currentTotal
            {
                lastProgressUpdate = now
                if let progressCallback = onProgress {
                    // Call callback asynchronously to respect actor boundaries
                    await progressCallback(currentCompleted, currentTotal)
                }
            }
        }

        ApplicationLogger.shared.debug("Worker \(workerId.uuidString.prefix(8)) finished for \(destination.lastPathComponent)", category: .backup)
    }

    private func manageWorkerCount() async {
        while !shouldCancel, isRunning {
            // Wait a bit before adjusting
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds

            // Check memory usage before adjusting workers
            let memoryUsage = getMemoryUsage()
            if memoryUsage > maxMemoryUsageMB {
                ApplicationLogger.shared.debug("High memory usage (\(memoryUsage)MB), limiting workers for \(destination.lastPathComponent)", category: .backup)
                // Don't add more workers if memory is high
                continue
            }

            let recommendedWorkers = await throughputMonitor.recommendedWorkerCount

            if recommendedWorkers > currentWorkerCount {
                // Add workers
                let toAdd = min(recommendedWorkers - currentWorkerCount, maxWorkers - currentWorkerCount)
                for _ in 0 ..< toAdd {
                    let task = Task {
                        await runWorker()
                    }
                    workerTasks.append(task)
                }
                currentWorkerCount += toAdd
                ApplicationLogger.shared.debug("Added \(toAdd) workers for \(destination.lastPathComponent) (now \(currentWorkerCount))", category: .backup)

            } else if recommendedWorkers < currentWorkerCount, currentWorkerCount > minWorkers {
                // Reduce workers (they'll naturally exit when they finish current task)
                currentWorkerCount = max(minWorkers, recommendedWorkers)
                ApplicationLogger.shared.debug("Reducing to \(currentWorkerCount) workers for \(destination.lastPathComponent)", category: .backup)
            }
        }
    }

    // MARK: - File Processing

    private func processFileTask(_ task: FileTask) async -> CopyResult {
        guard !shouldCancel else { return .cancelled }

        let destPath = buildDestinationPath(for: task)
        let destDir = destPath.deletingLastPathComponent()
        let startTime = Date()

        do {
            guard !shouldCancel else { return .cancelled }

            // Create directory if needed
            if !fileOperations.fileExists(at: destDir) {
                try fileOperations.createDirectory(at: destDir, withIntermediateDirectories: true)
            }

            // Check if file can be skipped (already exists with matching checksum)
            if try await checkExistingFileCanBeSkipped(task, at: destPath) {
                return .skipped(reason: "Already exists with matching checksum")
            }

            guard !shouldCancel else { return .cancelled }

            // Copy the file
            return try await performFileCopy(task, to: destPath, startTime: startTime)
        } catch {
            if shouldCancel { return .cancelled }
            return .failed(error: error)
        }
    }

    /// Perform the actual file copy with security-scoped access
    private func performFileCopy(_ task: FileTask, to destPath: URL, startTime: Date) async throws
        -> CopyResult
    {
        let sourceAccess = fileOperations.startAccessingSecurityScopedResource(for: task.sourceURL)
        let destAccess = fileOperations.startAccessingSecurityScopedResource(for: destination)
        defer {
            if sourceAccess {
                fileOperations.stopAccessingSecurityScopedResource(for: task.sourceURL)
            }
            if destAccess {
                fileOperations.stopAccessingSecurityScopedResource(for: destination)
            }
        }

        do {
            try await RetryHandler.shared.copyFileWithRetry(
                from: task.sourceURL,
                to: destPath,
                fileOperations: fileOperations
            )

            let duration = Date().timeIntervalSince(startTime)
            await logCopySuccess(task, to: destPath, duration: duration)
            ApplicationLogger.shared.debug("Copied \(task.relativePath) to \(destination.lastPathComponent)", category: .backup)
            return .success
        } catch {
            await logCopyError(task, to: destPath, error: error)

            // Clean up partial file if copy failed
            if fileOperations.fileExists(at: destPath) {
                try? fileOperations.removeItem(at: destPath)
            }
            throw error
        }
    }

    // MARK: - File Processing Helpers

    /// Build the destination path, optionally including organization folder
    private func buildDestinationPath(for task: FileTask) -> URL {
        if !organizationName.isEmpty {
            return destination
                .appendingPathComponent(organizationName)
                .appendingPathComponent(task.relativePath)
        }
        return destination.appendingPathComponent(task.relativePath)
    }

    /// Check if file already exists with matching checksum and can be skipped
    private func checkExistingFileCanBeSkipped(_ task: FileTask, at destPath: URL) async throws
        -> Bool
    {
        guard fileOperations.fileExists(at: destPath) else { return false }

        // Quick size check first
        guard let destSize = fileOperations.fileSize(at: destPath),
              destSize == task.size
        else {
            // Size doesn't match, file needs to be replaced
            try fileOperations.removeItem(at: destPath)
            return false
        }

        // Size matches, verify checksum
        let checksumMatches = try await RetryHandler.shared.executeWithRetry(
            operation: "Verify checksum for \(task.relativePath)"
        ) {
            let existingChecksum = try await fileOperations.calculateChecksum(
                for: destPath,
                shouldCancel: { shouldCancel }
            )
            return existingChecksum == task.checksum
        }

        if checksumMatches {
            await logSkippedFile(task, at: destPath)
            return true
        }

        // Checksum doesn't match, file needs to be replaced
        try fileOperations.removeItem(at: destPath)
        return false
    }

    /// Log a skipped file event
    private func logSkippedFile(_ task: FileTask, at destPath: URL) async {
        await MainActor.run {
            EventLogger.shared.logEvent(
                type: .skip,
                severity: .debug,
                file: task.sourceURL,
                destination: destPath,
                fileSize: task.size,
                checksum: task.checksum,
                metadata: ["reason": "Already exists with matching checksum"]
            )
            ApplicationLogger.shared.debug(
                "Skipped (already exists): \(task.sourceURL.path)",
                category: .backup
            )
        }
    }

    /// Log a successful copy event
    private func logCopySuccess(_ task: FileTask, to destPath: URL, duration: TimeInterval) async {
        await MainActor.run {
            EventLogger.shared.logEvent(
                type: .copy,
                severity: .info,
                file: task.sourceURL,
                destination: destPath,
                fileSize: task.size,
                checksum: task.checksum,
                duration: duration
            )
            ApplicationLogger.shared.debug(
                "Copied file: \(task.sourceURL.path) -> \(destPath.path)",
                category: .backup
            )
        }
    }

    /// Log a copy error event
    private func logCopyError(_ task: FileTask, to destPath: URL, error: Error) async {
        await MainActor.run {
            EventLogger.shared.logEvent(
                type: .error,
                severity: .error,
                file: task.sourceURL,
                destination: destPath,
                fileSize: task.size,
                error: error,
                metadata: ["operation": "copy"]
            )
            ApplicationLogger.shared.error(
                "Failed to copy \(task.sourceURL.path): \(error.localizedDescription)",
                category: .backup
            )
        }
    }

    // MARK: - Status and Monitoring

    func getStatus() async -> (completed: Int, total: Int, speed: String, eta: String?) {
        let speed = await throughputMonitor.getFormattedSpeed()

        let remainingBytes = totalBytes - bytesTransferred
        let eta: String?
        if let timeRemaining = await throughputMonitor.estimateTimeRemaining(
            bytesRemaining: remainingBytes)
        {
            eta = formatTime(timeRemaining)
        } else {
            eta = nil
        }

        return (completedFiles, totalFiles, speed, eta)
    }

    func getVerifiedCount() -> Int {
        return verifiedFiles
    }

    func getIsVerifying() -> Bool {
        return isVerifying
    }

    func getBytesInfo() -> (transferred: Int64, total: Int64) {
        return (bytesTransferred, totalBytes)
    }

    func isComplete() -> Bool {
        // Consider complete if:
        // 1. All files are verified successfully, OR
        // 2. Verification is done (not running) and we've attempted to verify all files
        // This accounts for files that failed verification
        let allFilesProcessed = (verifiedFiles + failedFiles.count) >= totalFiles
        let complete = allFilesProcessed && !isVerifying

        if complete || verifiedFiles > 0 {
            ApplicationLogger.shared.debug("Queue.isComplete(\(destination.lastPathComponent)): verified=\(verifiedFiles)/\(totalFiles), failed=\(failedFiles.count), isVerifying=\(isVerifying) -> \(complete)", category: .backup)
        }
        return complete
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        TimeFormatter.formatETA(seconds)
    }

    // MARK: - Resource Monitoring

    private func getMemoryUsage() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count
                )
            }
        }

        if result == KERN_SUCCESS {
            return Int(info.resident_size / 1024 / 1024) // Convert to MB
        }
        return 0
    }

    // MARK: - Verification

    private func startVerificationWhenCopyingComplete() async {
        // Wait for all copying to complete
        while completedFiles < totalFiles, !shouldCancel {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // Check every second
        }

        guard !shouldCancel else { return }

        ApplicationLogger.shared.debug("Copying complete for \(destination.lastPathComponent), starting verification...", category: .backup)
        ApplicationLogger.shared.debug("Debug: assignedTasks.count = \(assignedTasks.count), successfullyCopiedFiles.count = \(successfullyCopiedFiles.count)", category: .backup)

        // Debug: Check what files are in assignedTasks
        let sampleFiles = assignedTasks.prefix(5).map { $0.relativePath }
        ApplicationLogger.shared.debug("Sample of assignedTasks for \(destination.lastPathComponent): \(sampleFiles)", category: .backup)

        // Debug: Check what files were successfully copied
        let copiedSample = Array(successfullyCopiedFiles.prefix(5))
        ApplicationLogger.shared.debug("Sample of successfullyCopiedFiles for \(destination.lastPathComponent): \(copiedSample)", category: .backup)

        // Small delay before setting isVerifying to ensure UI sees copying complete first
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds

        // NOW set isVerifying to true, right before we actually start verifying
        isVerifying = true

        // Notify coordinator that verification has started
        if let callback = onVerificationStateChange {
            await callback(true, 0)
        }

        // Verify only files that were successfully copied to THIS destination
        for task in assignedTasks {
            guard !shouldCancel else { break }

            // Skip files that weren't copied to this destination
            guard successfullyCopiedFiles.contains(task.relativePath) else {
                // This file was not assigned to this destination, skip it
                continue
            }

            // If we have an organization name, include it in the path
            let destPath: URL
            if !organizationName.isEmpty {
                destPath =
                    destination
                        .appendingPathComponent(organizationName)
                        .appendingPathComponent(task.relativePath)
            } else {
                destPath = destination.appendingPathComponent(task.relativePath)
            }

            do {
                // Check if file exists
                guard fileOperations.fileExists(at: destPath) else {
                    ApplicationLogger.shared.debug("Verification failed: \(task.relativePath) missing at \(destination.lastPathComponent)", category: .backup)
                    failedFiles.append((file: task.relativePath, error: "File missing after copy"))
                    continue
                }

                // Verify checksum
                let verifyStartTime = Date()
                let actualChecksum = try await fileOperations.calculateChecksum(
                    for: destPath,
                    shouldCancel: { shouldCancel }
                )

                if actualChecksum == task.checksum {
                    verifiedFiles += 1
                    ApplicationLogger.shared.debug("Verified: \(task.relativePath) at \(destination.lastPathComponent) (total verified: \(verifiedFiles))", category: .backup)

                    // Log successful verification
                    let duration = Date().timeIntervalSince(verifyStartTime)
                    await MainActor.run {
                        EventLogger.shared.logEvent(
                            type: .verify,
                            severity: .info,
                            file: task.sourceURL,
                            destination: destPath,
                            fileSize: task.size,
                            checksum: task.checksum,
                            duration: duration
                        )

                        // Also log to ApplicationLogger
                        ApplicationLogger.shared.debug(
                            "Verified: \(destPath.path)",
                            category: .backup
                        )
                    }

                    // Notify coordinator of verification progress
                    if let callback = onVerificationStateChange {
                        let currentVerified = verifiedFiles
                        await callback(true, currentVerified)
                    }
                } else {
                    ApplicationLogger.shared.debug("Checksum mismatch: \(task.relativePath) at \(destination.lastPathComponent)", category: .backup)
                    failedFiles.append((file: task.relativePath, error: "Checksum mismatch"))

                    // Log verification failure
                    await MainActor.run {
                        EventLogger.shared.logEvent(
                            type: .error,
                            severity: .error,
                            file: task.sourceURL,
                            destination: destPath,
                            fileSize: task.size,
                            metadata: [
                                "operation": "verify",
                                "expectedChecksum": task.checksum,
                                "actualChecksum": actualChecksum,
                            ]
                        )

                        // Also log to ApplicationLogger
                        ApplicationLogger.shared.error(
                            "Verification failed for \(destPath.path): checksum mismatch",
                            category: .backup
                        )
                    }
                }
            } catch {
                ApplicationLogger.shared.debug("Verification error for \(task.relativePath): \(error)", category: .backup)
                failedFiles.append((file: task.relativePath, error: error.localizedDescription))
            }

            // Don't update progress during verification - it confuses the UI
            // The progress callback is for copying progress only
            // Verification happens after copying is complete (at 100%)
        }

        isVerifying = false

        // Notify coordinator that verification has completed
        if let callback = onVerificationStateChange {
            let finalVerified = verifiedFiles
            await callback(false, finalVerified)
        }
        ApplicationLogger.shared.debug("Verification complete for \(destination.lastPathComponent): \(verifiedFiles)/\(successfullyCopiedFiles.count) verified", category: .backup)
    }
}
