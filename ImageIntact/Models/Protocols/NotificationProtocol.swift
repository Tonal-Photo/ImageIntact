import Foundation

/// Protocol abstraction for notification operations
protocol NotificationProtocol {
    func sendBackupCompletionNotification(filesCopied: Int, destinations: Int, duration: TimeInterval)
    func requestNotificationPermission()
    func scheduleNotification(title: String, body: String, delay: TimeInterval)
}

/// Real implementation using NotificationManager
final class RealNotificationService: NotificationProtocol {
    
    func sendBackupCompletionNotification(filesCopied: Int, destinations: Int, duration: TimeInterval) {
        NotificationManager.shared.sendBackupCompletionNotification(
            filesCopied: filesCopied,
            destinations: destinations,
            duration: duration
        )
    }
    
    func requestNotificationPermission() {
        NotificationManager.shared.requestNotificationPermission()
    }
    
    func scheduleNotification(title: String, body: String, delay: TimeInterval) {
        // Would implement if NotificationManager had this method
        // For now, just use the completion notification
    }
}

/// Mock implementation for testing
final class MockNotificationService: NotificationProtocol {
    
    struct Notification {
        let title: String
        let body: String
        let timestamp: Date
        let filesCopied: Int?
        let destinations: Int?
        let duration: TimeInterval?
    }
    
    var sentNotifications: [Notification] = []
    var permissionRequested = false
    var shouldFailToSend = false
    
    func sendBackupCompletionNotification(filesCopied: Int, destinations: Int, duration: TimeInterval) {
        if shouldFailToSend {
            return
        }
        
        let title = "Backup Complete"
        let body = "\(filesCopied) files copied to \(destinations) destination(s) in \(formatDuration(duration))"
        
        sentNotifications.append(Notification(
            title: title,
            body: body,
            timestamp: Date(),
            filesCopied: filesCopied,
            destinations: destinations,
            duration: duration
        ))
    }
    
    func requestNotificationPermission() {
        permissionRequested = true
    }
    
    func scheduleNotification(title: String, body: String, delay: TimeInterval) {
        if shouldFailToSend {
            return
        }
        
        sentNotifications.append(Notification(
            title: title,
            body: body,
            timestamp: Date().addingTimeInterval(delay),
            filesCopied: nil,
            destinations: nil,
            duration: nil
        ))
    }
    
    // Test helper methods
    func reset() {
        sentNotifications.removeAll()
        permissionRequested = false
        shouldFailToSend = false
    }
    
    func lastNotification() -> Notification? {
        sentNotifications.last
    }
    
    func notificationCount() -> Int {
        sentNotifications.count
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1f seconds", duration)
        } else if duration < 3600 {
            let minutes = Int(duration / 60)
            let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration / 3600)
            let minutes = Int((duration.truncatingRemainder(dividingBy: 3600)) / 60)
            return "\(hours)h \(minutes)m"
        }
    }
}