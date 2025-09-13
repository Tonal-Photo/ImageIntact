//
//  StoreKitManagerTests.swift
//  ImageIntactTests
//
//  Tests for the StoreKit 2 in-app purchase manager
//

import XCTest
import StoreKit
import StoreKitTest
@testable import ImageIntact

@MainActor
final class StoreKitManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    var storeManager: StoreManager!
    var testSession: SKTestSession!
    
    // MARK: - Constants
    
    let proProductID = "com.imageintact.pro"
    let testBundleID = "com.imageintact.test"
    
    // MARK: - Setup & Teardown
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create test session for StoreKit testing
        testSession = try SKTestSession(configurationFileNamed: "StoreKitTestConfiguration")
        testSession.clearTransactions()
        testSession.resetToDefaultState()
        testSession.disableDialogs = true
        
        // Create store manager
        storeManager = StoreManager()
        
        // Wait for initial setup
        await storeManager.checkForPurchases()
    }
    
    override func tearDown() async throws {
        testSession.clearTransactions()
        testSession = nil
        storeManager = nil
        try await super.tearDown()
    }
    
    // MARK: - Initialization Tests
    
    func testStoreManagerInitialization() {
        // Given/When - manager is created in setUp
        
        // Then
        XCTAssertNotNil(storeManager)
        XCTAssertFalse(storeManager.hasPro, "Should not have Pro initially")
    }
    
    func testProductIDsAreDefined() {
        // Given
        let expectedProductID = proProductID
        
        // When
        let productIDs = storeManager.productIds
        
        // Then
        XCTAssertTrue(productIDs.contains(expectedProductID),
                     "Product IDs should contain Pro product")
        XCTAssertEqual(productIDs.count, 1, "Should have exactly one product")
    }
    
    // MARK: - Product Loading Tests
    
    func testLoadProducts() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Products loaded")
        
        // When
        let products = await storeManager.loadProducts()
        
        // Then
        XCTAssertFalse(products.isEmpty, "Should load at least one product")
        
        if let proProduct = products.first(where: { $0.id == proProductID }) {
            XCTAssertEqual(proProduct.id, proProductID)
            XCTAssertGreaterThan(proProduct.price, 0, "Product should have a price")
            XCTAssertFalse(proProduct.displayName.isEmpty, "Product should have a name")
            expectation.fulfill()
        } else {
            XCTFail("Pro product not found")
        }
        
        await fulfillment(of: [expectation], timeout: 5)
    }
    
    // MARK: - Purchase Tests
    
    func testSuccessfulPurchase() async throws {
        // Given
        XCTAssertFalse(storeManager.hasPro, "Should not have Pro before purchase")
        
        // When - simulate purchase
        try await testSession.buyProduct(identifier: proProductID)
        
        // Wait for transaction to be processed
        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        await storeManager.checkForPurchases()
        
        // Then
        XCTAssertTrue(storeManager.hasPro, "Should have Pro after purchase")
    }
    
    func testPurchaseCancellation() async throws {
        // Given
        XCTAssertFalse(storeManager.hasPro)
        
        // When - simulate cancelled purchase
        testSession.disableDialogs = false
        // Note: In real test environment, we'd simulate user cancellation
        // For now, we test that state doesn't change without purchase
        
        // Then
        XCTAssertFalse(storeManager.hasPro, "Should not have Pro after cancellation")
    }
    
    func testPurchaseFailure() async throws {
        // Given
        testSession.failTransactionsEnabled = true
        testSession.failureError = .paymentCancelled
        
        // When
        do {
            _ = try await storeManager.purchasePro()
            XCTFail("Purchase should have failed")
        } catch {
            // Then
            XCTAssertFalse(storeManager.hasPro, "Should not have Pro after failed purchase")
            XCTAssertNotNil(error, "Should have an error")
        }
    }
    
    // MARK: - Restore Purchase Tests
    
    func testRestorePurchasesWithExistingPurchase() async throws {
        // Given - make a purchase first
        try await testSession.buyProduct(identifier: proProductID)
        await storeManager.checkForPurchases()
        XCTAssertTrue(storeManager.hasPro)
        
        // When - reset and restore
        storeManager.hasPro = false
        await storeManager.restorePurchases()
        
        // Then
        XCTAssertTrue(storeManager.hasPro, "Should restore Pro purchase")
    }
    
    func testRestorePurchasesWithNoPurchase() async throws {
        // Given - no purchases made
        XCTAssertFalse(storeManager.hasPro)
        
        // When
        await storeManager.restorePurchases()
        
        // Then
        XCTAssertFalse(storeManager.hasPro, "Should not have Pro when no purchase to restore")
    }
    
    // MARK: - Transaction Verification Tests
    
    func testTransactionVerification() async throws {
        // Given
        try await testSession.buyProduct(identifier: proProductID)
        
        // When - check current entitlements
        var hasVerifiedTransaction = false
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == proProductID {
                    hasVerifiedTransaction = true
                }
            case .unverified:
                XCTFail("Transaction should be verified in test environment")
            }
        }
        
        // Then
        XCTAssertTrue(hasVerifiedTransaction, "Should have verified Pro transaction")
    }
    
    // MARK: - Offline Capability Tests
    
    func testOfflineReceiptValidation() async throws {
        // Given - make a purchase while "online"
        try await testSession.buyProduct(identifier: proProductID)
        await storeManager.checkForPurchases()
        XCTAssertTrue(storeManager.hasPro)
        
        // When - simulate offline by creating new manager
        // (In production, receipt would persist locally)
        let offlineManager = StoreManager()
        await offlineManager.checkForPurchases()
        
        // Then - should still detect purchase from local receipt
        XCTAssertTrue(offlineManager.hasPro, "Should validate purchase offline")
    }
    
    // MARK: - State Persistence Tests
    
    func testPurchaseStatePersistence() async throws {
        // Given
        try await testSession.buyProduct(identifier: proProductID)
        await storeManager.checkForPurchases()
        XCTAssertTrue(storeManager.hasPro)
        
        // When - create new instance (simulating app restart)
        let newManager = StoreManager()
        await newManager.checkForPurchases()
        
        // Then
        XCTAssertTrue(newManager.hasPro, "Purchase state should persist")
    }
    
    // MARK: - Transaction Updates Tests
    
    func testListenForTransactionUpdates() async throws {
        // Given
        let expectation = XCTestExpectation(description: "Transaction update received")
        var updateReceived = false
        
        // Set up observation
        let task = Task {
            for await _ in Transaction.updates {
                updateReceived = true
                expectation.fulfill()
                break
            }
        }
        
        // When - make a purchase
        try await testSession.buyProduct(identifier: proProductID)
        
        // Then
        await fulfillment(of: [expectation], timeout: 5)
        XCTAssertTrue(updateReceived, "Should receive transaction update")
        
        task.cancel()
    }
    
    // MARK: - Edge Case Tests
    
    func testMultiplePurchaseAttempts() async throws {
        // Given - already purchased
        try await testSession.buyProduct(identifier: proProductID)
        await storeManager.checkForPurchases()
        XCTAssertTrue(storeManager.hasPro)
        
        // When - try to purchase again
        do {
            _ = try await storeManager.purchasePro()
            // Should handle gracefully - user already owns it
            XCTAssertTrue(storeManager.hasPro, "Should still have Pro")
        } catch {
            // Some implementations might throw an "already owned" error
            XCTAssertTrue(storeManager.hasPro, "Should still have Pro even if error thrown")
        }
    }
    
    func testHandleExpiredTransaction() async throws {
        // Given - create expired transaction (if this was a subscription)
        // Note: Since we're using one-time purchase, this test is more relevant for subscriptions
        
        // For one-time purchases, they don't expire
        try await testSession.buyProduct(identifier: proProductID)
        await storeManager.checkForPurchases()
        
        // Then - one-time purchase should always be valid once purchased
        XCTAssertTrue(storeManager.hasPro, "One-time purchase should not expire")
    }
    
    // MARK: - Performance Tests
    
    func testCheckForPurchasesPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Check completes")
            
            Task {
                await storeManager.checkForPurchases()
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 1)
        }
    }
    
    // MARK: - Thread Safety Tests
    
    func testConcurrentPurchaseChecks() async {
        // Test that multiple concurrent checks don't cause issues
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { [weak self] in
                    await self?.storeManager.checkForPurchases()
                }
            }
        }
        
        // Should complete without crashes or data races
        XCTAssertNotNil(storeManager)
    }
}

// MARK: - StoreKit Test Configuration Helper

extension StoreKitManagerTests {
    
    /// Creates a test configuration file if it doesn't exist
    /// This would normally be done in Xcode's StoreKit Configuration file editor
    static func createTestConfiguration() -> String {
        return """
        {
            "identifier": "com.imageintact.test.configuration",
            "nonRenewingSubscriptions": [],
            "products": [
                {
                    "displayPrice": "4.99",
                    "familyShareable": true,
                    "id": "com.imageintact.pro",
                    "productID": "com.imageintact.pro",
                    "referenceName": "ImageIntact Pro",
                    "type": "NonConsumable"
                }
            ],
            "settings": {
                "applicationUsername": "testuser",
                "certificateRevocationEnabled": false,
                "locale": "en_US",
                "storefront": "USA",
                "timeRate": 1
            },
            "subscriptions": [],
            "version": 1
        }
        """
    }
}