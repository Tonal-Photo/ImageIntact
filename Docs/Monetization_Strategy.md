# ImageIntact Monetization Strategy

## Overview
ImageIntact will maintain a dual-edition model:
- **Open Source Edition**: Free, GitHub-distributed, includes all core features
- **Pro Edition**: App Store version with optional in-app purchases for premium features

## Core Principle
Core backup functionality will always remain free and open source. Premium features fund continued development and benefit all users through bug fixes and improvements.

## v2.0 HYBRID MODEL (IMPLEMENTED)

### Decision: Free Analysis + Pro Search

For v2.0, we implemented a **hybrid monetization model** that provides maximum value:

**FREE for Apple Silicon Users:**
- ✅ Vision Framework analysis (objects, scenes, faces, text OCR)
- ✅ Core Image analysis (colors, quality, histograms, EXIF)
- ✅ Drive UUID tracking for removable media
- ✅ All metadata stored in Core Data
- ✅ Analysis happens automatically during backup

**Pro Features ($4.99 one-time):**
- 🔒 Smart Search interface (natural language queries)
- 🔒 Browse Mode (drill-down by categories)
- 🔒 Semantic search with Foundation Models (macOS 26+)
- 🔒 Confidence scoring and AI ranking

### Rationale

1. **Better User Experience**: Users see immediate value (free analysis) during backup
2. **Clear Value Proposition**: "Your backups get smart for free; upgrade to search them"
3. **Lower Barrier to Entry**: No paywall blocking core AI features
4. **Premium Justification**: Search UI is the true value-add worth $4.99
5. **Implementation Simplicity**: Only gate UI, not backend analyzers

### Implementation Status (v2.0.0) - ✅ COMPLETED

**Completed: January 26, 2025**

- ✅ Feature gating added to Smart Search button (ContentView.swift:61-84)
- ✅ Pro badge shows/hides reactively based on purchase status
- ✅ Upgrade alert with "Smart Search Requires Pro" message and pricing
- ✅ PurchaseProView integrated with Close button
- ✅ StoreKit 2 configuration: `ImageIntactStore.storekit`
- ✅ Product ID: `com.tonalphoto.tech.ImageIntact.pro`
- ✅ Price: $4.99 (one-time, non-consumable, family shareable)
- ✅ All documentation updated (README, CHANGELOG, HelpView, App Store copy)
- ✅ Sandbox testing completed and verified:
  - Purchase flow works
  - Receipt persistence confirmed (offline validation)
  - Features unlock correctly after purchase
  - Crown badge reactivity working (@StateObject StoreManager)

**Ready for App Store submission.**

### Future Premium Features (v2.1+)

The following features remain planned as Pro additions:
- 🔒 Automated scheduled backups
- 🔒 Cloud backup destinations (iCloud, Dropbox, Google Drive)
- 🔒 Advanced selective restore
- 🔒 AI-powered similarity detection
- 🔒 Face grouping (privacy-aware)

## Edition Comparison

### Open Source Edition (GitHub)
**Always Free:**
- ✅ Manual backup/restore
- ✅ Multi-destination support
- ✅ Checksum verification
- ✅ File organization by date/type
- ✅ Duplicate detection (basic)
- ✅ All current features
- ✅ All bug fixes and performance improvements
- ✅ Community support

### Pro Edition (App Store)
**Free Features:**
- Everything in Open Source Edition

**Premium Features (IAP - $4.99 one-time):**
- ✅ Smart Search interface (natural language queries) - **IMPLEMENTED v2.0**
- ✅ Browse Mode (category drill-down) - **IMPLEMENTED v2.0**
- ✅ Semantic search with Foundation Models - **IMPLEMENTED v2.0**
- 🔒 Automated scheduled backups - **PLANNED v2.1**
- 🔒 Cloud backup destinations (iCloud, Dropbox, etc.) - **PLANNED v2.2**
- 🔒 Advanced restore with selective file recovery - **PLANNED v2.3**
- 🔒 AI-powered similarity detection - **PLANNED v2.2**
- 🔒 Face grouping (privacy-aware) - **PLANNED v2.2**

**Note**: Vision Framework and Core Image analysis are now FREE in v2.0. Only the search/browse UI requires Pro.

## Implementation Strategy: Option B - Runtime Feature Flags

### How It Works

1. **Single Codebase**: All code is open source and available on GitHub
2. **Build Configurations**: Use compiler flags to differentiate builds
   - `OPENSOURCE_BUILD`: GitHub releases
   - `APPSTORE_BUILD`: App Store releases
3. **Runtime Checks**: Features check for valid purchases at runtime
4. **Graceful Degradation**: Premium features show as "Pro Only" in open source builds

### Receipt Validation - How It Actually Works

#### Local Receipt Storage (Offline-Capable)
When a user makes an in-app purchase on macOS:

1. **Purchase Flow**:
   - User initiates purchase through StoreKit 2
   - Apple processes payment
   - App receives transaction confirmation
   - Receipt is stored in the app's container

2. **Receipt Location**:
   ```
   /Contents/_MASReceipt/receipt (App Store apps)
   ~/Library/Receipts/ (for testing)
   ```

3. **Offline Validation**:
   - The receipt is cryptographically signed by Apple
   - Your app validates the signature locally
   - No internet connection required after initial purchase
   - Receipt contains all purchase history

4. **What's In The Receipt**:
   - Bundle identifier
   - App version
   - Original purchase date
   - In-app purchase transactions
   - Subscription status (if applicable)

#### StoreKit 2 Implementation (Modern Approach)

