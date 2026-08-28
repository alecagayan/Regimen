//
//  ConflictChecker.swift
//  Regimen
//

import Foundation

/// Flags known-bad same-routine ingredient pairings from a small, hardcoded
/// lookup table rather than a general rules engine.
///
/// A real rules engine (weighted severity, concentration thresholds, buffer/
/// wait-time windows between applications, etc.) would need ingredient
/// concentration data and dermatological modeling this app doesn't have —
/// that's solving a problem v1 doesn't have. There are only a handful of
/// well-known "don't combine these" pairings that dominate real-world advice,
/// so a fixed table of (tag, tag) -> reason is simpler, fully predictable,
/// and easy to extend by just adding a row.
enum ConflictChecker {
    struct Conflict: Identifiable {
        let id = UUID()
        let productA: Product
        let productB: Product
        let reason: String
    }

    /// Order-independent key so (retinoid, acid) and (acid, retinoid) both
    /// match the same table entry.
    private struct TagPair: Hashable {
        let first: ConflictTag
        let second: ConflictTag

        init(_ a: ConflictTag, _ b: ConflictTag) {
            if a.rawValue <= b.rawValue {
                first = a
                second = b
            } else {
                first = b
                second = a
            }
        }
    }

    private static let conflictReasons: [TagPair: String] = [
        TagPair(.retinoid, .exfoliatingAcid):
            "Combining retinoids with exfoliating acids in the same routine raises the risk of irritation and a compromised skin barrier.",
        TagPair(.retinoid, .copperPeptide):
            "Copper peptides can destabilize retinoids, reducing the effectiveness of both when used together.",
        TagPair(.exfoliatingAcid, .copperPeptide):
            "Exfoliating acids can strip away copper peptides before they have a chance to bind to skin.",
        TagPair(.pureVitaminC, .niacinamide):
            "Pure vitamin C (L-ascorbic acid) needs a low pH to stay stable, and niacinamide can raise that pH. Vitamin C derivatives don't have this stability issue, so they aren't flagged here.",
    ]

    /// Returns every pairwise conflict among the given products' conflict
    /// tags. Intended to be called with "today's active products" (already
    /// filtered by AM/PM and archived status) — not the full product list.
    static func conflicts(among products: [Product]) -> [Conflict] {
        let tagged = products.filter { $0.conflictTag != .none }
        guard tagged.count > 1 else { return [] }

        var found: [Conflict] = []
        for i in 0..<tagged.count {
            for j in (i + 1)..<tagged.count {
                let a = tagged[i]
                let b = tagged[j]
                if let reason = conflictReasons[TagPair(a.conflictTag, b.conflictTag)] {
                    found.append(Conflict(productA: a, productB: b, reason: reason))
                }
            }
        }
        return found
    }
}
