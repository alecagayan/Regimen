//
//  CatalogProduct.swift
//  Regimen
//

import Foundation

/// Maps 1:1 to the `catalog_products` table (see `supabase/catalog.sql` and
/// `supabase/layering.sql`) — a shared, publicly-readable reference list of
/// known products, distinct from a user's own `products` rows. Picking one
/// in `CatalogPickerView` pre-fills the Add Product form; it never creates
/// data by itself.
struct CatalogProduct: Identifiable, Codable, Hashable {
    var id: UUID
    var brand: String
    var name: String
    var category: String?
    /// Every flaggable active this product contains -- see `ConflictTag`.
    var suggestedConflictTags: [ConflictTag]
    var layerCategory: LayerCategory
    /// A short line about what the product actually is/does -- shown
    /// alongside brand and category wherever a catalog row is browsed, so
    /// choosing between five brands' moisturizers doesn't come down to
    /// name alone.
    var productDescription: String?
    /// Full INCI list, where the catalog has one. The eight `ConflictTag`
    /// values remain what the conflict engine reasons about; this is the
    /// raw list behind them, and what makes "does anything I own contain
    /// fragrance" answerable.
    var ingredients: [String]
    /// Retail barcode, for scan-to-add. Nil for the many entries curated by
    /// hand without one.
    var barcode: String?

    enum CodingKeys: String, CodingKey {
        case id, brand, name, category, ingredients, barcode
        case suggestedConflictTags = "suggested_conflict_tags"
        case layerCategory = "layer_category"
        case productDescription = "description"
    }

    init(
        id: UUID,
        brand: String,
        name: String,
        category: String?,
        suggestedConflictTags: [ConflictTag],
        layerCategory: LayerCategory,
        productDescription: String? = nil,
        ingredients: [String] = [],
        barcode: String? = nil
    ) {
        self.id = id
        self.brand = brand
        self.name = name
        self.category = category
        self.suggestedConflictTags = suggestedConflictTags
        self.layerCategory = layerCategory
        self.productDescription = productDescription
        self.ingredients = ingredients
        self.barcode = barcode
    }

    /// Columns added after a release decode as absent, so a catalog row
    /// written before `schedules_and_history.sql` ran still loads.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        brand = try container.decode(String.self, forKey: .brand)
        name = try container.decode(String.self, forKey: .name)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        suggestedConflictTags = try container.decodeIfPresent([ConflictTag].self, forKey: .suggestedConflictTags) ?? []
        layerCategory = try container.decodeIfPresent(LayerCategory.self, forKey: .layerCategory) ?? .treatment
        productDescription = try container.decodeIfPresent(String.self, forKey: .productDescription)
        ingredients = try container.decodeIfPresent([String].self, forKey: .ingredients) ?? []
        barcode = try container.decodeIfPresent(String.self, forKey: .barcode)
    }

    /// Catalog categories that aren't facial skincare at all.
    private static let nonFaceCategories: Set<String> = ["Hair & Scalp", "Makeup / Primers"]

    /// Words marking a product as aimed somewhere other than the face.
    /// Needed as a second check because the catalog's own categories aren't
    /// all clean: "Newer Additions" mixes an eye cream and a sunscreen in
    /// with two *lip* serums, and anything not explicitly assigned a layer
    /// category falls through to `Treatment` (see `supabase/layering.sql`)
    /// -- which is how a shampoo could be proposed as a face treatment.
    private static let nonFaceWords: Set<String> = [
        "lip", "lips", "scalp", "hair", "lash", "lashes", "brow", "brows",
        "shampoo", "conditioner",
    ]

    /// Whether this is something `RoutineBuilderEngine` may propose as a
    /// step in a facial routine.
    ///
    /// This gates only *automatic suggestions*. A user can still add any of
    /// these to their own cabinet and have it ordered correctly -- the point
    /// is that the app shouldn't put a mascara, a shampoo, or a lip
    /// exfoliant into a face routine on their behalf.
    var isFaceRoutineCandidate: Bool {
        guard layerCategory.isSkincareStep else { return false }
        if let category, Self.nonFaceCategories.contains(category) { return false }
        return Self.nonFaceWords.isDisjoint(with: nameWords)
    }

    /// The product name split into whole lowercased words.
    ///
    /// Whole words, not substrings: matching "lip" as a substring threw out
    /// "Glyco**lip**id Cream Cleanser" and "Rice **Lip**ids & Ectoin
    /// Moisturizer", both of which are ordinary face products.
    private var nameWords: Set<String> {
        Set(
            name.lowercased()
                .split { !$0.isLetter }
                .map(String.init)
        )
    }
}
