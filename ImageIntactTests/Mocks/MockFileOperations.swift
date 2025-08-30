//
//  MockFileOperations.swift
//  ImageIntactTests
//
//  Mock implementation of FileOperationsProtocol for testing
//

import Foundation
@testable import ImageIntact

/// Mock implementation of FileOperationsProtocol for testing
class MockFileOperations: FileOperationsProtocol {
    
    // MARK: - Tracking properties for assertions
    var copiedFiles: [(source: URL, destination: URL)] = []
    var createdDirectories: [URL] = []
    var removedItems: [URL] = []
    var checksumCalculations: [URL] = []
    var securityScopedAccesses: [URL] = []
    
    // MARK: - Configurable behaviors
    var shouldFailCopy = false
    var shouldFailChecksum = false
    var filesExist: Set<URL> = []
    var mockChecksums: [URL: String] = [:]
    var mockFileSizes: [URL: Int64] = [:]
    var mockAttributes: [URL: [FileAttributeKey: Any]] = [:]
    
    // MARK: - Error types for testing
    enum MockError: Error {
        case copyFailed
        case checksumFailed
        case directoryCreationFailed
        case itemRemovalFailed
    }
    
    // MARK: - FileOperationsProtocol implementation
    
    func copyItem(at source: URL, to destination: URL) async throws {
        copiedFiles.append((source: source, destination: destination))
        
        if shouldFailCopy {
            throw MockError.copyFailed
        }
        
        // Simulate successful copy by adding destination to exists set
        filesExist.insert(destination)
        
        // Copy over mock attributes if they exist
        if let sourceSize = mockFileSizes[source] {
            mockFileSizes[destination] = sourceSize
        }
        if let sourceChecksum = mockChecksums[source] {
            mockChecksums[destination] = sourceChecksum
        }
    }
    
    func fileExists(at url: URL) -> Bool {
        return filesExist.contains(url)
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        createdDirectories.append(url)
        filesExist.insert(url)
    }
    
    func removeItem(at url: URL) throws {
        removedItems.append(url)
        filesExist.remove(url)
        mockFileSizes.removeValue(forKey: url)
        mockChecksums.removeValue(forKey: url)
        mockAttributes.removeValue(forKey: url)
    }
    
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        if let attributes = mockAttributes[url] {
            return attributes
        }
        
        // Return default attributes
        var attributes: [FileAttributeKey: Any] = [:]
        attributes[.size] = mockFileSizes[url] ?? 0
        attributes[.type] = filesExist.contains(url) ? FileAttributeType.typeRegular : nil
        return attributes
    }
    
    func calculateChecksum(for url: URL, shouldCancel: () -> Bool) async throws -> String {
        checksumCalculations.append(url)
        
        if shouldFailChecksum {
            throw MockError.checksumFailed
        }
        
        if let checksum = mockChecksums[url] {
            return checksum
        }
        
        // Return a default checksum
        return "mock_checksum_\(url.lastPathComponent)"
    }
    
    func startAccessingSecurityScopedResource(for url: URL) -> Bool {
        securityScopedAccesses.append(url)
        return true
    }
    
    func stopAccessingSecurityScopedResource(for url: URL) {
        // Just track that this was called
    }
    
    func fileSize(at url: URL) -> Int64? {
        return mockFileSizes[url]
    }
    
    // MARK: - Test helper methods
    
    /// Reset all tracking arrays and state
    func reset() {
        copiedFiles.removeAll()
        createdDirectories.removeAll()
        removedItems.removeAll()
        checksumCalculations.removeAll()
        securityScopedAccesses.removeAll()
        
        shouldFailCopy = false
        shouldFailChecksum = false
        filesExist.removeAll()
        mockChecksums.removeAll()
        mockFileSizes.removeAll()
        mockAttributes.removeAll()
    }
    
    /// Add a mock file with specified properties
    func addMockFile(at url: URL, size: Int64, checksum: String) {
        filesExist.insert(url)
        mockFileSizes[url] = size
        mockChecksums[url] = checksum
    }
    
    /// Verify that a file was copied from source to destination
    func verifyCopied(from source: URL, to destination: URL) -> Bool {
        return copiedFiles.contains { $0.source == source && $0.destination == destination }
    }
    
    /// Get count of operations
    var copyCount: Int { copiedFiles.count }
    var directoryCreationCount: Int { createdDirectories.count }
    var removalCount: Int { removedItems.count }
    var checksumCount: Int { checksumCalculations.count }
}