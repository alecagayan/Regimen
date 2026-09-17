//
//  PostgresDay.swift
//  Regimen
//

import Foundation

/// Encoding and decoding for Postgres `date` columns.
///
/// A `date` column has no time and no timezone: Postgres sends back
/// `"2026-09-15"`, not an ISO-8601 instant. Swift's synthesised `Codable`
/// conformance hands that string to the decoder's date strategy, which
/// expects a full timestamp, and the whole row fails to decode -- which
/// surfaces in the app as "The data couldn't be read because it isn't in
/// the correct format" and takes the entire fetch down with it.
///
/// `StreakRestore` solved this with a hand-written coder and a comment
/// warning about exactly this trap. `SkinReaction` and `ProductEmpty` were
/// written later with plain synthesis and fell into it anyway, so the
/// knowledge now lives in one shared place instead of one model's comment.
///
/// Every calendar-day column in this schema goes through here:
/// `streak_restores.restored_on`, `skin_reactions.occurred_on`,
/// `product_empties.finished_on`.
enum PostgresDay {
    /// POSIX locale and a fixed format, so parsing never depends on the
    /// device's locale or calendar.
    static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Reads a `date` column, tolerating a full timestamp as well.
    ///
    /// The fallback matters because the same logical column can come back
    /// either way depending on how a row was written -- a value inserted by
    /// a SQL script with `now()` rather than `current_date`, for instance,
    /// arrives with a time attached. Refusing those would mean a single
    /// hand-written row breaking the whole table's fetch.
    static func decode<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        forKey key: K
    ) throws -> Date {
        let raw = try container.decode(String.self, forKey: key)
        if let day = formatter.date(from: raw) {
            return day
        }
        if let instant = ISO8601DateFormatter().date(from: raw) {
            return instant
        }
        // Postgres timestamps carry fractional seconds, which the plain
        // ISO-8601 formatter above rejects.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let instant = fractional.date(from: raw) {
            return instant
        }
        throw DecodingError.dataCorruptedError(
            forKey: key,
            in: container,
            debugDescription: "Expected yyyy-MM-dd or an ISO-8601 timestamp, got \(raw)"
        )
    }
}
