import Foundation

/// Thread-safe cache for DriveInfo results keyed by volume UUID.
/// Eliminates redundant IOKit queries when the same drive is analyzed
/// by multiple callers (DriveMonitor, DestinationManager, callbacks).
final class DriveInfoCache {
    private var entries: [String: DriveAnalyzer.DriveInfo] = [:]
    private let lock = NSLock()

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    func get(volumeUUID: String) -> DriveAnalyzer.DriveInfo? {
        lock.lock()
        defer { lock.unlock() }
        return entries[volumeUUID]
    }

    func store(_ info: DriveAnalyzer.DriveInfo) {
        guard let uuid = info.volumeUUID else { return }
        lock.lock()
        defer { lock.unlock() }
        entries[uuid] = info
    }

    func invalidate(volumeUUID: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.removeValue(forKey: volumeUUID)
    }

    func invalidateAll() {
        lock.lock()
        defer { lock.unlock() }
        entries.removeAll()
    }
}