```swift
import StoreKit

class StoreManager: ObservableObject {
    static let shared = StoreManager()
    
    @Published var hasPro = false
    private var updateListenerTask: Task<Void, Error>?
    
    // Product IDs
    private let productIds = ["com.imageintact.pro"]
    
    init() {
        // Check for existing purchases on launch
        updateListenerTask = listenForTransactions()
        
        Task {
            await checkForPurchases()
        }
    }
    
    // This runs on app launch - NO INTERNET REQUIRED
    func checkForPurchases() async {
        // StoreKit 2 caches purchases locally
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.productID == "com.imageintact.pro" {
                hasPro = true
            }
        }
    }
    
    // Listen for new purchases
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                await self.handle(transactionResult: result)
            }
        }
    }
    
    // Purchase the Pro version
    func purchasePro() async throws {
        let products = try await Product.products(for: productIds)
        guard let pro = products.first else { return }
        
        let result = try await pro.purchase()
        
        switch result {
        case .success(let verification):
            await handle(transactionResult: verification)
        case .userCancelled:
            break
        case .pending:
            // Waiting for approval (parental controls, etc.)
            break
        @unknown default:
            break
        }
    }
    
    private func handle(transactionResult: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = transactionResult else { return }
        
        if transaction.productID == "com.imageintact.pro" {
            hasPro = true
            await transaction.finish()
        }
    }
    
    // Restore purchases (e.g., on new device)
    func restorePurchases() async {
        // This DOES require internet to sync with App Store
        try? await AppStore.sync()
        await checkForPurchases()
    }
}
```

### Key Points About Offline Operation

1. **Initial Purchase**: Requires internet (obviously)
2. **After Purchase**: Works completely offline
3. **Receipt Validation**: Happens locally using Apple's cryptographic signature
4. **New Device**: Requires one-time internet to restore purchases
5. **Receipt Refresh**: Only needed if receipt is corrupted or missing

### Feature Gating Implementation

```swift
class PremiumFeatureManager {
    static let shared = PremiumFeatureManager()
    
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
    }
    
    func isUnlocked(_ feature: Feature) -> Bool {
        #if OPENSOURCE_BUILD
        // GitHub version - all premium features locked
        return false
        #else
        // App Store version - check purchase status
        return StoreManager.shared.hasPro
        #endif
    }
    
    func performPremiumAction(_ feature: Feature, action: () -> Void, fallback: () -> Void) {
        if isUnlocked(feature) {
            action()
        } else {
            fallback()  // Show upgrade prompt
        }
    }
}
```

### UI Implementation

```swift
struct FeatureButton: View {
    let feature: PremiumFeatureManager.Feature
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            PremiumFeatureManager.shared.performPremiumAction(feature) {
                action()
            } fallback: {
                showUpgradePrompt()
            }
        }) {
            HStack {
                Image(systemName: feature.icon)
                Text(feature.rawValue)
                
                if !PremiumFeatureManager.shared.isUnlocked(feature) {
                    Spacer()
                    Label("Pro", systemImage: "crown.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
    }
    
    private func showUpgradePrompt() {
        // Show purchase UI
    }
}
```

## Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Implement StoreKit 2 manager
- [ ] Create feature gating system
- [ ] Add build configurations
- [ ] Update CI/CD for dual builds

### Phase 2: First Premium Feature (Week 2)
- [ ] Implement automated backups as first premium feature
- [ ] Add purchase UI
- [ ] Test end-to-end flow
- [ ] Update onboarding to explain editions

### Phase 3: Rollout (Week 3)
- [ ] Submit to App Store with IAP
- [ ] Update GitHub README
- [ ] Create comparison webpage
- [ ] Announce to community

### Phase 4: Additional Features (Ongoing)
- [ ] Add Vision Framework features
- [ ] Add Core Image features
- [ ] Implement cloud destinations
- [ ] Add selective restore

## Pricing Strategy

### Recommended: One-Time Purchase
- **ImageIntact Pro**: $19.99 (one-time)
- Unlocks all current and future Pro features
- Family sharing enabled
- No subscriptions

### Alternative: Freemium with Multiple IAPs
- Individual features: $4.99 each
- Complete bundle: $14.99
- More complex but allows incremental purchases

## GitHub Release Strategy

### Build Process
```yaml
# .github/workflows/release.yml
env:
  SWIFT_FLAGS: -D OPENSOURCE_BUILD
```

### Release Notes Template
```markdown
## ImageIntact v1.X.X

### What's New
- Feature improvements
- Bug fixes
- Performance enhancements

### Pro Features (App Store Only)
- Automated backups
- Advanced duplicate detection
- Cloud destinations

*Core features remain free and open source. Pro features available via App Store.*
```

## FAQ for Users

**Q: Why add paid features to an open source app?**
A: Core functionality remains free forever. Premium features fund continued development, benefiting all users through improvements and bug fixes.

**Q: Can I compile my own version with all features?**
A: The code is open source, but premium features require valid App Store receipts. You're welcome to fork and modify for personal use.

**Q: Will GitHub version still receive updates?**
A: Yes! All bug fixes, performance improvements, and core features will always be available in the GitHub version.

**Q: Is it a subscription?**
A: No. One-time purchase unlocks all current and future Pro features.

## Success Metrics

- **Target**: 2-5% of active users purchase Pro
- **Break-even**: ~100 purchases/month covers development time
- **Success**: 500+ purchases validates continued investment

## Risk Mitigation

1. **Fork Risk**: Accept that some users will bypass IAP
2. **Complexity Risk**: Start with single IAP, not multiple tiers
3. **Community Risk**: Clear communication about funding model
4. **Technical Risk**: Thorough testing of receipt validation

## Next Steps

1. Implement StoreManager class
2. Add feature flags to existing code
3. Create purchase UI
4. Test with sandbox accounts
5. Submit to App Store review