//
//  BarcodeLookupService.swift
//  Regimen
//

import Foundation
import os

/// Turns a scanned barcode into something the add-product form can prefill.
///
/// Tries the app's own catalog first, then falls back to Open Beauty Facts.
///
/// Worth being explicit about that fallback: the Open Beauty Facts *bulk
/// dataset* was evaluated for this app earlier and rejected -- a 2019
/// snapshot, French-market skewed, roughly twenty usable rows after real
/// filtering. Per-barcode lookup is a different proposition entirely. It's
/// one product the user is physically holding, the result is shown for
/// confirmation rather than trusted blindly, and a miss costs nothing
/// because the form is still there to fill in by hand.
enum BarcodeLookupService {
    struct Match {
        let name: String
        let brand: String
        let ingredients: [String]
        /// Whether this came from the curated catalog, which carries
        /// layering and active-ingredient data the open dataset doesn't.
        let catalogProduct: CatalogProduct?
    }

    /// A catalog hit is strictly better than an open-data one, so it wins.
    static func lookup(barcode: String) async -> Match? {
        // Double unwrap: the call itself can throw, and a successful call
        // can still find nothing.
        if let catalogMatch = (try? await CatalogService.product(withBarcode: barcode)) ?? nil {
            return Match(
                name: catalogMatch.name,
                brand: catalogMatch.brand,
                ingredients: catalogMatch.ingredients,
                catalogProduct: catalogMatch
            )
        }
        return await openBeautyFacts(barcode: barcode)
    }

    private static func openBeautyFacts(barcode: String) async -> Match? {
        guard let url = URL(string: "https://world.openbeautyfacts.org/api/v2/product/\(barcode).json") else {
            return nil
        }

        var request = URLRequest(url: url)
        // Their API asks callers to identify themselves.
        request.setValue("Regimen/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        // This is a convenience on top of a form the user can always fill
        // in themselves, so it should never be the reason a sheet hangs.
        request.timeoutInterval = 8

        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(OpenBeautyFactsResponse.self, from: data)
            guard response.status == 1, let product = response.product else { return nil }

            let name = product.productName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !name.isEmpty else { return nil }

            return Match(
                name: name,
                brand: product.brands?.components(separatedBy: ",").first?.trimmingCharacters(in: .whitespaces) ?? "",
                ingredients: product.ingredientList,
                catalogProduct: nil
            )
        } catch {
            AppLog.data.debug("barcode lookup failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private struct OpenBeautyFactsResponse: Decodable {
        let status: Int
        let product: OpenBeautyFactsProduct?
    }

    private struct OpenBeautyFactsProduct: Decodable {
        let productName: String?
        let brands: String?
        let ingredientsText: String?

        enum CodingKeys: String, CodingKey {
            case productName = "product_name"
            case brands
            case ingredientsText = "ingredients_text"
        }

        /// INCI lists are comma-separated free text of wildly varying
        /// quality, so this only splits and tidies -- it doesn't pretend to
        /// parse them.
        var ingredientList: [String] {
            guard let ingredientsText else { return [] }
            return ingredientsText
                .components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.count < 80 }
        }
    }
}
