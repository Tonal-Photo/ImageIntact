//
//  PreferencesManager+Support.swift
//  ImageIntact
//
//  Clamping helpers, path blocklist, folder-name sanitization, legacy JSON migration,
//  and derived helpers (cache-exclusion paths, hidden-file patterns, etc.).
//

import Foundation

extension PreferencesManager {

    // MARK: - Clamping helpers (single source of truth for every bound)

    static func clamped_networkCopyTimeout(_ v: Int) -> Int { max(1, min(v, 3600)) }
    static func clamped_networkCopySpeedLimit(_ v: Double) -> Double { max(0, min(v, 10_000)) }
    static func clamped_networkBufferSize(_ v: Int) -> Int { max(1, min(v, 16)) }
    static func clamped_networkRetryAttempts(_ v: Int) -> Int { max(0, min(v, 100)) }
    static func clamped_largeBackupFileThreshold(_ v: Int) -> Int { max(1, min(v, 10_000_000)) }
    static func clamped_largeBackupSizeThresholdGB(_ v: Double) -> Double { max(0, min(v, 100_000)) }
    static func clamped_operationalLogRetention(_ v: Int) -> Int { max(1, min(v, 3650)) }
    static func clamped_minimumLogLevel(_ v: Int) -> Int { max(0, min(v, 5)) }

    static let allowedFileTypeFilters: Set<String> = ["all", "photos", "raw", "videos"]
    static let allowedVisionPriorities: Set<String> = ["low", "normal", "high"]

    // MARK: - Path blocklist (setter-only defense for source/destination paths)

    private static let sensitivePathPatterns: [String] = [
        "/.ssh",
        "/library/keychains",
        "/library/application support/com.apple.tcc",
        "/library/cookies",
        "/private/etc",
        "/private/var/db",
        "/etc",
        "/var/db",
        "/.aws",
        "/.config/gcloud",
        "/.gnupg",
        "/.kube",
        "/.docker",
    ]

    /// Returns true if `path` points at (or inside) a directory on the sensitive-paths blocklist.
    /// No disk I/O — safe to call from UI context.
    static func isSensitivePath(_ path: String) -> Bool {
        guard path.hasPrefix("/") || path.hasPrefix("~") else { return true }
        if path.contains("://") { return true }
        if path.contains("\0") { return true }

        let expanded = (path as NSString).expandingTildeInPath
        let standardized = (expanded as NSString).standardizingPath
        let normalized = standardized.precomposedStringWithCanonicalMapping.lowercased()
        let padded = normalized.hasSuffix("/") ? normalized : normalized + "/"
        for pattern in sensitivePathPatterns {
            if padded.contains(pattern + "/") { return true }
        }
        return false
    }

    // MARK: - Folder-name sanitization (for recentOrganizationFolderNames)

    static func sanitizeFolderName(_ name: String) -> String? {
        let normalized = name.precomposedStringWithCanonicalMapping
        let trimmed = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.utf8.count <= 256 else { return nil }
        guard !trimmed.hasPrefix(".") else { return nil }
        guard !trimmed.hasPrefix("~") else { return nil }
        let pathSeparators: Set<Character> = ["/", "\\", "\0"]
        guard !trimmed.contains(where: { pathSeparators.contains($0) }) else { return nil }
        guard !trimmed.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return nil }
        return trimmed
    }

    // MARK: - Legacy JSON migration

    func migrateLegacyRecentFoldersJSONIfNeeded() {
        guard let legacyJSON = defaults.string(forKey: Self.legacyRecentOrganizationFolderNamesJSONKey) else { return }
        defer { defaults.removeObject(forKey: Self.legacyRecentOrganizationFolderNamesJSONKey) }

        guard defaults.stringArray(forKey: Keys.recentOrganizationFolderNames.rawValue) == nil else { return }

        guard legacyJSON.utf8.count <= Self.maxLegacyJSONBytes else {
            Self.migrationLogger.warning("Legacy recentOrganizationFolderNamesJSON exceeds 16KB; discarding without migration")
            return
        }
        guard let data = legacyJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data) else {
            Self.migrationLogger.warning("Legacy recentOrganizationFolderNamesJSON unparseable; discarding")
            return
        }
        let sanitized = decoded.compactMap { Self.sanitizeFolderName($0) }.prefix(Self.maxRecentFolderCount)
        defaults.set(Array(sanitized), forKey: Keys.recentOrganizationFolderNames.rawValue)
    }

    // MARK: - Derived helpers (unchanged from legacy behavior)

    func getDefaultFileTypeFilter() -> FileTypeFilter {
        switch defaultFileTypeFilter {
        case "photos": return .photosOnly
        case "raw":    return .rawOnly
        case "videos": return .videosOnly
        default:       return .allFiles
        }
    }

    func shouldWarnAboutVisionPerformance() -> Bool {
        !SystemCapabilities.shared.isAppleSilicon && enableVisionFramework
    }

    func getCacheExclusionPaths() -> [String] {
        guard excludeCacheFiles else { return [] }
        return [
            "Lightroom Catalog Previews.lrdata",
            "Lightroom Catalog Smart Previews.lrdata",
            "CaptureOne",
            "Capture One Catalog.cocatalogdb",
            ".pmarker",
            "DxO PhotoLab",
            "Photos Library.photoslibrary",
            ".BridgeCache",
            ".BridgeCacheT",
        ]
    }

    func getHiddenFilePatterns() -> [String] {
        guard skipHiddenFiles else { return [] }
        return [
            "._*",
            ".DS_Store",
            "Thumbs.db",
            ".Spotlight-V100",
            ".Trashes",
            ".fseventsd",
            ".TemporaryItems",
        ]
    }
}
