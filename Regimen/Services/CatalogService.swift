//
//  CatalogService.swift
//  Regimen
//

import Foundation
import Supabase

enum CatalogService {
    private static var table: String { "catalog_products" }

    /// Empty query returns the first 200 catalog entries, ordered by brand
    /// then name -- CatalogPickerView groups these into brand sections, so
    /// the fetch order determines section order; a non-empty query matches
    /// against name or brand, case-insensitively.
    static func search(_ query: String) async throws -> [CatalogProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = SupabaseManager.client.from(table).select()
        if !trimmed.isEmpty {
            request = request.or("name.ilike.%\(trimmed)%,brand.ilike.%\(trimmed)%")
        }
        return try await request
            .order("brand")
            .order("name")
            .limit(200)
            .execute()
            .value
    }

    /// Catalog entries whose suggested actives include `tag` -- used by
    /// `RecommendationEngine` to suggest a real, catalog-backed product
    /// rather than just naming an ingredient in the abstract. `conflict_tags`
    /// is a Postgres array column, so this is a containment check, not
    /// equality -- a product can carry more than one flaggable active.
    static func products(withConflictTag tag: ConflictTag) async throws -> [CatalogProduct] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .contains("suggested_conflict_tags", value: [tag.rawValue])
            .order("name")
            .limit(10)
            .execute()
            .value
    }
}
