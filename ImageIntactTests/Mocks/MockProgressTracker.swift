//
//  MockProgressTracker.swift
//  ImageIntactTests
//
//  Mock implementation of ProgressTrackerProtocol for testing
//

import Foundation
@testable import ImageIntact

/// Mock implementation of ProgressTrackerProtocol for testing
@MainActor
class MockProgressTracker: ProgressTrackerProtocol {
    
    // MARK: - Properties
    
    var totalFiles: Int = 0
    var processedFiles: Int = 0
    var currentFileName: String = ""
    var totalBytesToCopy: Int64 = 0
    var totalBytesCopied: Int64 = 0
    var copySpeed: Double = 0.0
    var estimatedSecondsRemaining: Double?
    var overallProgress: Double = 0.0
    var destinationProgress: [String: Int] = [:]
    var destinationTotalFiles: [String: Int] = [:]
    var destinationStates: [String: String] = [:]
    
    // MARK: - Tracking for assertions
    
    var resetAllCalled = false
    var startCopyTrackingCalled = false
    var updateCurrentFileCalls: [(fileName: String, index: Int, total: Int)] = []
    var incrementProcessedFilesCalls = 0
    var updateByteProgressCalls: [(copied: Int64, total: Int64)] = []
    var updateCopySpeedCalls: [Double] = []
    var initializeDestinationsCalls: [[URL]] = []
    var setDestinationProgressCalls: [(progress: Int, destination: String)] = []
    var setDestinationTotalFilesCalls: [(total: Int, destination: String)] = []
    var setDestinationStateCalls: [(state: String, destination: String)] = []
    var updateFromCoordinatorCalls: [(overallProgress: Double, totalBytes: Int64, copiedBytes: Int64, speed: Double)] = []
    var updateETACalls = 0
    
    // MARK: - ProgressTrackerProtocol Methods
    
    func resetAll() {
        resetAllCalled = true
        totalFiles = 0
        processedFiles = 0
        currentFileName = ""
        totalBytesToCopy = 0
        totalBytesCopied = 0
        copySpeed = 0.0
        estimatedSecondsRemaining = nil
        overallProgress = 0.0
        destinationProgress.removeAll()
        destinationTotalFiles.removeAll()
        destinationStates.removeAll()
    }
    
    func startCopyTracking() {
        startCopyTrackingCalled = true
    }
    
    func updateCurrentFile(_ fileName: String, index: Int, total: Int) {
        updateCurrentFileCalls.append((fileName: fileName, index: index, total: total))
        currentFileName = fileName
        totalFiles = total
    }
    
    func incrementProcessedFiles() {
        incrementProcessedFilesCalls += 1
        processedFiles += 1
    }
    
    func updateByteProgress(copied: Int64, total: Int64) {
        updateByteProgressCalls.append((copied: copied, total: total))
        totalBytesCopied = copied
        totalBytesToCopy = total
    }
    
    func updateCopySpeed(_ speed: Double) {
        updateCopySpeedCalls.append(speed)
        copySpeed = speed
    }
    
    func initializeDestinations(_ destinations: [URL]) {
        initializeDestinationsCalls.append(destinations)
        for dest in destinations {
            let name = dest.lastPathComponent
            destinationProgress[name] = 0
            destinationStates[name] = "pending"
        }
    }
    
    func setDestinationProgress(_ progress: Int, for destination: String) {
        setDestinationProgressCalls.append((progress: progress, destination: destination))
        destinationProgress[destination] = progress
    }
    
    func setDestinationTotalFiles(_ total: Int, for destination: String) {
        setDestinationTotalFilesCalls.append((total: total, destination: destination))
        destinationTotalFiles[destination] = total
    }
    
    func setDestinationState(_ state: String, for destination: String) {
        setDestinationStateCalls.append((state: state, destination: destination))
        destinationStates[destination] = state
    }
    
    func updateFromCoordinator(overallProgress: Double, totalBytes: Int64, copiedBytes: Int64, speed: Double) {
        updateFromCoordinatorCalls.append((
            overallProgress: overallProgress,
            totalBytes: totalBytes,
            copiedBytes: copiedBytes,
            speed: speed
        ))
        self.overallProgress = overallProgress
        self.totalBytesToCopy = totalBytes
        self.totalBytesCopied = copiedBytes
        self.copySpeed = speed
    }
    
    func updateETA() {
        updateETACalls += 1
        // Simple mock ETA calculation
        if copySpeed > 0 && totalBytesToCopy > totalBytesCopied {
            let remainingBytes = totalBytesToCopy - totalBytesCopied
            let remainingMB = Double(remainingBytes) / (1024 * 1024)
            estimatedSecondsRemaining = remainingMB / copySpeed
        } else {
            estimatedSecondsRemaining = nil
        }
    }
    
    // MARK: - Test Helper Methods
    
    /// Reset all tracking
    func resetTracking() {
        resetAllCalled = false
        startCopyTrackingCalled = false
        updateCurrentFileCalls.removeAll()
        incrementProcessedFilesCalls = 0
        updateByteProgressCalls.removeAll()
        updateCopySpeedCalls.removeAll()
        initializeDestinationsCalls.removeAll()
        setDestinationProgressCalls.removeAll()
        setDestinationTotalFilesCalls.removeAll()
        setDestinationStateCalls.removeAll()
        updateFromCoordinatorCalls.removeAll()
        updateETACalls = 0
    }
    
    /// Simulate progress to a specific percentage
    func simulateProgress(to percentage: Double) {
        let filesToProcess = Int(Double(totalFiles) * (percentage / 100.0))
        processedFiles = filesToProcess
        overallProgress = percentage / 100.0
        
        let bytesToCopy = Int64(Double(totalBytesToCopy) * (percentage / 100.0))
        totalBytesCopied = bytesToCopy
    }
    
    /// Verify that a destination was initialized
    func wasDestinationInitialized(_ destination: String) -> Bool {
        return destinationProgress.keys.contains(destination)
    }
    
    /// Get the last update for a specific destination
    func lastProgressUpdate(for destination: String) -> Int? {
        return setDestinationProgressCalls.last(where: { $0.destination == destination })?.progress
    }
    
    /// Verify state transition for a destination
    func verifyStateTransition(for destination: String, from: String, to: String) -> Bool {
        let states = setDestinationStateCalls.filter { $0.destination == destination }.map { $0.state }
        guard let fromIndex = states.firstIndex(of: from),
              let toIndex = states.firstIndex(of: to) else {
            return false
        }
        return toIndex > fromIndex
    }
}