//
//  EventLoggerProtocol.swift
//  ImageIntact
//
//  Protocol for event logging functionality
//

import Foundation
import CoreData

/// Protocol for event logging operations
@MainActor
protocol EventLoggerProtocol: AnyObject {
    
    /// Start a new backup session
    func startSession(
        sourceURL: URL,
        fileCount: Int,
        totalBytes: Int64,
        sessionID: String?
    ) -> String
    
    /// Complete the current session
    func completeSession(status: String)
    
    /// Log a backup event
    func logEvent(
        type: EventType,
        severity: EventSeverity,
        file: URL?,
        destination: URL?,
        fileSize: Int64,
        checksum: String?,
        error: Error?,
        metadata: [String: Any]?,
        duration: TimeInterval?
    )
    
    /// Delete old sessions and events
    func deleteOldSessions(olderThan days: Int)
}

// Make EventLogger conform to protocol
extension EventLogger: EventLoggerProtocol {
    // Already implements all required methods
}

// MARK: - Mock Implementation for Testing

@MainActor
class MockEventLogger: EventLoggerProtocol {
    
    // Track calls for testing
    var startSessionCallCount = 0
    var completeSessionCallCount = 0
    var logEventCallCount = 0
    var deleteOldSessionsCallCount = 0
    
    // Store logged events for verification
    var loggedEvents: [(type: EventType, severity: EventSeverity, file: URL?, error: Error?)] = []
    
    // Control behavior
    var mockSessionID = UUID()
    var currentSessionID: UUID?
    
    func startSession(
        sourceURL: URL,
        fileCount: Int,
        totalBytes: Int64,
        sessionID: String? = nil
    ) -> String {
        startSessionCallCount += 1
        
        if let sessionID = sessionID {
            if let uuid = UUID(uuidString: sessionID) {
                currentSessionID = uuid
            }
            return sessionID
        } else {
            currentSessionID = mockSessionID
            return mockSessionID.uuidString
        }
    }
    
    func completeSession(status: String) {
        completeSessionCallCount += 1
        currentSessionID = nil
    }
    
    func logEvent(
        type: EventType,
        severity: EventSeverity = .info,
        file: URL? = nil,
        destination: URL? = nil,
        fileSize: Int64 = 0,
        checksum: String? = nil,
        error: Error? = nil,
        metadata: [String: Any]? = nil,
        duration: TimeInterval? = nil
    ) {
        logEventCallCount += 1
        loggedEvents.append((type: type, severity: severity, file: file, error: error))
    }
    
    func deleteOldSessions(olderThan days: Int = 30) {
        deleteOldSessionsCallCount += 1
    }
    
    func reset() {
        startSessionCallCount = 0
        completeSessionCallCount = 0
        logEventCallCount = 0
        deleteOldSessionsCallCount = 0
        loggedEvents.removeAll()
        currentSessionID = nil
    }
}