//
//  RecommendationEngine.swift
//  Regimen
//

import Foundation

/// Turns a skin scan into ingredient *categories* worth browsing — one card
/// per category, not a rendered sentence — so the UI can show a tappable
/// icon per category and defer the actual catalog lookup until the user taps
/// one (see CategoryProductsView). Same deterministic, human-auditable style
/// as `ConflictChecker`/`LayeringAdvisor` — hardcoded mappings plus a small
/// scoring pass that's easy to read and retune in one place, not a model call.
///
/// Three inputs, not one. The scan's *findings* say what's on the surface;
/// the scan's *attributes* (`SkinAttribute`) say what the whole-face
/// classifiers noticed; and the user's own `SkinProfile` says what their skin
/// can actually tolerate. Recommending pure vitamin C to someone who told the
/// quiz their skin stings is worse than recommending nothing, so the profile
/// is a first-class input here rather than something only the routine builder
/// consults.
enum RecommendationEngine {
    struct CategoryRecommendation: Identifiable, Hashable {
        let tag: ConflictTag
        /// Why this category came up for *this* scan, in one line. Written
        /// against whichever signal contributed most, so the card can say
        /// "clears the congestion behind blackheads" rather than a generic
        /// blurb about the ingredient.
        let reason: String
        /// Name of an owned, active product already covering this category,
        /// if any -- drives the "already have this" checkmark.
        let ownedProductName: String?
        /// Set when this category fights something already in the cabinet,
        /// so the card can warn *before* the user goes shopping.
        let conflictWarning: String?
        /// True when this is a demanding active and the user told us they're
        /// sensitive or new to actives. The category still shows -- it does
        /// genuinely target what the scan found -- but flagged to ease in.
        let needsGentleStart: Bool

        var id: ConflictTag { tag }
    }

    /// Which ingredient tags address each finding, ordered by how directly
    /// they target it. A dermatology-adjacent starting point (BHA for
    /// congestion, vitamin C for pigmentation, niacinamide as the
    /// all-rounder) — not a clinical protocol, and framed as such in the UI.
    ///
    /// `.whitehead` is mapped for completeness even though its display
    /// threshold is pinned above 1.0 and it can never currently fire (see
    /// `SkinScanService`) -- so that if that channel is ever trusted enough
    /// to enable, it doesn't silently produce an empty recommendation list
    /// the way `.blackhead` did before it was mapped here.
    static let targetTags: [FindingKind: [ConflictTag]] = [
        .blemish: [.exfoliatingAcid, .benzoylPeroxide, .niacinamide],
        .spot: [.vitaminCDerivative, .pureVitaminC, .niacinamide],
        .blackhead: [.exfoliatingAcid, .retinoid, .niacinamide],
        .whitehead: [.benzoylPeroxide, .exfoliatingAcid, .niacinamide],
    ]

    /// What the whole-face classifiers imply, where they imply anything
    /// buyable. `.sensitivity` is deliberately absent: "this skin looks
    /// sensitive" is a reason to *hold back* demanding actives, not a reason
    /// to recommend a product, and it's applied that way in `evidence(...)`.
    static let attributeTags: [SkinAttribute: [ConflictTag]] = [
        .unevenSkin: [.niacinamide, .vitaminCDerivative],
        .darkSpots: [.vitaminCDerivative, .niacinamide],
    ]

    /// How much weight a tag gets from its position in a finding's list --
    /// the first entry is the most direct answer, later ones are supporting
    /// options. Anything past the end falls back to the last value.
    private static let positionWeights: [Double] = [1.0, 0.6, 0.35]

    /// What one flagged attribute is worth relative to findings. Attributes
    /// are whole-face yes/no calls from small-data classifiers held to a
    /// conservative 0.6 threshold (see `SkinAttributeService`), so they
    /// count for real but shouldn't outrank a face with actual blemishes
    /// counted on it -- this is roughly "one and a bit blemishes" worth.
    private static let attributeEvidence = 1.2

