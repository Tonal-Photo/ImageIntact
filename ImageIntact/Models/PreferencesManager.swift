//
//  PreferencesManager.swift
//  ImageIntact
//
//  Manages application preferences and settings.
//  See docs/design/2026-04-14-preferences-observable-refactor.md for the design rationale.
//
//  This file: `@Observable` class declaration, key enum, shared instance, init,
//  and the 31 public observable preference properties. Supporting code is split across:
//    - PreferencesManager+Accessors.swift  — typed getter/setter helpers
//    - PreferencesManager+Reset.swift      — resetToDefaults
//    - PreferencesManager+Support.swift    — clamping, path blocklist, sanitizers, migration
//

import Foundation
import OSLog
import Observation
import os

@Observable
final class PreferencesManager {

    /// Every observable preference's UserDefaults key. `CaseIterable` drives the reset coverage test.
    enum Keys: String, CaseIterable {
        case defaultSourcePath
        case defaultDestinationPath
        case restoreLastSession
        case showWelcomeOnLaunch
        case excludeCacheFiles
        case skipHiddenFiles
        case includeSubdirectories
        case trashSourceAfterBackup
        case defaultFileTypeFilter
        case enableVisionFramework
        case visionProcessingPriority
        case preventSleepDuringBackup
        case showNotificationOnComplete
        case networkCopyTimeout
        case networkCopySpeedLimit
        case useStreamCopyForNetwork
        case networkBufferSize
        case networkRetryAttempts
        case minimumLogLevel
        case enableConsoleLogging
        case enableDebugMenu
        case operationalLogRetention
        case anonymizePathsInExport
        case enableSmartDuplicateDetection
        case showTechnicalDetails
        case showPreflightSummary
        case confirmLargeBackups
        case largeBackupFileThreshold
        case largeBackupSizeThresholdGB
        case skipLargeBackupWarning
        case lastUsedOrganizationFolderName
        case recentOrganizationFolderNames
    }

    /// Legacy JSON storage key retired by the observable refactor.
    static let legacyRecentOrganizationFolderNamesJSONKey = "recentOrganizationFolderNamesJSON"

    /// Migration logging uses a direct os.Logger to avoid a circular dependency at init time
    /// (ApplicationLogger filters by `PreferencesManager.shared.minimumLogLevel`).
    @ObservationIgnored
    static let migrationLogger = Logger(subsystem: "com.imageintact.ImageIntact", category: "preferences-migration")

    #if DEBUG
    @ObservationIgnored
    private static let sharedLock = OSAllocatedUnfairLock(initialState: PreferencesManager(defaults: .standard))
    static var shared: PreferencesManager {
        sharedLock.withLock { $0 }
    }
    static func _replaceSharedForTesting(_ replacement: PreferencesManager) {
        sharedLock.withLock { $0 = replacement }
    }
    static func _restoreSharedAfterTesting() {
        sharedLock.withLock { $0 = PreferencesManager(defaults: .standard) }
    }

    /// Test-only override for the Apple-Silicon default branch of `enableVisionFramework`.
    /// Tests must restore to `nil` in tearDown.
    static var _isAppleSiliconOverride: Bool? = nil
    #else
    nonisolated(unsafe) static let shared = PreferencesManager(defaults: .standard)
    #endif

    @ObservationIgnored
    let defaults: UserDefaults

