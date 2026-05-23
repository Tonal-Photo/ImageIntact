//
//  SmartFolderName.swift
//  ImageIntact
//
//  Extracted from BackupManager (#103 / AMUX-18). A pure URL → String helper
//  that picks the most meaningful folder-name component for use as an
//  auto-generated backup organization name.
//

import Foundation

/// Pure URL → String helper for deriving a sensible folder name from a source path.
enum SmartFolderName {
    /// Examples:
    /// - ~/Downloads → "Downloads"
    /// - /Volumes/Card01/DCIM → "Card01"
    /// - ~/Pictures/2025/Q3/Clients/Johnson → "Johnson"
    /// - ~/Photos/My Photo Shoot → "My_Photo_Shoot"
    static func from(url: URL) -> String {
        let pathComponents = url.pathComponents
        var folderName: String

        // If it's a volume, use the volume name
        if pathComponents.count > 2 && pathComponents[1] == "Volumes" {
            folderName = pathComponents[2] // Volume name
        } else {
            // Skip generic folder names
            let genericNames = ["files", "images", "photos", "pictures", "dcim", "documents"]

            // Work backwards through path components to find a meaningful name
            folderName = url.lastPathComponent // Fallback
            for component in pathComponents.reversed() {
                let lowercased = component.lowercased()
                // Skip empty, hidden, or generic names
                if !component.isEmpty && !component.hasPrefix(".") && !genericNames.contains(lowercased)
                    && component != "/"
                {
                    folderName = component
                    break
                }
            }
        }

        // Replace spaces with underscores and collapse multiple underscores
        return folderName
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "__+", with: "_", options: .regularExpression)
    }

    /// Sanitizes a string for use as a filesystem folder name.
    ///
    /// - Replaces `/`, `\`, and `:` with underscores (path-separator characters).
    /// - Strips all C0 control characters (0x00–0x1F) and DEL (0x7F). This includes
    ///   null bytes, tabs, line endings, and terminal escape sequences. The latter
    ///   are a real concern: a filename containing ANSI escape codes can rewrite
    ///   preceding output in directory listings.
    /// - Trims leading/trailing whitespace and dots.
    /// - Truncates to ≤ 255 UTF-8 bytes without splitting multi-byte characters.
    ///
    /// International characters (CJK, Cyrillic, accented Latin, emoji) are
    /// intentionally preserved — this is a photography app and users routinely
    /// have folder names like "São Paulo", "München", "日本", "📷". A strict
    /// alphanumeric allowlist would break legitimate workflows.
    ///
    /// Pure function — no side effects. Idempotent: `sanitize(sanitize(x)) == sanitize(x)`.
    static func sanitize(_ name: String) -> String {
        // Strip all control characters (C0 range + DEL). CharacterSet's
        // `.controlCharacters` set covers 0x00–0x1F and 0x7F (and the C1 range,
        // which is also safe to strip from a filename).
        let stripped = String(String.UnicodeScalarView(
            name.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        ))
        var cleaned = stripped
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".")))
        // APFS/HFS+ limit is 255 UTF-8 bytes, not characters.
        if cleaned.utf8.count > 255 {
            var truncated = ""
            for char in cleaned {
                let next = truncated + String(char)
                if next.utf8.count > 255 { break }
                truncated = next
            }
            cleaned = truncated
        }
        return cleaned
    }
}
