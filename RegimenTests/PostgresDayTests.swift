//
//  PostgresDayTests.swift
//  RegimenTests
//

import Foundation
import Testing
@testable import Regimen

/// Regression tests for a bug that shipped and could only be seen at
/// runtime: `SkinReaction` and `ProductEmpty` were written with synthesised
/// `Codable`, so Postgres `date` columns ("2026-09-15", no time, no zone)
/// failed to decode and took the entire reactions and empties fetches down
/// with them. The app reported "The data couldn't be read because it isn't
/// in the correct format" and those features stayed permanently empty.
///
/// Nothing in the type system catches this -- it needs a test that decodes
/// the exact payload shape PostgREST returns.
struct PostgresDayTests {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    // MARK: - The shape Postgres actually sends

    @Test func reactionDecodesADateOnlyColumn() throws {
        let reaction = try decode(SkinReaction.self, """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "occurred_on": "2026-09-15",
          "severity": "moderate",
          "note": "Stinging after the new serum."
        }
        """)

        #expect(reaction.severity == .moderate)
        #expect(Calendar.current.component(.year, from: reaction.occurredOn) == 2026)
        #expect(Calendar.current.component(.day, from: reaction.occurredOn) == 15)
    }

    @Test func emptyDecodesADateOnlyColumn() throws {
        let empty = try decode(ProductEmpty.self, """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "product_id": null,
          "product_name": "Gentle Cleanser",
          "brand": "Cetaphil",
          "finished_on": "2026-08-01",
          "would_repurchase": true,
          "rating": 4,
          "note": null
        }
        """)

        #expect(empty.productName == "Gentle Cleanser")
        #expect(empty.wouldRepurchase == true)
        #expect(empty.rating == 4)
        #expect(Calendar.current.component(.month, from: empty.finishedOn) == 8)
    }

    @Test func streakRestoreDecodesADateOnlyColumn() throws {
        let restore = try decode(StreakRestore.self, """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "restored_on": "2026-07-04"
        }
        """)
        #expect(Calendar.current.component(.day, from: restore.restoredOn) == 4)
    }

    // MARK: - Tolerated variations

    /// A row written by a SQL script using `now()` rather than
    /// `current_date` comes back as a full timestamp. Rejecting those would
    /// let one hand-written row break the whole table's fetch.
    @Test func aFullTimestampIsAlsoAccepted() throws {
        let reaction = try decode(SkinReaction.self, """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "occurred_on": "2026-09-15T12:00:00Z",
          "severity": "mild"
        }
        """)
        #expect(Calendar.current.component(.year, from: reaction.occurredOn) == 2026)
    }

    @Test func fractionalSecondsAreAccepted() throws {
        let reaction = try decode(SkinReaction.self, """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "occurred_on": "2026-09-15T12:00:00.123456Z",
          "severity": "severe"
        }
        """)
        #expect(reaction.severity == .severe)
    }

    /// Absent optionals must not fail the row -- `note`, `rating` and
    /// `would_repurchase` are all genuinely nullable.
    @Test func missingOptionalsDoNotBreakTheRow() throws {
        let empty = try decode(ProductEmpty.self, """
        {
          "id": "\(UUID().uuidString)",
          "user_id": "\(UUID().uuidString)",
          "product_name": "Mystery Bottle",
          "finished_on": "2026-01-01"
        }
        """)
        #expect(empty.brand == "")
        #expect(empty.rating == nil)
        #expect(empty.wouldRepurchase == nil)
    }

    @Test func garbageIsRejectedWithAUsefulMessage() {
        #expect(throws: DecodingError.self) {
            try decode(SkinReaction.self, """
            {
              "id": "\(UUID().uuidString)",
              "user_id": "\(UUID().uuidString)",
              "occurred_on": "not a date",
              "severity": "mild"
            }
            """)
        }
    }

    // MARK: - Round trip

    /// What gets written back must be a bare day, or Postgres rejects the
    /// insert into a `date` column.
    @Test func encodingProducesABareDay() throws {
        let reaction = SkinReaction(
            userID: UUID(),
            occurredOn: PostgresDay.formatter.date(from: "2026-03-09") ?? .now,
            severity: .mild
        )
        let json = String(decoding: try JSONEncoder().encode(reaction), as: UTF8.self)

        #expect(json.contains("\"occurred_on\":\"2026-03-09\""))
        #expect(!json.contains("T00:00"))
    }

    @Test func roundTripPreservesTheDay() throws {
        let original = ProductEmpty(
            userID: UUID(),
            productID: nil,
            productName: "Serum",
            brand: "Brand",
            finishedOn: PostgresDay.formatter.date(from: "2026-11-30") ?? .now
        )
        let restored = try decode(ProductEmpty.self, String(decoding: try JSONEncoder().encode(original), as: UTF8.self))

        #expect(PostgresDay.string(from: restored.finishedOn) == "2026-11-30")
    }
}
