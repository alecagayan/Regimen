//
//  RoutineBuilderEngine.swift
//  Regimen
//

import Foundation

/// Assembles a complete AM/PM routine from scan findings plus what the user
/// told us about their own skin (`SkinProfile`), one step per
/// `LayerCategory` in its established layering order (see that type's
/// `rank`) -- an owned, active product if one already covers the step,
/// otherwise the best-scoring catalog suggestion. Deterministic and
/// auditable, same style as `ConflictChecker`/`LayeringAdvisor` -- no model
/// call.
///
/// Every unowned step is *scored*, not picked off the top of the list. An
/// earlier version took `candidates[0]`, which in practice meant "whichever
/// row Postgres happened to return first" -- so a user with oily skin and a
/// user with dry skin were handed the same cleanser, and the suggestion
/// silently changed whenever the catalog was reordered. `score(_:)` below is
/// the fix: texture suited to the skin type, actives suited to the findings,
/// gentleness when the profile asks for it, and a penalty for anything that
/// fights what's already in the cabinet.
enum RoutineBuilderEngine {
    struct RoutineItem: Identifiable {
        let layerCategory: LayerCategory
        let routineTime: RoutineTime
        /// How often to use it. The engine was already *saying* "gentle
        /// enough to start on" and "ease in, 2x a week" while creating
        /// every suggestion as daily -- advice the data model couldn't
        /// express until frequency existed, and then still didn't.
        let frequency: ProductFrequency
        /// Exactly one of these is set.
        let ownedProduct: Product?
        let catalogProduct: CatalogProduct?
        let reason: String

        var id: LayerCategory { layerCategory }
        var name: String { ownedProduct?.name ?? catalogProduct?.name ?? "" }
        var brand: String { ownedProduct?.brand ?? catalogProduct?.brand ?? "" }
        var isOwned: Bool { ownedProduct != nil }

        /// Whether this step belongs in the morning half of the routine.
        var isMorning: Bool { routineTime != .pm }
        /// Whether this step belongs in the evening half.
        var isEvening: Bool { routineTime != .am }
    }

    // MARK: - Scoring weights
    //
    // Deliberately a handful of readable constants rather than a tuned
    // model: every number here should be arguable in one sentence, and the
    // ordering between them is what actually matters (targeting beats
    // texture; a conflict outweighs both).

    /// How much a Treatment-step candidate gains for carrying an active the
    /// scan actually calls for. Scaled by the tag's priority for that
    /// finding, and set well above the texture weights so a targeted
    /// treatment always beats a merely well-textured one.
    private static let targetingWeight = 3.0

    /// Penalty for a candidate whose actives fight something the user
    /// already owns. Strong enough to lose to almost anything else, but not
    /// an outright ban -- if it's the only product the catalog has for a
    /// step, an imperfect suggestion still beats an empty step, and the
    /// `RoutineBuilderView` row shows the warning either way.
    private static let conflictPenalty = -2.5

    /// Penalty for a demanding active when the profile asks for gentleness.
    private static let gentlePenalty = -2.0

    /// Penalty for suggesting something the user has already finished a
    /// bottle of and said they wouldn't buy again. Strong: re-recommending
    /// a product someone has personally tried and rejected is worse than
    /// recommending an unknown, and it's the clearest signal the app has
    /// about this specific person's skin.
    private static let rejectedPenalty = -4.0

