//
//  SkinProfile.swift
//  Regimen
//

import Foundation

enum SkinType: String, CaseIterable, Identifiable, Codable {
    case oily = "Oily"
    case dry = "Dry"
    case combination = "Combination"
    case normal = "Normal"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .oily: "Shiny by midday, visible pores"
        case .dry: "Tight or flaky, rarely shiny"
        case .combination: "Oily T-zone, drier cheeks"
        case .normal: "Comfortable most of the time"
        }
    }
}

enum SkinSensitivity: String, CaseIterable, Identifiable, Codable {
    case notSensitive = "Not really"
    case sensitive = "Yes, easily"

    var id: String { rawValue }
}

enum ActivesExperience: String, CaseIterable, Identifiable, Codable {
    case beginner = "New to this"
    case experienced = "Used to actives"

    var id: String { rawValue }
}

/// How many steps the builder should reach for. The three "core" steps
/// (cleanse, treat, moisturize, protect -- see `RoutineBuilderEngine`) are
/// never optional; this controls whether toner, eye care, and facial oil
/// get added on top, since those are the steps most likely to feel like
/// "extra" to someone who just wants the basics covered.
enum RoutineLength: String, CaseIterable, Identifiable, Codable {
    case short = "Short"
    case medium = "Medium"
    case long = "Long"

    var id: String { rawValue }

    var detail: String {
        switch self {
        case .short: "Just the essentials — cleanse, treat, moisturize, protect"
        case .medium: "Adds a toner for a fuller routine"
        case .long: "The complete routine, including eye care and a facial oil"
        }
    }
}

/// What the user tells us about their own skin, gathered by the short quiz
/// in front of the routine builder. A scan can see what's on the surface
/// but not how skin *behaves* -- whether it stings, whether it runs oily by
/// afternoon, whether a retinoid is old news or brand new. Those change the
/// right routine as much as the findings do, and only the user knows them.
///
/// Stored device-locally in `UserDefaults` rather than in Supabase: it's a
/// lightweight personalization input rather than user data worth a schema
/// migration, and keeping it local means the quiz needs no new table to
/// work. The tradeoff is that it doesn't follow the account to another
/// device -- the quiz simply asks again there, pre-filled with defaults.
struct SkinProfile: Codable, Equatable {
    var skinType: SkinType = .combination
    var sensitivity: SkinSensitivity = .notSensitive
    var experience: ActivesExperience = .beginner
    var routineLength: RoutineLength = .medium

    var isSensitive: Bool { sensitivity == .sensitive }

    private static let storageKey = "skinProfile"

    static func load(from defaults: UserDefaults = .standard) -> SkinProfile {
        guard let data = defaults.data(forKey: storageKey),
              let profile = try? JSONDecoder().decode(SkinProfile.self, from: data)
        else { return SkinProfile() }
        return profile
    }

    func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
