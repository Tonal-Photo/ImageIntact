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
    /// - Strips Unicode "Control" category characters (`Cc`): C0 (0x00–0x1F),
    ///   C1 (0x80–0x9F), and DEL (0x7F). This includes null bytes, tabs, line
    ///   endings, and terminal escape sequences. The latter are a real concern:
    ///   a filename containing ANSI escape codes can rewrite preceding output
    ///   in directory listings.
    /// - **Preserves** Unicode "Format" category (`Cf`). Cf includes Zero-Width
    ///   Joiners (U+200D) used in family emojis like 👨‍👩‍👧‍👦 and bidirectional
    ///   markers used in Right-to-Left languages. Stripping Cf would break
    ///   legitimate international filenames.
    /// - Trims leading/trailing whitespace and dots.
    /// - Truncates to ≤ 255 UTF-8 bytes without splitting multi-byte characters.
    ///
    /// International characters (CJK, Cyrillic, accented Latin, emoji, RTL) are
    /// intentionally preserved — this is a photography app and users routinely
    /// have folder names like "São Paulo", "München", "日本", "📷", "‫مرحبا‬".
    /// A strict alphanumeric allowlist (or stripping Cf) would break legitimate
    /// workflows.
    ///
    /// Pure function — no side effects. Idempotent: `sanitize(sanitize(x)) == sanitize(x)`.
    static func sanitize(_ name: String) -> String {
        // Strip Cc (Control) category only. Foundation's
        // `CharacterSet.controlCharacters` includes BOTH Cc and Cf — using it
        // here would also strip ZWJ and bidirectional markers, breaking
        // family emojis and RTL languages.
        let stripped = String(String.UnicodeScalarView(
            name.unicodeScalars.filter { $0.properties.generalCategory != .control }
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
