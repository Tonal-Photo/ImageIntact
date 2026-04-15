//
//  PreferencesManager+Reset.swift
//  ImageIntact
//
//  `resetToDefaults` — clears every observable preference back to its registered default
//  and fires observation for every keypath. See the coverage test
//  `PreferencesObservationTests.testResetToDefaults_clearsEveryKeyAndFiresObservation`.
//

import Foundation

extension PreferencesManager {

    /// `@MainActor` because it mutates `recentOrganizationFolderNames` which is `@MainActor`.
    @MainActor
    func resetToDefaults() {
        withMutation(keyPath: \.defaultSourcePath) { defaults.removeObject(forKey: Keys.defaultSourcePath.rawValue) }
        withMutation(keyPath: \.defaultDestinationPath) { defaults.removeObject(forKey: Keys.defaultDestinationPath.rawValue) }
        withMutation(keyPath: \.restoreLastSession) { defaults.removeObject(forKey: Keys.restoreLastSession.rawValue) }
        withMutation(keyPath: \.showWelcomeOnLaunch) { defaults.removeObject(forKey: Keys.showWelcomeOnLaunch.rawValue) }
        withMutation(keyPath: \.excludeCacheFiles) { defaults.removeObject(forKey: Keys.excludeCacheFiles.rawValue) }
        withMutation(keyPath: \.skipHiddenFiles) { defaults.removeObject(forKey: Keys.skipHiddenFiles.rawValue) }
        withMutation(keyPath: \.includeSubdirectories) { defaults.removeObject(forKey: Keys.includeSubdirectories.rawValue) }
        withMutation(keyPath: \.trashSourceAfterBackup) { defaults.removeObject(forKey: Keys.trashSourceAfterBackup.rawValue) }
        withMutation(keyPath: \.defaultFileTypeFilter) { defaults.removeObject(forKey: Keys.defaultFileTypeFilter.rawValue) }
        withMutation(keyPath: \.visionProcessingPriority) { defaults.removeObject(forKey: Keys.visionProcessingPriority.rawValue) }
        withMutation(keyPath: \.preventSleepDuringBackup) { defaults.removeObject(forKey: Keys.preventSleepDuringBackup.rawValue) }
        withMutation(keyPath: \.showNotificationOnComplete) { defaults.removeObject(forKey: Keys.showNotificationOnComplete.rawValue) }
        withMutation(keyPath: \.networkCopyTimeout) { defaults.removeObject(forKey: Keys.networkCopyTimeout.rawValue) }
        withMutation(keyPath: \.networkCopySpeedLimit) { defaults.removeObject(forKey: Keys.networkCopySpeedLimit.rawValue) }
        withMutation(keyPath: \.useStreamCopyForNetwork) { defaults.removeObject(forKey: Keys.useStreamCopyForNetwork.rawValue) }
        withMutation(keyPath: \.networkBufferSize) { defaults.removeObject(forKey: Keys.networkBufferSize.rawValue) }
        withMutation(keyPath: \.networkRetryAttempts) { defaults.removeObject(forKey: Keys.networkRetryAttempts.rawValue) }
        withMutation(keyPath: \.minimumLogLevel) { defaults.removeObject(forKey: Keys.minimumLogLevel.rawValue) }
        withMutation(keyPath: \.enableConsoleLogging) { defaults.removeObject(forKey: Keys.enableConsoleLogging.rawValue) }
        withMutation(keyPath: \.enableDebugMenu) { defaults.removeObject(forKey: Keys.enableDebugMenu.rawValue) }
        withMutation(keyPath: \.operationalLogRetention) { defaults.removeObject(forKey: Keys.operationalLogRetention.rawValue) }
        withMutation(keyPath: \.anonymizePathsInExport) { defaults.removeObject(forKey: Keys.anonymizePathsInExport.rawValue) }
        withMutation(keyPath: \.enableSmartDuplicateDetection) { defaults.removeObject(forKey: Keys.enableSmartDuplicateDetection.rawValue) }
        withMutation(keyPath: \.showTechnicalDetails) { defaults.removeObject(forKey: Keys.showTechnicalDetails.rawValue) }
        withMutation(keyPath: \.showPreflightSummary) { defaults.removeObject(forKey: Keys.showPreflightSummary.rawValue) }
        withMutation(keyPath: \.confirmLargeBackups) { defaults.removeObject(forKey: Keys.confirmLargeBackups.rawValue) }
        withMutation(keyPath: \.largeBackupFileThreshold) { defaults.removeObject(forKey: Keys.largeBackupFileThreshold.rawValue) }
        withMutation(keyPath: \.largeBackupSizeThresholdGB) { defaults.removeObject(forKey: Keys.largeBackupSizeThresholdGB.rawValue) }
        withMutation(keyPath: \.skipLargeBackupWarning) { defaults.removeObject(forKey: Keys.skipLargeBackupWarning.rawValue) }
        withMutation(keyPath: \.lastUsedOrganizationFolderName) { defaults.removeObject(forKey: Keys.lastUsedOrganizationFolderName.rawValue) }
        withMutation(keyPath: \.recentOrganizationFolderNames) { defaults.removeObject(forKey: Keys.recentOrganizationFolderNames.rawValue) }
        withMutation(keyPath: \.enableVisionFramework) { _clearEnableVisionFrameworkOverride() }
    }
}
