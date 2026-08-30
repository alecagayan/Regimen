//
//  UsageLog.swift
//  Regimen
//

import Foundation

/// AM/PM only (unlike `RoutineTime` on `Product`, which also allows `.both`)
/// because a single log entry always records one concrete check-off, not a
/// recurring schedule.
enum TimeOfDay: String, Codable, CaseIterable, Identifiable, Hashable {
    case am = "AM"
    case pm = "PM"
    var id: String { rawValue }
}

/// Maps 1:1 to the `usage_logs` table. One row per check-off in the Routine
/// tab. `DepletionPredictor` reads the recent history of these to estimate a
/// usage rate; there is deliberately no "edit" affordance for logs in the UI
/// — if usage tracking needs to be corrected, the simplest and least
/// error-prone route is un-checking and re-checking the item.
struct UsageLog: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var productID: UUID
    var timestamp: Date
    var timeOfDay: TimeOfDay

    /// Copied from the product's `typicalDoseML` at the moment this log was
    /// created — a per-use estimate rather than a precise measurement, since
    /// there's no way to actually weigh or sense how much was applied.
    /// Stored per-log (not re-derived from the product later) so editing a
    /// product's dose going forward doesn't rewrite history.
    var estimatedAmountUsedML: Double

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case productID = "product_id"
        case timestamp
        case timeOfDay = "time_of_day"
        case estimatedAmountUsedML = "estimated_amount_used_ml"
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        productID: UUID,
        timestamp: Date = .now,
        timeOfDay: TimeOfDay,
        estimatedAmountUsedML: Double
    ) {
        self.id = id
        self.userID = userID
        self.productID = productID
        self.timestamp = timestamp
        self.timeOfDay = timeOfDay
        self.estimatedAmountUsedML = estimatedAmountUsedML
    }
}
