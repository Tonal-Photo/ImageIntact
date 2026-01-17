import CoreData
import Foundation

/// Detects existing files at destination that could be migrated to organized folders
@MainActor
class BackupMigrationDetector {
    struct MigrationCandidate {
        let sourceFile: URL
        let destinationFile: URL
        let checksum: String
        let size: Int64
    }

    struct MigrationPlan {
        let destinationURL: URL
        let organizationFolder: String
        let candidates: [MigrationCandidate]
        var totalSize: Int64 {
            candidates.reduce(0) { $0 + $1.size }
        }

        var fileCount: Int {
            candidates.count
        }
    }

    /// Check if migration is needed for a destination
    func checkForMigrationNeeded(
        source _: URL,
        destination: URL,
        organizationName: String,
        manifest: [FileManifestEntry]
    ) async -> MigrationPlan? {
        // Skip if no organization name
        guard !organizationName.isEmpty else { return nil }

        // Check if organization folder already exists
        let organizedPath = destination.appendingPathComponent(organizationName)
        if FileManager.default.fileExists(atPath: organizedPath.path) {
            // Already organized, no migration needed
            ApplicationLogger.shared.debug("Organization folder already exists at \(organizedPath.path)", category: .backup)
            return nil
        }

        ApplicationLogger.shared.debug("Checking for existing files at destination root that match source...", category: .backup)

        // Start security-scoped access for the destination
        let accessGranted = destination.startAccessingSecurityScopedResource()
        defer {
            if accessGranted {
                destination.stopAccessingSecurityScopedResource()
            }
        }

        // Get all files in destination root (not in subdirectories)
        var rootFiles: [URL] = []
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: destination,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )

            rootFiles = contents.filter { url in
                // Only regular files, not directories
                let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return resourceValues?.isRegularFile ?? false
            }
        } catch {
            ApplicationLogger.shared.error("Error reading destination: \(error)", category: .backup)
            return nil
        }

        guard !rootFiles.isEmpty else {
            ApplicationLogger.shared.debug("No files in destination root, no migration needed", category: .backup)
            return nil
        }

        ApplicationLogger.shared.debug("Found \(rootFiles.count) files in destination root", category: .backup)

        // Build a map of source checksums for quick lookup
        var sourceChecksums: [String: FileManifestEntry] = [:]
        for entry in manifest {
            sourceChecksums[entry.checksum] = entry
        }

        // Find matching files
        var candidates: [MigrationCandidate] = []

        for destFile in rootFiles {
            // Skip if file doesn't exist in our source
            let fileName = destFile.lastPathComponent

            // Quick check: does this filename exist in our manifest?
            let matchingEntry = manifest.first { entry in
                URL(fileURLWithPath: entry.relativePath).lastPathComponent == fileName
            }

            if let entry = matchingEntry {
                // Calculate checksum of destination file
                ApplicationLogger.shared.debug("Checking \(fileName)...", category: .backup)

                do {
                    let destChecksum = try BackupManager.sha256ChecksumStatic(
                        for: destFile,
                        shouldCancel: false
                    )

                    // Check if checksums match
                    if destChecksum == entry.checksum {
                        ApplicationLogger.shared.debug("Match found: \(fileName)", category: .backup)
                        candidates.append(
                            MigrationCandidate(
                                sourceFile: entry.sourceURL,
                                destinationFile: destFile,
                                checksum: entry.checksum,
                                size: entry.size
                            ))
                    } else {
                        ApplicationLogger.shared.warning("File exists but checksum differs: \(fileName)", category: .backup)
                    }
                } catch {
                    ApplicationLogger.shared.error("Error calculating checksum for \(fileName): \(error)", category: .backup)
                }
            }
        }

        if candidates.isEmpty {
            ApplicationLogger.shared.debug("No matching files found, no migration needed", category: .backup)
            return nil
        }

        ApplicationLogger.shared.debug("Found \(candidates.count) files that can be migrated", category: .backup)

        return MigrationPlan(
            destinationURL: destination,
            organizationFolder: organizationName,
            candidates: candidates
        )
    }

    /// Perform the migration
    func performMigration(
        plan: MigrationPlan,
        progressCallback: @escaping (Int, Int) -> Void
    ) async throws {
        let targetFolder = plan.destinationURL.appendingPathComponent(plan.organizationFolder)

        // Create the organization folder
        try FileManager.default.createDirectory(
            at: targetFolder,
            withIntermediateDirectories: true,
            attributes: nil
        )

        ApplicationLogger.shared.debug("Created organization folder: \(targetFolder.path)", category: .backup)

        var completed = 0
        let total = plan.candidates.count

        for candidate in plan.candidates {
            let fileName = candidate.destinationFile.lastPathComponent
            let newPath = targetFolder.appendingPathComponent(fileName)

            ApplicationLogger.shared.debug("Moving \(fileName)...", category: .backup)

            // Move the file
            try FileManager.default.moveItem(
                at: candidate.destinationFile,
                to: newPath
            )

            // Verify the move with checksum
            let movedChecksum = try BackupManager.sha256ChecksumStatic(
                for: newPath,
                shouldCancel: false
            )

            if movedChecksum != candidate.checksum {
                // Uh oh, move corrupted the file somehow
                throw NSError(
                    domain: "ImageIntact",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "File corrupted during move: \(fileName)"]
                )
            }

            completed += 1
            progressCallback(completed, total)

            ApplicationLogger.shared.debug("Moved and verified: \(fileName)", category: .backup)
        }

        ApplicationLogger.shared.info("Migration complete: \(completed) files moved to \(plan.organizationFolder)", category: .backup)
    }
}
