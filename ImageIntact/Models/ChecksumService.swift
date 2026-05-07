//
//  ChecksumService.swift
//  ImageIntact
//
//  Stateless checksum computation extracted from BackupManager (#103, AMUX-17).
//  Wraps OptimizedChecksum.sha256 with iCloud-not-downloaded detection and
//  typed error mapping. Pre-existing TOCTOU `fileExists`/`isReadableFile`
//  pre-checks were dropped (#108 items 1+4): the underlying read either
//  succeeds or throws a Cocoa error, which we map to a typed
//  `ChecksumServiceError`. No logging — callers have job context and decide
//  what to log (#108 items 5+6).
//

import Foundation

/// Strongly-typed errors thrown by `ChecksumService`. Replaces the pre-existing
/// `NSError(domain: "ImageIntact", code: 1/7, ...)` pattern from `BackupManager`.
///
/// The associated `URL` lets callers report which file failed without having to
/// preserve it from the call site. `LocalizedError` conformance keeps existing
/// `error.localizedDescription` consumers working.
///
/// `readFailed(URL, Error)` is the catch-all for any underlying read failure that
/// doesn't fit the other cases. Wrapping rather than rethrowing means callers
/// only need to know about `ChecksumServiceError` and `ChecksumError` to handle
/// every failure path — the underlying `Error` is preserved as the associated
/// value for diagnostics or logging.
///
/// `Equatable` is intentionally *not* synthesized: `readFailed`'s associated
/// `Error` doesn't conform to `Equatable`, so manual conformance would have to
/// elide that field. Tests use pattern matching (`case .fileNotFound = error`)
/// which doesn't require `Equatable`.
enum ChecksumServiceError: Error, LocalizedError {
    case fileNotFound(URL)
    case iCloudNotDownloaded(URL)
    case unreadable(URL)
    case readFailed(URL, underlyingError: Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File does not exist: \(url.lastPathComponent)"
        case .iCloudNotDownloaded(let url):
            return "File is in iCloud but not downloaded: \(url.lastPathComponent)"
        case .unreadable(let url):
            return "File is not readable: \(url.lastPathComponent)"
        case .readFailed(let url, let underlying):
            return "Failed to read \(url.lastPathComponent): \(underlying.localizedDescription)"
        }
    }
}

enum ChecksumService {
    /// SHA-256 checksum of `fileURL` using the project's optimized native implementation.
    ///
    /// Throws:
    /// - `ChecksumServiceError.iCloudNotDownloaded(url)` — file is in iCloud but not yet
    ///   downloaded locally. Detected up front via `ubiquitousItemDownloadingStatus`
    ///   resource value (semantic check, not TOCTOU; the underlying read would either
    ///   silently trigger a download or fail with a confusing native error).
    /// - `ChecksumServiceError.fileNotFound(url)` — mapped from
    ///   `NSCocoaErrorDomain` + `NSFileReadNoSuchFileError` raised by the read.
    /// - `ChecksumServiceError.unreadable(url)` — mapped from
    ///   `NSCocoaErrorDomain` + `NSFileReadNoPermissionError` raised by the read.
    /// - `ChecksumError.cancelled` — propagated from `OptimizedChecksum` when the
    ///   `shouldCancel` closure returns true, or when a `CancellationError` is caught
    ///   from the surrounding `Task`.
    /// - Any other `NSError` from the read is rethrown as-is (e.g., I/O errors,
    ///   filesystem corruption).
    ///
    /// The previous size-based fallback (`"size:%016x"`) was removed in PR #107 —
    /// for a verification tool, masking a read failure with a fake hash is a
    /// data-integrity risk (two different files of the same byte size produce the
    /// same fake checksum).
    ///
    /// - Parameters:
    ///   - fileURL: file to hash
    ///   - shouldCancel: cooperative cancellation predicate, polled by the inner reader
    static func sha256(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool
    ) throws -> String {
        // iCloud-not-downloaded check kept explicit because
        // `ubiquitousItemDownloadingStatus` isn't reliably surfaced through a CryptoKit
        // read; without this check the read could either silently trigger an iCloud
        // download or fail with a confusing native error. There's still a tiny
        // (microsecond-scale) TOCTOU window between this check and the read — the OS
        // could begin downloading in that window — but the alternative (no check) is
        // strictly worse for diagnostic clarity.
        if let status = try? fileURL.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus,
            status == .notDownloaded
        {
            throw ChecksumServiceError.iCloudNotDownloaded(fileURL)
        }

        return try calculateNative(for: fileURL, shouldCancel: shouldCancel)
    }

