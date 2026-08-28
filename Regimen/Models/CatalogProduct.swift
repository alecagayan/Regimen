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
    var suggestedConflictTag: ConflictTag
    var layerCategory: LayerCategory

    enum CodingKeys: String, CodingKey {
        case id, brand, name, category
        case suggestedConflictTag = "suggested_conflict_tag"
        case layerCategory = "layer_category"
    }
}
