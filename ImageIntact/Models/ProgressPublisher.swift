//
//  ProgressPublisher.swift
//  ImageIntact
//
//  Centralized progress tracking system using Combine publishers
//  This is the single source of truth for all backup progress data
//

import Foundation
import Combine

/// Represents the progress of a single destination
struct DestinationProgress: Equatable {
    let name: String
    var filesCompleted: Int = 0
    var filesTotal: Int = 0
    var bytesTransferred: Int64 = 0
    var bytesTotal: Int64 = 0
    var state: DestinationState = .idle
    var currentFile: String = ""
    var speed: Double = 0.0 // MB/s
    var eta: TimeInterval? = nil
    var isVerifying: Bool = false
    var verifiedCount: Int = 0
}

enum DestinationState: String, Equatable {
    case idle = "idle"
    case preparing = "preparing"
    case copying = "copying"
    case verifying = "verifying"
    case complete = "complete"
    case failed = "failed"
    case cancelled = "cancelled"
}

/// Main progress publisher for all backup operations
@MainActor
final class ProgressPublisher: ObservableObject {

    // MARK: - Singleton
    static let shared = ProgressPublisher()

    // MARK: - Published Properties for UI

    // Overall backup progress
    @Published private(set) var isBackupRunning: Bool = false
    @Published private(set) var currentPhase: BackupPhase = .idle
    @Published private(set) var overallProgress: Double = 0.0 // 0.0 to 1.0
    @Published private(set) var statusMessage: String = ""

    // File progress
    @Published private(set) var totalFiles: Int = 0
    @Published private(set) var processedFiles: Int = 0
    @Published private(set) var currentFileName: String = ""

    // Byte progress
    @Published private(set) var totalBytes: Int64 = 0
    @Published private(set) var transferredBytes: Int64 = 0
    @Published private(set) var currentSpeed: Double = 0.0 // MB/s
    @Published private(set) var estimatedTimeRemaining: TimeInterval? = nil

    // Per-destination progress
    @Published private(set) var destinations: [String: DestinationProgress] = [:]

    // Error tracking
    @Published private(set) var lastError: String? = nil
    @Published private(set) var failedFiles: [(file: String, destination: String, error: String)] = []

    // Vision/Core Image analysis progress
    @Published private(set) var isAnalyzing: Bool = false
    @Published private(set) var analyzedImages: Int = 0
    @Published private(set) var totalImagesToAnalyze: Int = 0

    // Network operation status
    @Published private(set) var networkOperationInProgress: Bool = false
    @Published private(set) var networkOperationMessage: String = ""
    @Published private(set) var networkRetryAttempt: Int = 0
    @Published private(set) var networkRetryMaxAttempts: Int = 0

    // MARK: - Private State
    private var speedSamples: [Double] = []
    private let maxSpeedSamples = 10
    private var lastSpeedUpdate = Date()
    private let speedUpdateInterval: TimeInterval = 0.5

    // MARK: - Initialization
    private init() {
        print("📊 ProgressPublisher initialized")
    }

    // MARK: - Public Update Methods

    /// Start a new backup operation
    func startBackup(totalFiles: Int, totalBytes: Int64, destinationNames: [String]) {
        print("📊 ProgressPublisher: Starting backup with \(totalFiles) files, \(destinationNames.count) destinations")

        self.isBackupRunning = true
        self.totalFiles = totalFiles
        self.totalBytes = totalBytes
        self.processedFiles = 0
        self.transferredBytes = 0
        self.overallProgress = 0.0
        self.currentSpeed = 0.0
        self.estimatedTimeRemaining = nil
        self.failedFiles.removeAll()
        self.lastError = nil
        self.speedSamples.removeAll()

        // Initialize destination progress
        self.destinations.removeAll()
        for name in destinationNames {
            self.destinations[name] = DestinationProgress(
                name: name,
                filesTotal: totalFiles,
                bytesTotal: totalBytes / Int64(destinationNames.count) // Divide bytes among destinations
            )
        }
    }

    /// Update phase
    func updatePhase(_ phase: BackupPhase) {
        print("📊 ProgressPublisher: Phase changed to \(phase)")
        self.currentPhase = phase

        // Update status message based on phase
        switch phase {
        case .idle:
            statusMessage = "Ready"
        case .analyzingSource:
            statusMessage = "Analyzing source files..."
        case .buildingManifest:
            statusMessage = "Building file manifest..."
        case .copyingFiles:
            statusMessage = "Copying files to destinations..."
        case .flushingToDisk:
            statusMessage = "Flushing data to disk..."
        case .verifyingDestinations:
            statusMessage = "Verifying file checksums..."
        case .complete:
            statusMessage = "Backup complete!"
            isBackupRunning = false
        }
    }

