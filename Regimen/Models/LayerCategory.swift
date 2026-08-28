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
}
