//
//  ProgressTrackerProtocol.swift
//  ImageIntact
//
//  Protocol for abstracting progress tracking operations
//

import Foundation

/// Protocol defining progress tracking operations for backup functionality
@MainActor
protocol ProgressTrackerProtocol: AnyObject {
    
    // MARK: - Properties (Read-only for protocol)
    
    /// Total number of files to process
    var totalFiles: Int { get }
    
    /// Number of files processed so far
    var processedFiles: Int { get }
    
    /// Current file being processed
    var currentFileName: String { get }
    
    /// Total bytes to copy
    var totalBytesToCopy: Int64 { get }
    
    /// Total bytes copied so far
    var totalBytesCopied: Int64 { get }
    
    /// Current copy speed in MB/s
    var copySpeed: Double { get }
    
    /// Estimated seconds remaining
    var estimatedSecondsRemaining: Double? { get }
    
    /// Overall progress (0-1)
    var overallProgress: Double { get }
    
    /// Progress by destination
    var destinationProgress: [String: Int] { get }
    
    /// Total files per destination
    var destinationTotalFiles: [String: Int] { get }
    
    /// State of each destination
    var destinationStates: [String: String] { get }
    
    // MARK: - Methods
    
    /// Reset all progress tracking
    func resetAll()
    
    /// Start tracking copy operation
    func startCopyTracking()
    
    /// Update the current file being processed
    func updateCurrentFile(_ fileName: String, index: Int, total: Int)
    
    /// Increment the count of processed files
    func incrementProcessedFiles()
    
    /// Update byte progress
    func updateByteProgress(copied: Int64, total: Int64)
    
    /// Update copy speed
    func updateCopySpeed(_ speed: Double)
    
    /// Initialize destinations for tracking
    func initializeDestinations(_ destinations: [URL])
    
    /// Set progress for a specific destination
    func setDestinationProgress(_ progress: Int, for destination: String)
    
    /// Set total files for a specific destination
    func setDestinationTotalFiles(_ total: Int, for destination: String)
    
    /// Set state for a specific destination
    func setDestinationState(_ state: String, for destination: String)
    
    /// Update from coordinator status
    func updateFromCoordinator(overallProgress: Double, totalBytes: Int64, copiedBytes: Int64, speed: Double)
    
    /// Calculate and update ETA
    func updateETA()
}

// MARK: - Default Implementations

extension ProgressTrackerProtocol {
    /// Calculate progress as a percentage
    var progressPercentage: Double {
        guard totalFiles > 0 else { return 0 }
        return Double(processedFiles) / Double(totalFiles) * 100
    }
    
    /// Check if backup is complete
    var isComplete: Bool {
        return processedFiles >= totalFiles && totalFiles > 0
    }
    
    /// Get formatted speed string
    var formattedSpeed: String {
        return String(format: "%.1f MB/s", copySpeed)
    }
    
    /// Get formatted ETA string
    var formattedETA: String? {
        guard let seconds = estimatedSecondsRemaining else { return nil }
        
        if seconds < 60 {
            return "< 1 min"
        } else if seconds < 3600 {
            let minutes = Int(seconds / 60)
            return "\(minutes) min"
        } else {
            let hours = Int(seconds / 3600)
            let minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}