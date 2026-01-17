//
//  DuplicateDetector.swift
//  ImageIntact
//
//  Detects duplicate files across sources and destinations using checksums
//

import CoreData
import Foundation

/// Manages detection of duplicate files across backup sources and destinations
@MainActor
class DuplicateDetector: ObservableObject {
    // MARK: - Types

    /// Represents a duplicate file found at destination
    struct DuplicateFile {
        let sourceFile: FileManifestEntry
        let destinationPath: String
        let checksum: String
        let isDifferentName: Bool
        let existingOrganization: String? // Which organization folder it's in
    }

    /// Categories of duplicates for reporting
    enum DuplicateCategory {
        case exact // Same checksum, same filename
        case renamed // Same checksum, different filename
        case nearDuplicate // Similar characteristics but different checksum
    }

    /// Summary of duplicate analysis
    struct DuplicateAnalysis {
        let totalSourceFiles: Int
        let exactDuplicates: [DuplicateFile]
        let renamedDuplicates: [DuplicateFile]
        let uniqueFiles: Int
        let potentialSpaceSaved: Int64
        let destinationDriveUUID: String?

        var totalDuplicates: Int {
            exactDuplicates.count + renamedDuplicates.count
        }

        var duplicatePercentage: Double {
            guard totalSourceFiles > 0 else { return 0 }
            return Double(totalDuplicates) * 100.0 / Double(totalSourceFiles)
        }
    }

    // MARK: - Properties

    @Published var isAnalyzing = false
    @Published var analysisProgress: Double = 0.0
    @Published var currentAnalysis: DuplicateAnalysis?

    // MARK: - Initialization

    init() {
        // Use the shared EventLogger's Core Data stack to avoid conflicts
    }

    // MARK: - Public Methods

    /// Analyze source files against a destination for duplicates
    /// - Parameters:
    ///   - manifest: Source files to check
    ///   - destination: Destination URL to check against
    ///   - organizationName: Current organization folder name (if any)
    /// - Returns: Analysis results
    func analyzeForDuplicates(
        manifest: [FileManifestEntry],
        destination: URL,
        organizationName _: String = ""
    ) async -> DuplicateAnalysis {
        isAnalyzing = true
        analysisProgress = 0.0
        defer {
            isAnalyzing = false
            analysisProgress = 1.0
        }

        ApplicationLogger.shared.debug(
            "Starting duplicate analysis for \(manifest.count) files at \(destination.lastPathComponent)",
            category: .fileSystem
        )

        // Get drive UUID if possible
        let driveUUID = getDriveUUID(for: destination)

        // Build checksum map from source
        var sourceByChecksum: [String: FileManifestEntry] = [:]
        for entry in manifest {
            sourceByChecksum[entry.checksum] = entry
        }

        // Query existing files at destination from Core Data
        let existingFiles = await queryExistingFiles(at: destination, driveUUID: driveUUID)

        // Analyze for duplicates
        var exactDuplicates: [DuplicateFile] = []
        var renamedDuplicates: [DuplicateFile] = []
        var potentialSpaceSaved: Int64 = 0

        for (index, entry) in manifest.enumerated() {
            // Update progress
            await MainActor.run {
                self.analysisProgress = Double(index) / Double(manifest.count)
            }

            // Check if this checksum exists at destination
            if let existingFile = existingFiles[entry.checksum] {
                let duplicate = DuplicateFile(
                    sourceFile: entry,
                    destinationPath: existingFile.path,
                    checksum: entry.checksum,
                    isDifferentName: existingFile.filename
                        != entry.relativePath.components(separatedBy: "/").last,
                    existingOrganization: existingFile.organization
                )

                if duplicate.isDifferentName {
                    renamedDuplicates.append(duplicate)
                } else {
                    exactDuplicates.append(duplicate)
                }

                potentialSpaceSaved += entry.size
            }
        }

        let uniqueFiles = manifest.count - exactDuplicates.count - renamedDuplicates.count

        let analysis = DuplicateAnalysis(
            totalSourceFiles: manifest.count,
            exactDuplicates: exactDuplicates,
            renamedDuplicates: renamedDuplicates,
            uniqueFiles: uniqueFiles,
            potentialSpaceSaved: potentialSpaceSaved,
            destinationDriveUUID: driveUUID
        )

        // Cache the analysis
        await MainActor.run {
            self.currentAnalysis = analysis
        }

        ApplicationLogger.shared.debug("Duplicate analysis complete:", category: .fileSystem)
        ApplicationLogger.shared.debug("   - Exact duplicates: \(exactDuplicates.count)", category: .fileSystem)
        ApplicationLogger.shared.debug("   - Renamed duplicates: \(renamedDuplicates.count)", category: .fileSystem)
        ApplicationLogger.shared.debug("   - Unique files: \(uniqueFiles)", category: .fileSystem)
        ApplicationLogger.shared.debug(
            "   - Space that would be saved: \(ByteCountFormatter.string(fromByteCount: potentialSpaceSaved, countStyle: .binary))",
            category: .fileSystem
        )

        return analysis
    }

