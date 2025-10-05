//
//  SleepPrevention.swift
//  ImageIntact
//
//  Manages sleep prevention during backup operations
//

import Foundation
import IOKit.pwr_mgt

/// Manages system sleep prevention during backup operations
actor SleepPrevention {
    static let shared = SleepPrevention()

    private var assertionID: IOPMAssertionID = 0
    private var isPreventingSleep = false
    private var timeoutTimer: Timer?
    private let maxDuration: TimeInterval = 14400 // 4 hours maximum

    private init() {}
    
    /// Start preventing system sleep
    /// - Parameters:
    ///   - reason: A descriptive reason for preventing sleep
    ///   - timeout: Optional custom timeout in seconds (default: 4 hours)
    /// - Returns: True if sleep prevention was successfully enabled
    @discardableResult
    func startPreventingSleep(reason: String = "ImageIntact Backup in Progress", timeout: TimeInterval? = nil) async -> Bool {
        
        // If already preventing sleep, cancel the old timer and reset
        if isPreventingSleep {
            await ApplicationLogger.shared.info("Sleep prevention already active - resetting timeout", category: .performance)
            timeoutTimer?.invalidate()
            timeoutTimer = nil
        }
        
        // Check if the preference is enabled
        guard await PreferencesManager.shared.preventSleepDuringBackup else {
            await ApplicationLogger.shared.info("Sleep prevention disabled by user preference", category: .performance)
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
                await ApplicationLogger.shared.info("Sleep prevention enabled: \(reason)", category: .performance)
            } else {
                await ApplicationLogger.shared.error("Failed to prevent sleep: IOKit error \(result)", category: .performance)
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
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { _ in
                Task { [weak self] in
                    await self?.handleTimeout()
                }
            }
            Task { [weak self] in
                await self?.setTimeoutTimer(timer)
            }
        }
        
        let hours = Int(duration / 3600)
        let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
        Task { @MainActor in
            ApplicationLogger.shared.info("Sleep prevention timeout set: \(hours)h \(minutes)m", category: .performance)
        }
    }
    
    /// Helper to set the timeout timer
    private func setTimeoutTimer(_ timer: Timer?) {
        self.timeoutTimer = timer
    }

    /// Handle timeout expiration
    private func handleTimeout() {
        Task {
            await ApplicationLogger.shared.warning("Sleep prevention timeout reached - automatically stopping", category: .performance)
            await ApplicationLogger.shared.warning("Sleep prevention timeout reached after \(self.maxDuration/3600) hours", category: .performance)
            await stopPreventingSleep()
        }
    }
    
    /// Stop preventing system sleep
    func stopPreventingSleep() async {
        
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
            await ApplicationLogger.shared.info("Sleep prevention disabled", category: .performance)
        } else {
            await ApplicationLogger.shared.error("Failed to release sleep prevention: IOKit error \(result)", category: .performance)
        }
    }
    
    /// Check if sleep is currently being prevented
    var isPreventing: Bool {
        return isPreventingSleep
    }
    
    // Actor cannot have deinit, sleep prevention will be cleaned up on app termination
}