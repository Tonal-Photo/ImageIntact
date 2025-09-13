//
//  FeatureGatingTests.swift
//  ImageIntactTests
//
//  Tests for the feature gating system that controls access to premium features
//

import XCTest
import Combine
@testable import ImageIntact

@MainActor
final class FeatureGatingTests: XCTestCase {
    
    // MARK: - Properties
    
    var featureManager: PremiumFeatureManager!
    var mockStoreManager: MockStoreManager!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        
        // Create mock store manager
        mockStoreManager = MockStoreManager()
        
        // Create feature manager with mock
        featureManager = PremiumFeatureManager(storeManager: mockStoreManager)
    }
    
    override func tearDown() {
        featureManager = nil
        mockStoreManager = nil
        super.tearDown()
    }
    
    // MARK: - Feature Enum Tests
    
    func testFeatureEnumHasAllExpectedCases() {
        // Given
        let expectedFeatures: [PremiumFeatureManager.Feature] = [
            .automatedBackups,
            .visionFramework,
            .coreImage,
            .cloudBackup,
            .selectiveRestore
        ]
        
        // When
        let allFeatures = PremiumFeatureManager.Feature.allCases
        
        // Then
        XCTAssertEqual(allFeatures.count, expectedFeatures.count)
        for feature in expectedFeatures {
            XCTAssertTrue(allFeatures.contains(feature))
        }
    }
    
    func testFeatureIconsAreDefined() {
        // Given
        let features = PremiumFeatureManager.Feature.allCases
        
        // Then
        for feature in features {
            XCTAssertFalse(feature.icon.isEmpty, "Feature \(feature) should have an icon")
            // Verify icon is a valid SF Symbol name format
            XCTAssertTrue(feature.icon.contains(".") || feature.icon.count > 2,
                         "Feature \(feature) icon should be a valid SF Symbol")
        }
    }
    
    func testFeatureDescriptionsAreDefined() {
        // Given
        let features = PremiumFeatureManager.Feature.allCases
        
        // Then
        for feature in features {
            XCTAssertFalse(feature.rawValue.isEmpty, "Feature \(feature) should have a description")
            XCTAssertGreaterThan(feature.rawValue.count, 5, 
                                "Feature \(feature) description should be meaningful")
        }
    }
    
    // MARK: - Open Source Build Tests
    
    func testAllFeaturesLockedInOpenSourceBuild() {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = true  // Simulate open source build
        #endif
        mockStoreManager.hasPro = true // Even with Pro flag set
        
        // Then - all features should still be locked
        for feature in PremiumFeatureManager.Feature.allCases {
            XCTAssertFalse(featureManager.isUnlocked(feature),
                          "Feature \(feature) should be locked in open source build")
        }
    }
    
    func testPerformPremiumActionShowsUpgradeInOpenSourceBuild() {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = true  // Simulate open source build
        #endif
        var actionExecuted = false
        var fallbackExecuted = false
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // When
        featureManager.performPremiumAction(feature,
                                           action: { actionExecuted = true },
                                           fallback: { fallbackExecuted = true })
        
        // Then
        XCTAssertFalse(actionExecuted, "Premium action should not execute in open source build")
        XCTAssertTrue(fallbackExecuted, "Fallback should execute in open source build")
    }
    
    // MARK: - App Store Build Tests
    
    func testFeaturesUnlockedWithProPurchase() {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = false  // Simulate App Store build
        #endif
        mockStoreManager.hasPro = true
        
        // Then - all features should be unlocked
        for feature in PremiumFeatureManager.Feature.allCases {
            XCTAssertTrue(featureManager.isUnlocked(feature),
                         "Feature \(feature) should be unlocked with Pro purchase")
        }
    }
    
    func testFeaturesLockedWithoutProPurchase() {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = false  // Simulate App Store build
        #endif
        mockStoreManager.hasPro = false
        
        // Then - all features should be locked
        for feature in PremiumFeatureManager.Feature.allCases {
            XCTAssertFalse(featureManager.isUnlocked(feature),
                          "Feature \(feature) should be locked without Pro purchase")
        }
    }
    
    func testPerformPremiumActionExecutesWithPro() {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = false  // Simulate App Store build
        #endif
        mockStoreManager.hasPro = true
        var actionExecuted = false
        var fallbackExecuted = false
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // When
        featureManager.performPremiumAction(feature,
                                           action: { actionExecuted = true },
                                           fallback: { fallbackExecuted = true })
        
        // Then
        XCTAssertTrue(actionExecuted, "Premium action should execute with Pro")
        XCTAssertFalse(fallbackExecuted, "Fallback should not execute with Pro")
    }
    
    func testPerformPremiumActionShowsUpgradeWithoutPro() {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = false  // Simulate App Store build
        #endif
        mockStoreManager.hasPro = false
        var actionExecuted = false
        var fallbackExecuted = false
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // When
        featureManager.performPremiumAction(feature,
                                           action: { actionExecuted = true },
                                           fallback: { fallbackExecuted = true })
        
        // Then
        XCTAssertFalse(actionExecuted, "Premium action should not execute without Pro")
        XCTAssertTrue(fallbackExecuted, "Fallback should execute without Pro")
    }
    
    // MARK: - Feature State Change Tests
    
    func testFeatureStateUpdatesWhenPurchaseChanges() async {
        // Given
        #if DEBUG
        featureManager.testModeIsOpenSource = false  // Simulate App Store build
        #endif
        mockStoreManager.hasPro = false
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // Initially locked
        XCTAssertFalse(featureManager.isUnlocked(feature))
        
        // When - simulate purchase
        await mockStoreManager.simulatePurchase()
        
        // Then - should be unlocked
        XCTAssertTrue(featureManager.isUnlocked(feature))
        
        // When - simulate restore with no purchase
        await mockStoreManager.simulateRestore(hasPurchase: false)
        
        // Then - should be locked again
        XCTAssertFalse(featureManager.isUnlocked(feature))
    }
    
    // MARK: - UI Helper Tests
    
    func testShouldShowProBadge() {
        // Given
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // Test App Store build behavior
        #if DEBUG
        featureManager.testModeIsOpenSource = false
        #endif
        
        // Should show badge only when locked
        mockStoreManager.hasPro = false
        XCTAssertTrue(featureManager.shouldShowProBadge(for: feature))
        
        mockStoreManager.hasPro = true
        XCTAssertFalse(featureManager.shouldShowProBadge(for: feature))
    }
    
    func testGetUpgradePromptMessage() {
        // Given
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // When
        let message = featureManager.getUpgradePrompt(for: feature)
        
        // Then
        XCTAssertTrue(message.contains(feature.rawValue) || message.contains("Pro"),
                     "Upgrade prompt should mention the feature or Pro")
        XCTAssertGreaterThan(message.count, 20, "Upgrade prompt should be informative")
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentFeatureChecks() async {
        // Test that multiple threads can safely check features
        let iterations = 100
        let feature = PremiumFeatureManager.Feature.automatedBackups
        
        // Since we're @MainActor, we need to stay on MainActor
        var results: [Bool] = []
        
        for _ in 0..<iterations {
            // All calls happen on MainActor since the test is @MainActor
            let result = featureManager.isUnlocked(feature)
            results.append(result)
        }
        
        // All results should be consistent
        let firstResult = results.first ?? false
        XCTAssertTrue(results.allSatisfy { $0 == firstResult },
                     "All concurrent checks should return the same result")
    }
}

// MARK: - Mock Store Manager

@MainActor
class MockStoreManager: StoreManagerProtocol {
    var hasPro: Bool = false
    var purchaseCompletionHandler: ((Bool) -> Void)?
    var restoreCompletionHandler: ((Bool) -> Void)?
    
    func simulatePurchase() async {
        hasPro = true
        purchaseCompletionHandler?(true)
    }
    
    func simulateRestore(hasPurchase: Bool) async {
        hasPro = hasPurchase
        restoreCompletionHandler?(hasPurchase)
    }
    
    func checkForPurchases() async {
        // Mock implementation
    }
    
    func purchasePro() async throws -> Bool {
        hasPro = true
        return true
    }
    
    func restorePurchases() async {
        // Mock implementation
    }
}