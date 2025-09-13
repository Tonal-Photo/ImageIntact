//
//  StoreManager.swift
//  ImageIntact
//
//  Manages StoreKit 2 in-app purchases for ImageIntact Pro
//

import Foundation
import StoreKit
import SwiftUI

/// Manages in-app purchases using StoreKit 2
@MainActor
class StoreManager: NSObject, ObservableObject, StoreManagerProtocol {
    
    // MARK: - Singleton
    
    static let shared = StoreManager()
    
    // MARK: - Published Properties
    
    @Published var hasPro: Bool = false
    @Published var isLoading: Bool = false
    @Published var products: [Product] = []
    @Published var purchaseError: Error?
    
    // MARK: - Properties
    
    let productIds = ["com.imageintact.pro"]
    private var updateListenerTask: Task<Void, Error>?
    private var productsLoaded = false
    
    // MARK: - Initialization
    
    override init() {
        super.init()
        
        // Start listening for transactions
        updateListenerTask = listenForTransactions()
        
        // Check for existing purchases on launch
        Task {
            await checkForPurchases()
            await loadProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Product Loading
    
    /// Load products from the App Store
    @discardableResult
    func loadProducts() async -> [Product] {
        guard !productsLoaded else { return products }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            products = try await Product.products(for: productIds)
            productsLoaded = true
            return products
        } catch {
            print("Failed to load products: \(error)")
            purchaseError = error
            return []
        }
    }
    
    // MARK: - Purchase Checking
    
    /// Check for existing purchases - works offline after initial purchase
    func checkForPurchases() async {
        // Check current entitlements (cached locally by StoreKit)
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            
            if transaction.productID == productIds[0] {
                hasPro = true
                await transaction.finish()
            }
        }
    }
    
    // MARK: - Transaction Listener
    
    /// Listen for transaction updates
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            // Listen for transaction updates
            for await result in StoreKit.Transaction.updates {
                await self.handle(transactionResult: result)
            }
        }
    }
    
    /// Handle a transaction result
    private func handle(transactionResult: VerificationResult<StoreKit.Transaction>) async {
        guard case .verified(let transaction) = transactionResult else {
            // Transaction failed verification
            return
        }
        
        // Update purchase state
        if transaction.productID == productIds[0] {
            await MainActor.run {
                hasPro = true
            }
            
            // Finish the transaction
            await transaction.finish()
        }
    }
    
    // MARK: - Purchase Actions
    
    /// Purchase ImageIntact Pro
    func purchasePro() async throws -> Bool {
        // Load products if needed
        if products.isEmpty {
            await loadProducts()
        }
        
        guard let product = products.first else {
            throw StoreError.productNotFound
        }
        
        isLoading = true
        defer { isLoading = false }
        
        // Attempt purchase
        let result = try await product.purchase()
        
        switch result {
        case .success(let verification):
            // Handle successful purchase
            await handle(transactionResult: verification)
            return true
            
        case .userCancelled:
            // User cancelled - not an error
            return false
            
        case .pending:
            // Purchase is pending (e.g., waiting for parental approval)
            throw StoreError.purchasePending
            
        @unknown default:
            return false
        }
    }
    
    /// Restore previous purchases
    func restorePurchases() async {
        isLoading = true
        defer { isLoading = false }
        
        // Sync with App Store (requires internet)
        do {
            try await AppStore.sync()
        } catch {
            print("Failed to sync with App Store: \(error)")
            purchaseError = error
        }
        
        // Check for purchases (will find restored ones)
        await checkForPurchases()
    }
    
    // MARK: - Price Formatting
    
    /// Get formatted price for Pro upgrade
    var proPriceString: String {
        guard let product = products.first else {
            return "$4.99" // Fallback price
        }
        return product.displayPrice
    }
    
    /// Get product description
    var proDescription: String {
        guard let product = products.first else {
            return "Unlock all premium features"
        }
        return product.description
    }
}

// MARK: - Store Errors

enum StoreError: LocalizedError {
    case productNotFound
    case purchasePending
    case verificationFailed
    
    var errorDescription: String? {
        switch self {
        case .productNotFound:
            return "Product not found. Please check your internet connection and try again."
        case .purchasePending:
            return "Purchase is pending approval."
        case .verificationFailed:
            return "Purchase verification failed."
        }
    }
}

// MARK: - Purchase UI Components

/// A view that shows the purchase button for Pro
struct PurchaseProView: View {
    @StateObject private var store = StoreManager.shared
    @State private var isPurchasing = false
    @State private var showError = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("ImageIntact Pro")
                .font(.largeTitle)
                .fontWeight(.bold)
            
            Text("Unlock all premium features with a one-time purchase")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
            
            // Features list
            VStack(alignment: .leading, spacing: 12) {
                ForEach(PremiumFeatureManager.Feature.allCases, id: \.self) { feature in
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        
                        VStack(alignment: .leading) {
                            Text(feature.rawValue)
                                .fontWeight(.medium)
                            Text(feature.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(10)
            
            // Price and purchase button
            VStack(spacing: 10) {
                Text(store.proPriceString)
                    .font(.title)
                    .fontWeight(.bold)
                
                Button(action: purchase) {
                    if store.isLoading || isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .scaleEffect(0.8)
                    } else {
                        Text("Purchase Pro")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(store.isLoading || isPurchasing || store.hasPro)
                
                Button("Restore Purchase") {
                    Task {
                        await store.restorePurchases()
                    }
                }
                .buttonStyle(.borderless)
                .disabled(store.isLoading || isPurchasing)
            }
            
            // Family sharing note
            Label("Family Sharing Enabled", systemImage: "person.2.fill")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .alert("Purchase Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(store.purchaseError?.localizedDescription ?? "An error occurred")
        }
        .onChange(of: store.hasPro) { _, hasPro in
            if hasPro {
                // Dismiss the purchase view when Pro is purchased
                dismiss()
            }
        }
    }
    
    @Environment(\.dismiss) private var dismiss
    
    private func purchase() {
        isPurchasing = true
        
        Task {
            do {
                _ = try await store.purchasePro()
            } catch {
                store.purchaseError = error
                showError = true
            }
            
            isPurchasing = false
        }
    }
}