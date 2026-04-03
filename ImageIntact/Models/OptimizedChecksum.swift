//
//  OptimizedChecksum.swift
//  ImageIntact
//
//  Optimized checksum implementation with buffer reuse and reduced allocations
//

import CryptoKit
import Foundation

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

  /// Calculate SHA256 checksum with optimized streaming
  public static func sha256(for fileURL: URL, shouldCancel: @escaping () -> Bool = { false }) throws
    -> String
  {
    // Get file attributes
    let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
    let fileSize = attributes[.size] as? Int64 ?? 0

    // Handle empty files
    if fileSize == 0 {
      return "empty-file-0-bytes"
    }

    // For small files (<10MB), use direct loading (fastest)
    if fileSize < 10_000_000 {
      return try calculateDirectChecksum(for: fileURL, shouldCancel: shouldCancel)
    }

    // For larger files, use optimized streaming
    return try calculateOptimizedStreamingChecksum(
      for: fileURL, fileSize: fileSize, shouldCancel: shouldCancel)
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

  /// Optimized streaming checksum for large files
  private static func calculateOptimizedStreamingChecksum(
    for fileURL: URL, fileSize: Int64, shouldCancel: @escaping () -> Bool
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

