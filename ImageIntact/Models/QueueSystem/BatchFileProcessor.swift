//
//  BatchFileProcessor.swift
//  ImageIntact
//
//  Batch file operations for improved memory efficiency
//

import Foundation

/// Processes files in batches for better memory efficiency
actor BatchFileProcessor {
    // MARK: - URL Cache

    private var urlCache = [String: URL]()
    private let maxCacheSize = 1000

    // MARK: - Buffer Pool

    private var bufferPool: [Data] = []
    private let bufferSize = 4 * 1024 * 1024 // 4MB buffers for better disk I/O
    private let maxBuffers = 4

    // MARK: - Batch Configuration

    private let batchSize = 50 // Process 50 files at a time

    init() {
        // Pre-allocate buffers
        for _ in 0 ..< maxBuffers {
            bufferPool.append(Data(capacity: bufferSize))
        }
    }

    // MARK: - URL Caching

    /// Get a cached URL or create a new one
    func getCachedURL(for path: String) -> URL {
        if let cached = urlCache[path] {
            return cached
        }

        let url = URL(fileURLWithPath: path)

        // Limit cache size
        if urlCache.count >= maxCacheSize {
            // Remove oldest entries (simple FIFO)
            let toRemove = urlCache.count / 4
            urlCache = Dictionary(
                uniqueKeysWithValues:
                urlCache.dropFirst(toRemove).map { ($0.key, $0.value) })
        }

        urlCache[path] = url
        return url
    }

    /// Clear the URL cache to free memory
    func clearURLCache() {
        urlCache.removeAll(keepingCapacity: true)
    }

    // MARK: - Buffer Management

    /// Get a buffer from the pool
    func borrowBuffer() -> Data {
        if !bufferPool.isEmpty {
            return bufferPool.removeLast()
        }
        // Create new buffer if pool is empty
        return Data(capacity: bufferSize)
    }

    /// Return a buffer to the pool
    func returnBuffer(_ buffer: Data) {
        if bufferPool.count < maxBuffers {
            var reusableBuffer = buffer
            reusableBuffer.removeAll(keepingCapacity: true)
            bufferPool.append(reusableBuffer)
        }
    }

    // MARK: - Batch Processing

    /// Process files in batches
    func processBatch<T>(
        _ files: [T],
        batchOperation: @escaping ([T]) async throws -> Void
    ) async throws {
        for batch in files.chunked(into: batchSize) {
            try await batchOperation(batch)
        }
    }

    // MARK: - Batch Checksum Calculation

    /// Calculate checksums for multiple files in a batch.
    ///
    /// Returns a dictionary keyed by every input URL that was *processed*, with the
    /// value being either the computed checksum (`.success`) or the typed error raised
    /// while computing it (`.failure`). URLs that weren't processed because cancellation
    /// fired mid-batch are *absent* from the returned dict — callers detect partial
    /// completion either by comparing keys against the input list or by checking
    /// `shouldCancel()` after the call returns. This is the existing pattern at the
    /// only production caller (`ManifestBuilder.build`).
    ///
    /// The function does **not** throw. Per-file errors are surfaced as `.failure`
    /// entries; cancellation halts the run and returns whatever was collected. This
    /// is a deliberate departure from Swift's structured-concurrency cancellation
    /// pattern (which would expect this function to rethrow `CancellationError`):
    /// for a backup tool, the caller wants to know *what was hashed* before being
    /// told that the rest didn't get done. Throwing would discard the partial
    /// progress. The caller (ManifestBuilder) handles cancellation explicitly via
    /// its own `shouldCancel()` guard.
    ///
    /// This Result-typed contract replaces a previous "successful results only,
    /// infer failures from missing keys" shape (#108 item 7).
    func batchCalculateChecksums(
        _ files: [URL],
        shouldCancel: @escaping () -> Bool
    ) async -> [URL: Result<String, Error>] {
        var results = [URL: Result<String, Error>]()

        for batch in files.chunked(into: batchSize) {
            // Bridge synchronous batch hashing to async via GCD. Two reasons it can't
            // run inline on the actor's executor:
            //   1. Hashing is synchronous CPU/IO — it would block every other actor
            //      message (including cancellation) for the full batch duration.
            //   2. Task.detached doesn't help: detached tasks still consume slots on
            //      the limited cooperative pool. GCD's global queues spawn extra
            //      threads for blocking work.
            let batchResults: [URL: Result<String, Error>] = await withCheckedContinuation {
                (continuation: CheckedContinuation<[URL: Result<String, Error>], Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    autoreleasepool {
                        var batchResults = [URL: Result<String, Error>]()
                        for file in batch {
                            guard !shouldCancel() else {
                                continuation.resume(returning: batchResults)
                                return
                            }
                            do {
                                let checksum = try ChecksumService.sha256(
                                    for: file,
                                    shouldCancel: shouldCancel
                                )
                                batchResults[file] = .success(checksum)
                            } catch ChecksumError.cancelled {
                                // Inner cancellation: stop processing this batch but
                                // preserve whatever was hashed so far.
                                continuation.resume(returning: batchResults)
                                return
                            } catch is CancellationError {
                                continuation.resume(returning: batchResults)
                                return
                            } catch {
                                // Per-file failure: record the typed error and continue
                                // so one bad file doesn't abort the rest of the batch.
                                batchResults[file] = .failure(error)
                            }
                        }
                        continuation.resume(returning: batchResults)
                    }
                }
            }

            // Merge batch results
            results.merge(batchResults) { _, new in new }

            // Cancellation between batches: stop iterating and return what we have.
            // Caller distinguishes "cancelled" from "completed" via shouldCancel().
            if shouldCancel() { return results }
        }

        return results
    }
}

// MARK: - Helper Extensions

extension Array {
    /// Split array into chunks of specified size
    func chunked(into size: Int) -> [[Element]] {
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}

struct CancellationError: Error {
    var localizedDescription: String {
        "Operation was cancelled"
    }
}
