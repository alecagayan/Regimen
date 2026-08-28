//
//  ProductService.swift
//  Regimen
//

import Foundation
import Supabase

enum ProductService {
    private static var table: String { "products" }

    static func fetchAll(userID: UUID) async throws -> [Product] {
        try await SupabaseManager.client
            .from(table)
            .select()
            .eq("user_id", value: userID)
            .order("name")
            .execute()
            .value
    }

    static func insert(_ product: Product) async throws {
        try await SupabaseManager.client
            .from(table)
            .insert(product)
            .execute()
    }

    static func update(_ product: Product) async throws {
        try await SupabaseManager.client
            .from(table)
            .update(product)
            .eq("id", value: product.id)
            .execute()
    }

    static func delete(id: UUID) async throws {
        try await SupabaseManager.client
            .from(table)
            .delete()
            .eq("id", value: id)
            .execute()
    }
}