    /// Single source of truth for non-zero/non-false/non-empty defaults.
    static let registeredDefaults: [String: Any] = [
        Keys.restoreLastSession.rawValue: true,
        Keys.showWelcomeOnLaunch.rawValue: true,
        Keys.excludeCacheFiles.rawValue: true,
        Keys.skipHiddenFiles.rawValue: true,
        Keys.includeSubdirectories.rawValue: true,
        Keys.confirmLargeBackups.rawValue: true,
        Keys.preventSleepDuringBackup.rawValue: true,
        Keys.showNotificationOnComplete.rawValue: true,
        Keys.useStreamCopyForNetwork.rawValue: true,
        Keys.enableConsoleLogging.rawValue: true,
        Keys.anonymizePathsInExport.rawValue: true,
        Keys.largeBackupFileThreshold.rawValue: 1000,
        Keys.networkCopyTimeout.rawValue: 90,
        Keys.networkBufferSize.rawValue: 1,
        Keys.networkRetryAttempts.rawValue: 3,
        Keys.minimumLogLevel.rawValue: 1,
        Keys.operationalLogRetention.rawValue: 30,
        Keys.largeBackupSizeThresholdGB.rawValue: 10.0,
        Keys.defaultFileTypeFilter.rawValue: "all",
        Keys.visionProcessingPriority.rawValue: "normal",
    ]

    init(defaults: UserDefaults) {
        self.defaults = defaults
        self.defaults.register(defaults: Self.registeredDefaults)
        migrateLegacyRecentFoldersJSONIfNeeded()
    }

    private var isAppleSiliconForDefault: Bool {
        #if DEBUG
        if let override = Self._isAppleSiliconOverride { return override }
        #endif
        return SystemCapabilities.shared.isAppleSilicon
    }

    /// Private raw storage for Vision override — not observable. Public `enableVisionFramework`
    /// wraps this and owns the observation keypath.
    @ObservationIgnored
    private var enableVisionFrameworkStorage: Bool? {
        get { (defaults.object(forKey: Keys.enableVisionFramework.rawValue) as? NSNumber)?.boolValue }
        set {
            if let v = newValue { defaults.set(v, forKey: Keys.enableVisionFramework.rawValue) }
            else { defaults.removeObject(forKey: Keys.enableVisionFramework.rawValue) }
        }
    }

    /// `resetToDefaults` mutates this via `withMutation(\.enableVisionFramework) { enableVisionFrameworkStorage = nil }`,
    /// which requires same-type access. Declared `internal` so the Reset extension can reach it.
    func _clearEnableVisionFrameworkOverride() {
        enableVisionFrameworkStorage = nil
    }

    // MARK: - General Preferences

    var defaultSourcePath: String {
        get { getString(key: Keys.defaultSourcePath.rawValue, default: "", keyPath: \.defaultSourcePath) }
        set {
            guard !Self.isSensitivePath(newValue) else {
                Self.migrationLogger.warning("Rejected write to defaultSourcePath: sensitive-path blocklist")
                return
            }
            setString(newValue, key: Keys.defaultSourcePath.rawValue, keyPath: \.defaultSourcePath)
        }
    }

    var defaultDestinationPath: String {
        get { getString(key: Keys.defaultDestinationPath.rawValue, default: "", keyPath: \.defaultDestinationPath) }
        set {
            guard !Self.isSensitivePath(newValue) else {
                Self.migrationLogger.warning("Rejected write to defaultDestinationPath: sensitive-path blocklist")
                return
            }
            setString(newValue, key: Keys.defaultDestinationPath.rawValue, keyPath: \.defaultDestinationPath)
        }
    }

    var restoreLastSession: Bool {
        get { getBool(key: Keys.restoreLastSession.rawValue, default: true, keyPath: \.restoreLastSession) }
        set { setBool(newValue, key: Keys.restoreLastSession.rawValue, keyPath: \.restoreLastSession) }
    }

    var showWelcomeOnLaunch: Bool {
        get { getBool(key: Keys.showWelcomeOnLaunch.rawValue, default: true, keyPath: \.showWelcomeOnLaunch) }
        set { setBool(newValue, key: Keys.showWelcomeOnLaunch.rawValue, keyPath: \.showWelcomeOnLaunch) }
    }

    // MARK: - File Handling