    /// How far a demanding active gets demoted when the profile asks for
    /// gentleness. A multiplier rather than a filter on purpose: the
    /// ingredient really does target the finding, so it stays visible with
    /// an "ease in" flag instead of vanishing and leaving the user to
    /// wonder why the obvious answer isn't listed.
    private static let gentleDemotion = 0.45

    /// At most this many cards. The grid is three columns wide, so two full
    /// rows is a complete answer; past that it stops reading as "what to
    /// use" and starts reading as a catalog dump.
    private static let maxRecommendations = 6

    /// Whichever signal contributed most to a tag's score, used to write the
    /// card's reason line.
    private enum Driver: Hashable {
        case finding(FindingKind)
        case attribute(SkinAttribute)
    }

    private struct Evidence {
        var score = 0.0
        var driver: Driver?
        var driverScore = 0.0

        mutating func add(_ amount: Double, from driver: Driver) {
            score += amount
            if amount > driverScore {
                driverScore = amount
                self.driver = driver
            }
        }
    }

    /// One card per category worth browsing, strongest evidence first.
    ///
    /// Ordering is by accumulated evidence rather than the order findings
    /// happen to be declared in: a face with nine dark spots and one blemish
    /// should lead with vitamin C, which enum-declaration order got wrong.
    static func categoryRecommendations(
        for result: SkinScanResult,
        ownedProducts: [Product],
        profile: SkinProfile
    ) -> [CategoryRecommendation] {
        categoryRecommendations(
            counts: result.counts,
            attributes: result.attributes,
            ownedProducts: ownedProducts,
            profile: profile
        )
    }

    /// The same recommendations from a scan restored out of storage, which
    /// has counts and attributes but not the original findings.
    static func categoryRecommendations(
        counts: [FindingKind: Int],
        attributes: [SkinAttribute],
        ownedProducts: [Product],
        profile: SkinProfile
    ) -> [CategoryRecommendation] {
        let active = ownedProducts.filter { !$0.isArchived }
        let scored = evidence(counts: counts, attributes: attributes, profile: profile)
        let beGentle = shouldBeGentle(profile: profile, attributes: attributes)

        return scored
            .sorted { lhs, rhs in
                // Stable tiebreak on the tag name so the same scan always
                // produces the same card order.
                lhs.value.score == rhs.value.score
                    ? lhs.key.rawValue < rhs.key.rawValue
                    : lhs.value.score > rhs.value.score
            }
            .prefix(maxRecommendations)
            .map { tag, evidence in
                CategoryRecommendation(
                    tag: tag,
                    reason: evidence.driver.map { reason(for: tag, driver: $0) } ?? genericReason(for: tag),
                    ownedProductName: active.first { $0.effectiveConflictTags.contains(tag) }?.name,
                    conflictWarning: conflictWarning(for: tag, ownedProducts: active),
                    needsGentleStart: tag.isDemanding && beGentle
                )
            }
    }

    /// Accumulates per-tag evidence from every signal the scan produced,
    /// then applies the profile's tolerance as a demotion.
    private static func evidence(
        counts: [FindingKind: Int],
        attributes: [SkinAttribute],
        profile: SkinProfile
    ) -> [ConflictTag: Evidence] {
        var scores: [ConflictTag: Evidence] = [:]

        for kind in FindingKind.allCases {
            let count = counts[kind] ?? 0
            guard count > 0, let tags = targetTags[kind] else { continue }
            // Severity-weighted so three blackheads don't outweigh three
            // inflamed blemishes just by counting the same.
            let weight = Double(count) * kind.severityWeight
            for (index, tag) in tags.enumerated() {
                scores[tag, default: Evidence()].add(weight * positionWeight(index), from: .finding(kind))
            }
        }

        for attribute in attributes {
            guard let tags = attributeTags[attribute] else { continue }
            for (index, tag) in tags.enumerated() {
                scores[tag, default: Evidence()].add(attributeEvidence * positionWeight(index), from: .attribute(attribute))
            }
        }

        guard shouldBeGentle(profile: profile, attributes: attributes) else { return scores }

        for tag in scores.keys where tag.isDemanding {
            scores[tag]?.score *= gentleDemotion
        }
        return scores
    }

