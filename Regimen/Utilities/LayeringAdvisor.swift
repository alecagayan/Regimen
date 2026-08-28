//
//  LayeringAdvisor.swift
//  Regimen
//

import Foundation

/// Computes the recommended application order for a set of active products.
///
/// Like `ConflictChecker`, this is deliberately simple and rule-based
/// rather than a personalized model: dermatological guidance on layering
/// order (cleanse, thinnest-to-thickest actives, then occlusives, sunscreen
/// last) is a small set of well-established category rules, not something
/// that needs machine learning or per-ingredient formulation data. See
/// `LayerCategory.rank` for the actual ordering table.
enum LayeringAdvisor {
    /// Sorts products by layer category first (cleanser through primer),
    /// then by the product's own `applicationOrder` as a tiebreaker within
    /// the same category. This is what drives the numbered steps shown in
    /// the Routine tab — it overrides a user's manual order across
    /// categories (a moisturizer never sorts before a cleanser even if
    /// mis-numbered), but respects it as a tiebreaker within one.
    static func recommendedOrder(for products: [Product]) -> [Product] {
        products.sorted { lhs, rhs in
            if lhs.layerCategory.rank != rhs.layerCategory.rank {
                return lhs.layerCategory.rank < rhs.layerCategory.rank
            }
            if lhs.applicationOrder != rhs.applicationOrder {
                return lhs.applicationOrder < rhs.applicationOrder
            }
            return lhs.name < rhs.name
        }
    }

    /// True when the user's manually-set `applicationOrder` disagrees with
    /// the layer-category-based recommendation — e.g. a moisturizer
    /// numbered ahead of a cleanser. Used to show a gentle explanatory
    /// note rather than silently overriding what the user typed.
    static func isManualOrderOutOfSync(_ products: [Product]) -> Bool {
        guard products.count > 1 else { return false }
        let manualOrder = products.sorted { $0.applicationOrder < $1.applicationOrder }
        return manualOrder.map(\.id) != recommendedOrder(for: products).map(\.id)
    }
}
