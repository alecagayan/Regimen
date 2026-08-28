//
//  CatalogService.swift
//  Regimen
//

import Foundation
import Supabase

enum CatalogService {
    private static var table: String { "catalog_products" }

    /// Empty query returns the first 50 catalog entries (alphabetical);
    /// a non-empty query matches against name or brand, case-insensitively.
    static func search(_ query: String) async throws -> [CatalogProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = SupabaseManager.client.from(table).select()
        if !trimmed.isEmpty {
            request = request.or("name.ilike.%\(trimmed)%,brand.ilike.%\(trimmed)%")
        }
        return try await request
            .order("name")
            .limit(50)
            .execute()
            .value
    }
}