    /// Update progress for a specific destination
    func updateDestinationProgress(
        name: String,
        filesCompleted: Int? = nil,
        bytesTransferred: Int64? = nil,
        state: DestinationState? = nil,
        currentFile: String? = nil,
        isVerifying: Bool? = nil,
        verifiedCount: Int? = nil
    ) {
        guard var progress = destinations[name] else {
            print("⚠️ ProgressPublisher: Unknown destination \(name)")
            return
        }

        // Update fields if provided
        if let files = filesCompleted {
            progress.filesCompleted = files
            print("📊 ProgressPublisher: \(name) progress = \(files)/\(progress.filesTotal)")
        }

        if let bytes = bytesTransferred {
            progress.bytesTransferred = bytes
            updateSpeed(bytes: bytes, destination: name)
        }

        if let state = state {
            progress.state = state
        }

        if let file = currentFile {
            progress.currentFile = file
            self.currentFileName = file // Also update global current file
        }

        if let verifying = isVerifying {
            progress.isVerifying = verifying
        }

        if let verified = verifiedCount {
            progress.verifiedCount = verified
        }

        // Update the destination
        destinations[name] = progress

        // Recalculate overall progress
        updateOverallProgress()
    }

    /// Report a file completion
    func reportFileCompleted(destination: String, fileName: String, size: Int64) {
        guard var progress = destinations[destination] else { return }

        progress.filesCompleted += 1
        progress.bytesTransferred += size
        destinations[destination] = progress

        // Update global counters (max of all destinations since they process same files)
        let maxCompleted = destinations.values.map { $0.filesCompleted }.max() ?? 0
        self.processedFiles = maxCompleted

        print("📊 ProgressPublisher: File completed at \(destination): \(fileName) (\(progress.filesCompleted)/\(progress.filesTotal))")

        updateOverallProgress()
    }

    private let maxFailedFiles = 1000  // Prevent unbounded growth

    /// Report an error
    func reportError(file: String? = nil, destination: String? = nil, error: String) {
        self.lastError = error

        if let file = file, let dest = destination {
            failedFiles.append((file: file, destination: dest, error: error))

            // Limit array size to prevent memory issues
            if failedFiles.count > maxFailedFiles {
                failedFiles.removeFirst(failedFiles.count - maxFailedFiles)
            }

            print("❌ ProgressPublisher: Error for \(file) at \(dest): \(error)")
        } else {
            print("❌ ProgressPublisher: Error: \(error)")
        }
    }

    /// Update Vision/Core Image analysis progress
    func updateAnalysisProgress(current: Int, total: Int) {
        self.isAnalyzing = total > 0
        self.analyzedImages = current
        self.totalImagesToAnalyze = total

        if current >= total {
            self.isAnalyzing = false
        }
    }

    /// Update network operation status
    func updateNetworkOperation(inProgress: Bool, message: String = "", retryAttempt: Int = 0, maxAttempts: Int = 0) {
        self.networkOperationInProgress = inProgress
        self.networkOperationMessage = message
        self.networkRetryAttempt = retryAttempt
        self.networkRetryMaxAttempts = maxAttempts

        if inProgress && !message.isEmpty {
            print("🌐 Network: \(message)" + (retryAttempt > 0 ? " (attempt \(retryAttempt)/\(maxAttempts))" : ""))
        }
    }

    /// Complete the backup
    func completeBackup() {
        // Flush any pending batched updates first
        ProgressUpdateBatcher.shared.flush()

        self.isBackupRunning = false
        self.currentPhase = .complete
        self.overallProgress = 1.0
        self.statusMessage = failedFiles.isEmpty ? "Backup completed successfully!" : "Backup completed with \(failedFiles.count) errors"

        // Reset the batcher for next backup
        ProgressUpdateBatcher.shared.reset()

        print("✅ ProgressPublisher: Backup complete")
    }

    /// Cancel the backup
    func cancelBackup() {
        // Flush any pending batched updates first
        ProgressUpdateBatcher.shared.flush()

        self.isBackupRunning = false
        self.currentPhase = .idle
        self.statusMessage = "Backup cancelled"

        // Mark all destinations as cancelled
        for (name, var progress) in destinations {
            progress.state = .cancelled
            destinations[name] = progress
        }

        // Reset the batcher
        ProgressUpdateBatcher.shared.reset()

        print("🛑 ProgressPublisher: Backup cancelled")
    }

