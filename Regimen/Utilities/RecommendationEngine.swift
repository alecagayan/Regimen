//
//  RecommendationEngine.swift
//  Regimen
//

import Foundation

/// Turns a skin scan's findings into ingredient *categories* worth
/// browsing — one card per category, not a rendered sentence — so the UI
/// can show a tappable icon per category and defer the actual catalog
/// lookup until the user taps one (see CategoryProductsView). Same
/// deterministic, human-auditable style as `ConflictChecker`/
/// `LayeringAdvisor` — a hardcoded mapping from finding to ingredient tag
/// that's easy to read and retune in one place, not a model call.
enum RecommendationEngine {
    struct CategoryRecommendation: Identifiable, Hashable {
        let tag: ConflictTag
        /// Which finding first pulled this category in -- when a tag
        /// targets more than one finding (niacinamide covers both), only
        /// the first is kept, since this is just for card ordering.
        let finding: FindingKind
        /// Name of an owned, active product already covering this
        /// category, if any -- drives the "already have this" checkmark.
        let ownedProductName: String?

        var id: ConflictTag { tag }
    }

    /// Which ingredient tags address each finding, ordered by how directly
    /// they target it. A dermatology-adjacent starting point (BHA/niacinamide
    /// for breakouts, vitamin C/niacinamide for hyperpigmentation) — not a
    /// clinical protocol, and framed as such in the UI.
    static let targetTags: [FindingKind: [ConflictTag]] = [
        .blemish: [.exfoliatingAcid, .benzoylPeroxide, .niacinamide],
        .spot: [.vitaminCDerivative, .pureVitaminC, .niacinamide],
    ]

    /// One card per unique category across all findings, in finding order
    /// -- a tag targeting two findings (niacinamide) still shows once.
    static func categoryRecommendations(for counts: [FindingKind: Int], ownedProducts: [Product]) -> [CategoryRecommendation] {
        var seenTags = Set<ConflictTag>()
        var results: [CategoryRecommendation] = []

        for finding in FindingKind.allCases {
            guard (counts[finding] ?? 0) > 0, let tags = targetTags[finding] else { continue }
            for tag in tags where seenTags.insert(tag).inserted {
                let owned = ownedProducts.first { !$0.isArchived && $0.conflictTags.contains(tag) }
                results.append(CategoryRecommendation(tag: tag, finding: finding, ownedProductName: owned?.name))
            }
        }

        return results
    }
}

extension ConflictTag {
    /// SF Symbol for the category card -- a rough visual mnemonic per
    /// ingredient family, not a clinical icon set.
    var icon: String {
        switch self {
        case .none: "questionmark"
        case .retinoid: "moon.fill"
        case .exfoliatingAcid: "sparkles"
        case .pureVitaminC: "sun.max.fill"
        case .vitaminCDerivative: "sun.max.fill"
        case .niacinamide: "shield.fill"
        case .copperPeptide: "bolt.fill"
        case .benzoylPeroxide: "flame.fill"
        }
    }
}