    /// Perform pre-flight check for all destinations
    func preflightDuplicateCheck(
        manifest: [FileManifestEntry],
        destinations: [URL],
        organizationName: String = ""
    ) async -> [URL: DuplicateAnalysis] {
        var results: [URL: DuplicateAnalysis] = [:]

        for destination in destinations {
            let analysis = await analyzeForDuplicates(
                manifest: manifest,
                destination: destination,
                organizationName: organizationName
            )
            results[destination] = analysis
        }

        return results
    }

    // MARK: - Private Methods

    /// Query Core Data for existing files at destination
    private func queryExistingFiles(
        at destination: URL,
        driveUUID: String?
    ) async -> [String: (path: String, filename: String, organization: String?)] {
        return await withCheckedContinuation { continuation in
            // Use EventLogger's shared container to avoid conflicts
            let context = EventLogger.shared.container.viewContext
            let request: NSFetchRequest<NSFetchRequestResult> = NSFetchRequest(entityName: "BackupEvent")

            // Build predicate
            var predicates: [NSPredicate] = []

            // If we have a driveUUID, use it for more efficient query
            if let uuid = driveUUID {
                predicates.append(NSPredicate(format: "driveUUID == %@", uuid))
            } else {
                // Fallback to path-based filtering
                let destPath = destination.path
                predicates.append(NSPredicate(format: "destinationPath BEGINSWITH %@", destPath))
            }

            // Filter by event type (successful copies)
            predicates.append(NSPredicate(format: "eventType == %@", "copy"))
            predicates.append(NSPredicate(format: "severity == %@", "info"))

            // Only get events with checksums
            predicates.append(NSPredicate(format: "checksum != nil"))

            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)

            // Fetch only needed properties
            request.propertiesToFetch = ["checksum", "destinationPath", "fileName"]
            request.resultType = .dictionaryResultType

            do {
                let results = try context.fetch(request) as? [[String: Any]] ?? []

                // Build checksum -> file info map
                var fileMap: [String: (path: String, filename: String, organization: String?)] = [:]

                for result in results {
                    guard let checksum = result["checksum"] as? String,
                          let destPath = result["destinationPath"] as? String
                    else {
                        continue
                    }

                    let filename =
                        result["fileName"] as? String ?? URL(fileURLWithPath: destPath).lastPathComponent

                    // Extract organization from path if present
                    let organization = extractOrganization(from: destPath, basePath: destination.path)

                    // Store the most recent occurrence of each checksum
                    fileMap[checksum] = (path: destPath, filename: filename, organization: organization)
                }

                ApplicationLogger.shared.debug("Found \(fileMap.count) existing files with checksums at destination", category: .fileSystem)
                continuation.resume(returning: fileMap)

            } catch {
                ApplicationLogger.shared.error("Error querying existing files: \(error)", category: .fileSystem)
                continuation.resume(returning: [:])
            }
        }
    }

    /// Extract organization folder from destination path
    private func extractOrganization(from destPath: String, basePath: String) -> String? {
        // Remove base path to get relative path
        let relativePath = destPath.replacingOccurrences(of: basePath, with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // First component is the organization folder (if any)
        let components = relativePath.components(separatedBy: "/")
        if components.count > 1 {
            return components.first
        }

        return nil
    }

    /// Get drive UUID for a destination URL
    private func getDriveUUID(for url: URL) -> String? {
        // Try to get volume UUID
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeUUIDStringKey])
            return resourceValues.volumeUUIDString
        } catch {
            ApplicationLogger.shared.warning("Could not get drive UUID for \(url.path): \(error)", category: .fileSystem)
            return nil
        }
    }

    // MARK: - Filtering Methods

    /// Filter manifest to exclude duplicates based on user preference
    func filterManifest(
        _ manifest: [FileManifestEntry],
        excludingDuplicates analysis: DuplicateAnalysis,
        skipExact: Bool = true,
        skipRenamed: Bool = false
    ) -> [FileManifestEntry] {
        var checksumToSkip = Set<String>()

        if skipExact {
            for dup in analysis.exactDuplicates {
                checksumToSkip.insert(dup.checksum)
            }
        }

        if skipRenamed {
            for dup in analysis.renamedDuplicates {
                checksumToSkip.insert(dup.checksum)
            }
        }

        return manifest.filter { entry in
            !checksumToSkip.contains(entry.checksum)
        }
    }

    /// Get a human-readable summary of the analysis
    func formatAnalysisSummary(_ analysis: DuplicateAnalysis) -> String {
        var summary = "📊 Duplicate Analysis:\n"
        summary += "• Total files: \(analysis.totalSourceFiles)\n"
        summary += "• Exact duplicates: \(analysis.exactDuplicates.count)\n"
        summary += "• Renamed duplicates: \(analysis.renamedDuplicates.count)\n"
        summary += "• Unique files: \(analysis.uniqueFiles)\n"
        summary +=
            "• Space to save: \(ByteCountFormatter.string(fromByteCount: analysis.potentialSpaceSaved, countStyle: .binary))\n"
        summary += "• Duplicate rate: \(String(format: "%.1f%%", analysis.duplicatePercentage))"

        return summary
    }
}
