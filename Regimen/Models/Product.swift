//
//  Product.swift
//  Regimen
//

import Foundation

/// When a product goes on the face during the day.
enum RoutineTime: String, Codable, CaseIterable, Identifiable, Hashable {
    case am = "AM"
    case pm = "PM"
    case both = "Both"
    var id: String { rawValue }
}

/// Ingredient categories that `ConflictChecker` knows how to cross-reference.
/// This is intentionally a closed, hardcoded set rather than free-text
/// ingredient tags — see `ConflictChecker` for why.
///
/// `.none` is kept only as a UI sentinel (the picker needs a default,
/// pre-multi-brand rows may still decode a legacy single value of "None")
/// -- it should never appear inside a `conflictTags` array. An empty array
/// is how "no flaggable actives" is actually represented, since a real
/// product can carry more than one of these at once (a serum can combine a
/// retinoid with niacinamide, say), which a single tag couldn't express.
enum ConflictTag: String, Codable, CaseIterable, Identifiable, Hashable {
    case none = "None"
    case retinoid = "Retinoid"
    case exfoliatingAcid = "Exfoliating Acid"
    case pureVitaminC = "Pure Vitamin C"
    case vitaminCDerivative = "Vitamin C Derivative"
    case niacinamide = "Niacinamide"
    case copperPeptide = "Copper Peptide"
    case benzoylPeroxide = "Benzoyl Peroxide"
    var id: String { rawValue }

    /// Actives that usually need tolerance built up first -- potent enough
    /// that starting straight in on them is the common cause of an
    /// irritated barrier, which then undoes whatever they were meant to
    /// fix. Used by both `RecommendationEngine` (to flag a card as
    /// "ease in") and `RoutineBuilderEngine` (to prefer a gentler pick),
    /// so the two can't give contradictory advice about the same
    /// ingredient.
    ///
    /// Benzoyl peroxide counts here alongside the obvious three: it's
    /// reliably drying and bleaches fabric, which is exactly the kind of
    /// surprise a beginner shouldn't get unwarned.
    var isDemanding: Bool {
        switch self {
        case .retinoid, .exfoliatingAcid, .pureVitaminC, .benzoylPeroxide:
            true
        case .none, .vitaminCDerivative, .niacinamide, .copperPeptide:
            false
        }
    }
}

