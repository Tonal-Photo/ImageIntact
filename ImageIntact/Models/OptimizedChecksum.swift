//
//  OptimizedChecksum.swift
//  ImageIntact
//
//  Optimized checksum implementation with buffer reuse and reduced allocations
//

import CryptoKit
import Darwin
import Foundation

/// How checksum reads interact with the OS caches (AMUX-352 / gh#134).
public enum ChecksumReadPolicy: Sendable, Equatable {
  /// Cached reads are fine (manifest building, pre-copy skip checks). Cache
  /// warming here is harmless and sometimes helps the copy phase.
  case standard
  /// Post-copy verification: flush the file to the medium (F_FULLFSYNC) and
  /// bypass the page cache (F_NOCACHE) so the hash attests bytes on the
  /// destination device — never mmap, regardless of file size.
  case verification
}

/// Concrete read strategy chosen for a (file size, policy) pair.
enum ChecksumReadStrategy: Equatable {
  case directMapped
  case streaming(noCache: Bool)
}

/// Buffer pool for reusing memory allocations across checksum operations
final class ChecksumBufferPool {
  static let shared = ChecksumBufferPool()

  private let lock = NSLock()
  private var buffersBySize: [Int: [UnsafeMutableRawBufferPointer]] = [:]
  private let maxBuffersPerSize = 2  // Keep up to 2 buffers of each size

  deinit {
    // Clean up all buffers
    for (_, buffers) in buffersBySize {
      for buffer in buffers {
        buffer.deallocate()
      }
    }
  }

  func acquire(size: Int) -> UnsafeMutableRawBufferPointer {
    lock.lock()
    defer { lock.unlock() }

    // Get or create buffer array for this size
    if var buffers = buffersBySize[size], !buffers.isEmpty {
      let buffer = buffers.removeLast()
      buffersBySize[size] = buffers
      return buffer
    } else {
      // Allocate new buffer with requested size
      return UnsafeMutableRawBufferPointer.allocate(byteCount: size, alignment: 16)
    }
  }

  func release(_ buffer: UnsafeMutableRawBufferPointer, size: Int) {
    lock.lock()
    defer { lock.unlock() }

    // Store buffer for reuse if we have room
    var buffers = buffersBySize[size] ?? []
    if buffers.count < maxBuffersPerSize {
      buffers.append(buffer)
      buffersBySize[size] = buffers
    } else {
      // Pool is full for this size, deallocate
      buffer.deallocate()
    }
  }

  /// Clean up unused buffers to free memory
  func cleanupUnusedBuffers() {
    lock.lock()
    defer { lock.unlock() }

    // Deallocate all stored buffers
    for (size, buffers) in buffersBySize {
      for buffer in buffers {
        buffer.deallocate()
      }
      buffersBySize[size] = []
    }
  }
}

/// Optimized checksum calculator with performance improvements
public struct OptimizedChecksum {

  // Optimal chunk sizes based on testing
  private static let optimalChunkSizes: [Int: Int] = [
    10_000_000: 256 * 1024,  // 10MB files: 256KB chunks
    100_000_000: 1024 * 1024,  // 100MB files: 1MB chunks
    500_000_000: 2 * 1024 * 1024,  // 500MB files: 2MB chunks
    Int.max: 4 * 1024 * 1024,  // >500MB files: 4MB chunks
  ]

  /// Get optimal chunk size based on file size
  static func optimalChunkSize(for fileSize: Int64) -> Int {
    let size = Int(fileSize)
    for (threshold, chunkSize) in optimalChunkSizes.sorted(by: { $0.key < $1.key }) {
      if size <= threshold {
        return chunkSize
      }
    }
    return 4 * 1024 * 1024  // Default to 4MB for very large files
  }

  /// Files below this size use the mmap fast path under `.standard` policy.
  static let smallFileThreshold: Int64 = 10_000_000

  /// Pure routing decision for a (file size, policy) pair. Verification must
  /// never touch the page cache, so it always streams with no-cache reads.
  static func readStrategy(forFileSize fileSize: Int64, policy: ChecksumReadPolicy)
    -> ChecksumReadStrategy
  {
    if policy == .verification {
      return .streaming(noCache: true)
    }
    return fileSize < smallFileThreshold ? .directMapped : .streaming(noCache: false)
  }

  /// Calculate SHA256 checksum with optimized streaming
  public static func sha256(
    for fileURL: URL, policy: ChecksumReadPolicy = .standard,
    shouldCancel: @escaping () -> Bool = { false }
  ) throws
    -> String
  {
    // Get file attributes
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fileSize = attributes[.size] as? Int64 ?? 0

    // Handle empty files
    if fileSize == 0 {
      return "empty-file-0-bytes"
    }

    switch readStrategy(forFileSize: fileSize, policy: policy) {
    case .directMapped:
      return try calculateDirectChecksum(for: fileURL, shouldCancel: shouldCancel)
    case .streaming(let noCache):
      return try calculateOptimizedStreamingChecksum(
        for: fileURL, fileSize: fileSize, noCache: noCache, shouldCancel: shouldCancel)
    }
  }

  /// Direct checksum for small files
  private static func calculateDirectChecksum(for fileURL: URL, shouldCancel: @escaping () -> Bool)
    throws -> String
  {
    if shouldCancel() {
      throw ChecksumError.cancelled
    }

    let fileData = try Data(contentsOf: fileURL, options: .mappedIfSafe)
    let hash = SHA256.hash(data: fileData)
    return hash.hexString
  }

