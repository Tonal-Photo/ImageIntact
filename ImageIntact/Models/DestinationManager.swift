//
//  DestinationManager.swift
//  ImageIntact
//
//  Owns all destination-folder state: items, drive info, bookmarks, validation,
//  and time estimation. Extracted from BackupManager to reduce its scope.
//

import Foundation

// MARK: - Destination Item

/// A single destination slot. URL is immutable — changing the URL creates a new item
/// with a new UUID, which makes async race condition guards bulletproof.
struct DestinationItem: Identifiable {
    let id = UUID()
    let url: URL?

    init(url: URL? = nil) {
        self.url = url
    }
}

// MARK: - Source Estimate State

/// Lightweight snapshot of source state needed by getDestinationEstimate.
/// Avoids coupling DestinationManager to SourceManager.
struct SourceEstimateState {
    let sourceURL: URL?
    let sourceTotalBytes: Int64
    let sourceFileTypes: [ImageFileType: Int]
    let isScanning: Bool
}

// MARK: - Destination Error

/// Errors thrown by setDestination — caller handles UI (alerts) and orchestration.
/// No state is mutated before any throw.
enum DestinationError: Error {
    case sameAsSource
    case duplicateDestination(existingIndex: Int)
    case indexOutOfRange
    case sourceTagConflict(URL)
}

// MARK: - Destination Manager

@MainActor
@Observable
class DestinationManager {

    // MARK: - State (private(set) — mutations only through methods)

    private(set) var destinationItems: [DestinationItem] = []
    private(set) var destinationDriveInfo: [UUID: DriveAnalyzer.DriveInfo] = [:]

    /// Computed from destinationItems — no parallel array to keep in sync.
    var destinationURLs: [URL?] { destinationItems.map { $0.url } }

    // MARK: - Dependencies (injected)

    private let fileOperations: FileOperationsProtocol
    private let driveAnalyzer: DriveAnalyzerProtocol
    private let diskSpaceChecker: DiskSpaceProtocol

    // MARK: - Initialization

    init(
        fileOperations: FileOperationsProtocol,
        driveAnalyzer: DriveAnalyzerProtocol,
        diskSpaceChecker: DiskSpaceProtocol
    ) {
        self.fileOperations = fileOperations
        self.driveAnalyzer = driveAnalyzer
        self.diskSpaceChecker = diskSpaceChecker
    }

    // MARK: - Private Helpers

    /// Normalizes a URL to a canonical path for comparison, handling trailing slashes.
    /// Uses standardizedFileURL only (no disk I/O) — resolves `.` and `..` but not symlinks.
    private func resolvedPath(_ url: URL) -> String {
        var path = url.standardizedFileURL.path
        if path.hasSuffix("/"), path != "/" { path = String(path.dropLast()) }
        return path
    }

    private func makeUnavailableDriveInfo(at url: URL) -> DriveAnalyzer.DriveInfo {
        DriveAnalyzer.DriveInfo(
            mountPath: url, connectionType: .unknown, isSSD: false,
            deviceName: url.lastPathComponent, protocolDetails: "Not Connected",
            estimatedWriteSpeed: 0, estimatedReadSpeed: 0,
            volumeUUID: nil, hardwareSerial: nil, deviceModel: nil,
            totalCapacity: 0, freeSpace: 0, driveType: .generic
        )
    }

    // MARK: - Test Support (internal — accessible via @testable import)

    /// Inject drive info for a specific item. Used by tests to set up state
    /// without triggering async drive analysis.
    func setDriveInfo(_ info: DriveAnalyzer.DriveInfo, for itemID: UUID) {
        destinationDriveInfo[itemID] = info
    }

    // MARK: - Slot Management

    func initializeEmpty() {
        destinationItems = [DestinationItem(url: nil)]
    }

    /// Adds a new empty destination slot (max 4).
    func addDestination() {
        if destinationItems.count < 4 {
            destinationItems.append(DestinationItem(url: nil))
        }
    }

    // MARK: - Core Mutations

