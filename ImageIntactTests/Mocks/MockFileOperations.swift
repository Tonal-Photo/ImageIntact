//
//  MockFileOperations.swift
//  ImageIntactTests
//
//  Mock implementation of FileOperationsProtocol for testing
//

import Foundation
@testable import ImageIntact

/// Mock implementation of FileOperationsProtocol for testing.
///
/// AMUX-232: This mock is exercised concurrently. `DestinationQueue` runs
/// multiple workers, and because the protocol methods are nonisolated, a worker's
/// `await fileOperations.X` runs on the generic executor (off the queue actor) —
/// so two workers mutate this mock's shared state in parallel. Swift collections
/// are not thread-safe; concurrent mutation corrupts their storage and aborts the
/// process (observed crash: `Set.contains` → `doesNotRecognizeSelector` → SIGABRT
/// in `fileExists`). All access to the mutable tracking/configuration state below
/// therefore goes through `stateLock`.
class MockFileOperations: FileOperationsProtocol {

    /// Serializes every access to this mock's mutable state. Recursive so a
    /// subclass override (e.g. SelectiveFailMockFileOperations) can hold it and
    /// still call `super`, and so any future intra-method delegation is safe.
    private let stateLock = NSRecursiveLock()

    @discardableResult
    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return try body()
    }

    // MARK: - Tracking properties for assertions
    var copiedFiles: [(source: URL, destination: URL)] = []
    var createdDirectories: [URL] = []
    var removedItems: [URL] = []
    var trashedItems: [URL] = []
    var checksumCalculations: [URL] = []
    /// AMUX-352: read policy of every policy-aware checksum call, in call order.
    var checksumPolicies: [ChecksumReadPolicy] = []
    var securityScopedAccesses: [URL] = []
    var movedItems: [(source: URL, destination: URL)] = []
    var setAttributesCalls: [(attributes: [FileAttributeKey: Any], url: URL)] = []
    var mockDirectoryContents: [URL: [URL]] = [:]
    var createdFiles: [(url: URL, data: Data?, attributes: [FileAttributeKey: Any]?)] = []

    // MARK: - Configurable behaviors
    var shouldFailCopy = false
    var shouldFailChecksum = false
    var shouldFailCreateFile = false
    var shouldFailTrash = false
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
        case trashFailed
    }

    // MARK: - FileOperationsProtocol implementation

    func copyItem(at source: URL, to destination: URL) async throws {
        try withLock {
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
    }

    func fileExists(at url: URL) -> Bool {
        withLock { filesExist.contains(url) }
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        withLock {
            createdDirectories.append(url)
            filesExist.insert(url)
        }
    }

    func removeItem(at url: URL) throws {
        withLock {
            removedItems.append(url)
            filesExist.remove(url)
            mockFileSizes.removeValue(forKey: url)
            mockChecksums.removeValue(forKey: url)
            mockAttributes.removeValue(forKey: url)
        }
    }

    func trashItem(at url: URL) throws {
        try withLock {
            trashedItems.append(url)
            if shouldFailTrash {
                throw MockError.trashFailed
            }
            // Simulate the trash by removing the file from the exists set.
            filesExist.remove(url)
            mockFileSizes.removeValue(forKey: url)
            mockChecksums.removeValue(forKey: url)
            mockAttributes.removeValue(forKey: url)
        }
    }

    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        withLock {
            if let attributes = mockAttributes[url] {
                return attributes
            }

            // Return default attributes
            var attributes: [FileAttributeKey: Any] = [:]
            attributes[.size] = mockFileSizes[url] ?? 0
            attributes[.type] = filesExist.contains(url) ? FileAttributeType.typeRegular : nil
            return attributes
        }
    }

    func calculateChecksum(
        for url: URL, policy: ChecksumReadPolicy, shouldCancel: @Sendable @escaping () -> Bool
    ) async throws -> String {
        withLock { checksumPolicies.append(policy) }
        // Delegate dynamically so subclass overrides of the 2-arg method
        // (e.g. MockFileOperationsWithCorruption) keep affecting policy-aware
        // callers like the DestinationQueue verify loop.
        return try await calculateChecksum(for: url, shouldCancel: shouldCancel)
    }

    func calculateChecksum(for url: URL, shouldCancel: @Sendable @escaping () -> Bool) async throws -> String {
        try withLock {
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
    }

    func startAccessingSecurityScopedResource(for url: URL) -> Bool {
        withLock {
            securityScopedAccesses.append(url)
            return true
        }
    }

    func stopAccessingSecurityScopedResource(for url: URL) {
        // Just track that this was called
    }

    func fileSize(at url: URL) -> Int64? {
        withLock { mockFileSizes[url] }
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try withLock {
            if shouldFailCopy { throw MockError.copyFailed }
            movedItems.append((source: source, destination: destination))
        }
    }

    func setAttributes(_ attributes: [FileAttributeKey: Any], at url: URL) throws {
        withLock {
            setAttributesCalls.append((attributes: attributes, url: url))
        }
    }

    func contentsOfDirectory(at url: URL, includingPropertiesForKeys keys: [URLResourceKey]?) throws -> [URL] {
        withLock { mockDirectoryContents[url] ?? [] }
    }

    func createFile(at url: URL, contents data: Data?, attributes: [FileAttributeKey: Any]?) -> Bool {
        withLock {
            if shouldFailCreateFile { return false }
            createdFiles.append((url: url, data: data, attributes: attributes))
            filesExist.insert(url)
            return true
        }
    }

    // MARK: - Test helper methods

    /// Reset all tracking arrays and state
    func reset() {
        withLock {
            copiedFiles.removeAll()
            createdDirectories.removeAll()
            removedItems.removeAll()
            checksumCalculations.removeAll()
            checksumPolicies.removeAll()
            securityScopedAccesses.removeAll()

            shouldFailCopy = false
            shouldFailChecksum = false
            shouldFailCreateFile = false
            filesExist.removeAll()
            mockChecksums.removeAll()
            mockFileSizes.removeAll()
            mockAttributes.removeAll()
            movedItems.removeAll()
            setAttributesCalls.removeAll()
            mockDirectoryContents.removeAll()
            createdFiles.removeAll()
        }
    }

    /// Add a mock file with specified properties
    func addMockFile(at url: URL, size: Int64, checksum: String) {
        withLock {
            filesExist.insert(url)
            mockFileSizes[url] = size
            mockChecksums[url] = checksum
        }
    }

    /// Verify that a file was copied from source to destination
    func verifyCopied(from source: URL, to destination: URL) -> Bool {
        withLock { copiedFiles.contains { $0.source == source && $0.destination == destination } }
    }

    /// Get count of operations
    var copyCount: Int { withLock { copiedFiles.count } }
    var directoryCreationCount: Int { withLock { createdDirectories.count } }
    var removalCount: Int { withLock { removedItems.count } }
    var checksumCount: Int { withLock { checksumCalculations.count } }
}
