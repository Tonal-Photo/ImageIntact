//
//  ErrorHandlingProtocol.swift
//  ImageIntact
//
//  Protocols for error handling and retry logic
//

import Foundation

// MARK: - Error Classifier Protocol

/// Protocol for classifying errors
protocol ErrorClassifierProtocol: Sendable {
    static func classify(_ error: Error) -> ErrorCategory
    static func retryStrategy(for error: Error) -> RetryStrategy
    static func userMessage(for error: Error) -> (message: String, action: String?)
    static func isSafeToRetry(_ error: Error) -> Bool
    static func shouldContinueBackup(after error: Error) -> Bool
}

// Make ErrorClassifier conform to protocol
extension ErrorClassifier: ErrorClassifierProtocol {
    // Already implements all required methods
}

// MARK: - Retry Handler Protocol

/// Protocol for retry operations
protocol RetryHandlerProtocol: Actor {
    
    /// Execute an operation with automatic retry on transient failures
    func executeWithRetry<T>(
        operation: String,
        task: @Sendable () async throws -> T
    ) async throws -> T
    
    /// Execute a file copy operation with retry
    func copyFileWithRetry(
        from source: URL,
        to destination: URL,
        fileOperations: FileOperationsProtocol
    ) async throws
    
    /// Execute a file verification with retry
    func verifyFileWithRetry(
        source: URL,
        destination: URL,
        expectedChecksum: String,
        hasher: HashingProtocol
    ) async throws -> Bool
    
    /// Get current retry statistics
    func getStatistics() -> RetryStatistics
    
    /// Reset retry statistics
    func resetStatistics()
}

// Make RetryHandler conform to protocol
extension RetryHandler: RetryHandlerProtocol {
    // Already implements all required methods
}

// MARK: - Mock Implementations for Testing

/// Mock error classifier for testing
/// Uses nonisolated(unsafe) for test-only mutable state
final class MockErrorClassifier: ErrorClassifierProtocol, @unchecked Sendable {

    nonisolated(unsafe) static var mockCategory: ErrorCategory = .transient
    nonisolated(unsafe) static var mockRetryStrategy = RetryStrategy.transientError
    nonisolated(unsafe) static var classifyCallCount = 0

    static func classify(_ error: Error) -> ErrorCategory {
        classifyCallCount += 1
        return mockCategory
    }

    static func retryStrategy(for error: Error) -> RetryStrategy {
        return mockRetryStrategy
    }

    static func userMessage(for error: Error) -> (message: String, action: String?) {
        return ("Test error", "Test action")
    }

    static func isSafeToRetry(_ error: Error) -> Bool {
        return mockCategory == .transient
    }

    static func shouldContinueBackup(after error: Error) -> Bool {
        return mockCategory != .critical
    }

    static func reset() {
        classifyCallCount = 0
        mockCategory = .transient
        mockRetryStrategy = RetryStrategy.transientError
    }
}

/// Mock retry handler for testing
actor MockRetryHandler: RetryHandlerProtocol {
    
    var executeCallCount = 0
    var copyCallCount = 0
    var verifyCallCount = 0
    var shouldFailFirstAttempt = false
    var shouldAlwaysFail = false
    var mockStatistics = RetryStatistics()
    
    func executeWithRetry<T>(
        operation: String,
        task: @Sendable () async throws -> T
    ) async throws -> T {
        executeCallCount += 1
        
        if shouldAlwaysFail {
            throw NSError(domain: "MockError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Mock error for testing"
            ])
        }
        
        if shouldFailFirstAttempt && executeCallCount == 1 {
            throw NSError(domain: "MockError", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Mock transient error"
            ])
        }
        
        return try await task()
    }
    
    func copyFileWithRetry(
        from source: URL,
        to destination: URL,
        fileOperations: FileOperationsProtocol
    ) async throws {
        copyCallCount += 1
        let shouldFail = shouldAlwaysFail

        try await executeWithRetry(operation: "Copy \(source.lastPathComponent)") {
            if !shouldFail {
                // Simulate successful copy
                return
            }
            throw NSError(domain: "MockError", code: -1)
        }
    }
    
    func verifyFileWithRetry(
        source: URL,
        destination: URL,
        expectedChecksum: String,
        hasher: HashingProtocol
    ) async throws -> Bool {
        verifyCallCount += 1
        let shouldFail = shouldAlwaysFail

        return try await executeWithRetry(operation: "Verify \(source.lastPathComponent)") {
            return !shouldFail
        }
    }
    
    func getStatistics() -> RetryStatistics {
        return mockStatistics
    }
    
    func resetStatistics() {
        mockStatistics = RetryStatistics()
        executeCallCount = 0
        copyCallCount = 0
        verifyCallCount = 0
    }
    
    func reset() {
        resetStatistics()
        shouldFailFirstAttempt = false
        shouldAlwaysFail = false
    }
}