//
//  FileOperationsProtocol.swift
//  ImageIntact
//
//  Protocol for abstracting file system operations to enable testing
//

import Foundation

/// Protocol defining file system operations for backup functionality
protocol FileOperationsProtocol {
    /// Copy a file from source to destination
    /// - Parameters:
    ///   - source: Source file URL
    ///   - destination: Destination file URL
    /// - Throws: Error if copy fails
    func copyItem(at source: URL, to destination: URL) async throws
    
    /// Check if a file exists at the given path
    /// - Parameter url: File URL to check
    /// - Returns: true if file exists, false otherwise
    func fileExists(at url: URL) -> Bool
    
    /// Create a directory at the specified URL
    /// - Parameters:
    ///   - url: Directory URL to create
    ///   - createIntermediates: If true, create intermediate directories
    /// - Throws: Error if creation fails
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws
    
    /// Remove an item at the specified URL
    /// - Parameter url: Item URL to remove
    /// - Throws: Error if removal fails
    func removeItem(at url: URL) throws
    
    /// Get file attributes
    /// - Parameter url: File URL
    /// - Returns: Dictionary of file attributes
    /// - Throws: Error if unable to get attributes
    func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any]
    
    /// Calculate SHA256 checksum for a file
    /// - Parameters:
    ///   - url: File URL to checksum
    ///   - shouldCancel: Closure to check if operation should be cancelled
    /// - Returns: SHA256 checksum as hex string
    /// - Throws: Error if checksum calculation fails
    /// Note: This method is kept for compatibility but delegates to ChecksumCalculatorProtocol
    func calculateChecksum(for url: URL, shouldCancel: () -> Bool) async throws -> String
    
    /// Start accessing a security-scoped resource
    /// - Parameter url: Resource URL
    /// - Returns: true if access was granted
    func startAccessingSecurityScopedResource(for url: URL) -> Bool
    
    /// Stop accessing a security-scoped resource
    /// - Parameter url: Resource URL
    func stopAccessingSecurityScopedResource(for url: URL)
    
    /// Get the file size from a URL
    /// - Parameter url: File URL
    /// - Returns: File size in bytes, or nil if unable to determine
    func fileSize(at url: URL) -> Int64?
}

/// Extension to provide convenience methods
extension FileOperationsProtocol {
    /// Check if a directory exists at the given URL
    func directoryExists(at url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileExists(at: url)
        if exists {
            do {
                let attributes = try attributesOfItem(at: url)
                isDirectory = (attributes[.type] as? FileAttributeType) == .typeDirectory ? true : false
            } catch {
                return false
            }
        }
        return exists && isDirectory.boolValue
    }
    
    /// Ensure a directory exists, creating it if necessary
    func ensureDirectoryExists(at url: URL) throws {
        if !directoryExists(at: url) {
            try createDirectory(at: url, withIntermediateDirectories: true)
        }
    }
}