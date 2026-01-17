import Foundation

/// Handles building file manifests for backup operations
/// Extracted from BackupManager to follow Single Responsibility Principle
actor ManifestBuilder {
    // MARK: - Properties

    /// Callback for status updates
    private var onStatusUpdate: ((String) -> Void)?

    /// Callback for failed files
    private var onFileError: ((String, String, String) -> Void)?

    /// Batch processor for optimized file operations
    private let batchProcessor = BatchFileProcessor()

    /// Cache and temporary file patterns to exclude
    private static let cachePatterns = [
        // macOS system cache patterns
        ".DS_Store",
        ".Spotlight-V100",
        ".Trashes",
        ".fseventsd",
        ".TemporaryItems",
        ".VolumeIcon.icns",
        ".DocumentRevisions-V100",
        ".PKInstallSandboxManager",
        ".PKInstallSandboxManager-SystemSoftware",

        // Adobe cache files
        "Adobe Premiere Pro Video Previews",
        "Adobe Premiere Pro Audio Previews",
        "Media Cache Files",
        "Media Cache",
        "CacheClip",
        ".BridgeCache",
        ".BridgeCacheT",

        // Photo editing app caches
        "Lightroom Catalog Previews.lrdata",
        "Lightroom Catalog Smart Previews.lrdata",
        ".photoslibrary/database",
        ".photoslibrary/private",

        // Capture One Session caches
        "Cache", // C1 Session cache folder
        "Proxies", // C1 Session proxy folder
        "Thumbnails", // C1 Session thumbnails

        // Development caches
        "node_modules",
        ".git",
        "DerivedData",
        "build",
        ".build",

        // Thumbnail caches
        "Thumbs.db",
        ".thumbnails",
        "thumbnail",

        // Temporary files
        "~",
        ".tmp",
        ".temp",
        ".cache",
        ".lock",
    ]

    // MARK: - Initialization

    init() {}

    // MARK: - Helper Methods

    /// Check if a file or directory should be excluded as a cache/temporary file
    private func isCacheFile(_ url: URL) -> Bool {
        let path = url.path
        let filename = url.lastPathComponent

        // Special handling for Capture One Session structure
        // Sessions have .cosessiondb extension and contain Cache/Proxies/Thumbnails folders
        if path.contains(".cosessiondb/") {
            // Check if we're in a cache subfolder within a Session
            if path.contains(".cosessiondb/Cache/") || path.contains(".cosessiondb/Proxies/")
                || path.contains(".cosessiondb/Thumbnails/")
            {
                return true
            }
        }

        // Check exact filename matches
        for pattern in Self.cachePatterns {
            if filename == pattern {
                return true
            }
        }

        // Check if path contains cache directories
        for pattern in Self.cachePatterns {
            if path.contains("/\(pattern)/") {
                return true
            }
        }

        // Check for temporary file patterns
        if filename.hasPrefix("~") || filename.hasPrefix(".") {
            // Exception for legitimate hidden image files
            let imageExtensions = ["jpg", "jpeg", "png", "gif", "tiff", "raw", "nef", "cr2", "arw"]
            let ext = url.pathExtension.lowercased()
            if imageExtensions.contains(ext) {
                return false // Don't exclude hidden image files
            }
            return true // Exclude other hidden/temp files
        }

        // Check for file extensions that indicate temp/cache
        if filename.hasSuffix(".tmp") || filename.hasSuffix(".temp") || filename.hasSuffix(".cache")
            || filename.hasSuffix(".lock")
        {
            return true
        }

        return false
    }

    // MARK: - Callbacks

    func setStatusCallback(_ callback: @escaping (String) -> Void) {
        onStatusUpdate = callback
    }

    func setErrorCallback(_ callback: @escaping (String, String, String) -> Void) {
        onFileError = callback
    }

    // MARK: - Main API

    /// Build manifest of files to copy
    /// - Parameters:
    ///   - source: Source directory URL
    ///   - shouldCancel: Closure to check if operation should be cancelled
    ///   - filter: Optional file type filter to apply
    ///   - includeSubdirectories: Whether to scan subdirectories recursively (default: true)
    /// - Returns: Array of manifest entries or nil if cancelled/failed
    func build(
        source: URL,
        shouldCancel: @escaping () -> Bool,
        filter: FileTypeFilter = FileTypeFilter(),
        includeSubdirectories: Bool = true
    ) async -> [FileManifestEntry]? {
        // Phase 1: Collect all files
        var filesToProcess: [(url: URL, relativePath: String, size: Int64)] = []

        let fileManager = FileManager.default

        // Set enumerator options based on preferences
        var enumeratorOptions: FileManager.DirectoryEnumerationOptions = []
        if PreferencesManager.shared.skipHiddenFiles {
            enumeratorOptions.insert(.skipsHiddenFiles)
        }
        if !includeSubdirectories {
            enumeratorOptions.insert(.skipsSubdirectoryDescendants)
        }

        guard
            let enumerator = fileManager.enumerator(
                at: source,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey],
                options: enumeratorOptions
            )
        else {
            ApplicationLogger.shared.debug("Failed to create directory enumerator for: \(source.path)", category: .fileSystem)
            return nil
        }

        ApplicationLogger.shared.debug("Created enumerator for: \(source.path)", category: .fileSystem)
        ApplicationLogger.shared.debug("Skip hidden files: \(PreferencesManager.shared.skipHiddenFiles)", category: .fileSystem)
        ApplicationLogger.shared.debug("Exclude cache files: \(PreferencesManager.shared.excludeCacheFiles)", category: .fileSystem)
        ApplicationLogger.shared.debug("Include subdirectories: \(includeSubdirectories)", category: .fileSystem)

        var fileCount = 0
        var skippedSymlinks = 0
        var skippedNonRegular = 0
        var skippedCache = 0
        var skippedUnsupported = 0
        var skippedByFilter = 0

        // Collect files first
        while let url = enumerator.nextObject() as? URL {
            guard !shouldCancel() else { return nil }

            do {
                let resourceValues = try url.resourceValues(forKeys: [
                    .isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey,
                ])

                // Skip symbolic links - we don't follow them for security
                if resourceValues.isSymbolicLink == true {
                    ApplicationLogger.shared.debug("Skipping symbolic link: \(url.lastPathComponent)", category: .fileSystem)
                    skippedSymlinks += 1
                    continue
                }

                guard resourceValues.isRegularFile == true else {
                    skippedNonRegular += 1
                    continue
                }

                // Skip cache and temporary files if preference is enabled
                if PreferencesManager.shared.excludeCacheFiles && isCacheFile(url) {
                    // Debug: log cache files being skipped
                    ApplicationLogger.shared.debug("Skipping cache/temp file: \(url.lastPathComponent)", category: .fileSystem)
                    skippedCache += 1
                    continue
                }

                guard ImageFileType.isSupportedFile(url) else {
                    // Debug: log skipped files
                    if url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
                        ApplicationLogger.shared.debug("Video file skipped (not supported?): \(url.lastPathComponent)", category: .fileSystem)
                    } else if url.pathExtension.lowercased() == "tif"
                        || url.pathExtension.lowercased() == "tiff"
                    {
                        ApplicationLogger.shared.debug("TIFF file marked as unsupported: \(url.lastPathComponent)", category: .fileSystem)
                    }
                    skippedUnsupported += 1
                    continue
                }

                // Apply file type filter
                guard filter.shouldInclude(fileURL: url) else {
                    // File is filtered out
                    skippedByFilter += 1
                    continue
                }

                fileCount += 1

                // Update status
                let statusMessage = "Scanning file \(fileCount)..."
                if let callback = onStatusUpdate {
                    Task { @MainActor in
                        callback(statusMessage)
                    }
                }

                // Debug logging for video files in manifest
                if url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
                    ApplicationLogger.shared.debug("Found video: \(url.lastPathComponent)", category: .fileSystem)
                }

                let relativePath = url.path.replacingOccurrences(of: source.path + "/", with: "")
                let size = resourceValues.fileSize ?? 0

                filesToProcess.append((url: url, relativePath: relativePath, size: Int64(size)))

            } catch {
                ApplicationLogger.shared.debug("Error scanning \(url.lastPathComponent): \(error)", category: .fileSystem)
            }
        }

        guard !shouldCancel() else { return nil }

        // Log summary of file scanning
        ApplicationLogger.shared.debug("File scanning summary:", category: .fileSystem)
        ApplicationLogger.shared.debug("Files found: \(fileCount)", category: .fileSystem)
        ApplicationLogger.shared.debug("Skipped (symlinks): \(skippedSymlinks)", category: .fileSystem)
        ApplicationLogger.shared.debug("Skipped (non-regular): \(skippedNonRegular)", category: .fileSystem)
        ApplicationLogger.shared.debug("Skipped (cache): \(skippedCache)", category: .fileSystem)
        ApplicationLogger.shared.debug("Skipped (unsupported): \(skippedUnsupported)", category: .fileSystem)
        ApplicationLogger.shared.debug("Skipped (filter): \(skippedByFilter)", category: .fileSystem)
        ApplicationLogger.shared.debug("Ready to process: \(filesToProcess.count)", category: .fileSystem)

        // Phase 2: Calculate checksums in batches
        ApplicationLogger.shared.debug("Processing \(filesToProcess.count) files for checksums...", category: .fileSystem)

        if let callback = onStatusUpdate {
            let fileCount = filesToProcess.count
            Task { @MainActor in
                callback("Calculating checksums for \(fileCount) files...")
            }
        }

        // Process checksums in batches
        let checksums: [URL: String]
        do {
            checksums = try await batchProcessor.batchCalculateChecksums(
                filesToProcess.map { $0.url },
                shouldCancel: shouldCancel
            )
        } catch {
            ApplicationLogger.shared.debug("Batch checksum calculation failed: \(error)", category: .fileSystem)
            return nil
        }

        guard !shouldCancel() else { return nil }

        // Phase 3: Build manifest from results
        var manifest: [FileManifestEntry] = []

        for (url, relativePath, size) in filesToProcess {
            guard let checksum = checksums[url] else {
                ApplicationLogger.shared.debug("No checksum for \(url.lastPathComponent)", category: .fileSystem)
                if let callback = onFileError {
                    Task { @MainActor in
                        callback(url.lastPathComponent, "manifest", "Failed to calculate checksum")
                    }
                }
                continue
            }

            let entry = FileManifestEntry(
                relativePath: relativePath,
                sourceURL: url,
                checksum: checksum,
                size: size
            )

            manifest.append(entry)
        }

        ApplicationLogger.shared.debug("Manifest built with \(manifest.count) files", category: .fileSystem)
        return manifest
    }

    // MARK: - Private Methods

    /// Calculate SHA256 checksum for a file
    private func calculateChecksum(for url: URL, shouldCancel: @escaping () -> Bool) async throws
        -> String
    {
        try await Task.detached(priority: .userInitiated) {
            try BackupManager.sha256ChecksumStatic(for: url, shouldCancel: shouldCancel())
        }.value
    }
}
