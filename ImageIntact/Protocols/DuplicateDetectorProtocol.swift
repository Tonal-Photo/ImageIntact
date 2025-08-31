//
//  DuplicateDetectorProtocol.swift
//  ImageIntact
//
//  Protocol for duplicate detection functionality
//

import Foundation

/// Protocol for duplicate file detection
@MainActor
protocol DuplicateDetectorProtocol: AnyObject {
    
    /// Analyze source files against a destination for duplicates
    func analyzeForDuplicates(
        manifest: [FileManifestEntry],
        destination: URL,
        organizationName: String
    ) async -> DuplicateDetector.DuplicateAnalysis
    
    /// Perform pre-flight check for all destinations
    func preflightDuplicateCheck(
        manifest: [FileManifestEntry],
        destinations: [URL],
        organizationName: String
    ) async -> [URL: DuplicateDetector.DuplicateAnalysis]
    
    /// Filter manifest to exclude duplicates based on user preference
    func filterManifest(
        _ manifest: [FileManifestEntry],
        excludingDuplicates analysis: DuplicateDetector.DuplicateAnalysis,
        skipExact: Bool,
        skipRenamed: Bool
    ) -> [FileManifestEntry]
    
    /// Get a human-readable summary of the analysis
    func formatAnalysisSummary(_ analysis: DuplicateDetector.DuplicateAnalysis) -> String
}

// MARK: - Make DuplicateDetector conform to protocol
extension DuplicateDetector: DuplicateDetectorProtocol {
    // Already implements all required methods
}

// MARK: - Mock Implementation for Testing
@MainActor
class MockDuplicateDetector: DuplicateDetectorProtocol {
    
    // Control behavior for testing
    var mockAnalysis: DuplicateDetector.DuplicateAnalysis?
    var shouldReturnDuplicates = false
    var analyzeCallCount = 0
    var filterCallCount = 0
    
    func analyzeForDuplicates(
        manifest: [FileManifestEntry],
        destination: URL,
        organizationName: String
    ) async -> DuplicateDetector.DuplicateAnalysis {
        analyzeCallCount += 1
        
        if let mockAnalysis = mockAnalysis {
            return mockAnalysis
        }
        
        if shouldReturnDuplicates {
            // Return some test duplicates
            let duplicate = DuplicateDetector.DuplicateFile(
                sourceFile: manifest.first ?? FileManifestEntry(
                    relativePath: "test.jpg",
                    sourceURL: URL(fileURLWithPath: "/test.jpg"),
                    checksum: "abc123",
                    size: 1024
                ),
                destinationPath: "/dest/test.jpg",
                checksum: "abc123",
                isDifferentName: false,
                existingOrganization: nil
            )
            
            return DuplicateDetector.DuplicateAnalysis(
                totalSourceFiles: manifest.count,
                exactDuplicates: [duplicate],
                renamedDuplicates: [],
                uniqueFiles: max(0, manifest.count - 1),
                potentialSpaceSaved: 1024,
                destinationDriveUUID: nil
            )
        }
        
        // Return no duplicates
        return DuplicateDetector.DuplicateAnalysis(
            totalSourceFiles: manifest.count,
            exactDuplicates: [],
            renamedDuplicates: [],
            uniqueFiles: manifest.count,
            potentialSpaceSaved: 0,
            destinationDriveUUID: nil
        )
    }
    
    func preflightDuplicateCheck(
        manifest: [FileManifestEntry],
        destinations: [URL],
        organizationName: String
    ) async -> [URL: DuplicateDetector.DuplicateAnalysis] {
        var results: [URL: DuplicateDetector.DuplicateAnalysis] = [:]
        
        for destination in destinations {
            results[destination] = await analyzeForDuplicates(
                manifest: manifest,
                destination: destination,
                organizationName: organizationName
            )
        }
        
        return results
    }
    
    func filterManifest(
        _ manifest: [FileManifestEntry],
        excludingDuplicates analysis: DuplicateDetector.DuplicateAnalysis,
        skipExact: Bool,
        skipRenamed: Bool
    ) -> [FileManifestEntry] {
        filterCallCount += 1
        
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
    
    func formatAnalysisSummary(_ analysis: DuplicateDetector.DuplicateAnalysis) -> String {
        return "Test summary: \(analysis.totalDuplicates) duplicates found"
    }
}