    /// Which conflict tags a Treatment-step suggestion should prefer, in
    /// priority order, pooled across every active finding -- reuses
    /// `RecommendationEngine.targetTags` so this stays in sync with what
    /// the category cards already recommend.
    ///
    /// Unlike an earlier version, demanding actives are *not* stripped out
    /// here for sensitive/beginner users. Filtering them away could empty
    /// the list entirely and fall through to an untargeted pick; leaving
    /// them in and letting `gentlePenalty` demote them means a gentler
    /// product wins whenever one exists, and the strong one is still
    /// available as a last resort rather than the step going generic.
    static func preferredTreatmentTags(for counts: [FindingKind: Int]) -> [ConflictTag] {
        var seen = Set<ConflictTag>()
        return FindingKind.allCases
            .filter { (counts[$0] ?? 0) > 0 }
            .compactMap { RecommendationEngine.targetTags[$0] }
            .flatMap { $0 }
            .filter { seen.insert($0).inserted }
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
        profile: SkinProfile,
        empties: [ProductEmpty] = []
    ) async -> [RoutineItem] {
        let active = ownedProducts.filter { !$0.isArchived }
        // Face skincare only -- see `CatalogProduct.isFaceRoutineCandidate`
        // for why the catalog's own categories aren't enough on their own.
        let catalog = ((try? await CatalogService.allProducts()) ?? []).filter(\.isFaceRoutineCandidate)
        let treatmentTags = preferredTreatmentTags(for: counts)
        // Matched on name because `product_empties` deliberately keeps no
        // foreign key -- the record of having finished something outlives
        // deleting it from the cabinet, and a catalog suggestion has no id
        // in common with it anyway.
        let rejected = Set(
            empties
                .filter { $0.wouldRepurchase == false }
                .map { $0.productName.lowercased() }
        )

        return categories(for: profile).compactMap { layerCategory -> RoutineItem? in
            // Several owned products can sit in one step. Pick by the
            // user's own application order, then name -- arbitrary
            // `first(where:)` meant the displayed step could change between
            // builds for no visible reason.
            let owned = active
                .filter { $0.layerCategory == layerCategory }
                .min { lhs, rhs in
                    lhs.applicationOrder == rhs.applicationOrder
                        ? lhs.name < rhs.name
                        : lhs.applicationOrder < rhs.applicationOrder
                }

            if let owned {
                return RoutineItem(
                    layerCategory: layerCategory,
                    routineTime: owned.routineTime,
                    frequency: owned.frequency,
                    ownedProduct: owned,
                    catalogProduct: nil,
                    reason: "Already in your cabinet."
                )
            }

            let candidates = catalog.filter { $0.layerCategory == layerCategory }
            guard let best = bestCandidate(
                from: candidates,
                for: layerCategory,
                profile: profile,
                treatmentTags: treatmentTags,
                ownedProducts: active,
                rejectedNames: rejected
            ) else { return nil }

            return RoutineItem(
                layerCategory: layerCategory,
                routineTime: routineTime(for: layerCategory, conflictTags: best.suggestedConflictTags),
                frequency: suggestedFrequency(for: best, profile: profile),
                ownedProduct: nil,
                catalogProduct: best,
                reason: reason(for: best, layerCategory: layerCategory, profile: profile, treatmentTags: treatmentTags, ownedProducts: active)
            )
        }
    }

    /// The best-fitting candidate for one step, or nil if there are none.
    ///
    /// Split out from `buildRoutine` so that choosing from a catalog is
    /// separable from fetching one -- they're different jobs, and this half
    /// is pure, so it can be exercised directly instead of only through a
    /// network round trip.
    static func bestCandidate(
        from candidates: [CatalogProduct],
        for layerCategory: LayerCategory,
        profile: SkinProfile,
        treatmentTags: [ConflictTag],
        ownedProducts: [Product],
        rejectedNames: Set<String> = []
    ) -> CatalogProduct? {
        guard !candidates.isEmpty else { return nil }

        let scored: [ScoredCandidate] = candidates.map { candidate in
            ScoredCandidate(
                candidate: candidate,
                score: score(
                    candidate,
                    for: layerCategory,
                    profile: profile,
                    treatmentTags: treatmentTags,
                    ownedProducts: ownedProducts,
                    rejectedNames: rejectedNames
                )
            )
        }

        return scored.max { lhs, rhs in
            // Higher score wins; an exact tie falls back to the
            // alphabetically-first name, so the same catalog always
            // produces the same routine no matter what order the rows
            // arrived in.
            lhs.score == rhs.score
                ? lhs.candidate.name > rhs.candidate.name
                : lhs.score < rhs.score
        }?.candidate
    }