    var excludeCacheFiles: Bool {
        get { getBool(key: Keys.excludeCacheFiles.rawValue, default: true, keyPath: \.excludeCacheFiles) }
        set { setBool(newValue, key: Keys.excludeCacheFiles.rawValue, keyPath: \.excludeCacheFiles) }
    }

    var skipHiddenFiles: Bool {
        get { getBool(key: Keys.skipHiddenFiles.rawValue, default: true, keyPath: \.skipHiddenFiles) }
        set { setBool(newValue, key: Keys.skipHiddenFiles.rawValue, keyPath: \.skipHiddenFiles) }
    }

    var includeSubdirectories: Bool {
        get { getBool(key: Keys.includeSubdirectories.rawValue, default: true, keyPath: \.includeSubdirectories) }
        set { setBool(newValue, key: Keys.includeSubdirectories.rawValue, keyPath: \.includeSubdirectories) }
    }

    var trashSourceAfterBackup: Bool {
        get { getBool(key: Keys.trashSourceAfterBackup.rawValue, default: false, keyPath: \.trashSourceAfterBackup) }
        set { setBool(newValue, key: Keys.trashSourceAfterBackup.rawValue, keyPath: \.trashSourceAfterBackup) }
    }

    var defaultFileTypeFilter: String {
        get {
            let raw = getString(key: Keys.defaultFileTypeFilter.rawValue, default: "all", keyPath: \.defaultFileTypeFilter)
            return Self.allowedFileTypeFilters.contains(raw) ? raw : "all"
        }
        set {
            let allowed = Self.allowedFileTypeFilters.contains(newValue) ? newValue : "all"
            setString(allowed, key: Keys.defaultFileTypeFilter.rawValue, keyPath: \.defaultFileTypeFilter)
        }
    }

    // MARK: - Backup Confirmations

    var confirmLargeBackups: Bool {
        get { getBool(key: Keys.confirmLargeBackups.rawValue, default: true, keyPath: \.confirmLargeBackups) }
        set { setBool(newValue, key: Keys.confirmLargeBackups.rawValue, keyPath: \.confirmLargeBackups) }
    }

    var largeBackupFileThreshold: Int {
        get { Self.clamped_largeBackupFileThreshold(getInt(key: Keys.largeBackupFileThreshold.rawValue, default: 1000, keyPath: \.largeBackupFileThreshold)) }
        set { setInt(Self.clamped_largeBackupFileThreshold(newValue), key: Keys.largeBackupFileThreshold.rawValue, keyPath: \.largeBackupFileThreshold) }
    }

    var largeBackupSizeThresholdGB: Double {
        get { Self.clamped_largeBackupSizeThresholdGB(getDouble(key: Keys.largeBackupSizeThresholdGB.rawValue, default: 10.0, keyPath: \.largeBackupSizeThresholdGB)) }
        set { setDouble(Self.clamped_largeBackupSizeThresholdGB(newValue), key: Keys.largeBackupSizeThresholdGB.rawValue, keyPath: \.largeBackupSizeThresholdGB) }
    }

    var skipLargeBackupWarning: Bool {
        get { getBool(key: Keys.skipLargeBackupWarning.rawValue, default: false, keyPath: \.skipLargeBackupWarning) }
        set { setBool(newValue, key: Keys.skipLargeBackupWarning.rawValue, keyPath: \.skipLargeBackupWarning) }
    }

    // MARK: - Performance

    var enableVisionFramework: Bool {
        get {
            access(keyPath: \.enableVisionFramework)
            return enableVisionFrameworkStorage ?? isAppleSiliconForDefault
        }
        set {
            let oldEffective = enableVisionFrameworkStorage ?? isAppleSiliconForDefault
            guard oldEffective != newValue else { return }
            withMutation(keyPath: \.enableVisionFramework) {
                enableVisionFrameworkStorage = newValue
            }
        }
    }

