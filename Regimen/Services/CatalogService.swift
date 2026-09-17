//
//  CatalogService.swift
//  Regimen
//

import Foundation
import Supabase

enum CatalogService {
    private static var table: String { "catalog_products" }

    /// Page size for browsing. Large enough that the picker almost never
    /// needs a second request, small enough not to pull the whole catalog
    /// down to render one screen.
    private static let pageSize = 200

    /// Empty query returns the first page of catalog entries, ordered by
    /// brand then name -- CatalogPickerView groups these into brand
    /// sections, so the fetch order determines section order; a non-empty
    /// query matches against name or brand, case-insensitively.
    static func search(_ query: String) async throws -> [CatalogProduct] {
        try await page(query, range: 0..<pageSize)
    }

    /// Every face-routine candidate in the catalog, paged until exhausted.
    ///
    /// `RoutineBuilderEngine` scores *all* candidates for a step against
    /// each other, so a truncated list doesn't just miss products -- it
    /// silently changes which one wins. The old single `.limit(200)` was
    /// already within a few dozen rows of the catalog's real size, and
    /// would have started quietly dropping whole brands from consideration
    /// the moment it was crossed, with nothing to indicate it.
    static func allProducts() async throws -> [CatalogProduct] {
        var all: [CatalogProduct] = []
        var offset = 0
        while true {
            let batch = try await page("", range: offset..<(offset + pageSize))
            all.append(contentsOf: batch)
            // A short page means there is no next one.
            if batch.count < pageSize { break }
            offset += pageSize
            // A catalog this size means something has gone wrong upstream;
            // stop rather than paging forever.
            if offset > 10_000 { break }
        }
        return all
    }

    /// The catalog entry for a scanned barcode, if there is one.
    static func product(withBarcode barcode: String) async throws -> CatalogProduct? {
        let matches: [CatalogProduct] = try await SupabaseManager.client
            .from(table)
            .select()
            .eq("barcode", value: barcode)
            .limit(1)
            .execute()
            .value
        return matches.first
    }

    private static func page(_ query: String, range: Range<Int>) async throws -> [CatalogProduct] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var request = SupabaseManager.client.from(table).select()
        if !trimmed.isEmpty {
            request = request.or("name.ilike.%\(trimmed)%,brand.ilike.%\(trimmed)%")
        }
        return try await request
            .order("brand")
            .order("name")
            .range(from: range.lowerBound, to: range.upperBound - 1)
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
