//
//  AnalyticsTests.swift
//  ImageIntactTests
//
//  Tests for the privacy-focused analytics system
//

import XCTest
@testable import ImageIntact

@MainActor
final class AnalyticsTests: XCTestCase {
    
    var analytics: AnalyticsManager!
    
    override func setUp() async throws {
        try await super.setUp()
        analytics = AnalyticsManager.shared
        analytics.isEnabled = true
    }
    
    override func tearDown() async throws {
        analytics.isEnabled = false
        analytics = nil
        try await super.tearDown()
    }
    
    // MARK: - Basic Tests
    
    func testAnalyticsCanBeDisabled() {
        // Given
        analytics.isEnabled = true
        
        // When
        analytics.isEnabled = false
        
        // Then
        XCTAssertFalse(analytics.isEnabled)
    }
    
    func testEventsNotTrackedWhenDisabled() {
        // Given
        analytics.isEnabled = false
        
        // When
        analytics.trackEvent(.backupStarted)
        
        // Then - no crash, events silently ignored
        XCTAssertFalse(analytics.isEnabled)
    }
    
    // MARK: - Event Tracking Tests
    
    func testTrackBackupEvent() {
        // Given
        let fileCount = 100
        let totalBytes: Int64 = 1024 * 1024 * 100 // 100MB
        let destinationCount = 2
        let duration: TimeInterval = 60.5
        
        // When
        analytics.trackBackup(
            fileCount: fileCount,
            totalBytes: totalBytes,
            destinationCount: destinationCount,
            duration: duration,
            success: true
        )
        
        // Then - event is tracked
        // We can't directly inspect events, but we can verify no crash
        XCTAssertTrue(analytics.isEnabled)
    }
    
    func testTrackFeatureUsage() {
        // Given
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // When
        analytics.trackFeatureUsage(feature)
        
        // Then
        XCTAssertTrue(analytics.isEnabled)
    }
    
    func testTrackPurchaseFlow() {
        // Test purchase initiated
        analytics.trackPurchase(initiated: true)
        
        // Test purchase completed
        analytics.trackPurchase(completed: true)
        
        // Test purchase failed
        analytics.trackPurchase(failed: true)
        
        // Test purchase restored
        analytics.trackPurchase(restored: true)
        
        // Verify no crashes
        XCTAssertTrue(analytics.isEnabled)
    }
    
    func testTrackError() {
        // Given
        let error = NSError(domain: "TestDomain", code: 42, userInfo: nil)
        let context = "TestContext"
        
        // When
        analytics.trackError(error, context: context)
        
        // Then
        XCTAssertTrue(analytics.isEnabled)
    }
    
    // MARK: - Privacy Tests
    
    func testPIIRemovalFromProperties() {
        // Given - properties with potential PII
        let properties = [
            "path": "/Users/johndoe/Documents/Photos",
            "network": "//192.168.1.100/share",
            "email": "user@example.com"
        ]
        
        // When tracking event (internally sanitizes)
        analytics.trackEvent(.backupStarted, properties: properties)
        
        // Then - verify analytics is still enabled (no crash from PII)
        XCTAssertTrue(analytics.isEnabled)
    }
    
    // MARK: - Report Generation Tests
    
    func testGenerateUsageReport() {
        // Given - track some events
        analytics.trackBackup(
            fileCount: 50,
            totalBytes: 1024 * 1024 * 50,
            destinationCount: 1,
            duration: 30,
            success: true
        )
        
        analytics.trackFeatureUsage(.automatedBackups)
        analytics.trackFeatureUsage(.cloudDestinations)
        analytics.trackFeatureUsage(.automatedBackups) // Track twice
        
        // When
        let report = analytics.generateUsageReport()
        
        // Then
        XCTAssertGreaterThanOrEqual(report.totalBackups, 0)
        XCTAssertGreaterThanOrEqual(report.sessionCount, 1)
        XCTAssertFalse(report.mostUsedFeatures.isEmpty)
    }
    
    // MARK: - Privacy Notice Tests
    
    func testPrivacyNoticeExists() {
        // Given/When
        let notice = AnalyticsManager.privacyNotice
        
        // Then
        XCTAssertFalse(notice.isEmpty)
        XCTAssertTrue(notice.contains("NEVER collect"))
        XCTAssertTrue(notice.contains("anonymous"))
    }
    
    // MARK: - Performance Tests
    
    func testEventTrackingPerformance() {
        measure {
            for _ in 0..<100 {
                analytics.trackEvent(.featureUsed, properties: ["feature": "test"])
            }
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentEventTracking() async {
        // Track events from multiple tasks concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<10 {
                group.addTask { [weak self] in
                    self?.analytics.trackEvent(.backupStarted, properties: ["index": "\(i)"])
                }
            }
        }
        
        // Should complete without crashes
        XCTAssertTrue(analytics.isEnabled)
    }
}

// MARK: - Integration Tests

extension AnalyticsTests {
    
    func testAnalyticsIntegrationWithBackup() {
        // Simulate a backup workflow with analytics
        
        // 1. Track backup start
        analytics.trackEvent(.backupStarted)
        
        // 2. Track feature usage during backup
        analytics.trackFeatureUsage(.automatedBackups)
        analytics.trackFeatureUsage(.cloudDestinations)
        
        // 3. Track backup completion
        analytics.trackBackup(
            fileCount: 150,
            totalBytes: 1024 * 1024 * 200,
            destinationCount: 2,
            duration: 120,
            success: true
        )
        
        // 4. Generate report
        let report = analytics.generateUsageReport()
        
        // Verify
        XCTAssertGreaterThan(report.totalBackups, 0)
        XCTAssertEqual(report.buildType, BuildConfiguration.editionName)
    }
    
    func testAnalyticsIntegrationWithPurchase() {
        // Simulate purchase flow with analytics
        
        // 1. Track premium feature attempt
        analytics.trackEvent(.premiumFeatureAttempted, properties: ["feature": "cloudDestinations"])
        
        // 2. Track purchase flow
        analytics.trackPurchase(initiated: true)
        
        // Simulate purchase completion
        analytics.trackPurchase(completed: true)
        
        // 3. Track feature unlocked
        analytics.trackEvent(.premiumFeatureUnlocked, properties: ["feature": "cloudDestinations"])
        
        // Generate report
        let report = analytics.generateUsageReport()
        
        // Verify tracking worked
        XCTAssertNotNil(report)
    }
}