//
//  ChecksumService.swift
//  ImageIntact
//
//  Stateless checksum computation extracted from BackupManager (#103, AMUX-17).
//  Wraps OptimizedChecksum.sha256 with iCloud-not-downloaded detection,
//  readability checks, and a size-hash fallback.
//

import Foundation

enum ChecksumService {
    /// SHA-256 checksum of `fileURL` using the project's optimized native implementation.
    ///
    /// Behavior:
    /// - Throws `NSError` (domain `"ImageIntact"`, code `1`) if the file does not exist.
    /// - Throws `NSError` (domain `"ImageIntact"`, code `7`) if the file is in iCloud and not yet downloaded.
    /// - Throws `NSError` (domain `"ImageIntact"`, code `1`) if the file is unreadable.
    /// - Falls back to `"size:%016x"` if the underlying read fails for any other reason
    ///   (and a size attribute is available); rethrows otherwise.
    /// - Rethrows `ChecksumError` (including `.cancelled`) and `CancellationError` directly.
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
                logWarning("File is in iCloud but not downloaded locally: \(fileURL.lastPathComponent)")
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

    // Native Swift checksum using CryptoKit - now with optimized implementation
    private static func calculateNative(
        for fileURL: URL, shouldCancel: @Sendable @escaping () -> Bool = { false }
    ) throws -> String {
        // Use the optimized checksum implementation for better performance
        do {
            return try OptimizedChecksum.sha256(for: fileURL, shouldCancel: shouldCancel)
        } catch let checksumError as ChecksumError {
            // Never swallow ChecksumError (includes .cancelled) — rethrow immediately
            throw checksumError
        } catch is CancellationError {
            // Never swallow Swift Task cancellation either
            throw ChecksumError.cancelled
        } catch {
            // Fall back to size-based checksum if file can't be read
            if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attributes[.size] as? Int64
            {
                let sizeHash = String(format: "%016x", size)
                return "size:\(sizeHash)"
            }
            throw error
        }
    }
}
