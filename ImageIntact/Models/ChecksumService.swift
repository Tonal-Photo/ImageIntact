//
//  ChecksumService.swift
//  ImageIntact
//
//  Stateless checksum computation extracted from BackupManager (#103, AMUX-17).
//  Wraps OptimizedChecksum.sha256 with iCloud-not-downloaded detection
//  and readability checks, throwing on all failure paths.
//

import Foundation

enum ChecksumService {
    /// SHA-256 checksum of `fileURL` using the project's optimized native implementation.
    ///
    /// Behavior:
    /// - Throws `NSError` (domain `"ImageIntact"`, code `1`) if the file does not exist.
    /// - Throws `NSError` (domain `"ImageIntact"`, code `7`) if the file is in iCloud and not yet downloaded.
    /// - Throws `NSError` (domain `"ImageIntact"`, code `1`) if the file is unreadable.
    /// - Rethrows `ChecksumError` (including `.cancelled`), `CancellationError`, and any
    ///   underlying read failure. The previous size-based fallback was removed — for a
    ///   verification tool, masking a read failure with `"size:%016x"` is a data-integrity
    ///   risk (two different files with the same byte size produce the same fake checksum).
    ///
    /// - Parameters:
    ///   - fileURL: file to hash
    ///   - shouldCancel: cooperative cancellation predicate, polled by the inner reader
    static func sha256(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool
    ) throws -> String {
        // First check if file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw NSError(
                domain: "ImageIntact", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File does not exist: \(fileURL.lastPathComponent)"]
            )
        }

        // Special handling for files that might be in iCloud and not downloaded
        let resourceValues = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
        if let status = resourceValues?.ubiquitousItemDownloadingStatus {
            // Status can be: .current, .downloaded, .notDownloaded
            if status == .notDownloaded {
                ApplicationLogger.shared.warning(
                    "File is in iCloud but not downloaded locally: \(fileURL.lastPathComponent)",
                    category: .app
                )
                throw NSError(
                    domain: "ImageIntact", code: 7,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "File is in iCloud but not downloaded: \(fileURL.lastPathComponent)",
                    ]
                )
            }
        }

        // Check if file is readable
        guard FileManager.default.isReadableFile(atPath: fileURL.path) else {
            throw NSError(
                domain: "ImageIntact", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "File is not readable: \(fileURL.lastPathComponent)"]
            )
        }

        // Use native Swift checksum as primary method for reliability
        return try calculateNative(for: fileURL, shouldCancel: shouldCancel)
    }

    // Native Swift checksum using CryptoKit - delegates to the optimized implementation
    private static func calculateNative(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool
    ) throws -> String {
        do {
            return try OptimizedChecksum.sha256(for: fileURL, shouldCancel: shouldCancel)
        } catch let checksumError as ChecksumError {
            // Never swallow ChecksumError (includes .cancelled) — rethrow immediately
            throw checksumError
        } catch is CancellationError {
            // Never swallow Swift Task cancellation either
            throw ChecksumError.cancelled
        }
        // All other read failures bubble up to the caller as-is. Returning a
        // size-based pseudo-checksum here would silently treat distinct files as
        // identical when reads fail under load — unacceptable for a backup tool.
    }

    /// Async wrapper around `sha256(for:shouldCancel:)` that bridges the synchronous,
    /// blocking SHA-256 read into an `async` context via GCD.
    ///
    /// `Task.detached` would *not* solve cooperative-pool starvation here — detached
    /// tasks still run on the cooperative thread pool (sized to active core count).
    /// GCD's global queues spawn additional threads for blocking work, keeping the
    /// cooperative pool free for other async tasks. See Apple WWDC 2021 — "Swift
    /// concurrency: Behind the scenes".
    ///
    /// Cancellation flows through the explicit `shouldCancel` closure (polled inside
    /// `OptimizedChecksum`), not through Swift Task cancellation. `withTaskCancellationHandler`
    /// is intentionally not used: the closure is opaque to this layer, so there is
    /// nothing to flip on parent-task cancellation; the GCD work completes on its
    /// own polling cadence and the continuation resumes.
    ///
    /// Concurrency note: `DispatchQueue.global` can spawn many threads under high
    /// concurrent load. ImageIntact's backup pipeline bounds concurrent calls to
    /// ≤ N destinations + 1 manifest builder (typically 2-5 concurrent), well under
    /// any GCD thread-explosion threshold.
    ///
    /// Use this from any `async` caller. The synchronous `sha256(for:shouldCancel:)`
    /// remains available for callers that already manage their own thread bridging
    /// (e.g., `BatchFileProcessor`, which runs an entire batch inside a single
    /// `autoreleasepool` to bound peak memory).
    static func sha256Async(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try ChecksumService.sha256(for: fileURL, shouldCancel: shouldCancel)
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
