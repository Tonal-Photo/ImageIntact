//
//  RetryHandler.swift
//  ImageIntact
//
//  Handles retry logic for failed operations
//

import Foundation

/// Statistics about retry operations
struct RetryStatistics {
  var totalRetries: Int = 0
  var successfulRetries: Int = 0
  var failedRetries: Int = 0
  var retriesByErrorType: [String: Int] = [:]

  var successRate: Double {
    guard totalRetries > 0 else { return 0 }
    return Double(successfulRetries) / Double(totalRetries)
  }
}

/// Handles retry logic with exponential backoff
actor RetryHandler {

  // MARK: - Properties

  private var statistics = RetryStatistics()
  private let maxConcurrentRetries = 3
  private var activeRetries = 0

  // MARK: - Public Methods

  /// Execute an operation with automatic retry on transient failures
  func executeWithRetry<T>(
    operation: String,
    task: () async throws -> T
  ) async throws -> T {
    let strategy = RetryStrategy.transientError
    var lastError: Error?

    for attempt in 1...strategy.maxAttempts {
      do {
        // Wait if we have too many concurrent retries
        while activeRetries >= maxConcurrentRetries {
          try await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second
        }

        activeRetries += 1
        defer { activeRetries -= 1 }

        // Try the operation
        let result = try await task()

        // Success on retry
        if attempt > 1 {
          statistics.successfulRetries += 1
          print("✅ Retry successful for \(operation) after \(attempt) attempts")
        }

        return result

      } catch {
        lastError = error

        // Check if we should retry
        let shouldRetry = ErrorClassifier.isSafeToRetry(error) && attempt < strategy.maxAttempts

        if shouldRetry {
          let delay = strategy.delay(for: attempt)
          print(
            "⚠️ \(operation) failed (attempt \(attempt)/\(strategy.maxAttempts)): \(error.localizedDescription)"
          )
          print("   Retrying in \(String(format: "%.1f", delay)) seconds...")

          // Record retry attempt
          statistics.totalRetries += 1
          let errorType = String(describing: type(of: error))
          statistics.retriesByErrorType[errorType, default: 0] += 1

          // Wait before retry with exponential backoff
          try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } else {
          // No retry - either permanent error or max attempts reached
          if attempt > 1 {
            statistics.failedRetries += 1
            print("❌ Retry failed for \(operation) after \(attempt) attempts")
          }
          throw error
        }
      }
    }

    // Exhausted all retries
    if let error = lastError {
      statistics.failedRetries += 1
      throw error
    } else {
      throw NSError(
        domain: "RetryHandler", code: -1,
        userInfo: [
          NSLocalizedDescriptionKey: "Operation failed after \(strategy.maxAttempts) attempts"
        ])
    }
  }

  /// Execute a file copy operation with retry
  func copyFileWithRetry(
    from source: URL,
    to destination: URL,
    fileOperations: FileOperationsProtocol
  ) async throws {
    try await executeWithRetry(operation: "Copy \(source.lastPathComponent)") {
      // Ensure destination directory exists
      let destDir = destination.deletingLastPathComponent()
      if !fileOperations.fileExists(at: destDir) {
        try fileOperations.createDirectory(at: destDir, withIntermediateDirectories: true)
      }

      // Attempt the copy
      try await fileOperations.copyItem(at: source, to: destination)
    }
  }

  /// Execute a file verification with retry
  func verifyFileWithRetry(
    source: URL,
    destination: URL,
    expectedChecksum: String,
    hasher: HashingProtocol
  ) async throws -> Bool {
    try await executeWithRetry(operation: "Verify \(source.lastPathComponent)") {
      let actualChecksum = try await hasher.sha256(for: destination, shouldCancel: { false })
      return actualChecksum == expectedChecksum
    }
  }

  /// Get current retry statistics
  func getStatistics() -> RetryStatistics {
    return statistics
  }

  /// Reset retry statistics
  func resetStatistics() {
    statistics = RetryStatistics()
  }

  // MARK: - Batch Retry

  /// Retry a batch of failed operations
  func retryFailedBatch<T>(
    _ failedItems: [(item: T, error: Error)],
    operation: (T) async throws -> Void
  ) async -> [(item: T, error: Error)] {
    var stillFailed: [(item: T, error: Error)] = []

    for (item, originalError) in failedItems {
      // Only retry transient errors
      guard ErrorClassifier.isSafeToRetry(originalError) else {
        stillFailed.append((item, originalError))
        continue
      }

      do {
        try await operation(item)
        statistics.successfulRetries += 1
      } catch {
        stillFailed.append((item, error))
        statistics.failedRetries += 1
      }
    }

    return stillFailed
  }
}

// MARK: - Global Retry Handler

extension RetryHandler {
  /// Shared retry handler instance
  static let shared = RetryHandler()
}
