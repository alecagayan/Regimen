//
//  WidgetSharedStore.swift
//  RegimenWidget
//

import Foundation
import WidgetKit

/// One line item in the widget's routine checklist.
///
/// Duplicated from `Regimen/Services/WidgetDataStore.swift`, not shared --
/// the widget extension is a separate module. The two definitions must
/// stay field-for-field identical or the JSON won't round-trip.
struct WidgetRoutineItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var icon: String
    var isChecked: Bool
}

/// The widget's half of the App Group container it shares with the app.
///
/// The app writes (see `WidgetDataStore`); this reads. The one thing that
/// flows the other way is `toggle` -- a checkbox tap, which this can't
/// send to Supabase directly (the widget process has no auth session), so
/// it records the intended state for the app to apply next time it opens.
/// `WidgetDataStore`'s header explains that trade-off in full.
///
/// Keys and the suite name must match that file exactly.
enum WidgetSharedStore {
    static let suiteName = "group.com.alecagayan.Regimen"
    static let widgetKind = "RegimenWidget"

    private static let streakKey = "streak"
    private static let latestScoreKey = "latestScore"
    private static let isPremiumKey = "isPremium"
    private static let amItemsKey = "amItems"
    private static let pmItemsKey = "pmItems"
    private static let pendingTogglesKey = "pendingToggles"

    struct Snapshot {
        var streak: Int = 0
        var latestScore: Double?
        var isPremium: Bool = false
        var amItems: [WidgetRoutineItem] = []
        var pmItems: [WidgetRoutineItem] = []
    }

    static func read() -> Snapshot {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return Snapshot() }
        return Snapshot(
            streak: defaults.integer(forKey: streakKey),
            latestScore: defaults.object(forKey: latestScoreKey) as? Double,
            isPremium: defaults.bool(forKey: isPremiumKey),
            amItems: items(from: defaults, key: amItemsKey),
            pmItems: items(from: defaults, key: pmItemsKey)
        )
    }

    /// Flips one item's checked state in the shared container, so the
    /// widget's next render reflects the tap right away, and records the
    /// resulting state for the app to reconcile later.
    static func toggle(productID: String, timeOfDay: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let key = timeOfDay == "AM" ? amItemsKey : pmItemsKey

        var items = items(from: defaults, key: key)
        guard let index = items.firstIndex(where: { $0.id.uuidString == productID }) else { return }
        items[index].isChecked.toggle()
        defaults.set(try? JSONEncoder().encode(items), forKey: key)

        var pending = defaults.dictionary(forKey: pendingTogglesKey) as? [String: Bool] ?? [:]
        pending["\(productID)|\(timeOfDay)"] = items[index].isChecked
        defaults.set(pending, forKey: pendingTogglesKey)

        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    private static func items(from defaults: UserDefaults, key: String) -> [WidgetRoutineItem] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([WidgetRoutineItem].self, from: data)) ?? []
    }
}
