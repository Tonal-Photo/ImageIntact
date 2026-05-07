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
}