    /// Whether to ease off demanding actives, from either source.
    ///
    /// Skin the classifier called sensitive counts the same as skin the
    /// user called sensitive -- the model noticing it is no less a reason
    /// to go carefully. Shared by the scoring pass and the card's
    /// `needsGentleStart` flag deliberately: demoting an ingredient for a
    /// reason the card then doesn't mention is how a recommendation ends up
    /// looking arbitrary.
    private static func shouldBeGentle(profile: SkinProfile, attributes: [SkinAttribute]) -> Bool {
        profile.prefersGentleActives || attributes.contains(.sensitivity)
    }

    private static func positionWeight(_ index: Int) -> Double {
        positionWeights[min(index, positionWeights.count - 1)]
    }

    /// The card's one-line "why", written against the strongest signal.
    /// Explicit rather than templated: an ingredient's role genuinely
    /// differs by what it's being asked to do (niacinamide is an oil
    /// regulator for congestion and a tone-evener for marks), and a
    /// generic blurb per ingredient would flatten that away.
    private static func reason(for tag: ConflictTag, driver: Driver) -> String {
        switch (tag, driver) {
        case (.exfoliatingAcid, .finding(.blackhead)):
            "Salicylic acid gets inside pores and clears the congestion behind blackheads."
        case (.exfoliatingAcid, .finding(.blemish)), (.exfoliatingAcid, .finding(.whitehead)):
            "Keeps pores clear, which is where most breakouts start."
        case (.benzoylPeroxide, _):
            "Targets the bacteria involved in inflamed breakouts."
        case (.retinoid, _):
            "Speeds up cell turnover so pores clog less in the first place."
        case (.pureVitaminC, _):
            "The most direct option for fading existing dark spots."
        case (.vitaminCDerivative, .attribute(.unevenSkin)):
            "Brightens overall tone, with less sting than pure vitamin C."
        case (.vitaminCDerivative, _):
            "Fades dark spots without pure vitamin C's irritation risk."
        case (.niacinamide, .finding(.blemish)):
            "Calms the redness around breakouts and helps regulate oil."
        case (.niacinamide, .finding(.blackhead)), (.niacinamide, .finding(.whitehead)):
            "Helps regulate the oil that feeds congestion."
        case (.niacinamide, .finding(.spot)), (.niacinamide, .attribute(.darkSpots)):
            "Gradually evens out the marks breakouts leave behind."
        case (.niacinamide, _):
            "A gentle all-rounder for tone and oil balance."
        default:
            genericReason(for: tag)
        }
    }

    private static func genericReason(for tag: ConflictTag) -> String {
        switch tag {
        case .exfoliatingAcid: "Clears pores and smooths texture."
        case .benzoylPeroxide: "Targets breakout-causing bacteria."
        case .retinoid: "Speeds up cell turnover over time."
        case .pureVitaminC: "Brightens and fades pigmentation."
        case .vitaminCDerivative: "Brightens gently over time."
        case .niacinamide: "A gentle all-rounder for tone and oil balance."
        case .copperPeptide: "Supports the skin barrier over time."
        case .none: "Worth a look."
        }
    }

    /// Warns when a category fights something already in the cabinet.
    /// Short by design -- the full explanation belongs in the Routine tab's
    /// conflict banner, which has room for it; here the job is just to stop
    /// someone buying a second product that undoes their first.
    private static func conflictWarning(for tag: ConflictTag, ownedProducts: [Product]) -> String? {
        let clashing = ownedProducts.first {
            ConflictChecker.conflictReason(between: [tag], and: $0.effectiveConflictTags) != nil
        }
        guard let clashing else { return nil }
        return "May clash with \(clashing.name)"
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