    var visionProcessingPriority: String {
        get {
            let raw = getString(key: Keys.visionProcessingPriority.rawValue, default: "normal", keyPath: \.visionProcessingPriority)
            return Self.allowedVisionPriorities.contains(raw) ? raw : "normal"
        }
        set {
            let allowed = Self.allowedVisionPriorities.contains(newValue) ? newValue : "normal"
            setString(allowed, key: Keys.visionProcessingPriority.rawValue, keyPath: \.visionProcessingPriority)
        }
    }

    var preventSleepDuringBackup: Bool {
        get { getBool(key: Keys.preventSleepDuringBackup.rawValue, default: true, keyPath: \.preventSleepDuringBackup) }
        set { setBool(newValue, key: Keys.preventSleepDuringBackup.rawValue, keyPath: \.preventSleepDuringBackup) }
    }

    var showNotificationOnComplete: Bool {
        get { getBool(key: Keys.showNotificationOnComplete.rawValue, default: true, keyPath: \.showNotificationOnComplete) }
        set { setBool(newValue, key: Keys.showNotificationOnComplete.rawValue, keyPath: \.showNotificationOnComplete) }
    }

    // MARK: - Network Performance

    var networkCopyTimeout: Int {
        get { Self.clamped_networkCopyTimeout(getInt(key: Keys.networkCopyTimeout.rawValue, default: 90, keyPath: \.networkCopyTimeout)) }
        set { setInt(Self.clamped_networkCopyTimeout(newValue), key: Keys.networkCopyTimeout.rawValue, keyPath: \.networkCopyTimeout) }
    }

    var networkCopySpeedLimit: Double {
        get { Self.clamped_networkCopySpeedLimit(getDouble(key: Keys.networkCopySpeedLimit.rawValue, default: 0, keyPath: \.networkCopySpeedLimit)) }
        set { setDouble(Self.clamped_networkCopySpeedLimit(newValue), key: Keys.networkCopySpeedLimit.rawValue, keyPath: \.networkCopySpeedLimit) }
    }

    var useStreamCopyForNetwork: Bool {
        get { getBool(key: Keys.useStreamCopyForNetwork.rawValue, default: true, keyPath: \.useStreamCopyForNetwork) }
        set { setBool(newValue, key: Keys.useStreamCopyForNetwork.rawValue, keyPath: \.useStreamCopyForNetwork) }
    }

    var networkBufferSize: Int {
        get { Self.clamped_networkBufferSize(getInt(key: Keys.networkBufferSize.rawValue, default: 1, keyPath: \.networkBufferSize)) }
        set { setInt(Self.clamped_networkBufferSize(newValue), key: Keys.networkBufferSize.rawValue, keyPath: \.networkBufferSize) }
    }

    var networkRetryAttempts: Int {
        get { Self.clamped_networkRetryAttempts(getInt(key: Keys.networkRetryAttempts.rawValue, default: 3, keyPath: \.networkRetryAttempts)) }
        set { setInt(Self.clamped_networkRetryAttempts(newValue), key: Keys.networkRetryAttempts.rawValue, keyPath: \.networkRetryAttempts) }
    }

    // MARK: - Logging & Privacy

    var minimumLogLevel: Int {
        get { Self.clamped_minimumLogLevel(getInt(key: Keys.minimumLogLevel.rawValue, default: 1, keyPath: \.minimumLogLevel)) }
        set { setInt(Self.clamped_minimumLogLevel(newValue), key: Keys.minimumLogLevel.rawValue, keyPath: \.minimumLogLevel) }
    }

    var enableConsoleLogging: Bool {
        get { getBool(key: Keys.enableConsoleLogging.rawValue, default: true, keyPath: \.enableConsoleLogging) }
        set { setBool(newValue, key: Keys.enableConsoleLogging.rawValue, keyPath: \.enableConsoleLogging) }
    }

    var enableDebugMenu: Bool {
        get { getBool(key: Keys.enableDebugMenu.rawValue, default: false, keyPath: \.enableDebugMenu) }
        set { setBool(newValue, key: Keys.enableDebugMenu.rawValue, keyPath: \.enableDebugMenu) }
    }

