//
//  InMemoryPreferencesProvider.swift
//  ImageIntactTests
//
//  In-memory PreferencesProviding for tests. Holds values in plain stored
//  properties — never touches UserDefaults. Lets BackupManager tests run in
//  parallel without bleeding shared state across test methods.
//

import Foundation
@testable import ImageIntact

/// Test double for `PreferencesProviding`. Each instance owns its own storage,
/// so multiple BackupManager tests can hold independent preference state.
final class InMemoryPreferencesProvider: PreferencesProviding {
    var enableSmartDuplicateDetection: Bool
    var lastUsedOrganizationFolderName: String?
    var restoreLastSession: Bool
    var showPreflightSummary: Bool
    var excludeCacheFiles: Bool
    var skipHiddenFiles: Bool
    var showNotificationOnComplete: Bool
    var trashSourceAfterBackup: Bool
    var largeBackupFileThreshold: Int
    var largeBackupSizeThresholdGB: Double
    var confirmLargeBackups: Bool
    var skipLargeBackupWarning: Bool

    /// Names recorded via `addRecentOrganizationFolderName(_:)`, most-recent first.
    /// Exposed so tests can assert the recorded order without reaching into UserDefaults.
    private(set) var recentOrganizationFolderNames: [String] = []

    init(
        enableSmartDuplicateDetection: Bool = false,
        lastUsedOrganizationFolderName: String? = nil,
        restoreLastSession: Bool = true,
        showPreflightSummary: Bool = false,
        excludeCacheFiles: Bool = true,
        skipHiddenFiles: Bool = true,
        showNotificationOnComplete: Bool = true,
        trashSourceAfterBackup: Bool = false,
        largeBackupFileThreshold: Int = 1000,
        largeBackupSizeThresholdGB: Double = 10.0,
        confirmLargeBackups: Bool = true,
        skipLargeBackupWarning: Bool = false
    ) {
        self.enableSmartDuplicateDetection = enableSmartDuplicateDetection
        self.lastUsedOrganizationFolderName = lastUsedOrganizationFolderName
        self.restoreLastSession = restoreLastSession
        self.showPreflightSummary = showPreflightSummary
        self.excludeCacheFiles = excludeCacheFiles
        self.skipHiddenFiles = skipHiddenFiles
        self.showNotificationOnComplete = showNotificationOnComplete
        self.trashSourceAfterBackup = trashSourceAfterBackup
        self.largeBackupFileThreshold = largeBackupFileThreshold
        self.largeBackupSizeThresholdGB = largeBackupSizeThresholdGB
        self.confirmLargeBackups = confirmLargeBackups
        self.skipLargeBackupWarning = skipLargeBackupWarning
    }

    func addRecentOrganizationFolderName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        recentOrganizationFolderNames.removeAll { $0 == trimmed }
        recentOrganizationFolderNames.insert(trimmed, at: 0)

        if recentOrganizationFolderNames.count > 10 {
            recentOrganizationFolderNames = Array(recentOrganizationFolderNames.prefix(10))
        }
    }
}
