//
//  ProductSchedule.swift
//  Regimen
//

import Foundation

/// How often a product is meant to be used.
///
/// Everything used to be implicitly daily, which is not how routines work:
/// retinoids run every other night, exfoliants twice a week, masks on
/// Sundays. The app was already handing out advice it had no way to store
/// -- `ConflictChecker` says "alternate evenings", `RecommendationEngine`
/// says "start 2x a week" -- and the user had nowhere to put either.
///
/// Three shapes, stored as three columns (see
/// `supabase/schedules_and_history.sql`) rather than one encoded blob, so a
/// row stays readable in the dashboard and decodes without a nested type.
enum ProductFrequency: Hashable {
    case daily
    /// Specific weekdays, using `Calendar`'s numbering: 1 = Sunday.
    case daysOfWeek(Set<Int>)
    /// Every N days, counted from the product's `openedDate`.
    case everyNDays(Int)

    static let everyOtherDay = ProductFrequency.everyNDays(2)

    var kindKey: String {
        switch self {
        case .daily: "daily"
        case .daysOfWeek: "days_of_week"
        case .everyNDays: "every_n_days"
        }
    }

    /// Short label for a row or chip.
    var shortLabel: String {
        switch self {
        case .daily:
            "Daily"
        case .daysOfWeek(let days):
            days.count == 7 ? "Daily" : "\(days.count)x a week"
        case .everyNDays(let interval):
            interval == 2 ? "Every other day" : "Every \(interval) days"
        }
    }

    /// Spelled out, for the one place there's room to be specific.
    var longLabel: String {
        switch self {
        case .daily:
            return "Every day"
        case .daysOfWeek(let days):
            guard !days.isEmpty else { return "No days selected" }
            guard days.count < 7 else { return "Every day" }
            let symbols = Calendar.current.shortWeekdaySymbols
            return days.sorted()
                .compactMap { symbols.indices.contains($0 - 1) ? symbols[$0 - 1] : nil }
                .joined(separator: ", ")
        case .everyNDays(let interval):
            return interval == 2 ? "Every other day" : "Every \(interval) days"
        }
    }

    var isDaily: Bool {
        switch self {
        case .daily: true
        case .daysOfWeek(let days): days.count == 7
        case .everyNDays(let interval): interval <= 1
        }
    }

    /// Whether this product is due on a given day.
    ///
    /// - Parameter anchor: the product's `openedDate`, which `everyNDays`
    ///   counts forward from. Using the opened date rather than an
    ///   arbitrary epoch means "every other day" lines up with the day the
    ///   user actually started, not with whether the Unix day number
    ///   happens to be even.
    func isScheduled(on date: Date, anchor: Date, calendar: Calendar = .current) -> Bool {
        switch self {
        case .daily:
            return true
        case .daysOfWeek(let days):
            // An empty set would silently hide the product forever, which
            // is never what someone means -- treat it as daily.
            guard !days.isEmpty else { return true }
            return days.contains(calendar.component(.weekday, from: date))
        case .everyNDays(let interval):
            guard interval > 1 else { return true }
            let start = calendar.startOfDay(for: anchor)
            let day = calendar.startOfDay(for: date)
            guard let elapsed = calendar.dateComponents([.day], from: start, to: day).day else { return true }
            // Days before the product was opened still count as "on
            // schedule" so a backfill isn't blocked by arithmetic.
            guard elapsed >= 0 else { return true }
            return elapsed % interval == 0
        }
    }

    // MARK: - Storage

    init(kind: String, daysOfWeek: [Int], intervalDays: Int) {
        switch kind {
        case "days_of_week": self = .daysOfWeek(Set(daysOfWeek))
        case "every_n_days": self = .everyNDays(max(intervalDays, 1))
        default: self = .daily
        }
    }

    var storedDaysOfWeek: [Int] {
        if case .daysOfWeek(let days) = self { return days.sorted() }
        return []
    }

    var storedIntervalDays: Int {
        if case .everyNDays(let interval) = self { return max(interval, 1) }
        return 1
    }
}

extension Product {
    var frequency: ProductFrequency {
        ProductFrequency(
            kind: frequencyKind,
            daysOfWeek: frequencyDaysOfWeek,
            intervalDays: frequencyIntervalDays
        )
    }

    mutating func setFrequency(_ frequency: ProductFrequency) {
        frequencyKind = frequency.kindKey
        frequencyDaysOfWeek = frequency.storedDaysOfWeek
        frequencyIntervalDays = frequency.storedIntervalDays
    }

    /// Whether this product belongs in the routine on a given day.
    func isScheduled(on date: Date, calendar: Calendar = .current) -> Bool {
        frequency.isScheduled(on: date, anchor: openedDate, calendar: calendar)
    }

    // MARK: - Shelf life

    /// When this bottle stops being worth using, from its opened date plus
    /// the period-after-opening the user recorded. Nil when they haven't
    /// said.
    var expiresOn: Date? {
        guard let months = monthsAfterOpening, months > 0 else { return nil }
        return Calendar.current.date(byAdding: .month, value: months, to: openedDate)
    }

    var isExpired: Bool {
        guard let expiresOn else { return false }
        return expiresOn < .now
    }

    /// True in the last month before expiry, so the app can mention it
    /// before the product is already past it.
    var isNearingExpiry: Bool {
        guard let expiresOn, !isExpired else { return false }
        guard let warningStart = Calendar.current.date(byAdding: .month, value: -1, to: expiresOn) else { return false }
        return warningStart <= .now
    }

    /// A short line about shelf life, or nil when there's nothing to say.
    var shelfLifeNote: String? {
        guard let expiresOn else { return nil }
        let formatted = expiresOn.formatted(.dateTime.month(.abbreviated).year())
        if isExpired { return "Past its best since \(formatted)" }
        if isNearingExpiry { return "Best used by \(formatted)" }
        return nil
    }
}