    /// Sets a destination URL at the given index.
    /// Throws DestinationError on validation failure — no state is mutated before any throw.
    func setDestination(
        _ url: URL, at index: Int,
        sourceURL: URL?,
        hasSourceTag: Bool,
        totalBytesToCopy: Int64 = 0
    ) throws {
        guard index < destinationItems.count else {
            throw DestinationError.indexOutOfRange
        }

        // Same-URL reselection at same index is a no-op
        if let existing = destinationItems[index].url,
           resolvedPath(existing) == resolvedPath(url)
        {
            return
        }

        // Check: same as source?
        if let source = sourceURL, resolvedPath(source) == resolvedPath(url) {
            throw DestinationError.sameAsSource
        }

        // Check: duplicate destination?
        let destPath = resolvedPath(url)
        for (i, item) in destinationItems.enumerated() {
            if i != index, let existingURL = item.url,
               resolvedPath(existingURL) == destPath
            {
                throw DestinationError.duplicateDestination(existingIndex: i)
            }
        }

        // Check: source-tagged folder?
        if hasSourceTag {
            throw DestinationError.sourceTagConflict(url)
        }

        // --- All validation passed. Mutate state. ---

        // Remove old UUID from driveInfo before replacement
        let oldID = destinationItems[index].id
        destinationDriveInfo.removeValue(forKey: oldID)

        // Create new item (immutable url = new UUID)
        let newItem = DestinationItem(url: url)
        destinationItems[index] = newItem

        // Save bookmark
        if index < BookmarkManager.destinationKeys.count {
            BookmarkManager.saveBookmark(url: url, key: BookmarkManager.destinationKeys[index])
        }

        // Async drive analysis + disk space check (detached to avoid main thread I/O)
        let itemID = newItem.id
        let fileOps = fileOperations
        let analyzer = driveAnalyzer
        let checker = diskSpaceChecker
        Task.detached { [weak self] in
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            let isAccessible = fileOps.fileExists(at: url)

            // Disk space check if we know the backup size
            if totalBytesToCopy > 0 {
                let spaceCheck = checker.checkDestinationSpace(
                    destination: url,
                    requiredBytes: totalBytesToCopy,
                    additionalBuffer: 100_000_000
                )
                if let error = spaceCheck.error {
                    await MainActor.run {
                        logError("Destination space issue: \(error)")
                    }
                } else if let warning = spaceCheck.warning {
                    await MainActor.run {
                        logWarning("Destination space warning: \(warning)")
                    }
                }
            }

            if isAccessible {
                if let driveInfo = analyzer.analyzeDrive(at: url) {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        guard self.destinationItems.contains(where: { $0.id == itemID }) else { return }
                        self.destinationDriveInfo[itemID] = driveInfo
                        logInfo(
                            "Drive analyzed: \(driveInfo.deviceName) - \(driveInfo.connectionType.displayName) - Write: \(driveInfo.estimatedWriteSpeed) MB/s",
                            category: .performance
                        )
                    }
                }
            } else {
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    guard self.destinationItems.contains(where: { $0.id == itemID }) else { return }
                    self.destinationDriveInfo[itemID] = self.makeUnavailableDriveInfo(at: url)
                    logInfo("Destination not accessible: \(url.lastPathComponent)")
                }
            }
        }
    }

    /// Clears the destination at the given index (sets URL to nil).
    func clearDestination(at index: Int) {
        guard index < destinationItems.count else { return }

        let oldID = destinationItems[index].id
        destinationDriveInfo.removeValue(forKey: oldID)

        destinationItems[index] = DestinationItem(url: nil)

        if index < BookmarkManager.destinationKeys.count {
            UserDefaults.standard.removeObject(forKey: BookmarkManager.destinationKeys[index])
        }
    }

    /// Removes the destination at the given index. If only one remains, clears it instead.
    func removeDestination(at index: Int) {
        guard index < destinationItems.count else { return }

        // Don't remove if it's the last one — clear instead
        guard destinationItems.count > 1 else {
            let oldID = destinationItems[0].id
            destinationDriveInfo.removeValue(forKey: oldID)
            destinationItems[0] = DestinationItem(url: nil)
            UserDefaults.standard.removeObject(forKey: BookmarkManager.destinationKeys[0])
            return
        }

        // Remove drive info for this item
        let oldID = destinationItems[index].id
        destinationDriveInfo.removeValue(forKey: oldID)

        // Remove from array
        destinationItems.remove(at: index)

        // Re-index bookmarks
        for (i, item) in destinationItems.enumerated() {
            if i < BookmarkManager.destinationKeys.count {
                if let url = item.url {
                    BookmarkManager.saveBookmark(url: url, key: BookmarkManager.destinationKeys[i])
                } else {
                    UserDefaults.standard.removeObject(forKey: BookmarkManager.destinationKeys[i])
                }
            }
        }

        // Clear trailing keys
        for i in destinationItems.count..<BookmarkManager.destinationKeys.count {
            UserDefaults.standard.removeObject(forKey: BookmarkManager.destinationKeys[i])
        }

        logInfo("Removed destination at index \(index), new count: \(destinationItems.count)")
    }

    // MARK: - Estimation

    func getDestinationEstimate(at index: Int, sourceState: SourceEstimateState) -> String? {
        guard index < destinationItems.count else { return nil }
        let itemID = destinationItems[index].id
        guard let driveInfo = destinationDriveInfo[itemID] else { return nil }

        // Unavailable destination
        if driveInfo.estimatedWriteSpeed == 0, driveInfo.protocolDetails == "Not Connected" {
            return "\u{26A0}\u{FE0F} Destination not accessible (drive may be disconnected)"
        }

        // Network drives: too many variables
        if driveInfo.connectionType == .network {
            var freeSpaceInfo = ""
            if driveInfo.freeSpace > 0 {
                let formatter = ByteCountFormatter()
                formatter.countStyle = .file
                freeSpaceInfo = " \u{2022} \(formatter.string(fromByteCount: driveInfo.freeSpace)) free"
            }
            return "Network Drive\(freeSpaceInfo) \u{2022} Too many variables to estimate time"
        }

        // Calculate total bytes
        var totalBytes: Int64 = 0
        if sourceState.sourceTotalBytes > 0 {
            totalBytes = sourceState.sourceTotalBytes
        } else if !sourceState.sourceFileTypes.isEmpty {
            let totalFiles = sourceState.sourceFileTypes.values.reduce(0, +)
            totalBytes = Int64(totalFiles) * 500_000
        } else if sourceState.isScanning {
            return "Scanning files..."
        } else if sourceState.sourceURL != nil {
            return "Analyzing source..."
        } else {
            return nil
        }

        guard totalBytes > 0 else { return nil }

        // Adjust for multiple simultaneous destinations
        let activeDestinations = destinationItems.compactMap { $0.url }.count
        var adjustedTotalBytes = totalBytes
        if activeDestinations > 1 {
            let overhead = 1.0 + (Double(activeDestinations - 1) * 0.3)
            adjustedTotalBytes = Int64(Double(totalBytes) * overhead)
        }

        let estimate = driveInfo.formattedEstimate(totalBytes: adjustedTotalBytes)
        let totalGB = Double(totalBytes) / (1000 * 1000 * 1000)
        let sizeStr = String(format: "%.2f GB", totalGB)

        // Free space from pre-computed drive info (no synchronous disk I/O)
        var freeSpaceInfo = ""
        if driveInfo.freeSpace > 0 {
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            freeSpaceInfo = " \u{2022} \(formatter.string(fromByteCount: driveInfo.freeSpace)) free"
        }

        let driveType = driveInfo.isSSD ? "SSD" : "HDD"
        return "\(driveInfo.connectionType.displayName) \u{2022} \(driveType) \u{2022} \(sizeStr)\(freeSpaceInfo) \u{2022} \(estimate)"
    }

    // MARK: - Session Persistence

    /// Load destinations from saved bookmarks. Does not analyze drives —
    /// call `validateAndAnalyzeDestinations()` after to perform security-scoped analysis.
    func loadFromSession() {
        let loadedURLs = BookmarkManager.loadDestinationBookmarks()
        destinationItems = loadedURLs.map { DestinationItem(url: $0) }
    }

    // MARK: - UI Test Support

    #if DEBUG
    func loadUITestDestinations() {
        logInfo("Loading UI test destination paths")

        var testDestinations: [URL?] = []

        if let path = UserDefaults.standard.string(forKey: "TestDest1Path") {
            testDestinations.append(URL(fileURLWithPath: path))
            logInfo("UI Test: Added destination 1: \(path)")
        }

        if let path = UserDefaults.standard.string(forKey: "TestDest2Path") {
            testDestinations.append(URL(fileURLWithPath: path))
            logInfo("UI Test: Added destination 2: \(path)")
        }

        if !testDestinations.isEmpty {
            destinationItems = testDestinations.map { DestinationItem(url: $0) }
        } else {
            destinationItems = [DestinationItem(url: nil)]
        }

        UserDefaults.standard.removeObject(forKey: "TestDest1Path")
        UserDefaults.standard.removeObject(forKey: "TestDest2Path")
    }
    #endif

    // MARK: - Validation

    /// Validate and analyze all loaded destinations (detached to avoid main thread I/O).
    func validateAndAnalyzeDestinations() {
        let fileOps = fileOperations
        let analyzer = driveAnalyzer
        for (index, item) in destinationItems.enumerated() {
            guard let url = item.url else { continue }
            let itemID = item.id
            Task.detached { [weak self] in
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }

                if !accessing {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        logWarning("Destination bookmark at index \(index) is invalid, clearing...")
                        guard let currentIndex = self.destinationItems.firstIndex(where: { $0.id == itemID }) else { return }
                        self.destinationDriveInfo.removeValue(forKey: itemID)
                        self.destinationItems[currentIndex] = DestinationItem(url: nil)
                        if currentIndex < BookmarkManager.destinationKeys.count {
                            UserDefaults.standard.removeObject(forKey: BookmarkManager.destinationKeys[currentIndex])
                        }
                    }
                    return
                }

                let isAccessible = fileOps.fileExists(at: url)
                if isAccessible {
                    if let driveInfo = analyzer.analyzeDrive(at: url) {
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            guard self.destinationItems.contains(where: { $0.id == itemID }) else { return }
                            self.destinationDriveInfo[itemID] = driveInfo
                            logInfo(
                                "Initial drive analysis: \(driveInfo.deviceName) - \(driveInfo.connectionType.displayName)",
                                category: .performance
                            )
                        }
                    }
                } else {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        guard self.destinationItems.contains(where: { $0.id == itemID }) else { return }
                        logInfo("Destination not accessible: \(url.lastPathComponent)")
                        self.destinationDriveInfo[itemID] = self.makeUnavailableDriveInfo(at: url)
                    }
                }
            }
        }
    }

    // MARK: - Bulk Operations

    /// Clear all destinations and reset to a single empty slot.
    func clearAll() {
        for item in destinationItems {
            destinationDriveInfo.removeValue(forKey: item.id)
        }
        for key in BookmarkManager.destinationKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        destinationItems = [DestinationItem(url: nil)]
    }
}