/// Maps 1:1 to the `products` table in Supabase Postgres (see
/// `supabase/schema.sql`, `supabase/layering.sql`, and `supabase/dose.sql`).
/// This app is a thin client over that table — data lives in Postgres, not
/// on-device, so the same account sees the same products on every device.
struct Product: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var name: String
    var brand: String
    var routineTime: RoutineTime
    /// Which layering step this product belongs to (cleanser, treatment,
    /// moisturizer, ...) — see `LayerCategory`. Drives the recommended
    /// application order computed by `LayeringAdvisor`.
    var layerCategory: LayerCategory
    /// A same-step tiebreaker, not the primary ordering signal: two
    /// products in the same `layerCategory` are ordered by this, but a
    /// "Moisturizer" always applies after a "Treatment" regardless of these
    /// numbers. See `LayeringAdvisor`.
    var applicationOrder: Int
    /// Every flaggable active this product contains -- see `ConflictTag`
    /// for why this is an array and not a single value. Empty means none.
    ///
    /// Only ever what was chosen explicitly (by hand, or copied from a
    /// catalog row). For conflict checking use `effectiveConflictTags`,
    /// which also reads the ingredient list.
    var conflictTags: [ConflictTag]
    var sizeInML: Double
    /// How much of this specific product gets used per application, in mL.
    /// The app has no way to actually measure usage (no scale, no sensor —
    /// just a checkbox tap), so this is what `DepletionPredictor` multiplies
    /// each check-off by. Defaults from `LayerCategory.defaultDoseML` when a
    /// product is created, but is a real per-product field so a cleanser and
    /// an eye serum aren't assumed to use the same amount.
    var typicalDoseML: Double
    var openedDate: Date
    var isArchived: Bool

    /// How often this product is used. Decoded through `ProductFrequency`
    /// -- see `Product.frequency` in ProductSchedule.swift. Stored as three
    /// flat columns so a row stays readable in the Supabase dashboard.
    var frequencyKind: String
    var frequencyDaysOfWeek: [Int]
    var frequencyIntervalDays: Int

    /// Period-after-opening in months (the "6M"/"12M" jar symbol). Nil when
    /// the user hasn't said, which is not the same as "never expires".
    var monthsAfterOpening: Int?

    /// Full INCI list, when a catalog entry or a barcode lookup supplied
    /// one. The eight `ConflictTag` values remain what the conflict engine
    /// reasons about; this is the raw list behind them, and what
    /// `IngredientInsights` reads to flag fragrance, drying alcohol and
    /// pregnancy cautions.
    var ingredients: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case name
        case brand
        case routineTime = "routine_time"
        case layerCategory = "layer_category"
        case applicationOrder = "application_order"
        case conflictTags = "conflict_tags"
        case sizeInML = "size_ml"
        case typicalDoseML = "typical_dose_ml"
        case openedDate = "opened_date"
        case isArchived = "is_archived"
        case frequencyKind = "frequency_kind"
        case frequencyDaysOfWeek = "frequency_days_of_week"
        case frequencyIntervalDays = "frequency_interval_days"
        case monthsAfterOpening = "months_after_opening"
        case ingredients
    }

    /// Rows written before `schedules_and_history.sql` ran have none of
    /// these columns, so they decode as absent rather than failing the
    /// whole product fetch.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        name = try container.decode(String.self, forKey: .name)
        brand = try container.decode(String.self, forKey: .brand)
        routineTime = try container.decode(RoutineTime.self, forKey: .routineTime)
        layerCategory = try container.decode(LayerCategory.self, forKey: .layerCategory)
        applicationOrder = try container.decode(Int.self, forKey: .applicationOrder)
        conflictTags = try container.decodeIfPresent([ConflictTag].self, forKey: .conflictTags) ?? []
        sizeInML = try container.decode(Double.self, forKey: .sizeInML)
        typicalDoseML = try container.decodeIfPresent(Double.self, forKey: .typicalDoseML) ?? layerCategory.defaultDoseML
        openedDate = try container.decode(Date.self, forKey: .openedDate)
        isArchived = try container.decodeIfPresent(Bool.self, forKey: .isArchived) ?? false
        frequencyKind = try container.decodeIfPresent(String.self, forKey: .frequencyKind) ?? "daily"
        frequencyDaysOfWeek = try container.decodeIfPresent([Int].self, forKey: .frequencyDaysOfWeek) ?? []
        frequencyIntervalDays = try container.decodeIfPresent(Int.self, forKey: .frequencyIntervalDays) ?? 1
        monthsAfterOpening = try container.decodeIfPresent(Int.self, forKey: .monthsAfterOpening)
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        name: String,
        brand: String,
        routineTime: RoutineTime,
        layerCategory: LayerCategory = .treatment,
        applicationOrder: Int,
        conflictTags: [ConflictTag] = [],
        sizeInML: Double,
        typicalDoseML: Double? = nil,
        openedDate: Date,
        isArchived: Bool = false,
        frequency: ProductFrequency = .daily,
        monthsAfterOpening: Int? = nil,
        ingredients: [String] = []
    ) {
        self.id = id
        self.userID = userID
        self.name = name
        self.brand = brand
        self.routineTime = routineTime
        self.layerCategory = layerCategory
        self.applicationOrder = applicationOrder
        self.conflictTags = conflictTags.filter { $0 != .none }
        self.sizeInML = sizeInML
        self.typicalDoseML = typicalDoseML ?? layerCategory.defaultDoseML
        self.openedDate = openedDate
        self.isArchived = isArchived
        self.frequencyKind = frequency.kindKey
        self.frequencyDaysOfWeek = frequency.storedDaysOfWeek
        self.frequencyIntervalDays = frequency.storedIntervalDays
        self.monthsAfterOpening = monthsAfterOpening
        self.ingredients = ingredients
    }
}

extension Product {
    /// Tags implied by the ingredient list but not explicitly set.
    ///
    /// Kept separate from `effectiveConflictTags` so the edit screen can
    /// show "we found these in the ingredients" as a distinct, dismissible
    /// suggestion rather than silently ticking boxes on the user's behalf.
    var derivedConflictTags: [ConflictTag] {
        let explicit = Set(conflictTags)
        return IngredientConflictMapper.tags(for: ingredients).filter { !explicit.contains($0) }
    }

    /// What conflict checking actually runs against: the tags chosen
    /// explicitly, plus anything the ingredient list plainly implies.
    ///
    /// The union rather than a fallback, deliberately. A product whose
    /// ingredients list retinol conflicts with an exfoliating acid whether
    /// or not anyone remembered to tick "Retinoid" -- and the products
    /// least likely to have been tagged by hand (typed in manually, in a
    /// hurry) are exactly the ones a user would most want caught.
    var effectiveConflictTags: [ConflictTag] {
        let combined = Set(conflictTags).union(IngredientConflictMapper.tags(for: ingredients))
        return ConflictTag.allCases.filter { combined.contains($0) && $0 != .none }
    }
}
