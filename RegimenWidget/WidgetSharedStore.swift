//
//  WidgetSharedStore.swift
//  RegimenWidget
//

import Foundation
import WidgetKit

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
    // Every name and shape below comes from WidgetSharedTypes.swift, which
    // lives in the app's folder and is compiled into this target too. It
    // used to be copied out by hand on both sides with a comment asking
    // future editors to keep them identical.
    static let suiteName = WidgetSharedKeys.suiteName
    static let widgetKind = WidgetSharedKeys.widgetKind

    private static let streakKey = WidgetSharedKeys.streak
    private static let latestScoreKey = WidgetSharedKeys.latestScore
    private static let isPremiumKey = WidgetSharedKeys.isPremium
    private static let amItemsKey = WidgetSharedKeys.amItems
    private static let pmItemsKey = WidgetSharedKeys.pmItems
    private static let pendingTogglesKey = WidgetSharedKeys.pendingToggles

    typealias Snapshot = WidgetSnapshot

    static func read() -> Snapshot {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return Snapshot() }
        return Snapshot(
            streak: defaults.integer(forKey: streakKey),
            latestScore: defaults.object(forKey: latestScoreKey) as? Double,
            isPremium: defaults.bool(forKey: isPremiumKey),
            amItems: WidgetSharedKeys.items(from: defaults, key: amItemsKey),
            pmItems: WidgetSharedKeys.items(from: defaults, key: pmItemsKey)
        )
    }

    /// Flips one item's checked state in the shared container, so the
    /// widget's next render reflects the tap right away, and records the
    /// resulting state for the app to reconcile later.
    static func toggle(productID: String, timeOfDay: String) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let key = timeOfDay == "AM" ? amItemsKey : pmItemsKey

        var items = WidgetSharedKeys.items(from: defaults, key: key)
        guard let index = items.firstIndex(where: { $0.id.uuidString == productID }) else { return }
        items[index].isChecked.toggle()
        defaults.set(try? JSONEncoder().encode(items), forKey: key)

        var pending = defaults.dictionary(forKey: pendingTogglesKey) as? [String: Bool] ?? [:]
        pending[WidgetSharedKeys.pendingToggleKey(productID: productID, timeOfDay: timeOfDay)] = items[index].isChecked
        defaults.set(pending, forKey: pendingTogglesKey)

        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// The hour AM hands over to PM, as set in the app (see
    /// `RoutineClock`). Read here rather than hardcoding midday, so a night
    /// shift worker's widget agrees with their app.
    static var changeoverHour: Int { WidgetSharedKeys.storedChangeoverHour }
}
