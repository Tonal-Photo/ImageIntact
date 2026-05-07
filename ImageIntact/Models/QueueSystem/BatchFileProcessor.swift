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

    /// Calculate checksums for multiple files in a batch
    func batchCalculateChecksums(
        _ files: [URL],
        shouldCancel: @escaping () -> Bool
    ) async throws -> [URL: String] {
        var results = [URL: String]()

        for batch in files.chunked(into: batchSize) {
            // Bridge synchronous batch hashing to async via GCD. Two reasons it can't
            // run inline on the actor's executor:
            //   1. Hashing is synchronous CPU/IO — it would block every other actor
            //      message (including cancellation) for the full batch duration.
            //   2. Task.detached doesn't help: detached tasks still consume slots on
            //      the limited cooperative pool. GCD's global queues spawn extra
            //      threads for blocking work.
            // Per-file errors are caught inside the loop so one unreadable file no
            // longer aborts the whole batch — readable files still produce checksums,
            // unreadable files are omitted from the result dict (callers like
            // ManifestBuilder already handle missing entries via `onFileError`).
            // ChecksumError.cancelled and CancellationError still abort the batch
            // (with whatever has been hashed so far) to preserve cancellation semantics.
            let batchResults: [URL: String] = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<[URL: String], Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    autoreleasepool {
                        var batchChecksums = [URL: String]()
                        for file in batch {
                            guard !shouldCancel() else {
                                continuation.resume(returning: batchChecksums)
                                return
                            }
                            do {
                                let checksum = try ChecksumService.sha256(
                                    for: file,
                                    shouldCancel: shouldCancel
                                )
                                batchChecksums[file] = checksum
                            } catch ChecksumError.cancelled {
                                continuation.resume(returning: batchChecksums)
                                return
                            } catch is CancellationError {
                                continuation.resume(returning: batchChecksums)
                                return
                            } catch {
                                ApplicationLogger.shared.warning(
                                    "Skipping \(file.lastPathComponent) — checksum failed: \(error.localizedDescription)",
                                    category: .fileSystem
                                )
                                // Omit this file from results; caller's missing-checksum
                                // path takes over.
                                continue
                            }
                        }
                        continuation.resume(returning: batchChecksums)
                    }
                }
            }

            // Merge batch results
            results.merge(batchResults) { _, new in new }

            // Check cancellation between batches
            guard !shouldCancel() else {
                throw CancellationError()
            }
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
