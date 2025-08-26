//
//  BackupPreset.swift
//  ImageIntact
//
//  Defines preset backup configurations for common scenarios
//

import Foundation
import SwiftUI

// MARK: - Backup Strategy
enum BackupStrategy: String, Codable, CaseIterable {
    case mirror = "Mirror"
    case archive = "Archive"
    case incremental = "Incremental"
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .mirror:
            return "Exact copy, deletes files not in source"
        case .archive:
            return "Never deletes, accumulates all files"
        case .incremental:
            return "Only copies new or changed files"
        }
    }
    
    var icon: String {
        switch self {
        case .mirror:
            return "arrow.triangle.2.circlepath"
        case .archive:
            return "archivebox"
        case .incremental:
            return "plus.circle"
        }
    }
}

// MARK: - Backup Schedule
enum BackupSchedule: String, Codable, CaseIterable {
    case manual = "Manual"
    case hourly = "Hourly"
    case daily = "Daily"
    case weekly = "Weekly"
    case onConnect = "On Drive Connect"
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .manual:
            return "Run backup manually"
        case .hourly:
            return "Automatic backup every hour"
        case .daily:
            return "Automatic backup once per day"
        case .weekly:
            return "Automatic backup once per week"
        case .onConnect:
            return "Start when backup drive connects"
        }
    }
    
    var icon: String {
        switch self {
        case .manual:
            return "hand.tap"
        case .hourly:
            return "clock"
        case .daily:
            return "calendar.day.timeline.left"
        case .weekly:
            return "calendar"
        case .onConnect:
            return "cable.connector"
        }
    }
}

// MARK: - Performance Mode
enum PerformanceMode: String, Codable, CaseIterable {
    case fast = "Fast"
    case balanced = "Balanced"
    case thorough = "Thorough"
    
    var displayName: String { rawValue }
    
    var description: String {
        switch self {
        case .fast:
            return "Skip verification, maximize speed"
        case .balanced:
            return "Sample verification, good speed"
        case .thorough:
            return "Full verification, maximum safety"
        }
    }
    
    var icon: String {
        switch self {
        case .fast:
            return "hare"
        case .balanced:
            return "gauge.medium"
        case .thorough:
            return "checkmark.shield"
        }
    }
    
    var verificationLevel: Double {
        switch self {
        case .fast: return 0.0      // No verification
        case .balanced: return 0.1  // 10% sampling
        case .thorough: return 1.0  // 100% verification
        }
    }
}

// MARK: - Backup Preset
struct BackupPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var icon: String
    var isBuiltIn: Bool
    
    // Configuration
    var strategy: BackupStrategy
    var schedule: BackupSchedule
    var performanceMode: PerformanceMode
    var fileTypeFilter: FileTypeFilter
    
    // Options
    var excludeCacheFiles: Bool
    var skipHiddenFiles: Bool
    var preventSleep: Bool
    var showNotification: Bool
    
    // Destinations
    var destinationCount: Int
    var preferredDriveUUIDs: [String]
    
    // Source and Destination Bookmarks (for custom presets)
    var sourceBookmark: Data?
    var destinationBookmarks: [Data?]
    
    // Metadata
    var createdDate: Date
    var lastUsedDate: Date?
    var useCount: Int
    
    init(
        id: UUID = UUID(),
        name: String,
        icon: String = "doc.text",
        isBuiltIn: Bool = false,
        strategy: BackupStrategy = .incremental,
        schedule: BackupSchedule = .manual,
        performanceMode: PerformanceMode = .balanced,
        fileTypeFilter: FileTypeFilter = .allFiles,
        excludeCacheFiles: Bool = true,
        skipHiddenFiles: Bool = true,
        preventSleep: Bool = true,
        showNotification: Bool = true,
        destinationCount: Int = 1,
        preferredDriveUUIDs: [String] = [],
        sourceBookmark: Data? = nil,
        destinationBookmarks: [Data?] = [],
        createdDate: Date = Date(),
        lastUsedDate: Date? = nil,
        useCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isBuiltIn = isBuiltIn
        self.strategy = strategy
        self.schedule = schedule
        self.performanceMode = performanceMode
        self.fileTypeFilter = fileTypeFilter
        self.excludeCacheFiles = excludeCacheFiles
        self.skipHiddenFiles = skipHiddenFiles
        self.preventSleep = preventSleep
        self.showNotification = showNotification
        self.destinationCount = destinationCount
        self.preferredDriveUUIDs = preferredDriveUUIDs
        self.sourceBookmark = sourceBookmark
        self.destinationBookmarks = destinationBookmarks
        self.createdDate = createdDate
        self.lastUsedDate = lastUsedDate
        self.useCount = useCount
    }
}

