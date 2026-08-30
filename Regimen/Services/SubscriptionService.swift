//
//  SubscriptionService.swift
//  Regimen
//

import Foundation
import StoreKit

enum SubscriptionError: Error {
    case failedVerification
    case productUnavailable
}

/// The two billing options for Regimen Premium -- same entitlement, same
/// App Store Connect subscription group (required: Apple treats plans in
/// one group as mutually exclusive upgrade/downgrade options, not
/// independent purchases), different renewal period.
enum SubscriptionPlan: String, CaseIterable {
    case monthly = "com.alecagayan.Regimen.premium.monthly2"
    case yearly = "com.alecagayan.Regimen.premium.yearly"
}

/// A single $0.99 consumable: one extra streak restore, past the free
/// one-every-30-days limit (see `AppData.daysBetweenStreakRestores`).
/// Unlike the subscription plans, this isn't an entitlement StoreKit
/// remembers -- a consumable only shows up once, at the moment of
/// purchase, so the app has to keep its own balance (`Profile.
/// purchasedRestoreCredits`) of what's been bought and not yet spent.
private let restoreCreditProductID = "com.alecagayan.Regimen.streakrestore.single"

/// Wraps StoreKit 2 for the subscription plans this app sells. This
/// device's verified entitlement (`hasActiveEntitlement`) is the actual
/// source of truth; `AppData.isPremium` mirrors it into the Supabase
/// `profiles.is_premium` flag purely so other views (and other signed-in
/// devices, until they next check StoreKit themselves) have something to
/// read instantly without an async StoreKit round trip.
///
/// Tested locally against `Regimen.storekit` (Xcode's StoreKit Testing --
/// see Edit Scheme > Run > Options > StoreKit Configuration). Once real
/// products are created in App Store Connect with the same product IDs,
/// this same code talks to the live App Store with no changes.
@MainActor
@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    // `StoreKit.Product` needs full qualification throughout this file --
    // the app already has its own `Product` (a skincare item, see
    // Models/Product.swift), and that's what the bare name resolves to.
    private(set) var products: [SubscriptionPlan: StoreKit.Product] = [:]
    private(set) var restoreCreditProduct: StoreKit.Product?
    private(set) var isPurchasing = false

    /// Set by `AppData` so a transaction that lands outside an explicit
    /// `purchase()` call -- a renewal, a refund, an Ask to Buy approval, a
    /// restore initiated from Settings -- still reconciles the mirrored
    /// Supabase flag.
    var onEntitlementChanged: (@MainActor () async -> Void)?

    // Not cancelled in a deinit: this is a permanent singleton (`shared`)
    // that lives for the process's whole lifetime, so deinit never runs in
    // practice, and a MainActor class's deinit is nonisolated anyway --
    // it couldn't touch this actor-isolated property without an
    // await/Task hop.
    private var transactionListener: Task<Void, Never>?

    private init() {
        transactionListener = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self, let transaction = try? self.verified(update) else { continue }
                await transaction.finish()
                await self.onEntitlementChanged?()
            }
        }
    }

    func product(for plan: SubscriptionPlan) -> StoreKit.Product? {
        products[plan]
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        do {
            let fetched = try await StoreKit.Product.products(for: SubscriptionPlan.allCases.map(\.rawValue))
            for product in fetched {
                guard let plan = SubscriptionPlan(rawValue: product.id) else { continue }
                products[plan] = product
            }
        } catch {
            print("SubscriptionService.loadProducts failed: \(error)")
        }
    }

    /// Scans this device's currently-valid transactions -- the real check,
    /// not the cached Supabase flag. True for *either* plan: monthly and
    /// yearly grant the identical entitlement, just billed differently.
    func hasActiveEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard let transaction = try? verified(result) else { continue }
            if SubscriptionPlan(rawValue: transaction.productID) != nil, transaction.revocationDate == nil {
                return true
            }
        }
        return false
    }

    /// Returns `true` once the purchase completes and is entitled. `false`
    /// for a user-cancelled or pending (e.g. Ask to Buy) purchase -- both
    /// legitimate outcomes, not errors.
    @discardableResult
    func purchase(_ plan: SubscriptionPlan) async throws -> Bool {
        await loadProducts()
        guard let product = products[plan] else { throw SubscriptionError.productUnavailable }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    /// Re-syncs this device's transactions with the App Store -- for a
    /// "Restore Purchases" button (a fresh install, a new device, or a
    /// purchase made outside this app session).
    func restore() async throws {
        try await AppStore.sync()
    }

    // MARK: - Restore credit (consumable)

    func loadRestoreCreditProduct() async {
        guard restoreCreditProduct == nil else { return }
        do {
            restoreCreditProduct = try await StoreKit.Product.products(for: [restoreCreditProductID]).first
        } catch {
            print("SubscriptionService.loadRestoreCreditProduct failed: \(error)")
        }
    }

    /// Buys one restore credit. Unlike `purchase(_:)`, success here doesn't
    /// mean "entitled" -- it means the credit still needs to be added to
    /// `AppData`'s balance and persisted, which is the caller's job (see
    /// `AppData.purchaseStreakRestoreCredit`), since a consumable's value
    /// exists only as this app's own bookkeeping, not anything StoreKit
    /// remembers afterward.
    @discardableResult
    func purchaseRestoreCredit() async throws -> Bool {
        await loadRestoreCreditProduct()
        guard let restoreCreditProduct else { throw SubscriptionError.productUnavailable }

        isPurchasing = true
        defer { isPurchasing = false }

        let result = try await restoreCreditProduct.purchase()
        switch result {
        case .success(let verification):
            let transaction = try verified(verification)
            // Consumables must be finished immediately after the benefit
            // is granted, not deferred to the shared transaction listener
            // -- Apple never re-surfaces a consumable transaction the way
            // it does subscriptions, so there's no later chance to catch
            // this one if it's left unfinished.
            await transaction.finish()
            return true
        case .userCancelled, .pending:
            return false
        @unknown default:
            return false
        }
    }

    private func verified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.failedVerification
        case .verified(let safe):
            return safe
        }
    }
}
