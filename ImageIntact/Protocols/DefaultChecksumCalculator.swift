//
//  DefaultChecksumCalculator.swift
//  ImageIntact
//
//  Default implementation using the existing optimized checksum code
//  This preserves all performance optimizations and reliability
//

import Foundation

/// Default checksum calculator using the existing optimized implementation
/// This ensures 100% compatibility with existing checksums
final class DefaultChecksumCalculator: ChecksumCalculatorProtocol, Sendable {
    
    /// Singleton instance for convenience
    static let shared = DefaultChecksumCalculator()
    
    func calculateSHA256(for url: URL, shouldCancel: @escaping @Sendable () -> Bool) async throws -> String {
        // Validate file exists and is readable
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "ImageIntact", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "File not found: \(url.lastPathComponent)"])
        }
        
        // Check for iCloud files
        let resourceValues = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = resourceValues?.ubiquitousItemDownloadingStatus {
            if status == .notDownloaded {
                throw NSError(domain: "ImageIntact", code: 7, 
                             userInfo: [NSLocalizedDescriptionKey: "File is in iCloud but not downloaded: \(url.lastPathComponent)"])
            }
        }
        
        // Check readability
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw NSError(domain: "ImageIntact", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "File not readable: \(url.lastPathComponent)"])
        }
        
        // Use the existing optimized implementation
        // This is critical - we MUST use the exact same implementation
        // to ensure checksums remain consistent
        do {
            return try await withCheckedThrowingContinuation { continuation in
                do {
                    // Call the existing static method that's been thoroughly tested
                    let checksum = try BackupManager.sha256ChecksumStatic(
                        for: url,
                        shouldCancel: shouldCancel()
                    )
                    continuation.resume(returning: checksum)
                } catch {
                    // Convert cancellation to our error type
                    if shouldCancel() {
                        continuation.resume(throwing: ChecksumError.cancelled)
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } catch {
            // Handle cancellation
            if shouldCancel() {
                throw ChecksumError.cancelled
            }
            throw error
        }
    }
    
    /// Verify checksum with detailed error reporting
    func verifyChecksum(for url: URL, expectedChecksum: String, shouldCancel: @escaping @Sendable () -> Bool) async throws -> Bool {
        let actualChecksum = try await calculateSHA256(for: url, shouldCancel: shouldCancel)
        
        // For debugging/logging purposes, we can detect mismatches
        if actualChecksum != expectedChecksum {
            // Log the mismatch but still return false (don't throw)
            // This maintains compatibility with existing verification logic
            print("⚠️ Checksum verification failed for \(url.lastPathComponent)")
            print("   Expected: \(expectedChecksum)")
            print("   Actual:   \(actualChecksum)")
        }
        
        return actualChecksum == expectedChecksum
    }
}

// MARK: - Compatibility Extension

extension DefaultChecksumCalculator {
    /// Direct synchronous method for compatibility with existing code
    /// This wraps the async method for use in synchronous contexts
    func calculateSHA256Sync(for url: URL, shouldCancel: Bool) throws -> String {
        // Use the existing static method directly
        return try BackupManager.sha256ChecksumStatic(
            for: url,
            shouldCancel: shouldCancel
        )
    }
}