    var operationalLogRetention: Int {
        get { Self.clamped_operationalLogRetention(getInt(key: Keys.operationalLogRetention.rawValue, default: 30, keyPath: \.operationalLogRetention)) }
        set { setInt(Self.clamped_operationalLogRetention(newValue), key: Keys.operationalLogRetention.rawValue, keyPath: \.operationalLogRetention) }
    }

    var anonymizePathsInExport: Bool {
        get { getBool(key: Keys.anonymizePathsInExport.rawValue, default: true, keyPath: \.anonymizePathsInExport) }
        set { setBool(newValue, key: Keys.anonymizePathsInExport.rawValue, keyPath: \.anonymizePathsInExport) }
    }

    // MARK: - Advanced

    var enableSmartDuplicateDetection: Bool {
        get { getBool(key: Keys.enableSmartDuplicateDetection.rawValue, default: false, keyPath: \.enableSmartDuplicateDetection) }
        set { setBool(newValue, key: Keys.enableSmartDuplicateDetection.rawValue, keyPath: \.enableSmartDuplicateDetection) }
    }

    var showTechnicalDetails: Bool {
        get { getBool(key: Keys.showTechnicalDetails.rawValue, default: false, keyPath: \.showTechnicalDetails) }
        set { setBool(newValue, key: Keys.showTechnicalDetails.rawValue, keyPath: \.showTechnicalDetails) }
    }

    var showPreflightSummary: Bool {
        get { getBool(key: Keys.showPreflightSummary.rawValue, default: false, keyPath: \.showPreflightSummary) }
        set { setBool(newValue, key: Keys.showPreflightSummary.rawValue, keyPath: \.showPreflightSummary) }
    }

    // MARK: - Backup Organization

    var lastUsedOrganizationFolderName: String? {
        get { getOptionalString(key: Keys.lastUsedOrganizationFolderName.rawValue, keyPath: \.lastUsedOrganizationFolderName) }
        set { setOptionalString(newValue, key: Keys.lastUsedOrganizationFolderName.rawValue, keyPath: \.lastUsedOrganizationFolderName) }
    }

    static let maxRecentFolderCount = 10
    static let maxLegacyJSONBytes = 16_384

    /// `@MainActor` at the property boundary: serializes getter, setter, and the RMW helper
    /// `addRecentOrganizationFolderName` through Swift's concurrency model.
    @MainActor
    var recentOrganizationFolderNames: [String] {
        get {
            access(keyPath: \.recentOrganizationFolderNames)
            let raw = defaults.stringArray(forKey: Keys.recentOrganizationFolderNames.rawValue) ?? []
            return Array(raw.compactMap { Self.sanitizeFolderName($0) }.prefix(Self.maxRecentFolderCount))
        }
        set {
            let sanitized = Array(newValue.compactMap { Self.sanitizeFolderName($0) }.prefix(Self.maxRecentFolderCount))
            let oldValue = defaults.stringArray(forKey: Keys.recentOrganizationFolderNames.rawValue) ?? []
            guard oldValue != sanitized else { return }
            withMutation(keyPath: \.recentOrganizationFolderNames) {
                defaults.set(sanitized, forKey: Keys.recentOrganizationFolderNames.rawValue)
            }
        }
    }

    @MainActor
    @discardableResult
    func addRecentOrganizationFolderName(_ name: String) -> Bool {
        guard let sanitized = Self.sanitizeFolderName(name) else { return false }
        var names = recentOrganizationFolderNames
        names.removeAll { $0 == sanitized }
        names.insert(sanitized, at: 0)
        if names.count > Self.maxRecentFolderCount {
            names = Array(names.prefix(Self.maxRecentFolderCount))
        }
        recentOrganizationFolderNames = names
        return true
    }
}
