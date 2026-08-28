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
enum ConflictTag: String, Codable, CaseIterable, Identifiable, Hashable {
    case none = "None"
    case retinoid = "Retinoid"
    case exfoliatingAcid = "Exfoliating Acid"
    case pureVitaminC = "Pure Vitamin C"
    case vitaminCDerivative = "Vitamin C Derivative"
    case niacinamide = "Niacinamide"
    case copperPeptide = "Copper Peptide"
    var id: String { rawValue }
}

/// Maps 1:1 to the `products` table in Supabase Postgres (see
/// `supabase/schema.sql` and `supabase/layering.sql`). This app is a thin
/// client over that table — data lives in Postgres, not on-device, so the
/// same account sees the same products on every device.
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
    var conflictTag: ConflictTag
    var sizeInML: Double
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
        case conflictTag = "conflict_tag"
        case sizeInML = "size_ml"
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
        conflictTag: ConflictTag,
        sizeInML: Double,
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
        self.conflictTag = conflictTag
        self.sizeInML = sizeInML
        self.openedDate = openedDate
        self.isArchived = isArchived
    }
}