    /// A candidate paired with its fitness for one step. A named type
    /// rather than an inline tuple purely for the type-checker's sake --
    /// mapping into an anonymous `(candidate:score:)` tuple and chaining
    /// straight into `max(by:)` was slow enough to fail the build outright.
    private struct ScoredCandidate {
        let candidate: CatalogProduct
        let score: Double
    }

    // MARK: - Candidate scoring

    /// How well one catalog product fits this step, this skin, and this
    /// scan. Higher is better; the components are independent and simply
    /// summed, which keeps the result explainable -- `reason(for:...)`
    /// below re-derives the same facts to say *why* a pick won.
    private static func score(
        _ candidate: CatalogProduct,
        for layerCategory: LayerCategory,
        profile: SkinProfile,
        treatmentTags: [ConflictTag],
        ownedProducts: [Product],
        rejectedNames: Set<String> = []
    ) -> Double {
        var total = 0.0
        let text = TextProfile(candidate)

        if layerCategory == .treatment, let index = treatmentTags.firstIndex(where: { candidate.suggestedConflictTags.contains($0) }) {
            // Earlier in the preferred list = more directly on target.
            total += targetingWeight / Double(index + 1)
        }

        total += textureScore(text, skinType: profile.skinType)

        if profile.isSensitive {
            if text.hasAny(["gentle", "soothing", "calming", "mild"]) { total += 0.6 }
            if text.isFragranceFree { total += 0.4 }
        }

        if profile.prefersGentleActives, candidate.suggestedConflictTags.contains(where: \.isDemanding) {
            total += gentlePenalty
        }

        if conflictingOwnedProduct(for: candidate, ownedProducts: ownedProducts) != nil {
            total += conflictPenalty
        }

        if rejectedNames.contains(candidate.name.lowercased()) {
            total += rejectedPenalty
        }

        return total
    }

    /// Texture/format fit, inferred from the words a product uses about
    /// itself. Crude by necessity -- the catalog stores no formulation
    /// field -- but "gel" versus "balm" is a genuinely strong signal about
    /// who a product suits, and it beats ignoring skin type entirely.
    ///
    /// Two tiers of richness on purpose: "cream" appears in half the
    /// catalog and shouldn't be treated as equivalent to "balm".
    private static func textureScore(_ text: TextProfile, skinType: SkinType) -> Double {
        let light = text.hasAny(["gel", "foam", "foaming", "fluid", "lotion", "water", "mattifying", "clay", "lightweight"])
        let veryRich = text.hasAny(["balm", "butter", "ointment", "rich"])
        let mildlyRich = text.hasAny(["cream", "milk", "nourishing"])

        switch skinType {
        case .oily:
            var score = 0.0
            if light { score += 1.0 }
            if text.isOilFree { score += 0.5 }
            if veryRich { score -= 1.0 }
            if mildlyRich { score -= 0.4 }
            return score
        case .dry:
            var score = 0.0
            if veryRich { score += 1.0 }
            if mildlyRich { score += 0.5 }
            if light { score -= 0.6 }
            if text.isOilFree { score -= 0.3 }
            return score
        case .combination:
            // Oily T-zone, drier cheeks -- a light base is the safer
            // default, but nothing is actually wrong for this skin.
            return light ? 0.3 : 0
        case .normal:
            return 0
        }
    }

    private static func conflictingOwnedProduct(for candidate: CatalogProduct, ownedProducts: [Product]) -> Product? {
        ownedProducts.first {
            ConflictChecker.conflictReason(between: candidate.suggestedConflictTags, and: $0.effectiveConflictTags) != nil
        }
    }

