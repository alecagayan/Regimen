//
//  RoutineClock.swift
//  Regimen
//

import Foundation
import WidgetKit

/// When the app considers the morning routine to hand over to the evening
/// one.
///
/// Noon is a fine default and a terrible assumption. Someone on nights
/// starts their day at 7pm, and a hardcoded midday boundary meant the app
/// and its widget both showed them the wrong half of their routine for
/// their entire waking shift.
///
/// Stored in the App Group rather than on the account, because the widget
/// process has no Supabase session and has to read the same value (see
/// `WidgetDataStore`). The trade-off is that it doesn't follow the account
/// to a second device, which for a preference about this device's clock is
/// the right way round.
enum RoutineClock {
    static let suiteName = "group.com.alecagayan.Regimen"
    private static let changeoverHourKey = "routineChangeoverHour"

    /// Midday, matching what both the app and the widget assumed before
    /// this was configurable.
    static let defaultChangeoverHour = 12

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: suiteName)
    }

    /// Clamps to a real hour of the day. Separated out so it can be
    /// checked without touching shared storage.
    static func clamped(hour: Int) -> Int {
        min(max(hour, 0), 23)
    }

    /// Hour (0-23) at which AM hands over to PM.
    static var changeoverHour: Int {
        get {
            guard let defaults, defaults.object(forKey: changeoverHourKey) != nil else {
                return defaultChangeoverHour
            }
            return clamped(hour: defaults.integer(forKey: changeoverHourKey))
        }
        set {
            defaults?.set(clamped(hour: newValue), forKey: changeoverHourKey)
            // The widget's "Auto" mode reads this too, and its timeline is
            // scheduled around the old boundary until it's rebuilt.
            WidgetCenter.shared.reloadTimelines(ofKind: "RegimenWidget")
        }
    }

    /// Which routine it currently is, by this user's own changeover hour.
    ///
    /// The hour is a parameter rather than read inline so this stays a pure
    /// function of its inputs. It defaults to the stored setting, so every
    /// caller in the app behaves as expected while tests can exercise a
    /// night shift without writing to shared storage.
    static func currentTimeOfDay(
        now: Date = .now,
        calendar: Calendar = .current,
        changeoverHour: Int = RoutineClock.changeoverHour
    ) -> TimeOfDay {
        calendar.component(.hour, from: now) < clamped(hour: changeoverHour) ? .am : .pm
    }

    /// The next changeover after `now`, used to schedule the widget's
    /// automatic AM/PM flip.
    static func nextChangeover(
        after now: Date = .now,
        calendar: Calendar = .current,
        changeoverHour: Int = RoutineClock.changeoverHour
    ) -> Date {
        let hour = clamped(hour: changeoverHour)
        let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
        if today > now { return today }
        // Past today's changeover, so the next one is tomorrow's.
        return calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(3600)
    }

    /// "12:00 PM" style label for the settings row.
    static func label(forHour hour: Int) -> String {
        var components = DateComponents()
        components.hour = hour
        components.minute = 0
        let date = Calendar.current.date(from: components) ?? .now
        return date.formatted(.dateTime.hour().minute())
    }
}
