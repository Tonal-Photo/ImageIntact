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
    /// Processing order:
    /// 1. Replace tab/CR/LF with space — so `"My\tFolder"` becomes `"My Folder"`,
    ///    not `"MyFolder"`. Preserves word boundaries when control whitespace
    ///    sneaks into the input.
    /// 2. Strip Unicode `Cc` (Control: C0 0x00–0x1F, C1 0x80–0x9F, DEL 0x7F),
    ///    `Zl` (Line Separator U+2028), and `Zp` (Paragraph Separator U+2029).
    ///    These can produce multiline directory listings or terminal escape
    ///    spoofing if left in.
    /// 3. Replace `/`, `\`, and `:` with underscores (path separators).
    /// 4. Trim leading/trailing whitespace and dots.
    /// 5. Truncate to ≤ 255 UTF-8 bytes without splitting multi-byte characters.
    ///
    /// **Preserved on purpose**: Unicode `Cf` (Format) category — includes Zero-Width
    /// Joiners (U+200D) used in family emojis like 👨‍👩‍👧‍👦 and bidirectional
    /// markers used in Right-to-Left languages. Stripping Cf would break legitimate
    /// international filenames.
    ///
    /// **Caller responsibility**: an input consisting entirely of strippable
    /// characters (e.g. `".."`, `"   "`, `"\t\n"`) returns `""`. Callers that
    /// construct paths from the result MUST guard `!result.isEmpty` before
    /// appending — otherwise `baseURL.appendingPathComponent("")` resolves to
    /// `baseURL` itself. `BackupManager.runBackup` does this check at the
    /// `!organizationName.isEmpty` guard.
    ///
    /// International characters (CJK, Cyrillic, accented Latin, emoji, RTL) are
    /// intentionally preserved — this is a photography app and users routinely
    /// have folder names like "São Paulo", "München", "日本", "📷", "‫مرحبا‬".
    /// A strict alphanumeric allowlist (or stripping Cf) would break legitimate
    /// workflows.
    ///
    /// Pure function — no side effects. Idempotent: `sanitize(sanitize(x)) == sanitize(x)`.
    static func sanitize(_ name: String) -> String {
        // 1. Replace whitespace-like control chars with space so word boundaries
        //    survive (e.g. "My\tFolder" → "My Folder", not "MyFolder").
        let spaced = name
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")

        // 2. Strip Cc (Control), Zl (Line Separator U+2028), Zp (Paragraph
        //    Separator U+2029). Cf (Format — ZWJ, bidi markers) is preserved.
        let stripped = String(String.UnicodeScalarView(
            spaced.unicodeScalars.filter { scalar in
                switch scalar.properties.generalCategory {
                case .control, .lineSeparator, .paragraphSeparator:
                    return false
                default:
                    return true
                }
            }
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
