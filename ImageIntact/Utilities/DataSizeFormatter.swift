import Foundation

/// Shared data size formatting utility
enum DataSizeFormatter {
    /// Format byte count into human-readable size (e.g., "1 KB", "100 MB")
    ///
    /// Creates a new ByteCountFormatter per call to avoid Swift 6 strict concurrency
    /// issues with caching a non-Sendable NSObject subclass in a static let.
    static func format(_ bytes: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .binary
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: bytes)
    }
}
