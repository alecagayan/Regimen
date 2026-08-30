//
//  WidgetDataStore.swift
//  Regimen
//

import Foundation
import WidgetKit

/// Writes the handful of numbers the home screen widget needs into the
/// shared App Group container -- the widget extension runs in a separate
/// process and can't read `AppData` in memory, so this is the only way it
/// sees anything. Keys/suite name must match the widget's own (duplicated,
/// not shared -- separate module) read side in
/// RegimenWidget/RegimenWidget.swift.
enum WidgetDataStore {
    private static let suiteName = "group.com.alecagayan.Regimen"
    private static let streakKey = "streak"
    private static let latestScoreKey = "latestScore"
    private static let isPremiumKey = "isPremium"
    private static let widgetKind = "RegimenWidget"

    static func write(streak: Int, latestScore: Double?, isPremium: Bool) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        defaults.set(streak, forKey: streakKey)
        if let latestScore {
            defaults.set(latestScore, forKey: latestScoreKey)
        } else {
            defaults.removeObject(forKey: latestScoreKey)
        }
        defaults.set(isPremium, forKey: isPremiumKey)
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }
}