// MARK: - Built-in Presets
extension BackupPreset {
    static let builtInPresets: [BackupPreset] = [
        // Daily Workflow - For regular photographer workflow
        BackupPreset(
            name: "Daily Workflow",
            icon: "camera",
            isBuiltIn: true,
            strategy: .incremental,
            schedule: .daily,
            performanceMode: .balanced,
            fileTypeFilter: .photosOnly,
            excludeCacheFiles: true,
            destinationCount: 2
        ),
        
        // Travel Backup - Quick backup while on location
        BackupPreset(
            name: "Travel Backup",
            icon: "airplane",
            isBuiltIn: true,
            strategy: .incremental,
            schedule: .onConnect,
            performanceMode: .fast,
            fileTypeFilter: .rawOnly,
            excludeCacheFiles: true,
            destinationCount: 1
        ),
        
        // Client Delivery - Final images for client
        BackupPreset(
            name: "Client Delivery",
            icon: "person.2",
            isBuiltIn: true,
            strategy: .mirror,
            schedule: .manual,
            performanceMode: .thorough,
            fileTypeFilter: FileTypeFilter(extensions: ["jpg", "jpeg", "tiff", "png"]),
            excludeCacheFiles: true,
            destinationCount: 1
        ),
        
        // Archive Master - Long-term archival
        BackupPreset(
            name: "Archive Master",
            icon: "lock.shield",
            isBuiltIn: true,
            strategy: .archive,
            schedule: .weekly,
            performanceMode: .thorough,
            fileTypeFilter: .allFiles,
            excludeCacheFiles: false,
            destinationCount: 3
        ),
        
        // Video Project - For video-heavy projects
        BackupPreset(
            name: "Video Project",
            icon: "video",
            isBuiltIn: true,
            strategy: .incremental,
            schedule: .manual,
            performanceMode: .fast,
            fileTypeFilter: .videosOnly,
            excludeCacheFiles: true,
            destinationCount: 2
        ),
        
        // Quick Mirror - Fast exact copy
        BackupPreset(
            name: "Quick Mirror",
            icon: "bolt",
            isBuiltIn: true,
            strategy: .mirror,
            schedule: .manual,
            performanceMode: .fast,
            fileTypeFilter: .allFiles,
            excludeCacheFiles: true,
            destinationCount: 1
        )
    ]
}

// MARK: - Preset Manager
@MainActor
class BackupPresetManager: ObservableObject {
    static let shared = BackupPresetManager()
    
    @Published var presets: [BackupPreset] = []
    @Published var selectedPreset: BackupPreset?
    
    private let presetKey = "com.imageintact.backupPresets"
    
    init() {
        loadPresets()
    }
    
    func loadPresets() {
        // Load custom presets from UserDefaults
        if let data = UserDefaults.standard.data(forKey: presetKey),
           let customPresets = try? JSONDecoder().decode([BackupPreset].self, from: data) {
            presets = BackupPreset.builtInPresets + customPresets
        } else {
            presets = BackupPreset.builtInPresets
        }
    }
    
