//
//  WidgetDataStore.swift
//  Regimen
//

import Foundation
import WidgetKit

/// One line item in the widget's interactive routine checklist -- a
/// snapshot of a single product's AM or PM check-off state. Duplicated
/// (not shared) in RegimenWidget/RegimenWidget.swift, same reasoning as
/// the rest of this file: the widget extension is a separate module.
struct WidgetRoutineItem: Codable, Identifiable {
    var id: UUID
    var name: String
    var icon: String
    var isChecked: Bool
}

/// Writes the handful of numbers -- and, now, today's AM/PM routine
/// checklist -- the home screen widget needs into the shared App Group
/// container. The widget extension runs in a separate process and can't
/// read `AppData` in memory, so this is the only way it sees anything.
/// Keys/suite name must match the widget's own (duplicated, not shared --
/// separate module) read side in RegimenWidget/RegimenWidget.swift.
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
    private static let suiteName = "group.com.alecagayan.Regimen"
    private static let streakKey = "streak"
    private static let latestScoreKey = "latestScore"
    private static let isPremiumKey = "isPremium"
    private static let amItemsKey = "amItems"
    private static let pmItemsKey = "pmItems"
    private static let pendingTogglesKey = "pendingToggles"
    private static let widgetKind = "RegimenWidget"

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
