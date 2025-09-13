//
//  MockFileOperations.swift
//  ImageIntactTests
//
//  Mock implementation of FileOperationsProtocol for testing
//

import Foundation
@testable import ImageIntact

/// Thread-safe storage for mock file operations
actor MockFileOperationsStorage {
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
    
    // MARK: - Retry behavior
    private var copyAttempts = 0
    var failUntilAttempt = 0  // 0 means no retry simulation
    
    func incrementCopyAttempts() {
        copyAttempts += 1
    }
    
    func getCopyAttempts() -> Int {
        return copyAttempts
    }
    
    // MARK: - Delay behavior
    var delayPerOperation: TimeInterval = 0  // 0 means no delay
    
    // MARK: - Corruption behavior
    var corruptFile: String? = nil
    
    func recordCopy(from source: URL, to destination: URL) {
        copiedFiles.append((source: source, destination: destination))
        filesExist.insert(destination)
    }
    
    func copyAttributes(from source: URL, to destination: URL) {
        if let size = mockFileSizes[source] {
            mockFileSizes[destination] = size
        }
        if let checksum = mockChecksums[source] {
            mockChecksums[destination] = checksum
        }
    }
    
    func addMockFile(at url: URL, size: Int64, checksum: String) {
        filesExist.insert(url)
        mockFileSizes[url] = size
        mockChecksums[url] = checksum
    }
    
    func setShouldFailCopy(_ value: Bool) {
        shouldFailCopy = value
    }
    
    func setShouldFailChecksum(_ value: Bool) {
        shouldFailChecksum = value
    }
    
    func recordDirectoryCreation(_ url: URL) {
        createdDirectories.append(url)
        filesExist.insert(url)
    }
    
    func recordRemoval(_ url: URL) {
        removedItems.append(url)
        filesExist.remove(url)
        mockChecksums.removeValue(forKey: url)
        mockFileSizes.removeValue(forKey: url)
        mockAttributes.removeValue(forKey: url)
    }
    
    func recordChecksumCalculation(_ url: URL) {
        checksumCalculations.append(url)
    }
    
    func recordSecurityScopedAccess(_ url: URL) {
        securityScopedAccesses.append(url)
    }
    
    func setMockChecksum(_ checksum: String, for url: URL) {
        mockChecksums[url] = checksum
    }
    
    func setMockFileSize(_ size: Int64, for url: URL) {
        mockFileSizes[url] = size
    }
    
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
        
        copyAttempts = 0
        failUntilAttempt = 0
        delayPerOperation = 0
        corruptFile = nil
    }
}

/// Mock implementation of FileOperationsProtocol for testing
/// Thread-safe implementation using actor isolation
class MockFileOperations: FileOperationsProtocol {
    let storage = MockFileOperationsStorage()
    
    // MARK: - Error types for testing
    enum MockError: Error {
        case copyFailed
        case checksumFailed
        case directoryCreationFailed
        case itemRemovalFailed
    }
    
    // MARK: - FileOperationsProtocol implementation
    
    func copyItem(at source: URL, to destination: URL) async throws {
        // Handle delay if configured
        let delay = await storage.delayPerOperation
        if delay > 0 {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        }
        
        // Handle retry simulation
        let failUntil = await storage.failUntilAttempt
        if failUntil > 0 {
            await storage.incrementCopyAttempts()
            let attempts = await storage.getCopyAttempts()
            if attempts <= failUntil {
                throw MockError.copyFailed
            }
        }
        
        // Regular failure check
        let shouldFail = await storage.shouldFailCopy
        
        await storage.recordCopy(from: source, to: destination)
        
        if shouldFail {
            throw MockError.copyFailed
        }
        
        // Copy over mock attributes if they exist
        await storage.copyAttributes(from: source, to: destination)
    }
    
    func fileExists(at url: URL) -> Bool {
        // This needs to be synchronous per protocol
        // We'll use a Task to bridge to async
        let task = Task { await storage.filesExist.contains(url) }
        return (try? task.waitForResult()) ?? false
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        // Bridge to async for thread safety
        let task = Task {
            await storage.recordDirectoryCreation(url)
        }
        _ = try task.waitForResult()
    }
    
