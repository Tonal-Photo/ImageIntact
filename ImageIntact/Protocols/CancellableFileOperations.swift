import Darwin  // For extended attribute functions
import Foundation

/// Cancellable file operations using stream-based copying
/// Uses NSFileCoordinator for network volumes to ensure data integrity
class CancellableFileOperations: FileOperationsProtocol {
  private let fileManager = FileManager.default
  private var bufferSize: Int {
    // Use user-configured buffer size for network operations
    return PreferencesManager.shared.networkBufferSize * 1024 * 1024
  }

  private let fileCoordinator = NSFileCoordinator(filePresenter: nil)
  private let prefs = PreferencesManager.shared

  /// Copy a file using streams that can be cancelled
  func copyItem(at source: URL, to destination: URL) async throws {
    // Validate paths before any operations
    try validatePaths(source: source, destination: destination)

    // Check if either source or destination is on a network volume
    let isNetwork = isNetworkVolume(url: source) || isNetworkVolume(url: destination)

    if isNetwork, prefs.useStreamCopyForNetwork {
      // Use stream-based copy for network volumes (cancellable and throttleable)
      try await streamCopy(from: source, to: destination, isNetwork: true)
    } else if isNetwork {
      // Use coordinated copy with timeout for network volumes
      try await coordinatedCopyWithTimeout(from: source, to: destination)
    } else {
      // First try to create hard link (instant and cancellable)
      if tryHardLink(from: source, to: destination) {
        return
      }

      // Fall back to stream-based copy for cross-volume or when hard link fails
      try await streamCopy(from: source, to: destination, isNetwork: false)
    }
  }

  /// Validate that paths are safe and within expected boundaries
  private func validatePaths(source: URL, destination: URL) throws {
    // Ensure both paths are file URLs
    guard source.isFileURL, destination.isFileURL else {
      throw NSError(
        domain: "CancellableFileOperations", code: 100,
        userInfo: [NSLocalizedDescriptionKey: "Only file URLs are supported"])
    }

    // Skip symbolic links for security (prevent path traversal attacks)
    let resourceValues = try? source.resourceValues(forKeys: [.isSymbolicLinkKey])
    if resourceValues?.isSymbolicLink == true {
      throw NSError(
        domain: "CancellableFileOperations", code: 110,
        userInfo: [NSLocalizedDescriptionKey: "Symbolic links are not supported"])
    }

    // Resolve symbolic links to get real paths
    let realSource = source.resolvingSymlinksInPath()
    let realDestination = destination.resolvingSymlinksInPath()

    // Check that source exists and is a regular file
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: realSource.path, isDirectory: &isDirectory) else {
      throw NSError(
        domain: "CancellableFileOperations", code: 101,
        userInfo: [NSLocalizedDescriptionKey: "Source file does not exist"])
    }

    guard !isDirectory.boolValue else {
      throw NSError(
        domain: "CancellableFileOperations", code: 102,
        userInfo: [NSLocalizedDescriptionKey: "Source must be a file, not a directory"])
    }

    // Prevent copying to system directories
    let restrictedPaths = [
      "/System",
      "/Library",
      "/usr",
      "/bin",
      "/sbin",
      "/private/etc",
      "/private/var/root",
    ]

    let destPath = realDestination.path
    for restricted in restrictedPaths {
      if destPath.hasPrefix(restricted) {
        throw NSError(
          domain: "CancellableFileOperations", code: 103,
          userInfo: [NSLocalizedDescriptionKey: "Cannot copy to system directory: \(restricted)"])
      }
    }

