import Foundation

/// Stateless utility for bookmark persistence (security-scoped bookmarks for sandbox access).
/// Extracted from BackupManager to isolate bookmark concerns.
struct BookmarkManager {
    // MARK: - Constants

    static let sourceKey = "sourceBookmark"
    static let destinationKeys = ["dest1Bookmark", "dest2Bookmark", "dest3Bookmark", "dest4Bookmark"]

    // MARK: - Save

    static func saveBookmark(url: URL, key: String) {
        do {
            // Start accessing the security-scoped resource before creating bookmark
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let bookmark = try url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
            )
            UserDefaults.standard.set(bookmark, forKey: key)
            // UserDefaults auto-saves; synchronize() is a deprecated no-op
            logInfo("Successfully saved bookmark for \(key): \(url.lastPathComponent)")
        } catch {
            logError("Failed to save bookmark for \(key): \(error)")
        }
    }

    // MARK: - Load

    static func loadBookmark(forKey key: String) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return loadBookmark(from: data, forKey: key)
    }

    static func loadBookmark(from data: Data, forKey key: String? = nil) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data, options: [.withoutUI, .withSecurityScope], relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else { return nil }

        // Re-create stale bookmarks while we still have access.
        // Without this, bookmarks degrade silently after system updates or
        // volume renames until they stop resolving entirely.
        // See: GH issue #91, finding #5.
        if isStale, let key = key {
            // Must access the security-scoped resource before creating new bookmark data
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }

            guard accessing else {
                ApplicationLogger.shared.debug("Cannot refresh stale bookmark for \(key): access denied", category: .fileSystem)
                return url // Still return the URL — it resolved, just can't refresh
            }

            if let refreshed = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(refreshed, forKey: key)
                ApplicationLogger.shared.debug("Refreshed stale bookmark for \(key)", category: .fileSystem)
            }
        }

        return url
    }

    // MARK: - Create

    static func createBookmark(for url: URL) -> Data? {
        return try? url.bookmarkData(
            options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
            includingResourceValuesForKeys: nil, relativeTo: nil
        )
    }

    // MARK: - Load Destinations

    static func loadDestinationBookmarks() -> [URL?] {
        var urls: [URL?] = []

        // Load bookmarks sequentially until we hit a gap
        for key in destinationKeys {
            if let url = loadBookmark(forKey: key) {
                logInfo("Loaded destination from \(key): \(url.lastPathComponent)")
                urls.append(url)
            } else {
                logInfo("No bookmark found for \(key)")
                // Stop at first missing bookmark to avoid gaps
                break
            }
        }

        // Always show at least one slot
        if urls.isEmpty {
            urls = [nil]
        }

        logInfo("Total destinations loaded: \(urls.count)")
        return urls
    }
}