    func removeItem(at url: URL) throws {
        let task = Task {
            await storage.recordRemoval(url)
        }
        _ = try task.waitForResult()
    }
    
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        let task = Task { () -> [FileAttributeKey: Any] in
            if let attributes = await storage.mockAttributes[url] {
                return attributes
            }
            
            // Return default attributes
            var attributes: [FileAttributeKey: Any] = [:]
            attributes[.size] = await storage.mockFileSizes[url] ?? 0
            attributes[.type] = await storage.filesExist.contains(url) ? FileAttributeType.typeRegular : nil
            return attributes
        }
        return try task.waitForResult()
    }
    
    func calculateChecksum(for url: URL, shouldCancel: () -> Bool) async throws -> String {
        await storage.recordChecksumCalculation(url)
        
        // Handle corruption simulation
        let corruptFile = await storage.corruptFile
        if let corruptFile = corruptFile,
           url.path.contains(corruptFile) && url.path.contains("TestOrg") {
            // Return a corrupted checksum for the destination
            return "corrupted_checksum_456"
        }
        
        let shouldFail = await storage.shouldFailChecksum
        if shouldFail {
            throw MockError.checksumFailed
        }
        
        if let checksum = await storage.mockChecksums[url] {
            return checksum
        }
        
        // Return a default checksum
        return "mock_checksum_\(url.lastPathComponent)"
    }
    
    func startAccessingSecurityScopedResource(for url: URL) -> Bool {
        let task = Task {
            await storage.recordSecurityScopedAccess(url)
        }
        _ = try? task.waitForResult()
        return true
    }
    
    func stopAccessingSecurityScopedResource(for url: URL) {
        // Just track that this was called
    }
    
    func fileSize(at url: URL) -> Int64? {
        let task = Task { await storage.mockFileSizes[url] }
        return try? task.waitForResult()
    }
    
    // MARK: - Test helper methods
    
    /// Reset all tracking arrays and state
    func reset() async {
        await storage.reset()
    }
    
    /// Add a mock file with specified properties
    func addMockFile(at url: URL, size: Int64, checksum: String) async {
        await storage.addMockFile(at: url, size: size, checksum: checksum)
    }
    
    /// Verify that a file was copied from source to destination
    func verifyCopied(from source: URL, to destination: URL) async -> Bool {
        let copies = await storage.copiedFiles
        return copies.contains { $0.source == source && $0.destination == destination }
    }
    
    /// Get count of operations
    var copyCount: Int {
        get async { await storage.copiedFiles.count }
    }
    var directoryCreationCount: Int {
        get async { await storage.createdDirectories.count }
    }
    var removalCount: Int {
        get async { await storage.removedItems.count }
    }
    var checksumCount: Int {
        get async { await storage.checksumCalculations.count }
    }
    
    // Bridge for synchronous property access (for backward compatibility)
    var shouldFailCopy: Bool {
        get { 
            let task = Task { await storage.shouldFailCopy }
            return (try? task.waitForResult()) ?? false
        }
        set {
            Task { await storage.setShouldFailCopy(newValue) }
        }
    }
    
    var shouldFailChecksum: Bool {
        get {
            let task = Task { await storage.shouldFailChecksum }
            return (try? task.waitForResult()) ?? false
        }
        set {
            Task { await storage.setShouldFailChecksum(newValue) }
        }
    }
    
    // Additional accessors for tests
    var mockChecksums: [URL: String] {
        get async { await storage.mockChecksums }
    }
    
    var mockFileSizes: [URL: Int64] {
        get async { await storage.mockFileSizes }
    }
    
    var copiedFiles: [(source: URL, destination: URL)] {
        get async { await storage.copiedFiles }
    }
    
    var createdDirectories: [URL] {
        get async { await storage.createdDirectories }
    }
    
    var removedItems: [URL] {
        get async { await storage.removedItems }
    }
    
    func setMockChecksum(_ checksum: String, for url: URL) async {
        await storage.setMockChecksum(checksum, for: url)
    }
    
    func setMockFileSize(_ size: Int64, for url: URL) async {
        await storage.setMockFileSize(size, for: url)
    }
}

// Extension to help with synchronous bridging
extension Task where Success == Void, Failure == Never {
    func waitForResult() throws {
        // Use RunLoop to wait for async completion
        var completed = false
        Task {
            _ = await self.value
            completed = true
        }
        while !completed {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
    }
}

extension Task where Failure == Never {
    func waitForResult() throws -> Success {
        // Use RunLoop to wait for async completion
        var result: Success!
        var completed = false
        Task { () -> Success in
            let val = await self.value
            result = val
            completed = true
            return val
        }
        while !completed {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
        }
        return result
    }
}