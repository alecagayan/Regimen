//
//  RoutineBuilderEngine.swift
//  Regimen
//

import Foundation

/// Assembles a complete AM/PM routine from scan findings plus what the user
/// told us about their own skin (`SkinProfile`), one step per
/// `LayerCategory` in its established layering order (see that type's
/// `rank`) -- an owned, active product if one already covers the step,
/// otherwise a catalog suggestion, preferring one that targets what the
/// scan actually found (via `RecommendationEngine`'s tag table) for the
/// Treatment step specifically. Deterministic and auditable, same style as
/// `ConflictChecker`/`LayeringAdvisor` -- no model call.
enum RoutineBuilderEngine {
    struct RoutineItem: Identifiable {
        let layerCategory: LayerCategory
        let routineTime: RoutineTime
        /// Exactly one of these is set.
        let ownedProduct: Product?
        let catalogProduct: CatalogProduct?
        let reason: String

        var id: LayerCategory { layerCategory }
        var name: String { ownedProduct?.name ?? catalogProduct?.name ?? "" }
        var brand: String { ownedProduct?.brand ?? catalogProduct?.brand ?? "" }
    }

    /// Actives that are too much for skin the user described as sensitive,
    /// or for someone who told us they're new to this. Both are the common
    /// starting advice: build tolerance on gentler ingredients first, since
    /// an irritated barrier undoes whatever the active was meant to fix.
    private static let demandingTags: Set<ConflictTag> = [.retinoid, .exfoliatingAcid, .pureVitaminC]

    /// Which conflict tags a Treatment-step suggestion should prefer, in
    /// priority order, pooled across every active finding -- reuses
    /// `RecommendationEngine.targetTags` so this stays in sync with what
    /// the category cards already recommend.
    private static func preferredTreatmentTags(for counts: [FindingKind: Int], profile: SkinProfile) -> [ConflictTag] {
        let fromFindings = FindingKind.allCases
            .filter { (counts[$0] ?? 0) > 0 }
            .compactMap { RecommendationEngine.targetTags[$0] }
            .flatMap { $0 }
        guard shouldAvoidDemandingActives(profile) else { return fromFindings }
        return fromFindings.filter { !demandingTags.contains($0) }
    }

    private static func shouldAvoidDemandingActives(_ profile: SkinProfile) -> Bool {
        profile.isSensitive || profile.experience == .beginner
    }

    /// Sunscreen is AM-only and actives that raise photosensitivity go at
    /// night -- a standard, non-personalized convention (the same one
    /// `ConflictChecker`/`PlanEngine` already assume), not derived from
    /// any per-product data since the catalog doesn't store a routine time
    /// (that's chosen when a product is actually added to a cabinet). Checks
    /// every tag the product carries, since a photosensitizing active might
    /// not be the first one listed.
    private static func routineTime(for layerCategory: LayerCategory, conflictTags: [ConflictTag]) -> RoutineTime {
        if layerCategory == .sunscreen { return .am }
        if conflictTags.contains(.retinoid) || conflictTags.contains(.exfoliatingAcid) { return .pm }
        return .both
    }

    /// Steps to build, given what the user said about their skin. Makeup is
    /// always excluded (see `LayerCategory.isSkincareStep`); facial oil is
    /// dropped for oily skin, where an extra occlusive layer is the last
    /// thing the routine needs; and the requested routine length trims (or
    /// keeps) the steps beyond the four non-negotiable ones.
    private static func categories(for profile: SkinProfile) -> [LayerCategory] {
        LayerCategory.allCases
            .filter(\.isSkincareStep)
            .filter { includesStep($0, for: profile.routineLength) }
            .filter { !($0 == .facialOil && profile.skinType == .oily) }
            .sorted { $0.rank < $1.rank }
    }

    /// Cleanser, treatment, moisturizer, and sunscreen are the routine at
    /// every length -- skin still needs cleaning, a shot at whatever the
    /// scan flagged, hydration, and daily protection regardless of how
    /// much time someone wants to spend. Toner, eye care, and facial oil
    /// are the steps that actually make a routine feel "short" or "long",
    /// so those are what scale with the answer.
    private static func includesStep(_ layerCategory: LayerCategory, for length: RoutineLength) -> Bool {
        switch layerCategory {
        case .cleanser, .treatment, .moisturizer, .sunscreen:
            return true
        case .toner:
            return length != .short
        case .eyeCare, .facialOil:
            return length == .long
        case .primer:
            return false
        }
    }

    static func buildRoutine(
        for counts: [FindingKind: Int],
        ownedProducts: [Product],
        profile: SkinProfile
    ) async -> [RoutineItem] {
        let active = ownedProducts.filter { !$0.isArchived }
        // Face skincare only -- see `CatalogProduct.isFaceRoutineCandidate`
        // for why the catalog's own categories aren't enough on their own.
        let catalog = ((try? await CatalogService.search("")) ?? []).filter(\.isFaceRoutineCandidate)
        let treatmentTags = preferredTreatmentTags(for: counts, profile: profile)
        let avoidDemanding = shouldAvoidDemandingActives(profile)

        return categories(for: profile).compactMap { layerCategory -> RoutineItem? in
            if let owned = active.first(where: { $0.layerCategory == layerCategory }) {
                return RoutineItem(
                    layerCategory: layerCategory,
                    routineTime: owned.routineTime,
                    ownedProduct: owned,
                    catalogProduct: nil,
                    reason: "Already in your cabinet."
                )
            }

            var candidates = catalog.filter { $0.layerCategory == layerCategory }
            if avoidDemanding {
                // Never leave a step empty just because the gentle filter
                // removed everything -- fall back to the unfiltered set.
                // Excluded if it carries *any* demanding tag, not just a
                // first/primary one.
                let gentle = candidates.filter { demandingTags.isDisjoint(with: $0.suggestedConflictTags) }
                if !gentle.isEmpty { candidates = gentle }
            }
            guard !candidates.isEmpty else { return nil }

            if layerCategory == .treatment, let targeted = treatmentTags.lazy.compactMap({ tag in
                candidates.first { $0.suggestedConflictTags.contains(tag) }
            }).first {
                return RoutineItem(
                    layerCategory: layerCategory,
                    routineTime: routineTime(for: layerCategory, conflictTags: targeted.suggestedConflictTags),
                    ownedProduct: nil,
                    catalogProduct: targeted,
                    reason: avoidDemanding
                        ? "Targets this scan, gentle enough to start on."
                        : "Targets what this scan flagged."
                )
            }

            let fallback = candidates[0]
            return RoutineItem(
                layerCategory: layerCategory,
                routineTime: routineTime(for: layerCategory, conflictTags: fallback.suggestedConflictTags),
                ownedProduct: nil,
                catalogProduct: fallback,
                reason: reason(for: layerCategory, profile: profile)
            )
        }
    }

    private static func reason(for layerCategory: LayerCategory, profile: SkinProfile) -> String {
        switch layerCategory {
        case .moisturizer where profile.skinType == .dry:
            "Dry skin needs this step most."
        case .facialOil where profile.skinType == .dry:
            "Extra help for dry skin."
        case .sunscreen:
            "Non-negotiable, especially alongside actives."
        default:
            "A starting pick for this step."
        }
    }
}
