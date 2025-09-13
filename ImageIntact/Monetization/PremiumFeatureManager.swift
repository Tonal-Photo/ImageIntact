//
//  PremiumFeatureManager.swift
//  ImageIntact
//
//  Manages access to premium features based on purchase status and build configuration
//

import Foundation
import SwiftUI

/// Manages premium feature access and gating
class PremiumFeatureManager: ObservableObject, PremiumFeatureManagerProtocol {
    
    // MARK: - Singleton
    
    static let shared = PremiumFeatureManager()
    
    // MARK: - Properties
    
    private let storeManager: StoreManagerProtocol
    
    // For testing only - allows overriding build detection
    #if DEBUG
    var testModeIsOpenSource: Bool?
    #endif
    
    // MARK: - Feature Definition
    
    enum Feature: String, CaseIterable {
        case automatedBackups = "Automated Backups"
        case visionFramework = "Smart Duplicate Detection"
        case coreImage = "Advanced Metadata"
        case cloudBackup = "Cloud Destinations"
        case selectiveRestore = "Selective Restore"
        
        var icon: String {
            switch self {
            case .automatedBackups: return "clock.arrow.circlepath"
            case .visionFramework: return "eye.circle"
            case .coreImage: return "camera.aperture"
            case .cloudBackup: return "icloud.and.arrow.up"
            case .selectiveRestore: return "arrow.down.doc"
            }
        }
        
        var description: String {
            switch self {
            case .automatedBackups:
                return "Schedule automatic backups to run at specified intervals"
            case .visionFramework:
                return "Use AI to detect duplicate images even with different names"
            case .coreImage:
                return "Extract and analyze advanced image metadata"
            case .cloudBackup:
                return "Backup directly to iCloud, Dropbox, and other cloud services"
            case .selectiveRestore:
                return "Choose specific files or folders to restore from backups"
            }
        }
    }
    
    // MARK: - Initialization
    
    init(storeManager: StoreManagerProtocol? = nil) {
        self.storeManager = storeManager ?? StoreManager.shared
    }
    
    // MARK: - Feature Access
    
    /// Check if a feature is unlocked
    @MainActor
    func isUnlocked(_ feature: Feature) -> Bool {
        // Check if this is an open source build
        #if DEBUG
        let isOpenSource = testModeIsOpenSource ?? BuildConfiguration.isOpenSourceBuild
        #else
        let isOpenSource = BuildConfiguration.isOpenSourceBuild
        #endif
        
        if isOpenSource {
            // GitHub version - all premium features locked
            return false
        } else {
            // App Store version - check purchase status
            return storeManager.hasPro
        }
    }
    
    /// Check if a feature can be used (tracks analytics)
    @MainActor
    func canUse(_ feature: Feature) -> Bool {
        let unlocked = isUnlocked(feature)
        
        // Track feature usage attempt
        if unlocked {
            AnalyticsManager.shared.trackFeatureUsage(feature)
        } else {
            AnalyticsManager.shared.trackEvent(.premiumFeatureAttempted, properties: ["feature": feature.rawValue])
        }
        
        return unlocked
    }
    
    /// Perform an action if feature is unlocked, otherwise show upgrade prompt
    @MainActor
    func performPremiumAction(_ feature: Feature, 
                             action: () -> Void,
                             fallback: () -> Void) {
        if isUnlocked(feature) {
            AnalyticsManager.shared.trackFeatureUsage(feature)
            action()
        } else {
            AnalyticsManager.shared.trackEvent(.premiumFeatureAttempted, properties: ["feature": feature.rawValue])
            fallback()
        }
    }
    
    /// Check if Pro badge should be shown for a feature
    @MainActor
    func shouldShowProBadge(for feature: Feature) -> Bool {
        return !isUnlocked(feature)
    }
    
    /// Get upgrade prompt message for a feature
    @MainActor
    func getUpgradePrompt(for feature: Feature) -> String {
        if BuildConfiguration.isOpenSourceBuild {
            return "\(feature.rawValue) is a Pro feature. This feature is only available in the App Store version of ImageIntact."
        } else {
            return "Upgrade to ImageIntact Pro to unlock \(feature.rawValue) and all other premium features with a one-time purchase."
        }
    }
    
    // MARK: - Batch Feature Checking
    
    /// Check if all features in a list are unlocked
    @MainActor
    func areAllUnlocked(_ features: [Feature]) -> Bool {
        return features.allSatisfy { isUnlocked($0) }
    }
    
    /// Get list of locked features from a set
    @MainActor
    func getLockedFeatures(from features: [Feature]) -> [Feature] {
        return features.filter { !isUnlocked($0) }
    }
    
    // MARK: - UI Helpers
    
    /// Get a SwiftUI view that shows feature status
    @MainActor
    func featureStatusView(for feature: Feature) -> some View {
        HStack {
            Image(systemName: feature.icon)
                .foregroundColor(isUnlocked(feature) ? .accentColor : .secondary)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(feature.rawValue)
                        .font(.headline)
                    
                    if shouldShowProBadge(for: feature) {
                        ProBadge()
                    }
                }
                
                Text(feature.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isUnlocked(feature) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .opacity(isUnlocked(feature) ? 1.0 : 0.7)
    }
}

// MARK: - Pro Badge View

struct ProBadge: View {
    var body: some View {
        Label("Pro", systemImage: "crown.fill")
            .font(.caption)
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.orange.opacity(0.15))
            )
    }
}

// MARK: - Feature Button View

struct PremiumFeatureButton: View {
    let feature: PremiumFeatureManager.Feature
    let action: () -> Void
    @State private var showingUpgradePrompt = false
    @StateObject private var featureManager = PremiumFeatureManager.shared
    
    var body: some View {
        Button(action: {
            featureManager.performPremiumAction(feature,
                action: action,
                fallback: { showingUpgradePrompt = true }
            )
        }) {
            HStack {
                Image(systemName: feature.icon)
                Text(feature.rawValue)
                
                if featureManager.shouldShowProBadge(for: feature) {
                    Spacer()
                    ProBadge()
                }
            }
        }
        .disabled(!featureManager.isUnlocked(feature) && false) // Never fully disable, allow tap for upgrade prompt
        .alert("Upgrade to Pro", isPresented: $showingUpgradePrompt) {
            #if !OPENSOURCE_BUILD
            Button("Upgrade Now") {
                Task {
                    try? await StoreManager.shared.purchasePro()
                }
            }
            #endif
            Button("Later", role: .cancel) { }
        } message: {
            Text(featureManager.getUpgradePrompt(for: feature))
        }
    }
}