    func savePresets() {
        // Only save custom presets
        let customPresets = presets.filter { !$0.isBuiltIn }
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: presetKey)
        }
    }
    
    func addPreset(_ preset: BackupPreset) {
        presets.append(preset)
        savePresets()
    }
    
    func updatePreset(_ preset: BackupPreset) {
        if let index = presets.firstIndex(where: { $0.id == preset.id }) {
            presets[index] = preset
            savePresets()
        }
    }
    
    func deletePreset(_ preset: BackupPreset) {
        guard !preset.isBuiltIn else { return }
        presets.removeAll { $0.id == preset.id }
        savePresets()
    }
    
    func applyPreset(_ preset: BackupPreset, to backupManager: BackupManager) {
        // Apply source bookmark if available (for custom presets)
        if let sourceBookmark = preset.sourceBookmark {
            if let url = BackupManager.loadBookmark(from: sourceBookmark) {
                backupManager.setSource(url)
                ApplicationLogger.shared.info("Restored source from preset: \(url.lastPathComponent)", category: .app)
            }
        }
        
        // Clear existing destinations and apply preset destinations
        backupManager.clearAllSelections()
        
        // Apply destination bookmarks if available
        if !preset.destinationBookmarks.isEmpty {
            for (index, bookmarkData) in preset.destinationBookmarks.enumerated() {
                if let data = bookmarkData,
                   let url = BackupManager.loadBookmark(from: data) {
                    if index == 0 {
                        // First destination - update the existing one
                        backupManager.setDestination(url, at: 0)
                    } else {
                        // Additional destinations - add new ones
                        backupManager.addDestination()
                        backupManager.setDestination(url, at: backupManager.destinationItems.count - 1)
                    }
                    ApplicationLogger.shared.info("Restored destination \(index + 1) from preset: \(url.lastPathComponent)", category: .app)
                }
            }
        } else {
            // Update destination count if no bookmarks but count specified
            while backupManager.destinationItems.count < preset.destinationCount {
                backupManager.addDestination()
            }
        }
        
        // Update backup manager settings
        backupManager.fileTypeFilter = preset.fileTypeFilter
        backupManager.excludeCacheFiles = preset.excludeCacheFiles
        
        // Update preferences
        PreferencesManager.shared.skipHiddenFiles = preset.skipHiddenFiles
        PreferencesManager.shared.preventSleepDuringBackup = preset.preventSleep
        PreferencesManager.shared.showNotificationOnComplete = preset.showNotification
        
        // Update use statistics
        var updatedPreset = preset
        updatedPreset.lastUsedDate = Date()
        updatedPreset.useCount += 1
        updatePreset(updatedPreset)
        
        selectedPreset = updatedPreset
        
        ApplicationLogger.shared.info("Applied preset: \(preset.name)", category: .app)
    }
    
    func currentConfigurationMatchesExistingPreset(backupManager: BackupManager) -> Bool {
        // Check if current configuration matches any existing preset
        for preset in presets {
            // Skip built-in presets as they don't have source/destination bookmarks
            if preset.isBuiltIn {
                continue
            }
            
            // Check if file type filter matches
            if preset.fileTypeFilter != backupManager.fileTypeFilter {
                continue
            }
            
            // Check if settings match
            if preset.excludeCacheFiles != backupManager.excludeCacheFiles ||
               preset.skipHiddenFiles != PreferencesManager.shared.skipHiddenFiles ||
               preset.preventSleep != PreferencesManager.shared.preventSleepDuringBackup ||
               preset.showNotification != PreferencesManager.shared.showNotificationOnComplete {
                continue
            }
            
            // Check if destination count matches
            let activeDestinations = backupManager.destinationItems.filter { $0.url != nil }
            if preset.destinationCount != activeDestinations.count {
                continue
            }
            
            // Check source bookmark
            if let sourceBookmark = preset.sourceBookmark,
               let savedURL = BackupManager.loadBookmark(from: sourceBookmark),
               let currentURL = backupManager.sourceURL {
                if savedURL.path != currentURL.path {
                    continue
                }
            } else if preset.sourceBookmark != nil || backupManager.sourceURL != nil {
                // One has source, the other doesn't
                continue
            }
            
            // Check destination bookmarks
            var destinationsMatch = true
            for (index, item) in activeDestinations.enumerated() {
                if index < preset.destinationBookmarks.count {
                    if let bookmarkData = preset.destinationBookmarks[index],
                       let savedURL = BackupManager.loadBookmark(from: bookmarkData),
                       let currentURL = item.url {
                        if savedURL.path != currentURL.path {
                            destinationsMatch = false
                            break
                        }
                    } else if preset.destinationBookmarks[index] != nil || item.url != nil {
                        // One has destination, the other doesn't
                        destinationsMatch = false
                        break
                    }
                }
            }
            
            if destinationsMatch {
                // Found a matching preset
                return true
            }
        }
        
        return false
    }
    
    func createPresetFromCurrent(name: String, backupManager: BackupManager) -> BackupPreset {
        // Create bookmarks for source and destinations
        var sourceBookmark: Data? = nil
        if let sourceURL = backupManager.sourceURL {
            sourceBookmark = BackupManager.createBookmark(for: sourceURL)
        }
        
        var destinationBookmarks: [Data?] = []
        for item in backupManager.destinationItems {
            if let url = item.url {
                destinationBookmarks.append(BackupManager.createBookmark(for: url))
            } else {
                destinationBookmarks.append(nil)
            }
        }
        
        return BackupPreset(
            name: name,
            icon: "star",
            isBuiltIn: false,
            strategy: .incremental, // Default for now
            schedule: .manual,       // Default for now
            performanceMode: .balanced, // Default for now
            fileTypeFilter: backupManager.fileTypeFilter,
            excludeCacheFiles: backupManager.excludeCacheFiles,
            skipHiddenFiles: PreferencesManager.shared.skipHiddenFiles,
            preventSleep: PreferencesManager.shared.preventSleepDuringBackup,
            showNotification: PreferencesManager.shared.showNotificationOnComplete,
            destinationCount: backupManager.destinationItems.count,
            preferredDriveUUIDs: [],
            sourceBookmark: sourceBookmark,
            destinationBookmarks: destinationBookmarks
        )
    }
}