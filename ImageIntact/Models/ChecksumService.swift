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
    ///   downloaded locally. Detected up front via `ubiquitousItemDownloadingStatus`.
    ///   Tiny TOCTOU window between the check and the read is acceptable — the
    ///   alternative (no check) is strictly worse for diagnostic clarity.
    /// - `ChecksumServiceError.fileNotFound(url)` — mapped from
    ///   `NSCocoaErrorDomain` + `NSFileReadNoSuchFileError` raised by the read.
    /// - `ChecksumServiceError.unreadable(url)` — mapped from
    ///   `NSCocoaErrorDomain` + `NSFileReadNoPermissionError` raised by the read.
    /// - `ChecksumServiceError.readFailed(url, underlyingError:)` — catch-all wrapper
    ///   around any other read failure (corrupt file, I/O error, POSIX error from a
    ///   future call site that bypasses Foundation). Underlying error is preserved
    ///   for diagnostics.
    /// - `ChecksumError.cancelled` — propagated from `OptimizedChecksum` when the
    ///   `shouldCancel` closure returns true.
    /// - `CancellationError` — propagated as-is from a cancelled parent `Task` to
    ///   preserve Swift structured-concurrency semantics. (Wrapping it as a
    ///   domain-specific error would cause `TaskGroup` siblings to treat it as a
    ///   regular failure rather than cooperative cancellation.)
    ///
    /// The previous size-based fallback (`"size:%016x"`) was removed in PR #107 —
    /// for a verification tool, masking a read failure with a fake hash is a
    /// data-integrity risk (two different files of the same byte size produce the
    /// same fake checksum).
    ///
    /// - Parameters:
    ///   - fileURL: file to hash
    ///   - policy: cache policy for the read — `.verification` flushes the file
    ///     to the medium and bypasses the page cache so the hash attests bytes
    ///     on the destination device (AMUX-352 / gh#134); `.standard` (default)
    ///     keeps the cached fast paths for manifest/copy-phase work
    ///   - shouldCancel: cooperative cancellation predicate, polled by the inner reader
    static func sha256(
        for fileURL: URL, policy: ChecksumReadPolicy = .standard,
        shouldCancel: @Sendable @escaping () -> Bool
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

        return try calculateNative(for: fileURL, policy: policy, shouldCancel: shouldCancel)
    }

    /// Native Swift checksum via `OptimizedChecksum`. Maps Cocoa file errors to
    /// `ChecksumServiceError`; rethrows cancellation as `ChecksumError.cancelled`.
    private static func calculateNative(
        for fileURL: URL, policy: ChecksumReadPolicy,
        shouldCancel: @Sendable @escaping () -> Bool
    ) throws -> String {
        do {
            return try OptimizedChecksum.sha256(for: fileURL, policy: policy, shouldCancel: shouldCancel)
        } catch let checksumError as ChecksumError {
            // Never swallow ChecksumError (includes .cancelled) — rethrow immediately
            throw checksumError
        } catch let cancellation as _Concurrency.CancellationError {
            // Qualified (AMUX-353): ImageIntact declares its own
            // CancellationError (BatchFileProcessor.swift) which shadows the
            // stdlib type in this scope — the unqualified name silently
            // matched the wrong type, sending real task cancellation to the
            // readFailed catch-all below.
            // Rethrow Swift's structured-concurrency cancellation as-is. Wrapping it
            // as ChecksumError.cancelled would cause a parent TaskGroup to treat it
            // as a regular failure rather than cooperative cancellation, which would
            // not unwind sibling tasks correctly.
            throw cancellation
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

    /// Shared, bounded queue for all blocking checksum reads (gh#111 item 1).
    /// Encapsulating the limit here means an unbounded caller (e.g. a future
    /// `TaskGroup` over an arbitrary file list) queues work instead of forcing
    /// GCD to spawn a thread per blocking call. Trade-off, accepted in gh#111:
    /// `ChecksumService` is no longer a stateless namespace — the queue is
    /// module-scoped *scheduling* state, not data state. Internal (not
    /// private) so tests can lock the bound and the name.
    static let ioQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.imageintact.checksum.io"
        queue.maxConcurrentOperationCount = ProcessInfo.processInfo.activeProcessorCount
        return queue
    }()

    /// Async wrapper around `sha256(for:policy:shouldCancel:)` that bridges the
    /// synchronous, blocking SHA-256 read into an `async` context via the shared
    /// bounded `ioQueue`.
    ///
    /// `Task.detached` would *not* solve cooperative-pool starvation here — detached
    /// tasks still run on the cooperative thread pool (sized to active core count).
    /// The OperationQueue runs blocking work on its own threads, keeping the
    /// cooperative pool free for other async tasks, and unlike `DispatchQueue.global`
    /// it caps concurrent blocking reads at `activeProcessorCount` (gh#111 item 1).
    ///
    /// Fail-fast: an already-cancelled caller throws `CancellationError` before any
    /// continuation allocation or queue hop (gh#111 item 2). Mid-flight cancellation
    /// is unchanged: a parent task `cancel()` flips a thread-safe flag inside
    /// `withTaskCancellationHandler`, the flag is OR'd into the cancellation
    /// predicate handed to the underlying reader, and the work surfaces
    /// `ChecksumError.cancelled` at the next poll.
    ///
    /// QoS: each `BlockOperation`'s `qualityOfService` is mapped from
    /// `Task.currentPriority`, so a background-priority caller doesn't artificially
    /// elevate the underlying I/O. Note: queue threads do *not* participate in Swift
    /// Concurrency's dynamic priority escalation. If the calling task is later
    /// awaited by a higher-priority task, this work continues at its initial QoS
    /// rather than being escalated. Acceptable for ImageIntact's
    /// foreground/userInitiated workload; reconsider if this method is ever called
    /// from low-priority contexts that may be escalated mid-flight.
    ///
    /// Use this from any `async` caller. The synchronous `sha256(for:shouldCancel:)`
    /// remains available for callers that already manage their own thread bridging
    /// (e.g., `BatchFileProcessor`, which runs an entire batch inside a single
    /// `autoreleasepool` to bound peak memory).
    static func sha256Async(
        for fileURL: URL, policy: ChecksumReadPolicy = .standard,
        shouldCancel: @Sendable @escaping () -> Bool
    ) async throws -> String {
        // Fail fast if the caller is already cancelled (gh#111 item 2): skips
        // the continuation allocation, the queue hop, and a thread wake.
        // CancellationError (not ChecksumError.cancelled) preserves
        // structured-concurrency semantics for TaskGroup parents.
        try Task.checkCancellation()

        let cancelFlag = CancelFlag()
        let qos = Self.operationQoS(for: Task.currentPriority)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let operation = BlockOperation {
                    do {
                        // Compose the user's predicate with our task-cancel flag so
                        // either signal stops the work.
                        let composed: @Sendable () -> Bool = {
                            shouldCancel() || cancelFlag.isSet
                        }
                        let result = try ChecksumService.sha256(
                            for: fileURL, policy: policy, shouldCancel: composed
                        )
                        continuation.resume(returning: result)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
                // Operations are never op.cancel()ed: a queued-but-cancelled
                // call still runs, polls the flag, and throws quickly — so the
                // continuation is resumed exactly once, never leaked.
                operation.qualityOfService = qos
                ioQueue.addOperation(operation)
            }
        } onCancel: {
            cancelFlag.set()
        }
    }

    /// Map a Swift `_Concurrency.TaskPriority` to the closest Foundation
    /// `QualityOfService` for operations on the shared `ioQueue`. Preserves
    /// caller-context priority across the queue hop instead of artificially
    /// elevating background work to `.userInitiated`. The fully-qualified type is
    /// required because ImageIntact has its own internal `TaskPriority` type that
    /// would otherwise shadow the standard library one in this scope.
    private static func operationQoS(for priority: _Concurrency.TaskPriority) -> QualityOfService {
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
