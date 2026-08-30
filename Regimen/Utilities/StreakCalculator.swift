//
//  StreakCalculator.swift
//  Regimen
//

import Foundation

/// Computes a simple day-based streak from usage log timestamps: a day
/// counts toward the streak if the user logged at least one product use
/// that day, full stop. Deliberately not "every scheduled product was
/// checked off" -- that stricter definition would need to know which
/// products were actually active on each past day, and product edits
/// (added, archived, routine time changed) would silently rewrite what
/// counted as "complete" for days that already happened.
///
/// A day the user has spent a *restore* on (see `StreakRestore`) counts
/// exactly as if it had been logged, which is the whole mechanism behind
/// the premium streak-restore feature.
enum StreakCalculator {
    struct Result {
        /// Consecutive days, ending today or yesterday, with at least one
        /// logged use. Today doesn't have to be logged yet to keep
        /// yesterday's streak alive -- the day isn't over -- but the streak
        /// resets to 0 the moment a full day passes with nothing logged.
        let currentStreak: Int
        /// Whether each of the last `historyLength` days (oldest first,
        /// ending today) had at least one log -- for a small dot-grid UI.
        let recentDays: [Bool]
    }

    static func compute(
        from logs: [UsageLog],
        restores: [StreakRestore] = [],
        historyLength: Int = 7,
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Result {
        let countedDays = countedDays(logs: logs, restores: restores, calendar: calendar)
        let today = calendar.startOfDay(for: now)

        var streak = 0
        var cursor = countedDays.contains(today)
            ? today
            : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        while countedDays.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }

        let recentDays = (0..<historyLength).reversed().compactMap { offset -> Bool? in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return countedDays.contains(day)
        }

        return Result(currentStreak: streak, recentDays: recentDays)
    }

    /// Every day that counts toward a streak: days with a usage log, plus
    /// days bridged by a restore.
    static func countedDays(
        logs: [UsageLog],
        restores: [StreakRestore],
        calendar: Calendar = .current
    ) -> Set<Date> {
        var days = Set(logs.map { calendar.startOfDay(for: $0.timestamp) })
        days.formUnion(restores.map { calendar.startOfDay(for: $0.restoredOn) })
        return days
    }

    /// Days the user actually logged, ignoring restores -- so the calendar
    /// can draw a restored day differently from an earned one rather than
    /// quietly passing it off as a day they showed up.
    static func loggedDays(logs: [UsageLog], calendar: Calendar = .current) -> Set<Date> {
        Set(logs.map { calendar.startOfDay(for: $0.timestamp) })
    }

    /// The single day a restore would bridge: the first gap walking
    /// backwards from the current streak's start.
    ///
    /// Returns nil when a restore would accomplish nothing -- when there's
    /// no gap yet, or when the gap has no earned history behind it to
    /// reconnect to (restoring a day that bridges to nothing would "restore"
    /// a one-day streak, which isn't worth spending anything on).
    static func restorableDay(
        logs: [UsageLog],
        restores: [StreakRestore] = [],
        calendar: Calendar = .current,
        now: Date = .now
    ) -> Date? {
        let countedDays = countedDays(logs: logs, restores: restores, calendar: calendar)
        guard !countedDays.isEmpty else { return nil }

        let today = calendar.startOfDay(for: now)

        // Walk back to the first day that doesn't count. Today itself is
        // never the gap -- the day isn't over, so nothing is broken yet.
        var cursor = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        while countedDays.contains(cursor) {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { return nil }
            cursor = previous
        }

        // Only worth restoring if there's earned history immediately behind
        // the gap for it to reconnect to.
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: cursor),
              countedDays.contains(dayBefore)
        else { return nil }

        return cursor
    }
}
