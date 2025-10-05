import Foundation
import CryptoKit

/// Protocol abstraction for file hashing operations
protocol HashingProtocol: Sendable {
    func sha256(for url: URL, shouldCancel: @escaping @Sendable () -> Bool) async throws -> String
    func sha256(for data: Data) -> String
}

/// Real implementation using CryptoKit
final class RealHasher: HashingProtocol, Sendable {
    
    func sha256(for url: URL, shouldCancel: @escaping @Sendable () -> Bool) async throws -> String {
        // Use the existing static method from BackupManager
        // Note: The static method takes a Bool, not a closure, so we evaluate it once
        return try BackupManager.sha256ChecksumStatic(for: url, shouldCancel: shouldCancel())
    }
    
    func sha256(for data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}

/// Mock implementation for testing
final class MockHasher: HashingProtocol, @unchecked Sendable {
    
    var mockHashes: [URL: String] = [:]
    var shouldFail = false
    var callCount = 0
    var lastHashedURL: URL?
    
    /// Predefined hashes for known test content
    private let knownHashes: [String: String] = [
        "test": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
        "hello": "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
        "world": "486ea46224d1bb4fb680f34f7c9ad96a8f24ec88be73ea8e5a6c65260e9cb8a7",
        "test content": "5e3235c8c94e703870cf3a39317c8eb09158ce221e36e29b5dd0f921ffa22c6f"
    ]
    
    func sha256(for url: URL, shouldCancel: @escaping @Sendable () -> Bool) async throws -> String {
        callCount += 1
        lastHashedURL = url
        
        // Check for cancellation
        if shouldCancel() {
            throw NSError(domain: "MockHasher", code: 1, userInfo: [NSLocalizedDescriptionKey: "Operation cancelled"])
        }
        
        if shouldFail {
            throw NSError(domain: "MockHasher", code: 2, userInfo: [NSLocalizedDescriptionKey: "Mock hash failed"])
        }
        
        // Return mock hash if set
        if let mockHash = mockHashes[url] {
            return mockHash
        }
        
        // Try to read file content and return known hash
        if let data = try? Data(contentsOf: url),
           let content = String(data: data, encoding: .utf8),
           let knownHash = knownHashes[content] {
            return knownHash
        }
        
        // Generate deterministic hash based on URL
        return generateDeterministicHash(for: url.lastPathComponent)
    }
    
    func sha256(for data: Data) -> String {
        callCount += 1
        
        // Check if this is known content
        if let content = String(data: data, encoding: .utf8),
           let knownHash = knownHashes[content] {
            return knownHash
        }
        
        // Generate hash from data
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generate a deterministic hash for testing based on filename
    private func generateDeterministicHash(for filename: String) -> String {
        let data = Data(filename.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // Test helper methods
    func reset() {
        mockHashes.removeAll()
        shouldFail = false
        callCount = 0
        lastHashedURL = nil
    }
    
    func setMockHash(_ hash: String, for url: URL) {
        mockHashes[url] = hash
    }
    
    func setMockHash(_ hash: String, for path: String) {
        mockHashes[URL(fileURLWithPath: path)] = hash
    }
}