//
//  MockChecksumCalculator.swift
//  ImageIntactTests
//
//  Mock implementation for testing - NOT for production use
//  WARNING: This mock does NOT produce real SHA256 checksums
//

import Foundation
@testable import ImageIntact

/// Mock checksum calculator for testing
/// WARNING: This does NOT calculate real checksums - only for testing!
class MockChecksumCalculator: ChecksumCalculatorProtocol {
    
    // MARK: - Configuration
    
    /// Predefined checksums to return for specific files
    var mockChecksums: [URL: String] = [:]
    
    /// If true, all calculations will fail
    var shouldFailCalculation = false
    
    /// If true, simulates cancellation
    var shouldSimulateCancellation = false
    
    /// Track calculation attempts for assertions
    var calculationAttempts: [(url: URL, timestamp: Date)] = []
    
    /// Track verification attempts
    var verificationAttempts: [(url: URL, expected: String, timestamp: Date)] = []
    
    // MARK: - ChecksumCalculatorProtocol
    
    func calculateSHA256(for url: URL, shouldCancel: @escaping () -> Bool) async throws -> String {
        // Track the attempt
        calculationAttempts.append((url: url, timestamp: Date()))
        
        // Simulate cancellation if configured
        if shouldSimulateCancellation || shouldCancel() {
            throw ChecksumError.cancelled
        }
        
        // Simulate failure if configured
        if shouldFailCalculation {
            throw ChecksumError.readError("Mock read error for \(url.lastPathComponent)")
        }
        
        // Return mock checksum if configured
        if let mockChecksum = mockChecksums[url] {
            return mockChecksum
        }
        
        // Generate a deterministic fake checksum based on filename
        // This ensures the same file always gets the same mock checksum
        return generateMockChecksum(for: url)
    }
    
    func verifyChecksum(for url: URL, expectedChecksum: String, shouldCancel: @escaping () -> Bool) async throws -> Bool {
        // Track the attempt
        verificationAttempts.append((url: url, expected: expectedChecksum, timestamp: Date()))
        
        // Calculate the mock checksum
        let actualChecksum = try await calculateSHA256(for: url, shouldCancel: shouldCancel)
        
        // Compare checksums
        return actualChecksum == expectedChecksum
    }
    
    // MARK: - Helper Methods
    
    /// Generate a deterministic mock checksum
    private func generateMockChecksum(for url: URL) -> String {
        let filename = url.lastPathComponent
        // Create a fake but deterministic checksum
        // Format: "mock_" + first 8 chars of filename hash + padding
        let hashBase = "mock_\(filename.hashValue)"
        let padding = String(repeating: "0", count: 64 - min(hashBase.count, 64))
        return String((hashBase + padding).prefix(64))
    }
    
    /// Configure a specific checksum for a file
    func setMockChecksum(_ checksum: String, for url: URL) {
        mockChecksums[url] = checksum
    }
    
    /// Reset all state
    func reset() {
        mockChecksums.removeAll()
        shouldFailCalculation = false
        shouldSimulateCancellation = false
        calculationAttempts.removeAll()
        verificationAttempts.removeAll()
    }
    
    /// Verify that checksum was calculated for a specific file
    func wasChecksumCalculated(for url: URL) -> Bool {
        return calculationAttempts.contains { $0.url == url }
    }
    
    /// Get number of calculation attempts
    var calculationCount: Int {
        return calculationAttempts.count
    }
    
    /// Get number of verification attempts
    var verificationCount: Int {
        return verificationAttempts.count
    }
    
    // MARK: - Test Helpers for Realistic Mocking
    
    /// Generate a realistic-looking SHA256 checksum (64 hex chars)
    static func generateRealisticChecksum() -> String {
        let chars = "0123456789abcdef"
        return String((0..<64).map { _ in chars.randomElement()! })
    }
    
    /// Set up mock checksums for a set of test files
    func setupTestFiles(_ files: [(url: URL, checksum: String)]) {
        for (url, checksum) in files {
            mockChecksums[url] = checksum
        }
    }
}