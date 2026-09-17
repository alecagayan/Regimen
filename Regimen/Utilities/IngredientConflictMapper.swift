//
//  IngredientConflictMapper.swift
//  Regimen
//

import Foundation

/// Derives `ConflictTag`s from an ingredient list.
///
/// Until this existed, conflict tags arrived exactly two ways: typed in by
/// hand on the edit screen, or copied off a catalog row's
/// `suggestedConflictTags`. A product added manually, or a catalog entry
/// whose suggestions were never filled in, therefore got *no* conflict
/// checking at all -- even when its ingredient list said "Retinol" in plain
/// text. The app's headline safety feature quietly didn't apply to the
/// products most likely to need it.
///
/// Matching follows the same discipline as `IngredientInsights`: whole
/// entries, never substrings. That matters more here than anywhere else in
/// the app, because the near-misses are real products with opposite
/// meanings -- "ascorbic acid" is the pure vitamin C that conflicts with
/// niacinamide, while "3-o-ethyl ascorbic acid" is a derivative that
/// deliberately does not.
enum IngredientConflictMapper {

    /// INCI names, lowercased, that identify each tag.
    ///
    /// Deliberately conservative. A false positive here shows the user a
    /// scary warning about a product that is fine, which trains them to
    /// ignore the warnings that matter -- so an ingredient earns a place
    /// only if its presence really does imply the active.
    private static let rules: [ConflictTag: Set<String>] = [
        .retinoid: [
            "retinol", "retinal", "retinaldehyde", "tretinoin", "adapalene",
            "retinyl palmitate", "retinyl propionate", "retinyl retinoate",
            "hydroxypinacolone retinoate", "granactive retinoid",
        ],
        .exfoliatingAcid: [
            "glycolic acid", "lactic acid", "salicylic acid", "mandelic acid",
            "malic acid", "tartaric acid", "betaine salicylate",
            "ammonium glycolate",
        ],
        // Pure L-ascorbic acid only. The derivatives below are a separate
        // tag precisely because they don't share its pH-stability problem.
        .pureVitaminC: [
            "ascorbic acid", "l-ascorbic acid",
        ],
        .vitaminCDerivative: [
            "sodium ascorbyl phosphate", "magnesium ascorbyl phosphate",
            "ascorbyl glucoside", "tetrahexyldecyl ascorbate",
            "ascorbyl palmitate", "3-o-ethyl ascorbic acid", "ethyl ascorbic acid",
            "ascorbyl tetraisopalmitate",
        ],
        .niacinamide: [
            "niacinamide", "nicotinamide",
        ],
        .copperPeptide: [
            "copper tripeptide-1", "copper peptide", "ghk-cu",
            "copper palmitoyl heptapeptide-14",
        ],
        .benzoylPeroxide: [
            "benzoyl peroxide",
        ],
    ]

    /// Entries that would otherwise trip a rule but shouldn't.
    ///
    /// Citric acid is the important one: it appears in a large share of all
    /// cosmetic formulas as a pH adjuster at a fraction of a percent, and
    /// treating it as an exfoliating acid would put a conflict banner on
    /// half the cabinet. Ascorbyl-something entries are listed so a
    /// derivative can never also register as pure vitamin C.
    private static let exclusions: Set<String> = [
        "citric acid", "hyaluronic acid", "amino acid", "fatty acid",
        "ferulic acid", "azelaic acid", "kojic acid", "tranexamic acid",
    ]

    /// Tags implied by `ingredients`, in the stable order the tags are
    /// declared, with no duplicates.
    static func tags(for ingredients: [String]) -> [ConflictTag] {
        guard !ingredients.isEmpty else { return [] }
        let normalized = normalize(ingredients)
        guard !normalized.isEmpty else { return [] }

        var found: Set<ConflictTag> = []
        for (tag, needles) in rules where matches(normalized, against: needles) {
            found.insert(tag)
        }
        return ConflictTag.allCases.filter { found.contains($0) && $0 != .none }
    }

    /// The ingredient entries that caused a given tag, so the UI can say
    /// *why* a product was tagged rather than asserting it.
    static func evidence(for tag: ConflictTag, in ingredients: [String]) -> [String] {
        guard let needles = rules[tag] else { return [] }
        return normalize(ingredients)
            .filter { entry in needles.contains { matches(entry, needle: $0) } }
            .sorted()
    }

    // MARK: - Matching

    private static func normalize(_ ingredients: [String]) -> [String] {
        ingredients
            .map {
                $0.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    // INCI lists carry trailing punctuation and the
                    // organic-certification asterisk ("Glycerin*"), which
                    // would otherwise stop an exact match dead.
                    .trimmingCharacters(in: CharacterSet(charactersIn: ".*;,"))
            }
            .filter { !$0.isEmpty }
    }

    private static func matches(_ entries: [String], against needles: Set<String>) -> Bool {
        entries.contains { entry in
            needles.contains { matches(entry, needle: $0) }
        }
    }

    /// Whole-entry match, or a match at the start of a qualified name
    /// ("retinol 0.5%", "salicylic acid (bha)"). Never a bare substring:
    /// that is what makes "ethyl ascorbic acid" stay a derivative instead
    /// of registering as the pure acid it contains the name of.
    private static func matches(_ entry: String, needle: String) -> Bool {
        guard !exclusions.contains(entry) else { return false }
        if entry == needle { return true }
        for separator in [" ", "/", "(", "-"] where entry.hasPrefix("\(needle)\(separator)") {
            return true
        }
        return false
    }
}
