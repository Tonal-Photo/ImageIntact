//
//  ProgressUpdateBatcher.swift
//  ImageIntact
//
//  Batches high-frequency progress updates to improve performance
//

import Foundation
import Combine

/// Batches progress updates to prevent excessive UI refreshes
@MainActor
final class ProgressUpdateBatcher {

    // MARK: - Configuration

    /// Maximum updates per second before batching kicks in
    private let maxUpdatesPerSecond = 10

    /// Batch interval when high-frequency detected (milliseconds)
    private let batchIntervalMs = 100

    // MARK: - State

    private var pendingUpdates: [ProgressUpdate] = []
    private var batchTimer: Timer?
    private var lastFlushTime = Date()
    private var updateCount = 0
    private var isHighFrequencyMode = false

    // MARK: - Types

    enum ProgressUpdate {
        case fileCompleted(destination: String, fileName: String, size: Int64)
        case destinationProgress(name: String, filesCompleted: Int?, bytesTransferred: Int64?, state: DestinationState?)
        case verificationProgress(destination: String, count: Int)
        case error(file: String?, destination: String?, error: String)
    }

    // MARK: - Singleton

    static let shared = ProgressUpdateBatcher()

    private init() {}

    // MARK: - Public API

    /// Submit an update for batching
    func submitUpdate(_ update: ProgressUpdate) {
        pendingUpdates.append(update)
        updateCount += 1

        // Check if we should enter high-frequency mode
        let timeSinceLastFlush = Date().timeIntervalSince(lastFlushTime)
        let currentRate = Double(updateCount) / max(0.1, timeSinceLastFlush)

        if currentRate > Double(maxUpdatesPerSecond) && !isHighFrequencyMode {
            enterHighFrequencyMode()
        } else if !isHighFrequencyMode {
            // In normal mode, flush immediately
            flushPendingUpdates()
        }
    }

    /// Force flush all pending updates
    func flush() {
        flushPendingUpdates()
    }

    /// Reset batcher state
    func reset() {
        batchTimer?.invalidate()
        batchTimer = nil
        pendingUpdates.removeAll()
        updateCount = 0
        isHighFrequencyMode = false
        lastFlushTime = Date()
    }

    // MARK: - Private Methods

    private func enterHighFrequencyMode() {
        guard !isHighFrequencyMode else { return }

        isHighFrequencyMode = true
        print("⚡ ProgressUpdateBatcher: Entering high-frequency mode (>\\(maxUpdatesPerSecond) updates/sec)")

        // Start batch timer
        batchTimer = Timer.scheduledTimer(withTimeInterval: Double(batchIntervalMs) / 1000.0, repeats: true) { _ in
            Task { @MainActor in
                self.flushPendingUpdates()
                self.checkExitHighFrequencyMode()
            }
        }
    }

    private func checkExitHighFrequencyMode() {
        let timeSinceLastFlush = Date().timeIntervalSince(lastFlushTime)
        let currentRate = Double(updateCount) / max(0.1, timeSinceLastFlush)

        if currentRate < Double(maxUpdatesPerSecond) * 0.5 { // 50% threshold for hysteresis
            exitHighFrequencyMode()
        }
    }

    private func exitHighFrequencyMode() {
        guard isHighFrequencyMode else { return }

        isHighFrequencyMode = false
        batchTimer?.invalidate()
        batchTimer = nil
        print("⚡ ProgressUpdateBatcher: Exiting high-frequency mode")
    }

    private func flushPendingUpdates() {
        guard !pendingUpdates.isEmpty else { return }

        // Group updates by type for efficient processing
        var fileCompletions: [(destination: String, fileName: String, size: Int64)] = []
        var destinationUpdates: [String: (filesCompleted: Int?, bytesTransferred: Int64?, state: DestinationState?)] = [:]
        var verificationUpdates: [String: Int] = [:]
        var errors: [(file: String?, destination: String?, error: String)] = []

        for update in pendingUpdates {
            switch update {
            case .fileCompleted(let dest, let file, let size):
                fileCompletions.append((dest, file, size))

            case .destinationProgress(let name, let files, let bytes, let state):
                // Merge with existing update for this destination
                var existing = destinationUpdates[name] ?? (nil, nil, nil)
                if let files = files { existing.filesCompleted = files }
                if let bytes = bytes { existing.bytesTransferred = bytes }
                if let state = state { existing.state = state }
                destinationUpdates[name] = existing

            case .verificationProgress(let dest, let count):
                // Keep only the latest count for each destination
                verificationUpdates[dest] = count

            case .error(let file, let dest, let error):
                errors.append((file, dest, error))
            }
        }

        // Apply batched updates to ProgressPublisher
        let publisher = ProgressPublisher.shared

        // Process file completions (aggregate by destination)
        var completionsByDest: [String: (count: Int, totalSize: Int64)] = [:]
        for (dest, _, size) in fileCompletions {
            var stats = completionsByDest[dest] ?? (0, 0)
            stats.count += 1
            stats.totalSize += size
            completionsByDest[dest] = stats
        }

        for (dest, stats) in completionsByDest {
            // Report aggregated completion using the public API
            if let currentProgress = publisher.destinations[dest] {
                publisher.updateDestinationProgress(
                    name: dest,
                    filesCompleted: currentProgress.filesCompleted + stats.count,
                    bytesTransferred: currentProgress.bytesTransferred + stats.totalSize
                )
            }
        }

        // Process destination updates
        for (name, update) in destinationUpdates {
            publisher.updateDestinationProgress(
                name: name,
                filesCompleted: update.filesCompleted,
                bytesTransferred: update.bytesTransferred,
                state: update.state
            )
        }

        // Process verification updates
        for (dest, count) in verificationUpdates {
            publisher.updateDestinationProgress(
                name: dest,
                verifiedCount: count
            )
        }

        // Process errors
        for (file, dest, error) in errors {
            publisher.reportError(file: file, destination: dest, error: error)
        }

        // Clear pending updates
        let updateCount = pendingUpdates.count
        pendingUpdates.removeAll()

        // Update metrics
        lastFlushTime = Date()
        self.updateCount = 0

        if isHighFrequencyMode && updateCount > 1 {
            print("⚡ Batched \\(updateCount) updates into single UI refresh")
        }
    }
}

// MARK: - ProgressPublisher Integration

extension ProgressPublisher {

    /// Report file completion with optional batching
    func reportFileCompletedBatched(destination: String, fileName: String, size: Int64) {
        if ProgressPerformanceMonitor.shared.updateFrequency > 20 {
            // Use batching for high-frequency updates
            ProgressUpdateBatcher.shared.submitUpdate(
                .fileCompleted(destination: destination, fileName: fileName, size: size)
            )
        } else {
            // Direct update for normal frequency
            reportFileCompleted(destination: destination, fileName: fileName, size: size)
        }
    }

    /// Flush any pending batched updates
    func flushBatchedUpdates() {
        ProgressUpdateBatcher.shared.flush()
    }
}