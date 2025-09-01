//
//  SleepPrevention.swift
//  ImageIntact
//
//  Manages sleep prevention during backup operations
//

import Foundation
import IOKit.pwr_mgt

/// Manages system sleep prevention during backup operations
class SleepPrevention {
    static let shared = SleepPrevention()
    
    private var assertionID: IOPMAssertionID = 0
    private var isPreventingSleep = false
    private let lock = NSLock()
    private var timeoutTimer: Timer?
    private let maxDuration: TimeInterval = 14400 // 4 hours maximum
    
    private init() {}
    
    /// Start preventing system sleep
    /// - Parameters:
    ///   - reason: A descriptive reason for preventing sleep
    ///   - timeout: Optional custom timeout in seconds (default: 4 hours)
    /// - Returns: True if sleep prevention was successfully enabled
    @discardableResult
    func startPreventingSleep(reason: String = "ImageIntact Backup in Progress", timeout: TimeInterval? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        // If already preventing sleep, cancel the old timer and reset
        if isPreventingSleep {
            logInfo("Sleep prevention already active - resetting timeout")
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }
        
        // Check if the preference is enabled
        guard PreferencesManager.shared.preventSleepDuringBackup else {
            logInfo("Sleep prevention disabled by user preference")
            return false
        }
        
        // Create the power assertion if not already active
        if !isPreventingSleep {
            let result = IOPMAssertionCreateWithName(
                kIOPMAssertionTypeNoIdleSleep as CFString,
                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                reason as CFString,
                &assertionID
            )
            
            if result == kIOReturnSuccess {
                isPreventingSleep = true
                logInfo("Sleep prevention enabled: \(reason)")
                ApplicationLogger.shared.info("Sleep prevention enabled", category: .performance)
            } else {
                logError("Failed to prevent sleep: IOKit error \(result)")
                ApplicationLogger.shared.error("Failed to prevent sleep: IOKit error \(result)", category: .performance)
                return false
            }
        }
        
        // Set up timeout timer for safety
        let timeoutDuration = timeout ?? maxDuration
        setupTimeoutTimer(duration: timeoutDuration)
        
        return true
    }
    
    /// Set up a timeout timer to automatically stop sleep prevention
    private func setupTimeoutTimer(duration: TimeInterval) {
        // Run on main thread to ensure timer works properly
        DispatchQueue.main.async { [weak self] in
            self?.timeoutTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                self?.handleTimeout()
            }
        }
        
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        logInfo("Sleep prevention timeout set: \(hours)h \(minutes)m")
    }
    
    /// Handle timeout expiration
    private func handleTimeout() {
        logWarning("Sleep prevention timeout reached - automatically stopping")
        ApplicationLogger.shared.warning("Sleep prevention timeout reached after \(maxDuration/3600) hours", category: .performance)
        stopPreventingSleep()
    }
    
    /// Stop preventing system sleep
    func stopPreventingSleep() {
        lock.lock()
        defer { lock.unlock() }
        
        // Cancel timeout timer
        timeoutTimer?.invalidate()
        timeoutTimer = nil
        
        // If not preventing sleep, nothing to do
        guard isPreventingSleep else {
            return
        }
        
        // Release the power assertion
        let result = IOPMAssertionRelease(assertionID)
        
        if result == kIOReturnSuccess {
            isPreventingSleep = false
            assertionID = 0
            logInfo("Sleep prevention disabled")
            ApplicationLogger.shared.info("Sleep prevention disabled", category: .performance)
        } else {
            logError("Failed to release sleep prevention: IOKit error \(result)")
            ApplicationLogger.shared.error("Failed to release sleep prevention: IOKit error \(result)", category: .performance)
        }
    }
    
    /// Check if sleep is currently being prevented
    var isPreventing: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isPreventingSleep
    }
    
    /// Ensure sleep prevention is stopped (e.g., on app termination)
    deinit {
        if isPreventingSleep {
            stopPreventingSleep()
        }
    }
}