//
//  WidgetDataStore.swift
//  Regimen
//

import Foundation
import WidgetKit

/// Writes the handful of numbers -- and, now, today's AM/PM routine
/// checklist -- the home screen widget needs into the shared App Group
/// container. The widget extension runs in a separate process and can't
/// read `AppData` in memory, so this is the only way it sees anything.
/// Keys, the suite name, and the item shape all come from
/// `WidgetSharedTypes.swift`, which both targets compile -- they used to
/// be transcribed by hand on each side.
///
/// The widget's checkboxes are interactive (see
/// `ToggleWidgetRoutineItemIntent` in the widget extension), but that
/// intent runs in the widget's own process and has no access to the
/// user's Supabase session. Rather than sharing Keychain-backed auth
/// between two processes -- a much bigger, riskier change -- a tap there
/// writes to a small "pending toggles" dictionary in this same shared
/// container instead. `consumePendingToggles` is how the main app picks
/// those up and actually applies them (see
/// `AppData.flushPendingWidgetToggles`), meaning a toggle made purely in
/// the widget, without ever reopening the app, won't reach Supabase (and
/// won't count toward the streak) until the app is next opened. A real
/// trade-off, consistent with this app's documented choice not to build a
/// full offline-first sync layer (see `AppData`'s own header comment).
enum WidgetDataStore {
    // Names and shapes come from WidgetSharedTypes.swift, which the widget
    // extension compiles too -- see that file for why they aren't written
    // out twice any more.
    private static let suiteName = WidgetSharedKeys.suiteName
    private static let streakKey = WidgetSharedKeys.streak
    private static let latestScoreKey = WidgetSharedKeys.latestScore
    private static let isPremiumKey = WidgetSharedKeys.isPremium
    private static let amItemsKey = WidgetSharedKeys.amItems
    private static let pmItemsKey = WidgetSharedKeys.pmItems
    private static let pendingTogglesKey = WidgetSharedKeys.pendingToggles
    private static let widgetKind = WidgetSharedKeys.widgetKind

    static func write(
        streak: Int,
        latestScore: Double?,
        isPremium: Bool,
        amItems: [WidgetRoutineItem],
        pmItems: [WidgetRoutineItem]
    ) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(streak, forKey: streakKey)
        if let latestScore {
            defaults.set(latestScore, forKey: latestScoreKey)
        } else {
            defaults.removeObject(forKey: latestScoreKey)
        }
        defaults.set(isPremium, forKey: isPremiumKey)
        defaults.set(try? JSONEncoder().encode(amItems), forKey: amItemsKey)
        defaults.set(try? JSONEncoder().encode(pmItems), forKey: pmItemsKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    /// What the shared container currently holds.
    ///
    /// The app normally has all of this in `AppData` already; this exists
    /// for App Intents (see `RegimenAppIntents`), which Siri can run in a
    /// process where `AppData` was never constructed and no Supabase
    /// session exists.
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

    /// Records an intended check-off from outside the app's normal flow
    /// (a Siri phrase, a Shortcut), updating the locally-cached list so the
    /// widget reflects it right away and queueing the intent for the app to
    /// reconcile. Same mechanism the widget's own checkboxes use.
    static func recordToggle(productID: String, timeOfDay: String, isChecked: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        let key = timeOfDay == "AM" ? amItemsKey : pmItemsKey

        var list = WidgetSharedKeys.items(from: defaults, key: key)
        if let index = list.firstIndex(where: { $0.id.uuidString == productID }) {
            list[index].isChecked = isChecked
            defaults.set(try? JSONEncoder().encode(list), forKey: key)
        }

        var pending = defaults.dictionary(forKey: pendingTogglesKey) as? [String: Bool] ?? [:]
        pending[WidgetSharedKeys.pendingToggleKey(productID: productID, timeOfDay: timeOfDay)] = isChecked
        defaults.set(pending, forKey: pendingTogglesKey)
    }

    /// Reads and clears the widget's pending checkbox taps -- keyed
    /// "<productID>|<AM or PM>", valued with the checked state the widget
    /// wants that item to end up in. A dictionary keyed this way (rather
    /// than an append-only log of taps) means only the *latest* intended
    /// state per item survives if the same box was tapped more than once
    /// before the app reopened.
    static func consumePendingToggles() -> [String: Bool] {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return [:] }
        let pending = defaults.dictionary(forKey: pendingTogglesKey) as? [String: Bool] ?? [:]
        defaults.removeObject(forKey: pendingTogglesKey)
        return pending
    }
}
