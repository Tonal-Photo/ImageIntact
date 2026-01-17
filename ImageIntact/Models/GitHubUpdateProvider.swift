import Foundation

/// GitHub-based update provider that checks releases via GitHub API
class GitHubUpdateProvider: UpdateProvider {
    private let owner = "kmichels"
    private let repo = "ImageIntact"
    private let session = URLSession.shared

    var providerName: String {
        return "GitHub Releases"
    }

    /// Check for updates via GitHub API
    func checkForUpdates(currentVersion: String) async throws -> AppUpdate? {
        // GitHub API endpoint for latest release
        guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)/releases/latest")
        else {
            throw UpdateError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.v3+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw UpdateError.invalidResponse
            }

            // Handle 404 (no releases yet)
            if httpResponse.statusCode == 404 {
                ApplicationLogger.shared.debug("No releases found on GitHub", category: .network)
                return nil
            }

            guard httpResponse.statusCode == 200 else {
                throw UpdateError.invalidResponse
            }

            // Parse GitHub release JSON
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw UpdateError.invalidResponse
            }

            // Extract version (remove 'v' prefix if present)
            guard let tagName = json["tag_name"] as? String else {
                throw UpdateError.invalidResponse
            }
            let version = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            // Check if update is newer (latest must be greater than current)
            let comparison = version.compare(currentVersion, options: .numeric)
            if comparison != .orderedDescending {
                ApplicationLogger.shared.debug("No update needed: current v\(currentVersion) >= latest v\(version)", category: .network)
                return nil
            }
            ApplicationLogger.shared.debug("Update available: v\(currentVersion) -> v\(version)", category: .network)

            // Extract release notes
            let releaseNotes = json["body"] as? String ?? "No release notes available"

            // Find .dmg asset (accept any DMG file)
            guard let assets = json["assets"] as? [[String: Any]],
                  let dmgAsset = assets.first(where: { asset in
                      guard let name = asset["name"] as? String else { return false }
                      return name.hasSuffix(".dmg")
                  })
            else {
                ApplicationLogger.shared.debug("No DMG found in release assets", category: .network)
                throw UpdateError.invalidResponse
            }

            guard let downloadURLString = dmgAsset["browser_download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString)
            else {
                throw UpdateError.invalidResponse
            }

            // Parse published date
            let publishedDate: Date
            if let publishedString = json["published_at"] as? String {
                let formatter = ISO8601DateFormatter()
                publishedDate = formatter.date(from: publishedString) ?? Date()
            } else {
                publishedDate = Date()
            }

            // Get file size if available
            let fileSize = dmgAsset["size"] as? Int64

            // Extract minimum OS version from release notes (if specified)
            let minimumOSVersion = extractMinimumOSVersion(from: releaseNotes)

            return AppUpdate(
                version: version,
                releaseNotes: releaseNotes,
                downloadURL: downloadURL,
                publishedDate: publishedDate,
                minimumOSVersion: minimumOSVersion,
                fileSize: fileSize
            )

        } catch {
            throw UpdateError.networkError(error)
        }
    }

    /// Download an update with progress tracking
    func downloadUpdate(_ update: AppUpdate, progress: @escaping (Double) -> Void) async throws -> URL {
        ApplicationLogger.shared.debug("GitHubUpdateProvider: Starting download from \(update.downloadURL)", category: .network)

        // Use URLSession's built-in download with delegate for progress
        let _ = URLRequest(url: update.downloadURL)

        // Download using standard URLSession (simpler approach)
        let (localURL, response) = try await URLSession.shared.download(from: update.downloadURL)

        // Note: For now, we'll use a simulated progress since URLSession's async download
        // doesn't provide built-in progress. This is a known limitation.
        // A proper implementation would use URLSessionDownloadTask with a delegate.

        guard let httpResponse = response as? HTTPURLResponse else {
            ApplicationLogger.shared.debug("Download failed: Invalid response type", category: .network)
            throw UpdateError.downloadFailed(UpdateError.invalidResponse)
        }

        ApplicationLogger.shared.debug("HTTP Status: \(httpResponse.statusCode)", category: .network)

        guard httpResponse.statusCode == 200 else {
            ApplicationLogger.shared.debug("Download failed: HTTP \(httpResponse.statusCode)", category: .network)
            throw UpdateError.downloadFailed(UpdateError.invalidResponse)
        }

        // For sandboxed apps, we need to use the user's actual Downloads folder, not the sandbox container
        // First try to get the actual Downloads folder
        let fileName = update.downloadURL.lastPathComponent
        let destinationURL: URL

        // Check if we're sandboxed
        let isSandboxed = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil

        if isSandboxed {
            // For sandboxed apps, keep the file in temp directory and return that
            // The system will handle opening it from there
            ApplicationLogger.shared.debug("App is sandboxed, keeping download in temp location", category: .network)

            // Create a better temp location with the actual filename
            let tempDir = FileManager.default.temporaryDirectory
            destinationURL = tempDir.appendingPathComponent(fileName)

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                ApplicationLogger.shared.debug("Removing existing file at destination", category: .network)
                try? FileManager.default.removeItem(at: destinationURL)
            }

            // Move to temp with proper name
            try FileManager.default.moveItem(at: localURL, to: destinationURL)
            ApplicationLogger.shared.debug("Download saved to temp: \(destinationURL.path)", category: .network)
        } else {
            // Non-sandboxed, use actual Downloads folder
            guard
                let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)
                .first
            else {
                ApplicationLogger.shared.debug("Could not find Downloads folder", category: .network)
                throw UpdateError.downloadFailed(UpdateError.invalidResponse)
            }

            destinationURL = downloadsURL.appendingPathComponent(fileName)

            ApplicationLogger.shared.debug("Moving download to: \(destinationURL.path)", category: .network)

            // Remove existing file if present
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                ApplicationLogger.shared.debug("Removing existing file at destination", category: .network)
                try? FileManager.default.removeItem(at: destinationURL)
            }

            // Move downloaded file
            try FileManager.default.moveItem(at: localURL, to: destinationURL)
        }

        ApplicationLogger.shared.debug("Download complete: \(destinationURL.path)", category: .network)

        // Call progress with 1.0 to indicate completion
        progress(1.0)

        return destinationURL
    }

    // MARK: - Helper Methods

    /// Extract minimum OS version from release notes
    private func extractMinimumOSVersion(from releaseNotes: String) -> String? {
        // Look for patterns like "Requires macOS 13.0" or "Minimum: macOS 14.0"
        let patterns = [
            "Requires macOS ([0-9]+(?:\\.[0-9]+)?)",
            "Minimum: macOS ([0-9]+(?:\\.[0-9]+)?)",
            "macOS ([0-9]+(?:\\.[0-9]+)?) or later",
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(
                   in: releaseNotes, range: NSRange(releaseNotes.startIndex..., in: releaseNotes)
               ),
               match.numberOfRanges > 1
            {
                let versionRange = match.range(at: 1)
                if let range = Range(versionRange, in: releaseNotes) {
                    return String(releaseNotes[range])
                }
            }
        }

        return nil
    }
}
