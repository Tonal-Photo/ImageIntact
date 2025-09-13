//
//  PIISanitizer.swift
//  ImageIntact
//
//  Sanitizes Personally Identifiable Information (PII) from logs for bug reports
//

import Foundation

/// Sanitizes PII from text while preserving debugging information
class PIISanitizer {
    
    /// Result of sanitization including the cleaned text and a report of what was removed
    struct SanitizationResult {
        let sanitizedText: String
        let report: String
    }
    
    /// Tracking what was sanitized
    private struct SanitizationStats {
        var usernames = Set<String>()
        var volumes = Set<String>()
        var filenames = Set<String>()
        var networks = Set<String>()
        var emails = Set<String>()
        
        var report: String {
            var parts: [String] = []
            if !usernames.isEmpty {
                parts.append("\(usernames.count) username\(usernames.count == 1 ? "" : "s")")
            }
            if !volumes.isEmpty {
                parts.append("\(volumes.count) volume\(volumes.count == 1 ? "" : "s")")
            }
            if !filenames.isEmpty {
                parts.append("\(filenames.count) filename\(filenames.count == 1 ? "" : "s")")
            }
            if !networks.isEmpty {
                parts.append("\(networks.count) network address\(networks.count == 1 ? "" : "es")")
            }
            if !emails.isEmpty {
                parts.append("\(emails.count) email\(emails.count == 1 ? "" : "s")")
            }
            
            if parts.isEmpty {
                return "No PII detected"
            }
            
            return "Removed: " + parts.joined(separator: ", ")
        }
    }
    
    /// Main sanitization function
    func sanitize(_ text: String) -> String {
        var result = text
        var dummyStats: SanitizationStats? = nil
        
        // Order matters: sanitize in specific order
        result = sanitizeUserPaths(result, stats: &dummyStats)
        result = sanitizeVolumePaths(result, stats: &dummyStats)
        result = sanitizeNetworkPaths(result, stats: &dummyStats)
        result = sanitizeEmails(result, stats: &dummyStats)
        result = sanitizeDirectoryNames(result, stats: &dummyStats)  // Before filenames
        result = sanitizeFilenames(result, stats: &dummyStats)
        
        return result
    }
    
    /// Sanitize with optional text
    func sanitizeOptional(_ text: String?) -> String? {
        guard let text = text else { return nil }
        return sanitize(text)
    }
    
    /// Sanitize and generate a report of what was removed
    func sanitizeWithReport(_ text: String) -> SanitizationResult {
        var result = text
        var stats: SanitizationStats? = SanitizationStats()
        
        result = sanitizeUserPaths(result, stats: &stats)
        result = sanitizeVolumePaths(result, stats: &stats)
        result = sanitizeNetworkPaths(result, stats: &stats)
        result = sanitizeEmails(result, stats: &stats)
        result = sanitizeDirectoryNames(result, stats: &stats)
        result = sanitizeFilenames(result, stats: &stats)
        
        return SanitizationResult(
            sanitizedText: result,
            report: stats?.report ?? "No PII detected"
        )
    }
    
    // MARK: - User Path Sanitization
    