    /// Native Swift checksum via `OptimizedChecksum`. Maps Cocoa file errors to
    /// `ChecksumServiceError`; rethrows cancellation as `ChecksumError.cancelled`.
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
        } catch let nsError as NSError where nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                throw ChecksumServiceError.fileNotFound(fileURL)
            case NSFileReadNoPermissionError:
                throw ChecksumServiceError.unreadable(fileURL)
            default:
                throw ChecksumServiceError.readFailed(fileURL, underlyingError: nsError)
            }
        } catch {
            // Catch-all for any non-Cocoa Error (e.g., POSIXError if a future call site
            // bypasses Foundation wrappers). Wrap rather than rethrow so the caller's
            // contract stays "ChecksumServiceError | ChecksumError | CancellationError".
            throw ChecksumServiceError.readFailed(fileURL, underlyingError: error)
        }
        // Returning a size-based pseudo-checksum here would silently treat distinct
        // files as identical when reads fail under load — unacceptable for a backup
        // tool. Removed in PR #107.
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
    /// Cancellation: this method honors *both* the explicit `shouldCancel` closure
    /// (polled inside `OptimizedChecksum`) and Swift Task cancellation. A parent task
    /// `cancel()` flips a thread-safe flag inside `withTaskCancellationHandler`, and
    /// the flag is OR'd into the cancellation predicate handed to the underlying
    /// reader. Either signal stops the work at the next poll; the resulting
    /// `ChecksumError.cancelled` propagates back to the awaiting caller.
    ///
    /// QoS: the dispatched queue's QoS is mapped from `Task.currentPriority`, so a
    /// background-priority caller doesn't artificially elevate the underlying I/O.
    /// Note: GCD threads do *not* participate in Swift Concurrency's dynamic priority
    /// escalation. If the calling task is later awaited by a higher-priority task,
    /// this work continues at its initial QoS rather than being escalated. Acceptable
    /// for ImageIntact's foreground/userInitiated workload; reconsider if this method
    /// is ever called from low-priority contexts that may be escalated mid-flight.
    ///
    /// Concurrency note: `DispatchQueue.global` can spawn many threads under high
    /// concurrent load. ImageIntact's backup pipeline bounds concurrent calls to
    /// ≤ N destinations + 1 manifest builder (typically 2-5 concurrent), well under
    /// any GCD thread-explosion threshold. If a future caller fires unbounded
    /// concurrent checksums (e.g., a `TaskGroup` over an arbitrary file list), wrap
    /// the call site in a `Semaphore` or migrate this method to a shared
    /// `OperationQueue` with `maxConcurrentOperationCount`.
    ///
    /// Use this from any `async` caller. The synchronous `sha256(for:shouldCancel:)`
    /// remains available for callers that already manage their own thread bridging
    /// (e.g., `BatchFileProcessor`, which runs an entire batch inside a single
    /// `autoreleasepool` to bound peak memory).
    static func sha256Async(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool
    ) async throws -> String {
        let cancelFlag = CancelFlag()
        let qos = Self.dispatchQoS(for: Task.currentPriority)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: qos).async {
                    do {
                        // Compose the user's predicate with our task-cancel flag so
                        // either signal stops the work.
                        let composed: @Sendable () -> Bool = {
                            shouldCancel() || cancelFlag.isSet
                        }
                        let result = try ChecksumService.sha256(
                            for: fileURL, shouldCancel: composed
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: {
            cancelFlag.set()
        }
    }

    /// Map a Swift `_Concurrency.TaskPriority` to the closest `DispatchQoS.QoSClass`.
    /// Preserves caller-context priority across the GCD bridge instead of artificially
    /// elevating background work to `.userInitiated`. The fully-qualified type is
    /// required because ImageIntact has its own internal `TaskPriority` type that
    /// would otherwise shadow the standard library one in this scope.
    private static func dispatchQoS(for priority: _Concurrency.TaskPriority) -> DispatchQoS.QoSClass {
        switch priority {
        case .high: return .userInitiated
        case .userInitiated: return .userInitiated
        case .medium: return .default
        case .low, .utility: return .utility
        case .background: return .background
        default: return .default
        }
    }
}

/// Thread-safe boolean used to bridge Swift Task cancellation into the polling
/// closure consumed by `OptimizedChecksum`.
private final class CancelFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()

    var isSet: Bool {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock(); defer { lock.unlock() }
        value = true
    }
}