    /// Reset all progress
    func reset() {
        // Reset batcher first
        ProgressUpdateBatcher.shared.reset()

        self.isBackupRunning = false
        self.currentPhase = .idle
        self.overallProgress = 0.0
        self.statusMessage = ""
        self.totalFiles = 0
        self.processedFiles = 0
        self.currentFileName = ""
        self.totalBytes = 0
        self.transferredBytes = 0
        self.currentSpeed = 0.0
        self.estimatedTimeRemaining = nil
        self.destinations.removeAll()
        self.lastError = nil
        self.failedFiles.removeAll()
        self.isAnalyzing = false
        self.analyzedImages = 0
        self.totalImagesToAnalyze = 0
        self.speedSamples.removeAll()

        print("🔄 ProgressPublisher: Reset")
    }

    // MARK: - Private Methods

    private func updateOverallProgress() {
        guard !destinations.isEmpty else {
            overallProgress = 0.0
            return
        }

        // Calculate overall progress as average of all destinations
        // Each destination contributes equally to overall progress
        var totalProgress = 0.0

        for progress in destinations.values {
            let copyProgress = progress.filesTotal > 0
                ? Double(progress.filesCompleted) / Double(progress.filesTotal)
                : 0.0

            let verifyProgress = progress.filesTotal > 0
                ? Double(progress.verifiedCount) / Double(progress.filesTotal)
                : 0.0

            // If verifying, progress is 50% copy + 50% verify
            // If copying, progress is just copy progress
            let destinationProgress = progress.isVerifying
                ? (0.5 + verifyProgress * 0.5)
                : (copyProgress * 0.5) // Copying is only half the work

            totalProgress += destinationProgress
        }

        overallProgress = totalProgress / Double(destinations.count)

        // Calculate total bytes transferred
        transferredBytes = destinations.values.reduce(0) { $0 + $1.bytesTransferred }

        // Update ETA
        if currentSpeed > 0 && totalBytes > transferredBytes {
            let remainingBytes = totalBytes - transferredBytes
            let remainingSeconds = Double(remainingBytes) / (currentSpeed * 1024 * 1024)
            estimatedTimeRemaining = remainingSeconds
        } else {
            estimatedTimeRemaining = nil
        }
    }

    private func updateSpeed(bytes: Int64, destination: String) {
        let now = Date()
        guard now.timeIntervalSince(lastSpeedUpdate) >= speedUpdateInterval else { return }

        // Calculate speed for this destination
        guard var progress = destinations[destination] else { return }

        let elapsedTime = now.timeIntervalSince(lastSpeedUpdate)
        if elapsedTime > 0 {
            let speed = Double(bytes - progress.bytesTransferred) / elapsedTime / 1_048_576 // MB/s

            // Add to samples for smoothing
            speedSamples.append(speed)
            if speedSamples.count > maxSpeedSamples {
                speedSamples.removeFirst()
            }

            // Calculate average speed
            let avgSpeed = speedSamples.reduce(0, +) / Double(speedSamples.count)
            progress.speed = avgSpeed
            destinations[destination] = progress

            // Update global speed (max of all destinations)
            currentSpeed = destinations.values.map { $0.speed }.max() ?? 0.0
        }

        lastSpeedUpdate = now
    }
}

// MARK: - Helper Methods for UI

extension ProgressPublisher {

    /// Get progress for a specific destination (for UI binding)
    func progressForDestination(_ name: String) -> DestinationProgress? {
        return destinations[name]
    }

    /// Get file progress as a percentage string
    var fileProgressPercentage: String {
        guard totalFiles > 0 else { return "0%" }
        let percentage = Int((Double(processedFiles) / Double(totalFiles)) * 100)
        return "\(percentage)%"
    }

    /// Get byte progress as a percentage string
    var byteProgressPercentage: String {
        guard totalBytes > 0 else { return "0%" }
        let percentage = Int((Double(transferredBytes) / Double(totalBytes)) * 100)
        return "\(percentage)%"
    }

    /// Format bytes for display
    static func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    /// Format speed for display
    static func formatSpeed(_ speed: Double) -> String {
        return String(format: "%.1f MB/s", speed)
    }

    /// Format ETA for display
    static func formatETA(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "Less than a minute"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) minute\(minutes == 1 ? "" : "s")"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}