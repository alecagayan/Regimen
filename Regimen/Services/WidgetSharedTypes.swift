//
//  WidgetSharedTypes.swift
//  Regimen
//
//  COMPILED INTO BOTH TARGETS. This file lives in the app's folder but is
//  also a member of RegimenWidgetExtension, via a membership exception in
//  the project file. Editing it changes both processes at once, which is
//  the entire point.
//

import Foundation

/// One line item in the widget's interactive routine checklist.
///
/// This type and the keys below used to be written out by hand in two
/// places -- `WidgetDataStore` in the app and `WidgetSharedStore` in the
/// widget -- with comments in both saying they had to stay identical or
/// the JSON wouldn't round-trip. That's a promise a comment can't keep:
/// the two processes only ever meet through `UserDefaults`, so a field
/// added on one side and forgotten on the other fails silently at runtime,
/// in a widget, on a device, with no compiler to catch it.
///
/// Each target still gets its own copy of the type at compile time (they
/// are separate modules), but both copies are now generated from this one
/// source, so they cannot disagree.
struct WidgetRoutineItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var icon: String
    var isChecked: Bool

    init(id: UUID, name: String, icon: String, isChecked: Bool) {
        self.id = id
        self.name = name
        self.icon = icon
        self.isChecked = isChecked
    }
}

/// Everything the shared App Group container holds.
struct WidgetSnapshot {
    var streak: Int = 0
    var latestScore: Double?
    var isPremium: Bool = false
    var amItems: [WidgetRoutineItem] = []
    var pmItems: [WidgetRoutineItem] = []

    init(
        streak: Int = 0,
        latestScore: Double? = nil,
        isPremium: Bool = false,
        amItems: [WidgetRoutineItem] = [],
        pmItems: [WidgetRoutineItem] = []
    ) {
        self.streak = streak
        self.latestScore = latestScore
        self.isPremium = isPremium
        self.amItems = amItems
        self.pmItems = pmItems
    }
}

/// The App Group container's address and key names.
///
/// A typo in any one of these is a silent failure: the reader just sees an
/// absent value and renders an empty widget. Defining them once removes
/// that failure mode rather than documenting it.
enum WidgetSharedKeys {
    static let suiteName = "group.com.alecagayan.Regimen"
    static let widgetKind = "RegimenWidget"

    static let streak = "streak"
    static let latestScore = "latestScore"
    static let isPremium = "isPremium"
    static let amItems = "amItems"
    static let pmItems = "pmItems"
    static let pendingToggles = "pendingToggles"
    static let changeoverHour = "routineChangeoverHour"

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// Key for one pending check-off, `"<productID>|<AM or PM>"`.
    static func pendingToggleKey(productID: String, timeOfDay: String) -> String {
        "\(productID)|\(timeOfDay)"
    }

    static func items(from defaults: UserDefaults, key: String) -> [WidgetRoutineItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WidgetRoutineItem].self, from: data)) ?? []
    }

    /// The hour AM hands over to PM (see `RoutineClock`). Read by the
    /// widget, which has no access to the app's own settings.
    static var storedChangeoverHour: Int {
        guard let defaults, defaults.object(forKey: changeoverHour) != nil else { return 12 }
        return min(max(defaults.integer(forKey: changeoverHour), 0), 23)
    }
}

/// Deep links into the app.
///
/// Lives here because both processes need it and they cannot share code
/// any other way: the widget builds these URLs, the app parses them. A
/// scheme string duplicated across a target boundary is the same silent
/// runtime failure as a duplicated `UserDefaults` key -- the tap just does
/// nothing, with nothing to debug.
enum AppDeepLink {
    static let scheme = "regimen"

    /// The routine tab, optionally pinned to one half of the day.
    /// `regimen://routine?time=PM`
    static func routine(timeOfDay: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "routine"
        if let timeOfDay {
            components.queryItems = [URLQueryItem(name: "time", value: timeOfDay)]
        }
        return components.url
    }

    /// Where a password-reset email sends the user back to.
    ///
    /// Supabase appends the recovery token to this, so it must be
    /// registered as a Redirect URL in the Supabase dashboard or the link
    /// in the email is rejected before it ever reaches the app.
    static var passwordReset: URL? { URL(string: "\(scheme)://reset-password") }

    static func tab(_ host: String) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        return components.url
    }
}
