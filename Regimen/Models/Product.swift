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
        isArchived: Bool = false
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
    }
}
