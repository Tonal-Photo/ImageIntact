//
//  AnalyticsManager.swift
//  ImageIntact
//
//  Privacy-focused analytics for understanding usage patterns
//

import Foundation
import CryptoKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Manages privacy-focused analytics and telemetry
@MainActor
class AnalyticsManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = AnalyticsManager()
    
    // MARK: - Properties
    
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: "AnalyticsEnabled")
            if !isEnabled {
                clearAllData()
            }
        }
    }
    
    private var sessionID: String
    private var events: [AnalyticsEvent] = []
    private let maxEventsInMemory = 100
    private let analyticsQueue = DispatchQueue(label: "com.imageintact.analytics")
    
    // MARK: - Event Types
    
    enum EventType: String, Codable {
        // App lifecycle
        case appLaunched = "app_launched"
        case appTerminated = "app_terminated"
        
        // Backup events
        case backupStarted = "backup_started"
        case backupCompleted = "backup_completed"
        case backupCancelled = "backup_cancelled"
        case backupFailed = "backup_failed"
        
        // Feature usage
        case featureUsed = "feature_used"
        case premiumFeatureAttempted = "premium_feature_attempted"
        case premiumFeatureUnlocked = "premium_feature_unlocked"
        
        // IAP events
        case purchaseInitiated = "purchase_initiated"
        case purchaseCompleted = "purchase_completed"
        case purchaseFailed = "purchase_failed"
        case purchaseRestored = "purchase_restored"
        
        // Settings changes
        case settingChanged = "setting_changed"
        case presetCreated = "preset_created"
        case presetUsed = "preset_used"
        
        // Error tracking
        case errorOccurred = "error_occurred"
        case crashDetected = "crash_detected"
    }
    
    // MARK: - Analytics Event
    
    struct AnalyticsEvent: Codable {
        let id: UUID
        let timestamp: Date
        let sessionID: String
        let type: EventType
        let properties: [String: String]
        let buildType: String
        let appVersion: String
        let osVersion: String
    }
    
    // MARK: - Initialization
    
    private init() {
        self.isEnabled = UserDefaults.standard.bool(forKey: "AnalyticsEnabled")
        self.sessionID = UUID().uuidString
        
        // Register for app lifecycle
        #if os(macOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
        #elseif os(iOS)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        #endif
        
        // Track app launch
        trackEvent(.appLaunched)
    }
    
    // MARK: - Event Tracking
    
    /// Track an analytics event
    func trackEvent(_ type: EventType, properties: [String: String] = [:]) {
        guard isEnabled else { return }
        
        let currentSessionID = self.sessionID
        let buildType = BuildConfiguration.editionName
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        
        analyticsQueue.async { [weak self] in
            guard let self = self else { return }
            
            let event = AnalyticsEvent(
                id: UUID(),
                timestamp: Date(),
                sessionID: currentSessionID,
                type: type,
                properties: self.sanitizeProperties(properties),
                buildType: buildType,
                appVersion: appVersion,
                osVersion: osVersion
            )
            
            Task { @MainActor in
                self.events.append(event)
                
                // Trim events if needed
                if self.events.count > self.maxEventsInMemory {
                    self.events.removeFirst(self.events.count - self.maxEventsInMemory)
                }
                
                // Save to disk periodically
                if self.events.count % 10 == 0 {
                    self.saveEvents()
                }
            }
        }
    }
    
    /// Track a backup session
    func trackBackup(fileCount: Int, totalBytes: Int64, destinationCount: Int, duration: TimeInterval, success: Bool) {
        let properties: [String: String] = [
            "file_count": "\(fileCount)",
            "total_mb": "\(totalBytes / 1024 / 1024)",
            "destination_count": "\(destinationCount)",
            "duration_seconds": "\(Int(duration))",
            "success": "\(success)"
        ]
        
        trackEvent(success ? .backupCompleted : .backupFailed, properties: properties)
    }
    
    /// Track feature usage
    func trackFeatureUsage(_ feature: PremiumFeatureManager.Feature) {
        let properties = [
            "feature": feature.rawValue,
            "is_premium": "\(PremiumFeatureManager.shared.isUnlocked(feature))"
        ]
        
        trackEvent(.featureUsed, properties: properties)
    }
    
    /// Track IAP events
    func trackPurchase(initiated: Bool = false, completed: Bool = false, failed: Bool = false, restored: Bool = false) {
        if initiated {
            trackEvent(.purchaseInitiated)
        } else if completed {
            trackEvent(.purchaseCompleted, properties: ["price": StoreManager.shared.proPriceString])
        } else if failed {
            trackEvent(.purchaseFailed)
        } else if restored {
            trackEvent(.purchaseRestored)
        }
    }
    
    /// Track errors (without PII)
    func trackError(_ error: Error, context: String) {
        let properties = [
            "error_type": String(describing: type(of: error)),
            "context": context,
            "error_code": "\((error as NSError).code)"
        ]
        
        trackEvent(.errorOccurred, properties: properties)
    }
    
    // MARK: - Data Management
    
    /// Sanitize properties to remove PII
    nonisolated private func sanitizeProperties(_ properties: [String: String]) -> [String: String] {
        var sanitized = properties
        
        // Remove any paths that might contain usernames
        for (key, value) in sanitized {
            if value.contains("/Users/") || value.contains("/home/") {
                sanitized[key] = PIISanitizer().sanitize(value)
            }
        }
        
        return sanitized
    }
    
    /// Save events to disk
    private func saveEvents() {
        guard isEnabled else { return }
        
        do {
            let url = getAnalyticsFileURL()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(events)
            try data.write(to: url)
        } catch {
            print("Failed to save analytics: \(error)")
        }
    }
    
    /// Load events from disk
    private func loadEvents() {
        guard isEnabled else { return }
        
        do {
            let url = getAnalyticsFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            events = try decoder.decode([AnalyticsEvent].self, from: data)
        } catch {
            print("Failed to load analytics: \(error)")
        }
    }
    
    /// Get analytics file URL
    private func getAnalyticsFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("analytics.json")
    }
    
    /// Clear all analytics data
    private func clearAllData() {
        events.removeAll()
        
        let url = getAnalyticsFileURL()
        try? FileManager.default.removeItem(at: url)
    }
    
    // MARK: - Reporting
    
    /// Generate anonymous usage statistics
    func generateUsageReport() -> UsageReport {
        let backupEvents = events.filter { $0.type == .backupCompleted }
        let totalBackups = backupEvents.count
        
        let totalFiles = backupEvents.compactMap { event in
            Int(event.properties["file_count"] ?? "0")
        }.reduce(0, +)
        
        let totalMB = backupEvents.compactMap { event in
            Int(event.properties["total_mb"] ?? "0")
        }.reduce(0, +)
        
        let features = events.filter { $0.type == .featureUsed }
            .compactMap { $0.properties["feature"] }
            .reduce(into: [:]) { counts, feature in
                counts[feature, default: 0] += 1
            }
        
        let errors = events.filter { $0.type == .errorOccurred }.count
        
        return UsageReport(
            sessionCount: Set(events.map { $0.sessionID }).count,
            totalBackups: totalBackups,
            totalFilesBackedUp: totalFiles,
            totalMBProcessed: totalMB,
            mostUsedFeatures: features.sorted { $0.value > $1.value }.prefix(5).map { $0.key },
            errorCount: errors,
            buildType: BuildConfiguration.editionName,
            isPro: StoreManager.shared.hasPro
        )
    }
    
    /// Usage report structure
    struct UsageReport {
        let sessionCount: Int
        let totalBackups: Int
        let totalFilesBackedUp: Int
        let totalMBProcessed: Int
        let mostUsedFeatures: [String]
        let errorCount: Int
        let buildType: String
        let isPro: Bool
    }
    
    // MARK: - Lifecycle
    
    @objc private func appWillTerminate() {
        trackEvent(.appTerminated)
        saveEvents()
    }
}

// MARK: - Privacy Notice

extension AnalyticsManager {
    /// Get privacy policy text
    static var privacyNotice: String {
        """
        ImageIntact Analytics
        
        We collect anonymous usage data to improve the app. This includes:
        • Feature usage patterns
        • Backup statistics (file counts, sizes)
        • Error occurrences (no personal data)
        • App version and OS version
        
        We NEVER collect:
        • File names or contents
        • Folder paths with usernames
        • Personal information
        • Network addresses
        • Email addresses
        
        All data is stored locally on your device and is never sent to external servers.
        You can disable analytics at any time in Settings.
        """
    }
}