    /// How often to use a suggested product.
    ///
    /// Demanding actives get eased into rather than started daily, which
    /// is the advice the app was already giving in words. Twice a week for
    /// someone the profile says should go gently, every other day
    /// otherwise; everything non-demanding stays daily because cleansers
    /// and sunscreen genuinely are daily.
    ///
    /// Weekday-pinned rather than `everyNDays` for the gentle case so the
    /// routine lands on predictable days (the same two each week) instead
    /// of drifting through the calendar.
    static func suggestedFrequency(for candidate: CatalogProduct, profile: SkinProfile) -> ProductFrequency {
        guard candidate.suggestedConflictTags.contains(where: \.isDemanding) else { return .daily }
        // Sunday and Wednesday: spaced, easy to remember, and it matches
        // the "2x a week to start" line RecommendationEngine shows.
        return profile.prefersGentleActives ? .daysOfWeek([1, 4]) : .everyOtherDay
    }

    /// Re-derives why the winning candidate won, so the row can explain
    /// itself in the user's own terms ("Gel texture suits oily skin")
    /// rather than the same generic line on every step.
    private static func reason(
        for candidate: CatalogProduct,
        layerCategory: LayerCategory,
        profile: SkinProfile,
        treatmentTags: [ConflictTag],
        ownedProducts: [Product]
    ) -> String {
        if let clashing = conflictingOwnedProduct(for: candidate, ownedProducts: ownedProducts) {
            return "May clash with \(clashing.name)."
        }

        if layerCategory == .treatment, candidate.suggestedConflictTags.contains(where: { treatmentTags.contains($0) }) {
            return profile.prefersGentleActives
                ? "Targets this scan, gentle enough to start on."
                : "Targets what this scan flagged."
        }

        let text = TextProfile(candidate)
        switch profile.skinType {
        case .oily where text.hasAny(["gel", "foam", "foaming", "clay", "lightweight"]) || text.isOilFree:
            return "Lighter texture suits oily skin."
        case .dry where text.hasAny(["balm", "butter", "cream", "rich", "nourishing"]):
            return "Richer texture for dry skin."
        default:
            break
        }

        if profile.isSensitive, text.hasAny(["gentle", "soothing", "calming", "mild"]) || text.isFragranceFree {
            return "Formulated for easily-irritated skin."
        }

        switch layerCategory {
        case .sunscreen: return "Non-negotiable, especially alongside actives."
        case .moisturizer where profile.skinType == .dry: return "Dry skin needs this step most."
        case .facialOil where profile.skinType == .dry: return "Extra help for dry skin."
        default: return "A starting pick for this step."
        }
    }

    /// A candidate's name and description reduced to whole lowercased
    /// words, for keyword matching.
    ///
    /// Whole words, never substrings -- the same trap `CatalogProduct`
    /// documents, where matching "lip" as a substring threw out
    /// "Glyco**lip**id Cream Cleanser". Here the equivalent would be "oil"
    /// matching inside "oil-free" and marking an oil-free gel as rich, so
    /// the hyphenated negations are checked against the raw string first.
    private struct TextProfile {
        private let raw: String
        private let words: Set<String>

        init(_ candidate: CatalogProduct) {
            raw = "\(candidate.name) \(candidate.productDescription ?? "")".lowercased()
            words = Set(raw.split { !$0.isLetter }.map(String.init))
        }

        func hasAny(_ candidates: Set<String>) -> Bool {
            !candidates.isDisjoint(with: words)
        }

        /// Checked on the raw string, not the word set: splitting
        /// "oil-free" yields the word "oil", which would otherwise read as
        /// the opposite of what the label says.
        var isOilFree: Bool {
            raw.contains("oil-free") || raw.contains("oil free")
        }

        var isFragranceFree: Bool {
            raw.contains("fragrance-free") || raw.contains("fragrance free")
        }
    }
}