    private func sanitizeUserPaths(_ text: String, stats: inout SanitizationStats?) -> String {
        var result = text
        
        // Match /Users/username patterns (macOS)
        let userPattern = #"/Users/([^/\s]+)"#
        if let regex = try? NSRegularExpression(pattern: userPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            // Process matches in reverse to maintain string indices
            for match in matches.reversed() {
                if let usernameRange = Range(match.range(at: 1), in: result) {
                    let username = String(result[usernameRange])
                    stats?.usernames.insert(username)
                    
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "/Users/[USER]")
                    }
                }
            }
        }
        
        // Match C:\Users\username patterns (Windows)
        let windowsUserPattern = #"C:\\Users\\([^\\]+)"#
        if let regex = try? NSRegularExpression(pattern: windowsUserPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let usernameRange = Range(match.range(at: 1), in: result) {
                    let username = String(result[usernameRange])
                    stats?.usernames.insert(username)
                    
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "C:\\Users\\[USER]")
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Volume Path Sanitization
    
    private func sanitizeVolumePaths(_ text: String, stats: inout SanitizationStats?) -> String {
        var result = text
        
        // Match /Volumes/VolumeName patterns
        let volumePattern = #"/Volumes/([^/\s]+)"#
        if let regex = try? NSRegularExpression(pattern: volumePattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let volumeRange = Range(match.range(at: 1), in: result) {
                    let volume = String(result[volumeRange])
                    stats?.volumes.insert(volume)
                    
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "/Volumes/[VOLUME]")
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Network Path Sanitization
    
    private func sanitizeNetworkPaths(_ text: String, stats: inout SanitizationStats?) -> String {
        var result = text
        
        // Match IP addresses
        let ipPattern = #"//(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})"#
        if let regex = try? NSRegularExpression(pattern: ipPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let ipRange = Range(match.range(at: 1), in: result) {
                    let ip = String(result[ipRange])
                    stats?.networks.insert(ip)
                    
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "//[NETWORK]")
                    }
                }
            }
        }
        
        // Match hostnames (smb://hostname.local, afp://hostname, etc.)
        let hostnamePattern = #"(smb|afp|ftp|http|https)://([^/\s]+)"#
        if let regex = try? NSRegularExpression(pattern: hostnamePattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let protocolRange = Range(match.range(at: 1), in: result),
                   let hostnameRange = Range(match.range(at: 2), in: result) {
                    let proto = String(result[protocolRange])
                    let hostname = String(result[hostnameRange])
                    stats?.networks.insert(hostname)
                    
                    if let fullRange = Range(match.range, in: result) {
                        result.replaceSubrange(fullRange, with: "\(proto)://[NETWORK]")
                    }
                }
            }
        }
        
        return result
    }
    
    // MARK: - Email Sanitization
    
    private func sanitizeEmails(_ text: String, stats: inout SanitizationStats?) -> String {
        var result = text
        
        // Match email addresses
        let emailPattern = #"[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}"#
        if let regex = try? NSRegularExpression(pattern: emailPattern, options: []) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let emailRange = Range(match.range, in: result) {
                    let email = String(result[emailRange])
                    stats?.emails.insert(email)
                    result.replaceSubrange(emailRange, with: "[EMAIL]")
                }
            }
        }
        
        return result
    }
    
    // MARK: - Directory Name Sanitization
    
    private func sanitizeDirectoryNames(_ text: String, stats: inout SanitizationStats?) -> String {
        var result = text
        
        // Standard directories to skip
        let standardDirs = ["Users", "Volumes", "Applications", "Library", "System",
                           "Documents", "Pictures", "Photos", "Movies", "Music",
                           "Downloads", "Desktop", "Public", "DCIM", "Backups",
                           "Archive", "NetworkBackup", "[USER]", "[VOLUME]", "[FILENAME]", "[DIRECTORY]"]
        
        // Pattern for personal information
        let personalPattern = #"(\d{4}[-_]\d{2}[-_]\d{2})|([Ww]edding\d{4})|([Bb]irthday\d{4})|([Vv]acation\d{4})|([Tt]rip\d{4})|([Ee]vent\d{4})|([Pp]arty\d{4})|(\d{4}[-_][A-Za-z]+)|([A-Za-z]+[-_]\d{4})"#
        
        // Create a regex that directly matches personal directories in paths
        // This finds directories with personal patterns that are between slashes
        let pathPersonalPattern = #"/(\d{4}[-_]\d{2}[-_]\d{2}[-_][A-Za-z]+|\d{4}[-_]\d{2}[-_]\d{2}|[Ww]edding\d{4}|[Bb]irthday\d{4}|[Vv]acation\d{4}|[Tt]rip\d{4}|[Ee]vent\d{4}|[Pp]arty\d{4}|[A-Za-z]+[-_]\d{4}|Backup-Drive)/"#
        
        if let regex = try? NSRegularExpression(pattern: pathPersonalPattern, options: []) {
            // Keep replacing until no more matches
            var previousResult = ""
            while previousResult != result {
                previousResult = result
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(location: 0, length: result.utf16.count),
                    withTemplate: "/[DIRECTORY]/"
                )
            }
        }
        
        // Also handle directories at end of path (no trailing slash)
        let endPersonalPattern = #"/(\d{4}[-_]\d{2}[-_]\d{2}|[Ww]edding\d{4}|[Bb]irthday\d{4}|[Vv]acation\d{4}|[Tt]rip\d{4}|[Ee]vent\d{4}|[Pp]arty\d{4}|[A-Za-z]+[-_]\d{4})$"#
        
        if let regex = try? NSRegularExpression(pattern: endPersonalPattern, options: []) {
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: NSRange(location: 0, length: result.utf16.count),
                withTemplate: "/[DIRECTORY]"
            )
        }
        
        return result
    }
    
    // MARK: - Filename Sanitization
    
    private func sanitizeFilenames(_ text: String, stats: inout SanitizationStats?) -> String {
        var result = text
        
        // Common image/video extensions to look for
        let extensions = [
            // RAW formats
            "nef", "cr2", "cr3", "arw", "orf", "rw2", "dng", "raf", "raw", "rwl", "srw", "x3f",
            // Image formats
            "jpg", "jpeg", "png", "tiff", "tif", "heic", "heif", "bmp", "webp",
            // Video formats
            "mov", "mp4", "avi", "mkv", "m4v", "mpg", "mpeg", "wmv", "flv", "webm",
            // Sidecar formats
            "xmp", "aae", "dop",
            // Document formats
            "pdf", "doc", "docx", "txt"
        ]
        
        // Build pattern for filenames with these extensions
        let extensionPattern = extensions.joined(separator: "|")
        let filenamePattern = #"([^/\\\s]+)\.(\#(extensionPattern))"#
        
        if let regex = try? NSRegularExpression(pattern: filenamePattern, options: [.caseInsensitive]) {
            let matches = regex.matches(in: result, options: [], range: NSRange(location: 0, length: result.utf16.count))
            
            for match in matches.reversed() {
                if let nameRange = Range(match.range(at: 1), in: result),
                   let extRange = Range(match.range(at: 2), in: result) {
                    let filename = String(result[nameRange])
                    let ext = String(result[extRange])
                    
                    // Don't sanitize if it's already a placeholder
                    if filename != "[FILENAME]" {
                        stats?.filenames.insert("\(filename).\(ext)")
                        
                        if let fullRange = Range(match.range, in: result) {
                            result.replaceSubrange(fullRange, with: "[FILENAME].\(ext)")
                        }
                    }
                }
            }
        }
        
        return result
    }
}