//
//  LayerCategory.swift
//  Regimen
//

import Foundation

/// The skincare-layering step a product belongs to. `rank` encodes the
/// standard "cleanse, thinnest-to-thickest, occlusive last" layering rule
/// dermatologists commonly give — this is a fixed, universally-agreed
/// ordering of *categories*, not a personalized or formulation-chemistry
/// model, so a small hardcoded enum is the right amount of engineering for
/// it (same reasoning as `ConflictChecker`'s hardcoded pairing table).
enum LayerCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case cleanser = "Cleanser"
    case toner = "Toner"
    case treatment = "Treatment"
    case eyeCare = "Eye Care"
    case moisturizer = "Moisturizer"
    case facialOil = "Facial Oil"
    case sunscreen = "Sunscreen"
    case primer = "Primer"

    var id: String { rawValue }

    /// Lower applies first.
    var rank: Int {
        switch self {
        case .cleanser: 0
        case .toner: 1
        case .treatment: 2
        case .eyeCare: 3
        case .moisturizer: 4
        case .facialOil: 5
        case .sunscreen: 6
        case .primer: 7
        }
    }

    var icon: String {
        switch self {
        case .cleanser: "drop.fill"
        case .toner: "circle.hexagongrid.fill"
        case .treatment: "eyedropper.halffull"
        case .eyeCare: "eye.fill"
        case .moisturizer: "cloud.fill"
        case .facialOil: "circle.fill"
        case .sunscreen: "sun.max.fill"
        case .primer: "paintbrush.fill"
        }
    }

    /// A rough starting point for "how much product per use," in mL, used to
    /// pre-fill a new product's `typicalDoseML` (see `Product`). These are
    /// generic face-application heuristics (a dime-sized amount for
    /// cleanser, a few drops for a serum, the "quarter teaspoon" sunscreen
    /// guideline, ...) — not personalized, and always user-editable. Better
    /// than one flat number for every product regardless of type, which is
    /// what this replaced.
    /// Whether this step belongs in an auto-built *skincare* routine.
    ///
    /// `.primer` is the odd one out: it exists so makeup can be layered in
    /// the right order relative to skincare (see `LayeringAdvisor`), and in
    /// the catalog it holds foundation and mascara alongside actual primers
    /// (see `supabase/layering.sql`). Those are fine to track in a cabinet
    /// and to order correctly, but suggesting one as a routine step is
    /// wrong -- it's how `RoutineBuilderEngine` ended up recommending a
    /// mascara. A user's own primer still shows in their routine; it just
    /// isn't something the builder proposes.
    var isSkincareStep: Bool {
        self != .primer
    }

    var defaultDoseML: Double {
        switch self {
        case .cleanser: 2.0
        case .toner: 1.0
        case .treatment: 0.5
        case .eyeCare: 0.2
        case .moisturizer: 1.5
        case .facialOil: 0.4
        case .sunscreen: 1.25
        case .primer: 0.5
        }
    }
}
