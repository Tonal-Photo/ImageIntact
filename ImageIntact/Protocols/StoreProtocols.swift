//
//  StoreProtocols.swift
//  ImageIntact
//
//  Protocol definitions for Store and Feature management
//

import Foundation
import Combine

/// Protocol for Store Manager functionality
@MainActor
protocol StoreManagerProtocol: AnyObject {
    /// Indicates whether the user has purchased Pro
    var hasPro: Bool { get }
    
    /// Check for existing purchases
    func checkForPurchases() async
    
    /// Purchase the Pro version
    func purchasePro() async throws -> Bool
    
    /// Restore previous purchases
    func restorePurchases() async
}

/// Protocol for Premium Feature management
@MainActor
protocol PremiumFeatureManagerProtocol {
    /// Check if a feature is unlocked
    func isUnlocked(_ feature: PremiumFeatureManager.Feature) -> Bool
    
    /// Perform an action if the feature is unlocked, otherwise show upgrade prompt
    func performPremiumAction(_ feature: PremiumFeatureManager.Feature,
                             action: () -> Void,
                             fallback: () -> Void)
    
    /// Check if Pro badge should be shown for a feature
    func shouldShowProBadge(for feature: PremiumFeatureManager.Feature) -> Bool
    
    /// Get upgrade prompt message for a feature
    func getUpgradePrompt(for feature: PremiumFeatureManager.Feature) -> String
}