//
//  DefaultFileOperations.swift
//  ImageIntact
//
//  Default implementation of FileOperationsProtocol using FileManager
//

import CryptoKit
import Foundation

/// Default implementation of FileOperationsProtocol using system FileManager
/// Uses NSFileCoordinator for network volumes to ensure data integrity
class DefaultFileOperations: FileOperationsProtocol {

  private let fileManager = FileManager.default
  private let fileCoordinator = NSFileCoordinator(filePresenter: nil)

  func copyItem(at source: URL, to destination: URL) async throws {
    // Check if source is a symbolic link
    var isSymlink = false
    if let resourceValues = try? source.resourceValues(forKeys: [.isSymbolicLinkKey]) {
      isSymlink = resourceValues.isSymbolicLink ?? false
    }

    if isSymlink {
      // Silently skip symlinks - they should have been filtered during manifest building
      // This is just a safety check. Log for debugging but don't throw user-visible error
      print("🔗 Skipping symbolic link during copy (safety check): \(source.lastPathComponent)")
      return  // Return successfully without copying
    }

    // Check if we need file coordination for network volumes
    if isNetworkVolume(url: source) || isNetworkVolume(url: destination) {
      try await coordinatedCopy(from: source, to: destination)
    } else {
      // Use standard copy for local volumes
      try await withCheckedThrowingContinuation { continuation in
        do {
          try fileManager.copyItem(at: source, to: destination)
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  /// Check if a URL is on a network volume
  private func isNetworkVolume(url: URL) -> Bool {
    do {
      let resourceValues = try url.resourceValues(forKeys: [.volumeIsLocalKey])
      if let isLocal = resourceValues.volumeIsLocal {
        return !isLocal
      }
    } catch {
      // If we can't determine, assume it's local for performance
      return false
    }
    return false
  }

  /// Coordinated copy using NSFileCoordinator for network volumes
  private func coordinatedCopy(from source: URL, to destination: URL) async throws {
    var readError: NSError?
    var writeError: NSError?
    var copyError: Error?

    await withCheckedContinuation { continuation in
      fileCoordinator.coordinate(
        readingItemAt: source,
        options: [.withoutChanges],
        error: &readError,
        byAccessor: { (readURL) in
          // Use a separate coordinator for writing to avoid conflicts
          let writeCoordinator = NSFileCoordinator(filePresenter: nil)
          writeCoordinator.coordinate(
            writingItemAt: destination,
            options: [.forReplacing],
            error: &writeError,
            byAccessor: { (writeURL) in
              do {
                try self.fileManager.copyItem(at: readURL, to: writeURL)
              } catch {
                copyError = error
              }
            }
          )
        }
      )
      continuation.resume()
    }

    // Check for errors in order of occurrence
    if let error = readError {
      throw error
    }
    if let error = writeError {
      throw error
    }
    if let error = copyError {
      throw error
    }
  }

  func fileExists(at url: URL) -> Bool {
    return fileManager.fileExists(atPath: url.path)
  }

  func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
    try fileManager.createDirectory(
      at: url, withIntermediateDirectories: createIntermediates, attributes: nil)
  }

  func removeItem(at url: URL) throws {
    try fileManager.removeItem(at: url)
  }

  func attributesOfItem(at url: URL) throws -> [FileAttributeKey: Any] {
    return try fileManager.attributesOfItem(atPath: url.path)
  }

  func calculateChecksum(for url: URL, shouldCancel: () -> Bool) async throws -> String {
    // Use the existing static method from BackupManager
    // This maintains compatibility with existing checksum logic
    // Pass network volume status for optimized reading
    let isNetwork = isNetworkVolume(url: url)
    return try BackupManager.sha256ChecksumStatic(
      for: url, shouldCancel: shouldCancel(), isNetworkVolume: isNetwork)
  }

  func startAccessingSecurityScopedResource(for url: URL) -> Bool {
    return url.startAccessingSecurityScopedResource()
  }

  func stopAccessingSecurityScopedResource(for url: URL) {
    url.stopAccessingSecurityScopedResource()
  }

  func fileSize(at url: URL) -> Int64? {
    do {
      let attributes = try attributesOfItem(at: url)
      return attributes[.size] as? Int64
    } catch {
      return nil
    }
  }
}

/// Singleton instance for convenience
extension DefaultFileOperations {
  static let shared = DefaultFileOperations()
}
