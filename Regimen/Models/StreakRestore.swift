//
//  StreakRestore.swift
//  Regimen
//

import Foundation

/// Maps 1:1 to the `streak_restores` table. One row per day the user has
/// spent a restore on -- a day with no usage logs that `StreakCalculator`
/// nonetheless counts, bridging a gap that would have reset the streak.
///
/// `restoredOn` is a calendar day, not an instant: a restore applies to a
/// whole day in the user's own timezone. It's encoded as a plain `yyyy-MM-dd`
/// string to match the column's `date` type -- letting `Date` round-trip
/// through the default ISO-8601 encoding would attach a time and could
/// shift the restore onto the neighbouring day.
struct StreakRestore: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var restoredOn: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case restoredOn = "restored_on"
    }

    init(id: UUID = UUID(), userID: UUID, restoredOn: Date) {
        self.id = id
        self.userID = userID
        self.restoredOn = restoredOn
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        restoredOn = try PostgresDay.decode(from: container, forKey: .restoredOn)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(PostgresDay.string(from: restoredOn), forKey: .restoredOn)
    }
}