  /// Verification reads must attest bytes that reached the destination device
  /// (gh#134). Two distinct guarantees, split across two mechanisms:
  /// 1. Per-file, here: `fsync` pushes this file's dirty pages out of the
  ///    kernel to the drive, so the read below cannot be satisfied by pages
  ///    the copy left behind, and `F_NOCACHE` makes reads on this descriptor
  ///    bypass the unified buffer cache. The read therefore attests "the data
  ///    traversed the bus and the drive acknowledged it". No userspace API
  ///    can force a drive past its own read cache, so media-level readback
  ///    cannot be promised. `fsync` on a read-only descriptor is permitted on
  ///    Darwin (non-POSIX but long-standing); it is best-effort by design.
  /// 2. Per-destination, after the verify loop: one device-wide `F_FULLFSYNC`
  ///    (`flushVolumeToMedium`) lands the whole batch on permanent storage.
  ///    Ordered after every per-file fsync — flushing before them would leave
  ///    late-fsynced data in the drive's volatile cache (PR #136 round 2).
  ///    Per-file full-syncs are deliberately avoided: the flush is
  ///    device-wide, so repeating it per file only adds write amplification
  ///    (PR #136 round 1).
  /// All calls are best-effort: on volumes supporting neither, a cached
  /// verify is still preferable to failing the whole backup.
  private static func configureNoCacheRead(on fd: Int32) {
    _ = fsync(fd)
    _ = fcntl(fd, F_NOCACHE, 1)
  }

  /// One-shot, best-effort flush of the drive's volatile write cache for the
  /// volume containing `url`. `F_FULLFSYNC` is device-wide, so calling this
  /// once per destination covers every file the copy phase wrote, at a single
  /// flush's cost. Call AFTER the per-file fsyncs of a verification pass (see
  /// `configureNoCacheRead`). Works on file and directory descriptors alike;
  /// silently a no-op where unsupported.
  static func flushVolumeToMedium(containing url: URL) {
    let fd = open(url.path, O_RDONLY)
    guard fd >= 0 else { return }
    defer { close(fd) }
    if fcntl(fd, F_FULLFSYNC, 0) == -1 {
      _ = fsync(fd)
    }
  }

  /// Async bridge for `flushVolumeToMedium(containing:)`. F_FULLFSYNC can
  /// block for seconds on spinning media; running it inline on an actor would
  /// pin a cooperative-pool thread (PR #136 round 2). Same GCD pattern as
  /// `ChecksumService.sha256Async`.
  ///
  /// Deliberately NOT cancellation-aware (PR #136 round 3): an in-flight
  /// F_FULLFSYNC syscall cannot be interrupted, so resuming the continuation
  /// early would only detach a still-running flush. A backup cancelled during
  /// this final flush therefore waits it out — bounded at one flush per
  /// destination, at the very end of verification.
  static func flushVolumeToMediumAsync(containing url: URL) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      DispatchQueue.global(qos: .utility).async {
        flushVolumeToMedium(containing: url)
        continuation.resume()
      }
    }
  }

  /// Optimized streaming checksum for large files (and all verification reads)
  private static func calculateOptimizedStreamingChecksum(
    for fileURL: URL, fileSize: Int64, noCache: Bool = false,
    shouldCancel: @escaping () -> Bool
  ) throws -> String {
    // Wrap in autoreleasepool for better memory management
    return try autoreleasepool {
      // Determine optimal chunk size
      let chunkSize = optimalChunkSize(for: fileSize)

      // Use shared buffer pool instance with appropriate size
      let buffer = ChecksumBufferPool.shared.acquire(size: chunkSize)
      defer { ChecksumBufferPool.shared.release(buffer, size: chunkSize) }

      // Open file handle for reading
      let fileHandle = try FileHandle(forReadingFrom: fileURL)
      defer { try? fileHandle.close() }

      if noCache {
        configureNoCacheRead(on: fileHandle.fileDescriptor)
      }

      var hasher = SHA256()
      var totalBytesRead: Int64 = 0

      // Read and hash in chunks
      while totalBytesRead < fileSize {
        // Wrap each chunk in its own autoreleasepool for very large files
        try autoreleasepool {
          // Check cancellation
          if shouldCancel() {
            throw ChecksumError.cancelled
          }

          // Calculate how much to read
          let remainingBytes = fileSize - totalBytesRead
          let bytesToRead = Int(min(Int64(chunkSize), remainingBytes))

          // Read directly into buffer
          let bytesRead = try readIntoBuffer(
            fileHandle: fileHandle, buffer: buffer, maxLength: bytesToRead)

          if bytesRead == 0 {
            // End of file reached
            return
          }

          // Update hasher directly with buffer pointer (no Data allocation)
          buffer.withUnsafeBytes { bytes in
            let uint8Bytes = bytes.bindMemory(to: UInt8.self)
            hasher.update(
              bufferPointer: UnsafeRawBufferPointer(start: uint8Bytes.baseAddress, count: bytesRead)
            )
          }

          totalBytesRead += Int64(bytesRead)
        }
      }

      let hash = hasher.finalize()
      return hash.hexString
    }
  }

  /// Optimized file reading directly into buffer
  private static func readIntoBuffer(
    fileHandle: FileHandle, buffer: UnsafeMutableRawBufferPointer, maxLength: Int
  ) throws -> Int {
    guard let data = try? fileHandle.read(upToCount: maxLength) else {
      return 0
    }
    data.withUnsafeBytes { dataBytes in
      buffer.copyMemory(from: dataBytes)
    }
    return data.count
  }
}

/// Checksum-specific errors
enum ChecksumError: LocalizedError {
  case cancelled
  case readError(String)

  var errorDescription: String? {
    switch self {
    case .cancelled:
      return "Checksum calculation was cancelled"
    case .readError(let message):
      return "Failed to read file: \(message)"
    }
  }
}

// MARK: - Helper Extensions

extension SHA256.Digest {
  /// Convert hash digest to hex string
  var hexString: String {
    self.compactMap { String(format: "%02x", $0) }.joined()
  }
}

