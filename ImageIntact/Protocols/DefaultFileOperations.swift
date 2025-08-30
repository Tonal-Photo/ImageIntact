//
//  DefaultFileOperations.swift
//  ImageIntact
//
//  Default implementation of FileOperationsProtocol using FileManager
//

import Foundation
import CryptoKit

/// Default implementation of FileOperationsProtocol using system FileManager
class DefaultFileOperations: FileOperationsProtocol {
    
    private let fileManager = FileManager.default
    
    func copyItem(at source: URL, to destination: URL) async throws {
        // Use async wrapper for FileManager operation
        try await withCheckedThrowingContinuation { continuation in
            do {
                try fileManager.copyItem(at: source, to: destination)
                continuation.resume()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
    
    func fileExists(at url: URL) -> Bool {
        return fileManager.fileExists(atPath: url.path)
    }
    
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try fileManager.createDirectory(at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
    }
    
    func removeItem(at url: URL) throws {
        try fileManager.removeItem(at: url)
    }
    
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
        return try fileManager.attributesOfItem(atPath: url.path)
    }
    
    func calculateChecksum(for url: URL, shouldCancel: () -> Bool) async throws -> String {
        // Use the existing static method from BackupManager
        // This maintains compatibility with existing checksum logic
        // Note: sha256ChecksumStatic expects a Bool, so we evaluate the closure
        return try BackupManager.sha256ChecksumStatic(for: url, shouldCancel: shouldCancel())
    }
    
    func startAccessingSecurityScopedResource(for url: URL) -> Bool {
        return url.startAccessingSecurityScopedResource()
    }
    
    func stopAccessingSecurityScopedResource(for url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
    
    func fileSize(at url: URL) -> Int64? {
        do {
            let attributes = try attributesOfItem(at: url)
            return attributes[.size] as? Int64
        } catch {
            return nil
        }
    }
}

/// Singleton instance for convenience
extension DefaultFileOperations {
    static let shared = DefaultFileOperations()
}