    // Ensure destination parent directory exists or can be created
    let destParent = realDestination.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: destParent.path) {
      // Verify we can create it (not in a read-only location)
      if !fileManager.isWritableFile(atPath: destParent.deletingLastPathComponent().path) {
        throw NSError(
          domain: "CancellableFileOperations", code: 104,
          userInfo: [NSLocalizedDescriptionKey: "Cannot write to destination directory"])
      }
    }

    // Prevent source and destination being the same
    if realSource.path == realDestination.path {
      throw NSError(
        domain: "CancellableFileOperations", code: 105,
        userInfo: [NSLocalizedDescriptionKey: "Source and destination cannot be the same"])
    }
  }

  /// Try to create a hard link (instant copy on same volume)
  private func tryHardLink(from source: URL, to destination: URL) -> Bool {
    // Additional validation for hard links
    // Hard links should only be created for regular files, not directories or special files

    // Check if both paths are on the same volume (required for hard links)
    guard let sourceVolume = try? source.resourceValues(forKeys: [.volumeURLKey]).volume,
      let destVolume = try? destination.deletingLastPathComponent().resourceValues(forKeys: [
        .volumeURLKey
      ]).volume,
      sourceVolume == destVolume
    else {
      return false  // Different volumes, hard link not possible
    }

    do {
      try fileManager.linkItem(at: source, to: destination)
      return true
    } catch {
      // Hard link failed (file system doesn't support it or other error)
      return false
    }
  }

  /// Preserve extended attributes from source to destination file
  private func preserveExtendedAttributes(from source: URL, to destination: URL) throws {
    // Get list of extended attributes
    let sourcePath = source.path
    let destPath = destination.path

    // Get the list of extended attribute names
    let listSize = listxattr(sourcePath, nil, 0, 0)
    guard listSize > 0 else { return }  // No extended attributes

    let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: listSize)
    defer { buffer.deallocate() }

    let result = listxattr(sourcePath, buffer, listSize, 0)
    guard result > 0 else { return }

    // Parse attribute names (null-terminated strings)
    var position = 0
    while position < result {
      let nameStart = buffer.advanced(by: position)
      let name = String(cString: nameStart)

      // Get size of this attribute's value
      let valueSize = getxattr(sourcePath, name, nil, 0, 0, 0)
      if valueSize > 0 {
        // Get the attribute value
        let valueBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: valueSize)
        defer { valueBuffer.deallocate() }

        let fetchResult = getxattr(sourcePath, name, valueBuffer, valueSize, 0, 0)
        if fetchResult > 0 {
          // Set the attribute on the destination
          // Use XATTR_NOFOLLOW to not follow symlinks (though we skip them anyway)
          setxattr(destPath, name, valueBuffer, fetchResult, 0, 0)
        }
      }

      // Move to next attribute name
      position += strlen(nameStart) + 1
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

  /// Coordinated copy with timeout for network volumes
  private func coordinatedCopyWithTimeout(from source: URL, to destination: URL) async throws {
    let timeout = TimeInterval(prefs.networkCopyTimeout)

    // Race between timeout and copy using withThrowingTaskGroup
    try await withThrowingTaskGroup(of: Void.self) { group in
      // Add the copy task
      group.addTask {
        try await self.coordinatedCopy(from: source, to: destination)
      }

      // Add the timeout task
      group.addTask {
        try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        throw NSError(
          domain: "CancellableFileOperations", code: 408,
          userInfo: [
            NSLocalizedDescriptionKey: "Network copy timed out after \(Int(timeout)) seconds"
          ])
      }

      // Wait for the first task to complete (either copy succeeds or timeout)
      for try await _ in group {
        // First task completed successfully (must be the copy since timeout throws)
        group.cancelAll()  // Cancel the timeout
        return
      }
    }
  }

  /// Coordinated copy using NSFileCoordinator for network volumes
  private func coordinatedCopy(from source: URL, to destination: URL) async throws {
    // Check if task is cancelled before starting
    try Task.checkCancellation()

    // Create parent directory if needed
    let destDir = destination.deletingLastPathComponent()
    if !fileManager.fileExists(atPath: destDir.path) {
      try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
    }

    // Use file coordination for network safety
    var readError: NSError?
    var writeError: NSError?
    var copyError: Error?

    await withCheckedContinuation { continuation in
      fileCoordinator.coordinate(
        readingItemAt: source,
        options: [.withoutChanges],
        error: &readError,
        byAccessor: { readURL in
          // Now we have exclusive read access to the source file
          // Use a separate coordinator for writing to avoid conflicts
          let writeCoordinator = NSFileCoordinator(filePresenter: nil)
          writeCoordinator.coordinate(
            writingItemAt: destination,
            options: [.forReplacing],
            error: &writeError,
            byAccessor: { writeURL in
              // Now we have exclusive write access to the destination
              // Check if task is cancelled (in sync context)
              if Task.isCancelled {
                copyError = CancellationError()
                return
              }

              do {
                // Use FileManager for the actual copy within the coordination
                // This ensures proper locking on network volumes
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

  /// Stream-based copy that can be cancelled and throttled
  private func streamCopy(from source: URL, to destination: URL, isNetwork: Bool) async throws {
    // Check for cancellation before starting
    try Task.checkCancellation()

    // Open source file for reading
    guard let sourceHandle = try? FileHandle(forReadingFrom: source) else {
      throw NSError(
        domain: "CancellableFileOperations", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Cannot open source file"])
    }
    defer {
      try? sourceHandle.close()
    }

    // Create destination file
    fileManager.createFile(atPath: destination.path, contents: nil)
    guard let destHandle = try? FileHandle(forWritingTo: destination) else {
      throw NSError(
        domain: "CancellableFileOperations", code: 2,
        userInfo: [NSLocalizedDescriptionKey: "Cannot create destination file"])
    }
    defer {
      try? destHandle.close()
    }

    // Track timing for throttling
    var lastChunkTime = Date()
    let speedLimit = isNetwork ? prefs.networkCopySpeedLimit : 0  // MB/s
    let chunkSize = isNetwork ? bufferSize : (4 * 1024 * 1024)  // Use configured size for network

    // Copy in chunks that can be cancelled between iterations
    while true {
      // Check for cancellation
      try Task.checkCancellation()

      // Read a chunk
      let chunk = sourceHandle.readData(ofLength: chunkSize)

      // If no data read, we're done
      if chunk.isEmpty {
        break
      }

      // Write the chunk
      try destHandle.write(contentsOf: chunk)

      // Throttle for network copies if speed limit is set
      if isNetwork, speedLimit > 0 {
        let bytesPerSecond = speedLimit * 1024 * 1024
        let expectedDuration = Double(chunk.count) / bytesPerSecond
        let actualDuration = Date().timeIntervalSince(lastChunkTime)

        if actualDuration < expectedDuration {
          // Sleep to limit speed
          let sleepTime = expectedDuration - actualDuration
          try await Task.sleep(nanoseconds: UInt64(sleepTime * 1_000_000_000))
        }
        lastChunkTime = Date()
      }

      // Yield to allow cancellation
      await Task.yield()
    }

    // Ensure all data is written to disk
    try destHandle.synchronize()

    // Copy file attributes (permissions, dates, etc.)
    let attributes = try fileManager.attributesOfItem(atPath: source.path)
    try fileManager.setAttributes(attributes, ofItemAtPath: destination.path)

    // Preserve extended attributes (Finder tags, comments, etc.)
    try preserveExtendedAttributes(from: source, to: destination)
  }

  // MARK: - FileOperationsProtocol conformance

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
    // Use the existing static method from BackupManager for consistency
    // This uses SHA-256 which is what the rest of the app expects
    // Pass network volume status for optimized reading
    let isNetwork = isNetworkVolume(url: url)
    return try BackupManager.sha256ChecksumStatic(
      for: url, shouldCancel: shouldCancel(), isNetworkVolume: isNetwork)
  }

  func fileSize(at url: URL) -> Int64? {
    guard let attributes = try? attributesOfItem(at: url),
      let size = attributes[.size] as? NSNumber
    else {
      return nil
    }
    return size.int64Value
  }

  func startAccessingSecurityScopedResource(for url: URL) -> Bool {
    return url.startAccessingSecurityScopedResource()
  }

  func stopAccessingSecurityScopedResource(for url: URL) {
    url.stopAccessingSecurityScopedResource()
  }
}
