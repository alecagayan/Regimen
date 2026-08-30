//
//  PlanEngine.swift
//  Regimen
//

import Foundation

/// Builds a structured, multi-part plan from a skin scan: what was found
/// (by face zone), how to sequence ingredients into the AM/PM routine, and
/// what timeline to expect. "What to use" is deliberately not a section
/// here anymore — it's the tappable category-card grid in PhotoDetailView
/// (backed by `RecommendationEngine.categoryRecommendations`), which lets
/// the user browse the actual catalog instead of reading a name in a
/// sentence. Deterministic and human-auditable like `ConflictChecker` /
/// `LayeringAdvisor` — every line traces to a rule you can read here, not
/// a model call.
enum PlanEngine {
    struct Plan {
        struct Section: Identifiable {
            let id: String
            let title: String
            let items: [String]
        }

        let sections: [Section]
    }

    static func plan(for result: SkinScanResult, ownedProducts: [Product]) -> Plan {
        var sections: [Plan.Section] = []

        let zoneItems = zoneBreakdown(result.findings)
        if !zoneItems.isEmpty {
            sections.append(Plan.Section(id: "zones", title: "Where things are", items: zoneItems))
        }

        let routineItems = routineAdjustments(for: result.counts, ownedProducts: ownedProducts)
        if !routineItems.isEmpty {
            sections.append(Plan.Section(id: "routine", title: "How to work it in", items: routineItems))
        }

        let expectationItems = expectations(for: result.counts)
        if !expectationItems.isEmpty {
            sections.append(Plan.Section(id: "expectations", title: "What to expect", items: expectationItems))
        }

        return Plan(sections: sections)
    }

    // MARK: - Sections

    /// "Forehead — 2 blemish areas, 1 dark spot", ordered top of face down.
    private static func zoneBreakdown(_ findings: [SkinFinding]) -> [String] {
        let zoneOrder: [FaceZone] = [.forehead, .nose, .leftCheek, .rightCheek, .chin]
        return zoneOrder.compactMap { zone in
            let inZone = findings.filter { $0.zone == zone }
            guard !inZone.isEmpty else { return nil }
            let parts = FindingKind.allCases.compactMap { kind -> String? in
                let count = inZone.filter { $0.kind == kind }.count
                guard count > 0 else { return nil }
                return "\(count) \(count == 1 ? kind.singular : kind.plural)"
            }
            return "\(zone.rawValue.prefix(1).capitalized + zone.rawValue.dropFirst()) — \(parts.joined(separator: ", "))"
        }
    }

    /// Sequencing guidance for the ingredients the findings call for,
    /// phrased against how this app already orders routines
    /// (LayerCategory steps) and its conflict rules.
    private static func routineAdjustments(for counts: [FindingKind: Int], ownedProducts: [Product]) -> [String] {
        var items: [String] = []
        let active = ownedProducts.filter { !$0.isArchived }

        if (counts[.blemish] ?? 0) > 0 {
            items.append("Use a BHA (salicylic acid) treatment in your PM routine, after cleansing and before moisturizer. Start 2-3 evenings a week and build up.")
            if active.contains(where: { $0.conflictTags.contains(.retinoid) }) {
                items.append("You also use a retinoid — alternate evenings rather than layering it with the BHA (the Routine tab flags this conflict too).")
            }
        }

        if (counts[.spot] ?? 0) > 0 {
            items.append("Use a vitamin C serum in your AM routine, after cleansing and before sunscreen — it pairs with daily SPF, which does most of the work against dark spots.")
            if !active.contains(where: { $0.layerCategory == .sunscreen }) {
                items.append("No sunscreen in your cabinet — daily SPF is the single highest-impact step for fading dark spots.")
            }
        }

        return items
    }

    private static func expectations(for counts: [FindingKind: Int]) -> [String] {
        var items: [String] = []
        if (counts[.blemish] ?? 0) > 0 {
            items.append("Blemishes: expect 4-6 weeks of consistent use before a visible change; a brief purge in weeks 1-2 is normal with BHAs.")
        }
        if (counts[.spot] ?? 0) > 0 {
            items.append("Dark spots: fading is slow — think 8-12 weeks. Photograph in similar lighting weekly so the score trend means something.")
        }
        if !items.isEmpty {
            items.append("This is general skincare guidance from a photo scan, not medical advice — a dermatologist beats an app for anything persistent or painful.")
        }
        return items
    }
}
