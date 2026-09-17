//
//  IngredientInsights.swift
//  Regimen
//

import Foundation

/// Reads a product's INCI list and flags the handful of things people
/// actually check a label for.
///
/// Deliberately small and hardcoded, in the same spirit as
/// `ConflictChecker`: a general ingredient-safety engine would need
/// concentration data, regulatory tables and clinical modelling this app
/// doesn't have. What it *can* do honestly is pattern-match a short list of
/// well-known names and say "this contains fragrance" without pretending to
/// know whether that matters for a given person.
///
/// Everything here is phrased as an observation, never a verdict.
enum IngredientInsights {
    struct Flag: Identifiable, Hashable {
        let kind: Kind
        /// Which ingredients triggered it, for the detail line.
        let matches: [String]

        var id: Kind { kind }
    }

    enum Kind: String, Hashable {
        case fragrance
        case dryingAlcohol
        case essentialOil
        case pregnancyCaution

        var label: String {
            switch self {
            case .fragrance: "Contains fragrance"
            case .dryingAlcohol: "Contains drying alcohol"
            case .essentialOil: "Contains essential oils"
            case .pregnancyCaution: "Check with your doctor if pregnant"
            }
        }

        var detail: String {
            switch self {
            case .fragrance: "A common irritant for reactive skin."
            case .dryingAlcohol: "Can feel stripping on dry or sensitive skin."
            case .essentialOil: "Naturally derived, still a frequent irritant."
            case .pregnancyCaution: "Retinoids are usually avoided in pregnancy."
            }
        }

        var icon: String {
            switch self {
            case .fragrance: "nose"
            case .dryingAlcohol: "drop.triangle"
            case .essentialOil: "leaf"
            case .pregnancyCaution: "exclamationmark.shield"
            }
        }

        /// Whether this is a caution rather than an observation, which is
        /// the only one worth colouring differently.
        var isCaution: Bool { self == .pregnancyCaution }
    }

    /// Matched as whole words against a normalized list, never as
    /// substrings. The substring trap is well established in this codebase
    /// -- "lip" once excluded "Glycolipid Cream Cleanser" -- and it's worse
    /// here, where "alcohol" appears inside "cetearyl alcohol", a
    /// non-drying fatty alcohol that is close to the opposite of the thing
    /// being flagged.
    private static let rules: [Kind: Set<String>] = [
        .fragrance: ["fragrance", "parfum", "perfume", "aroma"],
        .dryingAlcohol: ["alcohol denat", "denatured alcohol", "sd alcohol", "sd alcohol 40", "isopropyl alcohol", "ethanol"],
        .essentialOil: [
            "lavandula angustifolia oil", "citrus limon peel oil", "mentha piperita oil",
            "eucalyptus globulus leaf oil", "melaleuca alternifolia leaf oil",
            "rosmarinus officinalis leaf oil", "citrus aurantium dulcis peel oil",
        ],
        .pregnancyCaution: [
            "retinol", "retinal", "retinaldehyde", "tretinoin", "adapalene",
            "retinyl palmitate", "hydroxypinacolone retinoate",
        ],
    ]

    /// Fatty alcohols, which are emollients rather than solvents. Listed
    /// explicitly so they can never trip the drying-alcohol rule.
    private static let benignAlcohols: Set<String> = [
        "cetearyl alcohol", "cetyl alcohol", "stearyl alcohol", "behenyl alcohol", "myristyl alcohol",
    ]

    static func flags(for ingredients: [String]) -> [Flag] {
        guard !ingredients.isEmpty else { return [] }
        let normalized = ingredients.map {
            $0.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
                // INCI entries carry trailing punctuation and asterisks
                // ("Alcohol Denat.", "Glycerin*"), which would otherwise
                // stop an exact match dead.
                .trimmingCharacters(in: CharacterSet(charactersIn: ".*;"))
        }

        var found: [Flag] = []
        for (kind, needles) in rules {
            let matches = normalized.filter { ingredient in
                if kind == .dryingAlcohol, benignAlcohols.contains(ingredient) { return false }
                return needles.contains { needle in
                    ingredient == needle || ingredient.hasPrefix("\(needle) ") || ingredient.hasPrefix("\(needle)/")
                }
            }
            guard !matches.isEmpty else { continue }
            found.append(Flag(kind: kind, matches: Array(Set(matches)).sorted()))
        }
        // Stable order so the same product always reads the same way.
        return found.sorted { $0.kind.rawValue < $1.kind.rawValue }
    }
}
