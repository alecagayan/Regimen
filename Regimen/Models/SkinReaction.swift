//
//  SkinReaction.swift
//  Regimen
//

import Foundation

enum ReactionSeverity: String, Codable, CaseIterable, Identifiable, Hashable {
    case mild = "mild"
    case moderate = "moderate"
    case severe = "severe"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mild: "A bit off"
        case .moderate: "Reacting"
        case .severe: "Bad reaction"
        }
    }

    var detail: String {
        switch self {
        case .mild: "Slight redness or tightness"
        case .moderate: "Visible irritation or stinging"
        case .severe: "Painful, swollen, or breaking out badly"
        }
    }
}

/// A day the user's skin reacted badly.
///
/// The app already knows what's in the cabinet and when each product was
/// opened, and the trend chart already marks those start dates. What it
/// couldn't do was join the two: "my skin went wrong on this day" was
/// nowhere in the data, so nothing could point at what had changed shortly
/// before. One row per day, so marking the same day twice updates rather
/// than accumulating.
struct SkinReaction: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    var occurredOn: Date
    var severity: ReactionSeverity
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case occurredOn = "occurred_on"
        case severity
        case note
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        occurredOn: Date = .now,
        severity: ReactionSeverity = .mild,
        note: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.occurredOn = occurredOn
        self.severity = severity
        self.note = note
    }

    /// `occurred_on` is a Postgres `date`, which arrives as "2026-09-15"
    /// and cannot be decoded by the default date strategy -- see
    /// `PostgresDay`. Without this the whole reactions fetch fails.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        occurredOn = try PostgresDay.decode(from: container, forKey: .occurredOn)
        severity = try container.decodeIfPresent(ReactionSeverity.self, forKey: .severity) ?? .mild
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(PostgresDay.string(from: occurredOn), forKey: .occurredOn)
        try container.encode(severity, forKey: .severity)
        try container.encodeIfPresent(note, forKey: .note)
    }
}

/// A finished bottle, kept after the product itself may be gone.
struct ProductEmpty: Identifiable, Codable, Hashable {
    var id: UUID
    var userID: UUID
    /// Nullable on purpose: finishing a bottle is worth remembering even
    /// after the product is deleted from the cabinet.
    var productID: UUID?
    var productName: String
    var brand: String
    var finishedOn: Date
    var wouldRepurchase: Bool?
    var rating: Int?
    var note: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case productID = "product_id"
        case productName = "product_name"
        case brand
        case finishedOn = "finished_on"
        case wouldRepurchase = "would_repurchase"
        case rating
        case note
    }

    init(
        id: UUID = UUID(),
        userID: UUID,
        productID: UUID?,
        productName: String,
        brand: String,
        finishedOn: Date = .now,
        wouldRepurchase: Bool? = nil,
        rating: Int? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.userID = userID
        self.productID = productID
        self.productName = productName
        self.brand = brand
        self.finishedOn = finishedOn
        self.wouldRepurchase = wouldRepurchase
        self.rating = rating
        self.note = note
    }

    /// Same `date`-column hazard as `SkinReaction.occurredOn`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userID = try container.decode(UUID.self, forKey: .userID)
        productID = try container.decodeIfPresent(UUID.self, forKey: .productID)
        productName = try container.decode(String.self, forKey: .productName)
        brand = try container.decodeIfPresent(String.self, forKey: .brand) ?? ""
        finishedOn = try PostgresDay.decode(from: container, forKey: .finishedOn)
        wouldRepurchase = try container.decodeIfPresent(Bool.self, forKey: .wouldRepurchase)
        rating = try container.decodeIfPresent(Int.self, forKey: .rating)
        note = try container.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encodeIfPresent(productID, forKey: .productID)
        try container.encode(productName, forKey: .productName)
        try container.encode(brand, forKey: .brand)
        try container.encode(PostgresDay.string(from: finishedOn), forKey: .finishedOn)
        try container.encodeIfPresent(wouldRepurchase, forKey: .wouldRepurchase)
        try container.encodeIfPresent(rating, forKey: .rating)
        try container.encodeIfPresent(note, forKey: .note)
    }
}
