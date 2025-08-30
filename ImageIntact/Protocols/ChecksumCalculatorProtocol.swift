//
//  ChecksumCalculatorProtocol.swift
//  ImageIntact
//
//  Protocol for checksum calculation - critical for data integrity
//  IMPORTANT: Any implementation MUST produce identical checksums for identical files
//

import Foundation

/// Protocol defining checksum calculation operations
/// WARNING: Checksum accuracy is critical for data integrity. 
/// Any implementation MUST produce bit-identical results to the default implementation.
protocol ChecksumCalculatorProtocol {
    
    /// Calculate SHA256 checksum for a file
    /// - Parameters:
    ///   - url: File URL to calculate checksum for
    ///   - shouldCancel: Closure to check if operation should be cancelled
    /// - Returns: SHA256 checksum as lowercase hex string
    /// - Throws: Error if checksum calculation fails
    /// 
    /// IMPORTANT: The returned checksum MUST be:
    /// 1. Lowercase hexadecimal string
    /// 2. Exactly 64 characters for SHA256
    /// 3. Deterministic - same file always produces same checksum
    /// 4. Match the output of standard SHA256 implementations
    func calculateSHA256(for url: URL, shouldCancel: @escaping () -> Bool) async throws -> String
    
    /// Verify that a file matches an expected checksum
    /// - Parameters:
    ///   - url: File URL to verify
    ///   - expectedChecksum: Expected checksum value
    ///   - shouldCancel: Closure to check if operation should be cancelled
    /// - Returns: true if checksums match, false otherwise
    /// - Throws: Error if verification fails (not for mismatch, but for I/O errors)
    func verifyChecksum(for url: URL, expectedChecksum: String, shouldCancel: @escaping () -> Bool) async throws -> Bool
}

// MARK: - Default Implementation

extension ChecksumCalculatorProtocol {
    /// Default verification implementation using calculateSHA256
    func verifyChecksum(for url: URL, expectedChecksum: String, shouldCancel: @escaping () -> Bool) async throws -> Bool {
        let actualChecksum = try await calculateSHA256(for: url, shouldCancel: shouldCancel)
        return actualChecksum == expectedChecksum
    }
}

// Note: ChecksumError is defined in OptimizedChecksum.swift